"""A family pause (dinner time, say) and when a person's locks start and end (docs/home-assistant-integration.md,
Pause and Locks).

hearth.pause holds the chosen people (everyone in the household by default) for some minutes or until a time;
hearth.pause_end lets them go. While paused a person is locked, so a Hearth TV holds their apps as for bedtime, and
their state document says why ("pause": {until, reason}). Pauses are kept outside the entry (an options change reloads
it), not across a restart.

A lock entity of Family Link's says when bedtime or school time starts and ends (bedtime_start / bedtime_end,
schooltime_start / schooltime_end, local times): that's "lock" {by, until} while one is on, and "next_lock" {at, by}
for the next one today, so a device can wind down before it.
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


def set_pause(hass: HomeAssistant, people: list[str], until: datetime, reason: str | None) -> None:
    for person in people:
        _pauses(hass)[person] = {"until": until, "reason": (reason or "").strip()[:MAX_REASON]}


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
