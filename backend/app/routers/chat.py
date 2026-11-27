import asyncio
import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Query, WebSocket, WebSocketDisconnect, status
from fastapi.security import HTTPAuthorizationCredentials
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.chat import (
    ChatMessageCreateRequest,
    ChatMessageResponse,
    ChatRoomResponse,
)


router = APIRouter(tags=["chat"])
logger = logging.getLogger(__name__)
CHAT_MESSAGE_DELETE_WINDOW = timedelta(minutes=10)
DELETED_MESSAGE_BODY = "삭제된 메시지입니다."


class ConnectionManager:
    def __init__(self):
        self._connections: dict[int, dict[WebSocket, UUID]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, room_id: int, user_id: UUID, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self._connections.setdefault(room_id, {})[websocket] = user_id

    async def disconnect(self, room_id: int, websocket: WebSocket):
        async with self._lock:
            room_connections = self._connections.get(room_id)
            if room_connections is None:
                return

            room_connections.pop(websocket, None)
            if not room_connections:
                self._connections.pop(room_id, None)

    async def broadcast(self, room_id: int, message: dict):
        async with self._lock:
            connections = list(self._connections.get(room_id, {}).items())

        for websocket, user_id in connections:
            if not await asyncio.to_thread(
                _has_chat_access,
                room_id,
                user_id,
            ):
                await self.disconnect(room_id, websocket)
                continue

            try:
                await websocket.send_json(message)
            except Exception:
                logger.exception("WebSocket message delivery failed")
                await self.disconnect(room_id, websocket)


connection_manager = ConnectionManager()


def _require_verified_user(cursor, user_id: UUID):
    cursor.execute(
        """
        SELECT room_number, dorm_verified
        FROM public.users
        WHERE id = %s
        """,
        (user_id,),
    )
    user = cursor.fetchone()

    if user is None:
        raise ApiException(404, "USER_NOT_FOUND", "User not found")
    if not user["dorm_verified"]:
        raise ApiException(
            403,
            "DORM_VERIFICATION_REQUIRED",
            "Dorm verification is required to use chat",
        )

    return user


def _get_accessible_room(cursor, room_id: int, current_user_id: UUID):
    cursor.execute(
        """
        SELECT
            r.id,
            r.room_type,
            r.post_id,
            p.status AS post_status,
            (
                r.room_type = 'GROUP'
                AND (
                    p.author_id = %s
                    OR EXISTS (
                        SELECT 1
                        FROM public.participations AS part
                        WHERE part.post_id = r.post_id
                          AND part.user_id = %s
                    )
                )
            ) AS group_access,
            (
                r.room_type = 'DM'
                AND EXISTS (
                    SELECT 1
                    FROM public.chat_room_members AS member
                    WHERE member.room_id = r.id
                      AND member.user_id = %s
                )
            ) AS dm_access
        FROM public.chat_rooms AS r
        LEFT JOIN public.posts AS p ON p.id = r.post_id
        WHERE r.id = %s
        """,
        (current_user_id, current_user_id, current_user_id, room_id),
    )
    room = cursor.fetchone()

    if room is None:
        raise ApiException(404, "CHAT_ROOM_NOT_FOUND", "Chat room not found")

    if room["room_type"] == "GROUP" and not room["group_access"]:
        raise ApiException(
            403,
            "CHAT_ACCESS_FORBIDDEN",
            "Only the post author or participants can access this chat",
        )
    if room["room_type"] == "DM" and not room["dm_access"]:
        raise ApiException(
            403,
            "CHAT_ACCESS_FORBIDDEN",
            "Only direct chat members can access this chat",
        )

    return room


def _has_chat_access(room_id: int, user_id: UUID) -> bool:
    try:
        with get_connection() as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                _require_verified_user(cursor, user_id)
                _get_accessible_room(cursor, room_id, user_id)
        return True
    except ApiException:
        return False
    except Exception:
        logger.exception("WebSocket access check failed")
        return False


def _websocket_credentials(websocket: WebSocket) -> HTTPAuthorizationCredentials:
    authorization = websocket.headers.get("authorization")
    if authorization is None:
        raise ApiException(401, "AUTH_REQUIRED", "Authentication required")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise ApiException(401, "AUTH_REQUIRED", "Authentication required")

    return HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials=token.strip(),
    )


def _authorize_websocket(websocket: WebSocket, room_id: int) -> UUID:
    credentials = _websocket_credentials(websocket)
    current_user_id = get_current_user_id(credentials)

    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)
            _get_accessible_room(cursor, room_id, current_user_id)

    return current_user_id


def _room_response(row, current_user_id: UUID) -> ChatRoomResponse:
    other_user_id = None
    other_user_room_number = None

    if row["room_type"] == "DM":
        if row["dm_user_a"] == current_user_id:
            other_user_id = row["dm_user_b"]
            other_user_room_number = row["dm_room_b"]
        else:
            other_user_id = row["dm_user_a"]
            other_user_room_number = row["dm_room_a"]

    return ChatRoomResponse(
        id=row["id"],
        room_type=row["room_type"],
        post_id=row["post_id"],
        product_name=row["product_name"],
        other_user_id=other_user_id,
        other_user_room_number=other_user_room_number,
        created_at=row["created_at"],
    )


@router.post(
    "/chat/rooms/{room_id}/messages",
    response_model=ApiResponse[ChatMessageResponse],
    status_code=status.HTTP_201_CREATED,
)
def send_chat_message(
    room_id: int,
    message: ChatMessageCreateRequest,
    background_tasks: BackgroundTasks,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            current_user = _require_verified_user(cursor, current_user_id)
            room = _get_accessible_room(cursor, room_id, current_user_id)

            if room["room_type"] == "GROUP" and room["post_status"] in {
                "COMPLETED",
                "CANCELLED",
            }:
                raise ApiException(
                    409,
                    "CHAT_ROOM_READ_ONLY",
                    "This group chat is read-only",
                )

            cursor.execute(
                """
                INSERT INTO public.chat_messages (
                    room_id,
                    sender_id,
                    message_type,
                    body
                )
                VALUES (%s, %s, 'USER', %s)
                RETURNING id, sender_id, message_type, body, created_at, deleted_at
                """,
                (room_id, current_user_id, message.body),
            )
            row = cursor.fetchone()

    if row is None:
        raise ApiException(
            503,
            "CHAT_MESSAGE_UNAVAILABLE",
            "Message could not be saved",
        )

    response = ChatMessageResponse(
        id=row["id"],
        sender_id=row["sender_id"],
        sender_room_number=current_user["room_number"],
        message_type=row["message_type"],
        body=row["body"],
        created_at=row["created_at"],
    )

    background_tasks.add_task(
        connection_manager.broadcast,
        room_id,
        {"data": response.model_dump(mode="json")},
    )

    return {
        "data": response,
    }


@router.delete(
    "/chat/rooms/{room_id}/messages/{message_id}",
    response_model=ApiResponse[ChatMessageResponse],
)
def delete_chat_message(
    room_id: int,
    message_id: int,
    background_tasks: BackgroundTasks,
    current_user_id: UUID = Depends(get_current_user_id),
):
    newly_deleted = False
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)
            _get_accessible_room(cursor, room_id, current_user_id)

            cursor.execute(
                """
                SELECT
                    m.id,
                    m.sender_id,
                    u.room_number AS sender_room_number,
                    m.message_type,
                    m.body,
                    m.created_at,
                    m.deleted_at
                FROM public.chat_messages AS m
                LEFT JOIN public.users AS u ON u.id = m.sender_id
                WHERE m.id = %s
                  AND m.room_id = %s
                FOR UPDATE OF m
                """,
                (message_id, room_id),
            )
            row = cursor.fetchone()

            if row is None:
                raise ApiException(
                    404,
                    "CHAT_MESSAGE_NOT_FOUND",
                    "Chat message not found",
                )
            if row["message_type"] != "USER":
                raise ApiException(
                    409,
                    "SYSTEM_MESSAGE_DELETE_NOT_ALLOWED",
                    "System messages cannot be deleted",
                )
            if row["sender_id"] != current_user_id:
                raise ApiException(
                    403,
                    "CHAT_MESSAGE_DELETE_FORBIDDEN",
                    "Only the sender can delete this message",
                )

            if row["deleted_at"] is None:
                if datetime.now(timezone.utc) - row["created_at"] > CHAT_MESSAGE_DELETE_WINDOW:
                    raise ApiException(
                        409,
                        "MESSAGE_DELETE_WINDOW_EXPIRED",
                        "The message delete window has expired",
                    )

                cursor.execute(
                    """
                    UPDATE public.chat_messages
                    SET deleted_at = NOW()
                    WHERE id = %s
                    RETURNING deleted_at
                    """,
                    (message_id,),
                )
                updated = cursor.fetchone()
                row["deleted_at"] = updated["deleted_at"]
                newly_deleted = True

    response = ChatMessageResponse(
        id=row["id"],
        sender_id=row["sender_id"],
        sender_room_number=row["sender_room_number"],
        message_type=row["message_type"],
        body=DELETED_MESSAGE_BODY,
        created_at=row["created_at"],
        deleted_at=row["deleted_at"],
    )

    if newly_deleted:
        background_tasks.add_task(
            connection_manager.broadcast,
            room_id,
            {"data": response.model_dump(mode="json")},
        )

    return {"data": response}


@router.get(
    "/chat/rooms/{room_id}/messages",
    response_model=ApiResponse[list[ChatMessageResponse]],
)
def get_room_messages(
    room_id: int,
    before_id: int | None = Query(default=None, gt=0),
    limit: int = Query(default=50, ge=1, le=50),
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)
            _get_accessible_room(cursor, room_id, current_user_id)

            cursor.execute(
                """
                SELECT
                    m.id,
                    m.sender_id,
                    u.room_number AS sender_room_number,
                    m.message_type,
                    CASE
                        WHEN m.deleted_at IS NULL THEN m.body
                        ELSE %s
                    END AS body,
                    m.created_at,
                    m.deleted_at
                FROM public.chat_messages AS m
                LEFT JOIN public.users AS u ON u.id = m.sender_id
                WHERE m.room_id = %s
                  AND (%s IS NULL OR m.id < %s)
                ORDER BY m.id DESC
                LIMIT %s
                """,
                (DELETED_MESSAGE_BODY, room_id, before_id, before_id, limit),
            )
            rows = cursor.fetchall()

    return {
        "data": [ChatMessageResponse.model_validate(row) for row in rows]
    }


@router.websocket("/ws/chat/{room_id}")
async def websocket_chat(websocket: WebSocket, room_id: int):
    try:
        current_user_id = await asyncio.to_thread(
            _authorize_websocket,
            websocket,
            room_id,
        )
    except ApiException:
        await websocket.close(code=1008)
        return
    except Exception:
        logger.exception("WebSocket connection authorization failed")
        await websocket.close(code=1011)
        return

    await connection_manager.connect(room_id, current_user_id, websocket)
    try:
        while True:
            await websocket.receive()
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket receive failed")
    finally:
        await connection_manager.disconnect(room_id, websocket)


@router.post(
    "/chat/direct/{user_id}",
    response_model=ApiResponse[ChatRoomResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_direct_chat(
    user_id: UUID,
    current_user_id: UUID = Depends(get_current_user_id),
):
    if user_id == current_user_id:
        raise ApiException(
            409,
            "CHAT_SELF_DM_NOT_ALLOWED",
            "Cannot create a direct chat with yourself",
        )

    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)

            cursor.execute(
                """
                SELECT id, room_number, dorm_verified
                FROM public.users
                WHERE id = %s
                """,
                (user_id,),
            )
            target_user = cursor.fetchone()

            if target_user is None:
                raise ApiException(404, "USER_NOT_FOUND", "User not found")
            if not target_user["dorm_verified"]:
                raise ApiException(
                    403,
                    "TARGET_DORM_VERIFICATION_REQUIRED",
                    "The target user is not verified for chat",
                )

            dm_user_a, dm_user_b = sorted((current_user_id, user_id))
            cursor.execute(
                """
                INSERT INTO public.chat_rooms (room_type, dm_user_a, dm_user_b)
                VALUES ('DM', %s, %s)
                ON CONFLICT (dm_user_a, dm_user_b)
                    WHERE room_type = 'DM'
                DO NOTHING
                RETURNING id, created_at
                """,
                (dm_user_a, dm_user_b),
            )
            room = cursor.fetchone()

            if room is not None:
                cursor.execute(
                    """
                    INSERT INTO public.chat_room_members (room_id, user_id)
                    VALUES (%s, %s), (%s, %s)
                    """,
                    (room["id"], dm_user_a, room["id"], dm_user_b),
                )
            else:
                cursor.execute(
                    """
                    SELECT id, room_type, post_id, product_name,
                           dm_user_a, dm_user_b,
                           NULL::VARCHAR AS dm_room_a,
                           NULL::VARCHAR AS dm_room_b,
                           created_at
                    FROM public.chat_rooms
                    WHERE room_type = 'DM'
                      AND dm_user_a = %s
                      AND dm_user_b = %s
                    FOR UPDATE
                    """,
                    (dm_user_a, dm_user_b),
                )
                room = cursor.fetchone()

            if room is None:
                raise ApiException(
                    503,
                    "CHAT_ROOM_UNAVAILABLE",
                    "Chat room is temporarily unavailable",
                )

            response = _room_response(
                {
                    **room,
                    "room_type": room.get("room_type", "DM"),
                    "post_id": room.get("post_id"),
                    "product_name": room.get("product_name"),
                    "dm_user_a": room.get("dm_user_a", dm_user_a),
                    "dm_user_b": room.get("dm_user_b", dm_user_b),
                    "dm_room_a": (
                        target_user["room_number"]
                        if dm_user_a == user_id
                        else None
                    ),
                    "dm_room_b": (
                        target_user["room_number"]
                        if dm_user_b == user_id
                        else None
                    ),
                },
                current_user_id,
            )

    return {"data": response}


@router.get(
    "/posts/{post_id}/chat",
    response_model=ApiResponse[ChatRoomResponse],
)
def get_post_chat(
    post_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)

            cursor.execute(
                """
                SELECT
                    p.id,
                    p.author_id,
                    p.product_name,
                    (
                        p.author_id = %s
                        OR EXISTS (
                            SELECT 1
                            FROM public.participations AS part
                            WHERE part.post_id = p.id
                              AND part.user_id = %s
                        )
                    ) AS can_access
                FROM public.posts AS p
                WHERE p.id = %s
                """,
                (current_user_id, current_user_id, post_id),
            )
            post = cursor.fetchone()

            if post is None:
                raise ApiException(404, "POST_NOT_FOUND", "Post not found")
            if not post["can_access"]:
                raise ApiException(
                    403,
                    "CHAT_ACCESS_FORBIDDEN",
                    "Only the post author or participants can access this chat",
                )

            cursor.execute(
                """
                INSERT INTO public.chat_rooms (room_type, post_id)
                VALUES ('GROUP', %s)
                ON CONFLICT (post_id)
                    WHERE room_type = 'GROUP'
                DO NOTHING
                """,
                (post_id,),
            )
            cursor.execute(
                """
                SELECT
                    r.id,
                    r.room_type,
                    r.post_id,
                    p.product_name,
                    r.dm_user_a,
                    r.dm_user_b,
                    NULL::VARCHAR AS dm_room_a,
                    NULL::VARCHAR AS dm_room_b,
                    r.created_at
                FROM public.chat_rooms AS r
                JOIN public.posts AS p ON p.id = r.post_id
                WHERE r.room_type = 'GROUP'
                  AND r.post_id = %s
                """,
                (post_id,),
            )
            room = cursor.fetchone()

    if room is None:
        raise ApiException(
            503,
            "CHAT_ROOM_UNAVAILABLE",
            "Chat room is temporarily unavailable",
        )

    return {"data": _room_response(room, current_user_id)}


@router.get(
    "/chat/rooms",
    response_model=ApiResponse[list[ChatRoomResponse]],
)
def get_chat_rooms(current_user_id: UUID = Depends(get_current_user_id)):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            _require_verified_user(cursor, current_user_id)

            # Backfill GROUP rooms for older posts without storing group members.
            cursor.execute(
                """
                INSERT INTO public.chat_rooms (room_type, post_id)
                SELECT 'GROUP', p.id
                FROM public.posts AS p
                WHERE (
                    p.author_id = %s
                    OR EXISTS (
                        SELECT 1
                        FROM public.participations AS part
                        WHERE part.post_id = p.id
                          AND part.user_id = %s
                    )
                )
                ON CONFLICT (post_id)
                    WHERE room_type = 'GROUP'
                DO NOTHING
                """,
                (current_user_id, current_user_id),
            )
            cursor.execute(
                """
                SELECT
                    r.id,
                    r.room_type,
                    r.post_id,
                    p.product_name,
                    r.dm_user_a,
                    r.dm_user_b,
                    dm_a.room_number AS dm_room_a,
                    dm_b.room_number AS dm_room_b,
                    r.created_at
                FROM public.chat_rooms AS r
                LEFT JOIN public.posts AS p ON p.id = r.post_id
                LEFT JOIN public.users AS dm_a ON dm_a.id = r.dm_user_a
                LEFT JOIN public.users AS dm_b ON dm_b.id = r.dm_user_b
                WHERE (
                    r.room_type = 'GROUP'
                    AND (
                        p.author_id = %s
                        OR EXISTS (
                            SELECT 1
                            FROM public.participations AS part
                            WHERE part.post_id = r.post_id
                              AND part.user_id = %s
                        )
                    )
                )
                OR (
                    r.room_type = 'DM'
                    AND EXISTS (
                        SELECT 1
                        FROM public.chat_room_members AS member
                        WHERE member.room_id = r.id
                          AND member.user_id = %s
                    )
                )
                ORDER BY r.created_at DESC, r.id DESC
                """,
                (
                    current_user_id,
                    current_user_id,
                    current_user_id,
                ),
            )
            rooms = cursor.fetchall()

    return {
        "data": [
            _room_response(room, current_user_id)
            for room in rooms
        ]
    }
