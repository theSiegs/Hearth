"""Each kid's time today as a Glint Panel's kid card shows it (docs/contracts/panel-config.md, Kid time): read only,
served over the panel's own secret (`<d>/panel/kids/subscribe`), so the panel never builds entity ids from names.

What it holds is what a household's shared screen may show of a kid: today's time (the time model's `time`, without
the adults' names in its origins), whether they're locked and why, the schedule's mode, school today and bedtime.
Never a place, a PIN, a request's note or anything to change it with.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

from homeassistant.util import dt as dt_util

from .const import CONF_ROLES
from .counting import ALL

# The time model's fields a kid card needs (household.time_view); origins (who gave what) stay with the adults' apps
TIME_KEYS = (
    "today_left", "today_minutes", "base_minutes", "bonus", "bonus_left", "used", "unlimited", "unlimited_today",
    "text", "categories", "by_category", "uncounted", "category_bonuses",
)


def kids(household) -> list[str]:
    """The kids on Hearth's page, else everyone the household maps something to that isn't an adult."""
    roles: dict[str, str] = dict(household.options.get(CONF_ROLES) or {})
    named = sorted(p for p, role in roles.items() if role == "kid")
    return named or [p for p in household.people() if roles.get(p) != "adult"]


def kid_view(household, person: str) -> dict[str, Any]:
    day = household.days.get(person)
    time = household.time_view(person)
    locks = household._locks_document(person, day)
    scheduled = household.schedule_view(person)
    return {
        "person": person,
        "name": household.person_name(person),
        "time": {key: time.get(key) for key in TIME_KEYS},
        # Daily time's minutes used today while Unlimited: used, not counted (time.used is the counted part)
        "unlimited_minutes": max(
            0, household.day_used_minutes(day).get(ALL, 0) - household.day_minutes(day).get(ALL, 0)
        ),
        "locked": bool(day and day.locked),
        # {by, kind (bedtime | school_time | pause | other), kinds, until} while something locks them, else null
        "lock": locks.get("lock"),
        "pause": locks.get("pause"),
        "bedtime_lifted": locks.get("bedtime_lifted"),
        "next_lock": locks.get("next_lock"),
        # The weekly schedule's mode now ({id, name, allows, since, until, closed}), null while it has no changes
        "mode": (scheduled or {}).get("mode"),
        # school | half_day | off | home_today, with today's School time window
        "school_today": household.school_today(person),
        # {start: tonight, end: this morning's wake}, local; null when nothing says
        "bedtime": household.bedtime_today(person),
    }


def kids_document(household) -> dict[str, Any]:
    """{"kids": [kid_view...], "at", "version"}: version changes exactly when a kid's part does."""
    body: dict[str, Any] = {"kids": [kid_view(household, p) for p in kids(household)]}
    body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True, default=str).encode()).hexdigest()[:16]
    body["at"] = dt_util.now().isoformat()
    return body
