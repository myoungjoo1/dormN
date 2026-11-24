import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

import psycopg
from fastapi import HTTPException

from app.routers.users import complete_dorm_verification, get_me


USER_ID = UUID("11111111-1111-1111-1111-111111111111")
CREATED_AT = datetime(2026, 11, 15, tzinfo=timezone.utc)


def user_row(
    *,
    room_number="717-1",
    dorm_verified=False,
    location_status="COMPLETED",
):
    return {
        "id": USER_ID,
        "room_number": room_number,
        "dorm_verified": dorm_verified,
        "dorm_verified_at": None,
        "created_at": CREATED_AT,
        "location_status": location_status,
    }


def verified_user_row():
    return {
        "id": USER_ID,
        "room_number": "717-1",
        "dorm_verified": True,
        "dorm_verified_at": datetime(2026, 11, 24, tzinfo=timezone.utc),
        "created_at": CREATED_AT,
    }


class FakeCursor:
    def __init__(self, rows, fail_on_execute=None):
        self.rows = list(rows)
        self.fail_on_execute = fail_on_execute
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.fail_on_execute == len(self.calls):
            raise psycopg.Error("database failure")

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class FakeConnection:
    def __init__(self, rows, fail_on_execute=None):
        self.cursor_instance = FakeCursor(rows, fail_on_execute)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


class DormVerificationTest(unittest.TestCase):
    def test_room_and_completed_gps_verification_set_dorm_verified(self):
        connection = FakeConnection(
            [
                user_row(),
                {
                    **user_row(),
                    "dorm_verified": True,
                    "dorm_verified_at": datetime(
                        2026,
                        11,
                        24,
                        tzinfo=timezone.utc,
                    ),
                },
            ]
        )

        with patch("app.routers.users.get_connection", return_value=connection):
            result = complete_dorm_verification(USER_ID)

        self.assertTrue(result["data"].dorm_verified)
        queries = [query for query, _ in connection.cursor_instance.calls]
        self.assertTrue(any("FOR UPDATE OF u" in query for query in queries))
        self.assertTrue(any("SET dorm_verified = TRUE" in query for query in queries))
        self.assertTrue(
            all(
                params == (USER_ID,)
                for _, params in connection.cursor_instance.calls
            )
        )

    def test_room_number_missing_cannot_complete_verification(self):
        connection = FakeConnection([user_row(room_number=None)])

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                complete_dorm_verification(USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "ROOM_NUMBER_REQUIRED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_incomplete_gps_verification_cannot_complete(self):
        connection = FakeConnection([user_row(location_status="IN_PROGRESS")])

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                complete_dorm_verification(USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "GPS_VERIFICATION_REQUIRED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_repeated_completion_request_is_idempotent(self):
        connection = FakeConnection([verified_user_row()])

        with patch("app.routers.users.get_connection", return_value=connection):
            result = complete_dorm_verification(USER_ID)

        self.assertTrue(result["data"].dorm_verified)
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_database_failure_does_not_return_completion(self):
        connection = FakeConnection([user_row()], fail_on_execute=2)

        with patch("app.routers.users.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                complete_dorm_verification(USER_ID)

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.code, "DORM_VERIFICATION_UNAVAILABLE")

    def test_get_me_returns_updated_dorm_verified_state(self):
        connection = FakeConnection([verified_user_row()])

        with patch("app.routers.users.get_connection", return_value=connection):
            result = get_me(USER_ID)

        self.assertTrue(result["data"].dorm_verified)
        self.assertEqual(
            connection.cursor_instance.calls[0][1],
            (USER_ID,),
        )


if __name__ == "__main__":
    unittest.main()
