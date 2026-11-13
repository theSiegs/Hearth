"""Notices on the TVs: the attention items for TVs (the chosen suggestions) in the state document of a TV that shows
them (cap "notices"), never a phone's; a new one wakes the TV's wait, an unchanged one doesn't."""

import asyncio
from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_attention import _household, _hub, _press
from test_init import PHONE_ID, TV_ID, _pair, _post
from test_people import _tv_status
from test_phones import _options
from test_suggest_push import KEY, TAG, _check, _video_out
from test_wait import _wait

CAPS = ["commands.play", "events", "notices"]
TV_STATUS = {**_tv_status(hearthtube_s=600, game_s=300), "caps": CAPS}
NOTICE = {
    "key": KEY,
    "tag": TAG,
    "title": "Sam's Video ran out",
    "message": "Give 30 more minutes today?",
    "urgency": "notice",
    "actions": [{"id": "0", "title": "+30 min"}, {"id": "1", "title": "+15 min"}, {"id": "2", "title": "Not today"}],
}


async def _state(client, secret: str, body=TV_STATUS, device_id: str = TV_ID) -> dict:
    response = await _post(client, secret, body=body, device_id=device_id)
    assert response.status == 200
    return (await response.json())["state"]


async def _suggested(hass: HomeAssistant, hass_client_no_auth):
    """Sam's Video is out and its suggestion was pushed (the household chose it)."""
    client, secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    await _check(hass)
    return client, secret, users, sent


async def test_a_tv_that_shows_notices_gets_the_suggestion(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    state = await _state(client, secret)
    # For every adult: no "for"; no service or data, only the buttons' numbers and titles
    assert state["notices"] == [NOTICE]
    assert "person.sam" in state["people"].values()


async def test_a_tv_without_the_cap_gets_none(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    # A TV from before caps (its kind's defaults), or one that declares caps without notices
    assert "notices" not in await _state(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))
    assert "notices" not in await _state(client, secret, body={**TV_STATUS, "caps": ["commands.play", "events"]})


async def test_a_phone_never_gets_the_adults_notices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, _secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    phone_secret = await _pair(hass, client, PHONE_ID, "mobile", "Phone")
    # Even one that says it shows notices
    state = await _state(client, phone_secret, body={"screen": "on", "caps": ["push", "notices"]}, device_id=PHONE_ID)
    assert "notices" not in state
    assert KEY not in str(state)


async def test_a_new_notice_wakes_the_tv_and_an_unchanged_one_doesn_t(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    version = (await _state(client, secret))["version"]
    await hass.async_block_till_done()

    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=30))
    await asyncio.sleep(0.1)
    assert not held.done()
    await _check(hass)
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    assert await (await asyncio.wait_for(held, 10)).json() == {"changed": True}

    # Looked at again, the same notice: the TV isn't woken
    version = (await _state(client, secret))["version"]
    await hass.async_block_till_done()
    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=1))
    await asyncio.sleep(0.1)
    await _check(hass)
    _hub(hass).waits.changed()
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    assert await (await asyncio.wait_for(held, 10)).json() == {"changed": False}


async def test_a_cleared_notice_goes_from_the_tv(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, _sent = await _suggested(hass, hass_client_no_auth)
    assert (await _state(client, secret))["notices"] == [NOTICE]
    # "Not today" from an adult's phone: the suggestion goes, and with it the TV's notice
    _press(hass, f"HEARTH_ACT|{KEY}|2", users["alex"])
    await hass.async_block_till_done()
    await _check(hass)
    assert (await _state(client, secret))["notices"] == []
