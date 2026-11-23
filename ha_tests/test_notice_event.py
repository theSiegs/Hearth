"""The hearth_notice event (docs/contracts/notice-event.md): every attention item shown, updated or cleared, announced
read-only (words, audience, buttons' labels, never a service or its data); and hearth.notify, a message on phones and
TVs through the same items."""

from datetime import timedelta
import json
import logging

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import adult_offer
from custom_components.hearth.attention import EVENT_NOTICE, Action, Attention, Item
from custom_components.hearth.const import DOMAIN
from test_adult_offer import _household as _offer_household, _read, _ws_as
from test_asks import _ask
from test_attention import _household, _hub
from test_init import TV_ID
from test_notices import _state, _tv
from test_phones import _options

ROLES = {"person.alex": "adult", "person.jordan": "adult", "person.sam": "kid"}


def _events(events, **match) -> list[dict]:
    return [e.data for e in events if all(e.data.get(k) == v for k, v in match.items())]


def _pushes(sent) -> list:
    return [c for c in sent if c.data.get("message") != "clear_notification"]


async def test_a_kid_s_ask_is_announced_with_its_phone_words(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, sent = await _household(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT_NOTICE)
    response = await _ask(client, secret, minutes=30, profile_id="user:10", note="Finishing a level")
    assert response.status == 200, await response.text()
    request = (await response.json())["request"]
    await hass.async_block_till_done()

    [event] = _events(events, kind="ask")
    [push] = _pushes(sent["alex_phone"])
    assert event["v"] == 1 and event["change"] == "shown"
    assert event["key"] == event["tag"] == f"hearth_more_{request['id']}"
    # The same words its phone notification shows
    assert event["title"] == push.data["title"] and event["text"] == push.data["message"]
    assert event["urgency"] == "notice"
    assert event["audience"] == {"kind": "adults", "people": ["person.alex", "person.jordan"]}
    assert event["about"]["person"] == "person.sam"
    # Labels only, numbered as the phone's buttons are
    assert [a["label"] for a in event["actions"]] == [b["title"] for b in push.data["data"]["actions"]]
    assert all(set(a) == {"n", "label"} for a in event["actions"])
    assert [a["n"] for a in event["actions"]] == list(range(len(event["actions"])))
    assert event["link"] == f"/hearth?ask={request['id']}"
    assert event["channels"] == ["phone"]
    assert event["expires"] and event["sent"]


async def test_an_offer_s_buttons_are_labels_never_their_service(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, _sent = await _offer_household(hass)
    events = async_capture_events(hass, EVENT_NOTICE)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)

    [event] = _events(events, kind="adult_offer")
    assert event["change"] == "shown"
    assert event["key"] == adult_offer.offer_key("person.jordan")
    assert event["title"] == "Make Jordan an adult?"
    assert event["audience"] == {"kind": "admins", "people": ["person.alex"]}
    assert event["actions"] == [{"n": 0, "label": "Make adult"}, {"n": 1, "label": "Not now"}]
    assert event["link"] == "/hearth"
    # Nothing a listener could run: no service, no data
    dumped = json.dumps(event)
    assert "adult_offer_answer" not in dumped and f"{DOMAIN}." not in dumped and '"answer"' not in dumped


async def test_an_outside_change_s_block_button_carries_no_data(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT_NOTICE)
    _hub(hass).attention.notify(
        Item(
            "outside_app_fl_sam_com.example.game",
            "A parent unblocked Example Game in Family Link.",
            title="Sam: Example Game unblocked",
            urgency="notice",
            actions=(
                Action("block", "Block again", "hearth.block_app", {"people": ["person.sam"], "apps": ["com.example.game"]}),
                Action("not_now", "Not now", dismiss=True),
            ),
            about={"person": "person.sam", "audit": {"secret": "x"}},
        )
    )
    await hass.async_block_till_done()
    [event] = events
    assert event.data["kind"] == "outside_change"
    assert event.data["actions"] == [{"n": 0, "label": "Block again"}, {"n": 1, "label": "Not now"}]
    # Only who and which group it's about
    assert event.data["about"] == {"person": "person.sam"}
    dumped = json.dumps(event.data)
    assert "block_app" not in dumped and '"apps"' not in dumped and "audit" not in dumped and "secret" not in dumped


async def test_cleared_and_replaced_are_announced(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT_NOTICE)
    attention = _hub(hass).attention
    attention.notify(Item("hearth_place_person.sam_1", "Sam got to school.", title="Sam", tag="hearth_place_person.sam"))
    # Same key: new words
    attention.notify(Item("hearth_place_person.sam_1", "Sam is at school.", title="Sam", tag="hearth_place_person.sam"))
    # Same tag, another key: the old one is gone, the new one takes its place
    attention.notify(Item("hearth_place_person.sam_2", "Sam left school.", title="Sam", tag="hearth_place_person.sam"))
    attention.clear("hearth_place_person.sam")
    # Nothing kept by that key: nothing announced
    attention.clear("hearth_nothing_here")
    await hass.async_block_till_done()
    assert [(e.data["change"], e.data["key"]) for e in events] == [
        ("shown", "hearth_place_person.sam_1"),
        ("updated", "hearth_place_person.sam_1"),
        ("cleared", "hearth_place_person.sam_1"),
        ("updated", "hearth_place_person.sam_2"),
        ("cleared", "hearth_place_person.sam_2"),
    ]
    assert events[-1].data["text"] == "Sam left school." and events[-1].data["kind"] == "place"


async def test_a_failing_announcement_never_stops_delivery(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch, caplog
) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)

    def broken(self, change, item):
        raise RuntimeError("listener trouble")

    monkeypatch.setattr(Attention, "notice_event", broken)
    attention = _hub(hass).attention
    with caplog.at_level(logging.ERROR):
        attention.notify(Item("hearth_check_tv_accessibility", "The TV needs a look.", title="A TV needs a look"))
        await hass.async_block_till_done()
    assert _pushes(sent["alex_phone"])[-1].data["message"] == "The TV needs a look."
    assert attention.item("hearth_check_tv_accessibility") is not None
    assert "couldn't announce" in caplog.text
    attention.clear("hearth_check_tv_accessibility")
    await hass.async_block_till_done()
    assert attention.item("hearth_check_tv_accessibility") is None
    assert sent["alex_phone"][-1].data["message"] == "clear_notification"


# hearth.notify


async def _notify(hass: HomeAssistant, user=None, **data):
    return await hass.services.async_call(
        DOMAIN, "notify", data, blocking=True, return_response=True,
        context=Context(user_id=user.id if user else None),
    )


async def test_notify_is_refused_for_someone_who_isn_t_an_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, roles=ROLES)
    with pytest.raises(Unauthorized):
        await _notify(hass, users["sam"], people=["person.alex"], message="Hi")
    # A user who isn't on Hearth's page at all
    stranger = await hass.auth.async_create_user("Visitor")
    with pytest.raises(Unauthorized):
        await _notify(hass, stranger, household=True, message="Hi")
    await hass.async_block_till_done()
    assert not any(_pushes(calls) for calls in sent.values())


async def test_notify_reaches_a_person_s_phones(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT_NOTICE)
    # Alex is an adult on Hearth's page (not an administrator)
    answer = await _notify(hass, users["alex"], people=["person.jordan"], title="Laundry", message="The washer is done.",
                           duration=60)
    await hass.async_block_till_done()
    [push] = _pushes(sent["jordan_iphone"])
    assert push.data["title"] == "Laundry" and push.data["message"] == "The washer is done."
    assert push.data["data"]["tag"].startswith("hearth_notify_")
    assert not _pushes(sent["alex_phone"]) and not _pushes(sent["sam_phone"])
    assert answer["phones"] == ["notify.mobile_app_jordan_iphone"]
    [event] = events
    assert event.data["kind"] == "notify" and event.data["audience"] == {"kind": "person", "people": ["person.jordan"]}
    assert event.data["actions"] == []

    # Taken off at its duration
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=61))
    await hass.async_block_till_done()
    assert sent["jordan_iphone"][-1].data == {"message": "clear_notification", "data": {"tag": push.data["data"]["tag"]}}
    assert events[-1].data["change"] == "cleared"


async def test_notify_the_household_and_a_tv(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, roles=ROLES)
    await _state(client, secret, _tv())

    # An automation's (no user): the household's own
    answer = await _notify(hass, household=True, message="Dinner is ready.")
    await hass.async_block_till_done()
    for phone in ("alex_phone", "jordan_iphone", "sam_phone"):
        assert _pushes(sent[phone])[-1].data["message"] == "Dinner is ready."
    assert answer["tvs"] == [TV_ID]
    [notice] = [n for n in (await _state(client, secret, _tv()))["notices"] if n["message"] == "Dinner is ready."]
    assert notice["urgency"] == "notice" and notice["actions"] == [] and "for" not in notice

    # One TV only: no phone
    answer = await _notify(hass, devices=[TV_ID], message="Movie in 5 minutes.")
    assert answer == {"keys": answer["keys"], "phones": [], "tvs": [TV_ID]}
    assert any(n["message"] == "Movie in 5 minutes." for n in (await _state(client, secret, _tv()))["notices"])


async def test_notify_refuses_a_tv_that_doesn_t_show_notices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, _sent = await _household(hass, hass_client_no_auth)
    await _state(client, secret, _tv(["events"]))
    with pytest.raises(ServiceValidationError):
        await _notify(hass, devices=[TV_ID], message="Hi")
    with pytest.raises(ServiceValidationError):
        await _notify(hass, devices=["no-such-device"], message="Hi")
    with pytest.raises(ServiceValidationError):
        await _notify(hass, message="Nobody")
