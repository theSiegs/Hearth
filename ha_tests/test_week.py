"""The household summary's `week`: each person's last 7 local days, from the history log's `day` records (history.py)
and today's live minutes."""

from datetime import datetime, timedelta
import json

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import ASK, BONUS, DAY, DEVICE_BONUS, OUT, History
from custom_components.hearth.websocket import summary
from test_init import TV_ID
from test_people import _household_with_sam, _tv_status


def _at(day, hour: int, minute: int = 0) -> datetime:
    return dt_util.start_of_local_day(day) + timedelta(hours=hour, minutes=minute)


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _days(hass: HomeAssistant, person: str) -> list[dict]:
    return [e for e in _household(hass).history.of(person, kinds=(DAY,))]


async def test_the_week_is_seven_days_newest_first_with_what_happened(hass: HomeAssistant) -> None:
    history = History(hass, "test")
    today = dt_util.now().date()
    now = _at(today, 18)
    history.log(DAY, "person.alex", _at(today - timedelta(days=1), 0, 1), date=(today - timedelta(days=2)).isoformat(),
                minutes={"all": 95, "games": 40})
    history.log(OUT, "person.alex", _at(today - timedelta(days=2), 17), group="games")
    history.log(OUT, "person.alex", _at(today - timedelta(days=2), 18), group="games")
    history.log(ASK, "person.alex", _at(today - timedelta(days=2), 17, 5), group="games", minutes=30)
    history.log(BONUS, "person.alex", _at(today - timedelta(days=2), 17, 10), group="games", minutes=30)
    history.log(DEVICE_BONUS, "person.alex", _at(today, 9), device="hearth:tv", minutes=15)
    history.log(ASK, "person.sam", _at(today, 9), minutes=30)
    # Older than the week, and a record for today (today's minutes are always live)
    history.log(DAY, "person.alex", _at(today - timedelta(days=7), 0, 1), date=(today - timedelta(days=8)).isoformat(),
                minutes={"all": 10})
    history.log(DAY, "person.alex", _at(today, 0, 1), date=today.isoformat(), minutes={"all": 1})

    week = history.week("person.alex", {"all": 20, "games": 0}, now)
    assert [row["date"] for row in week] == [(today - timedelta(days=i)).isoformat() for i in range(7)]
    assert week[0] == {"date": today.isoformat(), "minutes": {"all": 20, "games": 0}, "out": [],
                       "bonus": {"all": 15}, "asks": 0, "budget": {}}
    assert week[1] == {"date": (today - timedelta(days=1)).isoformat(), "minutes": {}, "out": [], "bonus": {}, "asks": 0,
                       "budget": {}}
    assert week[2] == {"date": (today - timedelta(days=2)).isoformat(), "minutes": {"all": 95, "games": 40},
                       "out": ["games"], "bonus": {"games": 30}, "asks": 1, "budget": {}}
    assert all(row["minutes"] == {} for row in week[3:])


async def test_the_day_s_minutes_are_recorded_when_it_turns(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    day = dt_util.now().date()
    freezer.move_to(_at(day, 12))
    await _household_with_sam(hass, hass_client_no_auth)
    household = _household(hass)

    freezer.move_to(_at(day + timedelta(days=1), 0, 1))
    household.recompute()
    await hass.async_block_till_done()
    [record] = _days(hass, "person.sam")
    assert record["date"] == day.isoformat()
    assert record["minutes"]["all"] == 15 and record["minutes"]["video"] == 10 and record["minutes"]["games"] == 5
    # Once a day, however often it's looked at
    household.recompute()
    assert len(_days(hass, "person.sam")) == 1
    # No names: people are entity ids, groups their ids
    assert "Sam" not in json.dumps(household.history.events)

    # Today's minutes are live
    freezer.move_to(_at(day + timedelta(days=1), 9))
    # Straight to the hub and the summary: Home Assistant's HTTP and WebSocket don't take a clock moved this far
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    hub.update_status(TV_ID, _tv_status(hearthtube_s=1200))
    await hass.async_block_till_done()
    sam = next(p for p in summary(hub)["people"] if p["id"] == "person.sam")
    week = sam["week"]
    assert len(week) == 7 and [r["date"] for r in week[:2]] == [(day + timedelta(days=1)).isoformat(), day.isoformat()]
    assert week[0]["minutes"]["all"] == 20 and week[0]["minutes"]["video"] == 20
    assert week[1]["minutes"] == record["minutes"]
    # A day nothing was recorded for is unknown, not zero
    assert week[2]["minutes"] == {}
    assert set(week[0]) == {"date", "minutes", "out", "bonus", "asks", "budget"}
    # The day's budget per group: logged with its minutes, today's live (null: no limit)
    assert set(record["budget"]) == set(record["minutes"]) and week[1]["budget"] == record["budget"]
    assert set(week[0]["budget"]) == set(record["budget"]) and set(week[2]["budget"]) == set(record["budget"])


async def test_a_midnight_missed_while_home_assistant_was_down_is_recorded_on_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    day = dt_util.now().date()
    freezer.move_to(_at(day, 12))
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert _days(hass, "person.sam") == []

    # Stopped before midnight, started the morning after
    assert await hass.config_entries.async_unload(entry.entry_id)
    await hass.async_block_till_done()
    freezer.move_to(_at(day + timedelta(days=1), 7))
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()

    [record] = _days(hass, "person.sam")
    assert record["date"] == day.isoformat()
    assert record["minutes"]["all"] == 15 and record["minutes"]["games"] == 5
    _household(hass).recompute()
    assert len(_days(hass, "person.sam")) == 1
