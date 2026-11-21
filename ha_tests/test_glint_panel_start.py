"""A Glint Panel's own Start (the document's `start`, docs/contracts/panel-config.md): checking a layout, set_start from
the wall (stale, invalid, too often, unauthorized), change_panel_start and undo_panel_start, the last 10 changes, the
room layout a report brings, entity renames, and get_panel."""

import hashlib
import json

import pytest
from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator
from test_glint_panel import (  # noqa: F401 (the autouse fixture: the panels' shared login and tokens)
    OTHER_ID,
    PANEL_ID,
    _after_push,
    _device,
    _displays,
    _household,
    _pair_panel,
    _panels,
    _subscribe,
)

from custom_components.hearth import async_remove_config_entry_device
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glint_panel import start
from custom_components.hearth.glint_panel.document import Refused

ROOM = [
    {"id": "clock", "kind": "clock", "col": 1, "row": 1, "w": 2, "h": 1},
    {"id": "calendar", "kind": "calendar", "col": 3, "row": 1, "w": 2, "h": 2},
    {"id": "room_stack", "kind": "room_stack", "col": 1, "row": 3, "w": 2, "h": 1},
]
LAMP = {"id": "test_lamp", "kind": "entity", "entity": "switch.test_lamp", "col": 7, "row": 3, "w": 2, "h": 1}


def _never(entity_id: str) -> bool:
    return entity_id.split(".")[0] in ("lock", "binary_sensor")


def _version(tiles) -> str:
    return hashlib.sha256(json.dumps(tiles, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:8]


async def _set_up_panel(hass, hass_client_no_auth, **kw) -> dict:
    _entry, client = await _household(hass, hass_client_no_auth)
    for entity_id in ("switch.test_lamp", "light.porch", "light.yard", "fan.bedroom_fan", "lock.front_door"):
        hass.states.async_set(entity_id, "off")
    hass.states.async_set("cover.garage_door", "closed", {"device_class": "garage"})
    hass.states.async_set("cover.blinds", "open", {"device_class": "blind"})
    return await _pair_panel(hass, client, area_id="kitchen", **kw)


async def _ws(hass_ws_client, hass, body):
    return await hass_ws_client(hass, access_token=body["ha_token"])


async def _send(ws, msg_id: int, body: dict, type_: str, device_id: str = PANEL_ID, **fields) -> dict:
    await ws.send_json({"id": msg_id, "type": f"hearth/panel/{type_}", "device_id": device_id, "secret": body["secret"], **fields})
    while True:
        answer = await ws.receive_json()
        if answer["id"] == msg_id and answer["type"] == "result":
            return answer


async def _change(hass, ops, device_id: str | None = None, **extra) -> dict:
    return await hass.services.async_call(
        DOMAIN, "change_panel_start", {"device_id": device_id or _device(hass).id, "ops": ops, **extra},
        blocking=True, return_response=True,
    )


# Checking a layout


def test_a_whole_layout_is_checked_and_the_first_problem_said() -> None:
    assert start.check_start(None, _never) is None
    assert start.check_start({"tiles": [*ROOM, LAMP], "changed": {"by": "x"}, "version": "x"}, _never) == [*ROOM, LAMP]
    # Unknown fields are dropped; deals and stacks are kept as given
    stack = {"id": "stack", "kind": "stack", "name": " porch and yard ", "entities": ["light.porch", "light.yard"],
             "col": 5, "row": 4, "w": 2, "h": 1, "face": "big",
             "deals": [{"entity": "light.porch", "when": {"from": "18:00", "until": "22:00", "days": ["sun", "mon"]}}]}
    [cleaned] = start.check_tiles([stack], _never)
    assert "face" not in cleaned and cleaned["name"] == "porch and yard"
    assert cleaned["deals"] == [{"entity": "light.porch", "when": {"from": "18:00", "until": "22:00", "days": ["mon", "sun"]}}]

    def why(tiles) -> str:
        with pytest.raises(Refused) as err:
            start.check_tiles(tiles, _never)
        return str(err.value)

    assert why([{**LAMP, "kind": "toaster"}]) == "no tile kind toaster"
    assert why([{**LAMP, "id": "Heat-Lamp"}]).startswith("not a tile id")
    assert why([{**LAMP, "id": "x" * 33}]).startswith("not a tile id")
    assert why([LAMP, {**LAMP, "col": 1}]) == "two tiles are called test_lamp"
    assert why([ROOM[0], {**ROOM[0], "id": "clock2", "row": 4}]) == "only one clock on Start"
    assert why([ROOM[0], {**LAMP, "col": 2, "row": 1}]) == "tiles test_lamp and clock overlap"
    assert why([{**LAMP, "col": 0}]) == "tile test_lamp's col is a whole number from 1"
    assert why([{**LAMP, "w": True}]) == "tile test_lamp's w is a whole number from 1"
    assert why([{**LAMP, "col": 8}]) == "tile test_lamp goes past cell 8"
    assert why([{**LAMP, "row": 8, "h": 2}]) == "tile test_lamp goes past cell 8"
    # The larger side is 8: a tile in rows 6 to 8 is the server's to keep (the panel leaves it out in landscape)
    assert start.check_tiles([{**LAMP, "row": 8}], _never)
    assert why([{**LAMP, "entity": None}]) == "tile test_lamp needs an entity"
    assert why([{**stack, "entities": []}]) == "stack stack needs 1 to 12 entities"
    assert why([{**stack, "entities": [f"light.l{n}" for n in range(13)]}]) == "stack stack needs 1 to 12 entities"
    assert why([{**stack, "name": ""}]).startswith("stack stack needs a name")
    assert why([{**ROOM[0], "deals": [{"entity": "fan.bedroom_fan", "when": "on"}]}]) == (
        "only a room stack or a stack deals, not tile clock"
    )
    deal = {**ROOM[2], "deals": [{"entity": "lock.front_door", "when": "on"}]}
    assert why([deal]) == "lock.front_door is a normal state, never dealt"
    assert why([{**ROOM[2], "deals": [{"entity": "fan.f", "when": "sometimes"}]}]).startswith('when is "on"')
    assert why([{**ROOM[2], "deals": [{"entity": "fan.f", "when": {"from": "25:00", "until": "22:00", "days": ["mon"]}}]}])
    assert why([{**ROOM[2], "deals": [{"entity": "fan.f", "when": "on"}] * 2}]) == "fan.f is dealt twice in tile room_stack"
    # At most 40 tiles and 16 KB
    many = [{"id": f"t{n}", "kind": "entity", "entity": f"light.l{n}", "col": 1 + n % 8, "row": 1 + n // 8, "w": 1, "h": 1}
            for n in range(41)]
    assert why(many) == "more than 40 tiles"
    big = [{**stack, "name": "x" * 40, "entities": [f"light.{'a' * 900}{n}" for n in range(12)],
            "col": 1, "row": n + 1, "w": 1, "h": 1, "id": f"s{n}"} for n in range(2)]
    assert why(big) == "more than 16 KB of tiles"
    # A room layout is built-in kinds only
    with pytest.raises(Refused, match="no tile kind entity"):
        start.check_tiles([LAMP], _never, built_in_only=True)


def test_the_version_is_of_the_tiles_only() -> None:
    assert start.version_of(None) is None
    assert start.version_of(ROOM) == _version(ROOM) and len(start.version_of(ROOM)) == 8
    assert start.version_of([*ROOM, LAMP]) != start.version_of(ROOM)


# set_start from the wall


async def test_set_start_from_the_wall_stores_stamps_and_pushes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws, doc = await _subscribe(hass_ws_client, hass, body)
    assert doc["start"] is None and doc["schema"] == "glint.panel-config/1.1"

    # The first time (the panel kept a Start on the tablet before the server had one): base_version null
    answer = await _send(ws, 2, body, "set_start", start={"tiles": [*ROOM, LAMP]}, base_version=None)
    assert answer["success"], answer
    assert answer["result"]["version"] == _version([*ROOM, LAMP]) and answer["result"]["undo"]
    await _after_push(hass)
    pushed = (await ws.receive_json())["event"]
    assert pushed["start"]["tiles"] == [*ROOM, LAMP]
    assert pushed["start"]["version"] == answer["result"]["version"]
    assert pushed["start"]["changed"]["by"] == "panel" and pushed["start"]["changed"]["undo"] == answer["result"]["undo"]
    assert pushed["start"]["changed"]["at"].endswith("Z")
    assert pushed["version"] != doc["version"]

    # From the version it has: taken; the same tiles keep the same start version (a new stamp alone doesn't change it)
    again = await _send(ws, 3, body, "set_start", start=pushed["start"], base_version=pushed["start"]["version"])
    assert again["success"] and again["result"]["version"] == pushed["start"]["version"]
    assert again["result"]["undo"] != answer["result"]["undo"]

    # Back to the room's layout
    back = await _send(ws, 4, body, "set_start", start=None, base_version=pushed["start"]["version"])
    assert back["success"] and back["result"]["version"] is None
    assert _panels(hass).document(PANEL_ID)["start"] is None


async def test_set_start_from_an_old_version_is_stale(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws = await _ws(hass_ws_client, hass, body)
    stale = await _send(ws, 1, body, "set_start", start={"tiles": ROOM}, base_version="0badc0de")
    assert not stale["success"] and stale["error"]["code"] == "stale"
    assert stale["error"]["translation_placeholders"] == {"version": ""}
    assert _panels(hass).start_tiles(PANEL_ID) is None

    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    await _change(hass, [{"op": "add", "entity": "switch.test_lamp"}])
    stored = _panels(hass).start_version(PANEL_ID)
    # An edit from the room's layout (base null) after Home Assistant changed it: stale, with the stored version
    stale = await _send(ws, 2, body, "set_start", start={"tiles": ROOM}, base_version=None)
    assert stale["error"]["code"] == "stale" and stale["error"]["translation_placeholders"] == {"version": stored}
    assert stale["error"]["translation_key"] == "stale"
    assert _panels(hass).start_version(PANEL_ID) == stored


async def test_set_start_refuses_a_bad_layout_with_why(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws = await _ws(hass_ws_client, hass, body)
    cases = (
        ({"tiles": [{**LAMP, "kind": "toaster"}]}, "no tile kind toaster"),
        ({"tiles": [{**ROOM[2], "deals": [{"entity": "lock.front_door", "when": "on"}]}]},
         "lock.front_door is a normal state, never dealt"),
        ({"tiles": [{**ROOM[2], "deals": [{"entity": "cover.garage_door", "when": "on"}]}]},
         "cover.garage_door is a normal state, never dealt"),
        ({"tiles": [ROOM[0], {**LAMP, "id": "heat_lamp", "col": 1, "row": 1}]}, "tiles heat_lamp and clock overlap"),
        ({"tiles": "clock"}, "tiles is a list"),
        ({"layout": []}, "start is null or {tiles}"),
    )
    for n, (value, why) in enumerate(cases, start=1):
        answer = await _send(ws, n, body, "set_start", start=value, base_version=None)
        assert not answer["success"] and answer["error"]["code"] == "invalid", answer
        assert answer["error"]["translation_placeholders"] == {"why": why}
    assert _panels(hass).start_tiles(PANEL_ID) is None
    # A cover of another class may be dealt
    blinds = {**ROOM[2], "deals": [{"entity": "cover.blinds", "when": "on"}]}
    assert (await _send(ws, 20, body, "set_start", start={"tiles": [blinds]}, base_version=None))["success"]


async def test_set_start_is_thirty_a_minute_and_the_panel_s_own_secret(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws = await _ws(hass_ws_client, hass, body)
    wrong = await _send(ws, 1, {"secret": "not-the-secret"}, "set_start", start=None, base_version=None)
    assert wrong["error"]["code"] == "unauthorized"
    for n in range(2, 32):
        assert (await _send(ws, n, body, "set_start", start={"tiles": []}, base_version="0badc0de"))["error"]["code"] == "stale"
    assert (await _send(ws, 40, body, "set_start", start=None, base_version=None))["error"]["code"] == "too_often"
    # Counted apart from reports
    assert (await _send(ws, 41, body, "report", view="tiles"))["success"]


async def test_another_panel_s_secret_never_sets_this_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    bedroom = await _pair_panel(hass, client, OTHER_ID, area_id="bedroom")
    ws = await _ws(hass_ws_client, hass, bedroom)
    answer = await _send(ws, 1, bedroom, "set_start", device_id=PANEL_ID, start={"tiles": ROOM}, base_version=None)
    assert answer["error"]["code"] == "unauthorized"
    assert _panels(hass).start_tiles(PANEL_ID) is None


# The room layout a report brings


async def test_a_report_keeps_the_room_layout_built_in_kinds_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws = await _ws(hass_ws_client, hass, body)
    bad = await _send(ws, 1, body, "report", view="tiles", room_layout=[*ROOM, LAMP])
    assert bad["error"]["code"] == "invalid"
    assert bad["error"]["translation_placeholders"] == {"why": "no tile kind entity"}
    assert "room_layout" not in _panels(hass).panels[PANEL_ID]
    assert (await _send(ws, 2, body, "report", room_layout=ROOM))["success"]
    assert _panels(hass).panels[PANEL_ID]["room_layout"] == ROOM
    # The room layout isn't the panel's Start: the document is unchanged
    assert _panels(hass).document(PANEL_ID)["start"] is None


# change_panel_start


async def test_the_first_change_needs_the_room_layout(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError, match="the panel hasn't said its layout yet"):
        await _change(hass, [{"op": "add", "entity": "switch.test_lamp"}])
    assert _panels(hass).start_tiles(PANEL_ID) is None
    # reset alone needs no layout
    answer = await _change(hass, [{"op": "reset"}])
    assert answer["changed"] == "back to the room's layout" and answer["start"] is None

    ws = await _ws(hass_ws_client, hass, body)
    assert (await _send(ws, 1, body, "report", room_layout=ROOM))["success"]
    answer = await _change(hass, [{"op": "add", "entity": "switch.test_lamp"}])
    # The first fit from the top-left, row by row, next to the room's own tiles
    assert answer["changed"] == "test lamp placed at column 5, row 1"
    assert answer["start"]["tiles"] == [*ROOM, {**LAMP, "col": 5, "row": 1}]
    assert answer["start"]["changed"]["by"] == "home assistant" and answer["start"]["changed"]["undo"] == answer["undo"]
    assert answer["start"]["version"] == _version(answer["start"]["tiles"])
    assert "key" not in json.dumps(answer) and body["secret"] not in json.dumps(answer)


async def test_change_panel_start_ops_and_words(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    ws, _doc = await _subscribe(hass_ws_client, hass, body)
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM

    answer = await _change(
        hass,
        [
            {"op": "add", "entity": "switch.test_lamp", "at": [7, 3]},
            {"op": "add", "kind": "weather", "size": "2x2", "at": [5, 1]},
            {"op": "move", "tile": "clock", "at": [1, 5]},
            {"op": "resize", "tile": "test_lamp", "size": "1x1"},
            {"op": "deals", "tile": "room_stack", "entity": "fan.bedroom_fan", "when": "on"},
            {"op": "deals", "tile": "room_stack", "entity": "light.porch",
             "when": {"from": "18:00", "until": "22:00", "days": ["mon", "tue"]}},
        ],
        by="claude",
    )
    assert answer["changed"] == (
        "test lamp placed at column 7, row 3; weather placed at column 5, row 1; clock moved to column 1, row 5; "
        "test lamp is now 1×1; fan.bedroom_fan dealt from room stack when it's on; "
        "light.porch dealt from room stack from 18:00 until 22:00 on mon, tue"
    )
    tiles = {t["id"]: t for t in answer["start"]["tiles"]}
    assert tiles["test_lamp"] == {**LAMP, "w": 1}
    assert tiles["weather"] == {"id": "weather", "kind": "weather", "col": 5, "row": 1, "w": 2, "h": 2}
    assert (tiles["clock"]["col"], tiles["clock"]["row"]) == (1, 5)
    assert tiles["room_stack"]["deals"][0] == {"entity": "fan.bedroom_fan", "when": "on"}
    assert answer["start"]["changed"]["by"] == "claude"
    await _after_push(hass)
    assert (await ws.receive_json())["event"]["start"] == answer["start"]

    # A hand-made stack takes its devices' own tiles off Start
    answer = await _change(
        hass, [{"op": "make_stack", "name": "porch and lamp", "entities": ["light.porch", "switch.test_lamp"]},
               {"op": "deals", "tile": "stack", "entity": "light.porch", "when": "on"}],
    )
    tiles = {t["id"]: t for t in answer["start"]["tiles"]}
    assert "test_lamp" not in tiles
    assert tiles["stack"]["entities"] == ["light.porch", "switch.test_lamp"] and tiles["stack"]["deals"]
    assert answer["changed"].startswith("stack porch and lamp made at column ")
    # ... and leave other hand-made stacks (an emptied one goes)
    answer = await _change(hass, [{"op": "make_stack", "name": "lamp", "entities": "switch.test_lamp"}])
    tiles = {t["id"]: t for t in answer["start"]["tiles"]}
    assert tiles["stack"]["entities"] == ["light.porch"] and tiles["stack2"]["entities"] == ["switch.test_lamp"]
    answer = await _change(hass, [{"op": "make_stack", "name": "porch", "entities": ["light.porch"]}])
    stacks = {t["name"]: t["entities"] for t in answer["start"]["tiles"] if t["kind"] == "stack"}
    assert stacks == {"lamp": ["switch.test_lamp"], "porch": ["light.porch"]}
    # Stop dealing, remove, reset
    answer = await _change(
        hass, [{"op": "deals", "tile": "room_stack", "entity": "fan.bedroom_fan", "when": None},
               {"op": "remove", "tile": "weather"}],
    )
    assert answer["changed"] == "fan.bedroom_fan no longer dealt from room stack; weather taken off Start"
    room = next(t for t in answer["start"]["tiles"] if t["id"] == "room_stack")
    assert [d["entity"] for d in room["deals"]] == ["light.porch"]
    answer = await _change(hass, [{"op": "reset"}])
    assert answer["start"] is None and _panels(hass).document(PANEL_ID)["start"] is None


async def test_a_refused_change_changes_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up_panel(hass, hass_client_no_auth)
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    first = await _change(hass, [{"op": "add", "entity": "switch.test_lamp", "at": [7, 3]}])
    before = _panels(hass).start_section(PANEL_ID)
    refusals = (
        ([{"op": "add", "kind": "weather"}, {"op": "remove", "tile": "lamp"}], "no tile lamp"),
        ([{"op": "add", "kind": "clock"}], "the clock is on Start already"),
        ([{"op": "add", "entity": "switch.test_lamp"}], "switch.test_lamp is on Start already"),
        ([{"op": "add", "entity": "switch.nothing"}], "no entity switch.nothing"),
        ([{"op": "add", "kind": "toaster"}], "no tile kind toaster"),
        ([{"op": "add", "kind": "weather", "size": "8x8"}], "no room for a 8×8 tile"),
        ([{"op": "add", "kind": "weather", "size": "2x2", "at": [1, 1]}], "no room for a 2×2 tile at column 1, row 1"),
        ([{"op": "move", "tile": "test_lamp", "at": [1, 1]}], "no room for test lamp at column 1, row 1"),
        ([{"op": "resize", "tile": "test_lamp", "size": "3x1"}], "no room for a 3×1 tile at column 7, row 3"),
        ([{"op": "deals", "tile": "clock", "entity": "fan.bedroom_fan", "when": "on"}],
         "only a room stack or a stack deals, not clock"),
        ([{"op": "deals", "tile": "room_stack", "entity": "lock.front_door", "when": "on"}],
         "lock.front_door is a normal state, never dealt"),
        ([{"op": "make_stack", "name": "all", "entities": []}], "a stack has 1 to 12 entities"),
        ([{"op": "explode"}], "no op explode"),
    )
    for ops, words in refusals:
        with pytest.raises(ServiceValidationError) as err:
            await _change(hass, ops)
        assert str(err.value) == words, ops
    assert _panels(hass).start_section(PANEL_ID) == before
    assert [v["undo"] for v in _panels(hass).start_versions(PANEL_ID)] == [first["undo"]]


async def test_only_adults_change_a_panel_s_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user, hass_admin_user
) -> None:
    await _set_up_panel(hass, hass_client_no_auth)
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    target = _device(hass).id
    for service, data in (
        ("change_panel_start", {"device_id": target, "ops": [{"op": "reset"}]}),
        ("undo_panel_start", {"device_id": target, "undo": "abc"}),
    ):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, service, data, blocking=True, context=Context(user_id=hass_read_only_user.id),
            )
    await hass.services.async_call(
        DOMAIN, "change_panel_start", {"device_id": target, "ops": [{"op": "add", "kind": "weather"}]},
        blocking=True, context=Context(user_id=hass_admin_user.id),
    )
    assert any(t["kind"] == "weather" for t in _panels(hass).start_tiles(PANEL_ID))


# Undo and the last 10 changes


async def test_undo_puts_back_the_start_before_a_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up_panel(hass, hass_client_no_auth)
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    added = await _change(hass, [{"op": "add", "entity": "switch.test_lamp"}])
    moved = await _change(hass, [{"op": "move", "tile": "test_lamp", "at": [7, 5]}])

    answer = await hass.services.async_call(
        DOMAIN, "undo_panel_start", {"device_id": _device(hass).id, "undo": moved["undo"], "by": "panel helper"},
        blocking=True, return_response=True,
    )
    assert answer["start"]["tiles"] == added["start"]["tiles"]
    assert answer["changed"] == f"change {moved['undo']} undone" and answer["start"]["changed"]["by"] == "panel helper"
    # The very first change's undo: the room's layout again
    answer = await hass.services.async_call(
        DOMAIN, "undo_panel_start", {"device_id": _device(hass).id, "undo": added["undo"]},
        blocking=True, return_response=True,
    )
    assert answer["start"] is None
    with pytest.raises(ServiceValidationError, match="no change nope to undo"):
        await hass.services.async_call(
            DOMAIN, "undo_panel_start", {"device_id": _device(hass).id, "undo": "nope"}, blocking=True,
        )


async def test_the_last_ten_changes_are_kept_on_re_pairing_and_dropped_with_the_device(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up_panel(hass, hass_client_no_auth)
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    undos = []
    for n in range(11):
        undos.append((await _change(hass, [{"op": "add", "kind": "weather"}] if n % 2 == 0 else
                                    [{"op": "remove", "tile": "weather"}]))["undo"])
    kept = [v["undo"] for v in _panels(hass).start_versions(PANEL_ID)]
    assert kept == list(reversed(undos[1:]))
    with pytest.raises(ServiceValidationError, match="only the last 10 are kept"):
        await hass.services.async_call(
            DOMAIN, "undo_panel_start", {"device_id": _device(hass).id, "undo": undos[0]}, blocking=True,
        )
    tiles = _panels(hass).start_tiles(PANEL_ID)

    # Pairing again keeps the Start, its changes and the room layout
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await _repair(hass, hass_client_no_auth)
    assert _panels(hass).start_tiles(PANEL_ID) == tiles
    assert [v["undo"] for v in _panels(hass).start_versions(PANEL_ID)] == kept
    assert _panels(hass).panels[PANEL_ID]["room_layout"] == ROOM

    # Removing its device drops them
    device = _device(hass)
    assert await async_remove_config_entry_device(hass, entry, device)
    dr.async_get(hass).async_remove_device(device.id)
    await hass.async_block_till_done()
    await _repair(hass, hass_client_no_auth)
    assert _panels(hass).start_tiles(PANEL_ID) is None and _panels(hass).start_versions(PANEL_ID) == []
    assert "room_layout" not in _panels(hass).panels[PANEL_ID]


async def _repair(hass, hass_client_no_auth) -> dict:
    return await _pair_panel(hass, await hass_client_no_auth(), area_id="kitchen")


# Entity renames


async def test_a_renamed_entity_is_rewritten_in_every_start_and_pushed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    registry = er.async_get(hass)
    lamp = registry.async_get_or_create("switch", "test", "lamp-1", suggested_object_id="test_lamp")
    assert lamp.entity_id == "switch.test_lamp"
    hass.states.async_set("light.porch", "off")
    kitchen = await _pair_panel(hass, client, area_id="kitchen")
    await _pair_panel(hass, client, OTHER_ID, area_id="bedroom")
    for device_id in (PANEL_ID, OTHER_ID):
        _panels(hass).panels[device_id]["room_layout"] = ROOM
    await _change(hass, [{"op": "add", "entity": "switch.test_lamp"},
                         {"op": "deals", "tile": "room_stack", "entity": "switch.test_lamp", "when": "on"}])
    before_rename = await _change(
        hass, [{"op": "make_stack", "name": "lamps", "entities": ["switch.test_lamp", "light.porch"]}],
        device_id=_device(hass, OTHER_ID).id,
    )
    ws, doc = await _subscribe(hass_ws_client, hass, kitchen)

    registry.async_update_entity("switch.test_lamp", new_entity_id="switch.desk_lamp")
    await hass.async_block_till_done()
    await _after_push(hass)
    pushed = (await ws.receive_json())["event"]
    tiles = {t["id"]: t for t in pushed["start"]["tiles"]}
    # The tile keeps its id; its entity and its deal follow the rename
    assert tiles["test_lamp"]["entity"] == "switch.desk_lamp"
    assert tiles["room_stack"]["deals"] == [{"entity": "switch.desk_lamp", "when": "on"}]
    assert pushed["start"]["version"] != doc["start"]["version"]
    other = {t["id"]: t for t in _panels(hass).start_tiles(OTHER_ID)}
    assert other["stack"]["entities"] == ["switch.desk_lamp", "light.porch"]
    assert before_rename["start"]["tiles"] != _panels(hass).start_tiles(OTHER_ID)
    # Kept changes follow too, so an undo puts back working ids
    for version in _panels(hass).panels[PANEL_ID]["start_versions"]:
        assert "switch.test_lamp" not in json.dumps(version["start"])

    # An entity removed from Home Assistant is kept: the panel marks its tile
    registry.async_remove("switch.desk_lamp")
    await hass.async_block_till_done()
    assert any(t.get("entity") == "switch.desk_lamp" for t in _panels(hass).start_tiles(PANEL_ID))


# get_panel


async def test_get_panel_has_start_and_its_changes_and_no_secret(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    body = await _set_up_panel(hass, hass_client_no_auth)
    got = await hass.services.async_call(DOMAIN, "get_panel", {}, blocking=True, return_response=True)
    assert got["panels"][0]["start"] is None and got["panels"][0]["start_versions"] == []
    _panels(hass).panels[PANEL_ID]["room_layout"] = ROOM
    first = await _change(hass, [{"op": "add", "entity": "switch.test_lamp"}])
    second = await _change(hass, [{"op": "remove", "tile": "test_lamp"}], by="claude")
    got = await hass.services.async_call(DOMAIN, "get_panel", {}, blocking=True, return_response=True)
    panel = got["panels"][0]
    assert panel["start"] == second["start"] == panel["document"]["start"]
    assert [v["undo"] for v in panel["start_versions"]] == [second["undo"], first["undo"]]
    assert panel["start_versions"][0]["changed"]["by"] == "claude"
    assert set(panel["start_versions"][0]) == {"undo", "changed"}
    record = _panels(hass).panels[PANEL_ID]
    text = json.dumps(got)
    assert record["key"] not in text and record["secret_hash"] not in text and body["secret"] not in text
