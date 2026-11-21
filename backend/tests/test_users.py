import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException
import psycopg
from psycopg.errors import UniqueViolation
from pydantic import ValidationError

from app.routers.users import (
    get_settlement_account,
    search_users,
    update_me,
    upsert_settlement_account,
)
from app.schemas.users import (
    SettlementAccountRequest,
    UserSearchResponse,
    UserUpdateRequest,
)


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


class SearchCursor:
    def __init__(self, fetchone_rows, fetchall_rows):
        self.fetchone_rows = list(fetchone_rows)
        self.fetchall_rows = fetchall_rows
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))

    def fetchone(self):
        return self.fetchone_rows.pop(0)

    def fetchall(self):
        return self.fetchall_rows


class SearchConnection:
    def __init__(self, fetchone_rows, fetchall_rows):
        self.cursor_instance = SearchCursor(fetchone_rows, fetchall_rows)

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


def settlement_account_row(account_number="000123456789"):
    return {
        "bank_name": "KakaoBank",
        "account_number": account_number,
        "account_holder_name": "Hong Gil-dong",
        "updated_at": datetime(2026, 11, 16, tzinfo=timezone.utc),
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

    def test_unregistered_settlement_account_returns_null_data(self):
        connection = FakeConnection(row=None)

        with patch("app.routers.users.get_connection", return_value=connection):
            result = get_settlement_account(USER_ID)

        self.assertIsNone(result["data"])
        self.assertIn(
            "dormn_private.user_settlement_accounts",
            connection.cursor_instance.calls[0][0],
        )
        self.assertEqual(connection.cursor_instance.calls[0][1], (USER_ID,))

    def test_settlement_account_is_inserted_for_authenticated_user(self):
        connection = FakeConnection(row=settlement_account_row())
        account = SettlementAccountRequest(
            bank_name="  KakaoBank  ",
            account_number=" 000123456789 ",
            account_holder_name=" Hong Gil-dong ",
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            result = upsert_settlement_account(account, USER_ID)

        self.assertEqual(result["data"].account_number, "000123456789")
        query, params = connection.cursor_instance.calls[0]
        self.assertIn("ON CONFLICT (user_id) DO UPDATE", query)
        self.assertEqual(
            params,
            (USER_ID, "KakaoBank", "000123456789", "Hong Gil-dong"),
        )

    def test_existing_settlement_account_is_updated(self):
        connection = FakeConnection(row=settlement_account_row("00112233"))
        account = SettlementAccountRequest(
            bank_name="KakaoBank",
            account_number="00112233",
            account_holder_name="Hong Gil-dong",
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            result = upsert_settlement_account(account, USER_ID)

        self.assertEqual(result["data"].account_number, "00112233")
        query = connection.cursor_instance.calls[0][0]
        self.assertIn("updated_at = NOW()", query)
        self.assertNotIn("post_settlement_accounts", query)

    def test_account_request_rejects_blank_values(self):
        for field in ("bank_name", "account_number", "account_holder_name"):
            values = {
                "bank_name": "KakaoBank",
                "account_number": "00112233",
                "account_holder_name": "Hong Gil-dong",
            }
            values[field] = "   "
            with self.assertRaises(ValidationError):
                SettlementAccountRequest(**values)

    def test_account_request_does_not_accept_user_id(self):
        account = SettlementAccountRequest.model_validate(
            {
                "user_id": "22222222-2222-2222-2222-222222222222",
                "bank_name": "KakaoBank",
                "account_number": "000123456789",
                "account_holder_name": "Hong Gil-dong",
            }
        )

        self.assertNotIn("user_id", SettlementAccountRequest.model_fields)
        self.assertEqual(account.account_number, "000123456789")

        connection = FakeConnection(row=settlement_account_row())
        with patch("app.routers.users.get_connection", return_value=connection):
            upsert_settlement_account(account, USER_ID)

        self.assertEqual(connection.cursor_instance.calls[0][1][0], USER_ID)

    def test_account_query_uses_only_authenticated_user_id(self):
        connection = FakeConnection(row=settlement_account_row())

        with patch("app.routers.users.get_connection", return_value=connection):
            get_settlement_account(USER_ID)

        self.assertEqual(connection.cursor_instance.calls[0][1], (USER_ID,))

    def test_account_db_error_is_not_returned_to_client(self):
        connection = FakeConnection(error=psycopg.Error("account=secret"))
        account = SettlementAccountRequest(
            bank_name="KakaoBank",
            account_number="000123456789",
            account_holder_name="Hong Gil-dong",
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                upsert_settlement_account(account, USER_ID)

        self.assertEqual(context.exception.status_code, 503)
        self.assertNotIn("secret", context.exception.message)


class UserSearchTest(unittest.TestCase):
    def test_search_returns_only_verified_other_user_minimal_fields(self):
        target_id = UUID("22222222-2222-2222-2222-222222222222")
        connection = SearchConnection(
            fetchone_rows=[{"dorm_verified": True}],
            fetchall_rows=[{"user_id": target_id, "room_number": "717-2"}],
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            result = search_users("717-2", USER_ID)

        self.assertEqual(result["data"][0].user_id, target_id)
        self.assertEqual(result["data"][0].room_number, "717-2")
        self.assertEqual(
            set(UserSearchResponse.model_fields),
            {"user_id", "room_number"},
        )
        self.assertEqual(
            connection.cursor_instance.calls[1][1],
            ("717-2", USER_ID),
        )
        query = connection.cursor_instance.calls[1][0]
        self.assertIn("dorm_verified = TRUE", query)
        self.assertNotIn("account_number", query)

    def test_unverified_requester_cannot_search_users(self):
        connection = SearchConnection(
            fetchone_rows=[{"dorm_verified": False}],
            fetchall_rows=[],
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                search_users("717-2", USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(
            context.exception.code,
            "DORM_VERIFICATION_REQUIRED",
        )

    def test_search_excludes_requester_in_sql(self):
        connection = SearchConnection(
            fetchone_rows=[{"dorm_verified": True}],
            fetchall_rows=[],
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            search_users("717-1", USER_ID)

        query, params = connection.cursor_instance.calls[1]
        self.assertIn("id <> %s", query)
        self.assertEqual(params, ("717-1", USER_ID))


if __name__ == "__main__":
    unittest.main()
