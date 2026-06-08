"""Timezone utilities for E-Zyro.

All timestamps are stored as naive UTC in the database.
These helpers convert to Lima (UTC-5 / America/Lima) for API responses
so that the mobile app always receives Peru-local times.
"""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

LIMA = ZoneInfo("America/Lima")


def to_lima(dt: datetime | None) -> datetime | None:
    """Convert a naive-UTC datetime to Lima local time (naive)."""
    if dt is None:
        return None
    return dt.replace(tzinfo=timezone.utc).astimezone(LIMA).replace(tzinfo=None)


def fmt_lima(dt: datetime | None, fmt: str = "%Y-%m-%d %H:%M") -> str:
    """Format a naive-UTC datetime as a Lima-local string.
    Returns empty string if dt is None (mirrors the existing strftime pattern).
    """
    lima = to_lima(dt)
    return lima.strftime(fmt) if lima else ""


def fmt_lima_iso(dt: datetime | None) -> str | None:
    """Return a naive Lima-local ISO-8601 string, or None."""
    lima = to_lima(dt)
    return lima.isoformat() if lima else None
