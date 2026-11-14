from uuid import UUID

from fastapi import APIRouter, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.posts import (
    PostCreateRequest,
    PostRecruitmentResponse,
    PostResponse,
    PostStatusUpdateRequest,
)


router = APIRouter(prefix="/posts", tags=["posts"])

POST_STATUS_TRANSITIONS = {
    "CLOSED": "ORDERED",
    "ORDERED": "ARRIVED",
    "ARRIVED": "PICKUP",
    "PICKUP": "COMPLETED",
}


@router.post(
    "",
    response_model=ApiResponse[PostResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_post(
    post: PostCreateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO posts (
                    author_id,
                    product_name,
                    product_url,
                    image_url,
                    total_price,
                    total_quantity,
                    host_quantity,
                    deadline,
                    pickup_location,
                    shortfall_policy
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING
                    id,
                    author_id,
                    product_name,
                    product_url,
                    image_url,
                    total_price,
                    total_quantity,
                    host_quantity,
                    deadline,
                    pickup_location,
                    shortfall_policy,
                    status,
                    created_at
                """,
                (
                    current_user_id,
                    post.product_name,
                    post.product_url,
                    post.image_url,
                    post.total_price,
                    post.total_quantity,
                    post.host_quantity,
                    post.deadline,
                    post.pickup_location,
                    post.shortfall_policy,
                ),
            )
            row = cursor.fetchone()

    return {
        "data": {
            "id": row[0],
            "author_id": row[1],
            "product_name": row[2],
            "product_url": row[3],
            "image_url": row[4],
            "total_price": row[5],
            "total_quantity": row[6],
            "host_quantity": row[7],
            "deadline": row[8],
            "pickup_location": row[9],
            "shortfall_policy": row[10],
            "status": row[11],
            "created_at": row[12],
        }
    }


@router.patch("/{post_id}/status", response_model=ApiResponse[PostResponse])
def update_post_status(
    post_id: int,
    status_update: PostStatusUpdateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    author_id,
                    product_name,
                    product_url,
                    image_url,
                    total_price,
                    total_quantity,
                    host_quantity,
                    deadline,
                    pickup_location,
                    shortfall_policy,
                    status,
                    created_at
                FROM public.posts
                WHERE id = %s
                FOR UPDATE
                """,
                (post_id,),
            )
            post = cursor.fetchone()

            if post is None:
                raise ApiException(404, "POST_NOT_FOUND", "Post not found")

            if post["author_id"] != current_user_id:
                raise ApiException(
                    403,
                    "POST_AUTHOR_REQUIRED",
                    "Only the post author can change its status",
                )

            expected_status = POST_STATUS_TRANSITIONS.get(post["status"])
            if status_update.status != expected_status:
                raise ApiException(
                    409,
                    "INVALID_POST_STATUS_TRANSITION",
                    (
                        f"Cannot transition post from {post['status']} "
                        f"to {status_update.status}"
                    ),
                )

            if post["status"] == "CLOSED":
                cursor.execute(
                    """
                    SELECT COUNT(*) AS pending_count
                    FROM public.participations AS p
                    LEFT JOIN public.settlements AS s
                        ON s.participation_id = p.id
                    WHERE p.post_id = %s
                      AND (
                          s.id IS NULL
                          OR s.payment_status != 'CONFIRMED'
                      )
                    """,
                    (post_id,),
                )
                if cursor.fetchone()["pending_count"] > 0:
                    raise ApiException(
                        409,
                        "SETTLEMENTS_NOT_CONFIRMED",
                        "All participant settlements must be confirmed",
                    )

            cursor.execute(
                """
                UPDATE public.posts
                SET status = %s
                WHERE id = %s
                RETURNING
                    id,
                    author_id,
                    product_name,
                    product_url,
                    image_url,
                    total_price,
                    total_quantity,
                    host_quantity,
                    deadline,
                    pickup_location,
                    shortfall_policy,
                    status,
                    created_at
                """,
                (status_update.status, post_id),
            )
            updated_post = cursor.fetchone()

    return {"data": PostResponse.model_validate(updated_post)}


@router.get(
    "",
    response_model=ApiResponse[list[PostRecruitmentResponse]],
    status_code=status.HTTP_200_OK,
)
def get_posts():
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    p.id,
                    p.author_id,
                    p.product_name,
                    p.product_url,
                    p.image_url,
                    p.total_price,
                    p.total_quantity,
                    p.host_quantity,
                    p.deadline,
                    p.pickup_location,
                    p.shortfall_policy,
                    p.status,
                    p.created_at,
                    u.room_number AS author_room_number,
                    COALESCE(SUM(part.quantity), 0)::INTEGER AS joined_quantity,
                    (
                        p.total_quantity
                        - p.host_quantity
                        - COALESCE(SUM(part.quantity), 0)
                    )::INTEGER AS remaining_quantity,
                    COUNT(part.id)::INTEGER AS participant_count
                FROM public.posts AS p
                JOIN public.users AS u ON u.id = p.author_id
                LEFT JOIN public.participations AS part ON part.post_id = p.id
                GROUP BY p.id, u.room_number
                ORDER BY p.created_at DESC
                """
            )
            rows = cursor.fetchall()

    return {"data": [PostRecruitmentResponse.model_validate(row) for row in rows]}


@router.get("/{post_id}", response_model=ApiResponse[PostRecruitmentResponse])
def get_post(post_id: int):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    p.id,
                    p.author_id,
                    p.product_name,
                    p.product_url,
                    p.image_url,
                    p.total_price,
                    p.total_quantity,
                    p.host_quantity,
                    p.deadline,
                    p.pickup_location,
                    p.shortfall_policy,
                    p.status,
                    p.created_at,
                    u.room_number AS author_room_number,
                    COALESCE(SUM(part.quantity), 0)::INTEGER AS joined_quantity,
                    (
                        p.total_quantity
                        - p.host_quantity
                        - COALESCE(SUM(part.quantity), 0)
                    )::INTEGER AS remaining_quantity,
                    COUNT(part.id)::INTEGER AS participant_count
                FROM public.posts AS p
                JOIN public.users AS u ON u.id = p.author_id
                LEFT JOIN public.participations AS part ON part.post_id = p.id
                WHERE p.id = %s
                GROUP BY p.id, u.room_number
                """,
                (post_id,),
            )
            row = cursor.fetchone()

    if row is None:
        raise ApiException(404, "POST_NOT_FOUND", "Post not found")

    return {"data": PostRecruitmentResponse.model_validate(row)}
