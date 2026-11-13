"""Suggestions (glance.suggestions): what an adult will likely be asked for next, with the answer ready; and the
history log (history.py) that sizes and silences them."""

from datetime import datetime, timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glance import household_glance, suggestions
from custom_components.hearth.history import BONUS, DISMISS, History
from test_glance import _kids_alex_and_sam, _person, _summary


def _keys(found) -> list[str]:
    return [s["key"] for s in found]


def test_a_group_out_suggests_more_of_that_group() -> None:
    found = suggestions(_person(all=40, games=0, youtube=12), [], [])
    assert _keys(found) == ["more:games"]
    games = found[0]
    assert games["text"] == "games ran out · give 15?" and games["group"] == "games" and games["minutes"] == 15
    actions = {a["id"]: a for a in games["actions"]}
    assert actions["suggest:more:games:15"]["data"] == {"person": "person.alex", "minutes": 15, "group": "games"}
    assert actions["suggest:more:games:15"]["primary"] and "primary" not in actions["suggest:more:games:30"]
    assert actions["suggest_dismiss:more:games"] == {
        "id": "suggest_dismiss:more:games",
        "label": "not today",
        "service": "hearth.dismiss_suggestion",
        "data": {"person": "person.alex", "key": "more:games"},
    }


def test_out_of_all_screen_time_suggests_all_only() -> None:
    found = suggestions(_person(all=0, games=0), [], [])
    assert _keys(found) == ["more:all"]
    assert found[0]["minutes"] == 30 and found[0]["text"] == "screen time ran out · give 30?"


def test_no_suggestion_while_an_ask_waits_an_allow_lifts_it_or_it_was_put_off() -> None:
    person = _person(all=40, games=0, youtube=0)
    ask = {"id": "abc", "person": "person.alex", "minutes": 30, "group": "games"}
    assert _keys(suggestions(person, [ask], [])) == ["more:youtube"]
    allow = {"id": "a1", "group": "youtube", "until": "2026-11-06T19:00:00"}
    assert _keys(suggestions(person, [ask], [allow])) == []
    assert _keys(suggestions(person, [], [], {"dismissed": {"more:games"}})) == ["more:youtube"]


def test_the_amount_is_the_household_s_then_the_usual_then_a_quarter() -> None:
    person = _person(all=40, games=0)
    assert suggestions(person, [], [], {"minutes": {"games": 45}})[0]["minutes"] == 45
    assert suggestions(person, [], [], {"usual": {"games": 30}})[0]["minutes"] == 30
    assert [a["data"]["minutes"] for a in suggestions(person, [], [], {"usual": {"games": 30}})[0]["actions"][:2]] == [
        30, 15
    ]


def test_a_first_party_limit_suggests_extra_time_on_that_device() -> None:
    person = {
        **_person(all=40, games=20),
        "targets": [
            {"id": "fl:d1", "name": "Pixel", "kind": "phone", "via": "family_link", "groups": False},
            {"id": "fs:xbox", "name": "Xbox", "kind": "xbox", "via": "family_safety", "groups": False},
            {"id": "nintendo:switch.kid", "name": "Switch", "kind": "switch", "via": "nintendo", "groups": False},
        ],
        "first_party": {
            "family_link": [{"device_id": "d1", "device": "Pixel", "blocking": True}],
            "family_safety": [{"platform": "Xbox", "blocking": True}, {"platform": "Windows", "blocking": False}],
            "nintendo": [{"name": "Switch", "blocking": True}],
        },
        "device_extras": [],
    }
    found = suggestions(person, [], [])
    assert _keys(found) == ["device:fl:d1", "device:fs:xbox", "device:nintendo:switch.kid"]
    assert found[0]["text"] == "pixel · google's limit · give 15?"
    assert found[1]["actions"][0]["data"] == {"person": "person.alex", "minutes": 15, "group": "all", "device": "fs:xbox"}
    # Extra time already running there, or a Family Safety request waiting: nothing more to suggest
    running = {**person, "device_extras": [{"target": "fs:xbox"}]}
    assert "device:fs:xbox" not in _keys(suggestions(running, [], []))
    fs_ask = {"id": "r", "person": "person.alex", "minutes": 30, "group": "all", "source": "family_safety"}
    assert "device:fs:xbox" not in _keys(suggestions(person, [fs_ask], []))
    # Out of All screen time: Hearth's time is what stops them, so only more of it
    out = {**person, "groups": _person(all=0)["groups"]}
    assert _keys(suggestions(out, [], [])) == ["more:all"]


def test_the_household_lists_everyone_s_suggestions_all_first() -> None:
    alex = {**_person(all=40, games=0), "suggestions": suggestions(_person(all=40, games=0), [], [])}
    sam_view = {**_person(all=0), "id": "person.sam", "name": "Sam"}
    sam = {**sam_view, "suggestions": suggestions(sam_view, [], [])}
    found = household_glance([alex, sam], [])["suggestions"]
    assert [(s["person"], s["key"]) for s in found] == [("person.sam", "more:all"), ("person.alex", "more:games")]
    assert found[0]["person_name"] == "Sam"


async def test_history_sizes_and_silences(hass: HomeAssistant) -> None:
    history = History(hass, "test")
    now = dt_util.utcnow()
    for minutes in (30, 30, 15, 30):
        history.log(BONUS, "person.alex", now - timedelta(days=1), group="games", minutes=minutes)
    history.log(BONUS, "person.alex", now - timedelta(days=40), group="games", minutes=60)
    assert history.usual_bonus("person.alex", "games", now) == 30
    assert history.usual_bonus("person.alex", "youtube", now) is None
    history.log(DISMISS, "person.alex", now, key="more:games")
    history.log(DISMISS, "person.alex", now - timedelta(days=1), key="more:youtube")
    assert history.dismissed("person.alex", dt_util.as_local(now).date()) == {"more:games"}
    days = history.days_summary("person.alex", 7, now)
    assert days[-1]["bonus"] == {"games": 105}


async def test_the_summary_suggests_and_not_today_puts_it_off(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    await _kids_alex_and_sam(hass, hass_client_no_auth, freezer)
    # Alex has watched 25 minutes of video: a 20-minute budget is out
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.alex", "group": "video", "minutes": 20}, blocking=True
    )
    await hass.async_block_till_done()
    ws = await hass_ws_client(hass)
    summary = await _summary(ws)
    alex = next(p for p in summary["people"] if p["id"] == "person.alex")
    assert _keys(alex["suggestions"]) == ["more:video"]
    assert ("person.alex", "more:video") in [(s["person"], s["key"]) for s in summary["household"]["suggestions"]]
    history = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household.history
    assert any(e["kind"] == "out" and e.get("group") == "video" for e in history.of("person.alex"))

    await hass.services.async_call(
        DOMAIN, "dismiss_suggestion", {"person": "person.alex", "key": "more:video"}, blocking=True
    )
    await hass.async_block_till_done()
    alex = next(p for p in (await _summary(ws, 2))["people"] if p["id"] == "person.alex")
    assert alex["suggestions"] == []

    # A bonus is logged, with its group and minutes
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.alex", "group": "video", "minutes": 15}, blocking=True
    )
    assert history.of("person.alex", kinds=("bonus",))[-1] | {"at": None} == {
        "at": None, "kind": "bonus", "person": "person.alex", "group": "video", "minutes": 15
    }
