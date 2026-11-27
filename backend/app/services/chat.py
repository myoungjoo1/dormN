from psycopg.rows import dict_row


SYSTEM_MESSAGE_BODIES = {
    "CLOSED": "모집이 마감되었습니다. 각자의 정산 금액을 확인해주세요.",
    "CANCELLED": "공동구매가 취소되었습니다.",
    "ORDERED": "모집자가 주문을 완료했습니다.",
    "ARRIVED": "상품이 수경재에 도착했습니다.",
    "PICKUP": "현재 픽업이 진행 중입니다.",
    "COMPLETED": "거래가 완료되었습니다.",
}


def create_group_system_message(conn, post_id: int, status: str):
    body = SYSTEM_MESSAGE_BODIES.get(status)
    if body is None:
        return None

    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            INSERT INTO public.chat_rooms (room_type, post_id)
            VALUES ('GROUP', %s)
            ON CONFLICT (post_id)
                WHERE room_type = 'GROUP'
            DO NOTHING
            RETURNING id
            """,
            (post_id,),
        )
        room = cursor.fetchone()

        if room is None:
            cursor.execute(
                """
                SELECT id
                FROM public.chat_rooms
                WHERE room_type = 'GROUP'
                  AND post_id = %s
                """,
                (post_id,),
            )
            room = cursor.fetchone()

        if room is None:
            raise RuntimeError("Group chat room could not be created")

        cursor.execute(
            """
            INSERT INTO public.chat_messages (
                room_id,
                sender_id,
                message_type,
                body
            )
            SELECT %s, NULL, 'SYSTEM', %s
            WHERE NOT EXISTS (
                SELECT 1
                FROM public.chat_messages
                WHERE room_id = %s
                  AND message_type = 'SYSTEM'
                  AND body = %s
            )
            RETURNING id, room_id, sender_id, message_type, body, created_at, deleted_at
            """,
            (room["id"], body, room["id"], body),
        )
        message = cursor.fetchone()

    if message is None:
        return None

    return {
        "room_id": message["room_id"],
        "message": {
            "id": message["id"],
            "sender_id": message["sender_id"],
            "sender_room_number": None,
            "message_type": message["message_type"],
            "body": message["body"],
            "created_at": message["created_at"],
            "deleted_at": message.get("deleted_at"),
        },
    }
