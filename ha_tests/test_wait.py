"""A device's long-poll: answered as soon as its state document changes, so a TV hears a pause in seconds."""

import asyncio
from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_init import TV_ID, _post
from test_people import _household_with_sam, _tv_status


def _wait(client, secret: str | None, version: str | None = None, timeout: float = 5, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    params = {"timeout": str(timeout)}
    if version is not None:
        params["version"] = version
    return client.get(f"/api/hearth/device/{device_id}/wait", params=params, headers=headers)


async def _version(client, secret: str) -> str:
    response = await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))
    return (await response.json())["state"]["version"]


async def test_a_paired_device_only(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert (await _wait(client, None)).status == 401
    assert (await _wait(client, "not-the-secret")).status == 401
    assert (await _wait(client, secret, timeout="soon")).status == 400


async def test_an_old_or_missing_version_answers_at_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert await (await _wait(client, secret)).json() == {"changed": True}
    assert await (await _wait(client, secret, version="0000000000000000")).json() == {"changed": True}


async def test_a_pause_wakes_the_tv(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    version = await _version(client, secret)
    await hass.async_block_till_done()

    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=30))
    await asyncio.sleep(0.1)
    assert not held.done()

    await hass.services.async_call(DOMAIN, "pause", {"minutes": 30, "reason": "Dinner"}, blocking=True)
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    response = await asyncio.wait_for(held, 10)
    assert await response.json() == {"changed": True}


async def test_nothing_changed_answers_at_the_timeout(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    version = await _version(client, secret)
    await hass.async_block_till_done()
    assert await (await _wait(client, secret, version=version, timeout=1)).json() == {"changed": False}


async def test_a_reload_ends_the_wait(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    version = await _version(client, secret)
    await hass.async_block_till_done()

    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=30))
    await asyncio.sleep(0.1)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    response = await asyncio.wait_for(held, 10)
    assert await response.json() == {"changed": False}
