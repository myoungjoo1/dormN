from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.routers.chat import connection_manager
from app.schemas.pickups import (
    PickupCompletionResponse,
    PickupParticipantResponse,
)
from app.services.chat import create_group_system_message


router = APIRouter(tags=["pickups"])


@router.post(
    "/participations/{participation_id}/pickup",
    response_model=ApiResponse[PickupCompletionResponse],
    status_code=status.HTTP_200_OK,
)
def complete_pickup(
    participation_id: int,
    background_tasks: BackgroundTasks,
    current_user_id: UUID = Depends(get_current_user_id),
):
    chat_event = None

    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    p.id AS participation_id,
                    p.post_id,
                    p.user_id,
                    p.pickup_completed_at,
                    post.author_id,
                    post.status AS post_status
                FROM public.participations AS p
                JOIN public.posts AS post ON post.id = p.post_id
                WHERE p.id = %s
                FOR UPDATE OF p, post
                """,
                (participation_id,),
            )
            participation = cursor.fetchone()

            if participation is None:
                raise ApiException(
                    404,
                    "PARTICIPATION_NOT_FOUND",
                    "Participation not found",
                )
            if participation["user_id"] != current_user_id:
                raise ApiException(
                    403,
                    "PARTICIPATION_OWNER_REQUIRED",
                    "Only the participant can complete this pickup",
                )

            if participation["post_status"] not in {"PICKUP", "COMPLETED"}:
                raise ApiException(
                    409,
                    "POST_NOT_PICKUP",
                    "Pickup is not in progress",
                )
            if (
                participation["post_status"] == "COMPLETED"
                and participation["pickup_completed_at"] is None
            ):
                raise ApiException(
                    409,
                    "POST_ALREADY_COMPLETED",
                    "Post is already completed",
                )

            if participation["pickup_completed_at"] is None:
                cursor.execute(
                    """
                    UPDATE public.participations
                    SET pickup_completed_at = NOW()
                    WHERE id = %s
                    RETURNING pickup_completed_at
                    """,
                    (participation_id,),
                )
                participation["pickup_completed_at"] = cursor.fetchone()[
                    "pickup_completed_at"
                ]

            if participation["post_status"] == "PICKUP":
                cursor.execute(
                    """
                    SELECT COUNT(*) AS pending_count
                    FROM public.participations
                    WHERE post_id = %s
                      AND pickup_completed_at IS NULL
                    """,
                    (participation["post_id"],),
                )
                pending_count = cursor.fetchone()["pending_count"]

                if pending_count == 0:
                    cursor.execute(
                        """
                        UPDATE public.posts
                        SET status = 'COMPLETED'
                        WHERE id = %s AND status = 'PICKUP'
                        RETURNING status
                        """,
                        (participation["post_id"],),
                    )
                    updated_post = cursor.fetchone()
                    if updated_post is not None:
                        participation["post_status"] = updated_post["status"]
                        chat_event = create_group_system_message(
                            conn,
                            participation["post_id"],
                            "COMPLETED",
                        )

    if chat_event is not None:
        background_tasks.add_task(
            connection_manager.broadcast,
            chat_event["room_id"],
            {"data": chat_event["message"]},
        )

    return {
        "data": PickupCompletionResponse(
            participation_id=participation["participation_id"],
            post_id=participation["post_id"],
            pickup_completed_at=participation["pickup_completed_at"],
            post_status=participation["post_status"],
        )
    }


@router.get(
    "/posts/{post_id}/pickups",
    response_model=ApiResponse[list[PickupParticipantResponse]],
)
def get_post_pickups(
    post_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    post.author_id,
                    p.id AS participation_id,
                    u.room_number,
                    p.quantity,
                    p.pickup_completed_at IS NOT NULL AS pickup_completed,
                    p.pickup_completed_at
                FROM public.posts AS post
                LEFT JOIN public.participations AS p ON p.post_id = post.id
                LEFT JOIN public.users AS u ON u.id = p.user_id
                WHERE post.id = %s
                ORDER BY p.created_at, p.id
                """,
                (post_id,),
            )
            rows = cursor.fetchall()

    if not rows:
        raise ApiException(404, "POST_NOT_FOUND", "Post not found")
    if rows[0]["author_id"] != current_user_id:
        raise ApiException(
            403,
            "POST_AUTHOR_REQUIRED",
            "Only the post author can view pickups",
        )

    return {
        "data": [
            PickupParticipantResponse.model_validate(row)
            for row in rows
            if row["participation_id"] is not None
        ]
    }
