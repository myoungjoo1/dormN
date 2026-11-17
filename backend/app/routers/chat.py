from uuid import UUID

from fastapi import APIRouter, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.chat import ChatRoomResponse


router = APIRouter(tags=["chat"])


def _require_verified_user(cursor, user_id: UUID) -> None:
    cursor.execute(
        """
        SELECT dorm_verified
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
