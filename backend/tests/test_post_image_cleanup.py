import unittest
from datetime import datetime, timezone
from threading import Event, Lock, Thread
from unittest.mock import patch
from uuid import UUID

from app.services.post_image_cleanup import cleanup_expired_post_images
from app.services.post_image_storage import PostImageUploadError


UPLOAD_ID = UUID("33333333-3333-3333-3333-333333333333")
STORAGE_PATH = "tmp/11111111-1111-1111-1111-111111111111/upload.png"


class FakeCursor:
    def __init__(self, fetchall_rows=None, fetchone_rows=None, delete_error=None):
        self.fetchall_rows = fetchall_rows or []
        self.fetchone_rows = list(fetchone_rows or [])
        self.delete_error = delete_error
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))
        if self.delete_error and query.lstrip().startswith("DELETE FROM"):
            raise self.delete_error

    def fetchall(self):
        return self.fetchall_rows

    def fetchone(self):
        return self.fetchone_rows.pop(0) if self.fetchone_rows else None


class FakeConnection:
    def __init__(self, cursor):
        self.cursor_instance = cursor
        self.rolled_back = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.rolled_back = exc_type is not None
        return False

    def cursor(self):
        return self.cursor_instance


class ConcurrentCleanupState:
    def __init__(self):
        self.lock = Lock()
        self.deleted = False


class ConcurrentCleanupCursor:
    def __init__(self, state):
        self.state = state
        self.pending_row = None
        self.lock_acquired = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        if "SELECT id, storage_path" in query:
            self.state.lock.acquire()
            self.lock_acquired = True
            if not self.state.deleted:
                self.pending_row = (UPLOAD_ID, STORAGE_PATH)
        elif query.lstrip().startswith("DELETE FROM"):
            self.state.deleted = True
            self.pending_row = (UPLOAD_ID,)

    def fetchone(self):
        row = self.pending_row
        self.pending_row = None
        return row


class ConcurrentCleanupConnection:
    def __init__(self, state):
        self.cursor_instance = ConcurrentCleanupCursor(state)
        self.state = state

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if self.cursor_instance.lock_acquired:
            self.state.lock.release()
        return False

    def cursor(self):
        return self.cursor_instance


def expired_row(claimed_post_id=None):
    return (UPLOAD_ID, STORAGE_PATH, claimed_post_id)


class PostImageCleanupTest(unittest.TestCase):
    def _connections(self, row, delete_error=None):
        candidate = FakeConnection(FakeCursor(fetchall_rows=[(UPLOAD_ID,)]))
        locked = FakeConnection(
            FakeCursor(
                fetchone_rows=[row, (UPLOAD_ID,)],
                delete_error=delete_error,
            )
        )
        return candidate, locked

    def test_expired_unclaimed_image_is_deleted(self):
        candidate, locked = self._connections(expired_row())

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[candidate, locked],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage"
        ) as delete_storage:
            summary = cleanup_expired_post_images(10)

        self.assertEqual(summary.deleted, 1)
        self.assertEqual(summary.failed, 0)
        delete_storage.assert_called_once_with(STORAGE_PATH)
        self.assertIn("FOR UPDATE", locked.cursor_instance.calls[0][0])

    def test_unexpired_image_is_not_selected(self):
        candidate = FakeConnection(FakeCursor(fetchall_rows=[]))

        with patch(
            "app.services.post_image_cleanup.get_connection",
            return_value=candidate,
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage"
        ) as delete_storage:
            summary = cleanup_expired_post_images(10)

        self.assertEqual(summary.processed, 0)
        delete_storage.assert_not_called()

    def test_claimed_image_is_not_selected(self):
        candidate = FakeConnection(FakeCursor(fetchall_rows=[]))

        with patch(
            "app.services.post_image_cleanup.get_connection",
            return_value=candidate,
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage"
        ) as delete_storage:
            summary = cleanup_expired_post_images(10)

        self.assertEqual(summary.processed, 0)
        delete_storage.assert_not_called()

    def test_storage_failure_keeps_db_record(self):
        candidate, locked = self._connections(expired_row())

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[candidate, locked],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage",
            side_effect=PostImageUploadError("storage unavailable"),
        ):
            summary = cleanup_expired_post_images(10)

        self.assertEqual(summary.failed, 1)
        self.assertEqual(
            len(
                [
                    query
                    for query, _ in locked.cursor_instance.calls
                    if query.lstrip().startswith("DELETE FROM")
                ]
            ),
            0,
        )

    def test_missing_storage_file_is_treated_as_deleted(self):
        candidate, locked = self._connections(expired_row())

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[candidate, locked],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage",
            return_value=None,
        ):
            summary = cleanup_expired_post_images(10)

        self.assertEqual(summary.deleted, 1)

    def test_db_delete_failure_leaves_row_for_next_retry(self):
        first_candidate, first_locked = self._connections(
            expired_row(),
            delete_error=RuntimeError("database delete failed"),
        )
        second_candidate, second_locked = self._connections(expired_row())

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[
                first_candidate,
                first_locked,
                second_candidate,
                second_locked,
            ],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage",
            return_value=None,
        ):
            first_summary = cleanup_expired_post_images(10)
            second_summary = cleanup_expired_post_images(10)

        self.assertEqual(first_summary.failed, 1)
        self.assertTrue(first_locked.rolled_back)
        self.assertEqual(second_summary.deleted, 1)

    def test_repeated_cleanup_is_idempotent(self):
        first_candidate, first_locked = self._connections(expired_row())
        second_candidate = FakeConnection(FakeCursor(fetchall_rows=[]))

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[first_candidate, first_locked, second_candidate],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage",
            return_value=None,
        ):
            first_summary = cleanup_expired_post_images(10)
            second_summary = cleanup_expired_post_images(10)

        self.assertEqual(first_summary.deleted, 1)
        self.assertEqual(second_summary.processed, 0)

    def test_cleanup_and_post_claim_are_serialized_by_upload_lock(self):
        state = ConcurrentCleanupState()
        candidate = FakeConnection(FakeCursor(fetchall_rows=[(UPLOAD_ID,)]))
        locked = ConcurrentCleanupConnection(state)
        post_started = Event()
        post_claimed = []
        post_threads = []

        def post_claim():
            post_started.set()
            with state.lock:
                post_claimed.append(not state.deleted)

        def delete_storage(_storage_path):
            post_thread = Thread(target=post_claim)
            post_threads.append(post_thread)
            post_thread.start()
            self.assertTrue(post_started.wait(1))
            post_thread.join(1)
            self.assertTrue(post_thread.is_alive())

        with patch(
            "app.services.post_image_cleanup.get_connection",
            side_effect=[candidate, locked],
        ), patch(
            "app.services.post_image_cleanup.delete_post_image_storage",
            side_effect=delete_storage,
        ):
            summary = cleanup_expired_post_images(10)

        post_threads[0].join(1)
        self.assertEqual(summary.deleted, 1)
        self.assertEqual(post_claimed, [False])


if __name__ == "__main__":
    unittest.main()
