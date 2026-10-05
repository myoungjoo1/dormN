from fastapi import APIRouter, status

from app.database import get_connection
from app.schemas.posts import PostCreateRequest, PostResponse


router = APIRouter(prefix="/posts", tags=["posts"])


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
def create_post(post: PostCreateRequest):
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
                    1,
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
