import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from threading import Lock
from unittest.mock import patch
from uuid import UUID

import psycopg
from fastapi import HTTPException

from app.routers.settlements import confirm_post_settlement_account


HOST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
OTHER_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
POST_ID = 10
REGISTERED_AT = datetime(2026, 11, 16, tzinfo=timezone.utc)


def post_row(status="CLOSED", author_id=HOST_USER_ID):
    return {"id": POST_ID, "author_id": author_id, "status": status}


def account_row(account_number="000123456789"):
    return {
        "bank_name": "KakaoBank",
        "account_number": account_number,
        "account_holder_name": "Hong Gil-dong",
    }


def snapshot_row():
    return {"post_id": POST_ID, "registered_at": REGISTERED_AT}


class FakeCursor:
    def __init__(self, rows, error=None):
        self.rows = list(rows)
        self.error = error
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.error is not None and query.lstrip().startswith("INSERT"):
            raise self.error

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class FakeConnection:
    def __init__(self, rows, error=None):
        self.cursor_instance = FakeCursor(rows, error)
        self.rolled_back = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.rolled_back = exc_type is not None
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


class ConcurrentState:
    def __init__(self):
        self.post_lock = Lock()
        self.snapshot_exists = False

    def connection(self):
        return ConcurrentConnection(self)


class ConcurrentConnection:
    def __init__(self, state):
        self.state = state
        self.cursor_instance = ConcurrentCursor(state)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if self.cursor_instance.post_lock_acquired:
            self.state.post_lock.release()
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


class ConcurrentCursor:
    def __init__(self, state):
        self.state = state
        self.pending_row = None
        self.post_lock_acquired = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        if "FROM public.posts" in query:
            self.state.post_lock.acquire()
            self.post_lock_acquired = True
            self.pending_row = post_row()
        elif "FROM dormn_private.user_settlement_accounts" in query:
            self.pending_row = account_row()
        elif "INSERT INTO dormn_private.post_settlement_accounts" in query:
            if self.state.snapshot_exists:
                self.pending_row = None
            else:
                self.state.snapshot_exists = True
                self.pending_row = snapshot_row()

    def fetchone(self):
        row = self.pending_row
        self.pending_row = None
        return row


class SettlementAccountConfirmationTest(unittest.TestCase):
    def test_host_can_confirm_closed_post_account(self):
        connection = FakeConnection([post_row(), account_row(), snapshot_row()])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            result = confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(result["data"].post_id, POST_ID)
        self.assertTrue(result["data"].account_confirmed)
        self.assertEqual(result["data"].registered_at, REGISTERED_AT)
        insert_query, insert_params = connection.cursor_instance.calls[2]
        self.assertIn("ON CONFLICT (post_id) DO NOTHING", insert_query)
        self.assertEqual(
            insert_params,
            (POST_ID, "KakaoBank", "000123456789", "Hong Gil-dong"),
        )
        self.assertNotIn("account_number", type(result["data"]).model_fields)

    def test_missing_user_account_is_rejected(self):
        connection = FakeConnection([post_row(), None])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(
            context.exception.code,
            "SETTLEMENT_ACCOUNT_NOT_REGISTERED",
        )
        self.assertEqual(len(connection.cursor_instance.calls), 2)

    def test_recruiting_post_is_rejected(self):
        connection = FakeConnection([post_row(status="RECRUITING")])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.code, "SETTLEMENT_ACCOUNT_POST_NOT_CLOSED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_cancelled_post_is_rejected(self):
        connection = FakeConnection([post_row(status="CANCELLED")])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.code, "SETTLEMENT_ACCOUNT_POST_NOT_CLOSED")

    def test_non_host_cannot_confirm_account(self):
        connection = FakeConnection([post_row(author_id=OTHER_USER_ID)])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "POST_AUTHOR_REQUIRED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_missing_post_is_rejected(self):
        connection = FakeConnection([None])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.status_code, 404)
        self.assertEqual(context.exception.code, "POST_NOT_FOUND")

    def test_existing_snapshot_cannot_be_overwritten(self):
        connection = FakeConnection([post_row(), account_row(), None])

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(
            context.exception.code,
            "SETTLEMENT_ACCOUNT_ALREADY_FIXED",
        )

    def test_database_error_rolls_back_and_hides_details(self):
        connection = FakeConnection(
            [post_row(), account_row()],
            error=psycopg.Error("account_number=secret"),
        )

        with patch(
            "app.routers.settlements.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                confirm_post_settlement_account(POST_ID, HOST_USER_ID)

        self.assertTrue(connection.rolled_back)
        self.assertEqual(context.exception.status_code, 503)
        self.assertNotIn("secret", context.exception.message)

    def test_concurrent_confirmation_creates_one_snapshot(self):
        state = ConcurrentState()

        def confirm():
            try:
                return confirm_post_settlement_account(POST_ID, HOST_USER_ID)
            except HTTPException as exc:
                return exc

        with patch(
            "app.routers.settlements.get_connection",
            side_effect=state.connection,
        ):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(lambda _: confirm(), range(2)))

        successes = [result for result in results if isinstance(result, dict)]
        conflicts = [
            result
            for result in results
            if isinstance(result, HTTPException)
            and result.code == "SETTLEMENT_ACCOUNT_ALREADY_FIXED"
        ]
        self.assertEqual(len(successes), 1)
        self.assertEqual(len(conflicts), 1)
        self.assertTrue(state.snapshot_exists)


if __name__ == "__main__":
    unittest.main()
