"""The schedule: day types, School time off on a day off and back inside the window, half days, extra time, the
website list, chores and offering more time."""

from datetime import date, datetime, timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.schooldays import SchoolDays
from test_enforce import _add_enforcer
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
SWITCH = "switch.sam_school_time"
SENSOR = "binary_sensor.sam_phone_school_time_active"
URL = "https://example.com/blocklist.txt"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _at(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=dt_util.get_default_time_zone())


def _family_link_entities(hass: HomeAssistant, child: str = "42", name: str = "sam") -> None:
    registry = er.async_get(hass)
    registry.async_get_or_create(
        "switch", "familylink", f"familylink_{child}_school_time", suggested_object_id=f"{name}_school_time"
    )
    registry.async_get_or_create(
        "switch", "familylink", f"familylink_{child}_daily_limit", suggested_object_id=f"{name}_daily_limit"
    )
    hass.states.async_set(f"switch.{name}_school_time", "on")
    hass.states.async_set(f"switch.{name}_daily_limit", "on")
    for iso in range(1, 8):
        for bound, value in (("start", "08:10:00"), ("end", "15:00:00")):
            entity = registry.async_get_or_create(
                "time",
                "familylink",
                f"familylink_{child}_schooltime_{iso}_{bound}",
                suggested_object_id=f"{name}_day{iso}_school_time_{bound}",
            )
            hass.states.async_set(entity.entity_id, value, {"child_id": child})
    for weekday in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
        hass.states.async_set(
            f"number.{name}_family_link_{weekday}_limit",
            "120",
            {"child_id": child, "weekly_minutes": 120, "override_minutes": None},
        )
    hass.states.async_set(f"sensor.{name}_family_link_daily_screen_time", "0", {"child_id": child})


async def _set_up(hass: HomeAssistant, hass_client_no_auth, freezer, now: datetime, school: dict, schedule: dict):
    freezer.move_to(now)
    await _household_with_sam(hass, hass_client_no_auth)
    _family_link_entities(hass)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "school_time_apps": []})
    await _option(hass, "school_days", school)
    await _option(hass, "schedule", schedule)
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _tick(hass: HomeAssistant, household, freezer, now: datetime) -> None:
    freezer.move_to(now)
    await household.scheduler.async_tick(now)
    await hass.async_block_till_done()


YEAR = {"year_start": "2026-08-31", "year_end": "2027-06-14"}


async def test_day_types(hass: HomeAssistant) -> None:
    school = SchoolDays(hass)
    school.configure({"school_days": {**YEAR, "days_off": "2026-11-26", "half_days": "2026-11-25"}})
    assert school.decide_type(date(2026, 11, 24)) == "school"
    assert school.decide_type(date(2026, 11, 25)) == "half_day"
    assert school.decide_type(date(2026, 11, 26)) == "day_off"
    assert school.decide_type(date(2026, 11, 28)) == "weekend"
    assert school.decide_type(date(2027, 7, 6)) == "no_school"
    # A half day takes the other-day budget unless chosen otherwise
    assert school.budget_is_school("half_day") is False
    school.configure({"school_days": {"half_day_budget": "school_days"}})
    assert school.budget_is_school("half_day") is True

    hass.states.async_set("input_select.day_type", "half")
    school.configure({"school_days": {**YEAR, "entity": "input_select.day_type", "school_states": "school"}})
    assert school.decide_type(date(2026, 11, 24)) == "half_day"


async def test_a_day_off_takes_school_time_off_and_puts_it_back_inside_the_window(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    off = async_mock_service(hass, "switch", "turn_off")
    on = async_mock_service(hass, "switch", "turn_on")
    pin = async_mock_service(hass, "familylink", "set_school_time")
    limit = async_mock_service(hass, "familylink", "set_daily_limit")
    day_off, next_day = date(2026, 11, 26), date(2026, 11, 27)
    household = await _set_up(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_school_time_off": True, "day_off_bonus": 60},
    )
    assert off == []  # before 00:05
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert [c.data for c in off] == [{"entity_id": SWITCH}]
    # Today only, the weekday's limit plus the extra hour, the child's id as a string
    assert [c.data for c in limit] == [{"child_id": "42", "daily_minutes": 180}]
    assert hass.states.get("sensor.hearth_home_day_type").state == "day_off"
    hass.states.async_set(SWITCH, "off")
    await _tick(hass, household, freezer, _at(day_off, 9))
    assert len(off) == 1 and on == []  # once a day; never on on a day off
    [taken] = hass.states.get("sensor.hearth_sam_screen_time_today").attributes["exceptions"]["school_time_off"]
    assert taken["applied"] is True and taken["restore_from"] == next_day.isoformat()

    # The next school day: not before the window, then on inside it with today's hours pinned
    await _tick(hass, household, freezer, _at(next_day, 7, 30))
    assert on == []
    await _tick(hass, household, freezer, _at(next_day, 8, 15))
    assert [c.data for c in on] == [{"entity_id": SWITCH}]
    assert pin[-1].data == {"entity_id": SWITCH, "scope": "today", "start_time": "08:10", "end_time": "15:00"}
    hass.states.async_set(SWITCH, "on")
    hass.states.async_set(SENSOR, "on", {"child_id": "42", "schooltime_end": "2026-11-27T23:59:00"})
    await _tick(hass, household, freezer, _at(next_day, 8, 16))
    assert len(pin) == 1  # just pinned: Family Link catches up first
    await _tick(hass, household, freezer, _at(next_day, 8, 18))
    assert len(pin) == 2  # the devices still say 23:59: pinned again
    hass.states.async_set(SENSOR, "on", {"child_id": "42", "schooltime_end": "2026-11-27T15:00:00"})
    await _tick(hass, household, freezer, _at(next_day, 8, 19))
    assert household.scheduler.offs == {}
    assert len(on) == 1 and len(pin) == 2


async def test_a_half_day_ends_school_time_early_with_extra_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    pin = async_mock_service(hass, "familylink", "set_school_time")
    limit = async_mock_service(hass, "familylink", "set_daily_limit")
    half = date(2026, 11, 25)
    household = await _set_up(
        hass,
        hass_client_no_auth,
        freezer,
        _at(half, 0, 1),
        {**YEAR, "half_days": "2026-11-25"},
        {"half_day_hours_early": 3, "half_day_bonus": 60, "bonus_group": "video"},
    )
    await _tick(hass, household, freezer, _at(half, 0, 6))
    assert [c.data for c in pin] == [
        {"entity_id": SWITCH, "scope": "today", "start_time": "08:10", "end_time": "12:00"}
    ]
    assert limit[0].data == {"child_id": "42", "daily_minutes": 180}
    assert hass.states.get("number.hearth_sam_video_bonus_today").state == "60"
    await _tick(hass, household, freezer, _at(half, 0, 7))
    assert len(pin) == 1 and len(limit) == 1


async def test_school_time_off_from_noon_and_the_watchdog(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    off = async_mock_service(hass, "switch", "turn_off")
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "familylink", "set_school_time")
    monday = date(2026, 11, 9)
    household = await _set_up(
        hass, hass_client_no_auth, freezer, _at(monday, 9), YEAR, {"watchdog": "10:00:00"}
    )
    answer = await hass.services.async_call(
        DOMAIN,
        "school_time_off",
        {"people": ["person.sam"], "from": "12:00", "reason": "Field trip"},
        blocking=True,
        return_response=True,
    )
    assert len(answer["ids"]) == 1
    await _tick(hass, household, freezer, _at(monday, 11, 59))
    assert off == []
    await _tick(hass, household, freezer, _at(monday, 12))
    assert [c.data for c in off] == [{"entity_id": SWITCH}]

    # Tuesday at 10:00 School time is still off (it couldn't be put back): the adults are told, once
    told: list[str] = []
    household.scheduler.tell = lambda title, message, _id: told.append(message)
    hass.states.async_set(SWITCH, "off")
    household.scheduler.offs.clear()
    await _tick(hass, household, freezer, _at(monday + timedelta(days=1), 9, 59))
    assert told == []
    await _tick(hass, household, freezer, _at(monday + timedelta(days=1), 10))
    await _tick(hass, household, freezer, _at(monday + timedelta(days=1), 10, 1))
    assert told == ["Family Link School time is still off for Sam. Check Family Link."]


async def test_school_time_off_can_be_cancelled(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    off = async_mock_service(hass, "switch", "turn_off")
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(monday, 9), YEAR, {})
    await hass.services.async_call(
        DOMAIN, "school_time_off", {"people": ["person.sam"], "date": "2026-11-12"}, blocking=True
    )
    await hass.services.async_call(DOMAIN, "school_time_off_cancel", {"people": ["person.sam"]}, blocking=True)
    await hass.async_block_till_done()
    assert household.scheduler.offs == {}
    assert off == []


async def test_the_website_list_syncs_each_person_and_one_failure_doesn_t_stop_the_rest(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls: list[ServiceCall] = []

    async def sync(call: ServiceCall) -> None:
        calls.append(call)
        if call.data["entity_id"] == "sensor.alex_family_link_daily_screen_time":
            raise HomeAssistantError("list unreachable")

    hass.services.async_register("familylink", "sync_site_list", sync)
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(monday, 7), YEAR, {})
    _family_link_entities(hass, "7", "alex")
    await _option(hass, "enforce", {"person": "person.alex", "family_link": "sensor.alex_family_link_daily_screen_time"})
    await _option(hass, "site_list", {"url": URL, "time": "07:30:00"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    await _tick(hass, household, freezer, _at(monday, 7, 29))
    assert calls == []
    await _tick(hass, household, freezer, _at(monday, 7, 30))
    assert sorted(c.data["entity_id"] for c in calls) == [
        "sensor.alex_family_link_daily_screen_time",
        FAMILY_LINK,
    ]
    assert all(c.data["url"] == URL for c in calls)
    await _tick(hass, household, freezer, _at(monday, 7, 31))
    assert len(calls) == 2  # Sam's is done for today; Alex's waits before it's tried again


async def test_the_website_list_syncs_family_safety_too_on_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    fl_calls: list[ServiceCall] = []
    fs_calls: list[ServiceCall] = []

    async def fl_sync(call: ServiceCall) -> None:
        fl_calls.append(call)

    async def fs_sync(call: ServiceCall) -> None:
        fs_calls.append(call)
        if len(fs_calls) == 1:
            raise HomeAssistantError("Microsoft said no")

    hass.services.async_register("familylink", "sync_site_list", fl_sync)
    hass.services.async_register("microsoft_family_safety", "sync_site_list", fs_sync)
    events = async_capture_events(hass, "hearth_schedule")
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(monday, 7), YEAR, {})
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "family_safety": "sensor.sam_xbox_screen_time"},
    )
    # Alex has Family Safety only, by a typed-in account id
    await _add_enforcer(hass, {"kind": "family_safety", "person": "person.alex", "entity_id": "123456"})
    await _option(hass, "site_list", {"url": URL, "time": "07:30:00"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    await _tick(hass, household, freezer, _at(monday, 7, 30))
    assert [c.data for c in fl_calls] == [{"entity_id": FAMILY_LINK, "url": URL}]
    # Alex first (sorted), whose call fails; Sam's still goes
    assert [c.data for c in fs_calls] == [
        {"account_id": "123456", "url": URL},
        {"entity_id": "sensor.sam_xbox_screen_time", "url": URL},
    ]
    seen = [(e.data["action"], e.data["person"], e.data["via"]) for e in events]
    assert ("site_list", "person.sam", "family_link") in seen
    assert ("site_list", "person.sam", "family_safety") in seen
    assert ("site_list_failed", "person.alex", "family_safety") in seen

    await _tick(hass, household, freezer, _at(monday, 7, 31))
    assert len(fs_calls) == 2  # Alex's waits before it's tried again
    await _tick(hass, household, freezer, _at(monday, 7, 40))
    assert len(fs_calls) == 3 and fs_calls[2].data["account_id"] == "123456"
    assert len(fl_calls) == 1
    await _tick(hass, household, freezer, _at(monday, 7, 50))
    assert len(fs_calls) == 3


async def test_the_website_list_skips_an_older_family_safety_quietly(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    fl_calls = async_mock_service(hass, "familylink", "sync_site_list")
    events = async_capture_events(hass, "hearth_schedule")
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(monday, 7), YEAR, {})
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "family_safety": "sensor.sam_xbox_screen_time"},
    )
    await _option(hass, "site_list", {"url": URL, "time": "07:30:00"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    await _tick(hass, household, freezer, _at(monday, 7, 30))
    assert len(fl_calls) == 1
    assert [e.data["via"] for e in events] == ["family_link"]


async def test_the_website_list_must_be_https(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "site_list"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"url": "http://example.com/x"})
    assert result["errors"] == {"url": "not_https"}


async def test_a_chore_checked_off_adds_its_minutes_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    async_mock_service(
        hass,
        "todo",
        "get_items",
        response={
            "todo.sam_chores": {
                "items": [
                    {"uid": "1", "summary": "Dishes +30", "status": "completed"},
                    {"uid": "2", "summary": "Bed", "status": "completed"},
                ]
            }
        },
        supports_response=SupportsResponse.ONLY,
    )
    removed = async_mock_service(hass, "todo", "remove_item")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("todo.sam_chores", "2")
    await _option(hass, "chores", {"person": "person.sam", "todo": "todo.sam_chores", "group": "video", "minutes": 15})
    hass.states.async_set("todo.sam_chores", "0")
    await hass.async_block_till_done()
    assert sorted(c.data["item"] for c in removed) == ["1", "2"]
    assert hass.states.get("number.hearth_sam_video_bonus_today").state == "45"


async def test_the_adults_are_offered_more_when_a_group_runs_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "offer_more", {"person": "person.sam", "groups": ["video"], "minutes": "30"})
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 10}, blocking=True
    )
    await hass.async_block_till_done()
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    [offer] = hub.asks.pending()
    assert offer.offered and offer.minutes == 30 and offer.group == "video"
    # The kid's devices aren't told about it as a request of theirs
    assert hub.asks.latest_for("person.sam") is None
    hub.asks.answer(offer.id, 30, None)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "30"
