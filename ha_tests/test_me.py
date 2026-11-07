"""A kid's own Home Assistant user: hearth/me (their own document) and hearth/ask, and nothing else of Hearth's."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.asks import EVENT_MORE_TIME_REQUESTED
from test_parent_pin import _adults
from test_people import _household_with_sam
from test_phones import _options


async def _sam_signs_in(hass: HomeAssistant, hass_client_no_auth, user) -> None:
    """Sam (a kid with limits) has their own Home Assistant user, which isn't an administrator; Riley is another kid."""
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam", "user_id": user.id})
    hass.states.async_set("person.riley", "home", {"friendly_name": "Riley", "user_id": "someone-else"})
    await _options(hass, roles={"person.sam": "kid", "person.riley": "kid"})
    user.groups = []


async def test_a_kid_reads_only_their_own_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    await _sam_signs_in(hass, hass_client_no_auth, hass_admin_user)
    ws = await hass_ws_client(hass)

    await ws.send_json({"id": 1, "type": "hearth/me"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    me = answer["result"]
    assert set(me) == {"person", "media_rooms", "version", "contract"}
    assert me["contract"] == 2
    assert me["person"]["person"] == "person.sam" and me["person"]["kind"] == "kid" and me["person"]["kind_set"]
    # The same document a paired phone of Sam's would get
    hub = hass.config_entries.async_entries("hearth")[0].runtime_data
    assert me == hub.household.own_document("person.sam")

    # No way to name someone else
    await ws.send_json({"id": 2, "type": "hearth/me", "person": "person.riley"})
    assert (await ws.receive_json())["error"]["code"] == "invalid_format"
    # Not the household, not the page's settings, not an answer, not a service
    await ws.send_json({"id": 3, "type": "hearth/household"})
    assert (await ws.receive_json())["error"]["code"] == "unauthorized"
    await ws.send_json({"id": 4, "type": "hearth/household/subscribe"})
    assert (await ws.receive_json())["error"]["code"] == "unauthorized"
    await ws.send_json({"id": 5, "type": "hearth/config"})
    assert (await ws.receive_json())["error"]["code"] == "unauthorized"
    await ws.send_json({"id": 6, "type": "hearth/approvals/answer", "request_id": "x", "minutes": 15})
    assert (await ws.receive_json())["error"]["code"] == "unauthorized"
    await ws.send_json(
        {
            "id": 7,
            "type": "call_service",
            "domain": "hearth",
            "service": "add_bonus",
            "service_data": {"person": "person.sam", "group": "all", "minutes": 60},
        }
    )
    refused = await ws.receive_json()
    assert not refused["success"] and "Unauthorized" in refused["error"]["message"]


async def test_a_kid_hears_their_document_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, freezer
) -> None:
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    await _sam_signs_in(hass, hass_client_no_auth, hass_admin_user)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/me/subscribe"})
    assert (await ws.receive_json())["success"]
    first = (await ws.receive_json())["event"]
    assert first["person"]["person"] == "person.sam" and "request" not in first["person"]

    await ws.send_json({"id": 2, "type": "hearth/ask", "minutes": 15})
    assert (await ws.receive_json())["result"]["ok"]
    freezer.tick(timedelta(seconds=3))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    second = (await ws.receive_json())["event"]
    assert second["person"]["request"]["status"] == "pending"


async def test_a_kid_asks_for_more_time_as_their_device_would(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, freezer
) -> None:
    await _sam_signs_in(hass, hass_client_no_auth, hass_admin_user)
    phone = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    await _options(hass, ask_notify="notify.mobile_app_alex_phone")
    asked = async_capture_events(hass, EVENT_MORE_TIME_REQUESTED)
    ws = await hass_ws_client(hass)

    await ws.send_json({"id": 1, "type": "hearth/ask", "minutes": 20})
    assert (await ws.receive_json())["error"]["code"] == "bad_request"
    await ws.send_json({"id": 2, "type": "hearth/ask", "minutes": 30, "group": "video", "note": "One more episode"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    request = answer["result"]["request"]
    assert answer["result"]["ok"] and request["status"] == "pending" and request["asked_minutes"] == 30
    assert request["group"] == "video"
    await hass.async_block_till_done()
    # Shown as asked from their Home Assistant user, not a device
    assert asked[0].data["person"] == "person.sam" and asked[0].data["via"] == "home_assistant"
    assert asked[0].data["user_id"] == hass_admin_user.id and asked[0].data["device_id"] == ""
    assert "in the Home Assistant app" in phone[0].data["message"]

    # One open at a time, as from a device
    await ws.send_json({"id": 3, "type": "hearth/ask", "minutes": 15})
    again = (await ws.receive_json())["result"]
    assert again == {"ok": False, "error": "already_open", "request": request}

    # "Not now" from an adult: the cooldown holds for Sam's own user too
    hub = hass.config_entries.async_entries("hearth")[0].runtime_data
    hub.asks.answer(request["id"], None, "an-adult")
    await ws.send_json({"id": 4, "type": "hearth/ask", "minutes": 15})
    cooled = (await ws.receive_json())["result"]
    assert cooled["ok"] is False and cooled["error"] == "cooldown" and cooled["retry_in"] > 0
    freezer.tick(timedelta(minutes=11))

    # Their document says what came of it
    await ws.send_json({"id": 5, "type": "hearth/me"})
    assert (await ws.receive_json())["result"]["person"]["request"]["status"] == "denied"
    await ws.send_json({"id": 6, "type": "hearth/ask", "minutes": 15, "app": "com.example.game"})
    assert (await ws.receive_json())["result"]["ok"]


async def test_asking_too_often_is_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    await _sam_signs_in(hass, hass_client_no_auth, hass_admin_user)
    ws = await hass_ws_client(hass)
    codes = []
    for i in range(1, 13):
        await ws.send_json({"id": i, "type": "hearth/ask", "minutes": 15})
        answer = await ws.receive_json()
        codes.append(answer["error"]["code"] if not answer["success"] else answer["result"].get("error", "ok"))
    assert codes[0] == "ok" and codes[1] == "already_open" and codes[-1] == "too_often"


async def test_a_user_with_no_person_is_told_so(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    # An administrator with no person of their own
    await _household_with_sam(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    for i, kind in enumerate(("hearth/me", "hearth/me/subscribe", "hearth/ask"), start=1):
        await ws.send_json({"id": i, "type": kind})
        assert (await ws.receive_json())["error"]["code"] == "not_found"


async def test_an_adult_reads_their_own_document_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": hass_admin_user.id})
    await _adults(hass, "person.alex")
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/me"})
    me = (await ws.receive_json())["result"]
    assert me["person"]["person"] == "person.alex" and me["person"]["kind"] == "adult"
