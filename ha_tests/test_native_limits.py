"""The parents' own daily limits next to Hearth's budgets (native_limits.py): per kid, platform and weekday below,
covered, ok or none; hearth.explain's rows; one notice per kid and platform, said again only when it changes. Read
only: nothing is written to a platform."""

from datetime import date

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_enforce import _add_enforcer
from test_schedule import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    SW_LIMIT,
    YEAR,
    _at,
    _budget,
    _family_safety_entities,
    _family_safety_services,
    _set_up,
    _with_family_safety,
    _with_switch,
)
from test_sources import _option

WEDNESDAY = date(2026, 11, 25)
FL_KEY = "hearth_native_limit_person.sam_family_link"
XBOX_KEY = "hearth_native_limit_person.sam_xbox"
SWITCH_KEY = f"hearth_native_limit_switch_{SW_LIMIT}"


def _days(row: dict) -> dict[str, tuple]:
    return {d["weekday"]: (d["native"], d["budget"], d["status"]) for d in row["days"]}


def _row(household, key: str, person: str = "person.sam") -> dict:
    return next(r for r in household.native_limits.rows(_at(WEDNESDAY, 12))[person] if r["key"] == key)


async def _look(hass: HomeAssistant, household, times: int = 1) -> None:
    for _ in range(times):
        household.recompute()
        household.native_limits.check(_at(WEDNESDAY, 12))
        await hass.async_block_till_done()


def _told(events, key: str) -> list[str]:
    return [e.data["change"] for e in events if e.data["key"] == key]


def _fl_limit(hass: HomeAssistant, weekday: str, minutes) -> None:
    hass.states.async_set(
        f"number.sam_family_link_{weekday}_limit", str(minutes), {"child_id": "42", "weekly_minutes": minutes}
    )


async def _family_link_household(hass, hass_client_no_auth, freezer, schedule=None, backstop=False):
    async_mock_service(hass, "familylink", "set_daily_limit")
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(WEDNESDAY, 12), YEAR, schedule or {})
    if backstop:
        await _option(
            hass, "enforce",
            {"person": "person.sam", "family_link": FAMILY_LINK, "school_time_apps": [], "fl_backstop": True},
        )
        household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    await _budget(hass, 120, "school_days")
    await _budget(hass, 180, "other_days")
    return household


async def test_family_link_below_equal_and_none_per_weekday_and_one_notice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer)
    _fl_limit(hass, "sunday", 1440)  # no limit of its own
    events = async_capture_events(hass, "hearth_notice")

    days = _days(_row(household, FL_KEY))
    assert days["wednesday"] == (120, 120, "ok")  # equal: never stops them first
    assert days["saturday"] == (120, 180, "below")
    assert days["sunday"] == (None, 180, "none")
    row = _row(household, FL_KEY)
    assert next(d for d in row["days"] if d["weekday"] == "saturday")["short"] == 60
    assert row["covered_by"] is None

    explained = household.explain("person.sam", group="all")["native_limits"]
    assert [r["key"] for r in explained] == [FL_KEY]
    lines = explained[0]["lines"]
    assert any("Saturday (120 of 180 min, 60 short)" in line for line in lines)
    assert any("no daily limit of its own on Sunday" in line and "Home Assistant is down" in line for line in lines)

    # Said once it's seen on two looks in a row; never again while the same
    await _look(hass, household)
    assert _told(events, FL_KEY) == []
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == ["shown"]
    item = household.hub.attention.item(FL_KEY)
    assert "Saturday 120 of 180 min (60 short)" in item.text and "Sunday" not in item.text
    assert "Family Link app" in item.text
    # The page has it too
    assert household.native_limits.view("person.sam")[0]["key"] == FL_KEY


async def test_a_changed_finding_is_said_again_and_a_fixed_one_taken_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer)
    events = async_capture_events(hass, "hearth_notice")
    await _look(hass, household, 2)
    assert _told(events, FL_KEY) == ["shown"]
    # Kept across a restart: not pushed again, back on the bell
    told = dict(household.native_limits.told)
    household.hub.attention.clear(FL_KEY, bell_too=True, phone=True)
    household.native_limits._seen.clear()
    await _look(hass, household)
    assert household.native_limits.told == told
    assert household.hub.attention.item(FL_KEY).phone is False

    events.clear()
    _fl_limit(hass, "saturday", 150)  # changed: said again (after two looks)
    await _look(hass, household)
    assert _told(events, FL_KEY) == []
    await _look(hass, household)
    assert _told(events, FL_KEY) == ["updated"]
    assert "Saturday 150 of 180 min (30 short)" in household.hub.attention.item(FL_KEY).text

    for weekday in ("saturday", "sunday"):
        _fl_limit(hass, weekday, 180)
    await _look(hass, household)
    assert _told(events, FL_KEY)[-1] == "cleared"
    assert FL_KEY not in household.native_limits.told


async def test_family_link_covered_by_the_backstop_or_following_is_no_notice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer, backstop=True)
    events = async_capture_events(hass, "hearth_notice")
    row = _row(household, FL_KEY)
    assert row["covered_by"] == "backstop"
    assert _days(row)["saturday"] == (120, 180, "covered")
    assert any("backstop" in line for line in row["lines"])
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == []


async def test_family_link_covered_by_following_with_the_backstop_off(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer, {"follow_family_link": True})
    events = async_capture_events(hass, "hearth_notice")
    row = _row(household, FL_KEY)
    assert row["covered_by"] == "follow_family_link"
    assert _days(row)["sunday"] == (120, 180, "covered")
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == []


async def test_unknown_values_warn_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer)
    hass.states.async_set("number.sam_family_link_monday_limit", "unavailable", {"child_id": "42"})
    events = async_capture_events(hass, "hearth_notice")
    assert _days(_row(household, FL_KEY))["monday"] == (None, 120, "unknown")
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == []
    # The daily limit switch unreadable: every day unknown
    _fl_limit(hass, "monday", 120)
    hass.states.async_set("switch.sam_daily_limit", "unavailable")
    assert {d["status"] for d in _row(household, FL_KEY)["days"]} == {"unknown"}
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == []
    # Readable again: said (two looks)
    hass.states.async_set("switch.sam_daily_limit", "on")
    await _look(hass, household, 2)
    assert _told(events, FL_KEY) == ["shown"]
    # Unknown again later: nothing taken back on a read cut short
    hass.states.async_set("number.sam_family_link_saturday_limit", "unavailable", {"child_id": "42"})
    await _look(hass, household, 2)
    assert _told(events, FL_KEY) == ["shown"]


async def test_family_link_daily_limit_off_is_none_every_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _family_link_household(hass, hass_client_no_auth, freezer)
    hass.states.async_set("switch.sam_daily_limit", "off")
    events = async_capture_events(hass, "hearth_notice")
    assert {d["status"] for d in _row(household, FL_KEY)["days"]} == {"none"}
    await _look(hass, household, 3)
    assert _told(events, FL_KEY) == []


async def _xbox(hass, hass_client_no_auth, freezer, xbox: int, follow: bool = False):
    _family_safety_services(hass)
    async_mock_service(hass, "familylink", "set_daily_limit")
    _family_safety_entities(hass, "sam", "fs-sam", {"Xbox": xbox})
    return await _with_family_safety(
        hass, hass_client_no_auth, freezer, _at(WEDNESDAY, 12), YEAR, {"follow_family_safety": follow}, ["Xbox"],
        other_days=120, school_days=120,
    )


async def test_family_safety_games_with_no_limit_falls_back_to_all_screen_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _xbox(hass, hass_client_no_auth, freezer, 90)
    events = async_capture_events(hass, "hearth_notice")
    # Games has no limit: All screen time's 120 is the Xbox's budget
    assert _days(_row(household, XBOX_KEY))["friday"] == (90, 120, "below")
    await _look(hass, household, 2)
    assert _told(events, XBOX_KEY) == ["shown"]
    text = household.hub.attention.item(XBOX_KEY).text
    assert "Monday 90 of 120 min (30 short)" in text and "follow the day's budget" in text
    # Games 60: the least of the two is the budget, the Xbox's 90 is over it
    await _budget(hass, 60, "both", "games")
    assert _days(_row(household, XBOX_KEY))["friday"] == (90, 60, "ok")
    await _look(hass, household)
    assert _told(events, XBOX_KEY) == ["shown", "cleared"]
    # An Android app isn't on the Xbox: its explain leaves the Xbox out; an Xbox app's has only it
    assert all(r["platform"] != "xbox" for r in household.explain("person.sam", app="com.example.game").get(
        "native_limits", []
    ))


async def test_family_safety_1440_is_none_and_following_covers(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _xbox(hass, hass_client_no_auth, freezer, 1440)
    assert {d["status"] for d in _row(household, XBOX_KEY)["days"]} == {"none"}
    assert any("nothing caps it while Home Assistant is down" in line for line in _row(household, XBOX_KEY)["lines"])


async def test_family_safety_following_the_budget_covers_a_lower_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household = await _xbox(hass, hass_client_no_auth, freezer, 90, follow=True)
    events = async_capture_events(hass, "hearth_notice")
    row = _row(household, XBOX_KEY)
    assert row["covered_by"] == "follow_family_safety"
    # Today's limit Hearth raised (if it did by now) still reads as the parent's 90
    assert {d["status"] for d in row["days"]} == {"covered"}
    assert {d["native"] for d in row["days"]} == {90}
    await _look(hass, household, 3)
    assert _told(events, XBOX_KEY) == []


async def test_a_shared_switch_takes_the_biggest_of_its_kids_budgets_and_one_notice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household, set_value, _ = await _with_switch(
        hass, hass_client_no_auth, freezer, _at(WEDNESDAY, 12), YEAR, {"follow_nintendo": False}, limit="120",
        other_days=60, school_days=60,
    )
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "roles": {**entry.options.get("roles", {}), "person.alex": "kid"}}
    )
    await hass.async_block_till_done()
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.alex", "entity_id": SW_LIMIT})
    await _budget(hass, 150, "both", person="person.alex")
    household = entry.runtime_data.household
    events = async_capture_events(hass, "hearth_notice")

    row = _row(household, SWITCH_KEY)
    assert row["people"] == ["person.alex", "person.sam"]
    assert _row(household, SWITCH_KEY, "person.alex") == row
    assert _days(row)["monday"] == (120, 150, "below")  # Alex's 150, not Sam's 60
    await _look(hass, household, 2)
    assert _told(events, SWITCH_KEY) == ["shown"]
    item = household.hub.attention.item(SWITCH_KEY)
    assert "Alex and Sam" in item.text and "30 short" in item.text
    assert set_value == []  # read only


async def test_a_switch_with_no_limit_is_none_and_following_covers_up_to_six_hours(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    household, _, _ = await _with_switch(
        hass, hass_client_no_auth, freezer, _at(WEDNESDAY, 12), YEAR, {}, limit="-1", other_days=400, school_days=180,
    )
    assert {d["status"] for d in _row(household, SWITCH_KEY)["days"]} == {"none"}
    hass.states.async_set(SW_LIMIT, "120")
    household.scheduler.temporary.held.clear()
    days = _days(_row(household, SWITCH_KEY))
    assert days["wednesday"][2] == "covered"  # 180: the Switch follows the budget
    assert days["saturday"][2] == "below"  # 400: over the Switch's 360, following can't reach it
