"""The house's media players by room, for a phone's "what's playing where" (see docs/home-assistant-integration.md).

A home tends to have several media_player entities for one thing: an Echo and its "Now Playing" twin, a console and
its Music Assistant player, a TV's remote and its Cast player. These are put together by name (one entity_id or name is
another's plus a known suffix, " (Music Assistant)", "_2"...), each room gets its players, and each player the one
entity to control (the rest are `also`). Only players in an area count, but for speaker groups ("Everywhere"), listed
as their own. Read from the registries and entity states' names only, never from what's playing, so the list changes
when the house's setup does.
"""

from __future__ import annotations

import re
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers import area_registry as ar, device_registry as dr, entity_registry as er

SPEAKER = "speaker"
TV = "tv"
GROUP = "group"

# A twin's entity_id or name is its player's plus one of these
_ID_SUFFIX = re.compile(r"(_now_playing|_music_assistant_display|_music_assistant|_media_player|_\d+)+$")
_NAME_SUFFIX = re.compile(
    r"(\s*\(music assistant(?: display)?\)|\s+now playing|\s+media player)+$", re.IGNORECASE
)

# Which of a player's entities to control: the integration closest to the thing first
_CONTROL_ORDER = (
    "androidtv_remote",
    "denonavr",
    "heos",
    "sonos",
    "xbox",
    "esphome",
    "alexa_media",
    "cast",
    "music_assistant",
)
_TV_PLATFORMS = {"androidtv_remote", "androidtv", "xbox", "webostv", "samsungtv", "braviatv", "roku", "apple_tv"}


# Names that say what a thing is, not which one: never a twin key on their own
_GENERIC_KEYS = {"media player", "player", "speaker", "tv", "display", "music assistant", "now playing"}


def _name_key(name: str | None) -> str | None:
    if not name:
        return None
    key = " ".join(_NAME_SUFFIX.sub("", name).lower().split())
    return key if key and key not in _GENERIC_KEYS else None


def _kind(platform: str | None, model: str | None, device_class: str | None) -> str:
    if model and "group" in model.lower() or platform == "group":
        return GROUP
    if device_class == TV or platform in _TV_PLATFORMS:
        return TV
    return SPEAKER


def media_rooms(hass: HomeAssistant) -> list[dict[str, Any]]:
    """[{room, area_id, entity_id, also, kind, players: [{name, entity_id, also, kind}]}], rooms by name; groups too."""
    entities = er.async_get(hass)
    devices = dr.async_get(hass)
    areas = ar.async_get(hass)
    found: list[dict[str, Any]] = []
    for state in hass.states.async_all("media_player"):
        entry = entities.async_get(state.entity_id)
        if entry is not None and (entry.hidden_by or entry.disabled_by):
            continue
        device = devices.async_get(entry.device_id) if entry and entry.device_id else None
        area_id = (entry.area_id if entry else None) or (device.area_id if device else None)
        platform = entry.platform if entry else None
        names = {state.name}
        if entry and not (device and entry.has_entity_name):
            # With a device and has_entity_name, the entry's names are only the entity part ("Media Player"),
            # the same on every device of the kind; the friendly name and the device's names carry which one
            names |= {entry.name, entry.original_name}
        if device:
            names |= {device.name_by_user, device.name}
        found.append(
            {
                "entity_id": state.entity_id,
                "name": (device.name_by_user or device.name) if device else state.name,
                "area_id": area_id,
                "platform": platform,
                "kind": _kind(platform, device.model if device else None, state.attributes.get("device_class")),
                "keys": {_ID_SUFFIX.sub("", state.entity_id.split(".", 1)[1])} | {k for n in names if (k := _name_key(n))},
                "available": state.state != "unavailable",
            }
        )

    # Twins: entities sharing a key are one player (union-find over the keys)
    parent = list(range(len(found)))

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    # Each player's area (of the first member that has one): members in different areas are never twins
    area_of = [item["area_id"] for item in found]
    owner: dict[str, int] = {}
    for i, item in enumerate(found):
        if item["kind"] == GROUP:
            continue
        for key in item["keys"]:
            if key not in owner:
                owner[key] = i
                continue
            mine, theirs = root(i), root(owner[key])
            if mine == theirs or (area_of[mine] and area_of[theirs] and area_of[mine] != area_of[theirs]):
                continue
            parent[mine] = theirs
            area_of[theirs] = area_of[theirs] or area_of[mine]
    players: dict[int, list[dict[str, Any]]] = {}
    for i, item in enumerate(found):
        players.setdefault(root(i), []).append(item)

    def control_rank(item: dict[str, Any]) -> tuple:
        order = _CONTROL_ORDER.index(item["platform"]) if item["platform"] in _CONTROL_ORDER else len(_CONTROL_ORDER)
        return (not item["available"], order, item["entity_id"])

    rooms: dict[str, dict[str, Any]] = {}
    for members in players.values():
        members.sort(key=control_rank)
        main = members[0]
        area_id = next((m["area_id"] for m in members if m["area_id"]), None)
        kind = TV if any(m["kind"] == TV for m in members) else main["kind"]
        player = {
            "name": main["name"],
            "entity_id": main["entity_id"],
            "also": [m["entity_id"] for m in members[1:]],
            "kind": kind,
        }
        if kind == GROUP:
            # A speaker group is a "room" of its own, named as the group
            rooms[f"group:{main['entity_id']}"] = {"room": main["name"], "area_id": area_id, "players": [player]}
            continue
        if area_id is None:
            continue
        area = areas.async_get_area(area_id)
        room = rooms.setdefault(area_id, {"room": area.name if area else area_id, "area_id": area_id, "players": []})
        room["players"].append(player)

    out = []
    for room in rooms.values():
        # The room's own player: its TV, else what's left by name
        room["players"].sort(key=lambda p: (p["kind"] != TV, p["name"].lower(), p["entity_id"]))
        main = room["players"][0]
        out.append(
            {
                "room": room["room"],
                "area_id": room["area_id"],
                "entity_id": main["entity_id"],
                "also": main["also"],
                "kind": main["kind"],
                "players": room["players"],
            }
        )
    out.sort(key=lambda r: (r["kind"] == GROUP, r["room"].lower()))
    return out
