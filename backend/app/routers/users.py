from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from psycopg.rows import dict_row

from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.users import UserResponse


router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserResponse)
def get_me(current_user_id: UUID = Depends(get_current_user_id)):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT id, room_number, dorm_verified, dorm_verified_at, created_at
                FROM public.users
                WHERE id = %s
                """,
                (current_user_id,),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="User profile not found")

    return UserResponse.model_validate(row)
