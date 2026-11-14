import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException
from psycopg.errors import UniqueViolation
from pydantic import ValidationError

from app.routers.users import update_me
from app.schemas.users import UserUpdateRequest


USER_ID = UUID("11111111-1111-1111-1111-111111111111")


class FakeCursor:
    def __init__(self, row=None, error=None):
        self.row = row
        self.error = error
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.error is not None:
            raise self.error

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, row=None, error=None):
        self.cursor_instance = FakeCursor(row, error)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def user_row(room_number="717-1"):
    return {
        "id": USER_ID,
        "room_number": room_number,
        "dorm_verified": False,
        "dorm_verified_at": None,
        "created_at": datetime(2026, 11, 15, tzinfo=timezone.utc),
    }


class UserUpdateTest(unittest.TestCase):
    def test_user_can_register_own_room_number(self):
        connection = FakeConnection(row=user_row())

        with patch("app.routers.users.get_connection", return_value=connection):
            result = update_me(UserUpdateRequest(room_number="717-1"), USER_ID)

        self.assertEqual(result["data"].room_number, "717-1")
        self.assertEqual(
            connection.cursor_instance.calls[0][1],
            ("717-1", USER_ID),
        )

    def test_duplicate_room_number_returns_conflict(self):
        connection = FakeConnection(error=UniqueViolation("duplicate room number"))

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                update_me(UserUpdateRequest(room_number="717-1"), USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(
            context.exception.code,
            "ROOM_NUMBER_ALREADY_REGISTERED",
        )

    def test_invalid_room_number_is_rejected(self):
        with self.assertRaises(ValidationError):
            UserUpdateRequest(room_number="room-1")

    def test_missing_profile_returns_not_found(self):
        connection = FakeConnection(row=None)

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                update_me(UserUpdateRequest(room_number="717-1"), USER_ID)

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "USER_PROFILE_NOT_FOUND")


if __name__ == "__main__":
    unittest.main()
