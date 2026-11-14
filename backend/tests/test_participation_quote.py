import unittest
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.participations import quote_participation
from app.schemas.participations import ParticipationCreateRequest


USER_ID = UUID("11111111-1111-1111-1111-111111111111")
AUTHOR_ID = UUID("22222222-2222-2222-2222-222222222222")


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


def post_row(**changes):
    row = {
        "id": 10,
        "author_id": AUTHOR_ID,
        "status": "RECRUITING",
        "total_price": 22900,
        "total_quantity": 24,
        "host_quantity": 4,
        "deadline_expired": False,
        "already_joined": False,
        "joined_quantity": 10,
    }
    row.update(changes)
    return row


class ParticipationQuoteTest(unittest.TestCase):
    def call_quote(self, row, quantity=4):
        connection = FakeConnection(row)
        with patch(
            "app.routers.participations.get_connection",
            return_value=connection,
        ):
            result = quote_participation(
                10,
                ParticipationCreateRequest(quantity=quantity),
                USER_ID,
            )
        return result["data"], connection

    def test_quote_returns_same_floor_amount_used_by_settlement(self):
        quote, connection = self.call_quote(post_row())

        self.assertEqual(quote.estimated_amount, 3816)
        self.assertEqual(quote.remaining_quantity_after_join, 6)
        self.assertEqual(connection.cursor_instance.calls[0][1], (USER_ID, 10))

    def test_missing_post_returns_not_found(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(None)

        self.assertEqual(context.exception.code, "POST_NOT_FOUND")

    def test_author_cannot_request_join_quote(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(post_row(author_id=USER_ID))

        self.assertEqual(context.exception.code, "POST_AUTHOR_CANNOT_JOIN")

    def test_closed_post_cannot_be_quoted(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(post_row(status="CLOSED"))

        self.assertEqual(context.exception.code, "POST_NOT_RECRUITING")

    def test_expired_post_cannot_be_quoted(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(post_row(deadline_expired=True))

        self.assertEqual(context.exception.code, "RECRUITMENT_DEADLINE_PASSED")

    def test_existing_participant_cannot_be_quoted_again(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(post_row(already_joined=True))

        self.assertEqual(context.exception.code, "PARTICIPATION_ALREADY_EXISTS")

    def test_quantity_cannot_exceed_remaining_quantity(self):
        with self.assertRaises(HTTPException) as context:
            self.call_quote(post_row(), quantity=11)

        self.assertEqual(context.exception.code, "INSUFFICIENT_QUANTITY")

    def test_direct_participation_cancellation_is_not_exposed(self):
        from app.main import app

        join_operations = app.openapi()["paths"]["/posts/{post_id}/join"]

        self.assertNotIn("delete", join_operations)


if __name__ == "__main__":
    unittest.main()
