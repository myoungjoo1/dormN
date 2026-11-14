from uuid import UUID

from fastapi import APIRouter, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.participations import (
    ParticipationCreateRequest,
    ParticipationResponse,
)
from app.services.recruitment import finalize_recruitment


router = APIRouter(prefix="/posts", tags=["participations"])


@router.post(
    "/{post_id}/join",
    response_model=ApiResponse[ParticipationResponse],
    status_code=status.HTTP_201_CREATED,
)
def join_post(
    post_id: int,
    participation: ParticipationCreateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    author_id,
                    status,
                    deadline,
                    total_quantity,
                    host_quantity,
                    deadline <= NOW() AS deadline_expired
                FROM posts
                WHERE id = %s
                FOR UPDATE
                """,
                (post_id,),
            )
            post = cursor.fetchone()

            if post is None:
                raise ApiException(404, "POST_NOT_FOUND", "Post not found")

            if post["author_id"] == current_user_id:
                raise ApiException(
                    409,
                    "POST_AUTHOR_CANNOT_JOIN",
                    "Post author cannot join own post",
                )

            if post["status"] != "RECRUITING":
                raise ApiException(
                    409,
                    "POST_NOT_RECRUITING",
                    "Post is not recruiting",
                )

            if post["deadline_expired"]:
                raise ApiException(
                    409,
                    "RECRUITMENT_DEADLINE_PASSED",
                    "Post recruitment deadline has passed",
                )

            cursor.execute(
                "SELECT 1 FROM users WHERE id = %s",
                (current_user_id,),
            )
            if cursor.fetchone() is None:
                raise ApiException(404, "USER_NOT_FOUND", "User not found")

            cursor.execute(
                """
                SELECT 1
                FROM participations
                WHERE post_id = %s AND user_id = %s
                """,
                (post_id, current_user_id),
            )
            if cursor.fetchone() is not None:
                raise ApiException(
                    409,
                    "PARTICIPATION_ALREADY_EXISTS",
                    "User has already joined this post",
                )

            cursor.execute(
                """
                SELECT COALESCE(SUM(quantity), 0) AS joined_quantity
                FROM participations
                WHERE post_id = %s
                """,
                (post_id,),
            )
            joined_quantity = cursor.fetchone()["joined_quantity"]
            remaining_quantity = (
                post["total_quantity"] - post["host_quantity"] - joined_quantity
            )

            if participation.quantity > remaining_quantity:
                raise ApiException(
                    409,
                    "INSUFFICIENT_QUANTITY",
                    "Not enough quantity remaining",
                )

            cursor.execute(
                """
                INSERT INTO participations (post_id, user_id, quantity)
                VALUES (%s, %s, %s)
                RETURNING id, post_id, user_id, quantity, created_at
                """,
                (post_id, current_user_id, participation.quantity),
            )
            row = cursor.fetchone()

        finalize_recruitment(conn, post_id)

    return {"data": ParticipationResponse.model_validate(row)}


@router.delete("/{post_id}/join", status_code=status.HTTP_204_NO_CONTENT)
def cancel_join(
    post_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    author_id,
                    status,
                    deadline <= NOW() AS deadline_expired
                FROM posts
                WHERE id = %s
                FOR UPDATE
                """,
                (post_id,),
            )
            post = cursor.fetchone()

            if post is None:
                raise ApiException(404, "POST_NOT_FOUND", "Post not found")

            if post["author_id"] == current_user_id:
                raise ApiException(
                    409,
                    "POST_AUTHOR_CANNOT_CANCEL_PARTICIPATION",
                    "Post author cannot cancel participation",
                )

            if post["status"] != "RECRUITING":
                raise ApiException(
                    409,
                    "POST_NOT_RECRUITING",
                    "Post is not recruiting",
                )

            if post["deadline_expired"]:
                raise ApiException(
                    409,
                    "RECRUITMENT_DEADLINE_PASSED",
                    "Post recruitment deadline has passed",
                )

            cursor.execute(
                """
                DELETE FROM participations
                WHERE post_id = %s AND user_id = %s
                RETURNING id
                """,
                (post_id, current_user_id),
            )
            participation = cursor.fetchone()

            if participation is None:
                raise ApiException(
                    404,
                    "PARTICIPATION_NOT_FOUND",
                    "Participation not found",
                )
