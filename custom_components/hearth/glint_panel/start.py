"""A panel's own Start (the document's `start`, docs/contracts/panel-config.md): checking a layout, its version, the
ops change_panel_start applies, and rewriting a renamed entity.

A layout is a list of tiles, cells counted from 1. `None` (no tiles) is the room's layout: the panel lays it out by its room rule,
which the server never does (a first edit starts from the `room_layout` the panel last reported). Only placed tiles,
hand-made stacks' members and "deals when" rules are stored; stacks derive the rest on the panel. An entity Home
Assistant no longer has is kept: the panel marks its tile until someone removes it.
"""

from __future__ import annotations

import copy
import hashlib
import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from .const import (
    DAYS,
    DEFAULT_PAGE,
    MAX_PAGE,
    START_BUILT_IN,
    START_DEALS_ON,
    START_GRID,
    START_KINDS,
    START_MAX_BYTES,
    START_MAX_DEALS,
    START_MAX_NAME,
    START_MAX_STACK,
    START_MAX_TILES,
)
from .document import Refused

_ID = re.compile(r"^[a-z0-9_]{1,32}$")
_ENTITY = re.compile(r"^[a-z0-9_]+\.[a-z0-9_]+$")
_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
_SIZE = re.compile(r"^\s*(\d+)\s*[x×]\s*(\d+)\s*$")
_CELLS = ("col", "row", "w", "h")


class NotReady(Refused):
    """A first change with no room layout reported yet: the server can't lay out the room itself."""


def _short(value: Any) -> str:
    text = repr(value)
    return text if len(text) <= 60 else text[:57] + "..."


# Checking a whole layout (set_start, a report's room_layout, and every change's result)


def check_start(
    value: Any, never_dealt: Callable[[str], bool], *, grid: int = START_GRID
) -> list[dict[str, Any]] | None:
    """The tiles of a whole `start` (None, or tiles None: the room's layout), cleaned; Refused with the first problem
    in words. Its `changed` and `version` are the server's and are ignored."""
    if value is None:
        return None
    if not isinstance(value, dict) or "tiles" not in value:
        raise Refused("start is null or {tiles}")
    if value["tiles"] is None:
        return None
    return check_tiles(value["tiles"], never_dealt, grid=grid)


def check_tiles(
    tiles: Any, never_dealt: Callable[[str], bool], *, built_in_only: bool = False, grid: int = START_GRID
) -> list[dict[str, Any]]:
    """A list of tiles, cleaned (known fields only), in its own order; Refused with the first problem in words. No tile
    goes past cell [grid] either way (the panel leaves out a tile off its page)."""
    if not isinstance(tiles, list):
        raise Refused("tiles is a list")
    if len(tiles) > START_MAX_TILES:
        raise Refused(f"more than {START_MAX_TILES} tiles")
    try:
        size = len(json.dumps(tiles, separators=(",", ":")))
    except (TypeError, ValueError) as err:
        raise Refused("tiles aren't JSON") from err
    if size > START_MAX_BYTES:
        raise Refused(f"more than {START_MAX_BYTES // 1024} KB of tiles")
    out: list[dict[str, Any]] = []
    taken: dict[tuple[int, int], str] = {}
    for raw in tiles:
        tile = _tile(raw, never_dealt, built_in_only, grid)
        if any(t["id"] == tile["id"] for t in out):
            raise Refused(f"two tiles are called {tile['id']}")
        if tile["kind"] in START_BUILT_IN and any(t["kind"] == tile["kind"] for t in out):
            raise Refused(f"only one {_words(tile['kind'])} on Start")
        for cell in cells(tile):
            if cell in taken:
                raise Refused(f"tiles {tile['id']} and {taken[cell]} overlap")
        taken.update(dict.fromkeys(cells(tile), tile["id"]))
        out.append(tile)
    return out


def _tile(raw: Any, never_dealt: Callable[[str], bool], built_in_only: bool, grid: int) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise Refused(f"not a tile: {_short(raw)}")
    kind = raw.get("kind")
    if kind not in START_KINDS or (built_in_only and kind not in START_BUILT_IN):
        raise Refused(f"no tile kind {kind}" if isinstance(kind, str) else "a tile has no kind")
    tile_id = raw.get("id")
    if not isinstance(tile_id, str) or not _ID.match(tile_id):
        raise Refused(f"not a tile id: {_short(tile_id)}")
    tile: dict[str, Any] = {"id": tile_id, "kind": kind}
    for key in _CELLS:
        value = raw.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            raise Refused(f"tile {tile_id}'s {key} is a whole number from 1")
        tile[key] = value
    if tile["col"] + tile["w"] - 1 > grid or tile["row"] + tile["h"] - 1 > grid:
        raise Refused(f"tile {tile_id} goes past cell {grid}")
    if kind == "entity":
        entity = raw.get("entity")
        if not isinstance(entity, str) or not _ENTITY.match(entity):
            raise Refused(f"tile {tile_id} needs an entity")
        tile["entity"] = entity
    if kind == "stack":
        name = raw.get("name")
        if not isinstance(name, str) or not 0 < len(name.strip()) <= START_MAX_NAME:
            raise Refused(f"stack {tile_id} needs a name of at most {START_MAX_NAME} letters")
        members = raw.get("entities")
        if (
            not isinstance(members, list)
            or not 0 < len(members) <= START_MAX_STACK
            or any(not isinstance(e, str) or not _ENTITY.match(e) for e in members)
        ):
            raise Refused(f"stack {tile_id} needs 1 to {START_MAX_STACK} entities")
        if len(set(members)) != len(members):
            raise Refused(f"stack {tile_id} names an entity twice")
        tile["name"] = name.strip()
        tile["entities"] = list(members)
    deals = raw.get("deals")
    if deals is not None and deals != []:
        if kind not in START_DEALS_ON:
            raise Refused(f"only a room stack or a stack deals, not tile {tile_id}")
        tile["deals"] = _deals(deals, tile_id, never_dealt)
    return tile


def _deals(value: Any, tile_id: str, never_dealt: Callable[[str], bool]) -> list[dict[str, Any]]:
    if not isinstance(value, list) or len(value) > START_MAX_DEALS:
        raise Refused(f"tile {tile_id}'s deals is a list of at most {START_MAX_DEALS}")
    out: list[dict[str, Any]] = []
    for deal in value:
        if not isinstance(deal, dict) or set(deal) - {"entity", "when"}:
            raise Refused(f"a deal is {{entity, when}}, not {_short(deal)}")
        entity = deal.get("entity")
        if not isinstance(entity, str) or not _ENTITY.match(entity):
            raise Refused(f"not an entity id: {_short(entity)}")
        if never_dealt(entity):
            raise Refused(f"{entity} is a normal state, never dealt")
        if any(d["entity"] == entity for d in out):
            raise Refused(f"{entity} is dealt twice in tile {tile_id}")
        out.append({"entity": entity, "when": when(deal.get("when"))})
    return out


def when(value: Any) -> str | dict[str, Any]:
    """A deal's `when`: "on", or a window {from, until, days} (HH:MM, mon...sun)."""
    if value == "on":
        return "on"
    days = value.get("days") if isinstance(value, dict) else None
    if (
        isinstance(value, dict)
        and not set(value) - {"from", "until", "days"}
        and isinstance(value.get("from"), str)
        and _TIME.match(value["from"])
        and isinstance(value.get("until"), str)
        and _TIME.match(value["until"])
        and isinstance(days, list)
        and days
        and all(d in DAYS for d in days)
    ):
        return {"from": value["from"], "until": value["until"], "days": [d for d in DAYS if d in days]}
    raise Refused(f'when is "on" or {{from, until, days}}, not {_short(value)}')


def version_of(tiles: list[dict[str, Any]] | None) -> str | None:
    """The first 8 hex digits of a SHA-256 of the tiles only (a new stamp alone doesn't change it); None for the room's
    layout."""
    if tiles is None:
        return None
    return hashlib.sha256(json.dumps(tiles, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:8]


def cells(tile: dict[str, Any]) -> set[tuple[int, int]]:
    return {
        (col, row)
        for col in range(tile["col"], tile["col"] + tile["w"])
        for row in range(tile["row"], tile["row"] + tile["h"])
    }


def rename(tiles: list[dict[str, Any]] | None, old: str, new: str) -> bool:
    """Rewrites a renamed entity id everywhere in [tiles] (in place); whether anything changed."""
    changed = False
    for tile in tiles or ():
        if tile.get("entity") == old:
            tile["entity"] = new
            changed = True
        if old in (members := tile.get("entities") or []):
            tile["entities"] = list(dict.fromkeys(new if e == old else e for e in members))
            changed = True
        for deal in tile.get("deals") or ():
            if deal.get("entity") == old:
                deal["entity"] = new
                changed = True
    return changed


# change_panel_start's ops


@dataclass
class Context:
    """What the ops need: the room's layout to start from (raises NotReady), whether Home Assistant has an entity,
    which entities are never dealt, and the panel's page (cols, rows) that tiles are fitted on."""

    seed: Callable[[], list[dict[str, Any]]]
    entity: Callable[[str], bool]
    never_dealt: Callable[[str], bool]
    page: tuple[int, int] = DEFAULT_PAGE


def apply(
    tiles: list[dict[str, Any]] | None, ops: Any, ctx: Context
) -> tuple[list[dict[str, Any]] | None, list[str]]:
    """[ops] applied in order to a copy of [tiles]: (the new tiles, the words for each op). All or none: Refused with
    the words of the first that can't be done."""
    if not isinstance(ops, list) or not ops:
        raise Refused("ops is a list of changes")
    work = copy.deepcopy(tiles)
    said: list[str] = []
    for op in ops:
        if not isinstance(op, dict) or not isinstance(op.get("op"), str):
            raise Refused(f"not an op: {_short(op)}")
        name = op["op"]
        if name == "reset":
            work = None
            said.append("back to the room's layout")
            continue
        if name not in _OPS:
            raise Refused(f"no op {name}")
        if work is None:
            work = copy.deepcopy(ctx.seed())
        said.append(_OPS[name](work, op, ctx))
    final = None if work is None else check_tiles(work, ctx.never_dealt, grid=max(START_GRID, *ctx.page))
    return final, said


def _find(tiles: list[dict[str, Any]], op: dict[str, Any]) -> dict[str, Any]:
    tile_id = op.get("tile")
    found = next((t for t in tiles if t["id"] == tile_id), None) if isinstance(tile_id, str) else None
    if found is None:
        raise Refused(f"no tile {tile_id}" if isinstance(tile_id, str) else "which tile?")
    return found


def _size(value: Any, default: tuple[int, int] | None = None) -> tuple[int, int]:
    if value is None and default is not None:
        return default
    match = _SIZE.match(value) if isinstance(value, str) else None
    if match is None or not all(1 <= int(n) <= MAX_PAGE for n in match.groups()):
        raise Refused(f'size is "WxH" (1 to {MAX_PAGE}), not {_short(value)}')
    return int(match[1]), int(match[2])


def _at(value: Any) -> tuple[int, int] | None:
    if value is None:
        return None
    if (
        not isinstance(value, (list, tuple))
        or len(value) != 2
        or any(not isinstance(n, int) or isinstance(n, bool) or n < 1 for n in value)
    ):
        raise Refused(f"at is [column, row] from 1, not {_short(value)}")
    return value[0], value[1]


def _fits(
    tiles: list[dict[str, Any]], page: tuple[int, int], col: int, row: int, w: int, h: int,
    skip: dict[str, Any] | None = None,
) -> bool:
    """On the page, over no other tile."""
    if col + w - 1 > page[0] or row + h - 1 > page[1]:
        return False
    wanted = cells({"col": col, "row": row, "w": w, "h": h})
    return not any(wanted & cells(t) for t in tiles if t is not skip)


def _place(
    tiles: list[dict[str, Any]], page: tuple[int, int], size: tuple[int, int], at: tuple[int, int] | None
) -> tuple[int, int]:
    """Where a new tile of [size] goes: at [at] if it fits, else (no at) the first fit on the page from the top-left,
    row by row."""
    w, h = size
    if at is not None:
        if not _fits(tiles, page, *at, w, h):
            raise Refused(f"no room for a {w}×{h} tile at column {at[0]}, row {at[1]}")
        return at
    for row in range(1, page[1] - h + 2):
        for col in range(1, page[0] - w + 2):
            if _fits(tiles, page, col, row, w, h):
                return col, row
    raise Refused(f"no room for a {w}×{h} tile")


def _new_id(tiles: list[dict[str, Any]], base: str) -> str:
    base = re.sub(r"[^a-z0-9_]", "_", base.casefold())[:30] or "tile"
    taken = {t["id"] for t in tiles}
    if base not in taken:
        return base
    n = 2
    while f"{base}{n}" in taken:
        n += 1
    return f"{base}{n}"


def _words(text: str) -> str:
    return text.replace("_", " ")


def label(tile: dict[str, Any]) -> str:
    """A tile in words: "heat lamp", "stack porch and yard", "room stack"."""
    if tile["kind"] == "entity":
        return _words(tile["entity"].split(".", 1)[1])
    if tile["kind"] == "stack":
        return f"stack {tile['name']}"
    return _words(tile["kind"])


def _where(tile: dict[str, Any]) -> str:
    return f"column {tile['col']}, row {tile['row']}"


def _entity(value: Any, ctx: Context) -> str:
    if not isinstance(value, str) or not _ENTITY.match(value):
        raise Refused(f"not an entity id: {_short(value)}")
    if not ctx.entity(value):
        raise Refused(f"no entity {value}")
    return value


def _add(tiles: list[dict[str, Any]], op: dict[str, Any], ctx: Context) -> str:
    kind = op.get("kind") or "entity"
    if kind == "stack":
        raise Refused("a stack is made with make_stack")
    if kind not in START_KINDS:
        raise Refused(f"no tile kind {kind}")
    tile: dict[str, Any] = {"kind": kind}
    if kind == "entity":
        entity = _entity(op.get("entity"), ctx)
        if any(t.get("entity") == entity for t in tiles):
            raise Refused(f"{entity} is on Start already")
        tile["id"] = _new_id(tiles, entity.split(".", 1)[1])
        tile["entity"] = entity
    else:
        if any(t["kind"] == kind for t in tiles):
            raise Refused(f"the {_words(kind)} is on Start already")
        tile["id"] = _new_id(tiles, kind)
    w, h = _size(op.get("size"), (2, 1))
    tile["col"], tile["row"] = _place(tiles, ctx.page, (w, h), _at(op.get("at")))
    tile["w"], tile["h"] = w, h
    tiles.append(tile)
    return f"{label(tile)} placed at {_where(tile)}"


def _move(tiles: list[dict[str, Any]], op: dict[str, Any], ctx: Context) -> str:
    tile = _find(tiles, op)
    at = _at(op.get("at"))
    if at is None:
        raise Refused("move needs at [column, row]")
    if not _fits(tiles, ctx.page, *at, tile["w"], tile["h"], skip=tile):
        raise Refused(f"no room for {label(tile)} at column {at[0]}, row {at[1]}")
    tile["col"], tile["row"] = at
    return f"{label(tile)} moved to {_where(tile)}"


def _resize(tiles: list[dict[str, Any]], op: dict[str, Any], ctx: Context) -> str:
    tile = _find(tiles, op)
    w, h = _size(op.get("size"))
    if not _fits(tiles, ctx.page, tile["col"], tile["row"], w, h, skip=tile):
        raise Refused(f"no room for a {w}×{h} tile at {_where(tile)}")
    tile["w"], tile["h"] = w, h
    return f"{label(tile)} is now {w}×{h}"


def _remove(tiles: list[dict[str, Any]], op: dict[str, Any], _ctx: Context) -> str:
    tile = _find(tiles, op)
    tiles.remove(tile)
    return f"{label(tile)} taken off Start"


def _deal(tiles: list[dict[str, Any]], op: dict[str, Any], ctx: Context) -> str:
    tile = _find(tiles, op)
    if tile["kind"] not in START_DEALS_ON:
        raise Refused(f"only a room stack or a stack deals, not {label(tile)}")
    entity = op.get("entity")
    if not isinstance(entity, str) or not _ENTITY.match(entity):
        raise Refused(f"not an entity id: {_short(entity)}")
    if "when" not in op:
        raise Refused('deals needs when: "on", {from, until, days} or null to stop')
    deals = [d for d in tile.get("deals", []) if d["entity"] != entity]
    if op["when"] is None:
        if deals:
            tile["deals"] = deals
        else:
            tile.pop("deals", None)
        return f"{entity} no longer dealt from {label(tile)}"
    if tile["kind"] == "stack" and entity not in tile["entities"]:
        raise Refused(f"{entity} isn't in {label(tile)}")
    if tile["kind"] != "stack":
        _entity(entity, ctx)
    if ctx.never_dealt(entity):
        raise Refused(f"{entity} is a normal state, never dealt")
    rule = when(op["when"])
    tile["deals"] = [*deals, {"entity": entity, "when": rule}]
    words = "when it's on" if rule == "on" else f"from {rule['from']} until {rule['until']} on {', '.join(rule['days'])}"
    return f"{entity} dealt from {label(tile)} {words}"


def _make_stack(tiles: list[dict[str, Any]], op: dict[str, Any], ctx: Context) -> str:
    name = op.get("name")
    if not isinstance(name, str) or not 0 < len(name.strip()) <= START_MAX_NAME:
        raise Refused(f"a stack needs a name of at most {START_MAX_NAME} letters")
    members = op.get("entities")
    if isinstance(members, str):
        members = [members]
    if not isinstance(members, list) or not 0 < len(members) <= START_MAX_STACK:
        raise Refused(f"a stack has 1 to {START_MAX_STACK} entities")
    members = list(dict.fromkeys(_entity(e, ctx) for e in members))
    # Its devices leave Start on their own, and leave other hand-made stacks (and those stacks' deals)
    for tile in list(tiles):
        if tile["kind"] == "entity" and tile["entity"] in members:
            tiles.remove(tile)
        elif tile["kind"] == "stack" and set(tile["entities"]) & set(members):
            tile["entities"] = [e for e in tile["entities"] if e not in members]
            if deals := [d for d in tile.get("deals", []) if d["entity"] not in members]:
                tile["deals"] = deals
            else:
                tile.pop("deals", None)
            if not tile["entities"]:
                tiles.remove(tile)
    tile: dict[str, Any] = {"id": _new_id(tiles, "stack"), "kind": "stack", "name": name.strip(), "entities": members}
    w, h = _size(op.get("size"), (2, 1))
    tile["col"], tile["row"] = _place(tiles, ctx.page, (w, h), _at(op.get("at")))
    tile["w"], tile["h"] = w, h
    tiles.append(tile)
    return f"{label(tile)} made at {_where(tile)}"


_OPS: dict[str, Callable[[list[dict[str, Any]], dict[str, Any], Context], str]] = {
    "add": _add,
    "move": _move,
    "resize": _resize,
    "remove": _remove,
    "deals": _deal,
    "make_stack": _make_stack,
}
