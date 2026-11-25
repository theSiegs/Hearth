"""What Glint's kid time asks of Hearth (Glint's docs/design/kid-time-2026-11.md §8): every group's budgets in the
household summary (F1), hearth.set_budget's "no limit" and its before/after (F2), a panel's read-only kid time (F3), the
person and kind on every pushed notice (F4), Unlimited's undo id kept until midnight (F6), and the minutes used while
Unlimited shown as used, not counted (F7)."""

from datetime import timedelta
from types import SimpleNamespace

import pytest
import voluptuous as vol

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import unlimited as unlimited_module
from custom_components.hearth.attention import ADULTS, Item, item_people, item_person, routing
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.exceptions import end_of_day
from custom_components.hearth.history import DAY, History
from test_attention import _household as _with_phones
from test_glint_panel import PANEL_ID, _displays, _pair_panel  # noqa: F401 - _displays: the panels' login
from test_init import _post
from test_people import _household_with_sam, _tv_status
from test_time_model import _call, _set

SAM = "person.sam"


def _household(hass):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _sam(hass, hass_ws_client) -> dict:
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    return answer["result"], next(p for p in answer["result"]["people"] if p["id"] == SAM)


# F1: every group's budgets in the summary


async def test_the_summary_has_every_group_s_budgets(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _call(hass, "set_budget", {"person": SAM, "group": "video", "minutes": 10, "days": "school_days"})
    body, sam = await _sam(hass, hass_ws_client)
    rows = {row["group"]: row for row in sam["budgets"]}
    # Every group of the household, in its order, a budget or not
    assert [row["group"] for row in sam["budgets"]] == [g.id for g in _household(hass).groups]
    assert rows["all"] == {
        "group": "all", "name": rows["all"]["name"], "school_days": 60, "other_days": 60, "per_weekday": False,
        "limitable": True,
    }
    assert (rows["video"]["school_days"], rows["video"]["other_days"]) == (10, None)
    assert (rows["games"]["school_days"], rows["games"]["other_days"]) == (None, None)
    assert rows["accessibility"]["limitable"] is False
    assert sam["budgets_per_weekday"] is False
    assert sam["half_day_budget"] == body["half_day_budget"] == "other_days"

    # A weekday of its own on the Schedule tab: the row says so and lists the days
    week = _household(hass).week
    week._own(SAM)["days"]["wed"]["limits"]["video"] = 30
    _, sam = await _sam(hass, hass_ws_client)
    video = next(row for row in sam["budgets"] if row["group"] == "video")
    assert video["per_weekday"] is True and sam["budgets_per_weekday"] is True
    assert video["weekdays"] == {
        "mon": 10, "tue": 10, "wed": 30, "thu": 10, "fri": 10, "sat": None, "sun": None, "day_off": None
    }
    # Their own half day: a school day's limits
    week._own(SAM)["half_day"]["limits"] = "weekday"
    _, sam = await _sam(hass, hass_ws_client)
    assert sam["half_day_budget"] == "school_days"


# F2: hearth.set_budget's no limit, and its before and after


async def test_set_budget_takes_no_limit_and_answers_before_and_after(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "video", 40)
    answer = await _call(hass, "set_budget", {"person": SAM, "group": "video", "minutes": "no_limit"})
    assert answer == {
        "person": SAM, "group": "video",
        "before": {"school_days": 40, "other_days": 40, "per_weekday": False},
        "after": {"school_days": None, "other_days": None, "per_weekday": False},
    }
    answer = await _call(hass, "set_budget", {"person": SAM, "group": "Video", "minutes": 25, "days": "other_days"})
    assert answer["group"] == "video" and answer["after"]["other_days"] == 25 and answer["after"]["school_days"] is None
    for no_limit in ({"minutes": -1}, {"minutes": None}, {"no_limit": True}):
        answer = await _call(hass, "set_budget", {"person": SAM, "group": "video", **no_limit})
        assert answer["after"]["other_days"] is None
        await _call(hass, "set_budget", {"person": SAM, "group": "video", "minutes": 25})
    # The undo: the before values back
    answer = await _call(hass, "set_budget", {"person": SAM, "group": "video", "minutes": 0, "days": "school_days"})
    assert answer["after"]["school_days"] == 0
    await _call(hass, "set_budget", {"person": SAM, "group": "video", "minutes": answer["before"]["school_days"],
                                     "days": "school_days"})
    assert _household(hass).limits.budget(SAM, "video", "weekday") == 25
    for bad in ({}, {"minutes": 1441}, {"minutes": -2}, {"no_limit": True, "minutes": 30}, {"no_limit": False}):
        with pytest.raises(vol.Invalid):
            await _call(hass, "set_budget", {"person": SAM, "group": "video", **bad})


# F3: a panel's kid time


async def test_a_panel_reads_each_kid_s_time_by_its_secret(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    # Tomorrow at 14:00: never behind the real clock, which the panel's login token is checked against
    freezer.move_to((dt_util.now() + timedelta(days=1)).replace(hour=14, minute=0, second=0, microsecond=0))
    client, _secret = await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {SAM: "kid"}})
    await hass.async_block_till_done()
    await _set(hass, "all", 60)
    panel = await _pair_panel(hass, client)
    ws = await hass_ws_client(hass, access_token=panel["ha_token"])

    await ws.send_json({"id": 1, "type": "hearth/panel/kids/subscribe", "device_id": PANEL_ID, "secret": "nope"})
    assert (await ws.receive_json())["error"]["code"] == "unknown_panel"

    await ws.send_json({"id": 2, "type": "hearth/panel/kids/subscribe", "device_id": PANEL_ID, "secret": panel["secret"]})
    assert (await ws.receive_json())["success"]
    first = (await ws.receive_json())["event"]
    [sam] = first["kids"]
    assert sam["person"] == SAM and sam["name"] == "Sam"
    assert sam["time"]["today_left"] == 45 and sam["time"]["used"] == 15 and sam["time"]["text"]
    assert "origins" not in sam["time"]
    assert sam["locked"] is False and sam["lock"] is None and sam["unlimited_minutes"] == 0
    assert sam["school_today"]["state"] in ("school", "half_day", "off", "home_today")
    assert {"mode", "bedtime", "pause", "next_lock", "bedtime_lifted"} <= set(sam)

    # A change comes as a new event (batched)
    await _call(hass, "add_time", {"person": SAM, "minutes": 30})
    freezer.tick(timedelta(seconds=3))
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    again = (await ws.receive_json())["event"]
    assert again["kids"][0]["time"]["bonus_left"] == 30 and again["version"] != first["version"]


# F4: the person and kind on every pushed notice


def test_routing_says_who_and_what() -> None:
    one = Item("hearth_place_person.sam_family_link", "Sam is home", about={"person": SAM})
    assert routing(one) == {"hearth_kind": "place", "hearth_person": SAM, "hearth_people": [SAM]}
    # A Switch held for one kid in another's turn: about the held kid, and both
    turn = Item("hearth_switch_x", "", about={"person": SAM, "people": [SAM, "person.kim"]})
    assert routing(turn) == {"hearth_kind": "switch", "hearth_person": SAM, "hearth_people": [SAM, "person.kim"]}
    # Several alike: no one person
    both = Item("hearth_native_limit_x", "", about={"people": [SAM, "person.kim"]}, kind="native_limit")
    assert routing(both) == {"hearth_kind": "native_limit", "hearth_person": "", "hearth_people": [SAM, "person.kim"]}
    assert (item_person(Item("k", "", about={"people": [SAM]})), item_people(Item("k", ""))) == (SAM, [])


async def test_every_push_carries_the_person_and_kind(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    monkeypatch.setattr(unlimited_module, "SETTLE", timedelta(0))
    freezer.move_to(dt_util.now().replace(hour=14, minute=0, second=0, microsecond=0))
    _client, _secret, _users, sent = await _with_phones(hass, hass_client_no_auth)
    household = _household(hass)
    events = []
    hass.bus.async_listen("hearth_notice", lambda e: events.append(e.data))

    # Unlimited's end, told the adults by asks.tell: its tag names the person, the data too
    await _call(hass, "unlimited", {"person": SAM, "until": "14:30"})
    freezer.tick(timedelta(minutes=31))
    household.recompute()
    await hass.async_block_till_done()
    data = sent["alex_phone"][-1].data["data"]
    assert data["tag"] == f"hearth_unlimited_{SAM}"
    assert (data["hearth_kind"], data["hearth_person"], data["hearth_people"]) == ("unlimited", SAM, [SAM])

    # A shared Switch's play on no player while two kids may not play: about both, no one person
    switch = SimpleNamespace(entity_id="number.living_room_switch_limit", person=SAM)
    household._switch_notice(switch, "unattributed", {"held_for": [SAM, "person.kim"], "minutes": 5})
    await hass.async_block_till_done()
    data = sent["alex_phone"][-1].data["data"]
    assert (data["hearth_kind"], data["hearth_person"], data["hearth_people"]) == ("switch", "", [SAM, "person.kim"])
    assert events[-1]["about"] == {"people": [SAM, "person.kim"]}
    # Held for Sam in Kim's turn: about Sam, and both
    household._switch_notice(switch, "caught_in_turn", {"for_person": "person.kim"})
    await hass.async_block_till_done()
    data = sent["alex_phone"][-1].data["data"]
    assert (data["hearth_kind"], data["hearth_person"], data["hearth_people"]) == ("switch", SAM, [SAM, "person.kim"])
    assert events[-1]["about"] == {"person": SAM, "people": [SAM, "person.kim"]}

    # hearth.notify: its kind, about no one
    await _call(hass, "notify", {"people": ["person.alex"], "message": "Dinner"})
    data = sent["alex_phone"][-1].data["data"]
    assert (data["hearth_kind"], data["hearth_person"], data["hearth_people"]) == ("notify", "", [])
    # One person's notice: the event's about is as before
    household.hub.attention.notify(Item("hearth_place_x", "Sam is home", audience=ADULTS, about={"person": SAM}))
    assert events[-1]["about"] == {"person": SAM}


# F6: Unlimited's undo id, kept until midnight


async def test_unlimited_answers_its_undo_id_and_keeps_it_until_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=14, minute=0, second=0, microsecond=0))
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    household = _household(hass)
    answer = await _call(hass, "unlimited", {"person": SAM})
    # The end of the day by default
    assert dt_util.parse_datetime(answer["until"][SAM]) == end_of_day(dt_util.now())
    origin = answer["origin_id"]
    assert origin and answer["origin_ids"] == {SAM: origin}
    assert household.time_view(SAM)["unlimited"]["origin"] == origin
    freezer.move_to(dt_util.now().replace(hour=23, minute=58))
    household.recompute()
    assert household.time_view(SAM)["unlimited"]["origin"] == origin
    # The undo
    assert (await _call(hass, "end_grant", {"origin_id": origin}))["kind"] == "unlimited"
    assert household.time_view(SAM)["unlimited"] is None


# F7: minutes used while Unlimited are used, not counted


async def test_unlimited_minutes_show_as_used_not_counted(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer, monkeypatch
) -> None:
    monkeypatch.setattr(unlimited_module, "SETTLE", timedelta(minutes=10))
    freezer.move_to(dt_util.now().replace(hour=14, minute=0, second=0, microsecond=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    household = _household(hass)
    await _call(hass, "unlimited", {"person": SAM, "until": "17:10"})
    freezer.tick(timedelta(hours=3, minutes=10))
    assert (await _post(client, secret, body=_tv_status(hearthtube_s=600 + 190 * 60, game_s=300))).status == 200
    await hass.async_block_till_done()

    # Counted: what the day's time goes by
    assert household.time_view(SAM)["used"] == 15
    # The group's today sensor shows every minute (its statistics too); counted and Unlimited's apart
    video = hass.states.get("sensor.hearth_sam_video_today")
    assert video.state == "200"
    assert (video.attributes["counted"], video.attributes["unlimited"]) == (10, 190)
    games = hass.states.get("sensor.hearth_sam_games_today")
    assert (games.state, games.attributes["counted"], games.attributes["unlimited"]) == ("5", 5, 0)

    # (the summary itself: the test login's token is past its time by now)
    from custom_components.hearth.websocket import summary

    sam = next(p for p in summary(household.hub)["people"] if p["id"] == SAM)
    groups = {g["id"]: g for g in sam["groups"]}
    assert (groups["video"]["used_minutes"], groups["video"]["total_minutes"], groups["video"]["unlimited_minutes"]) == (
        10, 200, 190
    )
    assert (groups["all"]["used_minutes"], groups["all"]["total_minutes"]) == (15, 205)
    assert sam["week"][0]["minutes"]["video"] == 10 and sam["week"][0]["used"]["video"] == 200


async def test_a_day_s_record_keeps_the_minutes_used_while_unlimited(hass: HomeAssistant) -> None:
    history = History(hass, "entry")
    day = dt_util.now().date() - timedelta(days=1)
    assert history.log_day(SAM, day, {"all": 15}, None, {"all": 205})
    assert history.log_day("person.kim", day, {"all": 15}, None, {"all": 15})
    [sam, kim] = [e for e in history.events if e["kind"] == DAY]
    assert sam["used"] == {"all": 205} and "used" not in kim  # kept only when it differs
    week = history.week(SAM, {}, dt_util.now())
    assert (week[1]["minutes"], week[1]["used"]) == ({"all": 15}, {"all": 205})
    assert history.week("person.kim", {}, dt_util.now())[1]["used"] == {"all": 15}
