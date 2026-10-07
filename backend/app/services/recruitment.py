from psycopg.rows import dict_row

from app.database import get_connection


def calculate_settlement_amount(
    total_price: int,
    participation_quantity: int,
    total_quantity: int,
) -> int:
    return total_price * participation_quantity // total_quantity


def create_settlements(conn, post_id: int, total_price: int, total_quantity: int):
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            SELECT id, quantity
            FROM participations
            WHERE post_id = %s
            """,
            (post_id,),
        )
        participations = cursor.fetchall()

        for participation in participations:
            cursor.execute(
                """
                INSERT INTO settlements (participation_id, amount)
                VALUES (%s, %s)
                ON CONFLICT (participation_id) DO NOTHING
                """,
                (
                    participation["id"],
                    calculate_settlement_amount(
                        total_price,
                        participation["quantity"],
                        total_quantity,
                    ),
                ),
            )


def finalize_recruitment(conn, post_id: int):
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            SELECT
                id,
                status,
                total_price,
                total_quantity,
                host_quantity,
                shortfall_policy,
                deadline <= NOW() AS deadline_reached
            FROM posts
            WHERE id = %s
            FOR UPDATE
            """,
            (post_id,),
        )
        post = cursor.fetchone()

        if post is None or post["status"] != "RECRUITING":
            return None

        cursor.execute(
            """
            SELECT COALESCE(SUM(quantity), 0) AS participant_quantity
            FROM participations
            WHERE post_id = %s
            """,
            (post_id,),
        )
        participant_quantity = cursor.fetchone()["participant_quantity"]
        is_full = (
            post["host_quantity"] + participant_quantity
            == post["total_quantity"]
        )

        if not post["deadline_reached"] and not is_full:
            return None

        if post["shortfall_policy"] == "KEEP_BY_HOST":
            final_host_quantity = post["total_quantity"] - participant_quantity
            final_status = "CLOSED"
        elif (
            post["host_quantity"] + participant_quantity
            < post["total_quantity"]
        ):
            final_host_quantity = post["host_quantity"]
            final_status = "CANCELLED"
        else:
            final_host_quantity = post["host_quantity"]
            final_status = "CLOSED"

        cursor.execute(
            """
            UPDATE posts
            SET host_quantity = %s, status = %s
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
            (final_host_quantity, final_status, post_id),
        )
        finalized_post = cursor.fetchone()

    if final_status == "CLOSED":
        create_settlements(
            conn,
            post_id,
            post["total_price"],
            post["total_quantity"],
        )

    return finalized_post


def process_expired_recruitment_once():
    # ponytail: one transaction per scheduler pass; split per post if batches grow.
    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT id
                FROM posts
                WHERE status = 'RECRUITING'
                  AND deadline <= NOW()
                """
            )
            post_ids = [row[0] for row in cursor.fetchall()]

        for post_id in post_ids:
            finalize_recruitment(conn, post_id)
