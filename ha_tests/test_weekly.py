"""The weekly schedule (weekly.py): modes, changes, per-day limits, day types, today-only changes, the migration
from the two budgets, and what Hearth holds for it."""

from datetime import date, datetime, timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.schooldays import DAY_OFF, HALF_DAY, NO_SCHOOL, SCHOOL, WEEKEND
from custom_components.hearth.weekly import (
    MAX_CHANGES,
    ScheduleError,
    Week,
    day_key_for,
    default_modes,
    half_day_changes,
    minutes_of,
    normalize_changes,
    snap,
)
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_phones import _options
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
# A Monday
MONDAY = date(2026, 11, 23)
SCHOOL_DAY = [
    {"at": "06:45", "mode": "free"},
    {"at": "07:45", "mode": "school"},
    {"at": "15:15", "mode": "free"},
    {"at": "16:00", "mode": "homework"},
    {"at": "17:00", "mode": "free"},
    {"at": "21:30", "mode": "sleep"},
]


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _week(hass: HomeAssistant, budgets=None, options=None, types=None) -> Week:
    week = Week(hass, "test", lambda: budgets or {}, lambda: options or {})
    if types is not None:
        week.type_of = lambda d: types.get(d, SCHOOL if d.weekday() < 5 else WEEKEND)
    return week


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _schedule(hass: HomeAssistant, **data) -> dict:
    return await hass.services.async_call(
        DOMAIN, "set_schedule", {"people": ["person.sam"], **data}, blocking=True, return_response=True
    )


# Times and changes


def test_times_snap_to_15_minutes() -> None:
    assert snap(7) == 0 and snap(8) == 15 and snap(22) == 15 and snap(23) == 30
    assert snap(1439) == 1425  # never past the day's last quarter hour
    assert minutes_of("07:52") == 7 * 60 + 45 and minutes_of("07:53") == 8 * 60
    assert minutes_of("21:30:00") == 21 * 60 + 30
    with pytest.raises(ScheduleError):
        minutes_of("25:00")


def test_changes_merge_sort_and_stop_at_twelve() -> None:
    modes = default_modes()
    out = normalize_changes(
        [["16:00", "free"], {"at": "07:44", "mode": "school"}, ["07:46", "free"], ["15:15", "free"], ["21:31", "sleep"]],
        modes,
    )
    # 07:44 and 07:46 both snap to 07:45 (the last given wins); 15:15 and 16:00 merge into the Free time before them
    assert out == [["07:45", "free"], ["21:30", "sleep"]]
    with pytest.raises(ScheduleError):
        normalize_changes([["08:00", "nap"]], modes)
    many = [[f"{h:02d}:00", "free" if h % 2 else "school"] for h in range(MAX_CHANGES + 1)]
    with pytest.raises(ScheduleError):
        normalize_changes(many, modes)


def test_day_types_pick_the_day_used() -> None:
    wednesday, saturday = MONDAY + timedelta(days=2), MONDAY + timedelta(days=5)
    assert day_key_for(wednesday, SCHOOL) == ("wed", False)
    assert day_key_for(saturday, WEEKEND) == ("sat", False)
    # An extra school day on a weekend uses Friday's
    assert day_key_for(saturday, SCHOOL) == ("fri", False)
    assert day_key_for(wednesday, DAY_OFF) == ("day_off", False)
    # Summer weekdays use the Day off
    assert day_key_for(wednesday, NO_SCHOOL) == ("day_off", False)
    assert day_key_for(wednesday, HALF_DAY) == ("wed", True)


def test_a_half_day_ends_school_early_then_carries_on() -> None:
    modes = default_modes()
    base = [(405, "free"), (465, "school"), (915, "free"), (960, "homework"), (1020, "free"), (1290, "sleep")]
    out = half_day_changes(base, modes, 12 * 60, None)
    assert out == [(405, "free"), (465, "school"), (720, "free"), (960, "homework"), (1020, "free"), (1290, "sleep")]
    # Some hours early instead (Configure > Schedule's half_day_hours_early): 15:15 less 2 h
    assert half_day_changes(base, modes, None, 120)[2] == (795, "free")
    # A School end after the weekday's changes nothing
    assert half_day_changes(base, modes, 16 * 60, None) == base
    # School split by lunch: a half day ending before lunch ends all of it, the afternoon School included
    split = [(405, "free"), (465, "school"), (690, "free"), (720, "school"), (915, "free"), (1290, "sleep")]
    assert half_day_changes(split, modes, 11 * 60, None) == [(405, "free"), (465, "school"), (660, "free"), (1290, "sleep")]
    # Ending after lunch: the morning, lunch and School until then
    assert half_day_changes(split, modes, 13 * 60, None) == [
        (405, "free"), (465, "school"), (690, "free"), (720, "school"), (780, "free"), (1290, "sleep")
    ]
    # Hours early counts back from the last School's end
    assert half_day_changes(split, modes, None, 120)[-2] == (795, "free")


async def test_the_night_carries_over_midnight(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_days(["person.sam"], ["school_days"], SCHOOL_DAY)
    week.set_days(["person.sam"], ["weekend", "day_off"], [["08:30", "free"], ["22:30", "sleep"]])
    tuesday = MONDAY + timedelta(days=1)
    segments = week.segments("person.sam", tuesday)
    assert segments[0] == {"start": 0, "end": 405, "mode": "sleep", "carried": True}
    assert segments[-1] == {"start": 1290, "end": 1440, "mode": "sleep", "carried": False}
    # Monday's night runs from Sunday's Sleep at 22:30
    assert week.segments("person.sam", MONDAY)[0]["carried"] is True

    zone = dt_util.get_default_time_zone()
    late = week.now("person.sam", datetime(2026, 11, 24, 23, 0, tzinfo=zone))
    assert late.mode == "sleep"
    # Tuesday's Sleep ends at Wednesday's first change
    assert late.until == datetime(2026, 11, 25, 6, 45, tzinfo=zone)
    early = week.now("person.sam", datetime(2026, 11, 25, 3, 0, tzinfo=zone))
    assert early.mode == "sleep" and early.since == datetime(2026, 11, 24, 21, 30, tzinfo=zone)
    homework = week.now("person.sam", datetime(2026, 11, 24, 16, 20, tzinfo=zone))
    assert homework.mode == "homework" and homework.next.mode == "free"
    assert homework.bedtime == datetime(2026, 11, 24, 21, 30, tzinfo=zone)
    assert homework.wake == datetime(2026, 11, 25, 6, 45, tzinfo=zone)
    assert homework.next_lock == (datetime(2026, 11, 24, 21, 30, tzinfo=zone), "bedtime")
    # Friday night: the Saturday sleeps in
    friday = week.now("person.sam", datetime(2026, 11, 27, 22, 0, tzinfo=zone))
    assert friday.until == datetime(2026, 11, 28, 8, 30, tzinfo=zone)


async def test_a_day_off_tomorrow_moves_tonight_s_wake(hass: HomeAssistant) -> None:
    thursday = MONDAY + timedelta(days=3)
    week = _week(hass, types={thursday: DAY_OFF})
    week.set_days(["person.sam"], ["school_days"], SCHOOL_DAY)
    week.set_days(["person.sam"], ["day_off"], [["09:00", "free"], ["21:30", "sleep"]])
    zone = dt_util.get_default_time_zone()
    found = week.now("person.sam", datetime(2026, 11, 25, 22, 0, tzinfo=zone))
    assert found.wake == datetime(2026, 11, 26, 9, 0, tzinfo=zone)
    assert week.resolve("person.sam", thursday).uses == "day_off"


# The migration


async def test_the_migration_is_today_s_two_budgets(hass: HomeAssistant) -> None:
    budgets = {"person.sam": {"all": {"weekday": 120, "weekend": 240}, "games": {"weekday": 30}}}
    week = _week(hass, budgets, {"school_days": {"half_day_budget": "school_days"}, "schedule": {"half_day_hours_early": 2}})
    assert week.is_set("person.sam") is False
    sched = week.migrated("person.sam")
    assert all(sched["days"][d]["changes"] == [] for d in sched["days"])
    assert sched["days"]["mon"]["limits"] == {"all": 120, "games": 30}
    assert sched["days"]["fri"]["limits"] == {"all": 120, "games": 30}
    assert sched["days"]["sat"]["limits"] == {"all": 240}
    assert sched["days"]["day_off"]["limits"] == {"all": 240}
    assert sched["half_day"] == {"school_ends": None, "early": 120, "limits": "weekday"}
    # Each day type gets what its budget kind gave before
    wednesday, saturday = MONDAY + timedelta(days=2), MONDAY + timedelta(days=5)
    assert week.limits_on("person.sam", wednesday, SCHOOL) == {"all": 120, "games": 30}
    assert week.limits_on("person.sam", wednesday, DAY_OFF) == {"all": 240}
    assert week.limits_on("person.sam", wednesday, NO_SCHOOL) == {"all": 240}
    assert week.limits_on("person.sam", wednesday, HALF_DAY) == {"all": 120, "games": 30}
    assert week.limits_on("person.sam", saturday, WEEKEND) == {"all": 240}
    assert week.limits_on("person.sam", saturday, SCHOOL) == {"all": 120, "games": 30}
    # No changes: nothing of the schedule holds anything
    assert week.now("person.sam", dt_util.now()) is None
    # A half day takes the Day off's limits by default (as half_day_budget did)
    assert _week(hass, budgets).limits_on("person.sam", wednesday, HALF_DAY) == {"all": 240}


async def test_the_first_edit_keeps_the_migration_and_the_budgets_stay_in_step(hass: HomeAssistant) -> None:
    budgets = {"person.sam": {"all": {"weekday": 120, "weekend": 240}}}
    week = _week(hass, budgets)
    week.set_days(["person.sam"], ["tue"], limits={"games": 45})
    assert week.is_set("person.sam")
    assert week.resolve("person.sam", MONDAY + timedelta(days=1), SCHOOL).limits == {"all": 120, "games": 45}
    assert week.resolve("person.sam", MONDAY + timedelta(days=5), WEEKEND).limits == {"all": 240}
    # The old budgets write Monday to Friday, and the weekend and the Day off
    week.set_budget_kind("person.sam", "all", "weekday", 90)
    week.set_budget_kind("person.sam", "all", "weekend", None)
    assert week.budget_of_kind("person.sam", "all", "weekday") == 90
    assert week.limits_on("person.sam", MONDAY + timedelta(days=4), SCHOOL)["all"] == 90
    assert week.limits_on("person.sam", MONDAY + timedelta(days=6), WEEKEND)["all"] is None
    assert week.limits_on("person.sam", MONDAY, DAY_OFF)["all"] is None


async def test_copy_to_days_and_to_kids_with_undo(hass: HomeAssistant) -> None:
    week = _week(hass, {"person.alex": {"all": {"weekday": 60, "weekend": 60}}})
    week.set_days(["person.sam"], ["mon"], SCHOOL_DAY, {"all": 180})
    token = week.copy("person.sam", "mon", None, ["tue", "wed", "day_off"], times=True, limits=False)
    assert week.schedule_of("person.sam")["days"]["wed"]["changes"][1] == ["07:45", "school"]
    assert week.schedule_of("person.sam")["days"]["wed"]["limits"] == {}
    week.undo(token)
    assert week.schedule_of("person.sam")["days"]["wed"]["changes"] == []

    token = week.copy("person.sam", None, ["person.alex"], None)
    assert week.schedule_of("person.alex")["days"]["mon"]["limits"] == {"all": 180}
    week.undo(token)
    # Alex never had a schedule of their own: back to their budgets
    assert week.is_set("person.alex") is False
    assert week.limits_on("person.alex", MONDAY, SCHOOL) == {"all": 60}
    with pytest.raises(ScheduleError):
        week.undo(token)


async def test_today_only_changes_and_resume(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_days(["person.sam"], ["school_days"], SCHOOL_DAY, {"all": 180})
    tuesday = MONDAY + timedelta(days=1)
    week.change_today("person.sam", tuesday, bedtime="22:05")
    day = week.resolve("person.sam", tuesday)
    assert day.changed_today and day.changes[-1] == (22 * 60, "sleep")
    # The weekly Tuesday is unchanged, and so is the next one
    assert week.resolve("person.sam", tuesday + timedelta(days=7)).changes[-1] == (21 * 60 + 30, "sleep")
    week.change_today("person.sam", tuesday, mode="homework", start=18 * 60, until="19:00", limits={"all": 240})
    day = week.resolve("person.sam", tuesday)
    assert (18 * 60, "homework") in day.changes and (19 * 60, "free") in day.changes
    assert day.limits["all"] == 240
    # Midnight ends it
    assert week.new_day(tuesday + timedelta(days=1)) == ["person.sam"]
    assert week.resolve("person.sam", tuesday).changed_today is False
    week.change_today("person.sam", tuesday, bedtime="20:00")
    assert week.resume(["person.sam"]) == ["person.sam"]


async def test_today_mode_until_keeps_its_end_without_a_schedule(hass: HomeAssistant) -> None:
    week = _week(hass)
    tuesday = MONDAY + timedelta(days=1)
    assert week.is_set("person.sam") is False
    week.change_today("person.sam", tuesday, mode="sleep", start=0, until="07:00")
    assert week.resolve("person.sam", tuesday).changes == [(0, "sleep"), (7 * 60, "free")]


# Bedtime and wake (bedtime_sync.py's lanes)


async def test_set_bedtime_moves_a_day_s_bedtime_and_wake_for_good(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_days(["person.sam"], ["school_days"], SCHOOL_DAY)
    week.set_bedtime(["person.sam"], ["wed"], bedtime="21:00")
    days = week.schedule_of("person.sam")["days"]
    assert days["wed"]["changes"][-1] == ["21:00", "sleep"]
    assert days["tue"]["changes"] == days["thu"]["changes"] == normalize_changes(SCHOOL_DAY, week.data.modes)
    # A wake moves the day's first change; School is kept
    week.set_bedtime(["person.sam"], ["wed"], wake="07:15")
    assert days["wed"]["changes"][:2] == [["07:15", "free"], ["07:45", "school"]]
    # Both, on a day with no changes yet
    token = week.set_bedtime(["person.sam"], ["sat"], bedtime="22:00", wake="08:30")
    assert week.schedule_of("person.sam")["days"]["sat"]["changes"] == [["08:30", "free"], ["22:00", "sleep"]]
    week.undo(token)
    assert week.schedule_of("person.sam")["days"]["sat"]["changes"] == []
    # A wake past School starts the day in School; a bedtime before wake is refused whole
    week.set_bedtime(["person.sam"], ["thu"], wake="08:00")
    assert week.schedule_of("person.sam")["days"]["thu"]["changes"][0] == ["08:00", "school"]
    with pytest.raises(ScheduleError):
        week.set_bedtime(["person.sam"], ["mon", "fri"], bedtime="06:00")
    assert week.schedule_of("person.sam")["days"]["mon"]["changes"][-1] == ["21:30", "sleep"]


async def test_the_night_sets(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_bedtime(["person.sam"], ["school_nights"], bedtime="21:00", wake="07:00")
    week.set_bedtime(["person.sam"], ["weekend_nights"], bedtime="22:30")
    days = week.schedule_of("person.sam")["days"]
    assert [k for k in ("mon", "tue", "wed", "thu", "fri", "sat", "sun", "day_off") if days[k]["changes"]] == [
        "mon", "tue", "wed", "thu", "fri", "sat", "sun"
    ]
    assert days["sun"]["changes"][-1] == ["21:00", "sleep"] and days["fri"]["changes"] == [["22:30", "sleep"]]
    assert days["day_off"]["changes"] == []


async def test_a_tonight_only_wake_earlier_and_later_than_usual(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_days(["person.sam"], ["every_day"], [["07:00", "free"], ["21:00", "sleep"]])
    monday, tuesday = MONDAY, MONDAY + timedelta(days=1)
    week.change_today("person.sam", monday, wake="08:30")
    # Tonight is unchanged; tomorrow's Sleep runs until 8:30
    assert week.resolve("person.sam", monday).changes == [(420, "free"), (1260, "sleep")]
    assert week.resolve("person.sam", tuesday).changes == [(0, "sleep"), (510, "free"), (1260, "sleep")]
    # Earlier than usual: from 6:00 it's the day's first awake mode, not the night carried on
    week.change_today("person.sam", monday, wake="06:00")
    assert week.resolve("person.sam", tuesday).changes == [(0, "sleep"), (360, "free"), (1260, "sleep")]
    zone = dt_util.get_default_time_zone()
    assert week.now("person.sam", datetime(2026, 11, 23, 22, 0, tzinfo=zone)).until == datetime(
        2026, 11, 24, 6, 0, tzinfo=zone
    )
    # With a bedtime too; the morning after it's gone
    week.change_today("person.sam", monday, bedtime="22:00", wake="08:00")
    assert week.resolve("person.sam", monday).changes[-1] == (1320, "sleep")
    assert week.resolve("person.sam", tuesday).changes[1] == (480, "free")
    assert week.new_day(tuesday) == []
    assert week.new_day(tuesday + timedelta(days=1)) == ["person.sam"]
    # No bedtime tonight: no wake to move
    week.set_days(["person.sam"], ["wed"], [["07:00", "free"]])
    with pytest.raises(ScheduleError):
        week.change_today("person.sam", tuesday + timedelta(days=1), wake="08:00")


async def test_modes_are_the_family_s(hass: HomeAssistant) -> None:
    week = _week(hass)
    week.set_days(["person.sam"], ["mon"], SCHOOL_DAY)
    with pytest.raises(ScheduleError):
        week.remove_mode("sleep")
    with pytest.raises(ScheduleError):
        week.set_mode("school", "School", "everything")
    mode_id = week.set_mode(None, "Reading", "some", ["games", "all"])
    assert week.data.modes[mode_id] == {"name": "Reading", "allows": "some", "closed": ["games"]}
    # Removing Homework: its change goes and Free time runs on
    assert week.remove_mode("homework") == ["person.sam"]
    assert ["16:00", "homework"] not in week.schedule_of("person.sam")["days"]["mon"]["changes"]
    assert week.schedule_of("person.sam")["days"]["mon"]["changes"][2:] == [["15:15", "free"], ["21:30", "sleep"]]
    for n in range(3):
        week.set_mode(None, f"Extra {n}", "everything")
    with pytest.raises(ScheduleError):
        week.set_mode(None, "One too many", "everything")


# In the household


async def test_no_schedule_changes_nothing(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    """A household that never set up a schedule: the budgets count as before, and nothing new is held."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": 60}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    sam = body["state"]["profiles"][KID]
    assert [g["id"] for g in sam["groups"]] == ["games"] and sam["groups"][0]["minutes_left"] == 55
    assert "schedule" not in sam and sam["locked"] is False
    household = _household(hass)
    assert household.week.is_set("person.sam") is False
    assert household.mode_of("person.sam")["source"] == "locks"


async def test_a_school_time_lock_shows_through_the_schedule_s_free_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A schedule with only bedtime (free from 7, Sleep at 9): while Family Link's School time is on, the mode says
    School, as it does without a schedule; Sleep still comes from the schedule."""
    freezer.move_to(dt_util.now().replace(hour=10, minute=0, second=0))
    await _household_with_sam(hass, hass_client_no_auth)
    school = "binary_sensor.sam_phone_school_time_active"
    hass.states.async_set(school, "on", {"child_id": "42"})
    await _option(hass, "locks", {"person": "person.sam", "entities": [school]})
    await _schedule(hass, days=["every_day"], changes=[{"at": "07:00", "mode": "free"}, {"at": "21:00", "mode": "sleep"}])
    household = _household(hass)
    assert household.mode_of("person.sam")["mode"] == "school"

    hass.states.async_set(school, "off", {"child_id": "42"})
    household.recompute()
    await hass.async_block_till_done()
    found = household.mode_of("person.sam")
    assert found["mode"] == "free" and found["source"] == "schedule"


async def test_homework_closes_games_on_the_tv_and_family_link(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=16, minute=20, second=0))
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    sam = body["state"]["profiles"][KID]
    closed = next(g for g in sam["groups"] if g["id"] == "schedule:games")
    assert closed["minutes_left"] == 0 and "com.example.game" in closed["apps"]
    assert closed["paused"]["reason"] == "Homework" and closed["name"] == "Games (Homework until 5 PM)"
    assert sam["schedule"]["mode"]["id"] == "homework" and sam["schedule"]["next"]["mode"] == "free"
    assert sam["next_lock"]["by"] == "schedule" and sam["next_lock"]["kind"] == "bedtime"
    assert sam["locked"] is False
    assert any("com.example.game" in c.data["packages"] for c in paused)

    # An allow of Games lifts it, as it lifts a budget's hold
    await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "games"}, blocking=True, return_response=True
    )
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    assert not any(g["id"] == "schedule:games" for g in body["state"]["profiles"][KID]["groups"])


async def test_sleep_is_a_bedtime_lock_and_the_mode_sensor_follows(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=21, minute=20, second=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _options(hass, roles={"person.sam": "kid"})
    events = async_capture_events(hass, "hearth_mode")
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)
    mode = hass.states.get("sensor.hearth_sam_mode")
    assert mode.state == "free" and mode.attributes["source"] == "schedule"
    bedtime = hass.states.get("sensor.hearth_sam_bedtime")
    assert dt_util.as_local(dt_util.parse_datetime(bedtime.state)).hour == 21

    freezer.tick(timedelta(minutes=15))
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 0}, blocking=True)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_mode").state == "sleep"
    assert [(e.data["previous"], e.data["mode"]) for e in events] == [("free", "sleep")]
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is True and sam["lock"]["by"] == ["schedule"] and sam["lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["lock"]["until"]).hour == 6

    # Let Sam stay up until 10, today only; then back to the schedule
    await hass.services.async_call(
        DOMAIN, "change_today", {"people": ["person.sam"], "bedtime": "22:00"}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_mode").state == "free"
    assert hass.states.get("sensor.hearth_sam_mode").attributes["today_changed"] is True
    await hass.services.async_call(DOMAIN, "resume_schedule", {"people": ["person.sam"]}, blocking=True)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_mode").state == "sleep"


async def test_get_schedule_and_the_per_day_limits(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    today = dt_util.now().date()
    key = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")[today.weekday()]
    await _schedule(hass, days=[key], limits={"games": 10})
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    games = next(g for g in body["state"]["profiles"][KID]["groups"] if g["id"] == "games")
    assert games["minutes_left"] == 5
    answer = await hass.services.async_call(
        DOMAIN, "get_schedule", {"person": "person.sam"}, blocking=True, return_response=True
    )
    assert answer["limits"]["games"] == 10 and answer["changes"] == [] and answer["bedtime"] is None
    with pytest.raises(ServiceValidationError):
        await _schedule(hass, days=[key], limits={"nope": 10})


async def test_the_panel_reads_edits_and_undoes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _options(hass, roles={"person.sam": "kid"})
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/schedule/get"})
    view = (await ws.receive_json())["result"]["schedule"]
    assert [k["id"] for k in view["kids"]] == ["person.sam"] and view["kids"][0]["set"] is False
    assert set(view["modes"]) == {"sleep", "school", "free", "homework", "wind"}
    assert len(view["week"]) == 7
    await ws.send_json(
        {"id": 2, "type": "hearth/schedule/set", "person": "person.sam", "days": ["mon"], "changes": [["07:00", "free"], ["21:07", "sleep"]]}
    )
    answer = (await ws.receive_json())["result"]
    sam = answer["schedule"]["kids"][0]
    assert sam["set"] is True and sam["days"]["mon"]["changes"] == [["07:00", "free"], ["21:00", "sleep"]]
    await ws.send_json({"id": 3, "type": "hearth/schedule/undo", "token": answer["undo"]})
    assert (await ws.receive_json())["result"]["schedule"]["kids"][0]["set"] is False
    await ws.send_json({"id": 4, "type": "hearth/schedule/mode", "name": "Reading", "allows": "some", "closed": ["games"]})
    assert "reading" in (await ws.receive_json())["result"]["schedule"]["modes"]
    # The half day's School end alone
    await ws.send_json({"id": 5, "type": "hearth/schedule/set", "person": "person.sam", "days": [], "half_day_ends": "11:30"})
    sam = (await ws.receive_json())["result"]["schedule"]["kids"][0]
    assert sam["half_day"]["school_ends"] == "11:30"


async def test_homework_holds_the_switch_and_its_end_lets_go(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from test_enforce import NINTENDO_LIMIT, _nintendo_services, _nintendo_switch

    freezer.move_to(dt_util.now().replace(hour=16, minute=50, second=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    assert set_value == []
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0]
    from custom_components.hearth.websocket import _sync_view

    assert _sync_view(_household(hass), "person.sam")["nintendo"]["why"]["Switch"] == "schedule"

    # 17:00: Free time, and the Switch gets its limit back
    hass.states.async_set(NINTENDO_LIMIT, "0")
    freezer.tick(timedelta(minutes=11))
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 0}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0, 120]
