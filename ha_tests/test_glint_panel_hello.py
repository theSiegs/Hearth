"""Setting a Glint Panel up over its socket (glint_panel/hello.py, docs/contracts/panel-config.md, hello): the matching
rules and the gate, the hello subscription's answers (pending, approved, denied, sent again until the panel subscribes),
the approval in HA (the discovered card and Hearth's page), the proxy MAC (1.4) and the device before its entities."""

from datetime import timedelta

import pytest
from homeassistant.auth.const import GROUP_ID_USER
from homeassistant.auth.models import TOKEN_TYPE_LONG_LIVED_ACCESS_TOKEN
from homeassistant.core import Context, HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_capture_events, async_fire_time_changed
from test_glint_panel import (  # noqa: F401  (_displays: the shared panels' login, autouse)
    DISPLAYS,
    OTHER_ID,
    PANEL_ID,
    TOKENS,
    _adult,
    _device,
    _displays,
    _household,
    _pair_panel,
    _panels,
)
from test_init import TV_ID, _pair

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glint_panel import hello, manager
from custom_components.hearth.glint_panel.const import CONNECTED_GRACE, HELLO_DENIED_FOR, HELLO_UNSEEN

NEW_ID = "panel-00000000aaaa1111"
TABLET_ID = "panel-00000000bbbb2222"
MAC = "02:00:5e:10:00:01"
OTHER_MAC = "02:00:5e:10:00:02"


# The rules, on their own


def _rules(device_id, area_id, replaces=None, panels=None, areas=None, online=()):
    panels = panels if panels is not None else {}
    areas = areas or {}
    return hello.match(device_id, area_id, replaces, panels, areas.get, lambda d: d in online)


def test_rule_1_a_panel_s_id_or_one_of_its_tablet_ids_is_that_panel() -> None:
    panels = {"panel-a": {"tablet_ids": ["tab-1"]}}
    assert _rules("panel-a", None, panels=panels) == hello.Match(hello.KNOWN, "panel-a")
    assert _rules("tab-1", "kitchen", panels=panels) == hello.Match(hello.KNOWN, "panel-a")
    # First rule that fits: a known id with an area and replaces false is still that panel
    assert _rules("panel-a", "bedroom", False, panels=panels) == hello.Match(hello.KNOWN, "panel-a")


def test_rule_2_takes_the_place_of_the_one_panel_in_the_area_that_isn_t_connected() -> None:
    panels = {"panel-a": {}, "panel-b": {}, "panel-c": {}}
    areas = {"panel-a": "kitchen", "panel-b": "kitchen", "panel-c": "bedroom"}
    # One of the kitchen's two panels is connected: the other one's place
    assert _rules("new", "kitchen", panels=panels, areas=areas, online={"panel-a"}) == hello.Match(
        hello.TAKES_PLACE, "panel-b"
    )
    assert _rules("new", "kitchen", True, panels=panels, areas=areas, online={"panel-b"}).device_id == "panel-a"
    # Two offline: not one, so a new panel; replaces false: a new panel; every one connected: a new panel
    assert _rules("new", "kitchen", panels=panels, areas=areas).rule == hello.NEW
    assert _rules("new", "bedroom", False, panels=panels, areas=areas).rule == hello.NEW
    assert _rules("new", "kitchen", panels=panels, areas=areas, online={"panel-a", "panel-b"}).rule == hello.NEW


def test_rule_3_an_area_alone_is_a_new_panel_and_rule_4_waits() -> None:
    assert _rules("new", "kitchen") == hello.Match(hello.NEW)
    # No area, or one HA doesn't have (the caller resolves it to None)
    assert _rules("new", None) == hello.Match(hello.WAITS)
    assert _rules("new", None, False, panels={"panel-a": {}}) == hello.Match(hello.WAITS)


@pytest.mark.parametrize(
    ("rule", "at_once"),
    [(hello.KNOWN, True), (hello.TAKES_PLACE, True), (hello.NEW, True), (hello.WAITS, False)],
)
def test_rules_1_to_3_are_approved_at_once(rule, at_once) -> None:
    found = hello.Match(rule, "panel-a" if rule in (hello.KNOWN, hello.TAKES_PLACE) else None)
    assert hello.at_once(found) is at_once


# The proxy MAC, on its own


def test_a_mac_is_cleaned_or_refused() -> None:
    for given in ("02:00:5E:10:00:01", "02-00-5e-10-00-01", "02005e100001", " 02:00:5e:10:00:01 "):
        assert hello.clean_mac(given) == MAC
    # Multicast, mixed separators, too short, not a string
    for bad in ("01:00:5e:10:00:01", "02:00-5e:10:00:01", "02:00:5e:10:00", "nope", None, 2):
        assert hello.clean_mac(bad) is None


def test_a_new_panel_s_mac_comes_from_its_id() -> None:
    mac = hello.mac_from_id(NEW_ID)
    assert mac == hello.mac_from_id(NEW_ID) != hello.mac_from_id(TABLET_ID)
    assert hello.clean_mac(mac) == mac
    # Locally administered and unicast: the first byte's low two bits are 10
    assert int(mac[:2], 16) & 0x03 == 0x02


def test_a_live_proxy_s_mac_is_adopted_by_its_name_title_or_host() -> None:
    entries = [
        ("02:00:5e:10:00:01", ["Kitchen panel", None, "192.0.2.10"]),
        ("02005e100002", ["Something", "bedroom-panel", None]),
        ("not a mac", ["den-panel", None, None]),
    ]
    assert hello.adopted_mac("kitchen-panel", entries) == MAC
    assert hello.adopted_mac("bedroom-panel", entries) == OTHER_MAC
    assert hello.adopted_mac("hall-panel", [("02:00:5e:10:00:03", [None, None, "hall-panel.local"])]) == "02:00:5e:10:00:03"
    assert hello.adopted_mac("den-panel", entries) is None
    assert hello.adopted_mac("", entries) is None
    # Two entries of that name with different MACs: never a guess
    assert hello.adopted_mac("kitchen-panel", [*entries, ("02:00:5e:10:00:09", ["kitchen-panel", None, None])]) is None


# Over the socket


async def _token(hass: HomeAssistant, user, name: str) -> str:
    refresh = await hass.auth.async_create_refresh_token(
        user, client_name=name, token_type=TOKEN_TYPE_LONG_LIVED_ACCESS_TOKEN,
        access_token_expiration=timedelta(days=1),
    )
    return hass.auth.async_create_access_token(refresh)


async def _kid(hass: HomeAssistant):
    """Sam: a kid with a Home Assistant login of their own."""
    sam = await hass.auth.async_create_user("Sam", group_ids=[GROUP_ID_USER])
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam", "user_id": sam.id})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    roles = {**entry.options.get("roles", {}), "person.sam": "kid"}
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": roles})
    await hass.async_block_till_done()
    return await _token(hass, sam, "Sam's phone")


class _Socket:
    """One WebSocket connection, on a login."""

    def __init__(self, ws) -> None:
        self.ws = ws
        self.next_id = 1

    async def hello(self, device_id: str, **fields) -> tuple[dict, dict | None, int]:
        """Says hello: (the result, the first event or None, the message id)."""
        msg_id = self.next_id
        self.next_id += 1
        await self.ws.send_json(
            {"id": msg_id, "type": "hearth/panel/hello", "device_id": device_id, "name": "glint panel",
             "model": "Example tablet", "version": "2.0.0", **fields}
        )
        result = await self.ws.receive_json()
        if not result["success"]:
            return result, None, msg_id
        event = await self.ws.receive_json()
        assert event["type"] == "event" and event["id"] == msg_id
        return result, event["event"], msg_id

    async def subscribe(self, device_id: str, secret: str) -> dict:
        msg_id = self.next_id
        self.next_id += 1
        await self.ws.send_json({"id": msg_id, "type": "hearth/panel/subscribe", "device_id": device_id, "secret": secret})
        return await self.ws.receive_json()

    async def event(self) -> dict:
        got = await self.ws.receive_json()
        assert got["type"] == "event", got
        return got["event"]


async def _socket(hass_ws_client, hass, token: str | None = None) -> _Socket:
    return _Socket(await hass_ws_client(hass, access_token=token) if token else await hass_ws_client(hass))


async def _restart(hass: HomeAssistant, entry) -> None:
    """Home Assistant restarts: the store is saved, the run's panels go, and Hearth loads again."""
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop(f"{DOMAIN}_glint_panel")
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()


async def _offline(hass: HomeAssistant, freezer) -> None:
    freezer.tick(CONNECTED_GRACE + timedelta(seconds=5))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


async def test_an_administrator_s_hello_with_a_room_is_a_new_panel_at_once(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    _entry, _client = await _household(hass, hass_client_no_auth)
    admin = await _socket(hass_ws_client, hass)
    result, event, _ = await admin.hello(NEW_ID, area="Kitchen")
    assert result["success"] and result["result"] is None
    assert event["status"] == "approved" and event["device_id"] == NEW_ID and event["secret"]
    assert event["name"] == "Kitchen panel" and event["area_id"] == "kitchen"
    assert set(event["urls"]) == {"internal", "external"}
    await hass.async_block_till_done()

    # H4: the device is named for its room and in it, so its entities are <domain>.<area>_panel_<key>
    device = _device(hass, NEW_ID)
    assert device.name == "Kitchen panel" and device.area_id == "kitchen"
    entities = er.async_get(hass)
    ids = {e.entity_id for e in er.async_entries_for_device(entities, device.id)}
    assert {
        "switch.kitchen_panel_photo_caption", "switch.kitchen_panel_house_panel", "select.kitchen_panel_motion",
        "select.kitchen_panel_photos_every", "binary_sensor.kitchen_panel_connected", "sensor.kitchen_panel_view",
        "sensor.kitchen_panel_on_the_tablet",
    } <= ids
    assert not any("kitchen_kitchen" in i or i.split(".", 1)[1].startswith("panel_") for i in ids)
    # Named by translation key as every panel entity is
    assert entities.async_get("switch.kitchen_panel_photo_caption").translation_key == "panel_photo_caption"

    # Sent again until the panel subscribes with it; then a hello is rule 1, with a new secret
    _r, again, _ = await admin.hello(NEW_ID, area="Kitchen")
    assert again == event
    assert (await admin.subscribe(NEW_ID, event["secret"]))["success"]
    assert (await admin.event())["panel"]["device_id"] == NEW_ID
    assert _panels(hass).hellos == {}
    reinstalled = await _socket(hass_ws_client, hass)
    _r, renewed, _ = await reinstalled.hello(NEW_ID)
    assert renewed["status"] == "approved" and renewed["device_id"] == NEW_ID
    assert renewed["secret"] != event["secret"]
    assert await admin.event() == {"unpaired": True}


async def test_an_area_is_an_id_or_a_name(hass: HomeAssistant, hass_client_no_auth, hass_ws_client) -> None:
    await _household(hass, hass_client_no_auth)
    admin = await _socket(hass_ws_client, hass)
    _r, by_id, _ = await admin.hello(NEW_ID, area="bedroom")
    _r, by_name, _ = await admin.hello(TABLET_ID, area="kitchen")
    assert by_id["area_id"] == "bedroom" and by_name["area_id"] == "kitchen"
    # An area HA doesn't have waits, even for an administrator
    _r, nowhere, _ = await admin.hello("panel-00000000cccc3333", area="Attic")
    assert nowhere == {"status": "pending"}


async def test_rule_1_on_the_panel_s_own_login_gives_a_new_secret_and_the_old_one_stops(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    key, mac = panels.panels[PANEL_ID]["key"], panels.panels[PANEL_ID]["mac"]
    panels.set_values(PANEL_ID, {"motion": "calm"})
    # The panel subscribes on the shared displays login: the login is kept with the panel
    old = await _socket(hass_ws_client, hass, TOKENS[0])
    assert (await old.subscribe(PANEL_ID, body["secret"]))["success"]
    await old.event()
    assert panels.panels[PANEL_ID]["user_id"] == DISPLAYS[0].id

    # Reinstalled (no secret): a hello on the same login is that panel again, at once
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    _r, event, _ = await tablet.hello(PANEL_ID)
    assert event["status"] == "approved" and event["device_id"] == PANEL_ID and event["secret"] != body["secret"]
    assert event["area_id"] == "kitchen" and event["name"] == "Kitchen panel"
    # The old secret's subscription is told, and the old secret is refused from now on (review finding 4)
    assert await old.event() == {"unpaired": True}
    refused = await tablet.subscribe(PANEL_ID, body["secret"])
    assert not refused["success"] and refused["error"]["code"] == "unknown_panel"
    assert (await tablet.subscribe(PANEL_ID, event["secret"]))["success"]
    # Settings, room, proxy key and MAC stay
    assert panels.value(PANEL_ID, "motion") == "calm"
    assert panels.panels[PANEL_ID]["key"] == key and panels.panels[PANEL_ID]["mac"] == mac
    assert _device(hass).area_id == "kitchen"


async def test_the_panels_shared_login_with_a_room_is_a_new_panel_at_once(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    # The owner's choice: a setup command that names a room needs no step in HA, on any login
    entry, _client = await _household(hass, hass_client_no_auth)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    _r, event, _ = await tablet.hello(NEW_ID, area="Kitchen")
    assert event["status"] == "approved" and event["device_id"] == NEW_ID and event["area_id"] == "kitchen"
    assert _panels(hass).has(NEW_ID)
    assert dr.async_get(hass).async_get_device_by_identifier((DOMAIN, f"panel:{NEW_ID}"), entry.entry_id) is not None
    # Without a room it still waits
    _r, waits, _ = await tablet.hello(TABLET_ID)
    assert waits == {"status": "pending"}


async def test_an_adult_s_login_is_approved_at_once(hass: HomeAssistant, hass_client_no_auth, hass_ws_client) -> None:
    await _household(hass, hass_client_no_auth)
    jordan = await _adult(hass)
    adult = await _socket(hass_ws_client, hass, await _token(hass, jordan, "Setup"))
    _r, event, _ = await adult.hello(NEW_ID, area="Kitchen")
    assert event["status"] == "approved" and event["device_id"] == NEW_ID


async def test_rule_2_a_new_tablet_takes_the_offline_panel_s_place(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client, freezer
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    key, mac = panels.panels[PANEL_ID]["key"], panels.panels[PANEL_ID]["mac"]
    old = await _socket(hass_ws_client, hass, TOKENS[0])
    assert (await old.subscribe(PANEL_ID, body["secret"]))["success"]
    await old.ws.close()
    await _offline(hass, freezer)
    logbook = async_capture_events(hass, "logbook_entry")

    # A new tablet on the panels' login, for the kitchen: the kitchen panel's place
    tablet = await _socket(hass_ws_client, hass, TOKENS[1])
    _r, event, _ = await tablet.hello(TABLET_ID, area="Kitchen")
    assert event["status"] == "approved" and event["device_id"] == PANEL_ID and event["area_id"] == "kitchen"
    await hass.async_block_till_done()
    record = panels.panels[PANEL_ID]
    assert record["tablet_ids"] == [TABLET_ID] and not panels.has(TABLET_ID)
    # The same proxy (key and MAC), and the old secret stops
    assert record["key"] == key and record["mac"] == mac
    assert not panels.authorized(PANEL_ID, body["secret"]) and panels.authorized(PANEL_ID, event["secret"])
    assert [(e.data["name"], e.data["message"]) for e in logbook] == [("Kitchen panel", "moved to a new tablet")]
    assert logbook[0].data["entity_id"] == "binary_sensor.kitchen_panel_connected"
    assert (await tablet.subscribe(PANEL_ID, event["secret"]))["success"]
    await tablet.event()

    # The tablet's own id is the panel's from now on (rule 1 after a reinstall), and a TV can't pair over it
    await tablet.ws.close()
    again = await _socket(hass_ws_client, hass, TOKENS[1])
    _r, renewed, _ = await again.hello(TABLET_ID, area="Bedroom")
    assert renewed["device_id"] == PANEL_ID and renewed["area_id"] == "kitchen"
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    tv = await client.post(
        "/api/hearth/pair", json={"device_id": TABLET_ID, "kind": "tv", "name": "TV", "nonce": "n" * 40}
    )
    assert tv.status == 400
    # get_panel shows the tablets to an administrator
    assert panels.describe(PANEL_ID, admin=True)["tablet_ids"] == [TABLET_ID]


async def test_a_second_tablet_is_a_new_panel_when_the_first_is_on_or_replaces_is_false(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client, freezer
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    body = await _pair_panel(hass, client, area_id="kitchen")
    on = await _socket(hass_ws_client, hass, TOKENS[0])
    assert (await on.subscribe(PANEL_ID, body["secret"]))["success"]
    admin = await _socket(hass_ws_client, hass)
    _r, second, _ = await admin.hello(NEW_ID, area="Kitchen")
    assert second["device_id"] == NEW_ID
    await on.ws.close()
    await _offline(hass, freezer)
    # Both kitchen panels are offline now (the new one never subscribed): not one, so a new panel
    _r, third, _ = await admin.hello(TABLET_ID, area="Kitchen", replaces=False)
    assert third["device_id"] == TABLET_ID
    assert "tablet_ids" not in _panels(hass).panels[PANEL_ID]


async def test_a_waiting_hello_is_approved_in_ha_sent_again_until_subscribed_and_outlives_restarts(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    entry, _client = await _household(hass, hass_client_no_auth)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    _r, event, _ = await tablet.hello(NEW_ID, seed={"look": {"motion": "lively"}})
    assert event == {"status": "pending"}
    await hass.async_block_till_done()
    panels = _panels(hass)
    first_seen = panels.hellos[NEW_ID]["first_seen"]
    # Its discovered card, and the adults' notice (no buttons: it never approves by itself)
    flows = [f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN) if f["context"].get("unique_id") == f"panel_hello:{NEW_ID}"]
    assert len(flows) == 1

    # Home Assistant restarts: still waiting, the same entry, and its card again
    await _restart(hass, entry)
    panels = _panels(hass)
    assert panels.hellos[NEW_ID]["status"] == "pending" and panels.hellos[NEW_ID]["first_seen"] == first_seen
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    _r, event, msg_id = await tablet.hello(NEW_ID)
    assert event == {"status": "pending"} and len(panels.hellos) == 1
    flows = [f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN) if f["context"].get("unique_id") == f"panel_hello:{NEW_ID}"]
    assert len(flows) == 1

    # An adult picks its room on the card: a new panel; the open hello is told
    step = await hass.config_entries.flow.async_configure(flows[0]["flow_id"], {"next_step_id": "panel_add"})
    assert step["type"] is FlowResultType.FORM and {str(k) for k in step["data_schema"].schema} == {"area_id", "replaces"}
    done = await hass.config_entries.flow.async_configure(flows[0]["flow_id"], {"area_id": "bedroom", "replaces": "new"})
    assert done["type"] is FlowResultType.ABORT and done["reason"] == "panel_added"
    approved = await tablet.event()
    assert approved["status"] == "approved" and approved["device_id"] == NEW_ID and approved["area_id"] == "bedroom"
    # The seed it brought is taken at its first pairing
    assert panels.value(NEW_ID, "motion") == "lively"
    assert _device(hass, NEW_ID).name == "Bedroom panel"

    # Lost before it subscribed (a dropped socket, a restart): the same answer on the next hello
    await _restart(hass, entry)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    _r, again, _ = await tablet.hello(NEW_ID)
    assert again == approved
    # Another login never gets it
    kid = await _socket(hass_ws_client, hass, await _kid(hass))
    _r, other, _ = await kid.hello(NEW_ID)
    assert other == {"status": "pending"}
    # The ack: the panel's first subscribe with that secret; it is never sent again
    assert (await tablet.subscribe(NEW_ID, approved["secret"]))["success"]
    assert _panels(hass).hellos == {}


async def test_a_waiting_hello_takes_an_offline_panel_s_place_from_the_card(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    tablet = await _socket(hass_ws_client, hass, await _kid(hass))
    _r, event, _ = await tablet.hello(TABLET_ID)
    assert event == {"status": "pending"}
    await hass.async_block_till_done()
    flow = next(
        f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN)
        if f["context"].get("unique_id") == f"panel_hello:{TABLET_ID}"
    )
    await hass.config_entries.flow.async_configure(flow["flow_id"], {"next_step_id": "panel_add"})
    # The room is required
    with pytest.raises(Exception):
        await hass.config_entries.flow.async_configure(flow["flow_id"], {"replaces": PANEL_ID})
    done = await hass.config_entries.flow.async_configure(flow["flow_id"], {"area_id": "kitchen", "replaces": PANEL_ID})
    assert done["reason"] == "panel_added"
    approved = await tablet.event()
    assert approved["device_id"] == PANEL_ID
    assert panels.panels[PANEL_ID]["tablet_ids"] == [TABLET_ID]


async def test_a_refused_hello_is_told_and_answered_denied_for_a_day(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client, freezer
) -> None:
    await _household(hass, hass_client_no_auth)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    await tablet.hello(NEW_ID)
    # Refused on Hearth's page
    admin = await _socket(hass_ws_client, hass)
    await admin.ws.send_json({"id": 1, "type": "hearth/config"})
    config = (await admin.ws.receive_json())["result"]
    assert [h["device_id"] for h in config["panel_hellos"]] == [NEW_ID]
    assert {"id": "kitchen", "name": "Kitchen"} in config["areas"]
    await admin.ws.send_json({"id": 2, "type": "hearth/panel_hello", "device_id": NEW_ID, "answer": "deny"})
    assert (await admin.ws.receive_json())["success"]
    assert await tablet.event() == {"status": "denied"}
    await hass.async_block_till_done()
    assert not [f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN) if f["context"].get("unique_id") == f"panel_hello:{NEW_ID}"]
    _r, again, _ = await tablet.hello(NEW_ID)
    assert again == {"status": "denied"}
    # A day later it may wait again
    freezer.tick(HELLO_DENIED_FOR + timedelta(minutes=1))
    _r, later, _ = await tablet.hello(NEW_ID)
    assert later == {"status": "pending"}


async def test_hearth_s_page_approves_with_a_room(hass: HomeAssistant, hass_client_no_auth, hass_ws_client) -> None:
    await _household(hass, hass_client_no_auth)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    await tablet.hello(NEW_ID)
    admin = await _socket(hass_ws_client, hass)
    await admin.ws.send_json({"id": 1, "type": "hearth/panel_hello", "device_id": NEW_ID, "answer": "approve"})
    assert (await admin.ws.receive_json())["error"]["code"] == "invalid_format"
    await admin.ws.send_json(
        {"id": 2, "type": "hearth/panel_hello", "device_id": NEW_ID, "answer": "approve", "area_id": "kitchen"}
    )
    assert (await admin.ws.receive_json())["success"]
    approved = await tablet.event()
    assert approved["status"] == "approved" and approved["device_id"] == NEW_ID and approved["area_id"] == "kitchen"
    # Not an administrator: refused
    displays = await _socket(hass_ws_client, hass, TOKENS[1])
    await displays.ws.send_json({"id": 1, "type": "hearth/panel_hello", "device_id": NEW_ID, "answer": "deny"})
    assert not (await displays.ws.receive_json())["success"]


async def test_a_tv_s_or_a_phone_s_id_is_never_a_panel_s(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair(hass, client)
    admin = await _socket(hass_ws_client, hass)
    result, event, _ = await admin.hello(TV_ID, area="Kitchen")
    assert not result["success"] and result["error"]["code"] == "taken" and event is None
    assert not _panels(hass).has(TV_ID) and _panels(hass).hellos == {}


async def test_waiting_hellos_are_capped_and_dropped_after_30_days_unseen(
    hass: HomeAssistant, hass_client_no_auth, hass_ws_client, freezer, monkeypatch
) -> None:
    await _household(hass, hass_client_no_auth)
    monkeypatch.setattr(manager, "MAX_HELLOS", 2)
    tablet = await _socket(hass_ws_client, hass, TOKENS[0])
    await tablet.hello(NEW_ID)
    await tablet.hello(TABLET_ID)
    result, _e, _ = await tablet.hello("panel-00000000cccc3333")
    assert result["error"]["code"] == "try_later"
    # The same id again is the same entry, never a second one
    _r, same, _ = await tablet.hello(NEW_ID)
    assert same == {"status": "pending"} and len(_panels(hass).hellos) == 2
    freezer.tick(timedelta(days=20))
    await tablet.hello(NEW_ID)
    freezer.tick(HELLO_UNSEEN - timedelta(days=5))
    _r, later, _ = await tablet.hello("panel-00000000cccc3333")
    assert later == {"status": "pending"}
    # TABLET_ID was unseen for more than 30 days; NEW_ID was seen 25 days ago
    assert set(_panels(hass).hellos) == {NEW_ID, "panel-00000000cccc3333"}


# The proxy MAC (1.4)


async def test_a_panel_without_a_mac_adopts_its_live_proxy_s_on_setup_and_keeps_it(
    hass: HomeAssistant, hass_client_no_auth, hass_storage
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    await _pair_panel(hass, client, OTHER_ID, area_id="bedroom")
    # The kitchen panel's proxy is in ESPHome already (its unique id is its MAC); the bedroom's isn't
    MockConfigEntry(domain="esphome", unique_id=MAC, title="kitchen-panel", data={"host": "192.0.2.10"}).add_to_hass(hass)
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop(f"{DOMAIN}_glint_panel")
    for record in hass_storage[f"{DOMAIN}.panels"]["data"]["panels"].values():
        # As stored before 1.4: no MAC
        record.pop("mac")
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    panels = _panels(hass)
    assert panels.panels[PANEL_ID]["mac"] == MAC
    assert panels.panels[OTHER_ID]["mac"] == hello.mac_from_id(OTHER_ID)
    assert panels.document(PANEL_ID)["proxy"]["mac"] == MAC

    # Once stored, it never changes on its own (another ESPHome entry of that name, a rename)
    MockConfigEntry(domain="esphome", unique_id=OTHER_MAC, title="bedroom-panel").add_to_hass(hass)
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=5))
    await hass.async_block_till_done()
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop(f"{DOMAIN}_glint_panel")
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    assert _panels(hass).panels[OTHER_ID]["mac"] == hello.mac_from_id(OTHER_ID)
    assert _panels(hass).panels[PANEL_ID]["mac"] == MAC


async def test_a_mac_another_panel_holds_is_never_adopted_twice(
    hass: HomeAssistant, hass_client_no_auth, hass_storage
) -> None:
    entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    await _pair_panel(hass, client, OTHER_ID, area_id="bedroom")
    MockConfigEntry(domain="esphome", unique_id=MAC, title="bedroom-panel").add_to_hass(hass)
    _panels(hass).set_proxy_mac(PANEL_ID, MAC)
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=5))
    await hass.async_block_till_done()
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop(f"{DOMAIN}_glint_panel")
    hass_storage[f"{DOMAIN}.panels"]["data"]["panels"][OTHER_ID].pop("mac")
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    assert _panels(hass).panels[OTHER_ID]["mac"] == hello.mac_from_id(OTHER_ID)


async def test_set_panel_changes_the_mac_for_administrators_only(
    hass: HomeAssistant, hass_client_no_auth, hass_admin_user
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    before = panels.panels[PANEL_ID]["mac"]
    device = _device(hass).id
    admin = Context(user_id=hass_admin_user.id)
    answer = await hass.services.async_call(
        DOMAIN, "set_panel", {"device_id": device, "proxy_mac": "02-00-5E-10-00-02"}, blocking=True,
        return_response=True, context=admin,
    )
    assert answer["proxy_mac"] == OTHER_MAC == panels.panels[PANEL_ID]["mac"] != before
    assert "mac" not in answer["proxy"] and "key" not in answer["proxy"]
    assert panels.document(PANEL_ID)["proxy"]["mac"] == OTHER_MAC
    for bad in ("01:00:5e:10:00:01", "nope", 12):
        with pytest.raises(ServiceValidationError) as err:
            await hass.services.async_call(
                DOMAIN, "set_panel", {"device_id": device, "proxy_mac": bad}, blocking=True, context=admin
            )
        assert "nope" not in str(err.value)
    jordan = await _adult(hass)
    for context in (Context(user_id=jordan.id), None):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, "set_panel", {"device_id": device, "proxy_mac": MAC}, blocking=True, context=context
            )
    assert panels.panels[PANEL_ID]["mac"] == OTHER_MAC


async def test_get_panel_shows_the_mac_and_tablet_ids_to_administrators_only(
    hass: HomeAssistant, hass_client_no_auth, hass_admin_user
) -> None:
    _entry, client = await _household(hass, hass_client_no_auth)
    await _pair_panel(hass, client, area_id="kitchen")
    panels = _panels(hass)
    panels.panels[PANEL_ID]["tablet_ids"] = [TABLET_ID]
    admin = await hass.services.async_call(
        DOMAIN, "get_panel", {}, blocking=True, return_response=True, context=Context(user_id=hass_admin_user.id)
    )
    assert admin["panels"][0]["mac"] == panels.panels[PANEL_ID]["mac"]
    assert admin["panels"][0]["tablet_ids"] == [TABLET_ID]
    assert "mac" not in admin["panels"][0]["document"]["proxy"]
    jordan = await _adult(hass)
    for context in (Context(user_id=jordan.id), None):
        got = await hass.services.async_call(DOMAIN, "get_panel", {}, blocking=True, return_response=True, context=context)
        assert all(k not in got["panels"][0] for k in ("mac", "tablet_ids", "proxy_key"))
