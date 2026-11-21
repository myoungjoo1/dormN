from uuid import UUID

from fastapi import APIRouter, Depends, Query
import psycopg
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.users import (
    ROOM_NUMBER_PATTERN,
    SettlementAccountRequest,
    SettlementAccountResponse,
    UserSearchResponse,
    UserResponse,
    UserUpdateRequest,
)
from app.schemas.posts import PostRecruitmentResponse
from app.schemas.participations import MyParticipationHistoryResponse


router = APIRouter(prefix="/users", tags=["users"])


POST_HISTORY_SELECT = """
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
        author.room_number AS author_room_number,
        COALESCE((
            SELECT SUM(all_participations.quantity)
            FROM public.participations AS all_participations
            WHERE all_participations.post_id = p.id
        ), 0)::INTEGER AS joined_quantity,
        (
            p.total_quantity
            - p.host_quantity
            - COALESCE((
                SELECT SUM(all_participations.quantity)
                FROM public.participations AS all_participations
                WHERE all_participations.post_id = p.id
            ), 0)
        )::INTEGER AS remaining_quantity,
        (
            SELECT COUNT(*)::INTEGER
            FROM public.participations AS all_participations
            WHERE all_participations.post_id = p.id
        ) AS participant_count
        ,mine.id AS participation_id
        ,mine.quantity
        ,settlement.id AS settlement_id
        ,settlement.amount AS settlement_amount
        ,settlement.payment_status
        ,mine.pickup_completed_at
    FROM public.posts AS p
    JOIN public.users AS author ON author.id = p.author_id
    LEFT JOIN public.participations AS mine
        ON mine.post_id = p.id
       AND mine.user_id = %s
    LEFT JOIN public.settlements AS settlement
        ON settlement.participation_id = mine.id
"""


@router.get(
    "/search",
    response_model=ApiResponse[list[UserSearchResponse]],
)
def search_users(
    room_number: str = Query(
        ...,
        min_length=5,
        max_length=20,
        pattern=ROOM_NUMBER_PATTERN,
    ),
    current_user_id: UUID = Depends(get_current_user_id),
):
    if room_number != room_number.strip():
        raise ApiException(
            422,
            "INVALID_ROOM_NUMBER",
            "Invalid room number",
        )

    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT dorm_verified
                FROM public.users
                WHERE id = %s
                """,
                (current_user_id,),
            )
            requester = cursor.fetchone()

            if requester is None:
                raise ApiException(404, "USER_NOT_FOUND", "User not found")
            if not requester["dorm_verified"]:
                raise ApiException(
                    403,
                    "DORM_VERIFICATION_REQUIRED",
                    "Dorm verification is required to search users",
                )

            cursor.execute(
                """
                SELECT id AS user_id, room_number
                FROM public.users
                WHERE room_number = %s
                  AND dorm_verified = TRUE
                  AND id <> %s
                """,
                (room_number, current_user_id),
            )
            rows = cursor.fetchall()

    return {
        "data": [UserSearchResponse.model_validate(row) for row in rows]
    }


@router.get(
    "/me/posts",
    response_model=ApiResponse[list[PostRecruitmentResponse]],
)
def get_my_posts(current_user_id: UUID = Depends(get_current_user_id)):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                POST_HISTORY_SELECT
                + """
                WHERE p.author_id = %s
                ORDER BY p.created_at DESC
                """,
                (current_user_id, current_user_id),
            )
            rows = cursor.fetchall()

    return {
        "data": [PostRecruitmentResponse.model_validate(row) for row in rows]
    }


@router.get(
    "/me/participations",
    response_model=ApiResponse[list[MyParticipationHistoryResponse]],
)
def get_my_participations(current_user_id: UUID = Depends(get_current_user_id)):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                POST_HISTORY_SELECT
                + """
                WHERE mine.id IS NOT NULL
                ORDER BY p.created_at DESC, mine.created_at DESC
                """,
                (current_user_id,),
            )
            rows = cursor.fetchall()

    return {
        "data": [
            MyParticipationHistoryResponse.model_validate(row)
            for row in rows
        ]
    }


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
