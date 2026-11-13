"""What a device can be sent (caps): said in its status, else its kind's, so devices from before caps keep what they
had."""

import time

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import CAP_EVENTS, CAP_NOTICES, CAP_PLAY, CAP_PUSH, DOMAIN, default_caps
from custom_components.hearth.status import clean_status
from test_init import PHONE_ID, STATUS, TV_ID, _pair, _post, _set_up
from test_watch import _events, _started


def test_unknown_caps_are_dropped() -> None:
    assert clean_status({})["caps"] is None
    assert clean_status({"caps": "push"})["caps"] is None
    assert clean_status({"caps": ["notices", "teleport", 7, None, "push", "notices"]})["caps"] == ["notices", "push"]
    # At most 16 are looked at: a known one past them is dropped too
    assert clean_status({"caps": ["x"] * 16 + ["push"]})["caps"] == []
    assert clean_status({"caps": []})["caps"] == []


def test_each_kind_has_what_it_had() -> None:
    assert default_caps("tv") == {CAP_PLAY, CAP_EVENTS}
    assert default_caps("mobile") == {CAP_PUSH}
    assert default_caps(None) == set()


async def _tv_and_phone(hass: HomeAssistant, hass_client_no_auth):
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    # One address may ask to pair only every 10 seconds
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    phone_secret = await _pair(hass, client, PHONE_ID, "mobile", "Phone")
    return client, secret, phone_secret


async def test_default_caps_keep_today_s_behaviour(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, phone_secret = await _tv_and_phone(hass, hass_client_no_auth)
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    tv = await (await _post(client, secret)).json()
    phone = await (await _post(client, phone_secret, body={"screen": "on"}, device_id=PHONE_ID)).json()
    assert hub.has_cap(TV_ID, CAP_PLAY) and hub.has_cap(TV_ID, CAP_EVENTS) and not hub.has_cap(TV_ID, CAP_PUSH)
    assert hub.has_cap(PHONE_ID, CAP_PUSH) and not hub.has_cap(PHONE_ID, CAP_EVENTS)
    # Only the phone is told its push channel; only the TV posts events and is played on
    assert "push" not in tv and "push" in phone
    assert (await _events(client, secret, [])).status == 200
    assert (await _events(client, phone_secret, [], device_id=PHONE_ID)).status == 403
    with pytest.raises(ServiceValidationError, match="TV"):
        await hass.services.async_call(
            DOMAIN, "play_on_tv", {"device_id": PHONE_ID, "what": "aBcDeFgHiJk"}, blocking=True, return_response=True
        )


async def test_a_declared_caps_list_wins(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, phone_secret = await _tv_and_phone(hass, hass_client_no_auth)
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    # A TV that says it shows notices only: no events, no plays
    await _post(client, secret, body={**STATUS, "caps": [CAP_NOTICES, "something_newer"]})
    assert hub.has_cap(TV_ID, CAP_NOTICES) and not hub.has_cap(TV_ID, CAP_PLAY)
    response = await _events(client, secret, [_started(int(time.time() * 1000))])
    assert response.status == 403
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "play_on_tv", {"device_id": TV_ID, "what": "aBcDeFgHiJk"}, blocking=True, return_response=True
        )
    # A later post that leaves caps out keeps what it said
    await _post(client, secret)
    assert not hub.has_cap(TV_ID, CAP_EVENTS)

    # A phone that says it takes events (and not push) is told no push channel
    phone = await (
        await _post(client, phone_secret, body={"screen": "on", "caps": [CAP_EVENTS]}, device_id=PHONE_ID)
    ).json()
    assert "push" not in phone
    assert (await _events(client, phone_secret, [], device_id=PHONE_ID)).status == 200
