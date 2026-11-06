"""Push to phones (H-6): a contentless "changed" ping over ntfy when a phone's state document changes.

Every publish here goes to aioclient_mock: nothing leaves the test.
"""

from datetime import timedelta
import re

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator, WebSocketGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.push import clean_server

from test_init import NONCE, PHONE_ID, TV_ID, _pair, _post, _set_up

SERVER = "https://push.example"
TOPIC = re.compile(r"^[A-Za-z0-9_-]{32}$")
PHONE_STATUS = {"screen": "on", "app": "Example Game", "app_package": "com.example.game"}


async def _pair_phone(hass: HomeAssistant, client) -> tuple[str, dict]:
    """Pairs Sam's phone as an administrator would; returns its secret and the whole approved answer."""
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    response = await client.post(
        "/api/hearth/pair", json={"device_id": PHONE_ID, "kind": "mobile", "name": "Sam's phone", "nonce": NONCE}
    )
    pairing_id = (await response.json())["pairing_id"]
    await hass.async_block_till_done()
    flow = hass.config_entries.flow.async_progress_by_handler(DOMAIN)[0]
    result = await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": "person.sam"})
    assert result["reason"] == "paired"
    await hass.async_block_till_done()
    answer = await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json()
    assert answer["status"] == "approved"
    return answer["secret"], answer


async def _set_server(hass: HomeAssistant, entry, server: str | None) -> None:
    hass.config_entries.async_update_entry(entry, options={**entry.options, "push_server": server})
    await hass.async_block_till_done()


async def _settle(hass: HomeAssistant, freezer, seconds: float = 6) -> None:
    """Lets the debounce (and any wait between pings) run out."""
    freezer.tick(timedelta(seconds=seconds))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


async def _pause_sam(hass: HomeAssistant, minutes: int = 30) -> None:
    await hass.services.async_call(DOMAIN, "pause", {"minutes": minutes, "people": ["person.sam"]}, blocking=True)


def test_the_server_address_is_checked() -> None:
    assert clean_server(None) is None
    assert clean_server("  ") is None
    assert clean_server("https://ntfy.example.com/") == "https://ntfy.example.com"
    assert clean_server("http://192.0.2.10:8080/ntfy") == "http://192.0.2.10:8080/ntfy"
    for bad in ("ntfy.example.com", "ftp://ntfy.example.com", "https://user:pw@ntfy.example.com",
                "https://ntfy.example.com/?a=1", "https://ntfy.example.com/#x", "https://", "https://a b.example"):
        with pytest.raises(Exception):
            clean_server(bad)


async def test_without_a_server_nothing_is_sent(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, aioclient_mock: AiohttpClientMocker, freezer
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret, answer = await _pair_phone(hass, client)
    assert answer["push"] is None
    body = await (await _post(client, secret, body=PHONE_STATUS, device_id=PHONE_ID)).json()
    assert body["push"] is None

    await _pause_sam(hass)
    await _settle(hass, freezer, 60)
    assert aioclient_mock.call_count == 0


async def test_a_change_pings_the_phone_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, aioclient_mock: AiohttpClientMocker, freezer
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    await _set_server(hass, entry, SERVER)
    client = await hass_client_no_auth()
    secret, answer = await _pair_phone(hass, client)
    topic = answer["push"]["topic"]
    assert answer["push"] == {"server": SERVER, "topic": topic}
    assert TOPIC.match(topic)
    aioclient_mock.post(f"{SERVER}/{topic}", text="{}")

    body = await (await _post(client, secret, body=PHONE_STATUS, device_id=PHONE_ID)).json()
    assert body["push"] == {"server": SERVER, "topic": topic}
    # What the phone was just handed isn't news
    await _settle(hass, freezer)
    assert aioclient_mock.call_count == 0

    # A pause, a bonus, a minute later: changes together are one ping
    await _pause_sam(hass)
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 15}, blocking=True
    )
    await _settle(hass, freezer)
    assert aioclient_mock.call_count == 1
    method, url, data, _headers = aioclient_mock.mock_calls[0]
    assert method == "POST"
    assert str(url) == f"{SERVER}/{topic}"
    # Nothing but "changed": no name, no number, no version
    assert data == "changed"

    # Not pinged again for the version it was pinged for
    await _settle(hass, freezer, 60)
    assert aioclient_mock.call_count == 1

    # A later change is a ping of its own
    await _settle(hass, freezer, 25)
    await _pause_sam(hass, 45)
    await _settle(hass, freezer)
    assert aioclient_mock.call_count == 2


async def test_pings_wait_out_the_gap(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, aioclient_mock: AiohttpClientMocker, freezer
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    await _set_server(hass, entry, SERVER)
    client = await hass_client_no_auth()
    secret, answer = await _pair_phone(hass, client)
    topic = answer["push"]["topic"]
    aioclient_mock.post(f"{SERVER}/{topic}", text="{}")
    await _post(client, secret, body=PHONE_STATUS, device_id=PHONE_ID)

    await _pause_sam(hass)
    await _settle(hass, freezer)
    assert aioclient_mock.call_count == 1
    await _pause_sam(hass, 45)
    await _settle(hass, freezer)
    # 6 seconds after the last ping: not yet
    assert aioclient_mock.call_count == 1
    await _settle(hass, freezer, 25)
    assert aioclient_mock.call_count == 2


async def test_a_failing_server_is_harmless(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, aioclient_mock: AiohttpClientMocker, freezer
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    await _set_server(hass, entry, SERVER)
    client = await hass_client_no_auth()
    secret, answer = await _pair_phone(hass, client)
    aioclient_mock.post(f"{SERVER}/{answer['push']['topic']}", exc=TimeoutError())
    await _post(client, secret, body=PHONE_STATUS, device_id=PHONE_ID)
    await _pause_sam(hass)
    await _settle(hass, freezer)
    assert aioclient_mock.call_count == 1
    # The phone still gets its state with its next post
    body = await (await _post(client, secret, body=PHONE_STATUS, device_id=PHONE_ID)).json()
    assert body["state"]["person"].get("pause") is not None


async def test_topics_are_the_phones_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, aioclient_mock: AiohttpClientMocker
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    await _set_server(hass, entry, SERVER)
    client = await hass_client_no_auth()
    tv_secret = await _pair(hass, client)
    # A TV isn't pinged and isn't told a topic
    body = await (await _post(client, tv_secret)).json()
    assert "push" not in body
    assert "push_topic" not in entry.data["devices"][TV_ID]

    _secret, first = await _pair_phone(hass, client)
    # Pairing again makes a new topic, as it makes a new secret
    _secret, second = await _pair_phone(hass, client)
    assert first["push"]["topic"] != second["push"]["topic"]
    assert entry.data["devices"][PHONE_ID]["push_topic"] == second["push"]["topic"]

    # A phone paired before push existed gets a topic when the household loads
    devices = {**entry.data["devices"], PHONE_ID: {k: v for k, v in entry.data["devices"][PHONE_ID].items() if k != "push_topic"}}
    hass.config_entries.async_update_entry(entry, data={**entry.data, "devices": devices})
    await hass.async_block_till_done()
    assert TOPIC.match(entry.data["devices"][PHONE_ID]["push_topic"])


async def test_set_in_the_options_and_on_hearth_s_page(
    hass: HomeAssistant, hass_ws_client: WebSocketGenerator
) -> None:
    entry = await _set_up(hass)
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "push"})
    assert result["step_id"] == "push"
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"server": "ntfy.example.com"})
    assert result["errors"] == {"server": "bad_server"}
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"server": "https://ntfy.example.com/"})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    assert entry.options["push_server"] == "https://ntfy.example.com"

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config/set", "key": "push_server", "value": "javascript:alert(1)"})
    assert not (await ws.receive_json())["success"]
    await ws.send_json({"id": 2, "type": "hearth/config/set", "key": "push_server", "value": None})
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()
    assert entry.options["push_server"] is None
    await ws.send_json({"id": 3, "type": "hearth/config"})
    assert (await ws.receive_json())["result"]["push_server"] is None
