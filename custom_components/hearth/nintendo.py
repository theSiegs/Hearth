"""A kid's Nintendo Switch as Hearth's page and an adult's app show it, and what the installed Nintendo integration can
do with it (Home Assistant's nintendo_parental_controls, or a patched copy of it with more actions).

    switches(household, person)   each Switch of the person's: today's play, the Switch's own limit, time left and
                                  extra time, Suspend software, playing now, bedtime, last synced, Hearth's hold
    capabilities(hass)            which actions the installed integration has, found at runtime: add_bonus_time and
                                  the minutes it takes, cancel_bonus_time, list_applications, set_app_allowed,
                                  update_daily_restrictions; and how Hearth tells who plays a shared Switch: each
                                  player's minutes (Home Assistant's own integration has them), a patched copy's
                                  playing sensor per player (used too when it's there)

A Switch is the person's when Hearth holds it for them (an enforcer of theirs) or a screen time source of theirs is one
of its entities. Its entities are found by the Switch's own id in their unique ids ({nintendo id}_{key}), as the
integration makes them, so renamed entities are still found. The view only reads; the page's commands (panel.py)
make the calls.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import HomeAssistant, State
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er

from .enforce import NINTENDO, NINTENDO_DOMAIN
from .switch_play import players, sources_of

if TYPE_CHECKING:
    from .enforce import Enforcer
    from .household import Household

# The integration's entity keys (the end of their unique ids)
LIMIT = "today_max_screentime"
SUSPEND = "suspend_software"
MODE = "timer_mode"
PLAYED = "playing_time"
LEFT = "time_remaining"
EXTRA = "time_extended"
PLAYING = "playing"
LAST_SYNC = "last_sync"
BEDTIME = "bedtime_alarm"
BEDTIME_END = "bedtime_end_time"
CANCEL_BUTTON = "cancel_extra_playing_time"
PLAYER_PLAYED = "player_playing_time"
KEYS = (LIMIT, SUSPEND, MODE, PLAYED, LEFT, EXTRA, PLAYING, LAST_SYNC, BEDTIME, BEDTIME_END, CANCEL_BUTTON)

ADD_BONUS = "add_bonus_time"
CANCEL_BONUS = "cancel_bonus_time"
LIST_APPS = "list_applications"
SET_APP_ALLOWED = "set_app_allowed"
# Nintendo's own minimum; core takes 5 to 30, a patched copy up to 360 and -1 (unlimited for the rest of the day)
BONUS_MIN = 5
UNLIMITED = -1
NO_LIMIT = -1


def accepts(hass: HomeAssistant, service: str, data: dict[str, Any]) -> bool:
    """The integration has [service] and its schema takes [data] (a probe: nothing is called)."""
    found = hass.services.async_services_for_domain(NINTENDO_DOMAIN).get(service)
    if found is None:
        return False
    if found.schema is None:
        return True
    try:
        found.schema(data)
    except vol.Invalid:
        return False
    return True


def capabilities(hass: HomeAssistant) -> dict[str, Any]:
    """What the page may offer for a Switch, by what's installed now."""
    probe = {"device_id": "probe"}
    add = accepts(hass, ADD_BONUS, {**probe, "bonus_time": BONUS_MIN})
    bonus_max = next(
        (m for m in (360, 120, 60, 30) if add and accepts(hass, ADD_BONUS, {**probe, "bonus_time": m})), None
    )
    has = hass.services.has_service
    found = players(hass)
    return {
        # Who plays a shared Switch: their minutes growing (core), a player's playing sensor too (a patched copy)
        "player_minutes": bool(found),
        "player_playing": any(p["playing"] for p in found),
        "update_daily_restrictions": has(NINTENDO_DOMAIN, "update_daily_restrictions"),
        "installed": bool(hass.config_entries.async_entries(NINTENDO_DOMAIN)),
        "add_bonus": add,
        "bonus_min": BONUS_MIN if add else None,
        "bonus_max": bonus_max,
        "unlimited": add and accepts(hass, ADD_BONUS, {**probe, "bonus_time": UNLIMITED}),
        "cancel_bonus": has(NINTENDO_DOMAIN, CANCEL_BONUS),
        "list_apps": has(NINTENDO_DOMAIN, LIST_APPS),
        "set_app_allowed": has(NINTENDO_DOMAIN, SET_APP_ALLOWED),
    }


def _nintendo_id(device: dr.DeviceEntry) -> str | None:
    return next((value for domain, value in device.identifiers if domain == NINTENDO_DOMAIN), None)


# Where a playing sensor may name the game (a patched integration's attributes, friend presence's)
TITLE_ATTRIBUTES = ("title", "game", "game_title", "application_name", "app_name", "application", "media_title")


def playing_title(state: State) -> str | None:
    """The game a Switch's playing sensor names, when it names one."""
    for attribute in TITLE_ATTRIBUTES:
        value = state.attributes.get(attribute)
        if isinstance(value, str) and value.strip() and value.strip().lower() not in ("none", "unknown", "unavailable"):
            return value.strip()[:128]
    return None


def playing_entities(hass: HomeAssistant, enforcer: Enforcer, enforcers: list[Enforcer]) -> list[str]:
    """What says the person is playing their Switch now (on or off): the enforcer's own playing entities (a shared
    Switch's player sensors, a patched integration's for their player's minutes too), else the Switch's Playing sensor
    when nobody else's enforcer is on the same Switch. A player's minutes say it too (switch_play.py,
    watched_entities)."""
    if enforcer.playing or enforcer.player:
        return sources_of(hass, enforcer)[0]
    registry = er.async_get(hass)
    entry = registry.async_get(enforcer.entity_id)
    if entry is None or entry.device_id is None:
        return []
    for other in enforcers:
        if other.kind == NINTENDO and other.person != enforcer.person:
            found = registry.async_get(other.entity_id)
            if found is not None and found.device_id == entry.device_id:
                return []
    device = dr.async_get(hass).async_get(entry.device_id)
    nintendo_id = _nintendo_id(device) if device else None
    if nintendo_id is None:
        return []
    playing = registry.async_get_entity_id("binary_sensor", NINTENDO_DOMAIN, f"{nintendo_id}_{PLAYING}")
    return [playing] if playing else []


def watched_entities(hass: HomeAssistant, enforcer: Enforcer, enforcers: list[Enforcer]) -> list[str]:
    """Every entity whose change may mean the person started or stopped playing their Switch: the playing sensors
    and their player's minutes."""
    found = playing_entities(hass, enforcer, enforcers)
    if enforcer.playing or enforcer.player:
        found += [e for e in sources_of(hass, enforcer)[1] if e not in found]
    return found


def switch_console(hass: HomeAssistant, entity_id: str) -> str:
    """Which Switch an entity is on (its device in Home Assistant, else the entity itself): two kids playing one
    console are together even when Nintendo doesn't name the game."""
    entry = er.async_get(hass).async_get(entity_id)
    return entry.device_id if entry is not None and entry.device_id else entity_id


def switch_name(hass: HomeAssistant, entity_id: str) -> str:
    """The name of the Switch an entity is on (as the adult named the device), else "Switch"."""
    entry = er.async_get(hass).async_get(entity_id)
    device = dr.async_get(hass).async_get(entry.device_id) if entry is not None and entry.device_id else None
    return (device.name_by_user or device.name or "Switch") if device else "Switch"


def _number(hass: HomeAssistant, entity_id: str | None) -> float | None:
    state = hass.states.get(entity_id) if entity_id else None
    if state is None:
        return None
    try:
        return float(state.state)
    except ValueError:
        return None


def _int(value: float | None) -> int | None:
    return None if value is None else int(round(value))


def _state(hass: HomeAssistant, entity_id: str | None) -> str | None:
    state = hass.states.get(entity_id) if entity_id else None
    return state.state if state is not None else None


def _player_ids(nintendo_id: str, entries: list[er.RegistryEntry], chosen: set[str]) -> set[str]:
    """The players (Nintendo's player ids) of these entities: a player's playing sensor or played sensor."""
    found = set()
    for entry in entries:
        if entry.entity_id not in chosen:
            continue
        rest = entry.unique_id.removeprefix(f"{nintendo_id}_")
        for suffix in (f"_{PLAYER_PLAYED}", f"_{PLAYING}"):
            if rest != entry.unique_id and rest.endswith(suffix) and rest != PLAYING:
                found.add(rest.removesuffix(suffix))
    return found


def _held_for_another(household, limit_entity: str | None, person: str) -> str | None:
    """Another person Hearth holds this Switch for (a shared Switch): None for none."""
    if not limit_entity:
        return None
    from .enforce import NINTENDO, SWITCH, _holding, key_parts

    for key, held in household.enforcement.held.items():
        if key.startswith(f"{NINTENDO}|") and held.entity_id == limit_entity and SWITCH in _holding(held):
            holder = key_parts(key)[1]
            if holder != person:
                return holder
    return None


def switches(household: Household, person: str) -> list[dict[str, Any]]:
    """Each Switch of the person's, as its entities say now. Nothing when there's none (or no Nintendo integration)."""
    hass = household.hass
    registry = er.async_get(hass)
    devices = dr.async_get(hass)
    # HA device id -> (Hearth's enforcer entity, the person's own entities on it: a player's sensors)
    mine: dict[str, dict[str, Any]] = {}
    for enforcer in household.enforcement.enforcers:
        if enforcer.person != person or enforcer.kind != NINTENDO:
            continue
        entry = registry.async_get(enforcer.entity_id)
        if entry is None or entry.device_id is None:
            continue
        found = mine.setdefault(entry.device_id, {"enforcer": None, "own": set()})
        found["enforcer"] = enforcer.entity_id
        found["own"].update(enforcer.playing)
        found["own"].update(enforcer.player)
    for source in household.sources:
        if source.person != person:
            continue
        entry = registry.async_get(source.entity_id)
        if entry is None or entry.device_id is None or entry.platform != NINTENDO_DOMAIN:
            continue
        mine.setdefault(entry.device_id, {"enforcer": None, "own": set()})["own"].add(source.entity_id)
    rows = []
    for device_id, found in mine.items():
        device = devices.async_get(device_id)
        nintendo_id = _nintendo_id(device) if device else None
        if device is None or nintendo_id is None:
            continue
        entries = [e for e in er.async_entries_for_device(registry, device_id) if e.platform == NINTENDO_DOMAIN]
        by_key = {key: next((e.entity_id for e in entries if e.unique_id == f"{nintendo_id}_{key}"), None) for key in KEYS}
        players = _player_ids(nintendo_id, entries, found["own"])
        player_played = [
            e.entity_id for e in entries for p in players if e.unique_id == f"{nintendo_id}_{p}_{PLAYER_PLAYED}"
        ]
        player_playing = [e.entity_id for e in entries for p in players if e.unique_id == f"{nintendo_id}_{p}_{PLAYING}"]
        limit = _number(hass, by_key[LIMIT])
        left = _number(hass, by_key[LEFT])
        extra = _number(hass, by_key[EXTRA])
        held = found["enforcer"] is not None and household.enforcement.switch_hold(found["enforcer"]) is not None
        limited = limit is not None and limit != NO_LIMIT
        bedtime = _state(hass, by_key[BEDTIME])
        playing = player_playing or ([by_key[PLAYING]] if by_key[PLAYING] else [])
        played = [_number(hass, e) for e in player_played]
        # A shared Switch's hold (switch_play.py): who it's held for, someone else's turn, who's playing (None: unknown)
        hold = household.enforcement.switch_view(found["enforcer"]) if found["enforcer"] else None
        playing_now = hold["playing"].get(person) if hold else None
        enforcer = next(
            (e for e in household.enforcement.enforcers if e.kind == NINTENDO and e.entity_id == found["enforcer"]
             and e.person == person),
            None,
        )
        rows.append(
            {
                "device_id": device_id,
                "name": device.name_by_user or device.name or "Switch",
                # What hearth.add_bonus and hearth.allow take as `device` (only when Hearth holds this Switch for them)
                "target": f"nintendo:{found['enforcer']}" if found["enforcer"] else None,
                "available": _state(hass, by_key[LIMIT] or by_key[PLAYED]) not in (None, "unavailable", "unknown"),
                "played_minutes": _int(_number(hass, by_key[PLAYED])),
                # On a shared Switch: their own player's minutes today
                "player_minutes": _int(sum(p for p in played if p is not None)) if any(p is not None for p in played)
                else None,
                "limit_minutes": _int(limit) if limited else None,
                "minutes_left": _int(left) if limited else None,
                # Nintendo's extra playing time today (-1: unlimited for the rest of the day)
                "extra_minutes": _int(extra),
                "suspended": None if _state(hass, by_key[SUSPEND]) is None else _state(hass, by_key[SUSPEND]) == "on",
                "playing": any(_state(hass, e) == "on" for e in playing) or playing_now is True,
                # Whether they're playing, as Hearth judges a shared Switch: true, false, or null (unknown)
                "playing_now": playing_now,
                # Shared with others: held only once they're caught playing
                "shared": bool(enforcer and enforcer.shared),
                # Hearth holds it because they were caught playing out of time (everyone on it waits)
                "caught": bool(hold and person in hold["caught"]),
                # Someone else's turn: {until, for_person, held_for}
                "turn": hold["turn"] if hold else None,
                "each_day": _state(hass, by_key[MODE]) == "each_day_of_the_week",
                "bedtime": bedtime[:5] if bedtime and bedtime not in ("unknown", "unavailable") and bedtime[:5] != "00:00"
                else None,
                "last_synced": _state(hass, by_key[LAST_SYNC])
                if _state(hass, by_key[LAST_SYNC]) not in (None, "unknown", "unavailable")
                else None,
                "held_by_hearth": held,
                # A shared Switch Hearth holds for another kid: Nintendo's extra on it would read as a parent's grant
                # for that kid
                "held_for_another": _held_for_another(household, by_key[LIMIT], person),
                # The Switch's own limit stops it now, not a hold of Hearth's
                "blocking": bool(limited and left is not None and left <= 0 and not held and not (extra or 0)),
                "entities": {key: entity_id for key, entity_id in by_key.items() if entity_id},
            }
        )
    rows.sort(key=lambda r: r["name"].casefold())
    return rows


def switch_of(household: Household, person: str, device_id: str) -> dict[str, Any] | None:
    """The person's Switch with this Home Assistant device id, or None (not theirs, or not a Switch)."""
    return next((s for s in switches(household, person) if s["device_id"] == device_id), None)
