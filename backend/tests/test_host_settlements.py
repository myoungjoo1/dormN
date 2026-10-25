import unittest
from unittest.mock import patch

from fastapi import HTTPException

from app.routers.settlements import get_host_settlements


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows
        self.queries = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.queries.append((query, params))

    def fetchall(self):
        return self.rows


class FakeConnection:
    def __init__(self, rows):
        self.cursor_instance = FakeCursor(rows)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def participant_row(
    *,
    status="RECRUITING",
    user_id=4,
    quantity=4,
    settlement_id=None,
    amount=None,
    payment_status=None,
    sent_at=None,
    confirmed_at=None,
):
    return {
        "post_id": 10,
        "author_id": 1,
        "status": status,
        "total_price": 22900,
        "total_quantity": 24,
        "user_id": user_id,
        "room_number": "709-2",
        "quantity": quantity,
        "settlement_id": settlement_id,
        "amount": amount,
        "payment_status": payment_status,
        "sent_at": sent_at,
        "confirmed_at": confirmed_at,
    }


class HostSettlementTest(unittest.TestCase):
    def call_endpoint(self, rows, post_id=10):
        connection = FakeConnection(rows)
        with patch("app.routers.settlements.get_connection", return_value=connection):
            result = get_host_settlements(post_id)
        return result, connection

    def test_host_can_view_recruiting_participants_without_creating_settlements(self):
        result, connection = self.call_endpoint([participant_row()])

        self.assertEqual(result["participants"][0]["amount"], 3816)
        self.assertIsNone(result["participants"][0]["settlement_id"])
        self.assertIsNone(result["participants"][0]["payment_status"])
        self.assertEqual(result["participant_total_amount"], 3816)
        self.assertEqual(result["host_amount"], 19084)
        self.assertFalse(
            "INSERT INTO settlements" in connection.cursor_instance.queries[0][0]
        )

    def test_non_host_gets_forbidden(self):
        connection = FakeConnection([participant_row()])
        with patch("app.routers.settlements.get_connection", return_value=connection), patch(
            "app.routers.settlements.DEVELOPMENT_HOST_USER_ID", 4
        ):
            with self.assertRaises(HTTPException) as context:
                get_host_settlements(10)

        self.assertEqual(context.exception.status_code, 403)

    def test_missing_post_returns_not_found(self):
        connection = FakeConnection([])
        with patch("app.routers.settlements.get_connection", return_value=connection):
            with self.assertRaises(HTTPException) as context:
                get_host_settlements(999)

        self.assertEqual(context.exception.status_code, 404)

    def test_closed_returns_saved_settlement_statuses_and_host_amount(self):
        rows = [
            participant_row(
                status="CLOSED",
                quantity=4,
                settlement_id=30,
                amount=3816,
                payment_status="UNPAID",
            ),
            participant_row(
                status="CLOSED",
                user_id=5,
                quantity=6,
                settlement_id=31,
                amount=5725,
                payment_status="SENT",
            ),
            participant_row(
                status="CLOSED",
                user_id=6,
                quantity=2,
                settlement_id=32,
                amount=1908,
                payment_status="CONFIRMED",
            ),
        ]

        result, _ = self.call_endpoint(rows)

        self.assertEqual(
            [participant["payment_status"] for participant in result["participants"]],
            ["UNPAID", "SENT", "CONFIRMED"],
        )
        self.assertEqual(result["participant_total_amount"], 11449)
        self.assertEqual(result["host_amount"], 11451)

    def test_cancelled_is_viewable_without_settlement_amounts(self):
        result, _ = self.call_endpoint(
            [participant_row(status="CANCELLED", settlement_id=None)]
        )

        participant = result["participants"][0]
        self.assertIsNone(participant["amount"])
        self.assertIsNone(participant["payment_status"])
        self.assertEqual(result["participant_total_amount"], 0)
        self.assertEqual(result["host_amount"], 0)


if __name__ == "__main__":
    unittest.main()
