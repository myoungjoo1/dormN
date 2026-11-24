import math
import os
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Any, Mapping
from zoneinfo import ZoneInfo


KOREA_TIMEZONE = ZoneInfo("Asia/Seoul")
EARTH_RADIUS_METERS = 6_371_000.0
VERIFICATION_START_TIME = time(0, 0)
VERIFICATION_END_TIME = time(3, 0)
LOCATION_STATUS_NOT_STARTED = "NOT_STARTED"
LOCATION_STATUS_IN_PROGRESS = "IN_PROGRESS"
LOCATION_STATUS_COMPLETED = "COMPLETED"
LOCATION_STATUS_OUT_OF_RANGE = "OUT_OF_RANGE"
LOCATION_STATUS_EXPIRED = "EXPIRED"


class LocationVerificationConfigurationError(ValueError):
    """Raised when a required location policy is absent or invalid."""


class LocationCheckRejected(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class LocationVerificationPolicy:
    latitude: float
    longitude: float
    radius_meters: float
    max_accuracy_meters: float
    min_dwell_minutes: float
    min_checks: int
    min_check_interval_seconds: float

    @property
    def minimum_dwell_seconds(self) -> int:
        return math.ceil(self.min_dwell_minutes * 60)

    @property
    def minimum_check_interval_seconds(self) -> int:
        return math.ceil(self.min_check_interval_seconds)


@dataclass
class LocationProgress:
    verification_date: date | None = None
    status: str = LOCATION_STATUS_NOT_STARTED
    valid_check_count: int = 0
    first_valid_at: datetime | None = None
    last_valid_at: datetime | None = None
    last_check_at: datetime | None = None
    completed_at: datetime | None = None

    @classmethod
    def from_row(cls, row: Mapping[str, Any] | None) -> "LocationProgress":
        if row is None:
            return cls()
        return cls(
            verification_date=row.get("verification_date"),
            status=row.get("status", LOCATION_STATUS_NOT_STARTED),
            valid_check_count=row.get("valid_check_count", 0),
            first_valid_at=row.get("first_valid_at"),
            last_valid_at=row.get("last_valid_at"),
            last_check_at=row.get("last_check_at"),
            completed_at=row.get("completed_at"),
        )

    def reset_for_date(self, verification_date: date) -> None:
        self.verification_date = verification_date
        self.status = LOCATION_STATUS_NOT_STARTED
        self.valid_check_count = 0
        self.first_valid_at = None
        self.last_valid_at = None
        self.completed_at = None
        self.last_check_at = None


def _required_value(environment: Mapping[str, str], name: str) -> str:
    value = environment.get(name, "").strip()
    if not value:
        raise LocationVerificationConfigurationError(
            f"Missing required location verification setting: {name}"
        )
    return value


def _parse_float(environment: Mapping[str, str], name: str) -> float:
    value = _required_value(environment, name)
    try:
        parsed = float(value)
    except ValueError as exc:
        raise LocationVerificationConfigurationError(
            f"Invalid location verification setting: {name}"
        ) from exc
    if not math.isfinite(parsed):
        raise LocationVerificationConfigurationError(
            f"Invalid location verification setting: {name}"
        )
    return parsed


def _parse_int(environment: Mapping[str, str], name: str) -> int:
    value = _required_value(environment, name)
    try:
        return int(value)
    except ValueError as exc:
        raise LocationVerificationConfigurationError(
            f"Invalid location verification setting: {name}"
        ) from exc


def get_location_verification_policy(
    environment: Mapping[str, str] | None = None,
) -> LocationVerificationPolicy:
    values = os.environ if environment is None else environment
    policy = LocationVerificationPolicy(
        latitude=_parse_float(values, "DORM_LOCATION_LATITUDE"),
        longitude=_parse_float(values, "DORM_LOCATION_LONGITUDE"),
        radius_meters=_parse_float(values, "DORM_LOCATION_RADIUS_METERS"),
        max_accuracy_meters=_parse_float(
            values,
            "DORM_LOCATION_MAX_ACCURACY_METERS",
        ),
        min_dwell_minutes=_parse_float(values, "DORM_LOCATION_MIN_DWELL_MINUTES"),
        min_checks=_parse_int(values, "DORM_LOCATION_MIN_CHECKS"),
        min_check_interval_seconds=_parse_float(
            values,
            "DORM_LOCATION_MIN_CHECK_INTERVAL_SECONDS",
        ),
    )

    if not -90 <= policy.latitude <= 90:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_LATITUDE must be between -90 and 90"
        )
    if not -180 <= policy.longitude <= 180:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_LONGITUDE must be between -180 and 180"
        )
    if policy.radius_meters <= 0:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_RADIUS_METERS must be greater than 0"
        )
    if policy.max_accuracy_meters < 0:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_MAX_ACCURACY_METERS must not be negative"
        )
    if policy.min_dwell_minutes < 0:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_MIN_DWELL_MINUTES must not be negative"
        )
    if policy.min_checks < 1:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_MIN_CHECKS must be at least 1"
        )
    if policy.min_check_interval_seconds < 0:
        raise LocationVerificationConfigurationError(
            "DORM_LOCATION_MIN_CHECK_INTERVAL_SECONDS must not be negative"
        )
    return policy


def to_korea_time(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("Location verification timestamps must be timezone-aware")
    return value.astimezone(KOREA_TIMEZONE)


def is_verification_window_open(value: datetime) -> bool:
    local_time = to_korea_time(value).time()
    return VERIFICATION_START_TIME <= local_time < VERIFICATION_END_TIME


def haversine_distance_meters(
    latitude: float,
    longitude: float,
    target_latitude: float,
    target_longitude: float,
) -> float:
    latitude_delta = math.radians(target_latitude - latitude)
    longitude_delta = math.radians(target_longitude - longitude)
    latitude_a = math.radians(latitude)
    latitude_b = math.radians(target_latitude)

    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(latitude_a)
        * math.cos(latitude_b)
        * math.sin(longitude_delta / 2) ** 2
    )
    # Floating-point rounding can produce a value just above 1 at the limit.
    haversine = min(1.0, max(0.0, haversine))
    return 2 * EARTH_RADIUS_METERS * math.asin(math.sqrt(haversine))


def is_within_allowed_radius(
    latitude: float,
    longitude: float,
    policy: LocationVerificationPolicy,
) -> bool:
    distance = haversine_distance_meters(
        latitude,
        longitude,
        policy.latitude,
        policy.longitude,
    )
    return distance <= policy.radius_meters


def _elapsed_seconds(start: datetime | None, end: datetime | None) -> int:
    if start is None or end is None:
        return 0
    return max(0, int((end - start).total_seconds()))


def apply_location_check(
    progress: LocationProgress,
    *,
    now: datetime,
    policy: LocationVerificationPolicy,
    in_allowed_radius: bool,
) -> str:
    """Apply one server-timestamped check to an in-memory progress row."""
    local_date = to_korea_time(now).date()

    if progress.status == LOCATION_STATUS_COMPLETED:
        return "GPS stay verification is already complete"

    if progress.verification_date != local_date:
        progress.reset_for_date(local_date)

    if progress.last_check_at is not None:
        elapsed = (now - progress.last_check_at).total_seconds()
        if elapsed < policy.minimum_check_interval_seconds:
            raise LocationCheckRejected(
                "LOCATION_CHECK_TOO_SOON",
                "Location checks must be separated by the minimum interval",
            )

    progress.last_check_at = now

    if not in_allowed_radius:
        progress.status = LOCATION_STATUS_OUT_OF_RANGE
        progress.valid_check_count = 0
        progress.first_valid_at = None
        progress.last_valid_at = None
        progress.completed_at = None
        return "The current location is outside the verification area"

    progress.valid_check_count += 1
    progress.first_valid_at = progress.first_valid_at or now
    progress.last_valid_at = now
    dwell_seconds = _elapsed_seconds(progress.first_valid_at, progress.last_valid_at)
    if (
        progress.valid_check_count >= policy.min_checks
        and dwell_seconds >= policy.minimum_dwell_seconds
    ):
        progress.status = LOCATION_STATUS_COMPLETED
        progress.completed_at = now
        return "GPS stay verification is complete"

    progress.status = LOCATION_STATUS_IN_PROGRESS
    progress.completed_at = None
    return "Additional location checks are required"


def build_location_verification_response(
    progress: LocationProgress,
    *,
    policy: LocationVerificationPolicy,
    now: datetime,
    message: str | None = None,
) -> dict[str, Any]:
    local_date = to_korea_time(now).date()
    status = progress.status
    if (
        progress.verification_date is not None
        and progress.verification_date != local_date
        and status != LOCATION_STATUS_COMPLETED
    ):
        status = LOCATION_STATUS_EXPIRED

    dwell_seconds = _elapsed_seconds(
        progress.first_valid_at,
        progress.last_valid_at,
    )
    interval_satisfied = (
        progress.last_check_at is None
        or (now - progress.last_check_at).total_seconds()
        >= policy.minimum_check_interval_seconds
    )
    next_check_at = None
    if status != LOCATION_STATUS_COMPLETED and progress.last_check_at is not None:
        candidate = progress.last_check_at + timedelta(
            seconds=policy.minimum_check_interval_seconds
        )
        if candidate > now:
            next_check_at = candidate

    dwell_satisfied = dwell_seconds >= policy.minimum_dwell_seconds
    return {
        "status": status,
        "valid_check_count": progress.valid_check_count,
        "required_check_count": policy.min_checks,
        "first_valid_check_at": progress.first_valid_at,
        "last_valid_check_at": progress.last_valid_at,
        "last_check_at": progress.last_check_at,
        "dwell_seconds": dwell_seconds,
        "minimum_dwell_seconds": policy.minimum_dwell_seconds,
        "dwell_satisfied": dwell_satisfied,
        "interval_satisfied": interval_satisfied,
        "additional_check_required": status != LOCATION_STATUS_COMPLETED,
        "eligible_time_start": "00:00",
        "eligible_time_end": "03:00",
        "eligible_time_zone": "Asia/Seoul",
        "next_check_at": next_check_at,
        "message": message,
    }
