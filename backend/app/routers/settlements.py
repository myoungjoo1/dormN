from uuid import UUID

from fastapi import APIRouter, Depends
from psycopg.rows import dict_row

from app.api import ApiException, ApiResponse
from app.auth import get_current_user_id
from app.database import get_connection
from app.schemas.settlements import (
    HostSettlementListResponse,
    SettlementResponse,
)
from app.services.recruitment import calculate_settlement_amount


router = APIRouter(tags=["settlements"])

SETTLEMENT_COLUMNS = """
    s.id,
    s.participation_id,
    s.amount,
    s.payment_status,
    s.sent_at,
    s.confirmed_at,
    s.created_at
"""


@router.get(
    "/posts/{post_id}/settlement/me",
    response_model=ApiResponse[SettlementResponse],
)
def get_my_settlement(
    post_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                f"""
                SELECT {SETTLEMENT_COLUMNS}
                FROM settlements AS s
                JOIN participations AS p ON p.id = s.participation_id
                WHERE p.post_id = %s AND p.user_id = %s
                """,
                (post_id, current_user_id),
            )
            row = cursor.fetchone()

    if row is None:
        raise ApiException(404, "SETTLEMENT_NOT_FOUND", "Settlement not found")

    return {"data": SettlementResponse.model_validate(row)}


@router.post(
    "/settlements/{settlement_id}/sent",
    response_model=ApiResponse[SettlementResponse],
)
def mark_settlement_sent(
    settlement_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                f"""
                SELECT {SETTLEMENT_COLUMNS}
                FROM settlements AS s
                JOIN participations AS p ON p.id = s.participation_id
                WHERE s.id = %s AND p.user_id = %s
                FOR UPDATE OF s
                """,
                (settlement_id, current_user_id),
            )
            settlement = cursor.fetchone()

            if settlement is None:
                raise ApiException(
                    404,
                    "SETTLEMENT_NOT_FOUND",
                    "Settlement not found",
                )

            if settlement["payment_status"] != "UNPAID":
                raise ApiException(
                    409,
                    "SETTLEMENT_NOT_UNPAID",
                    "Settlement is not unpaid",
                )

            cursor.execute(
                f"""
                UPDATE settlements AS s
                SET payment_status = 'SENT', sent_at = NOW()
                WHERE id = %s
                RETURNING {SETTLEMENT_COLUMNS}
                """,
                (settlement_id,),
            )
            row = cursor.fetchone()

    return {"data": SettlementResponse.model_validate(row)}


@router.post(
    "/settlements/{settlement_id}/confirm",
    response_model=ApiResponse[SettlementResponse],
)
def confirm_settlement(
    settlement_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                f"""
                SELECT {SETTLEMENT_COLUMNS}, post.author_id
                FROM settlements AS s
                JOIN participations AS p ON p.id = s.participation_id
                JOIN posts AS post ON post.id = p.post_id
                WHERE s.id = %s AND post.author_id = %s
                FOR UPDATE OF s
                """,
                (settlement_id, current_user_id),
            )
            settlement = cursor.fetchone()

            if settlement is None:
                raise ApiException(
                    404,
                    "SETTLEMENT_NOT_FOUND",
                    "Settlement not found",
                )

            if settlement["payment_status"] != "SENT":
                raise ApiException(
                    409,
                    "SETTLEMENT_NOT_SENT",
                    "Settlement is not sent",
                )

            cursor.execute(
                f"""
                UPDATE settlements AS s
                SET payment_status = 'CONFIRMED', confirmed_at = NOW()
                WHERE id = %s
                RETURNING {SETTLEMENT_COLUMNS}
                """,
                (settlement_id,),
            )
            row = cursor.fetchone()

    return {"data": SettlementResponse.model_validate(row)}


@router.get(
    "/posts/{post_id}/settlements",
    response_model=ApiResponse[HostSettlementListResponse],
)
def get_host_settlements(
    post_id: int,
    current_user_id: UUID = Depends(get_current_user_id),
):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    post.id AS post_id,
                    post.author_id,
                    post.status,
                    post.total_price,
                    post.total_quantity,
                    p.user_id,
                    u.room_number,
                    p.quantity,
                    s.id AS settlement_id,
                    s.amount,
                    s.payment_status,
                    s.sent_at,
                    s.confirmed_at
                FROM posts AS post
                LEFT JOIN participations AS p ON p.post_id = post.id
                LEFT JOIN users AS u ON u.id = p.user_id
                LEFT JOIN settlements AS s ON s.participation_id = p.id
                WHERE post.id = %s
                ORDER BY p.created_at, p.id
                """,
                (post_id,),
            )
            rows = cursor.fetchall()

    if not rows:
        raise ApiException(404, "POST_NOT_FOUND", "Post not found")

    post = rows[0]
    if post["author_id"] != current_user_id:
        raise ApiException(
            403,
            "POST_AUTHOR_REQUIRED",
            "Only the post author can view settlements",
        )

    participants = []
    participant_total_amount = 0
    for row in rows:
        if row["user_id"] is None:
            continue

        if post["status"] == "RECRUITING":
            amount = calculate_settlement_amount(
                post["total_price"],
                row["quantity"],
                post["total_quantity"],
            )
            settlement_id = None
            payment_status = None
            sent_at = None
            confirmed_at = None
        elif post["status"] == "CANCELLED":
            amount = None
            settlement_id = None
            payment_status = None
            sent_at = None
            confirmed_at = None
        else:
            amount = row["amount"]
            settlement_id = row["settlement_id"]
            payment_status = row["payment_status"]
            sent_at = row["sent_at"]
            confirmed_at = row["confirmed_at"]

        participants.append(
            {
                "settlement_id": settlement_id,
                "user_id": row["user_id"],
                "room_number": row["room_number"],
                "quantity": row["quantity"],
                "amount": amount,
                "payment_status": payment_status,
                "sent_at": sent_at,
                "confirmed_at": confirmed_at,
            }
        )
        if amount is not None:
            participant_total_amount += amount

    if post["status"] == "CANCELLED":
        participant_total_amount = 0

    return {
        "data": {
            "post_id": post["post_id"],
            "status": post["status"],
            "total_price": post["total_price"],
            "participant_total_amount": participant_total_amount,
            "host_amount": post["total_price"] - participant_total_amount
            if post["status"] != "CANCELLED"
            else 0,
            "participants": participants,
        }
    }
