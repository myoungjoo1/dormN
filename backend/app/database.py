import os

import psycopg
from dotenv import load_dotenv


load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")


def get_connection():
    return psycopg.connect(DATABASE_URL)


def test_connection():
    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1;")
            return cursor.fetchone()
