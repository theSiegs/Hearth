"""Asking for more time: a device asks, an adult answers once, the device hears it."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.asks import EVENT_MORE_TIME_ANSWERED, EVENT_MORE_TIME_REQUESTED
from test_init import TV_ID, _post
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option


async def _ask(client, secret, **body):
    return await client.post(f"/api/hearth/device/{TV_ID}/ask", json=body, headers={"X-Hearth-Secret": secret})


async def test_a_kid_asks_and_the_first_adult_answers(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    phone = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    await _option(hass, "new_apps", {"entities": [], "notify": "notify.mobile_app_alex_phone"})
    asked = async_capture_events(hass, EVENT_MORE_TIME_REQUESTED)
    answered = async_capture_events(hass, EVENT_MORE_TIME_ANSWERED)

    response = await _ask(client, secret, minutes=30, profile_id="user:10", note="Finishing a level")
    assert response.status == 200, await response.text()
    request = (await response.json())["request"]
    assert request["status"] == "pending" and request["asked_minutes"] == 30
    await hass.async_block_till_done()
    assert asked[0].data["person"] == "person.sam" and asked[0].data["note"] == "Finishing a level"
    buttons = [a["title"] for a in phone[0].data["data"]["actions"]]
    assert buttons == ["+30 min", "+45 min", "Not now"]

    # One open request per person
    again = await _ask(client, secret, minutes=15, profile_id="user:10")
    assert again.status == 409 and (await again.json())["request"]["id"] == request["id"]

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    approvals = (await ws.receive_json())["result"]["approvals"]
    assert [(a["type"], a["id"], a["minutes"]) for a in approvals] == [("more_time", request["id"], 30)]

    # The adult gives 45, not the 30 asked
    await ws.send_json({"id": 2, "type": "hearth/approvals/answer", "request_id": request["id"], "minutes": 45})
    result = await ws.receive_json()
    assert result["success"], result
    assert result["result"]["status"] == "approved" and result["result"]["minutes"] == 45
    await hass.async_block_till_done()
    assert answered[0].data["minutes"] == 45
    assert hass.states.get("sensor.hearth_sam_screen_time_today") is not None

    # Single use: a second answer (a phone button pressed late) is refused
    await ws.send_json({"id": 3, "type": "hearth/approvals/answer", "request_id": request["id"], "deny": True})
    assert (await ws.receive_json())["error"]["code"] == "not_open"

    # The TV hears it with its next status
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    told = body["state"]["profiles"][KID]["request"]
    assert told["id"] == request["id"] and told["status"] == "approved" and told["minutes"] == 45


async def test_not_now_starts_a_cooldown_and_a_phone_button_answers(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    request = (await (await _ask(client, secret, minutes=15, profile_id="user:10")).json())["request"]

    hass.bus.async_fire("mobile_app_notification_action", {"action": f"HEARTH_MORE|{request['id']}|0"})
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["request"]["status"] == "denied"

    cooled = await _ask(client, secret, minutes=15, profile_id="user:10")
    assert cooled.status == 429 and (await cooled.json())["retry_in"] > 0
    freezer.tick(timedelta(minutes=11))
    assert (await _ask(client, secret, minutes=15, profile_id="user:10")).status == 200


async def test_a_request_nobody_answers_expires(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert (await _ask(client, secret, minutes=20, profile_id="user:10")).status == 400
    request = (await (await _ask(client, secret, minutes=60, profile_id="user:10")).json())["request"]
    freezer.tick(timedelta(minutes=31))
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    told = body["state"]["profiles"][KID]["request"]
    assert told["id"] == request["id"] and told["status"] == "expired"
    # An expired one doesn't block a new one
    assert (await _ask(client, secret, minutes=15, profile_id="user:10")).status == 200
