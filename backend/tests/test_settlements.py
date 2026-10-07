import unittest

from app.services.recruitment import (
    calculate_settlement_amount,
    create_settlements,
)


class FakeCursor:
    def __init__(self, participations, inserted):
        self.participations = participations
        self.inserted = inserted
        self.calls = []
        self.rows = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if query.lstrip().startswith("SELECT"):
            self.rows = self.participations
            return

        participation_id, amount = params
        self.inserted.setdefault(participation_id, amount)

    def fetchall(self):
        return self.rows


class FakeConnection:
    def __init__(self, participations):
        self.inserted = {}
        self.cursor_instance = FakeCursor(participations, self.inserted)

    def cursor(self, row_factory=None):
        return self.cursor_instance


class SettlementTest(unittest.TestCase):
    def test_floor_amount_and_duplicate_insert_are_safe(self):
        self.assertEqual(calculate_settlement_amount(22900, 4, 24), 3816)
        self.assertEqual(3816 + (22900 - 3816), 22900)

        conn = FakeConnection([{"id": 20, "quantity": 4}])
        create_settlements(conn, 10, 22900, 24)
        create_settlements(conn, 10, 22900, 24)

        self.assertEqual(conn.inserted, {20: 3816})
        insert_sql = conn.cursor_instance.calls[1][0]
        self.assertIn("ON CONFLICT (participation_id) DO NOTHING", insert_sql)


if __name__ == "__main__":
    unittest.main()
