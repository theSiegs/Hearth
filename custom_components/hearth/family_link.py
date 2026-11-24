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


def bedtime_slot(hass: HomeAssistant, child: str, iso_day: int) -> tuple[str, str] | None:
    """The child's weekly bedtime of a weekday (1 Monday to 7 Sunday) as ("HH:MM" start, "HH:MM" end the next
    morning), from its start and end time entities (unique id familylink_<child>_bedtime_<day>_<start|end>, else a time
    entity of the child's named for the weekday); None when it can't be read."""
    found: dict[str, str] = {}
    for bound in ("start", "end"):
        entity_id = _by_unique_id(hass, "time", f"{FL_DOMAIN}_{child}_bedtime_{iso_day}_{bound}")
        if entity_id is None:
            suffix = f"_{WEEKDAYS[iso_day - 1]}_bedtime_{bound}"
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
            found[bound] = f"{clock.hour:02d}:{clock.minute:02d}"
    if "start" in found and "end" in found:
        return found["start"], found["end"]
    return None


def bedtime_switch(hass: HomeAssistant, child: str) -> str | None:
    """The child's Bedtime switch (on: Family Link's bedtime is on), by unique id, else the switch named like the
    child's bedtime time entities."""
    if (found := _by_unique_id(hass, "switch", f"{FL_DOMAIN}_{child}_bedtime")) is not None:
        return found
    for state in hass.states.async_all("time"):
        if str(state.attributes.get("child_id")) == child and state.entity_id.endswith("_monday_bedtime_start"):
            candidate = "switch." + state.entity_id[len("time."):-len("monday_bedtime_start")] + "bedtime"
            if hass.states.get(candidate) is not None:
                return candidate
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


def bonus_left(hass: HomeAssistant, child: str, device: Any, watch: set[str] | None = None) -> float:
    """The bonus minutes a device has left: its Active bonus sensor's remaining_minutes when a newer Family Link
    gives it (0 once used up, or when the sensor clears), else the device's bonus_minutes."""
    device_id = str(device.attributes.get("device_id"))
    sensor = _device_entity(hass, "sensor", child, device_id, "active_bonus", device.entity_id)
    state = hass.states.get(sensor) if sensor else None
    if state is not None:
        if watch is not None:
            watch.add(state.entity_id)
        if "remaining_minutes" in state.attributes:
            return _int(state.attributes.get("remaining_minutes")) or 0
        if state.state not in ("unknown", "unavailable"):
            return _int(state.state) or 0
    return _int(device.attributes.get("bonus_minutes")) or 0


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


def app_limits(hass: HomeAssistant, child: str) -> list[dict[str, Any]]:
    """The child's own Family Link app limits (Apps with time limits: package, name, limit_minutes, enabled), without
    the apps pause_app holds (Hearth's pauses, a 1-minute limit Hearth puts back itself)."""
    for state in hass.states.async_all("sensor"):
        if not state.entity_id.endswith("_apps_with_time_limits") or str(state.attributes.get("child_id")) != child:
            continue
        paused = {str(p.get("package")) for p in state.attributes.get("paused_apps") or [] if isinstance(p, dict)}
        return [
            {**app, "entity_id": state.entity_id}
            for app in state.attributes.get("apps") or []
            if isinstance(app, dict) and app.get("enabled", True) and app.get("package") not in paused
        ]
    return []


# The child's app lists that, together, are every app installed on their devices (Family Link's sensors split them:
# blocked, with a time limit, without one, always allowed)
INSTALLED_LISTS = ("_blocked_apps", "_apps_with_time_limits", "_apps_without_limits", "_always_allowed_apps")


def _child_lists(hass: HomeAssistant, child: str) -> list[tuple[str, Any]]:
    """(suffix, state) of the child's Family Link app list sensors. An empty list's sensor carries no attributes at
    all, not even child_id: it is the child's when its entity id has the same name as one of their other lists."""
    lists: list[tuple[str, Any]] = []
    prefixes: set[str] = set()
    unclaimed: list[tuple[str, Any]] = []
    for state in hass.states.async_all("sensor"):
        suffix = next((s for s in INSTALLED_LISTS if state.entity_id.endswith(s)), None)
        if suffix is None:
            continue
        owner = state.attributes.get("child_id")
        if owner is None:
            unclaimed.append((suffix, state))
        elif str(owner) == child:
            lists.append((suffix, state))
            prefixes.add(state.entity_id[: -len(suffix)])
    lists.extend((suffix, state) for suffix, state in unclaimed if state.entity_id[: -len(suffix)] in prefixes)
    return lists


def _apps_of(state) -> list | None:
    """A Family Link app list sensor's apps; an empty list carries no "apps" at all (state 0), which is none, not
    unknown."""
    apps = state.attributes.get("apps")
    if apps is None and str(state.state) == "0":
        return []
    return apps


# The last whole read of each child's installed apps (installed_apps), for while a list is cut short
_LAST_INSTALLED = "hearth_fl_installed"


def installed_apps(hass: HomeAssistant, child: str) -> set[str] | None:
    """The packages installed on the child's devices, from their Family Link app lists; None when that can't be told
    (a list missing, or cut short with no whole read of them before).

    A list cut short to fit Home Assistant's attribute limit (truncated) is read as the last whole read plus whatever
    the lists show now. Hearth's own pause of every app makes it so: each paused app moves into With time limits,
    which outgrows the limit. Reading that as "not known" swapped the pause of every app for the device lock and
    back, every few minutes."""
    found: set[str] = set()
    seen: set[str] = set()
    cut_short = False
    for suffix, state in _child_lists(hass, child):
        apps = _apps_of(state)
        if not isinstance(apps, list):
            return None
        cut_short = cut_short or bool(state.attributes.get("truncated"))
        seen.add(suffix)
        for app in apps:
            package = app.get("package") if isinstance(app, dict) else app
            if isinstance(package, str) and package:
                found.add(package)
    if seen != set(INSTALLED_LISTS):
        return None
    last: dict[str, frozenset[str]] = hass.data.setdefault(_LAST_INSTALLED, {})
    if not cut_short:
        last[child] = frozenset(found)
        return found
    return found | last[child] if child in last else None


def app_lists(hass: HomeAssistant, child: str) -> tuple[set[str], set[str] | None]:
    """(listed, blocked) of the child's Family Link app lists: every package any list names now (installed, as far as
    the lists tell, even one cut short), and the packages of the Blocked apps list (None without that list, or when it
    was cut short: whether an app is blocked can't be told then)."""
    listed: set[str] = set()
    blocked: set[str] | None = None
    for suffix, state in _child_lists(hass, child):
        apps = _apps_of(state)
        packages = {
            package
            for app in (apps if isinstance(apps, list) else [])
            if isinstance(package := (app.get("package") if isinstance(app, dict) else app), str) and package
        }
        listed |= packages
        if suffix == "_blocked_apps" and isinstance(apps, list) and not state.attributes.get("truncated"):
            blocked = (blocked or set()) | packages
    return listed, blocked


# Google's capabilities of a device that takes a daily limit (HAFamilyLink's CAPS_TIME_LIMIT): a Google TV has neither
TIME_LIMIT_CAPABILITIES = ("capabilityBedtime", "capabilityLockWithDeadline")


def device_minutes_today(hass: HomeAssistant, child: str) -> list[tuple[str, float]]:
    """Each of the child's devices that take a daily limit, with Family Link's screen time today on it, from their
    Daily screen time sensors: (device id, minutes). A device whose capabilities say it takes no daily limit (a Google
    TV) is left out; one with no capability list (an older Family Link) is kept."""
    found: list[tuple[str, float]] = []
    for state in hass.states.async_all("sensor"):
        attrs = state.attributes
        if (
            not state.entity_id.endswith("_daily_screen_time")
            or str(attrs.get("child_id")) != child
            or not attrs.get("device_id")
        ):
            continue
        caps = attrs.get("capabilities")
        if caps and not any(c in caps for c in TIME_LIMIT_CAPABILITIES):
            continue
        try:
            minutes = float(state.state)
        except (TypeError, ValueError):
            continue
        found.append((str(attrs["device_id"]), minutes))
    return found


def app_minutes_today(hass: HomeAssistant, child: str, package: str) -> list[tuple[str, float]]:
    """An app's minutes today on each of the child's devices, from their Daily screen time sensors: (device, minutes)."""
    found: list[tuple[str, float]] = []
    for state in hass.states.async_all("sensor"):
        attrs = state.attributes
        if (
            not state.entity_id.endswith("_daily_screen_time")
            or str(attrs.get("child_id")) != child
            or not attrs.get("device_id")
        ):
            continue
        for app in attrs.get("apps") or []:
            if isinstance(app, dict) and app.get("package") == package:
                try:
                    minutes = float(app.get("minutes") or 0)
                except (TypeError, ValueError):
                    continue
                found.append((str(attrs.get("device_name") or attrs.get("device_id")), minutes))
    return found


def _int(value: Any) -> int | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return int(number) if number == number else None
