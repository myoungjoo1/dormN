import os
import unittest
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import patch
from uuid import UUID, uuid4

import psycopg
from psycopg import sql

from app.api import ApiException
from app.database import DATABASE_URL
from app.routers.participations import join_post
from app.schemas.participations import ParticipationCreateRequest


HOST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
FIRST_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
SECOND_USER_ID = UUID("33333333-3333-3333-3333-333333333333")


@unittest.skipUnless(
    DATABASE_URL and os.getenv("RUN_SUPABASE_INTEGRATION") == "1",
    "Set RUN_SUPABASE_INTEGRATION=1 to run PostgreSQL integration tests",
)
class ParticipationConcurrencyIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.schema_name = f"dormn_test_{uuid4().hex}"
        self.addCleanup(self.drop_test_schema)
        self.create_test_schema()

    def drop_test_schema(self):
        with psycopg.connect(DATABASE_URL) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(
                        sql.Identifier(self.schema_name)
                    )
                )

    def create_test_schema(self):
        with psycopg.connect(DATABASE_URL) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    sql.SQL("CREATE SCHEMA {}").format(
                        sql.Identifier(self.schema_name)
                    )
                )
                for table in ("users", "posts", "participations", "settlements"):
                    cursor.execute(
                        sql.SQL(
                            "CREATE TABLE {}.{} (LIKE public.{} INCLUDING ALL)"
                        ).format(
                            sql.Identifier(self.schema_name),
                            sql.Identifier(table),
                            sql.Identifier(table),
                        )
                    )

                cursor.executemany(
                    sql.SQL("INSERT INTO {}.users (id) VALUES (%s)").format(
                        sql.Identifier(self.schema_name)
                    ),
                    [
                        (HOST_USER_ID,),
                        (FIRST_USER_ID,),
                        (SECOND_USER_ID,),
                    ],
                )
                cursor.execute(
                    sql.SQL(
                        """
                        INSERT INTO {}.posts (
                            id,
                            author_id,
                            product_name,
                            total_price,
                            total_quantity,
                            host_quantity,
                            deadline,
                            pickup_location,
                            shortfall_policy
                        )
                        VALUES (
                            1, %s, 'concurrency-test', 7000, 7, 4,
                            NOW() + INTERVAL '1 day',
                            'integration-test', 'KEEP_BY_HOST'
                        )
                        """
                    ).format(sql.Identifier(self.schema_name)),
                    (HOST_USER_ID,),
                )

    def schema_connection(self):
        connection = psycopg.connect(DATABASE_URL)
        connection.execute(
            sql.SQL("SET search_path TO {}, public").format(
                sql.Identifier(self.schema_name)
            )
        )
        return connection

    def test_only_one_concurrent_join_can_claim_the_last_available_quantity(self):
        barrier = Barrier(2)

        def join(user_id):
            barrier.wait()
            try:
                join_post(1, ParticipationCreateRequest(quantity=2), user_id)
                return "JOINED"
            except ApiException as error:
                return error.code

        with patch(
            "app.routers.participations.get_connection",
            side_effect=self.schema_connection,
        ):
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(join, (FIRST_USER_ID, SECOND_USER_ID)))

        self.assertCountEqual(results, ["JOINED", "INSUFFICIENT_QUANTITY"])

        with self.schema_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT COALESCE(SUM(quantity), 0), COUNT(*)
                    FROM participations
                    WHERE post_id = 1
                    """
                )
                self.assertEqual(cursor.fetchone(), (2, 1))


if __name__ == "__main__":
    unittest.main()
