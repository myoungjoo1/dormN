from fastapi import APIRouter, HTTPException, status
from psycopg.rows import dict_row

from app.database import get_connection
from app.schemas.participations import (
    ParticipationCreateRequest,
    ParticipationResponse,
)


router = APIRouter(prefix="/posts", tags=["participations"])
DEVELOPMENT_USER_ID = 4


@router.post(
    "/{post_id}/join",
    response_model=ParticipationResponse,
    status_code=status.HTTP_201_CREATED,
)
def join_post(post_id: int, participation: ParticipationCreateRequest):
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
                raise HTTPException(status_code=404, detail="Post not found")

            if post["author_id"] == DEVELOPMENT_USER_ID:
                raise HTTPException(
                    status_code=409,
                    detail="Post author cannot join own post",
                )

            if post["status"] != "RECRUITING":
                raise HTTPException(
                    status_code=409,
                    detail="Post is not recruiting",
                )

            if post["deadline_expired"]:
                raise HTTPException(
                    status_code=409,
                    detail="Post recruitment deadline has passed",
                )

            cursor.execute(
                "SELECT 1 FROM users WHERE id = %s",
                (DEVELOPMENT_USER_ID,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="User not found")

            cursor.execute(
                """
                SELECT 1
                FROM participations
                WHERE post_id = %s AND user_id = %s
                """,
                (post_id, DEVELOPMENT_USER_ID),
            )
            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="User has already joined this post",
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
                raise HTTPException(
                    status_code=409,
                    detail="Not enough quantity remaining",
                )

            cursor.execute(
                """
                INSERT INTO participations (post_id, user_id, quantity)
                VALUES (%s, %s, %s)
                RETURNING id, post_id, user_id, quantity, created_at
                """,
                (post_id, DEVELOPMENT_USER_ID, participation.quantity),
            )
            row = cursor.fetchone()

    return ParticipationResponse.model_validate(row)
