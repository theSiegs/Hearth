"""Glint Panels (custom_components/hearth/glint_panel/, docs/contracts/panel-config.md): pairing a wall tablet with a
room, its own Home Assistant user and token, its settings document over a WebSocket subscription, its entities and
services, the Parent PIN check, and the package's seam to the rest of Hearth."""

import ast
import asyncio
import json
from datetime import timedelta
from pathlib import Path

import pytest
from homeassistant.core import Context, HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import area_registry as ar
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator
from test_init import TV_ID, _pair, _set_up

from custom_components.hearth import (
    async_remove_config_entry_device,
    glint_panel,
    parent_pin,
)
from custom_components.hearth.const import DOMAIN, KIND_PANEL
from custom_components.hearth.glint_panel import document
from custom_components.hearth.glint_panel.const import (
    CONNECTED_GRACE,
    DEFAULT_COMMUTE,
    DEFAULT_WINDOWS,
    SCHEMA,
)

PANEL_ID = "panel-0123456789ab"
OTHER_ID = "panel-ba9876543210"
NONCE = "p" * 40
PIN = "4826"
PROXY_KEY = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
PACKAGE = Path(document.__file__).resolve().parent
HEARTH = PACKAGE.parent


@pytest.fixture(autouse=True)
def _an_owner(hass_owner_user):
    """Home Assistant always has its owner (made at onboarding): a panel's user is never the first."""
    yield


def _panels(hass: HomeAssistant) -> glint_panel.Panels:
    return glint_panel.Panels.get(hass, DOMAIN)


def _eid(hass: HomeAssistant, platform: str, key: str, device_id: str = PANEL_ID) -> str:
    entity_id = er.async_get(hass).async_get_entity_id(platform, DOMAIN, f"panel_{device_id}_{key}")
    assert entity_id, (platform, key)
    return entity_id


def _device(hass: HomeAssistant, device_id: str = PANEL_ID) -> dr.DeviceEntry:
    device = dr.async_get(hass).async_get_device_by_identifier(
        (DOMAIN, f"panel:{device_id}"), hass.config_entries.async_entries(DOMAIN)[0].entry_id
    )
    assert device is not None
    return device


async def _start(client, device_id: str = PANEL_ID, seed=None, **extra):
    body = {"device_id": device_id, "kind": "panel", "name": "glint panel", "model": "Example tablet",
            "version": "1.0.0", "nonce": NONCE, **extra}
    if seed is not None:
        body["seed"] = seed
    return await client.post("/api/hearth/pair", json=body)


async def _pair_panel(
    hass: HomeAssistant, client, device_id: str = PANEL_ID, area_id: str | None = None, seed=None
) -> dict:
    """Pairs a panel as an administrator would on Hearth's page (with a room, or none): the approved answer."""
    # A second pairing from the test's one address would wait PAIRING_INTERVAL_PER_ADDRESS
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    response = await _start(client, device_id, seed)
    assert response.status == 200, await response.text()
    started = await response.json()
    await hass.async_block_till_done()
    from custom_components.hearth.panel import async_answer_pairing

    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    assert await async_answer_pairing(hass, hub, started["pairing_id"], "approve", None, area_id)
    await hass.async_block_till_done()
    approved = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    body = await approved.json()
    assert body["status"] == "approved"
    return body


async def _household(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator):
    entry = await _set_up(hass)
    ar.async_get(hass).async_create("Kitchen")
    ar.async_get(hass).async_create("Bedroom")
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    return entry, await hass_client_no_auth()


async def _subscribe(hass_ws_client, hass, body: dict, device_id: str = PANEL_ID):
    ws = await hass_ws_client(hass, access_token=body["ha_token"])
    await ws.send_json({"id": 1, "type": "hearth/panel/subscribe", "device_id": device_id, "secret": body["secret"]})
    result = await ws.receive_json()
    assert result["success"], result
    first = await ws.receive_json()
    assert first["type"] == "event" and first["id"] == 1
    return ws, first["event"]


async def _after_push(hass: HomeAssistant) -> None:
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    await hass.async_block_till_done()


# Pairing


async def test_a_panel_pairs_with_a_room_and_gets_a_user_of_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    hub = entry.runtime_data
    # A household without a panel has no switch or select platform (they load with the first panel)
    assert "switch" not in hass.config.components and "select" not in hass.config.components
    body = await _pair_panel(hass, client, area_id="kitchen")
    assert hass.states.get(_eid(hass, "switch", "house_panel")).state == "on"

    assert body["device_id"] == PANEL_ID and body["secret"] and body["ha_token"]
    assert body["person"] is None and body["role"] is None and body["push"] is None
    assert set(body["urls"]) == {"internal", "external"}
    device = _device(hass)
    assert device.name == "Kitchen panel" and device.area_id == "kitchen"
    assert device.model == "Example tablet" and device.sw_version == "1.0.0"
    assert device.configuration_url == f"homeassistant://hearth#panel-{PANEL_ID}"
    assert entry.entry_id in device.config_entries

    user = await hass.auth.async_get_user(_panels(hass).panels[PANEL_ID]["user_id"])
    assert user is not None and user.name == "Kitchen panel"
    assert not user.is_admin and user.local_only and not user.system_generated
    assert not any(s.attributes.get("user_id") == user.id for s in hass.states.async_all("person"))
    # Kept apart from the TVs and phones: never in the entry, and the entry didn't reload
    assert PANEL_ID not in entry.data.get("devices", {})
    assert hass.config_entries.async_entries(DOMAIN)[0].runtime_data is hub
    # The token signs in as the panel's user
    refresh = hass.auth.async_validate_access_token(body["ha_token"])
    assert refresh is not None and refresh.user.id == user.id


async def test_a_panel_pairs_without_a_room(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client)
    device = _device(hass)
    assert device.name == "Panel" and device.area_id is None


async def test_the_confirm_form_asks_for_a_room_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    started = await (await _start(client)).json()
    await hass.async_block_till_done()
    flows = hass.config_entries.flow.async_progress_by_handler(DOMAIN)
    result = await hass.config_entries.flow.async_configure(flows[0]["flow_id"])
    assert [str(k) for k in result["data_schema"].schema] == ["area_id"]
    result = await hass.config_entries.flow.async_configure(flows[0]["flow_id"], {"area_id": "bedroom"})
    assert result["type"] is FlowResultType.ABORT and result["reason"] == "paired"
    approved = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    assert (await approved.json())["ha_token"]
    assert _device(hass).area_id == "bedroom"


async def test_the_token_is_in_the_first_approved_poll_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    response = await _start(client)
    started = await response.json()
    await hass.async_block_till_done()
    pending = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    assert "ha_token" not in await pending.json()
    from custom_components.hearth.panel import async_answer_pairing

    assert await async_answer_pairing(hass, entry.runtime_data, started["pairing_id"], "approve", None, "kitchen")
    # The panel contract's neutral header works as well as Hearth's own
    first = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Panel-Nonce": NONCE})
    assert (await first.json())["ha_token"]
    again = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    assert again.status == 404
    assert "ha_token" not in await again.text()
    # Hearth's own 404s are JSON, so a panel tells them from Home Assistant's "no such route"
    assert (await again.json())["error"]


async def test_a_pair_body_needs_its_device_id_and_a_small_seed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    no_id = await client.post("/api/hearth/pair", json={"kind": "panel", "name": "glint panel", "nonce": NONCE})
    assert no_id.status == 400
    assert (await _start(client, seed={"look": {"motion": "x" * 20000}})).status == 400
    assert (await _start(client, seed=["not", "a", "document"])).status == 400


async def test_one_id_is_one_device(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair(hass, client)
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    # A panel never pairs over a TV, nor a TV over a panel
    assert (await _start(client, device_id=TV_ID)).status == 400
    await _pair_panel(hass, client)
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    response = await client.post(
        "/api/hearth/pair", json={"device_id": PANEL_ID, "kind": "tv", "name": "TV", "nonce": NONCE}
    )
    assert response.status == 400


async def test_a_tv_s_ticket_never_pairs_a_panel(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    secret = await _pair(hass, client)
    response = await client.post(
        f"/api/hearth/device/{TV_ID}/ticket", json={"kind": "panel"}, headers={"X-Hearth-Secret": secret}
    )
    assert response.status == 400


async def test_removing_the_device_deletes_its_user(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    user_id = _panels(hass).panels[PANEL_ID]["user_id"]
    device = _device(hass)
    assert await async_remove_config_entry_device(hass, entry, device)
    dr.async_get(hass).async_remove_device(device.id)
    await hass.async_block_till_done()
    assert await hass.auth.async_get_user(user_id) is None
    assert not _panels(hass).has(PANEL_ID)
    assert er.async_get(hass).async_get_entity_id("switch", DOMAIN, f"panel_{PANEL_ID}_house_panel") is None


async def test_unpaired_on_the_panel_removes_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    user_id = _panels(hass).panels[PANEL_ID]["user_id"]
    ws = await hass_ws_client(hass, access_token=body["ha_token"])
    await ws.send_json(
        {"id": 1, "type": "hearth/panel/report", "device_id": PANEL_ID, "secret": body["secret"], "unpaired": True}
    )
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()
    assert await hass.auth.async_get_user(user_id) is None
    assert not dr.async_entries_for_config_entry(dr.async_get(hass), _entry.entry_id) or all(
        (DOMAIN, f"panel:{PANEL_ID}") not in d.identifiers for d in dr.async_entries_for_config_entry(dr.async_get(hass), _entry.entry_id)
    )


async def test_pairing_again_replaces_the_user_and_keeps_the_settings(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    first = await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    old_user = panels.panels[PANEL_ID]["user_id"]
    panels.set_values(PANEL_ID, {"motion": "calm"})
    key = panels.panels[PANEL_ID]["key"]

    second = await _pair_panel(hass, client)
    assert await hass.auth.async_get_user(old_user) is None
    assert hass.auth.async_validate_access_token(first["ha_token"]) is None
    new_user = panels.panels[PANEL_ID]["user_id"]
    assert new_user != old_user and await hass.auth.async_get_user(new_user) is not None
    assert not panels.authorized(PANEL_ID, first["secret"]) and panels.authorized(PANEL_ID, second["secret"])
    # Its settings, room and proxy key stay
    assert panels.value(PANEL_ID, "motion") == "calm" and panels.panels[PANEL_ID]["key"] == key
    assert _device(hass).area_id == "kitchen"


async def test_the_seed_is_taken_once_known_fields_and_entities_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    hass.states.async_set("calendar.family", "off")
    hass.states.async_set("camera.album", "idle")
    seed = {
        "look": {"motion": "lively"},
        "photos": {"every_s": 60, "caption": False, "camera": "camera.album"},
        "calendars": {"family": ["calendar.family", "calendar.gone"]},
        "wake": {"presence": "binary_sensor.gone"},
        "messages": {"shared_room_says_who": "yes"},
        "made_up": {"x": 1},
        "routines": {"windows": [dict(w) for w in DEFAULT_WINDOWS]},
        "proxy": {"on": True, "key": PROXY_KEY, "name": "bedroom-tablet"},
        "news": {"seen": "input_text.panel_seen"},
    }
    hass.states.async_set("input_text.panel_seen", "")
    await _pair_panel(hass, client, area_id="kitchen", seed=seed)
    panels = _panels(hass)
    # Defaults (every 60 s, the default windows) and fields that aren't right are dropped
    assert panels.panels[PANEL_ID]["values"] == {
        "motion": "lively",
        "photo_caption": False,
        "bluetooth_proxy": True,
        "proxy_name": "bedroom-tablet",
        "news_seen": "input_text.panel_seen",
    }
    assert panels.house == {"family_calendars": ["calendar.family"], "photos": "camera.album"}
    doc = panels.document(PANEL_ID)
    assert doc["proxy"]["key"] == PROXY_KEY and doc["wake"]["presence"] is None
    # The proxy keeps the ESPHome name it had, not one made from the device's name
    assert doc["proxy"]["name"] == "bedroom-tablet"
    assert doc["news"] == {"seen": "input_text.panel_seen"}

    # Once: pairing again with another seed changes nothing
    await _pair_panel(hass, client, seed={"look": {"motion": "still"}})
    assert panels.value(PANEL_ID, "motion") == "lively"


# The document


async def test_a_panel_with_only_a_room_has_a_whole_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    doc = _panels(hass).document(PANEL_ID)
    assert doc["schema"] == SCHEMA == "glint.panel-config/1"
    assert doc["served_by"] == "hearth"
    assert set(doc) == {
        "schema", "served_by", "version", "panel", "look", "photos", "calendars", "wake", "night", "doors",
        "messages", "routines", "bed", "proxy", "voice", "news",
    }
    assert "parent_pins" not in doc and "parent_pins_version" not in doc
    assert doc["panel"] == {
        "device_id": PANEL_ID, "name": "Kitchen panel", "area_id": "kitchen", "extra_areas": [], "people": [],
        "house_panel": True, "panel_areas": ["kitchen"],
    }
    assert doc["look"] == {"motion": "easy"}
    assert doc["photos"] == {"camera": None, "every_s": 60, "caption": True, "on_this_day": True}
    assert doc["calendars"] == {"family": [], "person": {}, "titles": True}
    assert doc["routines"] == {"entities": [], "windows": list(DEFAULT_WINDOWS), "commute": DEFAULT_COMMUTE}
    assert doc["bed"] is None
    assert doc["proxy"]["on"] is False and doc["proxy"]["name"] == "kitchen-panel"
    assert document.proxy_key(doc["proxy"]["key"])
    assert doc["voice"] == {"heard": None, "reply": None, "reply_attribute": None, "show": None}
    assert doc["news"] == {"seen": None}


async def test_set_beats_derived_and_the_version_follows_the_content(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    hass.states.async_set("camera.album", "idle")
    hass.states.async_set("camera.kitchen_album", "idle")
    await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    start = panels.document(PANEL_ID)
    assert panels.document(PANEL_ID)["version"] == start["version"]

    panels.set_house({"photos": "camera.album"})
    house = panels.document(PANEL_ID)
    assert house["photos"]["camera"] == "camera.album" and house["version"] != start["version"]
    panels.set_values(PANEL_ID, {"photos": "camera.kitchen_album"})
    assert panels.document(PANEL_ID)["photos"]["camera"] == "camera.kitchen_album"
    # Back to derived: back to the same content, the same version
    panels.set_values(PANEL_ID, {"photos": None})
    panels.set_house({"photos": None})
    assert panels.document(PANEL_ID)["version"] == start["version"]


async def test_secrets_are_never_in_answers_states_or_attributes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    record = _panels(hass).panels[PANEL_ID]
    secrets = (record["key"], record["secret_hash"], body["secret"], body["ha_token"])

    got = await hass.services.async_call(DOMAIN, "get_panel", {}, blocking=True, return_response=True)
    set_answer = await hass.services.async_call(
        DOMAIN, "set_panel", {"device_id": _device(hass).id, "motion": "calm"}, blocking=True, return_response=True
    )
    for answer in (got, set_answer):
        text = json.dumps(answer)
        assert not any(s in text for s in secrets)
    assert "key" not in got["panels"][0]["document"]["proxy"] and "key" not in set_answer["proxy"]
    states = [s.as_dict() for s in hass.states.async_all() if "panel" in s.entity_id]
    assert len(states) == 14
    assert not any(secret in json.dumps(states, default=str) for secret in secrets)


# Subscribe and report


async def test_a_wrong_secret_or_another_user_is_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_read_only_access_token
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    ws = await hass_ws_client(hass, access_token=body["ha_token"])
    await ws.send_json({"id": 1, "type": "hearth/panel/subscribe", "device_id": PANEL_ID, "secret": "not-the-secret"})
    answer = await ws.receive_json()
    assert not answer["success"] and answer["error"]["code"] == "unauthorized"
    # The panel's secret on another (not administrator) user's connection
    other = await hass_ws_client(hass, access_token=hass_read_only_access_token)
    await other.send_json({"id": 1, "type": "hearth/panel/subscribe", "device_id": PANEL_ID, "secret": body["secret"]})
    assert (await other.receive_json())["error"]["code"] == "unauthorized"


async def test_the_first_message_is_the_whole_document_and_one_call_is_one_push(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    ws, doc = await _subscribe(hass_ws_client, hass, body)
    assert doc == _panels(hass).document(PANEL_ID)

    await hass.services.async_call(
        DOMAIN, "set_panel",
        {"device_id": _device(hass).id, "motion": "calm", "photo_caption": False, "on_this_day": False},
        blocking=True,
    )
    await _after_push(hass)
    pushed = await ws.receive_json()
    assert pushed["type"] == "event" and pushed["id"] == 1
    assert pushed["event"]["look"]["motion"] == "calm"
    assert pushed["event"]["photos"]["caption"] is False and pushed["event"]["photos"]["on_this_day"] is False
    # Nothing else came: the next message is the answer to this report
    await ws.send_json(
        {"id": 2, "type": "hearth/panel/report", "device_id": PANEL_ID, "secret": body["secret"], "view": "dark clock",
         "on_tablet": ["allow turning the screen off"], "version": pushed["event"]["version"], "sw_version": "1.0.1"}
    )
    answer = await ws.receive_json()
    assert answer["id"] == 2 and answer["success"]
    await hass.async_block_till_done()
    assert hass.states.get(_eid(hass, "sensor", "view")).state == "dark_clock"
    assert hass.states.get(_eid(hass, "sensor", "on_the_tablet")).state == "allow turning the screen off"
    assert _device(hass).sw_version == "1.0.1"


async def test_a_room_change_pushes_and_renames_the_device(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    ws, _doc = await _subscribe(hass_ws_client, hass, body)
    devices = dr.async_get(hass)
    devices.async_update_device(_device(hass).id, area_id="bedroom")
    await hass.async_block_till_done()
    await _after_push(hass)
    pushed = (await ws.receive_json())["event"]
    assert pushed["panel"]["area_id"] == "bedroom" and pushed["panel"]["name"] == "Bedroom panel"
    assert pushed["panel"]["panel_areas"] == ["bedroom"]
    assert _device(hass).name == "Bedroom panel"

    # Renamed by the owner: their name stays
    devices.async_update_device(_device(hass).id, name_by_user="Hall tablet")
    await hass.async_block_till_done()
    devices.async_update_device(_device(hass).id, area_id="kitchen")
    await hass.async_block_till_done()
    await _after_push(hass)
    assert _panels(hass).document(PANEL_ID)["panel"]["name"] == "Hall tablet"
    assert _device(hass).name == "Bedroom panel"


async def test_connected_follows_the_subscription(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    connected = _eid(hass, "binary_sensor", "connected")
    assert hass.states.get(connected).state == "off"
    ws, _doc = await _subscribe(hass_ws_client, hass, body)
    await hass.async_block_till_done()
    assert hass.states.get(connected).state == "on"
    await ws.close()
    await hass.async_block_till_done()
    assert hass.states.get(connected).state == "on"
    freezer.tick(CONNECTED_GRACE + timedelta(seconds=5))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hass.states.get(connected).state == "off"


# Entities


async def test_the_entities_show_the_store_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    caption = _eid(hass, "switch", "photo_caption")
    motion = _eid(hass, "select", "motion")
    every = _eid(hass, "select", "photos_every")
    assert hass.states.get(caption).state == "on" and hass.states.get(motion).state == "easy"
    await hass.services.async_call("switch", "turn_off", {"entity_id": caption}, blocking=True)
    await hass.services.async_call("select", "select_option", {"entity_id": motion, "option": "still"}, blocking=True)
    await hass.services.async_call("select", "select_option", {"entity_id": every, "option": "300"}, blocking=True)
    assert _panels(hass).value(PANEL_ID, "photos_every") == 300

    # A restart: the store is read again, nothing comes from the state machine
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop(f"{DOMAIN}_glint_panel")
    hass.states.async_remove(caption)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    assert hass.states.get(caption).state == "off"
    assert hass.states.get(motion).state == "still"
    assert hass.states.get(every).state == "300"


async def test_the_house_panel_is_one_at_most(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    await _pair_panel(hass, client, device_id=OTHER_ID, area_id="bedroom")
    first, second = _eid(hass, "switch", "house_panel"), _eid(hass, "switch", "house_panel", OTHER_ID)
    # Derived: the first shared-room panel
    assert (hass.states.get(first).state, hass.states.get(second).state) == ("on", "off")
    await hass.services.async_call("switch", "turn_on", {"entity_id": second}, blocking=True)
    assert (hass.states.get(first).state, hass.states.get(second).state) == ("off", "on")
    await hass.services.async_call("switch", "turn_off", {"entity_id": second}, blocking=True)
    assert (hass.states.get(first).state, hass.states.get(second).state) == ("off", "off")
    # A person's room isn't the derived house panel
    await hass.services.async_call(DOMAIN, "set_panel", {"device_id": _device(hass).id, "house_panel": None,
                                                         "people": ["person.alex"]}, blocking=True)
    assert (hass.states.get(first).state, hass.states.get(second).state) == ("off", "on")
    assert _panels(hass).document(OTHER_ID)["panel"]["panel_areas"] == ["bedroom", "kitchen"]


async def test_flipping_a_switch_pushes_the_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    ws, doc = await _subscribe(hass_ws_client, hass, body)
    await hass.services.async_call(
        "switch", "turn_on", {"entity_id": _eid(hass, "switch", "bluetooth_proxy")}, blocking=True
    )
    await _after_push(hass)
    pushed = (await ws.receive_json())["event"]
    assert pushed["proxy"]["on"] is True and pushed["version"] != doc["version"]


# Services


async def test_set_panel_refuses_an_unknown_entity_by_name_and_resets_with_empty(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    target = _device(hass).id
    with pytest.raises(ServiceValidationError, match="script.nowhere"):
        await hass.services.async_call(
            DOMAIN, "set_panel", {"device_id": target, "routines": ["script.nowhere"]}, blocking=True
        )
    with pytest.raises(ServiceValidationError, match="garage"):
        await hass.services.async_call(DOMAIN, "set_panel", {"device_id": target, "extra_areas": ["garage"]}, blocking=True)
    with pytest.raises(ServiceValidationError, match="Not a panel"):
        await hass.services.async_call(DOMAIN, "set_panel", {"device_id": "nope", "motion": "calm"}, blocking=True)
    with pytest.raises(ServiceValidationError, match="motion"):
        await hass.services.async_call(DOMAIN, "set_panel", {"device_id": target, "motion": "fast"}, blocking=True)

    hass.states.async_set("script.good_morning", "off")
    answer = await hass.services.async_call(
        DOMAIN, "set_panel",
        {"device_id": target, "routines": ["script.good_morning"], "extra_areas": ["bedroom"],
         "bed_left": {"scripts": ["script.good_morning"]}},
        blocking=True, return_response=True,
    )
    assert answer["routines"]["entities"] == ["script.good_morning"] and answer["panel"]["extra_areas"] == ["bedroom"]
    assert answer["bed"] == {"left": {"connected": None, "scripts": ["script.good_morning"], "positions": []},
                             "right": None}
    got = await hass.services.async_call(DOMAIN, "get_panel", {"device_id": target}, blocking=True, return_response=True)
    assert got["panels"][0]["settings"]["routines"] == {"value": ["script.good_morning"], "source": "set"}
    assert got["panels"][0]["settings"]["motion"] == {"value": "easy", "source": "derived"}

    await hass.services.async_call(
        DOMAIN, "set_panel", {"device_id": target, "routines": [], "extra_areas": None, "bed_left": None}, blocking=True
    )
    got = await hass.services.async_call(DOMAIN, "get_panel", {}, blocking=True, return_response=True)
    settings = got["panels"][0]["settings"]
    assert settings["routines"]["source"] == settings["extra_areas"]["source"] == "derived"
    assert got["panels"][0]["document"]["bed"] is None


async def test_set_panel_defaults(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    hass.states.async_set("calendar.family", "off")
    hass.states.async_set("calendar.alex_work", "off")
    hass.states.async_set("input_boolean.night_mode", "off")
    windows = [{"word": "good morning", "from": "06:30", "until": "09:00", "days": ["sat", "sun"]}]
    answer = await hass.services.async_call(
        DOMAIN, "set_panel_defaults",
        {"family_calendars": ["calendar.family"], "person_calendars": {"person.alex": ["calendar.alex_work"]},
         "night": "input_boolean.night_mode", "routine_windows": windows,
         "commute_window": {"from": "07:15", "until": "08:30", "days": ["mon", "tue"]}},
        blocking=True, return_response=True,
    )
    assert answer["defaults"]["night"] == {"value": "input_boolean.night_mode", "source": "set"}
    assert answer["defaults"]["doorbell_camera"] == {"value": None, "source": "derived"}
    doc = _panels(hass).document(PANEL_ID)
    assert doc["calendars"]["person"] == {"person.alex": ["calendar.alex_work"]}
    assert doc["routines"]["windows"] == [{**windows[0], "after_bedtimes": False}]
    assert doc["routines"]["commute"]["from"] == "07:15"
    with pytest.raises(ServiceValidationError, match="routine window"):
        await hass.services.async_call(
            DOMAIN, "set_panel_defaults", {"routine_windows": [{"word": "x", "from": "25:00"}]}, blocking=True
        )
    await hass.services.async_call(DOMAIN, "set_panel_defaults", {"routine_windows": []}, blocking=True)
    assert _panels(hass).document(PANEL_ID)["routines"]["windows"] == list(DEFAULT_WINDOWS)


async def test_only_adults_call_the_panel_services(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user, hass_admin_user
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    target = _device(hass).id
    for service, data in (
        ("set_panel", {"device_id": target, "motion": "calm"}),
        ("set_panel_defaults", {"night": None}),
        ("get_panel", {}),
    ):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, service, data, blocking=True, context=Context(user_id=hass_read_only_user.id),
                return_response=service == "get_panel",
            )
    # The panel's own user isn't an adult either
    panel_user = _panels(hass).panels[PANEL_ID]["user_id"]
    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "get_panel", {}, blocking=True, context=Context(user_id=panel_user), return_response=True
        )
    await hass.services.async_call(
        DOMAIN, "set_panel", {"device_id": target, "motion": "calm"}, blocking=True,
        context=Context(user_id=hass_admin_user.id),
    )
    assert _panels(hass).value(PANEL_ID, "motion") == "calm"


# verify_pin


async def test_verify_pin_names_the_adult_and_locks_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    ws = await hass_ws_client(hass, access_token=body["ha_token"])
    msg_id = 0

    async def verify(pin: str, secret: str = body["secret"]) -> dict:
        nonlocal msg_id
        msg_id += 1
        await ws.send_json(
            {"id": msg_id, "type": "hearth/panel/verify_pin", "device_id": PANEL_ID, "secret": secret, "pin": pin}
        )
        return await ws.receive_json()

    assert (await verify(PIN))["error"]["code"] == "no_pin"
    hass.config_entries.async_update_entry(
        entry,
        options={**entry.options, "roles": {"person.alex": "adult"},
                 parent_pin.CONF_PARENT_PINS: {"person.alex": parent_pin.make(PIN)}},
    )
    await hass.async_block_till_done()
    assert (await verify(PIN, "not-the-secret"))["error"]["code"] == "unauthorized"
    right = await verify(PIN)
    assert right["success"] and right["result"] == {"person": "person.alex"}
    for _ in range(parent_pin.FREE_TRIES - 1):
        assert (await verify("0000"))["error"]["code"] == "wrong_pin"
    started = await verify("0000")
    assert started["error"]["code"] == "wrong_pin" and int(started["error"]["translation_placeholders"]["retry_in"]) > 0
    locked = await verify(PIN)
    assert locked["error"]["code"] == "locked_out"
    assert int(locked["error"]["translation_placeholders"]["retry_in"]) > 0
    # Its own lockout: a TV's tries aren't the panel's
    from custom_components.hearth.hub import pin_lockout

    assert pin_lockout(hass, PANEL_ID).failures == 0


# Nothing a panel does reloads the entry or ends a TV's wait


async def test_panel_changes_never_reload_the_entry_or_end_a_tv_s_wait(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    await _pair(hass, client)
    hub = entry.runtime_data
    version = hub.household.document_for(TV_ID)["version"]
    waiting = asyncio.get_running_loop().create_task(hub.waits.wait(TV_ID, version, 60))
    await asyncio.sleep(0)

    body = await _pair_panel(hass, client, area_id="kitchen")
    ws, _doc = await _subscribe(hass_ws_client, hass, body)
    target = _device(hass).id
    await hass.services.async_call(DOMAIN, "set_panel", {"device_id": target, "motion": "lively"}, blocking=True)
    await hass.services.async_call(DOMAIN, "set_panel_defaults", {"night": None}, blocking=True)
    await hass.services.async_call("switch", "turn_off", {"entity_id": _eid(hass, "switch", "dark_at_night")}, blocking=True)
    dr.async_get(hass).async_update_device(target, area_id="bedroom")
    await hass.async_block_till_done()
    await _after_push(hass)

    assert hass.config_entries.async_entries(DOMAIN)[0].runtime_data is hub
    assert not waiting.done()
    waiting.cancel()
    await ws.close()


# The package's seam


def _imports(path: Path) -> list[tuple[int, str]]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found += [(0, alias.name) for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            found.append((node.level, node.module or ""))
            if node.module is None:
                # from . import x
                found += [(node.level, alias.name) for alias in node.names]
    return found


def test_the_package_imports_nothing_of_hearth_s() -> None:
    for path in PACKAGE.glob("*.py"):
        for level, module in _imports(path):
            # Its own modules (one dot), Home Assistant and the standard library; never "..": the rest of Hearth
            assert level in (0, 1), (path.name, level, module)
            if level == 0:
                assert not module.startswith("custom_components"), (path.name, module)


def test_only_setup_and_the_platform_files_import_the_package() -> None:
    importers = set()
    for path in HEARTH.glob("*.py"):
        for level, module in _imports(path):
            if (level == 1 and module.split(".")[0] == "glint_panel") or "hearth.glint_panel" in module:
                importers.add(path.name)
    assert importers == {"__init__.py", "switch.py", "select.py", "sensor.py", "binary_sensor.py"}


def test_the_domain_is_in_one_constant() -> None:
    """No wire name in the package spells the domain: each is built from the host's (Hearth's DOMAIN)."""
    for path in PACKAGE.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        docstrings = {
            id(node.body[0].value)
            for node in ast.walk(tree)
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef))
            and node.body and isinstance(node.body[0], ast.Expr) and isinstance(node.body[0].value, ast.Constant)
        }
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
                assert "hearth" not in node.value.casefold(), (path.name, node.value)
    assert glint_panel.KIND == KIND_PANEL
