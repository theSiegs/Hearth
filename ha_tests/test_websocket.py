"""The household summary on Home Assistant's WebSocket."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from test_init import TV_ID, _post
from test_people import _household_with_sam, _tv_status
from test_sources import _option


async def test_the_household_at_a_glance(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    from test_parent_pin import _adults

    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": "4826", "pin_again": "4826"})

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    body = answer["result"]
    people = {p["id"]: p for p in body["people"]}
    assert people["person.alex"]["kind"] == "adult" and people["person.alex"]["kind_set"] is True
    assert body["contract"] == 2
    sam = people["person.sam"]
    assert sam["name"] == "Sam"
    assert sam["tv_profiles"] == ["user:10"]
    assert sam["all"]["used_minutes"] == 15
    assert sam["all"]["budget"] is None and sam["all"]["bonus"] == 0
    assert sam["held"] is False and sam["held_by"] == []
    [tv] = body["devices"]
    assert tv["id"] == TV_ID and tv["kind"] == "tv" and tv["connected"] is True
    assert body["approvals"] == []
    assert body["version"]


async def test_a_subscriber_hears_of_changes_once_settled(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household/subscribe"})
    assert (await ws.receive_json())["success"]
    first = (await ws.receive_json())["event"]
    assert first["people"][0]["all"]["used_minutes"] == 15

    await _post(client, secret, body=_tv_status(hearthtube_s=1200, game_s=300))
    await hass.async_block_till_done()
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=3))
    await hass.async_block_till_done()
    second = (await ws.receive_json())["event"]
    assert second["people"][0]["all"]["used_minutes"] == 25
    assert second["version"] != first["version"]


async def test_an_adult_who_isn_t_an_administrator_reads_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    from test_parent_pin import _adults

    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": hass_admin_user.id})
    await _adults(hass, "person.alex")
    hass_admin_user.groups = []
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    assert all(a["type"] != "pairing" for a in answer["result"]["approvals"])


async def test_only_administrators_get_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass_admin_user.groups = []
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert not answer["success"] and answer["error"]["code"] == "unauthorized"
