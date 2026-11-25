"""Which room a kid's play is in, and whether it is being played right now (Playing's `area_id` and `active`).

Hearth only names a room it knows from Home Assistant's own area registry; anything unsure is None, never a guess:

- A Hearth TV's app: the TV's own Home Assistant device's area.
- A live source (Xbox now playing): the console's area, only while the console itself is on. The console is the one
  set for the source in the options (`play_areas`: `{"source": <source id>, "console": <media_player>}`), else found:
  the Xbox integration's media player that is on, shows the same title and has an area (one room only). Set or found,
  when its media player names a title it must be the same one: a game played on another console, a PC or the cloud
  has no room.
- A kid's Switch (`nintendo:<entity>`): only while a dock signal set for that Switch says it's docked
  (`{"switch": <the Nintendo enforcer's entity>, "dock": <entity>, "above": <watts>, "area_id": <area>}`): a binary
  sensor, switch or input boolean that is on, or a power sensor (the dock's smart plug) reading more than `above`
  watts. The room is `area_id`, else the dock entity's own area. No signal set, or one unknown or unavailable: None.
  A TV says nothing here: a Hearth TV is a Google TV puck on one of the TV's inputs, so it reads "off" whenever another
  input (the Switch's) is showing, just as when the TV is off.
- A phone's app: None (a phone moves with its kid).

`active`: True while Hearth sees the play going on, False while it sees it stopped (paused), None when it can't tell.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from homeassistant.const import STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
import voluptuous as vol

from .const import DOMAIN
from .sources import normalize

if TYPE_CHECKING:
    from .hub import HearthHub

CONF_PLAY_AREAS = "play_areas"
MAX_PLAY_AREAS = 20
XBOX_DOMAIN = "xbox"
# A console in one of these is off
OFF_STATES = {"off", "standby", STATE_UNAVAILABLE, STATE_UNKNOWN, ""}
# A dock signal in one of these says nothing
UNKNOWN_STATES = {STATE_UNAVAILABLE, STATE_UNKNOWN, ""}


def _invalid(message: str):
    raise vol.Invalid(message)


_ENTITY = vol.All(str, vol.Match(r"^[a-z_]+\.[a-z0-9_]+$"))
_DOCK = vol.All(
    vol.Schema(
        {
            vol.Required("switch"): _ENTITY,
            vol.Required("dock"): vol.All(_ENTITY, vol.Match(r"^(binary_sensor|switch|input_boolean|sensor)\.")),
            # A power sensor's watts above which the Switch is docked (the dock's smart plug); a sensor needs it
            vol.Optional("above"): vol.All(vol.Coerce(float), vol.Range(min=0, max=10000)),
            vol.Optional("area_id"): vol.All(str, vol.Length(min=1, max=64)),
        }
    ),
    lambda d: d if d["dock"].startswith("sensor.") == ("above" in d)
    else _invalid("A power sensor needs above (watts), and only a power sensor takes it"),
)
_CONSOLE = vol.Schema(
    {
        vol.Required("source"): vol.All(str, vol.Match(r"^[a-z0-9_]{1,64}$")),
        vol.Required("console"): vol.All(str, vol.Match(r"^media_player\.[a-z0-9_]+$")),
    }
)


def _one_each(found: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keys = [("switch", e["switch"]) if "switch" in e else ("source", e["source"]) for e in found]
    if len(set(keys)) != len(keys):
        raise vol.Invalid("Each Switch and each source is listed once")
    return found


PLAY_AREAS_SCHEMA = vol.All([vol.Any(_DOCK, _CONSOLE)], vol.Length(max=MAX_PLAY_AREAS), _one_each)


def play_areas(options: dict[str, Any]) -> list[dict[str, Any]]:
    """The options' play_areas, each entry as it validates (anything else is left out: never in the way)."""
    found = []
    for entry in options.get(CONF_PLAY_AREAS) or []:
        try:
            found.append(vol.Any(_DOCK, _CONSOLE)(entry))
        except vol.Invalid:
            continue
    return found


def entity_area(hass: HomeAssistant, entity_id: str | None) -> str | None:
    """An entity's area: its own, else its device's; None when it has none or isn't registered."""
    if not entity_id:
        return None
    entry = er.async_get(hass).async_get(entity_id)
    if entry is None:
        return None
    if entry.area_id:
        return entry.area_id
    device = dr.async_get(hass).async_get(entry.device_id) if entry.device_id else None
    return device.area_id if device is not None else None


def hearth_device_area(hass: HomeAssistant, hub: HearthHub, device_id: str) -> str | None:
    """A Hearth device's area (its Home Assistant device's), as hearth_tv_profile_changed names it."""
    devices = dr.async_get(hass)
    # async_get_device with identifiers stops working in Home Assistant 2027.8
    by_identifier = getattr(devices, "async_get_device_by_identifier", None)
    entry = (
        by_identifier((DOMAIN, device_id), hub.entry.entry_id)
        if by_identifier is not None
        else devices.async_get_device(identifiers={(DOMAIN, device_id)})
    )
    return entry.area_id if entry is not None else None


def _same(a: str | None, b: str | None) -> bool:
    return bool(a) and bool(b) and normalize(a) == normalize(b)


def _media_title(state) -> str | None:
    title = state.attributes.get("media_title")
    return title if isinstance(title, str) and title.strip() else None


def _console_shows(state, title: str) -> bool | None:
    """Whether a console's media player is on with [title]: True, False (off, or another title), None (on, naming
    nothing)."""
    if state is None or state.state in OFF_STATES:
        return False
    shown = _media_title(state)
    if shown is None:
        return None
    return _same(shown, title)


def _set_console(options: dict[str, Any], source_id: str) -> str | None:
    return next((e["console"] for e in play_areas(options) if e.get("source") == source_id), None)


def console_area(hass: HomeAssistant, options: dict[str, Any], source_id: str, title: str) -> str | None:
    """The room of the console a live source's [title] is played on, or None."""
    console = _set_console(options, source_id)
    if console is not None:
        return entity_area(hass, console) if _console_shows(hass.states.get(console), title) is not False else None
    # Found: the Xbox integration's media players that are on with the same title, in one room
    rooms: set[str] = set()
    for entry in er.async_get(hass).entities.values():
        if entry.domain != "media_player" or entry.platform != XBOX_DOMAIN:
            continue
        if _console_shows(hass.states.get(entry.entity_id), title) is True:
            area = entity_area(hass, entry.entity_id)
            if area is None:
                return None
            rooms.add(area)
    return rooms.pop() if len(rooms) == 1 else None


def console_active(hass: HomeAssistant, options: dict[str, Any], source_id: str) -> bool | None:
    """A set console's media player playing (True) or paused (False); else None (a game shows "on")."""
    console = _set_console(options, source_id)
    state = hass.states.get(console) if console else None
    if state is None:
        return None
    return True if state.state == "playing" else False if state.state == "paused" else None


def docked(hass: HomeAssistant, dock: dict[str, Any]) -> bool | None:
    """Whether a dock signal says its Switch is docked: True, False, or None (unknown, unavailable, not a number)."""
    state = hass.states.get(dock["dock"])
    if state is None or state.state in UNKNOWN_STATES:
        return None
    if "above" in dock:
        try:
            watts = float(state.state)
        except ValueError:
            return None
        if watts != watts:
            return None
        if state.attributes.get("unit_of_measurement") == "kW":
            watts *= 1000
        return watts > dock["above"]
    return True if state.state == "on" else False if state.state == "off" else None


def dock_area(hass: HomeAssistant, options: dict[str, Any], switch_entity: str) -> str | None:
    """The room a Switch is docked in: its dock signal's area (set, else the signal entity's own) while the signal says
    docked; else None (handheld, no signal set, or the signal unknown)."""
    dock = next((e for e in play_areas(options) if e.get("switch") == switch_entity), None)
    if dock is None or docked(hass, dock) is not True:
        return None
    return dock.get("area_id") or entity_area(hass, dock["dock"])


def hearth_tv_active(state: str | None, paused: bool) -> bool | None:
    """A Hearth TV's play: its media playing (True) or paused (False); an app with no media playing says nothing."""
    if paused or state == "paused":
        return False
    return True if state == "playing" else None
