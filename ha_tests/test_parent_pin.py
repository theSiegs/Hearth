"""The household's parent PIN: set in Configure, checked for a paired device, wrong guesses locked out."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import parent_pin
from custom_components.hearth.const import DOMAIN
from test_init import TV_ID
from test_people import _household_with_sam
from test_sources import _option

PIN = "4826"


async def _verify(client, secret: str | None, pin, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return await client.post(f"/api/hearth/device/{device_id}/verify_pin", json={"pin": pin}, headers=headers)


def test_the_pin_is_kept_as_a_salted_hash() -> None:
    stored = parent_pin.make(PIN)
    assert PIN not in str(stored)
    assert stored != parent_pin.make(PIN)
    assert parent_pin.matches(stored, PIN)
    assert not parent_pin.matches(stored, "4827")
    assert not parent_pin.matches(stored, "abcd")
    assert not parent_pin.matches(None, PIN)


def test_lockouts_grow_to_an_hour() -> None:
    assert parent_pin.lockout(parent_pin.FREE_TRIES - 1) is None
    assert parent_pin.lockout(parent_pin.FREE_TRIES) == timedelta(seconds=30)
    assert parent_pin.lockout(parent_pin.FREE_TRIES + 1) == timedelta(seconds=60)
    assert parent_pin.lockout(parent_pin.FREE_TRIES + 20) == timedelta(hours=1)


async def test_a_paired_device_checks_the_parent_pin(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    response = await _verify(client, secret, PIN)
    assert response.status == 404
    assert (await response.json())["error"] == "no_pin"

    await _option(hass, "parent_pin", {"pin": PIN, "pin_again": PIN})
    stored = hass.config_entries.async_entries(DOMAIN)[0].options[parent_pin.CONF_PARENT_PIN]
    assert PIN not in str(stored)

    assert (await _verify(client, None, PIN)).status == 401
    assert (await _verify(client, "not-the-secret", PIN)).status == 401
    assert await (await _verify(client, secret, PIN)).json() == {"ok": True}
    assert await (await _verify(client, secret, "1111")).json() == {"ok": False}
    assert (await _verify(client, secret, 4826)).status == 400


async def test_wrong_pins_lock_the_device_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "parent_pin", {"pin": PIN, "pin_again": PIN})
    locked_out = async_capture_events(hass, parent_pin.EVENT_PARENT_PIN_LOCKED_OUT)

    for _ in range(parent_pin.FREE_TRIES - 1):
        assert await (await _verify(client, secret, "1111")).json() == {"ok": False}
    answer = await (await _verify(client, secret, "1111")).json()
    assert answer["ok"] is False and 0 < answer["retry_in"] <= 31
    await hass.async_block_till_done()
    assert len(locked_out) == 1

    # Even the right PIN waits out the lockout
    response = await _verify(client, secret, PIN)
    assert response.status == 429
    assert (await response.json())["error"] == "locked_out"

    freezer.tick(timedelta(seconds=31))
    assert await (await _verify(client, secret, PIN)).json() == {"ok": True}
    # The right PIN clears the count: wrong ones are free again
    assert await (await _verify(client, secret, "1111")).json() == {"ok": False}


async def test_the_pin_is_typed_twice_and_can_be_removed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]

    async def configure(data: dict):
        result = await hass.config_entries.options.async_init(entry.entry_id)
        result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "parent_pin"})
        return await hass.config_entries.options.async_configure(result["flow_id"], data)

    result = await configure({"pin": "12", "pin_again": "12"})
    assert result["type"] is FlowResultType.FORM and result["errors"] == {"pin": "bad_pin"}
    result = await configure({"pin": PIN, "pin_again": "4825"})
    assert result["type"] is FlowResultType.FORM and result["errors"] == {"pin_again": "pins_differ"}

    await _option(hass, "parent_pin", {"pin": PIN, "pin_again": PIN})
    assert parent_pin.CONF_PARENT_PIN in entry.options
    await _option(hass, "parent_pin", {"remove": True})
    assert parent_pin.CONF_PARENT_PIN not in entry.options
