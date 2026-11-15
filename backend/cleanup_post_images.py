import argparse
import sys

from app.services.post_image_cleanup import (
    DEFAULT_CLEANUP_LIMIT,
    MAX_CLEANUP_LIMIT,
    cleanup_expired_post_images,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Delete expired, unclaimed DormN post images"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_CLEANUP_LIMIT,
        help=f"maximum uploads to inspect (1-{MAX_CLEANUP_LIMIT})",
    )
    args = parser.parse_args()

    try:
        summary = cleanup_expired_post_images(args.limit)
    except ValueError as exc:
        parser.error(str(exc))
    except Exception:
        print(
            "Cleanup could not complete because the database or Storage is unavailable.",
            file=sys.stderr,
        )
        return 1

    print(
        "Cleanup complete: "
        f"processed={summary.processed}, "
        f"deleted={summary.deleted}, "
        f"skipped={summary.skipped}, "
        f"failed={summary.failed}"
    )
    return 0 if summary.failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
