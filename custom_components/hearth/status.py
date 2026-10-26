"""The TV status a Hearth TV posts (the same JSON as its webhook post, see docs/home-assistant.md), made safe.

Everything a TV sends is untrusted: only known fields are kept, text is shortened and stripped of control characters,
numbers are bounded, and nothing is ever used as a template.
"""

from __future__ import annotations

import re
from typing import Any

from .const import APP_CATEGORIES, TV_STATES

_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")

MAX_TEXT = 255
MAX_PROFILES = 20
MAX_APPS = 100
MAX_SECONDS_PER_DAY = 24 * 60 * 60

_TEXT_FIELDS = (
    "app",
    "app_package",
    "media_app",
    "media_title",
    "media_artist",
    "media_album",
    "profile",
    "profile_id",
    "screen_time_reason",
    "screen_time_text",
    "screen_time_unlocks_at",
    "screen_time_unlocks_at_iso",
    "screen_time_event",
    "day",
)
_BOOL_FIELDS = ("now_playing_available", "kids_profile", "screen_time_up")
_INT_FIELDS = {
    "media_duration_s": (0, 7 * MAX_SECONDS_PER_DAY),
    "screen_time_minutes_left": (0, 24 * 60),
    "screen_time_seen_at": (0, 2**53),
    "screen_time_event_at": (0, 2**53),
    "seconds_today": (0, MAX_SECONDS_PER_DAY),
}


def text(value: Any, limit: int = MAX_TEXT) -> str | None:
    """A string without control characters, at most [limit] long; None for anything else or an empty one."""
    if not isinstance(value, str):
        return None
    cleaned = _CONTROL.sub("", value).strip()[:limit]
    return cleaned or None


def number(value: Any, low: int, high: int) -> int | None:
    """A whole number within [low, high] (a float is rounded down); None for anything else."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value != value:  # NaN
        return None
    whole = int(value)
    return whole if low <= whole <= high else None


def _seconds_by_app(value: Any) -> dict[str, int]:
    """{"<package>": seconds}, at most MAX_APPS of them."""
    if not isinstance(value, dict):
        return {}
    out: dict[str, int] = {}
    for package, seconds in value.items():
        if len(out) >= MAX_APPS:
            break
        name = text(package, 128)
        count = number(seconds, 0, MAX_SECONDS_PER_DAY)
        if name and count is not None:
            out[name] = count
    return out


def _usage_today(value: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for profile_id, usage in value.items():
        if len(out) >= MAX_PROFILES:
            break
        key = text(profile_id, 128)
        if not key or not isinstance(usage, dict):
            continue
        out[key] = {
            "profile_name": text(usage.get("profile_name")),
            "seconds": number(usage.get("seconds"), 0, MAX_SECONDS_PER_DAY) or 0,
            "apps": _seconds_by_app(usage.get("apps")),
            "playing": _seconds_by_app(usage.get("playing")),
        }
    return out


def clean_status(raw: Any) -> dict[str, Any] | None:
    """The status with only known, safe fields; None when [raw] isn't a JSON object."""
    if not isinstance(raw, dict):
        return None
    status: dict[str, Any] = {}
    screen = raw.get("screen")
    status["screen"] = screen if screen in ("on", "off") else None
    state = raw.get("state")
    status["state"] = state if state in TV_STATES else None
    for field in _TEXT_FIELDS:
        status[field] = text(raw.get(field))
    for field in _BOOL_FIELDS:
        value = raw.get(field)
        status[field] = value if isinstance(value, bool) else None
    for field, (low, high) in _INT_FIELDS.items():
        status[field] = number(raw.get(field), low, high)
    allowed = raw.get("allowed_apps")
    status["allowed_apps"] = (
        [name for name in (text(a, 128) for a in allowed[:MAX_APPS]) if name] if isinstance(allowed, list) else None
    )
    status["app_seconds_today"] = _seconds_by_app(raw.get("app_seconds_today"))
    status["playing_seconds_today"] = _seconds_by_app(raw.get("playing_seconds_today"))
    status["usage_today"] = _usage_today(raw.get("usage_today"))
    status["app_categories"] = _categories(raw.get("app_categories"))
    return status


def _categories(value: Any) -> dict[str, str]:
    """{"<package>": "game" | "video" | ...}: what Android says each app is, at most MAX_APPS."""
    if not isinstance(value, dict):
        return {}
    out: dict[str, str] = {}
    for package, category in value.items():
        if len(out) >= MAX_APPS:
            break
        name = text(package, 128)
        if name and category in APP_CATEGORIES:
            out[name] = category
    return out
