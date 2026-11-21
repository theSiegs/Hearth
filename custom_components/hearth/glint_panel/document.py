"""A panel's document (glint.panel-config/1), and checking every value that goes into it.

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
    BED_KEYS,
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


def _bed(value: Any, known: Known, strict: bool) -> dict[str, Any] | None:
    if value is None or value == {}:
        return None
    if not isinstance(value, dict) or set(value) - {"connected", "scripts", "positions"}:
        if strict:
            raise Refused(f"A bed side is {{connected, scripts, positions}}, not {value!r}")
        return None
    side = {
        "connected": _entity(value.get("connected"), known, strict),
        "scripts": _entities(value.get("scripts"), known, strict) or [],
        "positions": _entities(value.get("positions"), known, strict) or [],
    }
    return side if side["connected"] or side["scripts"] or side["positions"] else None


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
) -> dict[str, Any]:
    """The whole document for one panel: every key present, null or [] where the panel derives it."""
    v = values

    def switch(k: str) -> bool:
        return v.get(k, SWITCHES[k])

    def given(k: str) -> Any:
        return copy.deepcopy(v.get(k))

    bed = {"left": given("bed_left"), "right": given("bed_right")}
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
