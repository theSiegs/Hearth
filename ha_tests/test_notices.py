"""Notices on the TVs: the attention items for TVs (the chosen suggestions) in the state document of a TV that shows
them (cap "notices"), never a phone's; a new one wakes the TV's wait, an unchanged one doesn't."""

import asyncio
from datetime import timedelta
from unittest.mock import patch

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    async_capture_events,
    async_fire_time_changed,
    async_mock_service,
)
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import parent_pin
from custom_components.hearth.attention import Action, Item
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import NOTICE_ANSWER
from custom_components.hearth.hub import pin_lockout
from custom_components.hearth.notices import APPROVE_FOR
from test_attention import _household, _hub, _press
from test_init import PHONE_ID, TV_ID, _pair, _post
from test_people import _tv_status
from test_phones import _options
from test_suggest_push import KEY, TAG, _check, _video_out
from test_wait import _wait

CAPS = ["commands.play", "events", "notices"]
TV_STATUS = {**_tv_status(hearthtube_s=600, game_s=300), "caps": CAPS}
NOTICE = {
    "key": KEY,
    "tag": TAG,
    "title": "Sam's Video ran out",
    "message": "Give 30 more minutes today?",
    "urgency": "notice",
    "actions": [{"id": "0", "title": "+30 min"}, {"id": "1", "title": "+15 min"}, {"id": "2", "title": "Not today"}],
}


async def _state(client, secret: str, body=TV_STATUS, device_id: str = TV_ID) -> dict:
    response = await _post(client, secret, body=body, device_id=device_id)
    assert response.status == 200
    return (await response.json())["state"]


async def _suggested(hass: HomeAssistant, hass_client_no_auth):
    """Sam's Video is out and its suggestion was pushed (the household chose it)."""
    client, secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    await _check(hass)
    return client, secret, users, sent


async def test_a_tv_that_shows_notices_gets_the_suggestion(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    state = await _state(client, secret)
    # For every adult: no "for"; no service or data, only the buttons' numbers and titles
    assert state["notices"] == [NOTICE]
    assert "person.sam" in state["people"].values()


async def test_a_tv_without_the_cap_gets_none(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    # A TV from before caps (its kind's defaults), or one that declares caps without notices
    assert "notices" not in await _state(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))
    assert "notices" not in await _state(client, secret, body={**TV_STATUS, "caps": ["commands.play", "events"]})


async def test_a_phone_never_gets_the_adults_notices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, _secret, _users, _sent = await _suggested(hass, hass_client_no_auth)
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    phone_secret = await _pair(hass, client, PHONE_ID, "mobile", "Phone")
    # Even one that says it shows notices
    state = await _state(client, phone_secret, body={"screen": "on", "caps": ["push", "notices"]}, device_id=PHONE_ID)
    assert "notices" not in state
    assert KEY not in str(state)


async def test_a_new_notice_wakes_the_tv_and_an_unchanged_one_doesn_t(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    version = (await _state(client, secret))["version"]
    await hass.async_block_till_done()

    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=30))
    await asyncio.sleep(0.1)
    assert not held.done()
    await _check(hass)
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    assert await (await asyncio.wait_for(held, 10)).json() == {"changed": True}

    # Looked at again, the same notice: the TV isn't woken
    version = (await _state(client, secret))["version"]
    await hass.async_block_till_done()
    held = asyncio.ensure_future(_wait(client, secret, version=version, timeout=1))
    await asyncio.sleep(0.1)
    await _check(hass)
    _hub(hass).waits.changed()
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=2))
    assert await (await asyncio.wait_for(held, 10)).json() == {"changed": False}


async def test_a_cleared_notice_goes_from_the_tv(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, _sent = await _suggested(hass, hass_client_no_auth)
    assert (await _state(client, secret))["notices"] == [NOTICE]
    # "Not today" from an adult's phone: the suggestion goes, and with it the TV's notice
    _press(hass, f"HEARTH_ACT|{KEY}|2", users["alex"])
    await hass.async_block_till_done()
    await _check(hass)
    assert (await _state(client, secret))["notices"] == []


# A press on the TV (POST /notice)

PIN = "4826"
WRONG = "1111"
BONUS = "number.hearth_sam_video_bonus_today"


def _notice(client, secret: str | None, body: dict, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return client.post(f"/api/hearth/device/{device_id}/notice", json=body, headers=headers)


async def _on_tv(hass: HomeAssistant, hass_client_no_auth):
    """Sam's Video suggestion is on the TV (which shows notices); Alex's Parent PIN is set."""
    client, secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(
        hass,
        suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}],
        parent_pins={"person.alex": parent_pin.make(PIN)},
    )
    await _video_out(hass)
    await _check(hass)
    assert (await _state(client, secret))["notices"] == [NOTICE]
    for phone in sent.values():
        phone.clear()
    return client, secret, users, sent


def _answers(hass: HomeAssistant) -> list[dict]:
    return _hub(hass).household.history.of(kinds=(NOTICE_ANSWER,))


async def test_a_parent_pin_runs_the_button_as_that_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, _sent = await _on_tv(hass, hass_client_no_auth)
    used = async_capture_events(hass, parent_pin.EVENT_PARENT_PIN_USED)
    response = await _notice(client, secret, {"key": KEY, "action": 0, "pin": PIN})
    assert response.status == 200
    assert await response.json() == {"ok": True, "done": True}
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "30"
    assert [e.data for e in used] == [{"device_id": TV_ID, "person": "person.alex"}]
    [answer] = _answers(hass)
    assert {k: answer.get(k) for k in ("person", "key", "action", "device", "via", "by")} == {
        "person": "person.sam", "key": KEY, "action": 0, "device": TV_ID, "via": "pin", "by": "person.alex"
    }
    # The suggestion goes, and with it the notice
    await _check(hass)
    assert (await _state(client, secret))["notices"] == []
    assert (await _notice(client, secret, {"key": KEY, "action": 0, "pin": PIN})).status == 404


async def test_the_pin_s_adult_is_their_home_assistant_user_or_the_household(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, _sent = await _on_tv(hass, hass_client_no_auth)
    ran = async_mock_service(hass, DOMAIN, "give_more_test")
    # Robin is an adult with a PIN but no Home Assistant user
    hass.states.async_set("person.robin", "home", {"friendly_name": "Robin"})
    await _options(hass, parent_pins={"person.alex": parent_pin.make(PIN), "person.robin": parent_pin.make("7351")})
    _hub(hass).attention.notify(
        Item(
            "hearth_test_notice",
            "Give Sam 15 more?",
            actions=(Action("give", "+15 min", "hearth.give_more_test", {"minutes": 15}),),
            about={"person": "person.sam"},
            tv=True,
        )
    )
    await _state(client, secret)
    assert (await _notice(client, secret, {"key": "hearth_test_notice", "action": 0, "pin": PIN})).status == 200
    assert (await _notice(client, secret, {"key": "hearth_test_notice", "action": 0, "pin": "7351"})).status == 200
    await hass.async_block_till_done()
    assert [c.context.user_id for c in ran] == [users["alex"].id, None]
    assert [(a["by"], a.get("user")) for a in _answers(hass)] == [("person.alex", None), ("person.robin", None)]


async def test_wrong_pins_share_the_device_s_lockout(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _on_tv(hass, hass_client_no_auth)
    for n in range(parent_pin.FREE_TRIES):
        response = await _notice(client, secret, {"key": KEY, "action": 0, "pin": WRONG})
        assert response.status == 403
        answer = await response.json()
        assert answer["error"] == "wrong_pin"
        # The wrong one that starts a lockout says how long
        assert ("retry_after" in answer) == (n == parent_pin.FREE_TRIES - 1)
    # Locked out: the right PIN too, here and at verify_pin
    response = await _notice(client, secret, {"key": KEY, "action": 0, "pin": PIN})
    assert response.status == 403
    assert 0 < (await response.json())["retry_after"] <= 31
    response = await client.post(f"/api/hearth/device/{TV_ID}/verify_pin", json={"pin": PIN}, headers={"X-Hearth-Secret": secret})
    assert response.status == 429
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "0"
    assert not _answers(hass)
    # Past the presses a minute allows
    response = await _notice(client, secret, {"key": KEY, "action": 0, "approval": "phone"})
    assert response.status == 429
    assert (await response.json())["error"] == "too_many"


async def test_a_gone_notice_a_bad_request_and_no_secret(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, sent = await _on_tv(hass, hass_client_no_auth)
    assert (await _notice(client, None, {"key": KEY, "action": 0, "pin": PIN})).status == 401
    assert (await _notice(client, "not-the-secret", {"key": KEY, "action": 0, "pin": PIN})).status == 401
    with patch("custom_components.hearth.api.is_local", return_value=False):
        response = await _notice(client, secret, {"key": KEY, "action": 0, "pin": PIN})
        assert response.status == 403 and (await response.json())["error"] == "not_local"
    response = await _notice(client, secret, {"key": "suggest:person.sam:more:games", "action": 0, "pin": WRONG})
    assert response.status == 404 and (await response.json()) == {"error": "gone"}
    for bad in (
        {"key": KEY, "action": 0},
        {"key": KEY, "action": 0, "pin": PIN, "approval": "phone"},
        {"key": KEY, "action": "0", "pin": PIN},
        {"key": KEY, "action": True, "pin": PIN},
        {"key": KEY, "action": 3, "pin": PIN},
        {"key": KEY, "action": 0, "approval": "sms"},
    ):
        response = await _notice(client, secret, bad)
        assert response.status == 400 and (await response.json()) == {"error": "bad_request"}, bad
        # A secret's presses past the rate are refused before anything else
        _hub(hass).state(TV_ID).notice_posts.clear()
    # None of it counted as a wrong PIN, ran anything or asked a phone
    assert pin_lockout(hass, TV_ID).failures == 0
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "0"
    assert not any(sent.values())


async def test_only_a_tv_that_shows_notices_can_press(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _on_tv(hass, hass_client_no_auth)
    # The TV now says it doesn't show notices: they're gone for it
    await _state(client, secret, body={**TV_STATUS, "caps": ["commands.play", "events"]})
    assert (await _notice(client, secret, {"key": KEY, "action": 0, "pin": PIN})).status == 404
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()
    phone_secret = await _pair(hass, client, PHONE_ID, "mobile", "Phone")
    await _state(client, phone_secret, body={"screen": "on", "caps": ["notices"]}, device_id=PHONE_ID)
    response = await _notice(client, phone_secret, {"key": KEY, "action": 0, "pin": PIN}, device_id=PHONE_ID)
    assert response.status == 404
    assert hass.states.get(BONUS).state == "0"


async def test_only_hearth_services_run_from_a_tv(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _on_tv(hass, hass_client_no_auth)
    script = async_mock_service(hass, "script", "give_more")
    ran = async_mock_service(hass, DOMAIN, "give_more_test")
    _hub(hass).attention.notify(
        Item(
            "hearth_mixed",
            "Mixed",
            actions=(Action("s", "Script", "script.give_more"), Action("h", "+15", "hearth.give_more_test")),
            tv=True,
        )
    )
    notices = (await _state(client, secret))["notices"]
    # The TV is shown only the button a press can run, by its own number
    assert next(n for n in notices if n["key"] == "hearth_mixed")["actions"] == [{"id": "1", "title": "+15"}]
    response = await _notice(client, secret, {"key": "hearth_mixed", "action": 0, "pin": PIN})
    assert response.status == 400
    response = await _notice(client, secret, {"key": "hearth_mixed", "action": 0, "approval": "phone"})
    assert response.status == 400
    await hass.async_block_till_done()
    assert not script and not ran
    assert pin_lockout(hass, TV_ID).failures == 0
    assert (await _notice(client, secret, {"key": "hearth_mixed", "action": 1, "pin": PIN})).status == 200
    await hass.async_block_till_done()
    assert len(ran) == 1 and not script


APPROVE_TAG = f"hearth_approve:{KEY}"


def _approvals(sent, phone: str = "alex_phone") -> list:
    return [c for c in sent[phone] if c.data.get("message") != "clear_notification" and c.data["data"]["tag"] == APPROVE_TAG]


def _approval_cleared(sent, phone: str = "alex_phone") -> bool:
    return any(c.data == {"message": "clear_notification", "data": {"tag": APPROVE_TAG}} for c in sent[phone])


async def test_a_parent_s_phone_approves_the_press(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, sent = await _on_tv(hass, hass_client_no_auth)
    response = await _notice(client, secret, {"key": KEY, "action": 0, "approval": "phone"})
    assert response.status == 200
    assert await response.json() == {"ok": True, "pending": "phone"}
    await hass.async_block_till_done()
    # Nothing ran yet: the TV is trusted with nothing
    assert hass.states.get(BONUS).state == "0"
    [push] = _approvals(sent)
    assert push.data["title"] == "Approve +30 min for Sam?"
    assert push.data["message"] == "Sam's Video ran out. Asked on Kitchen."
    [run, dont] = push.data["data"]["actions"]
    assert run["title"] == "+30 min" and dont["title"] == "Don't allow"
    assert run["action"].startswith(f"HEARTH_ACT|approve:{KEY}:0:") and run["action"].endswith("|0")
    # Every adult's phone, never the kid's or the bell
    assert _approvals(sent, "jordan_iphone") and not sent["sam_phone"]
    assert APPROVE_TAG not in persistent_notification._async_get_or_create_notifications(hass)

    # A kid firing the same action: not an adult, nothing runs
    _press(hass, run["action"], users["sam"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "0"

    # Alex's tap runs it as Alex, logs who answered, and takes the approval off the phones
    _press(hass, run["action"], users["alex"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "30"
    [answer] = _answers(hass)
    assert (answer["via"], answer["by"], answer["person"], answer["action"]) == ("phone", "person.alex", "person.sam", 0)
    assert _approval_cleared(sent)
    # Once: a second tap does nothing
    _press(hass, run["action"], users["jordan"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "30"


async def test_don_t_allow_and_a_notice_gone_clear_the_approval(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, sent = await _on_tv(hass, hass_client_no_auth)
    await _notice(client, secret, {"key": KEY, "action": 1, "approval": "phone"})
    await hass.async_block_till_done()
    [push] = _approvals(sent)
    assert push.data["title"] == "Approve +15 min for Sam?"
    _press(hass, push.data["data"]["actions"][1]["action"], users["alex"])
    await hass.async_block_till_done()
    assert _approval_cleared(sent)
    assert hass.states.get(BONUS).state == "0"
    assert not _answers(hass)
    assert not [i for i in _hub(hass).attention.items() if i.key.startswith("approve:")]

    # Asked again, then the suggestion is put off elsewhere: its approval goes with it
    sent["alex_phone"].clear()
    await _notice(client, secret, {"key": KEY, "action": 0, "approval": "phone"})
    await hass.async_block_till_done()
    [push] = _approvals(sent)
    await hass.services.async_call(DOMAIN, "dismiss_suggestion", {"person": "person.sam", "key": "more:video"}, blocking=True)
    await _check(hass)
    assert _approval_cleared(sent)
    _press(hass, push.data["data"]["actions"][0]["action"], users["alex"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "0"


async def test_an_approval_expires_after_ten_minutes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, sent = await _on_tv(hass, hass_client_no_auth)
    await _notice(client, secret, {"key": KEY, "action": 0, "approval": "phone"})
    await hass.async_block_till_done()
    [push] = _approvals(sent)
    async_fire_time_changed(hass, dt_util.utcnow() + APPROVE_FOR + timedelta(seconds=1))
    await hass.async_block_till_done()
    assert _approval_cleared(sent)
    _press(hass, push.data["data"]["actions"][0]["action"], users["alex"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS).state == "0"
    # The notice itself stays
    assert [n["key"] for n in (await _state(client, secret))["notices"]] == [KEY]
