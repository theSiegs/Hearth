"""hearth.play_on_tv: a one-shot command queued for a TV and handed over in its state document."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import device_registry as dr
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.commands import what_to_play
from custom_components.hearth.const import DOMAIN

from test_init import PHONE_ID, STATUS, TV_ID, _pair, _post, _set_up


async def _play(hass: HomeAssistant, **data):
    return await hass.services.async_call(DOMAIN, "play_on_tv", data, blocking=True, return_response=True)


def test_what_is_told_apart() -> None:
    assert what_to_play("aBcDeFgHiJk") == {"video_id": "aBcDeFgHiJk"}
    assert what_to_play("https://youtu.be/aBcDeFgHiJk") == {"video_id": "aBcDeFgHiJk"}
    assert what_to_play("https://www.youtube.com/watch?v=aBcDeFgHiJk&t=30") == {"video_id": "aBcDeFgHiJk"}
    assert what_to_play("https://example.com/show?id=1") == {"url": "https://example.com/show?id=1"}
    # Another site's link with a v= in it is a link, not a YouTube video
    assert what_to_play("https://example.com/watch?v=aBcDeFgHiJk") == {"url": "https://example.com/watch?v=aBcDeFgHiJk"}
    assert what_to_play("com.example.app") == {"package": "com.example.app"}
    for bad in ("", "hello world", "javascript:alert(1)", "file:///sdcard/x", "intent://x", "nodots", "https://a\nb"):
        assert what_to_play(bad) is None


async def test_a_play_reaches_the_tv_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    assert (await _post(client, secret)).status == 200
    done = async_capture_events(hass, "hearth_command_done")

    answer = await _play(hass, device_id=TV_ID, what="https://youtu.be/aBcDeFgHiJk")
    assert answer["device_id"] == TV_ID

    body = await (await _post(client, secret)).json()
    commands = body["state"]["commands"]
    assert len(commands) == 1
    command = commands[0]
    assert command["id"] == answer["id"]
    assert command["type"] == "play"
    assert command["video_id"] == "aBcDeFgHiJk"
    assert "url" not in command and "package" not in command
    assert command["profile_id"] is None
    assert command["expires"] == answer["expires"]
    # Handed over again until the TV says it's done (an answer may have been lost)
    again = await (await _post(client, secret)).json()
    assert again["state"]["commands"] == commands

    status = {**STATUS, "commands_done": [{"id": command["id"], "result": "ok"}]}
    after = await (await _post(client, secret, body=status)).json()
    assert after["state"]["commands"] == []
    assert after["state"]["version"] != again["state"]["version"]
    await hass.async_block_till_done()
    assert [e.data for e in done] == [
        {"device_id": TV_ID, "id": command["id"], "type": "play", "result": "ok", "error": None}
    ]
    # Said twice, it's told once
    await _post(client, secret, body=status)
    await hass.async_block_till_done()
    assert len(done) == 1


async def test_a_tv_by_its_home_assistant_device(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    await _post(client, secret)
    device = dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id)

    await _play(hass, device_id=device.id, what="com.example.app")
    body = await (await _post(client, secret)).json()
    assert body["state"]["commands"][0]["package"] == "com.example.app"

    # A newer play replaces one still waiting
    done = async_capture_events(hass, "hearth_command_done")
    first = body["state"]["commands"][0]["id"]
    await _play(hass, device_id=[device.id], what="https://example.com/show")
    body = await (await _post(client, secret)).json()
    assert [c["url"] for c in body["state"]["commands"]] == ["https://example.com/show"]
    await hass.async_block_till_done()
    assert done[0].data["id"] == first and done[0].data["result"] == "replaced"

    # The TV couldn't: a failure it reports is told with its reason
    second = body["state"]["commands"][0]["id"]
    await _post(client, secret, body={**STATUS, "commands_done": [{"id": second, "result": "refused", "error": "held"}]})
    await hass.async_block_till_done()
    assert done[-1].data["result"] == "refused" and done[-1].data["error"] == "held"


async def test_an_unclaimed_play_expires(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    await _post(client, secret)
    done = async_capture_events(hass, "hearth_command_done")
    await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk")

    freezer.tick(timedelta(minutes=4))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert [e.data["result"] for e in done] == ["expired"]
    body = await (await _post(client, secret)).json()
    assert body["state"]["commands"] == []


async def test_in_a_person_s_profile(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    hass.config_entries.async_update_entry(
        entry,
        options={"profiles": {"user:10": "person.sam", "user:0:alex": "person.alex", "user:11": "person.alex"}},
    )
    await hass.async_block_till_done()
    alex_on = {**STATUS, "profile_id": "user:0:alex"}
    await _post(client, secret, body=alex_on)

    await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk", profile="person.sam")
    body = await (await _post(client, secret, body=alex_on)).json()
    assert body["state"]["commands"][0]["profile_id"] == "user:10"
    # Alex has two profiles; the one this TV has seen is meant
    await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk", profile="person.alex")
    body = await (await _post(client, secret, body=alex_on)).json()
    assert body["state"]["commands"][0]["profile_id"] == "user:0:alex"
    await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk", profile="user:12")
    body = await (await _post(client, secret, body=alex_on)).json()
    assert body["state"]["commands"][0]["profile_id"] == "user:12"

    with pytest.raises(ServiceValidationError):
        await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk", profile="person.nobody")


async def test_what_can_t_be_played(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    # One address may ask to pair only every 10 seconds
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    phone_secret = await _pair(hass, client, PHONE_ID, "mobile", "Phone")
    await _post(client, phone_secret, body={"screen": "on"}, device_id=PHONE_ID)

    # Not yet heard from: not connected
    with pytest.raises(ServiceValidationError, match="connected"):
        await _play(hass, device_id=TV_ID, what="aBcDeFgHiJk")
    await _post(client, secret)
    with pytest.raises(ServiceValidationError, match="TV"):
        await _play(hass, device_id=PHONE_ID, what="aBcDeFgHiJk")
    with pytest.raises(ServiceValidationError):
        await _play(hass, device_id="tv-unknown-device", what="aBcDeFgHiJk")
    with pytest.raises(ServiceValidationError):
        await _play(hass, device_id=TV_ID, what="javascript:alert(1)")
    # A phone's state has no commands
    body = await (await _post(client, phone_secret, body={"screen": "on"}, device_id=PHONE_ID)).json()
    assert "commands" not in body["state"]
