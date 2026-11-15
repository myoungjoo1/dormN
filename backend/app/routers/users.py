from uuid import UUID

from fastapi import APIRouter, Depends
import psycopg
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.users import (
    SettlementAccountRequest,
    SettlementAccountResponse,
    UserResponse,
    UserUpdateRequest,
)


router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "/me/settlement-account",
    response_model=ApiResponse[SettlementAccountResponse | None],
)
def get_settlement_account(
    current_user_id: UUID = Depends(get_current_user_id),
):
    try:
        with get_connection() as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    SELECT bank_name, account_number, account_holder_name, updated_at
                    FROM dormn_private.user_settlement_accounts
                    WHERE user_id = %s
                    """,
                    (current_user_id,),
                )
                row = cursor.fetchone()
    except psycopg.Error as exc:
        raise ApiException(
            503,
            "SETTLEMENT_ACCOUNT_UNAVAILABLE",
            "Settlement account service is temporarily unavailable",
        ) from exc

    return {
        "data": (
            SettlementAccountResponse.model_validate(row)
            if row is not None
            else None
        )
    }


@router.put(
    "/me/settlement-account",
    response_model=ApiResponse[SettlementAccountResponse],
)
def upsert_settlement_account(
    account: SettlementAccountRequest,
    current_user_id: UUID = Depends(get_current_user_id),
):
    try:
        with get_connection() as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    INSERT INTO dormn_private.user_settlement_accounts (
                        user_id,
                        bank_name,
                        account_number,
                        account_holder_name,
                        updated_at
                    )
                    VALUES (%s, %s, %s, %s, NOW())
                    ON CONFLICT (user_id) DO UPDATE
                    SET bank_name = EXCLUDED.bank_name,
                        account_number = EXCLUDED.account_number,
                        account_holder_name = EXCLUDED.account_holder_name,
                        updated_at = NOW()
                    RETURNING
                        bank_name,
                        account_number,
                        account_holder_name,
                        updated_at
                    """,
                    (
                        current_user_id,
                        account.bank_name,
                        account.account_number,
                        account.account_holder_name,
                    ),
                )
                row = cursor.fetchone()
    except psycopg.Error as exc:
        raise ApiException(
            503,
            "SETTLEMENT_ACCOUNT_UNAVAILABLE",
            "Settlement account service is temporarily unavailable",
        ) from exc

    if row is None:
        raise ApiException(
            503,
            "SETTLEMENT_ACCOUNT_UNAVAILABLE",
            "Settlement account service is temporarily unavailable",
        )

    return {"data": SettlementAccountResponse.model_validate(row)}


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
