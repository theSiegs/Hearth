"""Pairing tickets: a paired TV vouches for another TV of its household, or for a parent's phone, with no code."""

from datetime import timedelta

from freezegun.api import FrozenDateTimeFactory
from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN, EVENT_DEVICE_PAIRED
from test_init import PHONE_ID, STATUS, TV_ID, _pair, _post, _set_up

STUDY_ID = "tv-study-0123456789"


def _ticket(client, secret: str | None, body: dict, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return client.post(f"/api/hearth/device/{device_id}/ticket", json=body, headers=headers)


def _redeem(client, ticket: str, device_id: str = STUDY_ID, kind: str = "tv", name: str = "Study"):
    return client.post(
        "/api/hearth/pair/redeem",
        json={"ticket": ticket, "device_id": device_id, "kind": kind, "name": name, "model": "Box", "version": "1"},
    )


async def _paired_tv(hass: HomeAssistant, hass_client_no_auth):
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    return entry, client, await _pair(hass, client)


async def test_a_paired_tv_adds_another_tv_with_no_code(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _paired_tv(hass, hass_client_no_auth)
    fired = []
    hass.bus.async_listen(EVENT_DEVICE_PAIRED, fired.append)

    answer = await (await _ticket(client, secret, {"kind": "tv"})).json()
    assert answer["expires_in"] == 300
    redeemed = await _redeem(client, answer["ticket"])
    assert redeemed.status == 200
    body = await redeemed.json()
    assert body["status"] == "approved" and body["device_id"] == STUDY_ID and body["person"] is None
    await hass.async_block_till_done()

    # The new TV posts with its own secret, and Home Assistant knows it
    assert (await _post(client, body["secret"], device_id=STUDY_ID)).status == 200
    assert STUDY_ID in hass.config_entries.async_entries(DOMAIN)[0].data["devices"]
    assert fired[0].data["by"] == TV_ID and fired[0].data["kind"] == "tv"
    # Nobody had to confirm a code
    assert not hass.config_entries.flow.async_progress_by_handler(DOMAIN)


async def test_a_ticket_works_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _, client, secret = await _paired_tv(hass, hass_client_no_auth)
    ticket = (await (await _ticket(client, secret, {"kind": "tv"})).json())["ticket"]
    assert (await _redeem(client, ticket)).status == 200
    await hass.async_block_till_done()
    assert (await _redeem(client, ticket, device_id="tv-other-0123456789")).status == 404


async def test_a_ticket_expires_and_keeps_its_kind(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer: FrozenDateTimeFactory
) -> None:
    _, client, secret = await _paired_tv(hass, hass_client_no_auth)
    ticket = (await (await _ticket(client, secret, {"kind": "tv"})).json())["ticket"]
    # A TV's ticket doesn't pair a phone (and is spent trying)
    assert (await _redeem(client, ticket, device_id=PHONE_ID, kind="mobile")).status == 404
    assert (await _redeem(client, ticket)).status == 404

    late = (await (await _ticket(client, secret, {"kind": "tv"})).json())["ticket"]
    freezer.tick(timedelta(minutes=6))
    assert (await _redeem(client, late)).status == 404
    assert (await _redeem(client, "x" * 43)).status == 404


async def test_only_a_paired_tv_asks_for_one(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer: FrozenDateTimeFactory
) -> None:
    _, client, secret = await _paired_tv(hass, hass_client_no_auth)
    assert (await _ticket(client, None, {"kind": "tv"})).status == 401
    assert (await _ticket(client, "wrong", {"kind": "tv"})).status == 401
    assert (await _ticket(client, secret, {"kind": "fridge"})).status == 400

    # Past the wait between two pairings from one address
    freezer.tick(timedelta(seconds=11))
    phone_secret = await _pair(hass, client, device_id=PHONE_ID, kind="mobile", name="Phone")
    await hass.async_block_till_done()
    assert (await _ticket(client, phone_secret, {"kind": "tv"}, device_id=PHONE_ID)).status == 403


async def test_a_phone_ticket_is_for_an_adult_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _paired_tv(hass, hass_client_no_auth)
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "roles": {"person.alex": "adult", "person.sam": "kid"}}
    )
    await hass.async_block_till_done()

    assert (await _ticket(client, secret, {"kind": "mobile", "person": "person.sam"})).status == 403
    assert (await _ticket(client, secret, {"kind": "mobile"})).status == 403
    ticket = (await (await _ticket(client, secret, {"kind": "mobile", "person": "person.alex"})).json())["ticket"]
    body = await (await _redeem(client, ticket, device_id=PHONE_ID, kind="mobile", name="Alex's phone")).json()
    assert body["person"] == "person.alex" and body["role"] == "adult"


async def test_a_ticket_from_a_removed_tv_pairs_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _paired_tv(hass, hass_client_no_auth)
    ticket = (await (await _ticket(client, secret, {"kind": "tv"})).json())["ticket"]
    await entry.runtime_data.async_remove_device(TV_ID)
    await hass.async_block_till_done()
    assert (await _redeem(client, ticket)).status == 404


async def test_pairing_status_still_answers(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    # The redeem address sits beside /api/hearth/pair/<id>: a code pairing still works, and posts are fine
    _, client, secret = await _paired_tv(hass, hass_client_no_auth)
    assert (await _post(client, secret, body=STATUS)).status == 200
