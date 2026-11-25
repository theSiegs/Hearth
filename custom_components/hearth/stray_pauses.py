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

Family Safety (Xbox and Windows apps) keeps its own record of each pause (the Applications sensor's paused_apps), so a
pause of Hearth's left behind there is resumed with that record (resume_app puts back what the app had). A stray
Family Safety pause is an app that:
- Family Safety's record shows paused by its pause_app and still blocked by it ("ours": nothing a parent blocked is
  under it, Family Safety skips an app already blocked), from whole lists only (every Applications sensor of the kid,
  none cut short, each with paused_apps),
- Hearth doesn't hold now, nor may hold (enforce.py's fs_maybe_paused), nor blocks itself (app_blocks.py's
  fs_applied),
- and Hearth asked Family Safety to pause in the last LOOK_BACK (its action log's calls, every app of a call).
Not within JUST_RESUMED of Hearth letting go of a Family Safety hold of the kid's either. A pause a parent made from
Family Safety's own card of an app Hearth paused that week can't be told from Hearth's: dry_run says which first.
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


def fs_stray_pauses(household: Household, person: str) -> list[str]:
    """The person's stray Family Safety pauses (see the module), sorted."""
    from .enforce import FAMILY_SAFETY, FS_DOMAIN, FS_HOLD_OURS, Held, _holding, fs_applications, fs_row_app

    entity_id = household.blocks.fs_target_of(person)
    if entity_id is None:
        raise ServiceValidationError(f"No Family Safety for {household.person_name(person)}")
    states = fs_applications(household.hass, entity_id)
    if not states:
        raise ServiceValidationError("Family Safety's Applications list isn't known yet")
    ours: set[str] = set()
    for state in states:
        rows = state.attributes.get("paused_apps")
        if state.attributes.get("truncated") or not isinstance(state.attributes.get("applications"), list):
            raise ServiceValidationError("Family Safety's Applications list is cut short: try again later")
        if not isinstance(rows, list):
            raise ServiceValidationError("This Family Safety keeps no record of its pauses (update it)")
        ours |= {app for row in rows if (app := fs_row_app(row)) and row.get("paused") == FS_HOLD_OURS}
    now = dt_util.utcnow()
    for record in household.activity.query(person, HOLD_END, since=now - JUST_RESUMED, limit=5000):
        if record.get("by") == FAMILY_SAFETY:
            raise ServiceValidationError(
                "Hearth let go of a Family Safety hold a moment ago and the list may not show it yet: "
                "try again in a few minutes"
            )
    held = _holding(household.enforcement.held.get(f"{FAMILY_SAFETY}|{person}") or Held())
    blocked = set(household.blocks.fs_applied.get(person, {}))
    since = now - LOOK_BACK
    hearths = {app for app in ours if household.activity.own_call({f"{FS_DOMAIN}.pause_app"}, app, since)}
    return sorted(hearths - held - blocked)


async def release_fs(household: Household, person: str, dry_run: bool) -> dict[str, Any]:
    """Resumes each stray Family Safety pause (Family Safety puts back what the app had); says which, and any that
    failed. A list that can't be read says why instead of raising (the Family Link part's answer stays)."""
    try:
        found = fs_stray_pauses(household, person)
    except ServiceValidationError as err:
        return {"apps": [], "error": str(err)}
    if dry_run or not found:
        return {"apps": found, **({"dry_run": True} if dry_run else {"failed": {}})}
    entity_id = household.blocks.fs_target_of(person)
    target = {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}
    try:
        await call_service(
            household.hass, "microsoft_family_safety", "resume_app", {**target, "apps": found}, blocking=True,
            person=person, why="stray_pause",
        )
    except Exception as err:  # noqa: BLE001 - said in the answer
        return {"apps": [], "failed": {app: (str(err) or type(err).__name__)[:200] for app in found}}
    try:
        household.enforcement.refresh_soon(entity_id)
    except Exception:  # noqa: BLE001 - the work is done
        _LOGGER.warning("Hearth couldn't ask Family Safety for fresh app lists after releasing stray pauses")
    return {"apps": found, "failed": {}}
