"""School days: which budget applies, from typed-in dates, an entity, a calendar, or Monday to Friday."""

from datetime import date

from homeassistant.core import HomeAssistant, SupportsResponse
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.schooldays import SchoolDays, by_rule, parse_dates, SchoolDaysConfig
from test_people import _household_with_sam
from test_sources import _option

MONDAY = date(2026, 10, 26)
SATURDAY = date(2026, 10, 24)


def test_dates_and_ranges():
    assert parse_dates("2026-11-26, 2026-12-30..2027-01-01\n2027-01-18; nonsense") == {
        date(2026, 11, 26),
        date(2026, 12, 30),
        date(2026, 12, 31),
        date(2027, 1, 1),
        date(2027, 1, 18),
    }
    assert parse_dates("") == set()


def test_the_rule_is_weekdays_within_the_school_year():
    config = SchoolDaysConfig(year_start=date(2026, 8, 31), year_end=date(2027, 6, 14))
    assert by_rule(config, MONDAY)
    assert not by_rule(config, SATURDAY)
    assert not by_rule(config, date(2027, 7, 6))  # summer


async def test_the_order(hass: HomeAssistant) -> None:
    school = SchoolDays(hass)
    school.configure(
        {
            "school_days": {
                "entity": "input_select.day_type",
                "school_states": "school",
                "days_off": "2026-10-26",
            }
        }
    )
    hass.states.async_set("input_select.day_type", "school")
    assert school.decide(MONDAY) == (False, "date")  # typed-in dates first
    assert school.decide(date(2026, 10, 27)) == (True, "entity")
    hass.states.async_set("input_select.day_type", "half")
    assert school.decide(date(2026, 10, 27)) == (False, "entity")
    hass.states.async_set("input_select.day_type", "unavailable")
    assert school.decide(date(2026, 10, 27)) == (True, "rule")  # passed on


async def test_a_calendar_of_days_off(hass: HomeAssistant) -> None:
    events = {"calendar.school": {"events": [{"summary": "Schools closed for students"}]}}
    async_mock_service(hass, "calendar", "get_events", response=events, supports_response=SupportsResponse.ONLY)
    school = SchoolDays(hass)
    school.configure({"school_days": {"calendar": "calendar.school", "keywords": "closed, break"}})
    await school.async_refresh(MONDAY)
    assert (school.school, school.reason) == (False, "calendar")


async def test_a_calendar_event_without_the_words_is_a_school_day(hass: HomeAssistant) -> None:
    events = {"calendar.school": {"events": [{"summary": "Picture day"}]}}
    async_mock_service(hass, "calendar", "get_events", response=events, supports_response=SupportsResponse.ONLY)
    school = SchoolDays(hass)
    school.configure({"school_days": {"calendar": "calendar.school", "keywords": "closed, break"}})
    await school.async_refresh(MONDAY)
    assert school.school


async def test_an_unreadable_calendar_leaves_it_to_the_rule(hass: HomeAssistant) -> None:
    school = SchoolDays(hass)
    school.configure({"school_days": {"calendar": "calendar.missing"}})
    await school.async_refresh(MONDAY)
    assert (school.school, school.reason) == (True, "rule")


async def test_the_budget_follows_the_school_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 30, "days": "school_days"},
        blocking=True,
    )
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 90, "days": "other_days"},
        blocking=True,
    )
    hass.states.async_set("input_select.day_type", "off")
    await _option(hass, "school_days", {"entity": "input_select.day_type", "school_states": "school"})
    assert hass.states.get("binary_sensor.hearth_home_school_day").state == "off"
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "80"  # 90 less the 10 watched

    hass.states.async_set("input_select.day_type", "school")
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.hearth_home_school_day").state == "on"
    assert hass.states.get("binary_sensor.hearth_home_school_day").attributes["decided_by"] == "entity"
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "20"
