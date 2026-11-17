import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.auth import get_current_user_id
from app.routers.settlements import (
    get_post_settlement_account,
    get_my_settlement,
    mark_settlement_sent,
)


HOST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
PARTICIPANT_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
OTHER_USER_ID = UUID("33333333-3333-3333-3333-333333333333")
POST_ID = 10
SETTLEMENT_ID = 20
CREATED_AT = datetime(2026, 11, 16, tzinfo=timezone.utc)


def post_access_row(status="CLOSED", author_id=HOST_USER_ID, is_participant=True):
    return {
        "id": POST_ID,
        "author_id": author_id,
        "status": status,
        "is_participant": is_participant,
    }


def account_snapshot_row(account_number="000123456789"):
    return {
        "bank_name": "KakaoBank",
        "account_number": account_number,
        "account_holder_name": "Hong Gil-dong",
        "registered_at": CREATED_AT,
    }


def settlement_row(
    payment_status="UNPAID",
    post_status="CLOSED",
    settlement_account_confirmed=True,
):
    return {
        "id": SETTLEMENT_ID,
        "participation_id": 30,
        "amount": 3816,
        "payment_status": payment_status,
        "sent_at": None,
        "confirmed_at": None,
        "created_at": CREATED_AT,
        "post_status": post_status,
        "settlement_account_confirmed": settlement_account_confirmed,
    }


class FakeCursor:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


class SettlementAccountAccessTest(unittest.TestCase):
    def test_my_settlement_includes_final_quantity(self):
        connection = FakeConnection(
            [
                {
                    "id": SETTLEMENT_ID,
                    "participation_id": 30,
                    "quantity": 4,
                    "pickup_completed_at": CREATED_AT,
                    "amount": 3816,
                    "payment_status": "UNPAID",
                    "sent_at": None,
                    "confirmed_at": None,
                    "created_at": CREATED_AT,
                }
            ]
        )

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            result = get_my_settlement(POST_ID, PARTICIPANT_USER_ID)

        self.assertEqual(result["data"].quantity, 4)
        self.assertEqual(result["data"].pickup_completed_at, CREATED_AT)
        self.assertIn("p.quantity", connection.cursor_instance.calls[0][0])

    def call_account(self, rows, user_id):
        connection = FakeConnection(rows)
        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            result = get_post_settlement_account(POST_ID, user_id)
        return result, connection

    def test_participant_can_view_confirmed_account(self):
        result, _ = self.call_account(
            [post_access_row(is_participant=True), account_snapshot_row()],
            PARTICIPANT_USER_ID,
        )

        self.assertEqual(result["data"].account_number, "000123456789")
        self.assertNotIn(
            "user_id",
            type(result["data"]).model_fields,
        )

    def test_unauthenticated_account_query_is_rejected(self):
        with self.assertRaises(HTTPException) as context:
            get_current_user_id(None)

        self.assertEqual(context.exception.status_code, 401)
        self.assertEqual(context.exception.code, "AUTH_REQUIRED")

    def test_post_author_can_view_confirmed_account(self):
        result, _ = self.call_account(
            [post_access_row(is_participant=False), account_snapshot_row()],
            HOST_USER_ID,
        )

        self.assertEqual(result["data"].bank_name, "KakaoBank")

    def test_non_participant_is_rejected(self):
        connection = FakeConnection(
            [post_access_row(author_id=HOST_USER_ID, is_participant=False)]
        )

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                get_post_settlement_account(POST_ID, OTHER_USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "POST_PARTICIPATION_REQUIRED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_recruiting_and_cancelled_posts_hide_account(self):
        for status in ("RECRUITING", "CANCELLED"):
            connection = FakeConnection([post_access_row(status=status)])

            with patch(
                "app.routers.settlements.get_connection",
                return_value=connection,
            ):
                with self.assertRaises(HTTPException) as context:
                    get_post_settlement_account(POST_ID, PARTICIPANT_USER_ID)

            self.assertEqual(
                context.exception.code,
                "SETTLEMENT_ACCOUNT_POST_NOT_CLOSED",
            )
            self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_unconfirmed_account_returns_distinct_conflict(self):
        with self.assertRaises(HTTPException) as context:
            self.call_account(
                [post_access_row(is_participant=True), None],
                PARTICIPANT_USER_ID,
            )

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "SETTLEMENT_ACCOUNT_NOT_FIXED")

    def test_non_owner_settlement_cannot_be_marked_sent(self):
        connection = FakeConnection([None])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                mark_settlement_sent(SETTLEMENT_ID, OTHER_USER_ID)

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "SETTLEMENT_NOT_FOUND")

    def test_sent_is_rejected_without_confirmed_account(self):
        connection = FakeConnection(
            [settlement_row(settlement_account_confirmed=False)]
        )

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                mark_settlement_sent(SETTLEMENT_ID, PARTICIPANT_USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "SETTLEMENT_ACCOUNT_NOT_FIXED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_sent_is_rejected_for_recruiting_or_cancelled_post(self):
        for status in ("RECRUITING", "CANCELLED"):
            connection = FakeConnection([settlement_row(post_status=status)])

            with patch(
                "app.routers.settlements.get_connection",
                return_value=connection,
            ):
                with self.assertRaises(HTTPException) as context:
                    mark_settlement_sent(SETTLEMENT_ID, PARTICIPANT_USER_ID)

            self.assertEqual(
                context.exception.code,
                "SETTLEMENT_ACCOUNT_POST_NOT_CLOSED",
            )

    def test_sent_succeeds_with_confirmed_account(self):
        updated = settlement_row(payment_status="SENT")
        updated["sent_at"] = CREATED_AT
        connection = FakeConnection([settlement_row(), updated])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            result = mark_settlement_sent(SETTLEMENT_ID, PARTICIPANT_USER_ID)

        self.assertEqual(result["data"].payment_status, "SENT")
        self.assertEqual(len(connection.cursor_instance.calls), 2)
        self.assertIn("FOR UPDATE OF s, post", connection.cursor_instance.calls[0][0])

    def test_confirmed_settlement_cannot_regress_to_sent(self):
        connection = FakeConnection(
            [settlement_row(payment_status="CONFIRMED")]
        )

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                mark_settlement_sent(SETTLEMENT_ID, PARTICIPANT_USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "SETTLEMENT_NOT_UNPAID")
        self.assertEqual(len(connection.cursor_instance.calls), 1)


if __name__ == "__main__":
    unittest.main()
