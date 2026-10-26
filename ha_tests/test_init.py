"""Setting up the household, pairing a TV, and the TV's status."""

from datetime import timedelta
from unittest.mock import patch

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.helpers import device_registry as dr
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN

TV_ID = "tv-0123456789abcdef"
NONCE = "n" * 40
STATUS = {
    "screen": "on",
    "state": "playing",
    "app": "Example TV",
    "app_package": "com.example.tv",
    "media_title": "Episode 1",
    "profile": "Alex",
    "profile_id": "user:0",
    "kids_profile": False,
    "screen_time_up": False,
    "seconds_today": 600,
}


async def _set_up(hass: HomeAssistant):
    from homeassistant.setup import async_setup_component

    assert await async_setup_component(hass, "http", {})
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.FORM
    result = await hass.config_entries.flow.async_configure(result["flow_id"], {"name": "Home"})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    return hass.config_entries.async_entries(DOMAIN)[0]


async def _pair(hass: HomeAssistant, client) -> str:
    """Pairs a TV as an administrator would, and returns the TV's secret."""
    response = await client.post(
        "/api/hearth/pair",
        json={"tv_id": TV_ID, "name": "Kitchen", "model": "Example box", "version": "2026.10.85", "nonce": NONCE},
    )
    assert response.status == 200
    started = await response.json()
    assert len(started["code"]) == 6
    await hass.async_block_till_done()

    flows = hass.config_entries.flow.async_progress_by_handler(DOMAIN)
    assert len(flows) == 1
    assert flows[0]["step_id"] == "confirm"

    pending = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    assert (await pending.json())["status"] == "pending"

    result = await hass.config_entries.flow.async_configure(flows[0]["flow_id"], {})
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "paired"
    await hass.async_block_till_done()

    approved = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    body = await approved.json()
    assert body["status"] == "approved"
    assert body["tv_id"] == TV_ID
    # Handed over once
    again = await client.get(f"/api/hearth/pair/{started['pairing_id']}", headers={"X-Hearth-Nonce": NONCE})
    assert again.status == 404
    return body["secret"]


async def _post(client, secret: str | None, body=STATUS, tv_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return await client.post(f"/api/hearth/tv/{tv_id}/status", json=body, headers=headers)


async def test_one_household(hass: HomeAssistant) -> None:
    await _set_up(hass)
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "single_instance_allowed"


async def test_pair_then_post_status(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)

    device = dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id)
    assert device is not None
    assert device.name == "Kitchen"
    assert device.sw_version == "2026.10.85"

    assert (await _post(client, secret)).status == 200
    await hass.async_block_till_done()

    assert hass.states.get("sensor.kitchen_state").state == "playing"
    assert hass.states.get("sensor.kitchen_app").state == "Example TV"
    assert hass.states.get("sensor.kitchen_app").attributes["package"] == "com.example.tv"
    assert hass.states.get("sensor.kitchen_media_title").state == "Episode 1"
    assert hass.states.get("sensor.kitchen_profile").attributes["profile_id"] == "user:0"
    assert hass.states.get("binary_sensor.kitchen_kids_profile").state == "off"
    assert hass.states.get("binary_sensor.kitchen_connected").state == "on"


async def test_before_a_status_the_tv_is_unavailable(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass)
    await _pair(hass, await hass_client_no_auth())
    await hass.async_block_till_done()
    assert hass.states.get("sensor.kitchen_state").state == "unavailable"
    assert hass.states.get("binary_sensor.kitchen_connected").state == "off"


async def test_a_quiet_tv_turns_unavailable(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    await _post(client, secret)
    await hass.async_block_till_done()

    later = dt_util.utcnow() + timedelta(minutes=16)
    with patch("homeassistant.util.dt.utcnow", return_value=later):
        async_fire_time_changed(hass, later)
        await hass.async_block_till_done()
        assert hass.states.get("binary_sensor.kitchen_connected").state == "off"
        assert hass.states.get("sensor.kitchen_state").state == "unavailable"


async def test_wrong_or_missing_secret_is_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    assert (await _post(client, "not-the-secret")).status == 401
    assert (await _post(client, None)).status == 401
    assert (await _post(client, secret, tv_id="tv-someoneelse00")).status == 401


async def test_wrong_nonce_cant_collect_the_secret(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    response = await client.post("/api/hearth/pair", json={"tv_id": TV_ID, "name": "Kitchen", "nonce": NONCE})
    pairing_id = (await response.json())["pairing_id"]
    assert (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": "m" * 40})).status == 404
    assert (await client.get(f"/api/hearth/pair/{pairing_id}")).status == 404


async def test_bad_posts_are_refused(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    assert (await _post(client, secret, body=[1, 2])).status == 400
    huge = {**STATUS, "media_title": "x" * (70 * 1024)}
    assert (await _post(client, secret, body=huge)).status == 400
    bad = await client.post("/api/hearth/pair", json={"tv_id": "x", "nonce": "short"})
    assert bad.status == 400


async def test_too_many_posts(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    codes = [(await _post(client, secret)).status for _ in range(25)]
    assert codes.count(200) == 20
    assert codes[-1] == 429


async def test_asking_to_pair_too_often(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    first = await client.post("/api/hearth/pair", json={"tv_id": TV_ID, "name": "Kitchen", "nonce": NONCE})
    second = await client.post("/api/hearth/pair", json={"tv_id": TV_ID, "name": "Kitchen", "nonce": NONCE})
    assert first.status == 200
    assert second.status == 429


async def test_only_local_addresses(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    with patch("custom_components.hearth.api.is_local", return_value=False):
        response = await client.post("/api/hearth/pair", json={"tv_id": TV_ID, "name": "Kitchen", "nonce": NONCE})
        assert response.status == 403
        assert (await _post(client, "anything")).status == 403


async def test_removing_the_device_removes_the_tv(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    from homeassistant.setup import async_setup_component

    assert await async_setup_component(hass, "config", {})
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    device = dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id)

    ws = await hass_ws_client(hass)
    await ws.send_json(
        {
            "id": 1,
            "type": "config/device_registry/remove_config_entry",
            "config_entry_id": entry.entry_id,
            "device_id": device.id,
        }
    )
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()

    assert (await _post(client, secret)).status == 401
    assert dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id) is None


async def test_status_survives_a_restart(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    await _post(client, secret)
    await hass.async_block_till_done()

    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.kitchen_app").state == "Example TV"
