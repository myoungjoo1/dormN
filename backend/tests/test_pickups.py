import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import BackgroundTasks, HTTPException

from app.routers.pickups import complete_pickup, get_post_pickups


HOST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
PARTICIPANT_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
OTHER_USER_ID = UUID("33333333-3333-3333-3333-333333333333")
POST_ID = 10
PARTICIPATION_ID = 20
PICKED_UP_AT = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)


class FakeCursor:
    def __init__(self, fetchone_rows=None, fetchall_rows=None):
        self.fetchone_rows = list(fetchone_rows or [])
        self.fetchall_rows = list(fetchall_rows or [])
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params=None):
        self.calls.append((query, params))

    def fetchone(self):
        return self.fetchone_rows.pop(0) if self.fetchone_rows else None

    def fetchall(self):
        return self.fetchall_rows


class FakeConnection:
    def __init__(self, fetchone_rows=None, fetchall_rows=None):
        self.cursor_instance = FakeCursor(fetchone_rows, fetchall_rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def participation_row(
    *,
    user_id=PARTICIPANT_USER_ID,
    post_status="PICKUP",
    pickup_completed_at=None,
):
    return {
        "participation_id": PARTICIPATION_ID,
        "post_id": POST_ID,
        "user_id": user_id,
        "pickup_completed_at": pickup_completed_at,
        "author_id": HOST_USER_ID,
        "post_status": post_status,
    }


def pickup_event():
    return {
        "room_id": 50,
        "message": {
            "id": 7,
            "sender_id": None,
            "sender_room_number": None,
            "message_type": "SYSTEM",
            "body": "거래가 완료되었습니다.",
            "created_at": PICKED_UP_AT,
        },
    }


class PickupTest(unittest.TestCase):
    def test_participant_can_complete_own_pickup(self):
        connection = FakeConnection(
            fetchone_rows=[
                participation_row(),
                {"pickup_completed_at": PICKED_UP_AT},
                {"pending_count": 1},
            ]
        )

        with patch("app.routers.pickups.get_connection", return_value=connection):
            result = complete_pickup(
                PARTICIPATION_ID,
                BackgroundTasks(),
                PARTICIPANT_USER_ID,
            )

        self.assertEqual(result["data"].participation_id, PARTICIPATION_ID)
        self.assertEqual(result["data"].post_status, "PICKUP")
        self.assertEqual(result["data"].pickup_completed_at, PICKED_UP_AT)

    def test_other_participant_cannot_complete_pickup(self):
        connection = FakeConnection(
            fetchone_rows=[participation_row(user_id=OTHER_USER_ID)]
        )

        with patch("app.routers.pickups.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                complete_pickup(
                    PARTICIPATION_ID,
                    BackgroundTasks(),
                    PARTICIPANT_USER_ID,
                )

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "PARTICIPATION_OWNER_REQUIRED")
        self.assertEqual(len(connection.cursor_instance.calls), 1)

    def test_duplicate_pickup_keeps_existing_timestamp(self):
        connection = FakeConnection(
            fetchone_rows=[
                participation_row(pickup_completed_at=PICKED_UP_AT),
                {"pending_count": 1},
            ]
        )

        with patch("app.routers.pickups.get_connection", return_value=connection):
            result = complete_pickup(
                PARTICIPATION_ID,
                BackgroundTasks(),
                PARTICIPANT_USER_ID,
            )

        self.assertEqual(result["data"].pickup_completed_at, PICKED_UP_AT)
        self.assertFalse(
            any(
                "UPDATE public.participations" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_last_pickup_completes_post_and_broadcasts_system_message(self):
        connection = FakeConnection(
            fetchone_rows=[
                participation_row(),
                {"pickup_completed_at": PICKED_UP_AT},
                {"pending_count": 0},
                {"status": "COMPLETED"},
            ]
        )
        background_tasks = BackgroundTasks()

        with patch(
            "app.routers.pickups.get_connection",
            return_value=connection,
        ), patch(
            "app.routers.pickups.create_group_system_message",
            return_value=pickup_event(),
        ) as create_message:
            result = complete_pickup(
                PARTICIPATION_ID,
                background_tasks,
                PARTICIPANT_USER_ID,
            )

        self.assertEqual(result["data"].post_status, "COMPLETED")
        create_message.assert_called_once_with(connection, POST_ID, "COMPLETED")
        self.assertEqual(len(background_tasks.tasks), 1)

    def test_host_can_view_pickup_status(self):
        connection = FakeConnection(
            fetchall_rows=[
                {
                    "author_id": HOST_USER_ID,
                    "participation_id": PARTICIPATION_ID,
                    "room_number": "717-2",
                    "quantity": 4,
                    "pickup_completed": True,
                    "pickup_completed_at": PICKED_UP_AT,
                }
            ]
        )

        with patch("app.routers.pickups.get_connection", return_value=connection):
            result = get_post_pickups(POST_ID, HOST_USER_ID)

        self.assertEqual(result["data"][0].participation_id, PARTICIPATION_ID)
        self.assertEqual(result["data"][0].room_number, "717-2")
        self.assertTrue(result["data"][0].pickup_completed)

    def test_non_host_cannot_view_pickup_status(self):
        connection = FakeConnection(
            fetchall_rows=[
                {
                    "author_id": HOST_USER_ID,
                    "participation_id": PARTICIPATION_ID,
                    "room_number": "717-2",
                    "quantity": 4,
                    "pickup_completed": False,
                    "pickup_completed_at": None,
                }
            ]
        )

        with patch("app.routers.pickups.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                get_post_pickups(POST_ID, OTHER_USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "POST_AUTHOR_REQUIRED")


if __name__ == "__main__":
    unittest.main()
