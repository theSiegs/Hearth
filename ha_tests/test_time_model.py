"""Today's time, category limits and bonus time (time_model.py), Unlimited (unlimited.py) and the Family Link backstop
(backstop.py). The worked examples are the accounting rule's documentation:

    bonus_used = max(0, minutes over daily time, sum over categories of minutes over each limit)
    bonus_left = max(0, N - bonus_used)
    today_left = max(0, base + N - used)
    cap_left   = max(0, limit - used in it) + bonus_left      (0: the category is held)
    usable     = min(cap_left, today_left)                    (what a person is shown)
"""

from datetime import timedelta
import math

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import Unauthorized
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce, unlimited as unlimited_module
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.exceptions import end_of_day
from custom_components.hearth.limits import TIME_MODEL, LimitsData
from custom_components.hearth.time_model import (
    Raise,
    account,
    backstop_minutes,
    category_text,
    limit_text,
    split_bonus,
    today_text,
    unlimited_span_text,
    unlimited_text,
)
from test_init import _post
from test_people import _household_with_sam, _tv_status
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


# The accounting, worked examples


def test_bonus_spent_past_one_limit() -> None:
    """Daily time 180, Games limit 120, +30 bonus. 150 min of games: 30 past Games' limit, paid from the bonus."""
    day = account(180, 30, 150, {"games": (120, 150)})
    assert (day.bonus_used, day.bonus_left) == (30, 0)
    # Games is held (past its limit, no bonus left); 60 min left for other things (180 + 30 - 150)
    assert day.cap_left["games"] == 0 and day.today_left == 60
    assert category_text("Games", day.usable["games"], day.today_left) == (
        "Games are done for today · 1 h left for other things"
    )
    # Halfway: 135 min of games, 15 of the bonus spent, 15 left for games (and anything else)
    half = account(180, 30, 135, {"games": (120, 135)})
    assert (half.bonus_left, half.cap_left["games"], half.today_left) == (15, 15, 75)


def test_one_bonus_shared_by_two_limits() -> None:
    """Games 60 and YouTube 60 limits, +30 bonus: 15 past Games and 10 past YouTube use 25 of the same 30."""
    day = account(180, 30, 145, {"games": (60, 75), "youtube": (60, 70)})
    assert (day.bonus_used, day.bonus_left) == (25, 5)
    assert day.cap_left == {"games": 5, "youtube": 5}
    assert day.today_left == 65
    # 30 past the two together: both held, the rest of the day open for other things
    done = account(180, 30, 150, {"games": (60, 80), "youtube": (60, 70)})
    assert done.bonus_left == 0 and done.cap_left == {"games": 0, "youtube": 0} and done.today_left == 60


def test_bonus_unused_at_the_end_of_the_day() -> None:
    """+30 never needed past a limit: it's daily time like any other, and goes at midnight (nothing carries over)."""
    day = account(180, 30, 200, {"games": (120, 60)})
    # 20 past daily time's base: from the bonus
    assert (day.bonus_used, day.bonus_left, day.today_left) == (20, 10, 10)
    assert today_text(day.today_left, day.bonus_left) == "10 min bonus left"
    tomorrow = account(180, 0, 0, {"games": (120, 0)})
    assert tomorrow.bonus_left == 0 and tomorrow.today_left == 180


def test_a_raised_limit_isn_t_bonus_time() -> None:
    """Raising Games to 3 h lets games use more of daily time; daily time is unchanged."""
    raised = Raise(to=180)
    day = account(180, 0, 150, {"games": (raised.cap(120), 150)})
    assert day.bonus_left == 0 and day.cap_left["games"] == 30 and day.today_left == 30
    # The same 30 as bonus time instead: Games may go on, and daily time grows by 30
    bonus = account(180, 30, 150, {"games": (120, 150)})
    assert bonus.cap_left["games"] == 0 and bonus.today_left == 60
    assert Raise(add=60).cap(120) == 180 and Raise(no_cap=True).cap(120) is None and Raise(add=-200).cap(120) == 0
    assert limit_text("Games", 120, 180, True) == "Games: 3 h limit today (raised)"
    assert limit_text("Games", 120, None, True) == "Games: no limit today (raised)"
    assert limit_text("Games", 120, 120, False) == "Games: 2 h limit"
    assert limit_text("Games", None, None, False) == "Games: no limit"


def test_time_taken_away_lowers_daily_time() -> None:
    assert split_bonus(180, 30) == (180, 30)
    assert split_bonus(180, -30) == (150, 0)
    assert split_bonus(None, -30) == (None, 0)


def test_the_words_people_see() -> None:
    assert today_text(70, 30) == "1 h 10 min left today"
    assert today_text(70, 30, adult=True) == "1 h 10 min left today (includes 30 min bonus)"
    assert today_text(70, 0, adult=True) == "1 h 10 min left today"
    assert today_text(30, 30) == "30 min bonus left"
    assert today_text(0, 0) == "No time left today"
    assert today_text(70, 0, unlimited_text("6 PM")) == "Unlimited until 6 PM"
    assert unlimited_text(None) == "Unlimited (until turned off)"
    assert category_text("Games", 25, 70) == "Games: 25 min left"
    assert unlimited_span_text((14, 0), (17, 10), 190) == "Unlimited 2:00–5:10 PM · 3 h 10 min not counted"
    assert unlimited_span_text((11, 30), (13, 0), 90).startswith("Unlimited 11:30 AM–1:00 PM")


def test_no_user_facing_string_says_pool() -> None:
    """The words people see: one daily time, categories with limits, bonus time; never pools, buckets or a max."""
    import json
    import pathlib
    import re

    root = pathlib.Path(__file__).resolve().parent.parent / "custom_components" / "hearth"
    for name in ("strings.json", "translations/en.json"):
        text = json.dumps(json.load(open(root / name, encoding="utf-8")), ensure_ascii=False)
        for word in (r"\bpools?\b", r"\bbuckets?\b", r"All screen time", r"grown-up", r"\bmax\b(?! screentime)"):
            assert not re.search(word, text, re.IGNORECASE), (name, word)


def test_the_backstop_math() -> None:
    # The device's minutes today + Hearth's daily time left + margin, rounded up to 5
    assert backstop_minutes(180, 0, 180, 30) == 210
    # Spending counted time keeps it steady: 60 more on the phone, 60 less left
    assert backstop_minutes(180, 60, 120, 30) == 210
    # Spending bonus too: +30 bonus (210 left), 150 used of it all
    assert backstop_minutes(180, 0, 210, 30) == backstop_minutes(180, 150, 60, 30) == 240
    # Time Hearth doesn't count (a not-screen-time app, Unlimited) raises it
    assert backstop_minutes(180, 120, 180, 30) == 330
    assert backstop_minutes(180, 3, 177, 31) == 215
    # Unlimited: a whole day; no daily time: left alone (Unlimited or not)
    assert backstop_minutes(180, 0, 0, 30, no_limits=True) == 1440
    assert backstop_minutes(None, 30, 0, 30) is None and backstop_minutes(None, 0, 0, 30, no_limits=True) is None
    assert backstop_minutes(180, 1400, 30, 30) == 1440


# Migration


def test_today_s_category_bonuses_become_raised_limits_once() -> None:
    from custom_components.hearth.limits import Limits

    limits = Limits.__new__(Limits)
    limits.data = LimitsData(day="2026-11-16", bonus={"person.sam": {"all": 30, "games": 90, "streaming": 0}})
    limits._store = None
    assert limits.migrate_bonuses() is True
    # All screen time's bonus stays bonus time; Games' 90 is a raised limit, not bonus time (nothing counted twice)
    assert limits.data.bonus == {"person.sam": {"all": 30}}
    assert limits.data.raises == {"person.sam": {"games": Raise(add=90).view()}}
    assert limits.data.model == TIME_MODEL
    # Again (a restart): nothing moves
    assert limits.migrate_bonuses() is False
    assert limits.data.raises == {"person.sam": {"games": Raise(add=90).view()}}


# The services, end to end (Sam: 15 min on the TV, 10 of Video and 5 of Games)


def _household(hass):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _call(hass, service, data, user=None):
    response = await hass.services.async_call(
        DOMAIN, service, data, blocking=True, return_response=True, context=Context(user_id=user.id if user else None)
    )
    await hass.async_block_till_done()
    return response


async def _set(hass, group, minutes):
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def test_bonus_time_add_and_take_back(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 15)
    await _set(hass, "video", 10)
    household = _household(hass)
    assert household.days["person.sam"].limits["all"].minutes_left == 0
    answer = await _call(hass, "add_time", {"person": "person.sam", "minutes": 30, "reason": "Homework done"})
    view = answer["person.sam"]
    assert (view["today_left"], view["bonus_left"]) == (30, 30)
    assert view["text"] == "30 min bonus left"
    # Video, at its limit, may use the bonus too
    video = household.days["person.sam"].limits["video"]
    assert video.minutes_left == 30 and video.raised is None
    assert hass.states.get("sensor.hearth_sam_bonus_time_left").state == "30"
    assert hass.states.get("number.hearth_sam_all_screen_time_bonus_today").state == "30"
    assert hass.states.get("number.hearth_sam_all_screen_time_bonus_today").name == "Hearth: Sam Bonus time today"
    assert hass.states.get("sensor.hearth_sam_all_screen_time_minutes_left").name == "Hearth: Sam Daily time left"
    assert hass.states.get("number.hearth_sam_video_budget_on_school_days").name == (
        "Hearth: Sam Video limit on school days"
    )
    assert (await _call(hass, "remove_time", {"person": "person.sam", "minutes": 45}))["removed"] == {"person.sam": 30}
    assert household.days["person.sam"].limits["all"].minutes_left == 0


async def test_the_older_add_bonus_raises_a_category_s_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 10)
    household = _household(hass)
    await _call(hass, "add_bonus", {"person": "person.sam", "group": "video", "minutes": 20})
    day = household.days["person.sam"]
    # Video's limit is 30 today; daily time is unchanged (no bonus time)
    assert day.limits["video"].minutes_left == 20 and day.limits["video"].raised == Raise(add=20)
    assert day.limits["all"].minutes_left == 45 and day.limits["all"].bonus_left == 0
    assert hass.states.get("number.hearth_sam_video_bonus_today").state == "20"
    # With no group it's bonus time
    await _call(hass, "add_bonus", {"person": "person.sam", "minutes": 10})
    assert household.days["person.sam"].limits["all"].bonus_left == 10


async def test_raise_a_limit_by_to_or_none_and_end_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 10)
    household = _household(hass)
    await _call(hass, "raise_cap", {"person": "person.sam", "category": "video", "to": 40})
    view = household.time_view("person.sam")
    video = next(c for c in view["categories"] if c["id"] == "video")
    assert (video["limit"], video["limit_today"], video["raised"], video["left"]) == (10, 40, True, 30)
    assert video["limit_text"] == "Video: 40 min limit today (raised)"
    # Daily time is unchanged
    assert view["today_left"] == 45 and view["bonus_left"] == 0
    await _call(hass, "raise_cap", {"person": "person.sam", "category": "video", "no_cap": True})
    assert household.days["person.sam"].limits["video"].minutes_left is None
    # Explain says the app's category and the raised limits (and never "group: null" for an app)
    explained = await _call(hass, "explain", {"person": "person.sam", "app": "com.thesiegs.hearthtube"})
    assert explained["group"] == "video" and explained["pool"] == "video" and "video" in explained["groups"]
    assert [c["id"] for c in explained["raised_limits"]] == ["video"]
    assert explained["bonus_left"] == 0 and explained["today_left"] == 45
    await _call(hass, "raise_cap_end", {"person": "person.sam", "category": "video"})
    assert household.days["person.sam"].limits["video"].minutes_left == 0
    # Daily time isn't a category
    with pytest.raises(Exception):
        await _call(hass, "raise_cap", {"person": "person.sam", "category": "all", "minutes": 30})


async def test_a_raise_ends_at_its_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "video", 10)
    household = _household(hass)
    await _call(hass, "raise_cap", {"person": "person.sam", "category": "video", "minutes": 30, "until": "13:00"})
    assert household.days["person.sam"].limits["video"].minutes_left == 30
    freezer.tick(timedelta(hours=1, minutes=1))
    household.recompute()
    assert household.days["person.sam"].limits["video"].minutes_left == 0


async def test_only_adults_change_today_s_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    for service, data in (
        ("add_time", {"person": "person.sam", "minutes": 30}),
        ("remove_time", {"person": "person.sam", "minutes": 30}),
        ("raise_cap", {"person": "person.sam", "category": "video", "minutes": 30}),
        ("raise_cap_end", {"person": "person.sam"}),
        ("unlimited", {"person": "person.sam"}),
        ("unlimited_end", {"person": "person.sam"}),
    ):
        with pytest.raises(Unauthorized):
            await _call(hass, service, data, hass_read_only_user)


async def test_a_chore_undone_after_its_bonus_was_spent(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """A chore's 20 min are bonus time: 5 of them spent past Video's limit; the undo takes all 20 back."""
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 5)
    household = _household(hass)
    household.limits.chore_minutes = lambda person, group: 20 if group == "games" else 0
    household.recompute()
    day = household.days["person.sam"]
    assert (day.limits["all"].bonus_min, day.limits["all"].bonus_left) == (20, 15)
    assert day.limits["video"].minutes_left == 15 and day.limits["all"].minutes_left == 65
    household.limits.chore_minutes = lambda person, group: 0
    household.recompute()
    day = household.days["person.sam"]
    assert day.limits["all"].bonus_left == 0 and day.limits["video"].minutes_left == 0
    assert day.limits["all"].minutes_left == 45


# Unlimited


async def test_unlimited_isn_t_counted_and_picks_up_where_it_was(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    monkeypatch.setattr(unlimited_module, "SETTLE", timedelta(minutes=10))
    freezer.move_to(dt_util.now().replace(hour=14, minute=0, second=0, microsecond=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 10)
    household = _household(hass)
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 20})
    before = household.time_view("person.sam")
    assert (before["today_left"], before["bonus_left"]) == (65, 20)

    answer = await _call(hass, "unlimited", {"person": "person.sam", "until": "17:10"})
    assert answer["text"] == {"person.sam": "Unlimited until 5:10 PM"}
    assert household.time_view("person.sam")["text"] == "Unlimited until 5:10 PM"
    # Video at its limit isn't held meanwhile (the allow of daily time lifts every hold)
    explained = await _call(hass, "explain", {"person": "person.sam", "app": "com.thesiegs.hearthtube"})
    assert explained["allowed"] and explained["unlimited"]["until"].startswith(dt_util.now().date().isoformat())

    # 3 h 10 min on the TV meanwhile (a live device's count): none of it counts
    freezer.tick(timedelta(hours=3, minutes=10))
    assert (await _post(client, secret, body=_tv_status(hearthtube_s=600 + 190 * 60, game_s=300))).status == 200
    await hass.async_block_till_done()
    during = household.time_view("person.sam")
    assert during["used"] == 15 and during["today_left"] == 65 and during["bonus_left"] == 20

    # It ends at its time; the settle keeps catching up late minutes, then it's settled
    freezer.tick(timedelta(minutes=1))
    household.recompute()
    assert household.time_view("person.sam")["unlimited"] is None
    assert household.time_view("person.sam")["text"] == "1 h 5 min left today"
    freezer.tick(timedelta(minutes=10))
    household.recompute()
    after = household.time_view("person.sam")
    assert (after["used"], after["today_left"], after["bonus_left"]) == (15, 65, 20)
    [span] = after["unlimited_today"]
    assert span["settled"] and span["minutes"] == 190
    assert span["text"] == "Unlimited 2:00–5:10 PM · 3 h 10 min not counted"
    assert any(e["kind"] == "unlimited" and e["minutes"] == 190 for e in household.history.events)


async def test_unlimited_from_a_total_only_source_and_ended_early(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    """A total-only source (Family Link's daily total): what it grew by during the window isn't counted."""
    monkeypatch.setattr(unlimited_module, "SETTLE", timedelta(0))
    freezer.move_to(dt_util.now().replace(hour=14, minute=0, second=0, microsecond=0))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "20", {"unit_of_measurement": "min", "child_id": "42"})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _set(hass, "all", 60)
    household = _household(hass)
    assert household.time_view("person.sam")["used"] == 35
    await _call(hass, "unlimited", {"person": "person.sam", "until": "turned_off", "include_bedtime": True})
    assert household.time_view("person.sam")["unlimited"]["text"] == "Unlimited (until turned off)"
    assert household.bedtime_lift.lifts["person.sam"]["no_limits"]
    hass.states.async_set(FAMILY_LINK, "80", {"unit_of_measurement": "min", "child_id": "42"})
    await hass.async_block_till_done()
    household.recompute()
    assert household.time_view("person.sam")["used"] == 35
    ended = await _call(hass, "unlimited_end", {"person": "person.sam"})
    assert ended["ended"] == ["person.sam"]
    assert ended["text"] == {"person.sam": "Limits back on · 25 min left today"}
    assert "person.sam" not in household.bedtime_lift.lifts
    # Settled: the 60 the phone added while unlimited stay out of today's minutes
    household.recompute()
    view = household.time_view("person.sam")
    assert view["used"] == 35 and view["today_left"] == 25 and view["unlimited"] is None
    # Bonus time was untouched throughout
    assert view["bonus_left"] == 0


async def test_unlimited_ends_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=22, minute=0, second=0, microsecond=0))
    await _household_with_sam(hass, hass_client_no_auth)
    household = _household(hass)
    answer = await _call(hass, "unlimited", {"person": "person.sam", "until": "turned_off"})
    until = dt_util.parse_datetime(answer["until"]["person.sam"])
    # "Until turned off" is midnight at the latest
    assert until == end_of_day(dt_util.now())
    freezer.tick(timedelta(hours=2, minutes=5))
    household.recompute()
    assert household.unlimited.active("person.sam") is None
    assert household.unlimited.windows == {}


# The Family Link backstop

CHILD = "424242424242424242424"
PHONE = "sensor.sam_phone_daily_screen_time"
TV_FL = "sensor.sam_living_room_tv_daily_screen_time"


def _phone(hass, minutes: float, counted: float | None = None, app: str = "com.example.game") -> None:
    """Family Link's screen time today on Sam's phone (a device that takes a daily limit), and the part of it Hearth
    counts (Family Link's daily total as Sam's source, all in [app]; None: all of it)."""
    hass.states.async_set(
        PHONE, str(minutes),
        {"child_id": CHILD, "device_id": "phone1", "device_name": "Phone", "capabilities": ["capabilityBedtime"]},
    )
    counted = minutes if counted is None else counted
    hass.states.async_set(
        FAMILY_LINK, str(counted),
        {"unit_of_measurement": "min", "child_id": CHILD, "apps": [{"package": app, "minutes": counted}] if counted else []},
    )


async def _backstop_household(hass, hass_client_no_auth, phone: float = 0):
    limits = async_mock_service(hass, "familylink", "set_daily_limit")
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    _phone(hass, phone)
    # Family Link's daily total is one of Sam's sources: Hearth counts the phone too
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    # A Google TV of the child's in Family Link: it takes no daily limit, so its minutes don't count
    hass.states.async_set(
        TV_FL, "500",
        {"child_id": CHILD, "device_id": "tv1", "device_name": "Living Room TV", "capabilities": ["capabilityAppUsage"]},
    )
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _set(hass, "all", 180)
    return limits, client, secret


async def _tick(hass) -> None:
    _household(hass).recompute()
    await hass.async_block_till_done()


async def test_the_backstop_follows_today_s_time_and_writes_only_on_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    # The phone's 0 + 165 left (15 counted on the TV) + 30, rounded up to 5; the child's id as a string, today's
    # override (no day); the Google TV's 500 in Family Link don't count
    assert [c.data for c in limits] == [{"child_id": CHILD, "daily_minutes": 195}]
    await _tick(hass)
    assert len(limits) == 1
    # Bonus time: higher, written
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 20})
    assert limits[-1].data["daily_minutes"] == 215 and len(limits) == 2
    # A raised limit inside daily time changes nothing there
    await _call(hass, "raise_cap", {"person": "person.sam", "category": "video", "minutes": 30})
    assert len(limits) == 2
    # Unlimited: a whole day, and the same sum again right after
    await _call(hass, "unlimited", {"person": "person.sam"})
    assert limits[-1].data["daily_minutes"] == 1440
    await _call(hass, "unlimited_end", {"person": "person.sam"})
    assert limits[-1].data["daily_minutes"] == 215
    # The margin is an option (higher: written); off leaves Family Link alone
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop_margin": 60})
    assert limits[-1].data["daily_minutes"] == 245
    count = len(limits)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop": False})
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 20})
    assert len(limits) == count


async def test_spending_bonus_writes_nothing_and_never_locks_early(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """+30 bonus, then the phone uses daily time and the bonus, inside and past a category's limit: the limit
    stays above what the phone used, and isn't written again while time is spent."""
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    await _set(hass, "games", 60)
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 30})
    written = limits[-1].data["daily_minutes"]
    count = len(limits)
    household = _household(hass)
    # Games on the phone: inside the limit, then past it on the bonus (5 more on the TV: 65, 95 of games)
    for used in (30, 60, 90):
        _phone(hass, used)
        await _tick(hass)
        assert len(limits) == count
        assert limits[-1].data["daily_minutes"] >= used + 5
    assert household.days["person.sam"].limits["all"].bonus_left < 30
    # Past the bonus too: Games is held, the limit hasn't moved
    _phone(hass, 120)
    await _tick(hass)
    assert household.days["person.sam"].limits["games"].minutes_left == 0
    assert len(limits) == count and limits[-1].data["daily_minutes"] == written


async def test_unlimited_ending_mid_day_doesn_t_lock_the_phone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """30 counted on the phone, then 150 on it while Unlimited: Family Link counted 180 of the 180 daily time. After
    Unlimited the limit is 180 + time left + margin, never the 180 that would lock it."""
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth, phone=30)
    await _call(hass, "unlimited", {"person": "person.sam"})
    assert limits[-1].data["daily_minutes"] == 1440
    _phone(hass, 180)
    await _tick(hass)
    await _call(hass, "unlimited_end", {"person": "person.sam"})
    view = _household(hass).time_view("person.sam")
    assert limits[-1].data["daily_minutes"] == math.ceil((180 + view["today_left"] + 30) / 5) * 5
    assert limits[-1].data["daily_minutes"] > 180 + 5


async def test_a_not_screen_time_app_then_games_doesn_t_lock_early(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """2 h on the phone in an app outside daily time (Hearth doesn't count it), then games: Family Link's limit rises
    with the phone's minutes, so it never sits below them."""
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    first = limits[-1].data["daily_minutes"]
    # 2 h that Hearth doesn't count
    _phone(hass, 120, counted=0)
    await _tick(hass)
    assert limits[-1].data["daily_minutes"] == first + 120
    # Then 30 of games, counted: steady (the phone's minutes grow as daily time left shrinks)
    _phone(hass, 150, counted=30)
    await _tick(hass)
    assert limits[-1].data["daily_minutes"] == first + 120 >= 150 + 5


async def test_lower_values_wait_for_the_hysteresis_and_a_hold_is_checked_before_writing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 20})
    count = len(limits)
    # 20 less (taken back): within 30 of what's written, not written
    await _call(hass, "remove_time", {"person": "person.sam", "minutes": 20})
    assert len(limits) == count
    # 40 less (daily time lowered): written
    await _set(hass, "all", 160)
    assert len(limits) == count + 1 and limits[-1].data["daily_minutes"] == 175
    # A hold started between the plan and the write: nothing written
    household = _household(hass)
    plans = household.backstop.plans()
    household.backstop._out = lambda person: True
    await household.backstop._write({"person.sam": (CHILD, 999)})
    assert all(c.data["daily_minutes"] != 999 for c in limits)
    assert plans == {}


async def test_the_backstop_never_names_a_tv(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    """Google TVs keep Family Link's limits off on purpose (Hearth holds them itself): the backstop names only the
    child, never a device, and Family Link's child_id path writes only devices that take a daily limit (its
    time_limit_device_ids skips a Google TV); a TV's own minutes in Family Link don't move it."""
    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    hass.states.async_set("switch.sam_phone", "on", {"child_id": CHILD, "device_id": "phone1", "device_name": "Phone"})
    hass.states.async_set(
        "switch.sam_living_room_tv", "on", {"child_id": CHILD, "device_id": "tv1", "device_name": "Living Room TV"}
    )
    await _tick(hass)
    assert limits and not any("entity_id" in c.data or "device_id" in c.data for c in limits)
    assert all(c.data["child_id"] == CHILD and c.data["daily_minutes"] < 500 for c in limits)


async def test_a_hold_s_put_back_is_the_weekday_s_own_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Hearth's whole-device hold keeps the weekday's own limit (weekly_minutes), not today's override (which is the
    backstop's), and puts that back."""
    from custom_components.hearth.enforce import WEEKDAYS

    limits, _client, _secret = await _backstop_household(hass, hass_client_no_auth)
    weekday = WEEKDAYS[dt_util.now().weekday()]
    backstop = limits[-1].data["daily_minutes"]
    hass.states.async_set(
        f"number.sam_family_link_{weekday}_limit", str(backstop), {"child_id": CHILD, "weekly_minutes": 120}
    )
    await _set(hass, "all", 10)  # 15 counted: out, held
    day = dt_util.now().isoweekday()
    assert limits[-1].data == {"child_id": CHILD, "daily_minutes": 0, "day": day}
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "0", {"child_id": CHILD, "weekly_minutes": 0})
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 30})
    put_back = [c.data for c in limits if c.data.get("day") == day]
    assert put_back[-1] == {"child_id": CHILD, "daily_minutes": 120, "day": day}


async def test_origins_say_where_each_status_came_from(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "video", 10)
    household = _household(hass)
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 30})
    await _call(hass, "raise_cap", {"person": "person.sam", "category": "video", "minutes": 15})
    await _call(hass, "unlimited", {"person": "person.sam", "until": "turned_off"})
    await hass.services.async_call(DOMAIN, "pause", {"people": ["person.sam"], "minutes": 20}, blocking=True)
    origins = household.time_view("person.sam")["origins"]
    assert [o["kind"] for o in origins] == ["pause", "unlimited", "raise", "bonus"]
    bonus = origins[-1]
    assert (bonus["source"], bonus["by"], bonus["detail"]) == ("hearth", None, "Bonus +30")
    assert bonus["text"].startswith("Bonus +30 · added in Hearth · ") and bonus["at"]
    assert origins[2]["detail"] == "Video: limit +15 today"
    explained = await _call(hass, "explain", {"person": "person.sam", "group": "video"})
    assert [o["kind"] for o in explained["origins"]] == ["pause", "unlimited", "raise", "bonus"]
