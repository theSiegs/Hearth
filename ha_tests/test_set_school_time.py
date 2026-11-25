"""hearth.set_school_time: a kid's weekly Family Link School time hours (given, or like another kid's), and School time
switched on inside the next school day's window, as a School time off is put back."""

from datetime import date

import pytest

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers import entity_registry as er
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_schedule import SENSOR, SWITCH, YEAR, _at, _family_link_entities, _set_up, _tick, settled  # noqa: F401
from test_sources import _option

ALEX_SWITCH = "switch.alex_school_time"


async def _call(hass: HomeAssistant, data: dict) -> dict:
    response = await hass.services.async_call(DOMAIN, "set_school_time", data, blocking=True, return_response=True)
    await hass.async_block_till_done()
    return response


def _alex_hours(hass: HomeAssistant, iso: int, start: str, end: str) -> None:
    registry = er.async_get(hass)
    for bound, value in (("start", start), ("end", end)):
        entity_id = registry.async_get_entity_id("time", "familylink", f"familylink_7_schooltime_{iso}_{bound}")
        hass.states.async_set(entity_id, value, {"child_id": "7"})


async def _with_alex(hass: HomeAssistant, hass_client_no_auth, freezer, now):
    household = await _set_up(hass, hass_client_no_auth, freezer, now, YEAR, {})
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    _family_link_entities(hass, "7", "alex")
    await _option(hass, "add_source", {"entity_id": "sensor.alex_family_link_daily_screen_time", "person": "person.alex"})
    await _option(hass, "enforce", {"person": "person.alex", "family_link": "sensor.alex_family_link_daily_screen_time"})
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def test_hours_like_another_kid_s_are_written_for_the_days_that_differ(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    written = async_mock_service(hass, "familylink", "set_school_time")
    household = await _with_alex(hass, hass_client_no_auth, freezer, _at(date(2026, 11, 25), 10))
    assert "person.alex" in household.people()
    # Alex: 9:00 to 16:15 on Monday to Thursday, Sam's own 8:10 to 15:00 on Friday; no School time on Saturday
    for iso in range(1, 5):
        _alex_hours(hass, iso, "09:00:00", "16:15:00")
    _alex_hours(hass, 6, "unknown", "unknown")

    answer = await _call(hass, {"people": ["person.sam"], "like": "person.alex", "days": ["school_days", "sat"]})
    sam = answer["people"]["person.sam"]
    assert sam["set"] == {d: "09:00-16:15" for d in ("mon", "tue", "wed", "thu")}
    assert sam["same"] == ["fri"]
    assert set(sam["skipped"]) == {"sat"}
    assert sorted((c.data["day"], c.data["start_time"], c.data["end_time"]) for c in written) == [
        (str(iso), "09:00", "16:15") for iso in range(1, 5)
    ]
    # The weekly slot: no today scope, Sam's own School time switch as the child's entity
    assert all(c.data["entity_id"] == SWITCH and "scope" not in c.data for c in written)
    # Hearth's own calls, in its action log
    logged = household.activity.query("person.sam", "call", limit=50)
    assert sum(1 for r in logged if r.get("service") == "familylink.set_school_time" and r.get("why") == "school_hours") == 4


async def test_switched_on_only_inside_the_next_school_day_s_window_and_pinned(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """switch.turn_on alone opens School time until 23:59: it's put on inside the window and today's hours pinned."""
    on = async_mock_service(hass, "switch", "turn_on")
    pin = async_mock_service(hass, "familylink", "set_school_time")
    saturday, monday = date(2026, 11, 28), date(2026, 11, 30)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(saturday, 10), YEAR, {})
    hass.states.async_set(SWITCH, "off")

    answer = await _call(hass, {"people": ["person.sam"], "switch_on": True})
    assert answer["people"]["person.sam"]["switch_on"] == saturday.isoformat()
    await _tick(hass, household, freezer, _at(saturday, 10, 5))
    assert on == []  # not a school day

    # Kept over a restart
    await household.scheduler.async_flush()
    household.scheduler.turn_on = {}
    await household.scheduler.async_load()
    assert household.scheduler.turn_on == {"person.sam": saturday.isoformat()}

    await _tick(hass, household, freezer, _at(monday, 7, 30))
    assert on == []  # before the window
    await _tick(hass, household, freezer, _at(monday, 8, 15))
    assert [c.data for c in on] == [{"entity_id": SWITCH}]
    assert pin[-1].data == {"entity_id": SWITCH, "scope": "today", "start_time": "08:10", "end_time": "15:00"}
    hass.states.async_set(SWITCH, "on")
    hass.states.async_set(SENSOR, "on", {"child_id": "42", "schooltime_end": "2026-11-30T15:00:00"})
    await _tick(hass, household, freezer, _at(monday, 8, 20))
    assert household.scheduler.turn_on == {}
    assert len(on) == 1


async def test_already_on_is_said_and_nothing_waits(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    on = async_mock_service(hass, "switch", "turn_on")
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(date(2026, 11, 30), 9), YEAR, {})
    answer = await _call(hass, {"people": ["person.sam"], "switch_on": True})
    assert answer["people"]["person.sam"]["switch_on"] == "already"
    assert household.scheduler.turn_on == {} and on == []


async def test_given_hours_and_what_s_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls: list[ServiceCall] = []

    async def write(call: ServiceCall) -> None:
        calls.append(call)
        if call.data["day"] == "2":
            raise HomeAssistantError("Tuesday has no School time in Family Link")

    hass.services.async_register("familylink", "set_school_time", write)
    await _set_up(hass, hass_client_no_auth, freezer, _at(date(2026, 11, 25), 10), YEAR, {})
    answer = await _call(hass, {"people": ["person.sam"], "days": ["mon", "tue", "wed"], "start": "08:30", "end": "14:45"})
    sam = answer["people"]["person.sam"]
    # One day failing doesn't stop the others
    assert sam["set"] == {"mon": "08:30-14:45", "wed": "08:30-14:45"}
    assert "School time" in sam["failed"]["tue"]
    assert len(calls) == 3

    with pytest.raises(ServiceValidationError, match="after it starts"):
        await _call(hass, {"people": ["person.sam"], "start": "15:00", "end": "08:00"})
    with pytest.raises(ServiceValidationError, match="Give hours"):
        await _call(hass, {"people": ["person.sam"]})
    with pytest.raises(ServiceValidationError, match="not both"):
        await _call(hass, {"people": ["person.sam"], "start": "08:00", "end": "15:00", "like": "person.sam"})


async def test_a_switch_on_right_after_new_hours_pins_the_new_hours_on_a_half_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link's time entities show the old hours until its next refresh: a switch-on right after hours were
    written pins the hours just written (less a half day's hours), not the old ones."""
    on = async_mock_service(hass, "switch", "turn_on")
    pin = async_mock_service(hass, "familylink", "set_school_time")
    half_day = date(2026, 11, 25)
    await _set_up(
        hass, hass_client_no_auth, freezer, _at(half_day, 10), {**YEAR, "half_days": "2026-11-25"},
        {"half_day_hours_early": 3},
    )
    hass.states.async_set(SWITCH, "off")

    # Sam's weekly hours read 8:10 to 15:00 and still do after the write (no refresh yet)
    answer = await _call(
        hass, {"people": ["person.sam"], "days": ["wed"], "start": "09:00", "end": "16:15", "switch_on": True}
    )
    assert answer["people"]["person.sam"]["set"] == {"wed": "09:00-16:15"}
    assert [c.data for c in on] == [{"entity_id": SWITCH}]
    assert pin[-1].data == {"entity_id": SWITCH, "scope": "today", "start_time": "09:00", "end_time": "13:15"}
