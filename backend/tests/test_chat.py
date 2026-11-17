import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import BackgroundTasks, HTTPException, WebSocketDisconnect
from pydantic import ValidationError

from app.routers.chat import (
    ConnectionManager,
    create_direct_chat,
    get_chat_rooms,
    get_post_chat,
    get_room_messages,
    send_chat_message,
    websocket_chat,
)
from app.schemas.chat import ChatMessageCreateRequest


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


class FakeWebSocket:
    def __init__(self, headers=None):
        self.headers = headers or {}
        self.accepted = False
        self.closed_code = None
        self.sent = []

    async def accept(self):
        self.accepted = True

    async def close(self, code=None):
        self.closed_code = code

    async def receive(self):
        raise WebSocketDisconnect()

    async def send_json(self, message):
        self.sent.append(message)


def verified_user():
    return {"room_number": "717-1", "dorm_verified": True}


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


def accessible_room(post_status="RECRUITING", group_access=True, dm_access=False):
    return {
        "id": 100,
        "room_type": "GROUP",
        "post_id": 10,
        "post_status": post_status,
        "group_access": group_access,
        "dm_access": dm_access,
    }


def message_row(message_id=99, body="안녕하세요"):
    return {
        "id": message_id,
        "sender_id": CURRENT_USER_ID,
        "sender_room_number": "717-1",
        "message_type": "USER",
        "body": body,
        "created_at": ROOM_CREATED_AT,
    }


class ChatRoomTest(unittest.TestCase):
    def test_message_is_saved_for_authorized_user(self):
        connection = FakeConnection(
            fetchone_rows=[
                verified_user(),
                accessible_room(),
                message_row(),
            ]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = send_chat_message(
                100,
                ChatMessageCreateRequest(body="  안녕하세요  "),
                BackgroundTasks(),
                CURRENT_USER_ID,
            )

        self.assertEqual(result["data"].body, "안녕하세요")
        self.assertEqual(result["data"].sender_id, CURRENT_USER_ID)
        self.assertEqual(result["data"].sender_room_number, "717-1")
        query, params = connection.cursor_instance.calls[-1]
        self.assertIn("message_type", query)
        self.assertIn("'USER'", query)
        self.assertEqual(params, (100, CURRENT_USER_ID, "안녕하세요"))

    def test_non_participant_cannot_send_message(self):
        connection = FakeConnection(
            fetchone_rows=[verified_user(), accessible_room(group_access=False)]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                send_chat_message(
                    100,
                    ChatMessageCreateRequest(body="메시지"),
                    BackgroundTasks(),
                    CURRENT_USER_ID,
                )

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.code, "CHAT_ACCESS_FORBIDDEN")

    def test_blank_and_oversized_message_are_rejected(self):
        with self.assertRaises(ValidationError):
            ChatMessageCreateRequest(body="   ")
        with self.assertRaises(ValidationError):
            ChatMessageCreateRequest(body="x" * 2001)

    def test_completed_group_chat_is_read_only(self):
        connection = FakeConnection(
            fetchone_rows=[verified_user(), accessible_room("COMPLETED")]
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                send_chat_message(
                    100,
                    ChatMessageCreateRequest(body="메시지"),
                    BackgroundTasks(),
                    CURRENT_USER_ID,
                )

        self.assertEqual(context.exception.status_code, 409)
        self.assertEqual(context.exception.code, "CHAT_ROOM_READ_ONLY")

    def test_messages_use_before_id_pagination_and_latest_first(self):
        connection = FakeConnection(
            fetchone_rows=[verified_user(), accessible_room()],
            fetchall_rows=[message_row(99, "두 번째"), message_row(98, "첫 번째")],
        )

        with patch("app.routers.chat.get_connection", return_value=connection):
            result = get_room_messages(
                100,
                before_id=100,
                limit=50,
                current_user_id=CURRENT_USER_ID,
            )

        self.assertEqual([message.id for message in result["data"]], [99, 98])
        query, params = connection.cursor_instance.calls[-1]
        self.assertIn("m.id < %s", query)
        self.assertEqual(params, (100, 100, 100, 50))

    def test_db_failure_does_not_schedule_websocket_delivery(self):
        class FailingCursor(FakeCursor):
            def execute(self, query, params=None):
                super().execute(query, params)
                if "INSERT INTO public.chat_messages" in query:
                    raise RuntimeError("database failure")

        class FailingConnection(FakeConnection):
            def __init__(self):
                self.cursor_instance = FailingCursor(
                    [verified_user(), accessible_room()]
                )

        background_tasks = BackgroundTasks()
        connection = FailingConnection()

        with patch("app.routers.chat.get_connection", return_value=connection):
            with self.assertRaises(RuntimeError):
                send_chat_message(
                    100,
                    ChatMessageCreateRequest(body="메시지"),
                    background_tasks,
                    CURRENT_USER_ID,
                )

        self.assertEqual(background_tasks.tasks, [])

    def test_websocket_connects_and_disconnects_cleanly(self):
        websocket = FakeWebSocket({"authorization": "Bearer access-token"})
        connection = FakeConnection(
            fetchone_rows=[verified_user(), accessible_room()]
        )
        manager = ConnectionManager()

        with patch("app.routers.chat.get_current_user_id", return_value=CURRENT_USER_ID), patch(
            "app.routers.chat.get_connection", return_value=connection
        ), patch("app.routers.chat.connection_manager", manager):
            import asyncio

            asyncio.run(websocket_chat(websocket, 100))

        self.assertTrue(websocket.accepted)
        self.assertIsNone(websocket.closed_code)
        self.assertEqual(manager._connections, {})

    def test_websocket_rejects_user_without_room_access(self):
        websocket = FakeWebSocket({"authorization": "Bearer access-token"})
        connection = FakeConnection(
            fetchone_rows=[verified_user(), accessible_room(group_access=False)]
        )

        with patch("app.routers.chat.get_current_user_id", return_value=CURRENT_USER_ID), patch(
            "app.routers.chat.get_connection", return_value=connection
        ):
            import asyncio

            asyncio.run(websocket_chat(websocket, 100))

        self.assertFalse(websocket.accepted)
        self.assertEqual(websocket.closed_code, 1008)

    def test_websocket_broadcast_is_limited_to_one_room(self):
        async def run_test():
            manager = ConnectionManager()
            first_room = FakeWebSocket()
            other_room = FakeWebSocket()
            await manager.connect(100, CURRENT_USER_ID, first_room)
            await manager.connect(200, TARGET_USER_ID, other_room)

            with patch("app.routers.chat._has_chat_access", return_value=True):
                await manager.broadcast(100, {"data": {"body": "안녕하세요"}})

            self.assertEqual(first_room.sent, [{"data": {"body": "안녕하세요"}}])
            self.assertEqual(other_room.sent, [])

        import asyncio

        asyncio.run(run_test())

    def test_websocket_disconnect_removes_connection(self):
        async def run_test():
            manager = ConnectionManager()
            websocket = FakeWebSocket()
            await manager.connect(100, CURRENT_USER_ID, websocket)
            await manager.disconnect(100, websocket)
            self.assertEqual(manager._connections, {})

        import asyncio

        asyncio.run(run_test())

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
