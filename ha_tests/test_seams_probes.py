"""Probes from the 2026-11-17 seams review: bugs that only show where two parts of Hearth meet.

Each probe states what should happen and failed on the code as reviewed (2026.11.39). All of them are fixed now and
run as regression tests; they stay together here, as the seams they pin.

The TV's side of the same review is in android/app/src/test/java/com/thesiegs/hearth/Seams*Test.java.
"""

from datetime import timedelta

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    async_capture_events,
    async_fire_time_changed,
    async_mock_service,
)
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from test_enforce import FAMILY_LINK, _bonus, _budget, settled  # noqa: F401 - the fixture
from test_init import TV_ID, _post
from test_native_sync import CHILD, _household, _installed, _sam_with_family_link
from test_people import KID, _household_with_sam, _tv_status
from test_phones import _options
from test_sources import _option
from test_time_model import _call, _set
from test_weekly import SCHOOL_DAY, _schedule

SAM = "person.sam"
HEARTHTUBE = "com.thesiegs.hearthtube"
CHROME = "com.android.chrome"


def _at(hour: int, minute: int = 0):
    return dt_util.now().replace(hour=hour, minute=minute, second=0, microsecond=0)


async def _minutes_later(hass: HomeAssistant, freezer, minutes: int) -> None:
    freezer.tick(timedelta(minutes=minutes))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()


async def _document(client, secret, **usage) -> dict:
    """Sam's part of the state document the TV gets with its next status."""
    body = await (await _post(client, secret, body=_tv_status(**(usage or {"hearthtube_s": 600, "game_s": 300})))).json()
    return body["state"]["profiles"][KID]


# 1. Family Link: a pause that never took is read as a parent's change (enforce.py _family_link_changes, native_sync.py
# detect). Seen live: 17 of 64 games, every day the Games limit runs out


async def test_a_pause_family_link_never_showed_is_not_a_parent_s_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Sam has the app (Family Link lists it). Hearth pauses it and the call succeeds, but Family Link never shows the
    1-minute limit. The pause was never intact, so nobody changed it: it isn't "the app's limit was changed in the
    Family Link app", and Hearth mustn't record a parent's grant that lifts its own hold until midnight."""
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    _installed(hass, [HEARTHTUBE])
    await _option(hass, "enforce", {"person": SAM, "family_link": FAMILY_LINK, "fl_backstop": False})
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "video", 10)
    assert HEARTHTUBE in paused[0].data["packages"]

    # Family Link's lists after the write: the app is still without a limit, and the pause it saved isn't in force
    hass.states.async_set(
        "sensor.sam_family_link_apps_with_time_limits",
        "0",
        {"child_id": CHILD, "apps": [], "paused_apps": [{"package": HEARTHTUBE, "pause_intact": False, "prior": -1}]},
    )
    await _minutes_later(hass, freezer, 2)  # past the quiet minute after Hearth's own calls
    await _bonus(hass, "video", 0)

    household = _household(hass)
    assert grants == [], "a pause that never took was told as a parent's change in the Family Link app"
    assert household.grants.of(SAM) == []
    assert household.days[SAM].limits["video"].minutes_left == 0


# 2. Family Link: a pause that failed part-way leaves apps paused that Hearth doesn't know it holds (enforce.py
# _async_apply and _call). Seen live once on 2026-11-17 ("Family Link did not take the app limit for ...")


async def test_apps_paused_before_a_failed_pause_are_resumed_when_time_comes_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link pauses a list one app after the other and raises at the first one Google refuses. The apps before
    it are paused for real. When the kid gets time again (bonus time, say) before a retry went through, Hearth must
    resume them: they're its own pauses."""
    really_paused: list[str] = []
    resumed = async_mock_service(hass, "familylink", "resume_app")

    async def pause_app(call: ServiceCall) -> None:
        for package in call.data["packages"]:
            if package == HEARTHTUBE:
                raise HomeAssistantError(f"Family Link did not take the app limit for {package}")
            really_paused.append(package)

    hass.services.async_register("familylink", "pause_app", pause_app)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "enforce", {"person": SAM, "family_link": FAMILY_LINK, "fl_backstop": False})
    await _budget(hass, "video", 10)  # 10 watched: Video is out, its apps are paused
    assert really_paused, "the apps sorted before the refused one were paused in Family Link"

    # An adult gives Video time again within the retry wait: nothing of it should stay paused
    await _bonus(hass, "video", 30)
    await _minutes_later(hass, freezer, 6)
    _household(hass).recompute()
    await hass.async_block_till_done()
    given_back = {p for call in resumed for p in call.data["packages"]}
    assert set(really_paused) <= given_back, "apps stay paused in Family Link with time left, unknown to Hearth"


# 3. Unlimited: a total's minutes that arrive after the 10-minute settle are counted after all (unlimited.py exclude)


async def test_minutes_a_total_reports_late_from_an_unlimited_window_are_not_counted(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Unlimited 2-3 PM, spent on a tablet that's off the Wi-Fi (a car ride). Family Link reports the hour at 3:25 PM
    (its numbers lag up to about 40 minutes, docs: Screen time from other integrations). The docs promise the
    approximation never goes against the kid; here the whole hour comes off daily time."""
    freezer.move_to(_at(14))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "20", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": SAM})
    await _set(hass, "all", 120)
    household = _household(hass)
    before = household.days[SAM].limits["all"].minutes_left
    await _call(hass, "unlimited", {"person": SAM, "until": "15:00"})

    freezer.move_to(_at(15, 25))
    household.recompute()
    await hass.async_block_till_done()
    assert household.days[SAM].limits["all"].minutes_left == before
    # 25 minutes after the window: Family Link's total catches up with the hour played in it
    hass.states.async_set(FAMILY_LINK, "80", {"unit_of_measurement": "min", "child_id": CHILD})
    await hass.async_block_till_done()
    assert household.days[SAM].limits["all"].minutes_left >= before - 25, "the Unlimited hour was counted"


async def test_minutes_played_after_an_unlimited_window_still_count(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The late minutes are only what a total gained beyond the time since the settle: real play after it counts."""
    freezer.move_to(_at(14))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "20", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": SAM})
    await _set(hass, "all", 120)
    household = _household(hass)
    before = household.days[SAM].limits["all"].minutes_left
    await _call(hass, "unlimited", {"person": SAM, "until": "15:00"})
    freezer.move_to(_at(15, 25))
    household.recompute()
    await hass.async_block_till_done()

    # 20 minutes later Sam has played 20 minutes more on the phone (the window itself had no minutes)
    freezer.move_to(_at(15, 45))
    hass.states.async_set(FAMILY_LINK, "40", {"unit_of_measurement": "min", "child_id": CHILD})
    await hass.async_block_till_done()
    assert household.days[SAM].limits["all"].minutes_left == before - 20


# 4. Unlimited started again within the settle of the last one: the overlap is left out twice (unlimited.py start)


async def test_unlimited_started_again_within_the_settle_leaves_no_minute_out_twice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(_at(14))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 120)
    household = _household(hass)
    before = household.days[SAM].limits["all"].minutes_left  # 105: 15 minutes were used before any Unlimited
    await _call(hass, "unlimited", {"person": SAM, "until": "15:00"})
    freezer.tick(timedelta(minutes=20))
    await _post(client, secret, body=_tv_status(hearthtube_s=600 + 1200, game_s=300))
    await _call(hass, "unlimited_end", {"person": SAM})
    # An adult turns it on again a minute later, for 8 minutes
    freezer.tick(timedelta(minutes=1))
    await _call(hass, "unlimited", {"person": SAM, "until": "15:00"})
    freezer.tick(timedelta(minutes=8))
    await _post(client, secret, body=_tv_status(hearthtube_s=600 + 1200 + 480, game_s=300))
    await _call(hass, "unlimited_end", {"person": SAM})
    freezer.tick(timedelta(minutes=30))
    household.recompute()
    await hass.async_block_till_done()
    # Everything since 2 PM was Unlimited: exactly the 15 minutes from before count, no fewer
    assert household.days[SAM].limits["all"].minutes_left == before


# 5. Pause screens and a phone that only Family Link holds (enforce.py update: paused_groups_of)


async def test_pause_screens_holds_a_family_link_only_phone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Sam's phone has no Hearth app: Family Link is the only thing holding it (as every kid's phone and tablet in the
    household this was reviewed for). Daily time used up locks it; Pause screens says "Screens paused" and locks the
    TVs, the Xbox and the Switch, so it must hold the phone too."""
    freezer.move_to(_at(14))
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    _installed(hass, ["com.example.chat", HEARTHTUBE])
    await _budget(hass, "all", 120)
    assert limits == [] and paused == []

    await _call(hass, "pause", {"people": [SAM], "minutes": 30, "reason": "Dinner"})
    await hass.async_block_till_done()
    assert _household(hass).days[SAM].locked
    assert limits or paused, "the phone is open through Pause screens"


async def test_the_schedule_s_sleep_locks_a_family_link_phone_without_a_bedtime_of_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Hearth's weekly schedule says Sleep at 9 and Family Link has no bedtime for Sam: the phone is locked whole (it
    used to be left open, Family Link's own bedtime being expected to do it). With a Family Link bedtime on, Family
    Link locks it itself and Hearth doesn't."""
    freezer.move_to(_at(21, 30))
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    _installed(hass, ["com.example.chat", HEARTHTUBE])
    await _schedule(hass, days=["every_day"], changes=[{"at": "07:00", "mode": "free"}, {"at": "21:00", "mode": "sleep"}])
    await hass.async_block_till_done()
    household = _household(hass)
    assert "Devices" in household.enforcement.status_of(SAM)["family_link"]["held"]
    assert limits or paused

    # Family Link's own bedtime is on: Hearth lets its lock go
    hass.states.async_set("binary_sensor.sam_phone_bedtime_active", "on", {"child_id": CHILD})
    freezer.tick(timedelta(minutes=2))
    household.recompute()
    await hass.async_block_till_done()
    assert household.sleep_locks_devices(SAM) is False


async def test_a_sleep_device_lock_moves_to_the_new_weekday_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link's device lock is one weekday's daily limit at 0: Sleep past midnight must put that weekday's limit
    back and lock the new weekday's, or the phone opens at midnight (and last week's day stays at 0 for good)."""
    from custom_components.hearth import enforce as enf

    freezer.move_to(_at(21, 30))
    async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    _installed(hass, ["com.example.chat", HEARTHTUBE])
    await _schedule(hass, days=["every_day"], changes=[{"at": "07:00", "mode": "free"}, {"at": "21:00", "mode": "sleep"}])
    await hass.async_block_till_done()
    first_day = dt_util.now().isoweekday()
    assert [c.data["daily_minutes"] for c in limits if c.data.get("day") == first_day] == [0]
    for day in range(1, 8):
        hass.states.async_set(
            f"number.sam_family_link_{enf.WEEKDAYS[day - 1]}_limit",
            "0" if day == first_day else "120",
            {"child_id": CHILD, "weekly_minutes": 0 if day == first_day else 120},
        )

    freezer.move_to(_at(21, 30) + timedelta(hours=2, minutes=40))  # 00:10 the next day, still Sleep
    household = _household(hass)
    household.recompute()
    await hass.async_block_till_done()
    next_day = dt_util.now().isoweekday()
    assert next_day != first_day
    calls = [(c.data["day"], c.data["daily_minutes"]) for c in limits if "day" in c.data]
    assert (first_day, 120) in calls, "yesterday's weekday limit put back"
    assert calls[-1] == (next_day, 0), "today's weekday locked"
    assert "Devices" in household.enforcement.status_of(SAM)["family_link"]["held"]


# 6. Chrome is "com.android.*", which Hearth's per-app holds treat as the system (enforce.essential)


async def test_pausing_chrome_pauses_it_in_family_link(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    _installed(hass, [CHROME, HEARTHTUBE])
    await _option(hass, "enforce", {"person": SAM, "family_link": FAMILY_LINK, "fl_backstop": False})

    answer = await _call(hass, "pause", {"people": [SAM], "app": CHROME, "minutes": 30})
    assert answer["paused"] == [SAM]
    explained = await _call(hass, "explain", {"person": SAM, "app": CHROME})
    assert [b["kind"] for b in explained["blocked_by"]] == ["pause"]  # Hearth says it's paused...
    assert any(CHROME in call.data["packages"] for call in paused), "...and nothing pauses it on the phone"


# 7. Family Safety's Downtime sensors say downtime_start / downtime_end; Hearth reads bedtime_start / bedtime_end
# (pause.py _STARTS and _ENDS, household.py _locks_bedtime). Checked against the installed integration's attributes


async def test_family_safety_downtime_says_when_it_starts_and_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(_at(20, 30))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    start = _at(21)
    end = start + timedelta(hours=10)
    downtime = "binary_sensor.sam_windows_downtime_active"
    # As the installed Family Safety has them (no bedtime_start / bedtime_end aliases any more)
    attributes = {
        "user_id": 123456,
        "platform": "Windows",
        "downtime_start": start.isoformat(),
        "downtime_end": end.isoformat(),
    }
    hass.states.async_set(downtime, "off", attributes)
    await _option(hass, "locks", {"person": SAM, "entities": [downtime]})

    sam = await _document(client, secret, hearthtube_s=60)
    assert sam.get("next_lock") == {"at": start.isoformat(), "by": downtime, "kind": "bedtime", "until": end.isoformat()}
    assert _household(hass).bedtime_tonight(SAM) is not None

    hass.states.async_set(downtime, "on", attributes)
    await hass.async_block_till_done()
    sam = await _document(client, secret, hearthtube_s=60)
    assert sam["lock"]["kind"] == "bedtime" and sam["lock"]["until"] is not None


# 8. Ending the allow behind Unlimited leaves Unlimited on (the page's and the phones' "end allow": hearth.allow_end)


async def test_ending_the_allow_behind_unlimited_ends_unlimited(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Unlimited is an allow of daily time plus a window of uncounted minutes. The allow shows among Sam's allows with
    an "end" action (the panel, the phones' glance). Ending it there must end Unlimited, or change nothing: not leave
    Sam held while every screen says "Unlimited until 6 PM" and his minutes still aren't counted."""
    freezer.move_to(_at(14))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 15)  # used up
    household = _household(hass)
    await _call(hass, "unlimited", {"person": SAM, "until": "18:00"})
    assert [a["group"] for a in household.allow_views(SAM)] == ["all"]

    await _call(hass, "allow_end", {"people": [SAM], "group": "all"})
    sam = await _document(client, secret)
    held = any(g["id"] == "all" and g["minutes_left"] == 0 for g in sam["groups"])
    assert not (held and sam["time"]["unlimited"] is not None), (
        f"held by daily time while the document says {sam['time']['text']!r}"
    )


# 9. A category that's off today: bonus time can't open it, yet the device is told nothing that stops the ask


async def test_a_category_that_is_off_today_is_marked_so_in_its_group(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Games: 0 today. time.categories says closed ("Games are off today"), but devices hold and ask by groups[], and
    the Games group there reads like one that ran out: the TV offers "Ask for bonus time", Hearth takes the ask, an
    adult approves, and the bonus doesn't open Games (time_model: a closed category takes no bonus)."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 120)
    await _set(hass, "games", 0)
    sam = await _document(client, secret)
    assert next(c for c in sam["time"]["categories"] if c["id"] == "games")["closed"] is True
    games = next(g for g in sam["groups"] if g["id"] == "games")
    asked = await client.post(
        f"/api/hearth/device/{TV_ID}/ask",
        json={"profile_id": KID, "group": "games", "minutes": 30},
        headers={"X-Hearth-Secret": secret},
    )
    # The group says it can't be asked for, and the ask is refused
    assert games.get("closed") is True
    assert asked.status == 400 and (await asked.json())["error"] == "closed"


# 10. School time taken off today is still announced as the next lock (household.py _locks_document, weekly.py now)


async def test_school_time_taken_off_is_not_the_next_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    """The weekly schedule's School starts at 7:45; an adult took School time off for today. schedule_lock knows (no
    lock at 7:50), but at 7:30 the document still says next_lock school_time at 7:45: the TV shows its heads-up, and
    locks at 7:45 by itself until Home Assistant's next word (all day if Home Assistant is away then)."""
    freezer.move_to(_at(7, 30))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _options(hass, roles={SAM: "kid"})
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)
    household = _household(hass)
    assert (await _document(client, secret, hearthtube_s=60))["next_lock"]["kind"] == "school_time"

    # School time off today, as scheduler.off_now says once Family Link took it (schedule.py)
    monkeypatch.setattr(household.scheduler, "off_now", lambda person, now=None: object())
    household.recompute()
    sam = await _document(client, secret, hearthtube_s=60)
    assert sam["locked"] is False
    assert (sam.get("next_lock") or {}).get("kind") != "school_time"


# The document the TV's probe SeamsDocumentTest starts from (passes: it pins Home Assistant's side of that seam)


async def test_an_allowed_youtube_is_only_in_daily_time_s_exceptions(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Daily time used up, then a bonus for the category HearthTube is in (or an allow of it): the document leaves the
    category out and names its apps in Daily time's `except`. The TV must read that as "HearthTube isn't held"."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 15)
    await _set(hass, "video", 10)
    await _call(hass, "add_time", {"person": SAM, "minutes": 15, "category": "video"})
    sam = await _document(client, secret)
    assert [(g["id"], g["minutes_left"]) for g in sam["groups"]] == [("all", 0)]
    assert HEARTHTUBE in sam["groups"][0]["except"]
