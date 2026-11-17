import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException

from app.routers.chat import create_direct_chat, get_chat_rooms, get_post_chat


CURRENT_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
TARGET_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
ROOM_CREATED_AT = datetime(2026, 11, 17, tzinfo=timezone.utc)


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


def verified_user():
    return {"dorm_verified": True}


def room_row(room_type="GROUP", post_id=10, product_name="햇반 24개"):
    return {
        "id": 100,
        "room_type": room_type,
        "post_id": post_id,
        "product_name": product_name,
        "dm_user_a": CURRENT_USER_ID,
        "dm_user_b": TARGET_USER_ID,
        "dm_room_a": "717-1",
        "dm_room_b": "717-2",
        "created_at": ROOM_CREATED_AT,
    }


class ChatRoomTest(unittest.TestCase):
    def test_direct_chat_is_created_with_two_members_in_one_flow(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                {
                    "id": TARGET_USER_ID,
                    "room_number": "717-2",
                    "dorm_verified": True,
                },
                {"id": 20, "created_at": ROOM_CREATED_AT},
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = create_direct_chat(TARGET_USER_ID, CURRENT_USER_ID)

        self.assertEqual(result["data"].id, 20)
        self.assertEqual(result["data"].room_type, "DM")
        self.assertEqual(result["data"].other_user_room_number, "717-2")
        self.assertTrue(
            any(
                "INSERT INTO public.chat_room_members" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_direct_chat_reuses_existing_room(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                {
                    "id": TARGET_USER_ID,
                    "room_number": "717-2",
                    "dorm_verified": True,
                },
                None,
                room_row("DM", None, None),
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = create_direct_chat(TARGET_USER_ID, CURRENT_USER_ID)

        self.assertEqual(result["data"].id, 100)
        self.assertFalse(
            any(
                "INSERT INTO public.chat_room_members" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_self_direct_chat_is_rejected(self):
        with self.assertRaises(HTTPException) as context:
            create_direct_chat(CURRENT_USER_ID, CURRENT_USER_ID)

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "CHAT_SELF_DM_NOT_ALLOWED")

    def test_unverified_user_cannot_use_chat(self):
        connection = FakeConnection(fetchone_rows=[{"dorm_verified": False}])

        with patch("app.routers.chat.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                create_direct_chat(TARGET_USER_ID, CURRENT_USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "DORM_VERIFICATION_REQUIRED")

    def test_group_chat_allows_post_author(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                {
                    "id": 10,
                    "author_id": CURRENT_USER_ID,
                    "product_name": "햇반 24개",
                    "can_access": True,
                },
                room_row(),
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = get_post_chat(10, CURRENT_USER_ID)

        self.assertEqual(result["data"].room_type, "GROUP")
        self.assertEqual(result["data"].product_name, "햇반 24개")
        self.assertTrue(
            any(
                "INSERT INTO public.chat_rooms" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_group_chat_allows_participant(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                {
                    "id": 10,
                    "author_id": TARGET_USER_ID,
                    "product_name": "햇반 24개",
                    "can_access": True,
                },
                room_row(),
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = get_post_chat(10, CURRENT_USER_ID)

        self.assertEqual(result["data"].product_name, "햇반 24개")

    def test_group_chat_rejects_non_participant(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                {
                    "id": 10,
                    "author_id": TARGET_USER_ID,
                    "product_name": "햇반 24개",
                    "can_access": False,
                },
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                get_post_chat(10, CURRENT_USER_ID)

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "CHAT_ACCESS_FORBIDDEN")

    def test_chat_room_list_contains_only_authorized_room_shapes(self):
        connection = FakeConnection(
            fetchone_rows=[verified_user()],
            fetchall_rows=[
                room_row(),
                room_row("DM", None, None),
            ],
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = get_chat_rooms(CURRENT_USER_ID)

        self.assertEqual(len(result["data"]), 2)
        self.assertEqual(result["data"][0].product_name, "햇반 24개")
        self.assertEqual(result["data"][1].other_user_room_number, "717-2")
        self.assertIn(
            "chat_room_members",
            connection.cursor_instance.calls[-1][0],
        )


if __name__ == "__main__":
    unittest.main()
