"""App pauses left behind: apps Family Link holds at Hearth's 1-minute pause with no record of the pause
(hearth.release_stray_pauses; docs/home-assistant-integration.md, Pause and locks).

Family Link's pause_app keeps the setting each app had before its pause and resume_app puts it back. When that record
is lost or wrong (a pause that read stale settings right after a resume and kept the pause itself, 1 minute, as the
setting to come back to), an app stays at 1 minute after Hearth has let go of it, and nothing puts it back.

A stray pause is an app of the kid's that:
- Family Link lists with a 1-minute limit that is on (With time limits, read whole: never from a list cut short),
- isn't in Family Link's own record of pauses (paused_apps),
- isn't blocked (Blocked apps, read whole too: writing a limit back can lift a block, which is why Family Link's own
  resume_app leaves a blocked app alone),
- Hearth doesn't hold now, nor may hold (a pause call that failed part-way: enforce.py's maybe_paused),
- and Hearth paused itself in the last LOOK_BACK (its action log: a Family Link hold of the app).

Nothing is read for JUST_RESUMED after Hearth let go of a Family Link hold of the kid's: the list may still show the
pause of an app that was resumed a moment ago, and a limit written then would replace the setting just put back.

Each goes back to no app limit (-1, the device's limits apply), or to the minutes given for it, through
familylink.set_app_daily_limit, recorded in the action log, so outside_apps.py doesn't tell the adults about it.
dry_run only says which.
"""

from __future__ import annotations

from datetime import timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .activity import HOLD_END, HOLD_START, call_service

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)
LOOK_BACK = timedelta(days=7)
# How long after Hearth let go of a Family Link hold the With time limits list may still show its pauses (Family Link
# is read once a minute, and a resume of many apps takes a while to show)
JUST_RESUMED = timedelta(minutes=3)
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
    blocked = fl.app_lists(household.hass, child)[1]
    if blocked is None:
        # Not known which apps are blocked: a limit written to one of them could unblock it
        raise ServiceValidationError("Family Link's list of blocked apps isn't known or is cut short: try again later")
    now = dt_util.utcnow()
    for record in household.activity.query(person, HOLD_END, since=now - JUST_RESUMED, limit=5000):
        if record.get("by") == "family_link":
            raise ServiceValidationError(
                "Hearth let go of a Family Link hold a moment ago and the list may not show it yet: "
                "try again in a few minutes"
            )
    at_pause = {
        a["package"]
        for a in state.attributes["apps"]
        if isinstance(a, dict)
        and a.get("package")
        and a.get("limit_minutes") == PAUSE_MINUTES
        and a.get("enabled", True)
    }
    recorded = {p.get("package") for p in state.attributes.get("paused_apps") or [] if isinstance(p, dict)}
    # With the apps a pause call may have paused without Hearth holding them for sure
    held = household.enforcement.family_link_holding(person)
    since = now - LOOK_BACK
    hearths: set[str] = set()
    for record in household.activity.query(person, HOLD_START, since=since, limit=5000):
        if record.get("by") == "family_link":
            hearths |= set(record.get("target") or [])
    return sorted((at_pause & hearths) - recorded - held - blocked)


async def release(household: Household, person: str, limits: dict[str, int], dry_run: bool) -> dict[str, Any]:
    """Puts each stray pause back (to no limit, or the minutes in [limits]); says which, and any that failed."""
    found = stray_pauses(household, person)
    planned = {package: int(limits.get(package, NO_LIMIT)) for package in found}
    if dry_run:
        return {"person": person, "dry_run": True, "apps": planned}
    child = household.family_link_child(person)
    # Taken before the calls: the sensor may be gone by the end (Family Link reloading), and what was done is still said
    sensor = _limits_sensor(household, child)
    sensor_id = sensor.entity_id if sensor is not None else None
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
        except Exception as err:  # noqa: BLE001 - Family Link's own errors (a session that expired) are plain Exceptions
            failed[package] = (str(err) or type(err).__name__)[:200]
            continue
        done[package] = minutes
    try:
        household.enforcement.refresh_soon(sensor_id)
    except Exception:  # noqa: BLE001 - the work is done: a refresh that can't be asked for mustn't lose the answer
        _LOGGER.warning("Hearth couldn't ask Family Link for fresh app limits after releasing stray pauses")
    return {"person": person, "dry_run": False, "apps": done, "failed": failed}
