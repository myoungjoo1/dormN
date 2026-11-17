import unittest
from datetime import datetime, timezone

from app.services.chat import create_group_system_message


class FakeCursor:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params=None):
        self.calls.append((query, params))

    def fetchone(self):
        return self.rows.pop(0) if self.rows else None


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def cursor(self, row_factory=None):
        return self.cursor_instance


CREATED_AT = datetime(2026, 11, 17, tzinfo=timezone.utc)


def message_row(body):
    return {
        "id": 7,
        "room_id": 50,
        "sender_id": None,
        "message_type": "SYSTEM",
        "body": body,
        "created_at": CREATED_AT,
    }


class ChatSystemMessageTest(unittest.TestCase):
    def test_status_message_creates_missing_group_room_and_message(self):
        body = "모집이 마감되었습니다. 각자의 정산 금액을 확인해주세요."
        connection = FakeConnection(
            [{"id": 50}, message_row(body)]
        )

        event = create_group_system_message(connection, 10, "CLOSED")

        self.assertEqual(event["room_id"], 50)
        self.assertEqual(event["message"]["message_type"], "SYSTEM")
        self.assertIsNone(event["message"]["sender_id"])
        self.assertEqual(event["message"]["body"], body)
        self.assertTrue(
            any(
                "INSERT INTO public.chat_messages" in query
                for query, _ in connection.cursor_instance.calls
            )
        )

    def test_cancelled_status_uses_cancel_message(self):
        body = "공동구매가 취소되었습니다."
        connection = FakeConnection([{"id": 50}, message_row(body)])

        event = create_group_system_message(connection, 10, "CANCELLED")

        self.assertEqual(event["message"]["body"], body)

    def test_duplicate_status_message_is_not_created(self):
        connection = FakeConnection([{"id": 50}, None])

        event = create_group_system_message(connection, 10, "ORDERED")

        self.assertIsNone(event)

    def test_unknown_status_does_not_write(self):
        connection = FakeConnection([])

        event = create_group_system_message(connection, 10, "RECRUITING")

        self.assertIsNone(event)
        self.assertEqual(connection.cursor_instance.calls, [])


if __name__ == "__main__":
    unittest.main()
