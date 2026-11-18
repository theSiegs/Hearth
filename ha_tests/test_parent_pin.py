"""The adults' parent PINs: set in Configure, checked for a paired device (or taken by a TV), wrong guesses locked
out."""

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
OTHER_PIN = "7351"


async def _adults(hass: HomeAssistant, *people: str) -> None:
    """Marks them as adults (Hearth's page): only an adult has a parent PIN."""
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    roles = {**entry.options.get("roles", {}), **{p: "adult" for p in people}}
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": roles})
    await hass.async_block_till_done()


async def _verify(client, secret: str | None, pin, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return await client.post(f"/api/hearth/device/{device_id}/verify_pin", json={"pin": pin}, headers=headers)


def test_the_pin_is_kept_as_a_salted_hash_in_the_tv_s_form() -> None:
    stored = parent_pin.make(PIN)
    # (A hex salt or hash can contain the digits by chance: no field is the PIN itself)
    assert PIN not in stored.split("$")
    assert parent_pin.valid(stored) and stored.startswith("v2$10000$")
    assert stored != parent_pin.make(PIN)
    assert parent_pin.matches(stored, PIN)
    assert not parent_pin.matches(stored, "4827")
    assert not parent_pin.matches(stored, "abcd")
    assert not parent_pin.matches(None, PIN)
    # Made by the TV's ParentPinHash (Dart) for the PIN 1234, salt 00..0f
    tv = "v2$10000$000102030405060708090a0b0c0d0e0f$" + parent_pin._derive("1234", bytes(range(16)), 10000).hex()
    assert parent_pin.matches(tv, "1234")


def test_any_adult_s_pin_says_whose_it_is() -> None:
    pins = {"person.alex": parent_pin.make(PIN), "person.robin": parent_pin.make(OTHER_PIN)}
    assert parent_pin.whose(pins, PIN) == "person.alex"
    assert parent_pin.whose(pins, OTHER_PIN) == "person.robin"
    assert parent_pin.whose(pins, "1111") is None


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

    await _adults(hass, "person.alex", "person.robin")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    await _option(hass, "parent_pin", {"person": "person.robin", "pin": OTHER_PIN, "pin_again": OTHER_PIN})
    stored = hass.config_entries.async_entries(DOMAIN)[0].options[parent_pin.CONF_PARENT_PINS]
    assert set(stored) == {"person.alex", "person.robin"} and PIN not in str(stored)
    used = async_capture_events(hass, parent_pin.EVENT_PARENT_PIN_USED)

    assert (await _verify(client, None, PIN)).status == 401
    assert (await _verify(client, "not-the-secret", PIN)).status == 401
    for pin, person in ((PIN, "person.alex"), (OTHER_PIN, "person.robin")):
        answer = await (await _verify(client, secret, pin)).json()
        # Contract 3: a grant for this device, two minutes, eight writes (pin_grants.py)
        assert {k: answer.pop(k) for k in ("grant_expires", "grant_writes")} == {"grant_expires": 120, "grant_writes": 8}
        assert len(answer.pop("grant")) == 32
        assert answer == {"ok": True, "person": person}
    assert await (await _verify(client, secret, "1111")).json() == {"ok": False}
    assert (await _verify(client, secret, 4826)).status == 400
    await hass.async_block_till_done()
    assert [e.data["person"] for e in used] == ["person.alex", "person.robin"]


async def test_wrong_pins_lock_the_device_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
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
    assert (await (await _verify(client, secret, PIN)).json())["ok"] is True
    # The right PIN clears the count: wrong ones are free again
    assert await (await _verify(client, secret, "1111")).json() == {"ok": False}


async def test_a_reload_keeps_the_lockout(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Changing an option reloads the entry; that mustn't hand someone guessing the PIN a fresh set of tries."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    for _ in range(parent_pin.FREE_TRIES):
        await _verify(client, secret, "1111")

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()

    response = await _verify(client, secret, PIN)
    assert response.status == 429
    assert (await response.json())["error"] == "locked_out"


async def test_the_pin_is_typed_twice_and_can_be_removed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]

    async def configure(data: dict):
        result = await hass.config_entries.options.async_init(entry.entry_id)
        result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "parent_pin"})
        return await hass.config_entries.options.async_configure(result["flow_id"], data)

    result = await configure({"person": "person.alex", "pin": PIN, "pin_again": PIN})
    assert result["type"] is FlowResultType.FORM and result["errors"] == {"person": "not_adult"}
    await _adults(hass, "person.alex", "person.robin")
    result = await configure({"person": "person.alex", "pin": "12", "pin_again": "12"})
    assert result["type"] is FlowResultType.FORM and result["errors"] == {"pin": "bad_pin"}
    result = await configure({"person": "person.alex", "pin": PIN, "pin_again": "4825"})
    assert result["type"] is FlowResultType.FORM and result["errors"] == {"pin_again": "pins_differ"}

    await _adults(hass, "person.alex", "person.robin")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    await _option(hass, "parent_pin", {"person": "person.robin", "pin": OTHER_PIN, "pin_again": OTHER_PIN})
    await _option(hass, "parent_pin", {"person": "person.alex", "remove": True})
    assert set(entry.options[parent_pin.CONF_PARENT_PINS]) == {"person.robin"}


async def test_a_tv_takes_the_adults_pins_and_reports_its_lockouts(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from test_people import _tv_status
    from test_init import _post

    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert "parent_pins" not in body["state"]

    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    locked_out = async_capture_events(hass, parent_pin.EVENT_PARENT_PIN_LOCKED_OUT)
    body = await (await _post(client, secret, body={**_tv_status(hearthtube_s=60), "pin_lockouts": 2})).json()
    [alex] = body["state"]["parent_pins"]
    assert alex["person"] == "person.alex" and parent_pin.matches(alex["hash"], PIN)
    assert isinstance(alex["profiles"], list)

    version = body["state"]["parent_pins_version"]

    # The TV has them: only the version comes again, until they change
    status = {**_tv_status(hearthtube_s=60), "pin_lockouts": 3, "parent_pins_version": version}
    body = await (await _post(client, secret, body=status)).json()
    assert "parent_pins" not in body["state"] and body["state"]["parent_pins_version"] == version
    await hass.async_block_till_done()
    assert [(e.data["device_id"], e.data["lockouts"]) for e in locked_out] == [(TV_ID, 1)]

    await _option(hass, "parent_pin", {"person": "person.alex", "pin": OTHER_PIN, "pin_again": OTHER_PIN})
    body = await (await _post(client, secret, body=status)).json()
    assert body["state"]["parent_pins_version"] != version
    assert parent_pin.matches(body["state"]["parent_pins"][0]["hash"], OTHER_PIN)


async def test_a_contract_4_tv_is_sent_no_hashes_only_the_version(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Contract 4: a TV asks verify_pin and keeps only PINs confirmed on it, so it is never sent the hashes. The
    version still comes, so it can drop what it learned when an adult's PIN changes."""
    from test_people import _tv_status
    from test_init import _post

    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    tv = {"id": "com.thesiegs.hearth", "version": "2026.11.41", "contract": 4}
    status = {**_tv_status(hearthtube_s=60), "client": tv}
    body = await (await _post(client, secret, body=status)).json()
    assert "parent_pins" not in body["state"]
    version = body["state"]["parent_pins_version"]
    assert body["contract"] == 4

    # Even a TV that says it holds an older version (or none) gets no hashes
    for said in (None, "0" * 16):
        body = await (await _post(client, secret, body={**status, "parent_pins_version": said})).json()
        assert "parent_pins" not in body["state"] and body["state"]["parent_pins_version"] == version

    # A changed PIN changes the version (the TV drops what it learned), still with no hash
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": OTHER_PIN, "pin_again": OTHER_PIN})
    body = await (await _post(client, secret, body={**status, "parent_pins_version": version})).json()
    assert "parent_pins" not in body["state"] and body["state"]["parent_pins_version"] != version
    changed = body["state"]["parent_pins_version"]

    # Removed: no version either (a TV keeps what it learned, as when unpaired)
    await _option(hass, "parent_pin", {"person": "person.alex", "remove": True})
    body = await (await _post(client, secret, body={**status, "parent_pins_version": changed})).json()
    assert "parent_pins" not in body["state"] and "parent_pins_version" not in body["state"]

    # The PIN is still checked for it
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    assert (await (await _verify(client, secret, PIN)).json())["ok"] is True
    assert await (await _verify(client, secret, OTHER_PIN)).json() == {"ok": False}


async def test_an_older_tv_is_still_sent_the_hashes_until_it_updates(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Staged migration: a TV below contract 4 can't learn PINs, so it still gets the hashes; once it reports
    contract 4 (or paired with it) it gets none, and naming an older contract later doesn't bring them back."""
    from test_people import _tv_status
    from test_init import _post

    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    old = {**_tv_status(hearthtube_s=60), "client": {"id": "com.thesiegs.hearth", "contract": 3}}
    body = await (await _post(client, secret, body=old)).json()
    assert parent_pin.matches(body["state"]["parent_pins"][0]["hash"], PIN)

    # Paired with contract 4 (the client locked at pairing): a post naming 3 gets no hashes
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    devices = {**entry.data["devices"]}
    devices[TV_ID] = {**devices[TV_ID], "client": {"id": "com.thesiegs.hearth", "contract": 4, "companions": []}}
    hass.config_entries.async_update_entry(entry, data={**entry.data, "devices": devices})
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=old)).json()
    assert "parent_pins" not in body["state"] and body["state"]["parent_pins_version"]


async def test_guesses_sent_all_at_once_never_get_past_the_free_tries(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    import asyncio

    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    checked: list[str] = []
    real = parent_pin.whose

    def counting(stored, pin):
        checked.append(pin)
        return real(stored, pin)

    parent_pin.whose = counting
    try:
        guesses = [f"{n:04d}" for n in range(1000, 1040)] + [PIN]
        answers = await asyncio.gather(*(_verify(client, secret, g) for g in guesses))
    finally:
        parent_pin.whose = real
    assert len(checked) <= parent_pin.FREE_TRIES
    bodies = [await a.json() for a in answers if a.status == 200]
    assert not any(b.get("ok") for b in bodies)


async def test_json_nested_too_deep_is_a_bad_request_not_a_crash(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    deep = "[" * 60000
    for path, headers in (("/api/hearth/pair", {}), (f"/api/hearth/device/{TV_ID}/status", {"X-Hearth-Secret": secret})):
        response = await client.post(path, data=deep, headers={**headers, "Content-Type": "application/json"})
        assert response.status < 500


async def test_a_lockout_goes_on_across_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_storage
) -> None:
    from datetime import timedelta as _td

    from homeassistant.util import dt as dt_util

    until = (dt_util.utcnow() + _td(minutes=10)).isoformat()
    hass_storage["hearth.pin_lockout"] = {
        "version": 1, "key": "hearth.pin_lockout", "data": {TV_ID: {"failures": 6, "locked_until": until}},
    }
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    response = await _verify(client, secret, PIN)
    assert response.status == 429
