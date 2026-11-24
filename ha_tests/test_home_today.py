"""A kid kept home on a school day (hearth.home_today), and each kid's School today sensor."""

from datetime import date

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_schedule import SWITCH, YEAR, _at, _set_up, _tick

SCHOOL_TODAY = "sensor.hearth_sam_school_today"
MONDAY = date(2026, 11, 9)


async def _kid(hass: HomeAssistant, hass_client_no_auth, freezer, now, school=YEAR):
    household = await _set_up(hass, hass_client_no_auth, freezer, now, school, {})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {"person.sam": "kid"}})
    await hass.async_block_till_done()
    household = entry.runtime_data.household
    for group, school_days, other_days in (("all", 60, 180),):
        for days, minutes in (("school_days", school_days), ("other_days", other_days)):
            await hass.services.async_call(
                DOMAIN, "set_budget", {"person": "person.sam", "group": group, "minutes": minutes, "days": days},
                blocking=True,
            )
    household.recompute()
    await hass.async_block_till_done()
    return household


def _left(hass: HomeAssistant) -> str:
    return hass.states.get("sensor.hearth_sam_all_screen_time_minutes_left").state


async def test_school_today_says_the_day_and_family_link_s_window(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _kid(hass, hass_client_no_auth, freezer, _at(MONDAY, 7))
    state = hass.states.get(SCHOOL_TODAY)
    assert state.state == "school"
    assert state.attributes["person"] == "person.sam"
    assert state.attributes["window_source"] == "family_link"
    assert state.attributes["start"].startswith("2026-11-09T08:10:00")
    assert state.attributes["end"].startswith("2026-11-09T15:00:00")
    # The other per-person entities say whose they are too
    assert hass.states.get("binary_sensor.hearth_sam_locked").attributes["person"] == "person.sam"
    assert hass.states.get("sensor.hearth_sam_mode").attributes["person"] == "person.sam"
    assert hass.states.get("sensor.hearth_sam_bedtime").attributes["person"] == "person.sam"
    assert hass.states.get("sensor.hearth_sam_place").attributes["person"] == "person.sam"
    assert state.attributes["decided_by"] == "rule"


async def test_a_weekend_is_off_without_a_window(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _kid(hass, hass_client_no_auth, freezer, _at(date(2026, 11, 14), 9))
    state = hass.states.get(SCHOOL_TODAY)
    assert state.state == "off"
    assert state.attributes["start"] is None and state.attributes["window_source"] is None


async def test_a_half_day_s_window_ends_early(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _kid(hass, hass_client_no_auth, freezer, _at(MONDAY, 7), {**YEAR, "half_days": "2026-11-09"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "schedule": {"half_day_hours_early": 3}})
    await hass.async_block_till_done()
    household = entry.runtime_data.household
    household.recompute()
    await hass.async_block_till_done()
    state = hass.states.get(SCHOOL_TODAY)
    assert state.state == "half_day"
    assert state.attributes["end"].startswith("2026-11-09T12:00:00")


async def test_home_today_is_a_day_off_for_that_kid_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    off = async_mock_service(hass, "switch", "turn_off")
    on = async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "familylink", "set_school_time")
    household = await _kid(hass, hass_client_no_auth, freezer, _at(MONDAY, 7))
    school_day_left = int(_left(hass))

    answer = await hass.services.async_call(
        DOMAIN, "home_today", {"people": ["person.sam"], "reason": "Sick"}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    assert answer["people"] == ["person.sam"] and len(answer["school_time_off"]) == 1
    state = hass.states.get(SCHOOL_TODAY)
    assert state.state == "home_today"
    assert state.attributes["decided_by"] == "home_today" and state.attributes["reason"] == "Sick"
    assert state.attributes["start"] is None
    # The other days' budget, School time off for the day; the household's day stays a school day
    assert int(_left(hass)) == school_day_left + 120
    assert [c.data for c in off] == [{"entity_id": SWITCH}]
    assert hass.states.get("sensor.hearth_home_day_type").state == "school"
    assert household.day_type_of("person.sam", MONDAY) == "day_off"
    assert hass.states.get("sensor.hearth_sam_screen_time_today").attributes["exceptions"]["home_today"] == [
        {"date": "2026-11-09", "reason": "Sick"}
    ]

    # Better after all: a school day again, School time back inside the window
    hass.states.async_set(SWITCH, "off")
    answer = await hass.services.async_call(
        DOMAIN, "home_today_cancel", {"people": ["person.sam"]}, blocking=True, return_response=True
    )
    assert answer == {"people": ["person.sam"]}
    await _tick(hass, household, freezer, _at(MONDAY, 9))
    assert hass.states.get(SCHOOL_TODAY).state == "school"
    assert int(_left(hass)) == school_day_left
    assert [c.data for c in on] == [{"entity_id": SWITCH}]


async def test_home_today_ends_with_its_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "switch", "turn_off")
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "familylink", "set_school_time")
    household = await _kid(hass, hass_client_no_auth, freezer, _at(MONDAY, 7))
    await hass.services.async_call(DOMAIN, "home_today", {"people": ["person.sam"]}, blocking=True)
    await _tick(hass, household, freezer, _at(date(2026, 11, 10), 0, 6))
    household.recompute()
    await hass.async_block_till_done()
    assert household.scheduler.home == {}
    assert hass.states.get(SCHOOL_TODAY).state == "school"


async def test_home_today_needs_a_school_day_that_hasn_t_passed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _kid(hass, hass_client_no_auth, freezer, _at(MONDAY, 7))
    with pytest.raises(ServiceValidationError, match="isn't a school day"):
        await hass.services.async_call(
            DOMAIN, "home_today", {"people": ["person.sam"], "date": "2026-11-14"}, blocking=True
        )
    with pytest.raises(ServiceValidationError, match="passed"):
        await hass.services.async_call(
            DOMAIN, "home_today", {"people": ["person.sam"], "date": "2026-11-06"}, blocking=True
        )
