"""A panel's document (glint.panel-config/1.3), and checking every value that goes into it.

Values come from three places: set_panel / set_panel_defaults and the entities (strict: a value that isn't right is
refused, naming it), and a pair body's seed (lax: a field that isn't right, or names an entity Home Assistant doesn't
have, is dropped). A value that's left out, or is the derived default, isn't kept: the document derives it.
"""

from __future__ import annotations

import base64
import binascii
import copy
import hashlib
import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from .const import (
    BED_CONTROLS,
    BED_KEYS,
    BED_MAX_DATA_BYTES,
    BED_MAX_DATA_KEYS,
    BED_MAX_PRESETS,
    BED_SIDE_KEYS,
    DAYS,
    DEFAULT_COMMUTE,
    DEFAULT_WINDOWS,
    ENTITY_KEYS,
    ENTITY_LIST_KEYS,
    MAX_LIST,
    MAX_WINDOWS,
    MOTIONS,
    PHOTO_EVERY,
    SCHEMA,
    SELECTS,
    SWITCHES,
)

_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
_ENTITY = re.compile(r"^[a-z0-9_]+\.[a-z0-9_]+$")
MAX_WORD = 40
MAX_ATTRIBUTE = 64


class Refused(ValueError):
    """A value set_panel or set_panel_defaults won't take; the message names it."""


@dataclass(frozen=True)
class Known:
    """What Home Assistant has: an entity id, an area id."""

    entity: Callable[[str], bool]
    area: Callable[[str], bool]


def _entity(value: Any, known: Known, strict: bool, domain: str | None = None) -> str | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str) or not _ENTITY.match(value) or (domain and not value.startswith(f"{domain}.")):
        if strict:
            raise Refused(f"Not {'a ' + domain if domain else 'an'} entity id: {value!r}")
        return None
    if not known.entity(value):
        if strict:
            raise Refused(f"No entity {value}")
        return None
    return value


def _entities(value: Any, known: Known, strict: bool, domain: str | None = None) -> list[str] | None:
    if value is None:
        return None
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or len(value) > MAX_LIST:
        if strict:
            raise Refused(f"Not a list of entity ids: {value!r}")
        return None
    found = [e for e in (_entity(v, known, strict, domain) for v in value) if e]
    unique = list(dict.fromkeys(found))
    return unique or None


def _areas(value: Any, known: Known, strict: bool) -> list[str] | None:
    if value is None:
        return None
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or len(value) > MAX_LIST:
        if strict:
            raise Refused(f"Not a list of area ids: {value!r}")
        return None
    found = []
    for area in value:
        if isinstance(area, str) and known.area(area):
            found.append(area)
        elif strict:
            raise Refused(f"No area {area}")
    return list(dict.fromkeys(found)) or None


def _data(value: Any, strict: bool, what: str) -> dict[str, Any] | None:
    """An action's fields: a small JSON object (string keys), or None for none."""
    if value is None or value == {}:
        return None
    try:
        size = len(json.dumps(value, separators=(",", ":"))) if isinstance(value, dict) else None
    except (TypeError, ValueError):
        size = None
    if (
        size is None
        or size > BED_MAX_DATA_BYTES
        or len(value) > BED_MAX_DATA_KEYS
        or any(not isinstance(k, str) or not k for k in value)
    ):
        if strict:
            raise Refused(
                f"{what}'s data is a JSON object of at most {BED_MAX_DATA_KEYS} fields and {BED_MAX_DATA_BYTES} bytes"
            )
        return None
    return copy.deepcopy(value)


def _name(value: Any, strict: bool, what: str) -> str | None:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    if not isinstance(value, str) or len(value.strip()) > MAX_WORD:
        if strict:
            raise Refused(f"{what} is words, at most {MAX_WORD} letters: {value!r}")
        return None
    return value.strip()


def _action(value: Any, known: Known, strict: bool, what: str) -> dict[str, Any] | None:
    """{entity, data?}; a bare entity id is {entity}. None: not one (refused when strict)."""
    if value is None or value == "" or value == {}:
        return None
    if isinstance(value, str):
        value = {"entity": value}
    if not isinstance(value, dict) or set(value) - {"entity", "data"} or not value.get("entity"):
        if strict:
            raise Refused(f"{what} is {{entity, data?}} or an entity id, not {value!r}")
        return None
    entity = _entity(value.get("entity"), known, strict)
    data = _data(value.get("data"), strict, what)
    if entity is None or (data is None and value.get("data") not in (None, {})):
        return None
    return {"entity": entity, **({"data": data} if data else {})}


def _presets(value: Any, known: Known, strict: bool) -> list[dict[str, Any]]:
    if value is None or value == []:
        return []
    if not isinstance(value, list) or len(value) > BED_MAX_PRESETS:
        if strict:
            raise Refused(f"A bed side's presets are a list of at most {BED_MAX_PRESETS}")
        return []
    found: list[dict[str, Any]] = []
    for preset in value:
        if not isinstance(preset, dict) or set(preset) - {"name", "entity", "data"}:
            if strict:
                raise Refused(f"A preset is {{name, entity, data?}}, not {preset!r}")
            continue
        name = _name(preset.get("name"), strict, "A preset's name")
        if name is None:
            if strict:
                raise Refused(f"A preset needs a name: {preset!r}")
            continue
        if any(p["name"].casefold() == name.casefold() for p in found):
            if strict:
                raise Refused(f"Two presets named {name}")
            continue
        action = _action({k: v for k, v in preset.items() if k != "name"}, known, strict, f"Preset {name}")
        if action is None:
            if strict:
                raise Refused(f"Preset {name} needs an entity")
            continue
        found.append({"name": name, **action})
    return found


def _controls(value: Any, known: Known, strict: bool) -> dict[str, Any]:
    if value is None or value == {}:
        return {}
    if not isinstance(value, dict) or set(value) - set(BED_CONTROLS):
        if strict:
            raise Refused(f"A bed side's controls are any of {', '.join(BED_CONTROLS)}, not {value!r}")
        if not isinstance(value, dict):
            return {}
    out = {}
    for key in BED_CONTROLS:
        if (action := _action(value.get(key), known, strict, f"Control {key}")) is not None:
            out[key] = action
    return out


def _bed(value: Any, known: Known, strict: bool) -> dict[str, Any] | None:
    if value is None or value == {}:
        return None
    if not isinstance(value, dict) or set(value) - set(BED_SIDE_KEYS):
        if strict:
            raise Refused(f"A bed side is {{{', '.join(BED_SIDE_KEYS)}}}, not {value!r}")
        return None
    reliable = value.get("reliable")
    if reliable is not None and not isinstance(reliable, bool):
        if strict:
            raise Refused(f"A bed side's reliable is true, false or null, not {reliable!r}")
        reliable = None
    side = {
        "connected": _entity(value.get("connected"), known, strict),
        "scripts": _entities(value.get("scripts"), known, strict) or [],
        "positions": _entities(value.get("positions"), known, strict) or [],
        # Since 1.2
        "name": _name(value.get("name"), strict, "A bed side's name"),
        "active": _entity(value.get("active"), known, strict),
        "reliable": reliable,
        "presets": _presets(value.get("presets"), known, strict),
        "controls": _controls(value.get("controls"), known, strict),
    }
    return side if any(v not in (None, [], {}) for v in side.values()) else None


def bed_side(side: Any) -> dict[str, Any] | None:
    """A stored side in the document's shape: every key present (a side stored before 1.2 gets the new ones empty)."""
    if not isinstance(side, dict):
        return None
    return {
        "connected": None, "scripts": [], "positions": [], "name": None, "active": None, "reliable": None,
        "presets": [], "controls": {}, **copy.deepcopy(side),
    }


def _days(value: Any) -> list[str] | None:
    if not isinstance(value, list) or not value or any(d not in DAYS for d in value):
        return None
    return [d for d in DAYS if d in value]


def _window(value: Any, strict: bool, word: bool = True) -> dict[str, Any] | None:
    keys = {"word", "from", "until", "days", "after_bedtimes"} if word else {"from", "until", "days"}
    days = _days(value.get("days")) if isinstance(value, dict) else None
    ok = (
        isinstance(value, dict)
        and not set(value) - keys
        and isinstance(value.get("from"), str)
        and _TIME.match(value["from"])
        and isinstance(value.get("until"), str)
        and _TIME.match(value["until"])
        and days is not None
        and (
            not word
            or (
                isinstance(value.get("word"), str)
                and 0 < len(value["word"].strip()) <= MAX_WORD
                and isinstance(value.get("after_bedtimes", False), bool)
            )
        )
    )
    if not ok:
        if strict:
            raise Refused(f"Not a {'routine' if word else 'commute'} window: {value!r}")
        return None
    out = {"from": value["from"], "until": value["until"], "days": days}
    if word:
        out = {"word": value["word"].strip(), **out, "after_bedtimes": value.get("after_bedtimes", False)}
    return out


def _windows(value: Any, strict: bool) -> list[dict[str, Any]] | None:
    if value is None or value == []:
        return None
    if not isinstance(value, list) or len(value) > MAX_WINDOWS:
        if strict:
            raise Refused(f"At most {MAX_WINDOWS} routine windows")
        return None
    found = [w for w in (_window(v, strict) for v in value) if w]
    if not found or found == list(DEFAULT_WINDOWS):
        return None
    return found


_PROXY_NAME = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,29}[a-z0-9])?$")


def panel_value(key: str, value: Any, known: Known, strict: bool = True) -> Any:
    """[value] for the panel's [key], checked; None: back to derived (left out, null, [] or the default)."""
    if key == "people":
        return _entities(value, known, strict, "person")
    if key == "extra_areas":
        return _areas(value, known, strict)
    if key in ENTITY_LIST_KEYS:
        return _entities(value, known, strict)
    if key in BED_KEYS:
        return _bed(value, known, strict)
    if key in ENTITY_KEYS:
        return _entity(value, known, strict)
    if key == "proxy_name":
        # The ESPHome name the panel's proxy already has (from its seed): kept, so ESPHome sees the same device
        if value is None or value == "":
            return None
        if not isinstance(value, str) or not _PROXY_NAME.match(value):
            if strict:
                raise Refused(f"Not an ESPHome name: {value!r}")
            return None
        return value
    if key == "voice_reply_attribute":
        if value is None or value == "":
            return None
        if not isinstance(value, str) or len(value) > MAX_ATTRIBUTE:
            if strict:
                raise Refused(f"Not an attribute name: {value!r}")
            return None
        return value
    if key == "motion":
        if value is None:
            return None
        if value not in MOTIONS:
            if strict:
                raise Refused(f"motion is one of {', '.join(MOTIONS)}")
            return None
        return None if value == SELECTS["motion"][0] else value
    if key == "photos_every":
        if value is None:
            return None
        try:
            seconds = int(value) if not isinstance(value, bool) else None
        except (TypeError, ValueError):
            seconds = None
        if seconds not in PHOTO_EVERY:
            if strict:
                raise Refused(f"photos_every is one of {', '.join(map(str, PHOTO_EVERY))} seconds")
            return None
        return None if seconds == SELECTS["photos_every"][0] else seconds
    if key in SWITCHES:
        if value is None:
            return None
        if not isinstance(value, bool):
            if strict:
                raise Refused(f"{key} is true or false")
            return None
        return None if value == SWITCHES[key] else value
    raise Refused(f"No panel setting {key}")


def house_value(key: str, value: Any, known: Known, strict: bool = True) -> Any:
    """[value] for the house-wide [key] (set_panel_defaults), checked; None: back to derived."""
    if key == "family_calendars":
        return _entities(value, known, strict, "calendar")
    if key == "person_calendars":
        if value is None or value == {}:
            return None
        if not isinstance(value, dict):
            if strict:
                raise Refused("person_calendars is {person: [calendars]}")
            return None
        out = {}
        for person, calendars in value.items():
            who = _entity(person, known, strict, "person")
            found = _entities(calendars, known, strict, "calendar")
            if who and found:
                out[who] = found
        return out or None
    if key in ("night", "doorbell_camera", "photos"):
        return _entity(value, known, strict)
    if key == "routine_windows":
        return _windows(value, strict)
    if key == "commute_window":
        if value is None or value == {}:
            return None
        window = _window(value, strict, word=False)
        return None if window == DEFAULT_COMMUTE else window
    raise Refused(f"No house-wide panel setting {key}")


def _renamed(value: Any, old: str, new: str) -> tuple[Any, bool]:
    """[value] (an entity id, or a list of them) with [old] renamed to [new]; whether it changed."""
    if value == old:
        return new, True
    if isinstance(value, list) and old in value:
        return list(dict.fromkeys(new if v == old else v for v in value)), True
    return value, False


def rename_values(values: dict[str, Any], old: str, new: str) -> bool:
    """A renamed entity id rewritten (in place) in a panel's values: people, routines, its entity settings and its
    bed sides. Whether anything changed."""
    changed = False
    for key in ("people", *ENTITY_LIST_KEYS, *ENTITY_KEYS):
        if key in values:
            values[key], did = _renamed(values[key], old, new)
            changed |= did
    for key in BED_KEYS:
        side = values.get(key)
        if isinstance(side, dict):
            for part in ("connected", "scripts", "positions", "active"):
                if part in side:
                    side[part], did = _renamed(side[part], old, new)
                    changed |= did
            # The presets' and controls' entities (1.2)
            actions = [p for p in side.get("presets") or [] if isinstance(p, dict)]
            if isinstance(controls := side.get("controls"), dict):
                actions += [c for c in controls.values() if isinstance(c, dict)]
            for action in actions:
                if action.get("entity") == old:
                    action["entity"], changed = new, True
    return changed


def rename_house(house: dict[str, Any], old: str, new: str) -> bool:
    """A renamed entity id rewritten (in place) in the house-wide values: the calendars (a person's too, and the
    person), night, the doorbell camera and the album. Whether anything changed."""
    changed = False
    for key in ("family_calendars", "night", "doorbell_camera", "photos"):
        if key in house:
            house[key], did = _renamed(house[key], old, new)
            changed |= did
    people = house.get("person_calendars")
    if isinstance(people, dict):
        out: dict[str, Any] = {}
        for person, calendars in people.items():
            calendars, did = _renamed(calendars, old, new)
            changed |= did
            if person == old:
                person, changed = new, True
            out[person] = list(dict.fromkeys([*out.get(person, []), *calendars])) if isinstance(calendars, list) else calendars
        house["person_calendars"] = out
    return changed


def proxy_key(value: Any) -> str | None:
    """An ESPHome API encryption key (32 bytes, base64), or None."""
    if not isinstance(value, str) or len(value) > 64:
        return None
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        return None
    return value if len(raw) == 32 else None


def new_proxy_key() -> str:
    """A fresh ESPHome API encryption key: 32 random bytes, base64 (standard, as ESPHome's api encryption key)."""
    import secrets

    return base64.b64encode(secrets.token_bytes(32)).decode()


# The seed: the panel's settings from before it paired, in the document's own shape: (section, field) -> key
_SEED_PANEL = {
    ("panel", "people"): "people",
    ("panel", "extra_areas"): "extra_areas",
    ("look", "motion"): "motion",
    ("photos", "every_s"): "photos_every",
    ("photos", "caption"): "photo_caption",
    ("photos", "on_this_day"): "on_this_day",
    ("calendars", "titles"): "calendar_titles",
    ("wake", "someone_in_front"): "someone_in_front",
    ("wake", "presence"): "presence",
    ("night", "dark_at_night"): "dark_at_night",
    ("doors", "pin_to_unlock"): "pin_to_unlock",
    ("messages", "shared_room_says_who"): "says_who_has_a_message",
    ("routines", "entities"): "routines",
    ("bed", "left"): "bed_left",
    ("bed", "right"): "bed_right",
    ("proxy", "on"): "bluetooth_proxy",
    ("proxy", "name"): "proxy_name",
    ("news", "seen"): "news_seen",
    ("voice", "heard"): "voice_heard",
    ("voice", "reply"): "voice_reply",
    ("voice", "reply_attribute"): "voice_reply_attribute",
    ("voice", "show"): "voice_show",
}
_SEED_HOUSE = {
    ("calendars", "family"): "family_calendars",
    ("calendars", "person"): "person_calendars",
    ("night", "entity"): "night",
    ("doors", "doorbell_camera"): "doorbell_camera",
    ("routines", "windows"): "routine_windows",
    ("routines", "commute"): "commute_window",
    ("photos", "camera"): "photos",
}


def clean_seed(seed: Any, known: Known, house: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], str | None]:
    """(the panel's values, house-wide values not set yet, the proxy key it had) from an untrusted seed: known
    fields only, entities Home Assistant has only, values equal to the derived default dropped. A house-wide value
    is taken only while the house has none; the seed's photo album goes to the panel when the house has another."""
    panel: dict[str, Any] = {}
    new_house: dict[str, Any] = {}
    if not isinstance(seed, dict):
        return panel, new_house, None

    def field(section: str, name: str) -> Any:
        part = seed.get(section)
        return part.get(name) if isinstance(part, dict) else None

    for (section, name), key in _SEED_PANEL.items():
        if key == "pin_to_unlock":
            # Never from an unchecked seed: the PIN stays on until an adult turns it off
            continue
        if (value := panel_value(key, field(section, name), known, strict=False)) is not None:
            panel[key] = value
    for (section, name), key in _SEED_HOUSE.items():
        value = house_value(key, field(section, name), known, strict=False)
        if value is None:
            continue
        if key not in house:
            new_house[key] = value
        elif key == "photos" and house[key] != value:
            panel["photos"] = value
    return panel, new_house, proxy_key(field("proxy", "key"))


def proxy_name(name: str) -> str:
    """The panel's Bluetooth proxy's ESPHome name: "kitchen-panel"."""
    slug = re.sub(r"[^a-z0-9]+", "-", name.casefold()).strip("-")
    return (slug or "panel")[:31].strip("-")


def build(
    domain: str,
    device_id: str,
    *,
    name: str,
    area_id: str | None,
    values: dict[str, Any],
    house: dict[str, Any],
    house_panel: bool,
    panel_areas: list[str],
    key: str | None,
    start: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """The whole document for one panel: every key present, null or [] where the panel derives it. [start]: the
    panel's own Start section ({tiles, changed, version}), None for the room's layout."""
    v = values

    def switch(k: str) -> bool:
        return v.get(k, SWITCHES[k])

    def given(k: str) -> Any:
        return copy.deepcopy(v.get(k))

    bed = {"left": bed_side(v.get("bed_left")), "right": bed_side(v.get("bed_right"))}
    doc: dict[str, Any] = {
        "schema": SCHEMA,
        "served_by": domain,
        "panel": {
            "device_id": device_id,
            "name": name,
            "area_id": area_id,
            "extra_areas": given("extra_areas") or [],
            "people": given("people") or [],
            "house_panel": house_panel,
            "panel_areas": list(panel_areas),
        },
        "look": {"motion": v.get("motion", SELECTS["motion"][0])},
        "photos": {
            "camera": v.get("photos") or house.get("photos"),
            "every_s": v.get("photos_every", SELECTS["photos_every"][0]),
            "caption": switch("photo_caption"),
            "on_this_day": switch("on_this_day"),
        },
        "calendars": {
            "family": copy.deepcopy(house.get("family_calendars")) or [],
            "person": copy.deepcopy(house.get("person_calendars")) or {},
            "titles": switch("calendar_titles"),
        },
        "wake": {"someone_in_front": switch("someone_in_front"), "presence": v.get("presence")},
        "night": {"entity": house.get("night"), "dark_at_night": switch("dark_at_night")},
        "doors": {"pin_to_unlock": switch("pin_to_unlock"), "doorbell_camera": house.get("doorbell_camera")},
        "messages": {"shared_room_says_who": switch("says_who_has_a_message")},
        "routines": {
            "entities": given("routines") or [],
            "windows": copy.deepcopy(house.get("routine_windows") or list(DEFAULT_WINDOWS)),
            "commute": copy.deepcopy(house.get("commute_window") or DEFAULT_COMMUTE),
        },
        "bed": bed if bed["left"] or bed["right"] else None,
        "proxy": {"on": switch("bluetooth_proxy"), "name": v.get("proxy_name") or proxy_name(name), "key": key},
        "voice": {
            "heard": v.get("voice_heard"),
            "reply": v.get("voice_reply"),
            "reply_attribute": v.get("voice_reply_attribute"),
            "show": v.get("voice_show"),
        },
        # Where the panel keeps which news it has shown (an input_text); null: the panel's own fallback
        "news": {"seen": v.get("news_seen")},
        # The panel's own Start (/1.1): null until something is placed (the room's layout)
        "start": copy.deepcopy(start),
    }
    doc["version"] = version_of(doc)
    return doc


def version_of(doc: dict[str, Any]) -> str:
    """A short hash of the content: changes exactly when the content does."""
    content = {k: val for k, val in doc.items() if k != "version"}
    return hashlib.sha256(json.dumps(content, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:8]


def public(doc: dict[str, Any]) -> dict[str, Any]:
    """The document without its secrets (the proxy key), for a service's answer."""
    out = copy.deepcopy(doc)
    out["proxy"].pop("key", None)
    out.pop("version", None)
    return out
