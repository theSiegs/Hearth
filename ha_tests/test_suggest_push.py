"""Suggestions pushed to the adults' phones (suggest_push.py): only the pairs the household chose, once a day, off the
phones once answered or gone, at most MAX_PER_HOUR an hour, and the older offer_more moved over without a second
notification."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import PUSHED
from custom_components.hearth.suggest_push import DEBOUNCE, MAX_PER_HOUR, migrated, pairs
from test_attention import _household, _hub, _press
from test_panel import _ws
from test_phones import _options

KEY = "suggest:person.sam:more:video"
TAG = "hearth_suggest:person.sam:more:video"


def _pushes(sent, tag: str = TAG) -> list:
    """The pushes of [tag] to Alex's phone (not its clears)."""
    return [c for c in sent["alex_phone"] if c.data.get("message") != "clear_notification" and c.data["data"]["tag"] == tag]


def _clears(sent, tag: str = TAG) -> list:
    return [c for c in sent["alex_phone"] if c.data.get("message") == "clear_notification" and c.data["data"]["tag"] == tag]


async def _video_out(hass: HomeAssistant) -> None:
    """Sam has watched 10 minutes of video: a 5-minute budget is out."""
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 5}, blocking=True)
    await hass.async_block_till_done()


async def _check(hass: HomeAssistant) -> None:
    _hub(hass).suggest_push.check()
    await hass.async_block_till_done()


async def test_a_chosen_suggestion_is_pushed_once_a_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    # Debounced: nothing at once, then one look
    assert not _pushes(sent)
    async_fire_time_changed(hass, dt_util.utcnow() + DEBOUNCE + timedelta(seconds=1))
    await hass.async_block_till_done()

    [push] = _pushes(sent)
    assert push.data["title"] == "Sam's Video ran out"
    assert push.data["message"] == "Give 30 more minutes today?"
    assert push.data["data"]["actions"] == [
        {"action": f"HEARTH_ACT|{KEY}|0", "title": "+30 min"},
        {"action": f"HEARTH_ACT|{KEY}|1", "title": "+15 min"},
        {"action": f"HEARTH_ACT|{KEY}|2", "title": "Not today"},
    ]
    # Every adult's phone, never the kid's, and never the bell (it's about a kid)
    assert [c.data["data"]["tag"] for c in sent["jordan_iphone"]] == [TAG]
    assert not sent["sam_phone"]
    from homeassistant.components import persistent_notification

    assert TAG not in persistent_notification._async_get_or_create_notifications(hass)
    history = _hub(hass).household.history
    assert [e["key"] for e in history.of("person.sam", kinds=(PUSHED,))] == ["more:video"]

    # Looked at again: not pushed again
    await _check(hass)
    assert len(_pushes(sent)) == 1


async def test_a_suggestion_not_chosen_isn_t_pushed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    await _video_out(hass)
    await _check(hass)
    assert not _pushes(sent)
    # Another of Sam's groups chosen, or Video for another kid: still not this one
    await _options(
        hass,
        suggest_push=[{"person": "person.sam", "group": "games"}, {"person": "person.alex", "group": "video"}],
    )
    await _check(hass)
    assert not _pushes(sent)
    assert not [c for phone in sent.values() for c in phone if "suggest" in c.data.get("data", {}).get("tag", "")]


async def test_put_off_today_isn_t_pushed_and_comes_off_the_phones(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video"}])
    await _video_out(hass)
    await hass.services.async_call(DOMAIN, "dismiss_suggestion", {"person": "person.sam", "key": "more:video"}, blocking=True)
    await _check(hass)
    assert not _pushes(sent)

    # Pushed, then "Not today" on Jordan's phone: off every phone
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "games"}])
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": 2}, blocking=True)
    await _check(hass)
    games = "hearth_suggest:person.sam:more:games"
    assert len(_pushes(sent, games)) == 1
    _press(hass, "HEARTH_ACT|suggest:person.sam:more:games|2", users["jordan"])
    await hass.async_block_till_done()
    await _check(hass)
    assert _clears(sent, games)
    assert any(c.data == {"message": "clear_notification", "data": {"tag": games}} for c in sent["jordan_iphone"])
    assert _hub(hass).attention.item("suggest:person.sam:more:games") is None


async def test_answered_or_no_longer_out_comes_off_the_phones(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    await _check(hass)
    assert len(_pushes(sent)) == 1

    # +30 from Alex's phone: the bonus is given as Alex, and the push goes
    _press(hass, f"HEARTH_ACT|{KEY}|0", users["alex"])
    await hass.async_block_till_done()
    assert hass.states.get("number.hearth_sam_video_bonus_today").state == "30"
    await _check(hass)
    assert _clears(sent)
    assert _hub(hass).attention.item(KEY) is None
    # Out again the same day: not pushed a second time
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "group": "video", "minutes": -30}, blocking=True)
    await _check(hass)
    assert len(_pushes(sent)) == 1

    # A pair no longer chosen comes off too
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": 2}, blocking=True)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "games"}])
    await _check(hass)
    games = "hearth_suggest:person.sam:more:games"
    assert len(_pushes(sent, games)) == 1
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": None}, blocking=True)
    await _check(hass)
    assert _clears(sent, games)


async def test_offer_more_moves_over_and_doesn_t_notify_twice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    # An older household's Configure > Offer more time: moved into suggest_push when it loads, with its amount
    await _options(hass, offer_more=[{"person": "person.sam", "group": "video", "minutes": 45}])
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert "offer_more" not in entry.options
    assert entry.options["suggest_push"] == [{"person": "person.sam", "group": "video", "minutes": 45}]

    await _video_out(hass)
    await _check(hass)
    # No offered request, one notification, the amount kept
    assert _hub(hass).asks.pending() == []
    [push] = _pushes(sent)
    assert push.data["message"] == "Give 45 more minutes today?"
    assert not [c for c in sent["alex_phone"] if c.data["data"]["tag"].startswith("hearth_more_")]


def test_migration_keeps_amounts_and_the_household_s_own_pairs() -> None:
    options = {
        "offer_more": [
            {"person": "person.sam", "group": "video", "minutes": 45},
            {"person": "person.sam", "group": "games"},
            {"person": "person.alex", "group": "video", "minutes": 15},
        ],
        "suggest_push": [{"person": "person.alex", "group": "video", "minutes": 60}],
        "roles": {"person.sam": "kid"},
    }
    # Read as pairs before it's moved
    assert {(p["person"], p["group"], p.get("minutes")) for p in pairs(options)} == {
        ("person.sam", "video", 45), ("person.sam", "games", 30), ("person.alex", "video", 60)
    }
    moved = migrated(options)
    assert "offer_more" not in moved and moved["roles"] == {"person.sam": "kid"}
    assert moved["suggest_push"] == [
        {"person": "person.alex", "group": "video", "minutes": 60},
        {"person": "person.sam", "group": "video", "minutes": 45},
        {"person": "person.sam", "group": "games", "minutes": 30},
    ]
    assert migrated(moved) is None


async def test_at_most_six_an_hour(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    history = _hub(hass).household.history
    for n in range(MAX_PER_HOUR):
        history.log(PUSHED, "person.sam", dt_util.utcnow() - timedelta(minutes=50), key=f"device:other_{n}")
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video"}])
    await _video_out(hass)
    await _check(hass)
    assert not _pushes(sent)
    # Still in the household summary
    from custom_components.hearth.websocket import summary

    sam = next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")
    assert [s["key"] for s in sam["suggestions"]] == ["more:video"]
    # One that wasn't pushed for the cap isn't pushed later that day either
    for event in history.events:
        event["at"] = (dt_util.utcnow() - timedelta(hours=2)).isoformat()
    await _check(hass)
    assert not _pushes(sent)


async def test_after_a_restart_it_isn_t_pushed_again_and_still_comes_off(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video"}])
    await _video_out(hass)
    # Pushed before Home Assistant restarted: the history has it, the items are gone
    hub = _hub(hass)
    hub.household.history.log(PUSHED, "person.sam", key="more:video")
    hub.attention.clear(KEY)
    sent["alex_phone"].clear()
    await _check(hass)
    assert not _pushes(sent)
    # Its buttons on the phones work again, and it comes off them when it goes
    _press(hass, f"HEARTH_ACT|{KEY}|2", users["alex"])
    await hass.async_block_till_done()
    await _check(hass)
    assert _clears(sent)


async def test_the_page_sets_which_suggestions_go_to_phones(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household(hass, hass_client_no_auth)
    await _options(hass, offer_more=[{"person": "person.sam", "group": "games", "minutes": 15}])
    ws = await hass_ws_client(hass)
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    assert config["suggest_push"] == [{"person": "person.sam", "group": "games", "minutes": 15}]

    value = [
        {"person": "person.sam", "group": "video", "minutes": 30},
        {"person": "person.sam", "group": "all"},
        {"person": "person.sam", "device": "fs:xbox", "minutes": 15},
    ]
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "suggest_push", "value": value})
    assert answer["success"], answer
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["suggest_push"] == value and "offer_more" not in entry.options

    for bad in (
        [{"person": "person.sam", "group": "video", "minutes": 20}],
        [{"person": "person.sam", "group": "video", "device": "fs:xbox"}],
        [{"person": "person.sam"}],
        [{"person": "sensor.sam", "group": "video"}],
        [{"person": "person.sam", "group": "Video!"}],
        [{"person": "person.sam", "group": "video"}, {"person": "person.sam", "group": "video", "minutes": 15}],
    ):
        answer = await _ws(ws, {"type": "hearth/config/set", "key": "suggest_push", "value": bad})
        assert not answer["success"] and answer["error"]["code"] == "invalid", bad
    assert entry.options["suggest_push"] == value
