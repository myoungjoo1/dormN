from uuid import UUID

from fastapi import APIRouter, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.participations import (
    ParticipationCreateRequest,
    ParticipationQuoteResponse,
    ParticipationResponse,
)
from app.services.recruitment import (
    calculate_settlement_amount,
    finalize_recruitment,
)


router = APIRouter(prefix="/posts", tags=["participations"])


def _validate_post_for_participation(post, current_user_id: UUID):
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


@router.post(
    "/{post_id}/quote",
    response_model=ApiResponse[ParticipationQuoteResponse],
)
def quote_participation(
    post_id: int,
    participation: ParticipationCreateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    p.id,
                    p.author_id,
                    p.status,
                    p.total_price,
                    p.total_quantity,
                    p.host_quantity,
                    p.deadline <= NOW() AS deadline_expired,
                    EXISTS (
                        SELECT 1
                        FROM public.participations AS own_participation
                        WHERE own_participation.post_id = p.id
                          AND own_participation.user_id = %s
                    ) AS already_joined,
                    COALESCE((
                        SELECT SUM(all_participations.quantity)
                        FROM public.participations AS all_participations
                        WHERE all_participations.post_id = p.id
                    ), 0) AS joined_quantity
                FROM public.posts AS p
                WHERE p.id = %s
                """,
                (current_user_id, post_id),
            )
            post = cursor.fetchone()

    _validate_post_for_participation(post, current_user_id)

    if post["already_joined"]:
        raise ApiException(
            409,
            "PARTICIPATION_ALREADY_EXISTS",
            "User has already joined this post",
        )

    remaining_quantity = (
        post["total_quantity"] - post["host_quantity"] - post["joined_quantity"]
    )
    if participation.quantity > remaining_quantity:
        raise ApiException(
            409,
            "INSUFFICIENT_QUANTITY",
            "Not enough quantity remaining",
        )

    return {
        "data": ParticipationQuoteResponse(
            post_id=post_id,
            quantity=participation.quantity,
            estimated_amount=calculate_settlement_amount(
                post["total_price"],
                participation.quantity,
                post["total_quantity"],
            ),
            remaining_quantity_after_join=(
                remaining_quantity - participation.quantity
            ),
        )
    }


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

            _validate_post_for_participation(post, current_user_id)

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
