"""Hearth's sidebar page: its settings, budgets, pairing and parent PIN commands."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import parent_pin
from custom_components.hearth.const import DOMAIN
from test_people import _household_with_sam


async def _ws(ws, message: dict):
    _ws.n = getattr(_ws, "n", 0) + 1
    await ws.send_json({"id": _ws.n, **message})
    return await ws.receive_json()


async def test_the_page_reads_and_sets_the_household(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    ws = await hass_ws_client(hass)

    answer = await _ws(ws, {"type": "hearth/config"})
    assert answer["success"], answer
    config = answer["result"]
    assert {p["id"] for p in config["persons"]} >= {"person.sam", "person.alex"}
    assert config["profiles"] == {"user:10": "person.sam"}
    assert any(g["id"] == "all" for g in config["groups"])

    answer = await _ws(ws, {"type": "hearth/config/set", "key": "roles", "value": {"person.sam": "kid", "person.alex": "adult"}})
    assert answer["success"], answer
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["roles"] == {"person.sam": "kid", "person.alex": "adult"}

    # Checked as the Configure menu would leave it
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "roles", "value": {"person.sam": "boss"}})
    assert not answer["success"] and answer["error"]["code"] == "invalid"
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "devices", "value": {}})
    assert not answer["success"]

    answer = await _ws(ws, {"type": "hearth/budget", "person": "person.sam", "group": "all", "days": "both", "minutes": 120})
    assert answer["success"], answer
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    assert config["budgets"]["person.sam"]["all"] == {"school": 120, "other": 120}
    await _ws(ws, {"type": "hearth/budget", "person": "person.sam", "group": "all", "days": "other_days", "minutes": None})
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    assert config["budgets"]["person.sam"]["all"] == {"school": 120, "other": None}

    answer = await _ws(ws, {"type": "hearth/parent_pin", "person": "person.alex", "pin": "12"})
    assert not answer["success"] and answer["error"]["code"] == "bad_pin"
    answer = await _ws(ws, {"type": "hearth/parent_pin", "person": "person.alex", "pin": "4826"})
    assert answer["success"]
    await hass.async_block_till_done()
    stored = hass.config_entries.async_entries(DOMAIN)[0].options[parent_pin.CONF_PARENT_PINS]
    assert parent_pin.matches(stored["person.alex"], "4826")
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    assert config["parent_pins"] == ["person.alex"]
    assert "4826" not in str(config)


async def test_a_device_is_paired_from_the_page(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    # One request per address a while: the TV's was a moment ago
    freezer.tick(timedelta(minutes=5))
    client = await hass_client_no_auth()
    response = await client.post(
        "/api/hearth/pair",
        json={"device_id": "phone-0123456789", "kind": "mobile", "name": "Sam's phone", "nonce": "n" * 40},
    )
    assert response.status == 200
    await hass.async_block_till_done()
    ws = await hass_ws_client(hass)
    [pairing] = (await _ws(ws, {"type": "hearth/config"}))["result"]["pairings"]
    assert pairing["kind"] == "mobile" and len(pairing["code"]) == 6

    answer = await _ws(
        ws, {"type": "hearth/pairing", "pairing_id": pairing["pairing_id"], "answer": "approve", "person": "person.sam"}
    )
    assert answer["success"], answer
    await hass.async_block_till_done()
    devices = hass.config_entries.async_entries(DOMAIN)[0].data["devices"]
    assert devices["phone-0123456789"]["person"] == "person.sam"
    assert (await _ws(ws, {"type": "hearth/config"}))["result"]["pairings"] == []
    assert hass.config_entries.flow.async_progress_by_handler(DOMAIN) == []


async def test_only_administrators_use_the_page(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass_admin_user.groups = []
    ws = await hass_ws_client(hass)
    answer = await _ws(ws, {"type": "hearth/config"})
    assert not answer["success"] and answer["error"]["code"] == "unauthorized"
