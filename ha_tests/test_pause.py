"""A family pause, and when a person's locks start and end."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option


async def test_a_pause_holds_everyone_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 45, "reason": "Dinner"}, blocking=True)

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is True
    assert sam["pause"]["reason"] == "Dinner"
    assert sam["lock"]["by"] == ["pause"] and sam["lock"]["until"] == sam["pause"]["until"]
    assert sam["lock"]["kind"] == "pause"

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    [person] = (await ws.receive_json())["result"]["people"]
    assert person["pause"]["reason"] == "Dinner"

    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is False and "pause" not in sam and "lock" not in sam

    # On its own, it ends when its time is up
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 10, "people": ["person.sam"]}, blocking=True)
    freezer.tick(timedelta(minutes=11))
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["locked"] is False


async def test_bedtime_says_until_when_and_comes_with_a_heads_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=20, minute=30, second=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    today = dt_util.now().date()
    tomorrow = today + timedelta(days=1)
    bedtime = "binary_sensor.sam_tablet_bedtime_active"
    attributes = {"bedtime_start": f"{today}T21:00:00", "bedtime_end": f"{tomorrow}T07:00:00"}
    hass.states.async_set(bedtime, "off", attributes)
    await _option(hass, "locks", {"person": "person.sam", "entities": [bedtime]})

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    upcoming = body["state"]["profiles"][KID]["next_lock"]
    assert upcoming["by"] == bedtime and upcoming["kind"] == "bedtime"
    assert dt_util.parse_datetime(upcoming["at"]).hour == 21

    hass.states.async_set(bedtime, "on", attributes)
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["lock"]["by"] == [bedtime] and sam["lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["lock"]["until"]).hour == 7
    assert "next_lock" not in sam
