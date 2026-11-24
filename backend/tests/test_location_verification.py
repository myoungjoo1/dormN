import math
import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException
from pydantic import ValidationError

from app.routers.users import check_my_location
from app.schemas.users import LocationCheckRequest
from app.services.location_verification import (
    LOCATION_STATUS_COMPLETED,
    LOCATION_STATUS_IN_PROGRESS,
    LOCATION_STATUS_OUT_OF_RANGE,
    LocationCheckRejected,
    LocationProgress,
    LocationVerificationConfigurationError,
    LocationVerificationPolicy,
    apply_location_check,
    get_location_verification_policy,
    haversine_distance_meters,
    is_verification_window_open,
    is_within_allowed_radius,
)


USER_ID = UUID("11111111-1111-1111-1111-111111111111")
UTC_MIDNIGHT_KST = datetime(2026, 11, 23, 15, 0, tzinfo=timezone.utc)


POLICY = LocationVerificationPolicy(
    latitude=37.5665,
    longitude=126.9780,
    radius_meters=100,
    max_accuracy_meters=30,
    min_dwell_minutes=10,
    min_checks=3,
    min_check_interval_seconds=60,
)


class FakeCursor:
    def __init__(self, row=None):
        self.row = row
        self.calls = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, query, params):
        self.calls.append((query, params))

    def fetchone(self):
        return self.row


class FakeConnection:
    def __init__(self, row=None):
        self.cursor_instance = FakeCursor(row)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def cursor(self, row_factory=None):
        return self.cursor_instance


def progress_row(current_date=date(2026, 11, 24), status="NOT_STARTED"):
    return {
        "verification_date": current_date,
        "status": status,
        "valid_check_count": 0,
        "first_valid_at": None,
        "last_valid_at": None,
        "last_check_at": None,
        "completed_at": None,
    }


class LocationPolicyTest(unittest.TestCase):
    def test_missing_policy_setting_fails_closed(self):
        with self.assertRaises(LocationVerificationConfigurationError):
            get_location_verification_policy(
                {"DORM_LOCATION_LATITUDE": "37.5"}
            )

    def test_same_coordinate_is_inside(self):
        self.assertEqual(
            haversine_distance_meters(
                POLICY.latitude,
                POLICY.longitude,
                POLICY.latitude,
                POLICY.longitude,
            ),
            0,
        )
        self.assertTrue(
            is_within_allowed_radius(POLICY.latitude, POLICY.longitude, POLICY)
        )

    def test_radius_boundary_is_inclusive(self):
        distance = haversine_distance_meters(
            POLICY.latitude,
            POLICY.longitude,
            POLICY.latitude + 0.001,
            POLICY.longitude,
        )
        boundary_policy = LocationVerificationPolicy(
            **{
                **POLICY.__dict__,
                "radius_meters": distance,
            }
        )
        self.assertTrue(
            is_within_allowed_radius(
                POLICY.latitude + 0.001,
                POLICY.longitude,
                boundary_policy,
            )
        )
        outside_policy = LocationVerificationPolicy(
            **{
                **POLICY.__dict__,
                "radius_meters": distance - 0.01,
            }
        )
        self.assertFalse(
            is_within_allowed_radius(
                POLICY.latitude + 0.001,
                POLICY.longitude,
                outside_policy,
            )
        )

    def test_verification_window_uses_korea_time_start_inclusive_end_exclusive(self):
        before_start = datetime(2026, 11, 23, 14, 59, 59, tzinfo=timezone.utc)
        at_start = datetime(2026, 11, 23, 15, 0, tzinfo=timezone.utc)
        at_end = datetime(2026, 11, 23, 18, 0, tzinfo=timezone.utc)

        self.assertFalse(is_verification_window_open(before_start))
        self.assertTrue(is_verification_window_open(at_start))
        self.assertFalse(is_verification_window_open(at_end))


class LocationRequestValidationTest(unittest.TestCase):
    def test_invalid_coordinates_and_accuracy_are_rejected(self):
        for values in (
            {"latitude": 91, "longitude": 126, "accuracy_meters": 10},
            {"latitude": 37, "longitude": -181, "accuracy_meters": 10},
            {"latitude": 37, "longitude": 126, "accuracy_meters": -1},
            {"latitude": math.nan, "longitude": 126, "accuracy_meters": 10},
        ):
            with self.assertRaises(ValidationError):
                LocationCheckRequest(**values)


class LocationProgressTest(unittest.TestCase):
    def test_minimum_checks_and_dwell_time_are_both_required(self):
        progress = LocationProgress()
        first = UTC_MIDNIGHT_KST
        second = first + timedelta(minutes=5)
        third = first + timedelta(minutes=10)

        apply_location_check(
            progress,
            now=first,
            policy=POLICY,
            in_allowed_radius=True,
        )
        apply_location_check(
            progress,
            now=second,
            policy=POLICY,
            in_allowed_radius=True,
        )
        self.assertEqual(progress.status, LOCATION_STATUS_IN_PROGRESS)
        self.assertEqual(progress.valid_check_count, 2)

        apply_location_check(
            progress,
            now=third,
            policy=POLICY,
            in_allowed_radius=True,
        )
        self.assertEqual(progress.status, LOCATION_STATUS_COMPLETED)
        self.assertEqual(progress.valid_check_count, 3)

    def test_short_interval_repeated_check_is_rejected(self):
        progress = LocationProgress()
        apply_location_check(
            progress,
            now=UTC_MIDNIGHT_KST,
            policy=POLICY,
            in_allowed_radius=True,
        )

        with self.assertRaises(LocationCheckRejected) as context:
            apply_location_check(
                progress,
                now=UTC_MIDNIGHT_KST + timedelta(seconds=30),
                policy=POLICY,
                in_allowed_radius=True,
            )

        self.assertEqual(context.exception.code, "LOCATION_CHECK_TOO_SOON")

    def test_out_of_range_check_resets_valid_stay_progress(self):
        progress = LocationProgress()
        apply_location_check(
            progress,
            now=UTC_MIDNIGHT_KST,
            policy=POLICY,
            in_allowed_radius=True,
        )
        apply_location_check(
            progress,
            now=UTC_MIDNIGHT_KST + timedelta(minutes=1),
            policy=POLICY,
            in_allowed_radius=False,
        )

        self.assertEqual(progress.status, LOCATION_STATUS_OUT_OF_RANGE)
        self.assertEqual(progress.valid_check_count, 0)
        self.assertIsNone(progress.first_valid_at)
        self.assertIsNone(progress.last_valid_at)

    def test_completed_gps_progress_is_not_changed_by_later_check(self):
        progress = LocationProgress()
        progress.status = LOCATION_STATUS_COMPLETED
        message = apply_location_check(
            progress,
            now=UTC_MIDNIGHT_KST,
            policy=POLICY,
            in_allowed_radius=False,
        )

        self.assertEqual(progress.status, LOCATION_STATUS_COMPLETED)
        self.assertIn("complete", message)


class LocationApiTest(unittest.TestCase):
    def test_accuracy_failure_does_not_write_location_state(self):
        connection = FakeConnection(progress_row())
        request = LocationCheckRequest(
            latitude=POLICY.latitude,
            longitude=POLICY.longitude,
            accuracy_meters=31,
        )
        with patch(
            "app.routers.users.get_location_verification_policy",
            return_value=POLICY,
        ), patch(
            "app.routers.users._utc_now",
            return_value=UTC_MIDNIGHT_KST,
        ), patch(
            "app.routers.users.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                check_my_location(request, USER_ID)

        self.assertEqual(context.exception.code, "GPS_ACCURACY_TOO_LOW")
        self.assertEqual(connection.cursor_instance.calls, [])

    def test_duplicate_requests_use_conflict_and_row_lock_without_dorm_update(self):
        connection = FakeConnection(progress_row())
        request = LocationCheckRequest(
            latitude=POLICY.latitude,
            longitude=POLICY.longitude,
            accuracy_meters=10,
        )
        with patch(
            "app.routers.users.get_location_verification_policy",
            return_value=POLICY,
        ), patch(
            "app.routers.users._utc_now",
            return_value=UTC_MIDNIGHT_KST,
        ), patch(
            "app.routers.users.get_connection",
            return_value=connection,
        ):
            result = check_my_location(request, USER_ID)

        queries = [query for query, _ in connection.cursor_instance.calls]
        self.assertTrue(
            any("ON CONFLICT (user_id) DO NOTHING" in query for query in queries)
        )
        self.assertTrue(any("FOR UPDATE" in query for query in queries))
        self.assertTrue(all("dorm_verified" not in query for query in queries))
        self.assertEqual(result["data"].valid_check_count, 1)

    def test_time_window_closure_marks_incomplete_progress_expired(self):
        row = progress_row(status=LOCATION_STATUS_IN_PROGRESS)
        connection = FakeConnection(row)
        request = LocationCheckRequest(
            latitude=POLICY.latitude,
            longitude=POLICY.longitude,
            accuracy_meters=10,
        )
        after_window = datetime(2026, 11, 23, 18, 0, tzinfo=timezone.utc)
        with patch(
            "app.routers.users.get_location_verification_policy",
            return_value=POLICY,
        ), patch(
            "app.routers.users._utc_now",
            return_value=after_window,
        ), patch(
            "app.routers.users.get_connection",
            return_value=connection,
        ):
            with self.assertRaises(HTTPException) as context:
                check_my_location(request, USER_ID)

        self.assertEqual(
            context.exception.code,
            "LOCATION_VERIFICATION_TIME_WINDOW_CLOSED",
        )
        self.assertTrue(
            any("status = 'EXPIRED'" in query for query, _ in connection.cursor_instance.calls)
        )


if __name__ == "__main__":
    unittest.main()
