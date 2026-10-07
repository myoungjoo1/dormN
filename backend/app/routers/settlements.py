from fastapi import APIRouter, HTTPException
from psycopg.rows import dict_row

from app.database import get_connection
from app.schemas.settlements import SettlementResponse


router = APIRouter(tags=["settlements"])
DEVELOPMENT_USER_ID = 4

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
    response_model=SettlementResponse,
)
def get_my_settlement(post_id: int):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                f"""
                SELECT {SETTLEMENT_COLUMNS}
                FROM settlements AS s
                JOIN participations AS p ON p.id = s.participation_id
                WHERE p.post_id = %s AND p.user_id = %s
                """,
                (post_id, DEVELOPMENT_USER_ID),
            )
            row = cursor.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Settlement not found")

    return SettlementResponse.model_validate(row)


@router.post(
    "/settlements/{settlement_id}/sent",
    response_model=SettlementResponse,
)
def mark_settlement_sent(settlement_id: int):
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
                (settlement_id, DEVELOPMENT_USER_ID),
            )
            settlement = cursor.fetchone()

            if settlement is None:
                raise HTTPException(status_code=404, detail="Settlement not found")

            if settlement["payment_status"] != "UNPAID":
                raise HTTPException(
                    status_code=409,
                    detail="Settlement is not unpaid",
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

    return SettlementResponse.model_validate(row)


@router.post(
    "/settlements/{settlement_id}/confirm",
    response_model=SettlementResponse,
)
def confirm_settlement(settlement_id: int):
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
                (settlement_id, DEVELOPMENT_USER_ID),
            )
            settlement = cursor.fetchone()

            if settlement is None:
                raise HTTPException(status_code=404, detail="Settlement not found")

            if settlement["payment_status"] != "SENT":
                raise HTTPException(
                    status_code=409,
                    detail="Settlement is not sent",
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

    return SettlementResponse.model_validate(row)
