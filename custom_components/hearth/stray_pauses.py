"""App pauses left behind: apps Family Link holds at Hearth's 1-minute pause with no record of the pause
(hearth.release_stray_pauses; docs/home-assistant-integration.md, Pause and locks).

Family Link's pause_app keeps the setting each app had before its pause and resume_app puts it back. When that record
is lost or wrong (a pause that read stale settings right after a resume and kept the pause itself, 1 minute, as the
setting to come back to), an app stays at 1 minute after Hearth has let go of it, and nothing puts it back.

A stray pause is an app of the kid's that:
- Family Link lists with a 1-minute limit (With time limits, read whole: never from a list cut short),
- isn't in Family Link's own record of pauses (paused_apps),
- Hearth doesn't hold now,
- and Hearth paused itself in the last LOOK_BACK (its action log: a Family Link hold of the app).

Each goes back to no app limit (-1, the device's limits apply), or to the minutes given for it, through
familylink.set_app_daily_limit, recorded in the action log, so outside_apps.py doesn't tell the adults about it.
dry_run only says which.
"""

from __future__ import annotations

from datetime import timedelta
from typing import TYPE_CHECKING, Any

from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.util import dt as dt_util

from .activity import HOLD_START, call_service

if TYPE_CHECKING:
    from .household import Household

LOOK_BACK = timedelta(days=7)
PAUSE_MINUTES = 1
NO_LIMIT = -1


def _limits_sensor(household: Household, child: str) -> Any:
    for state in household.hass.states.async_all("sensor"):
        if state.entity_id.endswith("_apps_with_time_limits") and str(state.attributes.get("child_id")) == child:
            return state
    return None


def stray_pauses(household: Household, person: str) -> list[str]:
    """The person's stray pauses (see the module), sorted."""
    child = household.family_link_child(person)
    if child is None:
        raise ServiceValidationError(f"No Family Link for {household.person_name(person)}")
    state = _limits_sensor(household, child)
    if state is None or not isinstance(state.attributes.get("apps"), list):
        raise ServiceValidationError("Family Link's apps with time limits aren't known yet")
    if state.attributes.get("truncated"):
        raise ServiceValidationError("Family Link's list of apps with time limits is cut short: try again later")
    at_pause = {
        a["package"]
        for a in state.attributes["apps"]
        if isinstance(a, dict) and a.get("package") and a.get("limit_minutes") == PAUSE_MINUTES
    }
    recorded = {p.get("package") for p in state.attributes.get("paused_apps") or [] if isinstance(p, dict)}
    held = set(household.enforcement.held_for(person).get("family_link", {}).get("held", []))
    since = dt_util.utcnow() - LOOK_BACK
    hearths: set[str] = set()
    for record in household.activity.query(person, HOLD_START, since=since, limit=5000):
        if record.get("by") == "family_link":
            hearths |= set(record.get("target") or [])
    return sorted((at_pause & hearths) - recorded - held)


async def release(household: Household, person: str, limits: dict[str, int], dry_run: bool) -> dict[str, Any]:
    """Puts each stray pause back (to no limit, or the minutes in [limits]); says which, and any that failed."""
    found = stray_pauses(household, person)
    planned = {package: int(limits.get(package, NO_LIMIT)) for package in found}
    if dry_run:
        return {"person": person, "dry_run": True, "apps": planned}
    child = household.family_link_child(person)
    done: dict[str, int] = {}
    failed: dict[str, str] = {}
    for package, minutes in planned.items():
        try:
            await call_service(
                household.hass,
                "familylink",
                "set_app_daily_limit",
                {"child_id": child, "package_name": package, "minutes": minutes},
                blocking=True,
                person=person,
                why="stray_pause",
            )
        except (HomeAssistantError, ValueError) as err:
            failed[package] = str(err)[:200]
            continue
        done[package] = minutes
    household.enforcement.refresh_soon(_limits_sensor(household, child).entity_id)
    return {"person": person, "dry_run": False, "apps": done, "failed": failed}
