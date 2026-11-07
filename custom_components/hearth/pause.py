"""A family pause (dinner time, say) and when a person's locks start and end (docs/home-assistant-integration.md,
Pause and Locks).

hearth.pause holds the chosen people (everyone in the household by default) for some minutes or until a time;
hearth.pause_end lets them go. While paused a person is locked, so a Hearth TV holds their apps as for bedtime, and
their state document says why ("pause": {until, reason}). Pauses are kept outside the entry (an options change reloads
it), not across a restart.

A lock entity of Family Link's says when bedtime or school time starts and ends (bedtime_start / bedtime_end,
schooltime_start / schooltime_end, local times): that's "lock" {by, until} while one is on, and "next_lock" {at, by}
for the next one today, so a device can wind down before it. Family Safety's Downtime Active sensors (one per child and
platform) say the same with bedtime_start / bedtime_end, so they are a bedtime here.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util

from .const import DOMAIN

PAUSE = "pause"
MAX_REASON = 80
_STARTS = ("bedtime_start", "schooltime_start")
_ENDS = ("bedtime_end", "schooltime_end")


def _pauses(hass: HomeAssistant) -> dict[str, dict[str, Any]]:
    return hass.data.setdefault(f"{DOMAIN}_pauses", {})


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


def lock_kinds(hass: HomeAssistant, by: list[str]) -> list[str]:
    """What the locks that are on are: bedtime, school_time, pause, or other (a lock entity that doesn't say)."""
    kinds: list[str] = []
    for item in by:
        if item == PAUSE:
            kind = PAUSE
        else:
            state = hass.states.get(item)
            attrs = state.attributes if state else {}
            if "bedtime_end" in attrs or "bedtime_start" in attrs or "bedtime" in item or "downtime" in item:
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
                best = (start, entity_id, "bedtime" if key.startswith("bed") else "school_time")
    if best is None:
        return None
    return {"at": dt_util.as_local(best[0]).isoformat(), "by": best[1], "kind": best[2]}
