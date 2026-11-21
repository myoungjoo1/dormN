import unittest
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.participations import get_my_participation


USER_ID = UUID("11111111-1111-1111-1111-111111111111")


class FakeCursor:
    def __init__(self, row):
        self.row = row
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, row):
        self.cursor_instance = FakeCursor(row)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


class MyParticipationTest(unittest.TestCase):
    def call_endpoint(self, row):
        connection = FakeConnection(row)
        with patch(
            "app.routers.participations.get_connection",
            return_value=connection,
        ):
            result = get_my_participation(10, USER_ID)
        return result["data"], connection

    def test_returns_joined_participation(self):
        participation, connection = self.call_endpoint(
            {
                "is_joined": True,
                "participation_id": 55,
                "quantity": 4,
            }
        )

        self.assertTrue(participation.is_joined)
        self.assertEqual(participation.participation_id, 55)
        self.assertEqual(participation.quantity, 4)
        self.assertEqual(connection.cursor_instance.calls[0][1], (USER_ID, 10))

    def test_returns_not_joined_without_private_participation_data(self):
        participation, _ = self.call_endpoint(
            {
                "is_joined": False,
                "participation_id": None,
                "quantity": None,
            }
        )

        self.assertFalse(participation.is_joined)
        self.assertIsNone(participation.participation_id)
        self.assertIsNone(participation.quantity)

    def test_missing_post_returns_not_found(self):
        with self.assertRaises(HTTPException) as context:
            self.call_endpoint(None)

        self.assertEqual(context.exception.code, "POST_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
