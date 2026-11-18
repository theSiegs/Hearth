"""A family pause (dinner time, say) and when a person's locks start and end (docs/home-assistant-integration.md,
Pause and Locks).

hearth.pause holds the chosen people (everyone in the household by default) for some minutes or until a time;
hearth.pause_end lets them go. While paused a person is locked, so a Hearth TV holds their apps as for bedtime, and
their state document says why ("pause": {until, reason}). Their Switch is held too, by the Nintendo enforcer's own
hold (enforce.py). Pauses are kept outside the entry (an options change reloads it) and in a store of their own, so
a restart doesn't end one: they're read back once when Home Assistant starts, those already over left out.

hearth.pause with an app or a group pauses only that, for the chosen people (YouTube and HearthTube, say): its apps
are held as a group out of time is (a Hearth TV and phone, Family Link, Family Safety's Xbox and Windows apps, the
Switch when the Nintendo enforcer covers the group), and an allow doesn't lift it. A person may have several of these besides a family pause; pause_end with the same app or
group ends that one, and pause_end without either ends only the family pause.

A lock entity of Family Link's says when bedtime or school time starts and ends (bedtime_start / bedtime_end,
schooltime_start / schooltime_end, local times): that's "lock" {by, until} while one is on, and "next_lock" {at, by}
for the next one today, so a device can wind down before it. Family Safety's Downtime Active sensors (one per child and
platform) say the same with downtime_start / downtime_end (an older one: bedtime_start / bedtime_end too), so they are
a bedtime here.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_ROLES, DOMAIN

PAUSE = "pause"
# The weekly schedule's Sleep or School (weekly.py), in a person's locked_by
SCHEDULE = "schedule"
MAX_REASON = 80
# Family Safety's Downtime Active sensors say downtime_start / downtime_end (an older one said bedtime_* too)
BEDTIME_STARTS = ("bedtime_start", "downtime_start")
BEDTIME_ENDS = ("bedtime_end", "downtime_end")
_STARTS = (*BEDTIME_STARTS, "schooltime_start")
_ENDS = (*BEDTIME_ENDS, "schooltime_end")


def _pauses(hass: HomeAssistant) -> dict[str, dict[str, Any]]:
    return hass.data.setdefault(f"{DOMAIN}_pauses", {})


def _store(hass: HomeAssistant) -> Store[dict[str, Any]]:
    key = f"{DOMAIN}_pauses_store"
    if key not in hass.data:
        hass.data[key] = Store(hass, 1, f"{DOMAIN}.pauses")
    return hass.data[key]


def _iso(value: datetime) -> str:
    return dt_util.as_utc(value).isoformat()


@callback
def _save(hass: HomeAssistant) -> None:
    """What's paused now, saved a moment later (a restart reads it back)."""

    def data() -> dict[str, Any]:
        return {
            "pauses": {p: {**v, "until": _iso(v["until"])} for p, v in _pauses(hass).items()},
            "app_pauses": {
                p: {k: {**v, "until": _iso(v["until"])} for k, v in mine.items()}
                for p, mine in _app_pauses(hass).items()
                if mine
            },
        }

    _store(hass).async_delay_save(data, 1)


async def async_load_pauses(hass: HomeAssistant) -> None:
    """The pauses saved before Home Assistant stopped, once per start (a reload keeps them in memory); those over are
    left out."""
    flag = f"{DOMAIN}_pauses_loaded"
    if hass.data.get(flag):
        return
    hass.data[flag] = True
    stored = await _store(hass).async_load() or {}
    now = dt_util.utcnow()

    def until_of(value: Any) -> datetime | None:
        parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
        return parsed if parsed is not None and parsed > now else None

    for person, pause in (stored.get("pauses") or {}).items():
        if isinstance(pause, dict) and (until := until_of(pause.get("until"))) is not None:
            _pauses(hass).setdefault(person, {**pause, "until": until})
    for person, mine in (stored.get("app_pauses") or {}).items():
        for key, pause in (mine or {}).items() if isinstance(mine, dict) else ():
            if isinstance(pause, dict) and (until := until_of(pause.get("until"))) is not None:
                _app_pauses(hass).setdefault(person, {}).setdefault(key, {**pause, "until": until})


def set_pause(
    hass: HomeAssistant,
    people: list[str],
    until: datetime,
    reason: str | None,
    ends_on: dict[str, str] | None = None,
) -> None:
    """Each person's pause is their own, so one that ends on a place ends for each person as they get there."""
    for person in people:
        _pauses(hass)[person] = {
            "until": until,
            "reason": (reason or "").strip()[:MAX_REASON],
            "ends_on": dict(ends_on) if ends_on else None,
        }
    _save(hass)


def pausable(household, named: list[str] | None) -> tuple[list[str], list[str]]:
    """Who a pause holds: the people named, or every kid with none named; never an adult (adults have no limits in
    Hearth, so a pause is the kids'). Also the adults named, left out."""
    roles = household.options.get(CONF_ROLES, {})
    people = [p for p in (named or household.people()) if roles.get(p) != "adult"]
    return people, [p for p in named or [] if roles.get(p) == "adult"]


def _app_pauses(hass: HomeAssistant) -> dict[str, dict[str, dict[str, Any]]]:
    return hass.data.setdefault(f"{DOMAIN}_app_pauses", {})


def _what_key(app: str | None, group: str | None) -> str:
    return f"app:{app}" if app is not None else f"group:{group}"


def set_app_pause(
    hass: HomeAssistant, people: list[str], until: datetime, reason: str | None, app: str | None, group: str | None
) -> None:
    """Pauses one app or one group (not All screen time: that's the family pause) for the people."""
    for person in people:
        _app_pauses(hass).setdefault(person, {})[_what_key(app, group)] = {
            "app": app,
            "group": group,
            "until": until,
            "reason": (reason or "").strip()[:MAX_REASON],
        }
    _save(hass)


def end_app_pause(hass: HomeAssistant, people: list[str] | None, app: str | None = None, group: str | None = None) -> None:
    """Ends the people's pause of that app or group; of every app and group without either."""
    pauses = _app_pauses(hass)
    for person in list(pauses) if people is None else people:
        mine = pauses.get(person)
        if not mine:
            continue
        if app is None and group is None:
            mine.clear()
        else:
            mine.pop(_what_key(app, group), None)
    _save(hass)


def app_pauses_of(hass: HomeAssistant, person: str, now: datetime | None = None) -> list[dict[str, Any]]:
    """The person's app and group pauses while they last: [{app, group, until (datetime), reason}], soonest end first."""
    mine = _app_pauses(hass).get(person) or {}
    now = now or dt_util.now()
    for key in [k for k, p in mine.items() if p["until"] <= now]:
        mine.pop(key)
    return sorted(mine.values(), key=lambda p: (p["until"], p["app"] or "", p["group"] or ""))


def pause_ends_on(hass: HomeAssistant, person: str) -> tuple[dict[str, str], datetime] | None:
    """The person's pause's ends_on and its cap, while it lasts and has one."""
    pause = _pauses(hass).get(person)
    if pause is None or not pause.get("ends_on") or pause["until"] <= dt_util.now():
        return None
    return pause["ends_on"], pause["until"]


def end_pause(hass: HomeAssistant, people: list[str] | None) -> None:
    pauses = _pauses(hass)
    for person in list(pauses) if people is None else people:
        pauses.pop(person, None)
    _save(hass)


def pause_of(hass: HomeAssistant, person: str, now: datetime | None = None) -> dict[str, Any] | None:
    """The person's pause while it lasts: {until (ISO), reason}."""
    pause = _pauses(hass).get(person)
    now = now or dt_util.now()
    if pause is None:
        return None
    if pause["until"] <= now:
        _pauses(hass).pop(person, None)
        return None
    return {"until": dt_util.as_local(pause["until"]).isoformat(), "reason": pause["reason"]}


def _local(value: Any) -> datetime | None:
    """A lock entity's time: ISO, local when it says no zone."""
    if not isinstance(value, str):
        return None
    parsed = dt_util.parse_datetime(value)
    if parsed is None:
        return None
    return parsed.replace(tzinfo=dt_util.get_default_time_zone()) if parsed.tzinfo is None else parsed


def lock_until(hass: HomeAssistant, entity_ids: list[str]) -> datetime | None:
    """When the locks that are on end (the latest of them), if they say."""
    ends = [
        end
        for entity_id in entity_ids
        if (state := hass.states.get(entity_id)) is not None
        for key in _ENDS
        if (end := _local(state.attributes.get(key))) is not None
    ]
    return max(ends) if ends else None


def lock_kinds(hass: HomeAssistant, by: list[str], schedule_kind: str | None = None) -> list[str]:
    """What the locks that are on are: bedtime, school_time, pause, or other (a lock entity that doesn't say). The
    weekly schedule's is [schedule_kind] (bedtime or school_time)."""
    kinds: list[str] = []
    for item in by:
        if item == PAUSE:
            kind = PAUSE
        elif item == SCHEDULE:
            kind = schedule_kind or "other"
        else:
            state = hass.states.get(item)
            attrs = state.attributes if state else {}
            if any(k in attrs for k in BEDTIME_STARTS + BEDTIME_ENDS) or "bedtime" in item or "downtime" in item:
                kind = "bedtime"
            elif "schooltime_end" in attrs or "schooltime_start" in attrs or "school" in item:
                kind = "school_time"
            else:
                kind = "other"
        if kind not in kinds:
            kinds.append(kind)
    return kinds


def next_lock(hass: HomeAssistant, entity_ids: list[str], now: datetime | None = None) -> dict[str, Any] | None:
    """The next lock to start, of those that are off: {at (ISO), by (entity), kind (bedtime / school_time)}."""
    now = now or dt_util.now()
    best: tuple[datetime, str, str] | None = None
    for entity_id in entity_ids:
        state = hass.states.get(entity_id)
        if state is None or state.state == "on":
            continue
        for key in _STARTS:
            start = _local(state.attributes.get(key))
            if start is not None and start > now and (best is None or start < best[0]):
                best = (start, entity_id, "school_time" if key.startswith("school") else "bedtime")
    if best is None:
        return None
    return {"at": dt_util.as_local(best[0]).isoformat(), "by": best[1], "kind": best[2]}
