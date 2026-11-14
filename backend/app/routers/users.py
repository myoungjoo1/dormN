from uuid import UUID

from fastapi import APIRouter, Depends
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.users import UserResponse, UserUpdateRequest


router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=ApiResponse[UserResponse])
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
        raise ApiException(404, "USER_PROFILE_NOT_FOUND", "User profile not found")

    return {"data": UserResponse.model_validate(row)}


@router.patch("/me", response_model=ApiResponse[UserResponse])
def update_me(
    user: UserUpdateRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    try:
        with get_connection() as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    UPDATE public.users
                    SET room_number = %s
                    WHERE id = %s
                    RETURNING
                        id,
                        room_number,
                        dorm_verified,
                        dorm_verified_at,
                        created_at
                    """,
                    (user.room_number, current_user_id),
                )
                row = cursor.fetchone()
    except UniqueViolation as exc:
        raise ApiException(
            409,
            "ROOM_NUMBER_ALREADY_REGISTERED",
            "Room number is already registered",
        ) from exc

    if row is None:
        raise ApiException(404, "USER_PROFILE_NOT_FOUND", "User profile not found")

    return {"data": UserResponse.model_validate(row)}
