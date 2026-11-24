from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, status
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_verified_user_id
from app.database import get_connection
from app.routers.chat import connection_manager
from app.schemas.posts import (
    PostCreateRequest,
    PostRecruitmentResponse,
    PostResponse,
    PostStatusUpdateRequest,
)
from app.services.product_metadata import (
    BlockedProductUrl,
    InvalidProductUrl,
    fetch_product_metadata,
)
from app.services.chat import create_group_system_message
from app.services.post_image_storage import (
    StorageConfigurationError,
    get_public_post_image_url,
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
    current_user_id: UUID = Depends(get_current_verified_user_id),
):
    image_url = None
    if post.image_upload_id is None and post.product_url is not None:
        try:
            image_url = fetch_product_metadata(post.product_url).image_url
        except InvalidProductUrl as exc:
            raise ApiException(
                422,
                "INVALID_PRODUCT_URL",
                str(exc),
            ) from exc
        except BlockedProductUrl as exc:
            raise ApiException(
                422,
                "PRODUCT_URL_BLOCKED",
                str(exc),
            ) from exc

    with get_connection() as conn:
        with conn.cursor() as cursor:
            upload = None
            if post.image_upload_id is not None:
                cursor.execute(
                    """
                    SELECT
                        id,
                        user_id,
                        storage_path,
                        expires_at,
                        claimed_post_id
                    FROM public.post_image_uploads
                    WHERE id = %s
                    FOR UPDATE
                    """,
                    (post.image_upload_id,),
                )
                upload = cursor.fetchone()

                if upload is None:
                    raise ApiException(
                        404,
                        "IMAGE_UPLOAD_NOT_FOUND",
                        "Image upload not found",
                    )
                if upload[1] != current_user_id:
                    raise ApiException(
                        403,
                        "IMAGE_UPLOAD_NOT_OWNED",
                        "Image upload does not belong to the current user",
                    )
                if upload[3] <= datetime.now(timezone.utc):
                    raise ApiException(
                        409,
                        "IMAGE_UPLOAD_EXPIRED",
                        "Image upload has expired",
                    )
                if upload[4] is not None:
                    raise ApiException(
                        409,
                        "IMAGE_UPLOAD_ALREADY_USED",
                        "Image upload has already been used",
                    )

                try:
                    image_url = get_public_post_image_url(upload[2])
                except StorageConfigurationError as exc:
                    raise ApiException(
                        500,
                        "STORAGE_CONFIGURATION_ERROR",
                        "Storage is not configured",
                    ) from exc

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
                    image_url,
                    post.total_price,
                    post.total_quantity,
                    post.host_quantity,
                    post.deadline,
                    post.pickup_location,
                    post.shortfall_policy,
                ),
            )
            row = cursor.fetchone()

            cursor.execute(
                """
                INSERT INTO public.chat_rooms (room_type, post_id)
                VALUES ('GROUP', %s)
                ON CONFLICT (post_id)
                    WHERE room_type = 'GROUP'
                DO NOTHING
                """,
                (row[0],),
            )

            if upload is not None:
                cursor.execute(
                    """
                    UPDATE public.post_image_uploads
                    SET claimed_post_id = %s, claimed_at = NOW()
                    WHERE id = %s
                      AND claimed_post_id IS NULL
                    RETURNING id
                    """,
                    (row[0], post.image_upload_id),
                )
                if cursor.fetchone() is None:
                    raise ApiException(
                        409,
                        "IMAGE_UPLOAD_ALREADY_USED",
                        "Image upload has already been used",
                    )

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
    background_tasks: BackgroundTasks,
    current_user_id: UUID = Depends(get_current_verified_user_id),
):
    chat_event = None
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

            if post["status"] == "PICKUP" and status_update.status == "COMPLETED":
                cursor.execute(
                    """
                    SELECT COUNT(*) AS pending_count
                    FROM public.participations
                    WHERE post_id = %s
                      AND pickup_completed_at IS NULL
                    """,
                    (post_id,),
                )
                if cursor.fetchone()["pending_count"] > 0:
                    raise ApiException(
                        409,
                        "PICKUPS_NOT_COMPLETED",
                        "All participants must complete pickup first",
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

        chat_event = create_group_system_message(
            conn,
            post_id,
            status_update.status,
        )

    if chat_event is not None:
        background_tasks.add_task(
            connection_manager.broadcast,
            chat_event["room_id"],
            {"data": chat_event["message"]},
        )

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
