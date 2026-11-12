"""The schedule: day types, School time off on a day off and back inside the window, half days, extra time, the
website list, chores and offering more time."""

from datetime import date, datetime, timedelta

import pytest
import voluptuous as vol

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


async def test_an_adult_s_app_is_offered_no_school_time_today_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from custom_components.hearth.websocket import summary

    async_mock_service(hass, "switch", "turn_off")
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(monday, 9), YEAR, {})
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data

    def sam():
        return next(p for p in summary(hub)["people"] if p["id"] == "person.sam")

    assert sam()["school_time"]["end"].startswith("2026-11-09T15:00")
    [offer] = [a for a in sam()["actions"] if a["id"] == "school_off"]
    assert offer["service"] == "hearth.school_time_off" and offer["data"] == {"people": ["person.sam"]}
    assert offer["confirm"] == "no school time today for sam?"

    # Once it's off today, not again
    await hass.services.async_call(DOMAIN, "school_time_off", {"people": ["person.sam"]}, blocking=True)
    assert not [a for a in sam()["actions"] if a["id"] == "school_off"]
    household.scheduler.offs.clear()
    # After School time ends, and on a weekend, nothing
    freezer.move_to(_at(monday, 15, 1))
    assert not [a for a in sam()["actions"] if a["id"] == "school_off"]
    freezer.move_to(_at(date(2026, 11, 14), 9))
    assert "school_time" not in sam()


# Family Safety (Windows, Xbox): the day's extra minutes as a today-only daily limit

FAMILY_SAFETY = "sensor.sam_family_safety"
ALEX_FS = "sensor.alex_family_safety"
_TARGET = {vol.Optional("entity_id"): str, vol.Optional("account_id"): str}
_PLATFORM = {vol.Optional("platform", default="Windows"): vol.In(["Windows", "Xbox"])}
# A newer Family Safety: today_only, and a child's entity as target
NEW_LIMIT = vol.Schema(
    {
        **_TARGET,
        **_PLATFORM,
        vol.Optional("today_only", default=False): bool,
        vol.Optional("day_of_week"): vol.All(int, vol.Range(min=0, max=6)),
        vol.Required("hours"): vol.All(int, vol.Range(min=0, max=24)),
        vol.Optional("minutes", default=0): vol.All(int, vol.Range(min=0, max=59)),
    }
)
NEW_INTERVALS = vol.Schema(
    {
        **_TARGET,
        **_PLATFORM,
        vol.Optional("today_only", default=False): bool,
        vol.Optional("day_of_week"): int,
        vol.Required("start_hour"): int,
        vol.Optional("start_minute", default=0): vol.In([0, 30]),
        vol.Required("end_hour"): int,
        vol.Optional("end_minute", default=0): vol.In([0, 30]),
    }
)
RESTORE = vol.Schema({**_TARGET, vol.Optional("platform"): vol.In(["Windows", "Xbox"])})
# An older one: a weekday's limit by account id only
OLD_LIMIT = vol.Schema(
    {
        vol.Required("account_id"): str,
        **_PLATFORM,
        vol.Required("day_of_week"): int,
        vol.Required("hours"): int,
        vol.Optional("minutes", default=0): int,
    }
)


def _family_safety_entities(
    hass: HomeAssistant, name: str, account: str, limits: dict[str, int], pending: dict | None = None
) -> None:
    hass.states.async_set(f"sensor.{name}_family_safety", name.title(), {"user_id": account})
    for platform, allowance in limits.items():
        hass.states.async_set(
            f"binary_sensor.{name}_{platform.lower()}_allowed_now",
            "on",
            {
                "user_id": account,
                "platform": platform,
                "reason": "within_limits",
                "allowance_minutes": allowance,
                "used_minutes": 0,
                "hold": "none",
            },
        )
    hass.states.async_set(
        f"sensor.{name}_screen_time_policy", "enabled", {"user_id": account, "today_only": pending or {}}
    )


def _family_safety_services(hass: HomeAssistant, limit_schema=NEW_LIMIT, fail=None):
    """The limit calls (one that [fail] says yes to raises), the interval calls and the restore calls."""
    limits: list[ServiceCall] = []

    async def set_limit(call: ServiceCall) -> None:
        limits.append(call)
        if fail is not None and fail(call.data):
            raise HomeAssistantError("Microsoft said no")

    hass.services.async_register("microsoft_family_safety", "set_screentime_limit", set_limit, schema=limit_schema)
    intervals = async_mock_service(hass, "microsoft_family_safety", "set_screentime_intervals", schema=NEW_INTERVALS)
    restores = async_mock_service(hass, "microsoft_family_safety", "restore_today_only", schema=RESTORE)
    return limits, intervals, restores


async def _with_family_safety(hass, hass_client_no_auth, freezer, now, school, schedule, platforms):
    household = await _set_up(hass, hass_client_no_auth, freezer, now, school, schedule)
    await _option(
        hass,
        "enforce",
        {
            "person": "person.sam",
            "family_link": FAMILY_LINK,
            "school_time_apps": [],
            "family_safety": FAMILY_SAFETY,
            "platforms": platforms,
        },
    )
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def test_a_day_off_raises_family_safety_s_limits_today_only_and_its_cancel_puts_them_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "switch", "turn_off")
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "familylink", "set_school_time")
    fl_limit = async_mock_service(hass, "familylink", "set_daily_limit")
    limits, intervals, restores = _family_safety_services(hass)
    events = async_capture_events(hass, "hearth_schedule")
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_school_time_off": True, "day_off_bonus": 60},
        ["Windows", "Xbox"],
    )
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120, "Xbox": 60})
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert [c.data for c in fl_limit] == [{"child_id": "42", "daily_minutes": 180}]
    # Each platform: today's limit plus the extra hour, today only, the child's entity as target
    assert sorted((c.data["platform"], c.data["hours"], c.data["minutes"]) for c in limits) == [
        ("Windows", 3, 0),
        ("Xbox", 2, 0),
    ]
    assert all(c.data["entity_id"] == FAMILY_SAFETY and c.data["today_only"] for c in limits)
    assert all("day_of_week" not in c.data for c in limits)
    # A day off doesn't change Family Link's bedtime: nor the allowed hours
    assert intervals == []
    fs_events = [e.data for e in events if e.data.get("via") == "family_safety"]
    assert sorted((e["action"], e["platform"], e["daily_minutes"]) for e in fs_events) == [
        ("bonus", "Windows", 180),
        ("bonus", "Xbox", 120),
    ]
    await _tick(hass, household, freezer, _at(day_off, 0, 7))
    assert len(limits) == 2  # once a day

    # The day off is called off: Family Safety's limits go back now, and aren't set again
    await hass.services.async_call(DOMAIN, "school_time_off_cancel", {"people": ["person.sam"]}, blocking=True)
    await hass.async_block_till_done()
    await _tick(hass, household, freezer, _at(day_off, 9))
    assert sorted((c.data["entity_id"], c.data["platform"]) for c in restores) == [
        (FAMILY_SAFETY, "Windows"),
        (FAMILY_SAFETY, "Xbox"),
    ]
    await _tick(hass, household, freezer, _at(day_off, 9, 1))
    assert len(restores) == 2 and len(limits) == 2
    assert [e.data["action"] for e in events].count("bonus_back") == 2


async def test_a_half_day_s_extra_reaches_an_xbox_as_its_limit_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "set_school_time")
    async_mock_service(hass, "familylink", "set_daily_limit")
    limits, intervals, restores = _family_safety_services(hass)
    half = date(2026, 11, 25)
    # A parent already cut today's limit for today only: the extra goes on top of their cut, not on what midnight
    # puts back
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(half, 0, 1),
        {**YEAR, "half_days": "2026-11-25"},
        {"half_day_hours_early": 3, "half_day_bonus": 90},
        ["Xbox"],
    )
    _family_safety_entities(
        hass,
        "sam",
        "123456",
        {"Xbox": 30},
        {"Xbox": {"date": half.isoformat(), "limit_minutes": 30, "restore_limit_minutes": 45}},
    )
    await _tick(hass, household, freezer, _at(half, 0, 6))
    assert [c.data for c in limits] == [
        {"entity_id": FAMILY_SAFETY, "platform": "Xbox", "today_only": True, "hours": 2, "minutes": 0}
    ]
    assert intervals == [] and restores == []
    # A cancel on a half day has no day off to call off: the extra stays
    await hass.services.async_call(DOMAIN, "school_time_off_cancel", {"people": ["person.sam"]}, blocking=True)
    await _tick(hass, household, freezer, _at(half, 9))
    assert restores == [] and len(limits) == 1


async def test_hearth_s_own_today_only_limit_isn_t_added_to_again_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(hass)
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 60},
        ["Windows"],
    )
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120})
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert [(c.data["hours"], c.data["minutes"]) for c in limits] == [(3, 0)]
    assert household.scheduler.fs_limits == {"person.sam": {"Windows": {"target": 180, "base": 120}}}
    # Family Safety now says Hearth's own today-only change; the marks were lost (a restart before they were saved)
    _family_safety_entities(
        hass,
        "sam",
        "123456",
        {"Windows": 180},
        {"Windows": {"date": day_off.isoformat(), "limit_minutes": 180, "restore_limit_minutes": 120}},
    )
    household.scheduler.marks.pop("person.sam", None)
    await _tick(hass, household, freezer, _at(day_off, 0, 7))
    assert len(limits) == 1


async def test_a_parent_s_today_only_raise_gets_the_extra_on_top(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(hass)
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 30},
        ["Windows"],
    )
    _family_safety_entities(
        hass,
        "sam",
        "123456",
        {"Windows": 150},
        {"Windows": {"date": day_off.isoformat(), "limit_minutes": 150, "restore_limit_minutes": 120}},
    )
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert [(c.data["hours"], c.data["minutes"]) for c in limits] == [(3, 0)]
    assert household.scheduler.fs_limits["person.sam"]["Windows"] == {"target": 180, "base": 150}


async def test_an_older_family_safety_without_today_only_is_skipped_quietly(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "switch", "turn_off")
    fl_limit = async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(hass, OLD_LIMIT)
    events = async_capture_events(hass, "hearth_schedule")
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 60},
        ["Windows", "Xbox"],
    )
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120, "Xbox": 60})
    told: list[str] = []
    household.scheduler.tell = lambda title, message, _id: told.append(message)
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    await _tick(hass, household, freezer, _at(day_off, 6))
    assert limits == [] and len(fl_limit) == 1
    assert not [e for e in events if e.data.get("via") == "family_safety"]
    assert told == []


async def test_one_family_safety_failure_doesn_t_stop_family_link_or_another_kid(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    fl_limit = async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(
        hass, fail=lambda data: data.get("entity_id") == FAMILY_SAFETY and data["platform"] == "Windows"
    )
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off, 0, 1),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 30},
        ["Windows", "Xbox"],
    )
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120, "Xbox": 60})
    _family_safety_entities(hass, "alex", "654321", {"Xbox": 90})
    await _add_enforcer(
        hass, {"kind": "family_safety", "person": "person.alex", "entity_id": ALEX_FS, "platforms": ["Xbox"]}
    )
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    told: list[str] = []
    household.scheduler.tell = lambda title, message, _id: told.append(message)
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert len(fl_limit) == 1
    assert sorted((c.data["entity_id"], c.data["platform"], c.data["hours"], c.data["minutes"]) for c in limits) == [
        (ALEX_FS, "Xbox", 2, 0),
        (FAMILY_SAFETY, "Windows", 2, 30),
        (FAMILY_SAFETY, "Xbox", 1, 30),
    ]
    # Tried again after a while, only the one that failed
    await _tick(hass, household, freezer, _at(day_off, 0, 7))
    assert len(limits) == 3
    await _tick(hass, household, freezer, _at(day_off, 0, 12))
    assert len(limits) == 4 and limits[-1].data["platform"] == "Windows"
    # Still failing at the morning check: the adults are told
    await _tick(hass, household, freezer, _at(day_off, 6))
    assert told == ["Sam's Windows extra time couldn't be set. Check Family Safety."]

async def test_family_safety_s_limit_waits_for_its_first_read_after_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(hass)
    events = async_capture_events(hass, "hearth_schedule")
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off - timedelta(days=1), 23, 50),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 60},
        ["Windows"],
    )
    # Last read yesterday, when yesterday's limit was 30
    _family_safety_entities(hass, "sam", "123456", {"Windows": 30})
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    await _tick(hass, household, freezer, _at(day_off, 0, 7))
    assert limits == []
    assert not [e for e in events if e.data.get("via") == "family_safety"]
    # Family Safety's first poll of the day says today's: then it applies, once
    freezer.move_to(_at(day_off, 0, 8))
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120})
    await _tick(hass, household, freezer, _at(day_off, 0, 8))
    await _tick(hass, household, freezer, _at(day_off, 0, 9))
    assert [c.data for c in limits] == [
        {"entity_id": FAMILY_SAFETY, "platform": "Windows", "today_only": True, "hours": 3, "minutes": 0}
    ]


async def test_a_poll_that_changes_nothing_still_counts_as_today_s_read(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "set_daily_limit")
    limits, _intervals, _restores = _family_safety_services(hass)
    day_off = date(2026, 11, 26)
    household = await _with_family_safety(
        hass,
        hass_client_no_auth,
        freezer,
        _at(day_off - timedelta(days=1), 23, 50),
        {**YEAR, "days_off": "2026-11-26"},
        {"day_off_bonus": 60},
        ["Windows"],
    )
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120})
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    assert limits == []
    # The same state written again after midnight (last_reported moves, last_updated doesn't)
    freezer.move_to(_at(day_off, 0, 8))
    _family_safety_entities(hass, "sam", "123456", {"Windows": 120})
    await _tick(hass, household, freezer, _at(day_off, 0, 8))
    assert [(c.data["hours"], c.data["minutes"]) for c in limits] == [(3, 0)]
