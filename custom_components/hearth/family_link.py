"""A child's Family Link entities (the HAFamilyLink integration), found from any one of them.

Family Link's entities carry the child's id (child_id) and have unique ids made from it, so Hearth finds the child's
School time switch, weekly School time window, School time sensors and daily limits from the one entity the household
chose in Configure > Enforce. The child's id is only ever passed on as a string from here: a templated child id loses
digits (Home Assistant reads the 21 digits as a number).
"""

from __future__ import annotations

from datetime import date, datetime, time
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util

FL_DOMAIN = "familylink"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def child_of(hass: HomeAssistant, entity_id: str) -> str | None:
    """The child's id: an attribute of the entity, or of another entity of its device."""
    state = hass.states.get(entity_id)
    if state is not None and state.attributes.get("child_id"):
        return str(state.attributes["child_id"])
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id)
    if entry is not None and entry.device_id:
        for other in er.async_entries_for_device(registry, entry.device_id):
            other_state = hass.states.get(other.entity_id)
            if other_state is not None and other_state.attributes.get("child_id"):
                return str(other_state.attributes["child_id"])
        # A unique id of the child's own entities: familylink_<child>_<what>
        if entry.platform == FL_DOMAIN and entry.unique_id.startswith(f"{FL_DOMAIN}_"):
            return entry.unique_id.split("_")[1]
    return None


def _by_unique_id(hass: HomeAssistant, domain: str, unique_id: str) -> str | None:
    return er.async_get(hass).async_get_entity_id(domain, FL_DOMAIN, unique_id)


def school_time_switch(hass: HomeAssistant, child: str) -> str | None:
    """The child's School time switch (on: the weekly School time is on)."""
    return _by_unique_id(hass, "switch", f"{FL_DOMAIN}_{child}_school_time")


def daily_limit_switch(hass: HomeAssistant, child: str) -> str | None:
    return _by_unique_id(hass, "switch", f"{FL_DOMAIN}_{child}_daily_limit")


def _clock(value: Any) -> time | None:
    if not isinstance(value, str) or len(value) < 5:
        return None
    try:
        return time.fromisoformat(value[:5])
    except ValueError:
        return None


def weekly_window(hass: HomeAssistant, child: str, day: date) -> tuple[time, time] | None:
    """The child's weekly School time for that weekday, from its start and end time entities (by unique id, else
    any time entity of the child's named for the weekday)."""
    iso = day.isoweekday()
    found: dict[str, time] = {}
    for bound in ("start", "end"):
        entity_id = _by_unique_id(hass, "time", f"{FL_DOMAIN}_{child}_schooltime_{iso}_{bound}")
        if entity_id is None:
            suffix = f"_{WEEKDAYS[iso - 1]}_school_time_{bound}"
            entity_id = next(
                (
                    s.entity_id
                    for s in hass.states.async_all("time")
                    if s.entity_id.endswith(suffix) and str(s.attributes.get("child_id")) == child
                ),
                None,
            )
        state = hass.states.get(entity_id) if entity_id else None
        clock = _clock(state.state if state else None)
        if clock is not None:
            found[bound] = clock
    if "start" in found and "end" in found and found["start"] < found["end"]:
        return found["start"], found["end"]
    return None


def school_time_sensors(hass: HomeAssistant, child: str) -> list[Any]:
    """The child's School time sensors, one per device (binary_sensor.<device>_school_time_active, maybe _2)."""
    return [
        s
        for s in hass.states.async_all("binary_sensor")
        if "_school_time_active" in s.entity_id and str(s.attributes.get("child_id")) == child
    ]


def school_time_active(hass: HomeAssistant, child: str) -> bool:
    """School time is on now on any of the child's devices."""
    return any(s.state == "on" for s in school_time_sensors(hass, child))


def school_time_end(hass: HomeAssistant, child: str) -> datetime | None:
    """When today's School time ends, as the child's devices say (schooltime_end, the latest of them)."""
    ends: list[datetime] = []
    for state in school_time_sensors(hass, child):
        parsed = dt_util.parse_datetime(str(state.attributes.get("schooltime_end") or ""))
        if parsed is not None:
            ends.append(parsed.replace(tzinfo=dt_util.get_default_time_zone()) if parsed.tzinfo is None else parsed)
    return max(ends) if ends else None


def weekday_limit(hass: HomeAssistant, child: str, day: date) -> dict[str, Any] | None:
    """The child's daily limit entity for that weekday: its attributes (weekly_minutes, override_minutes)."""
    suffix = f"_{WEEKDAYS[day.weekday()]}_limit"
    for state in hass.states.async_all("number"):
        if state.entity_id.endswith(suffix) and str(state.attributes.get("child_id")) == child:
            return {"entity_id": state.entity_id, "state": state.state, **state.attributes}
    return None


def devices(hass: HomeAssistant, child: str) -> list[Any]:
    """The child's device switches (one per device: device_id, bonus_minutes, remaining_minutes,
    daily_limit_reached, lock_override_code among their attributes)."""
    return [
        s
        for s in hass.states.async_all("switch")
        if str(s.attributes.get("child_id")) == child and s.attributes.get("device_id") not in (None, "")
    ]


def _device_entity(hass: HomeAssistant, domain: str, child: str, device_id: str, key: str, near: str | None) -> str | None:
    """A device's entity by its unique id (familylink_<child>_<device>_<key>), else one of the same device in the
    registry, else a state carrying the device's id."""
    if (found := _by_unique_id(hass, domain, f"{FL_DOMAIN}_{child}_{device_id}_{key}")) is not None:
        return found
    registry = er.async_get(hass)
    entry = registry.async_get(near) if near else None
    if entry is not None and entry.device_id:
        for other in er.async_entries_for_device(registry, entry.device_id):
            if other.domain == domain and other.unique_id.endswith(f"_{key}"):
                return other.entity_id
    return next(
        (
            s.entity_id
            for s in hass.states.async_all(domain)
            if s.entity_id.endswith(f"_{key}")
            and str(s.attributes.get("device_id")) == device_id
            and str(s.attributes.get("child_id")) == child
        ),
        None,
    )


def reset_bonus_button(hass: HomeAssistant, child: str, device_id: str, near: str | None = None) -> str | None:
    """The device's Reset bonus button (cancels the day's bonus time)."""
    return _device_entity(hass, "button", child, device_id, "reset_bonus", near)


def device_limit(hass: HomeAssistant, child: str, device: Any) -> dict[str, Any]:
    """Google's own daily limit of one device today: limit minutes (None: no limit), minutes left, bonus, reached."""
    device_id = str(device.attributes.get("device_id"))
    remaining_id = _device_entity(hass, "sensor", child, device_id, "screen_time_remaining", device.entity_id)
    limit_id = _device_entity(hass, "sensor", child, device_id, "daily_limit", device.entity_id)
    reached_id = _device_entity(hass, "binary_sensor", child, device_id, "daily_limit_reached", device.entity_id)
    remaining = hass.states.get(remaining_id) if remaining_id else None
    limit = hass.states.get(limit_id) if limit_id else None
    reached = hass.states.get(reached_id) if reached_id else None
    return {
        "entity_id": device.entity_id,
        "device_id": device_id,
        "device": device.attributes.get("device_name") or device.attributes.get("friendly_name") or device_id,
        "daily_limit": _int(limit.state) if limit else None,
        # None: no limit (nothing counts down)
        "minutes_left": _int(remaining.state) if remaining else None,
        "bonus_minutes": _int(device.attributes.get("bonus_minutes")) or 0,
        "reached": (reached.state == "on") if reached else bool(device.attributes.get("daily_limit_reached")),
        "remaining_entity": remaining_id,
    }


def _int(value: Any) -> int | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return int(number) if number == number else None
