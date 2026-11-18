"""Bedtime schedule sync (bedtime_sync.py): the weekly schedule's bedtime and wake kept in step in Family Link's
bedtime and Family Safety's allowed hours, by state (a ledger of what Hearth wants and last wrote), with a parent's
change in their app followed tonight and offered for good, never written over unasked.

The apps are faked (Apps): their services record each call and show what was written after a set number of polls, as
the real integrations' entities do."""

from __future__ import annotations

from datetime import date, datetime, timedelta
import json
from typing import Any

import pytest
import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import bedtime_sync as bs, enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.weekly import DAYS, default_modes
from test_people import _household_with_sam
from test_phones import _options

SAM = "person.sam"
CHILD = "42"
ACCOUNT = 123456
FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
FAMILY_SAFETY = "sensor.sam_family_safety"
BEDTIME = "binary_sensor.sam_phone_bedtime_active"
FL_WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
FS_WEEKDAYS = ("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")
# A Monday
MONDAY = date(2026, 11, 23)
NIGHTS = [{"at": "07:00", "mode": "free"}, {"at": "21:00", "mode": "sleep"}]
FL_OTHER = ("set_daily_limit", "pause_app", "resume_app", "block_app", "unblock_app", "add_time_bonus", "reset_bonus",
            "set_school_time", "disable_bedtime")
FS_OTHER = ("lock_platform", "unlock_platform", "add_time_bonus", "cancel_time_bonus", "pause_app", "resume_app",
            "set_screentime_limit")


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))
    monkeypatch.setattr(bs, "PACE", 0)


def _hm(hour: Any, minute: Any) -> str:
    return f"{int(hour):02d}:{int(minute):02d}"


class Apps:
    """Family Link and Family Safety as Hearth sees them: weekly slots and windows, tonight's override, the bedtime
    switch; each write shows after [delay] polls (0: at once)."""

    def __init__(self, hass: HomeAssistant, *, delay: int = 0, fl_slots=None, switch: bool = True, hours=None,
                 platforms=("Windows", "Xbox"), today_only: bool = True) -> None:
        self.hass = hass
        self.delay = delay
        self.fl_weekly = {i: list(v) for i, v in (fl_slots or {i: ("21:00", "07:00") for i in range(1, 8)}).items()}
        self.fl_override: dict[str, list[str]] = {}
        self.switch = switch
        self.platforms = platforms
        self.fs_weekly = {p: {wd: list((hours or {}).get(wd, ("07:00", "21:00"))) for wd in FS_WEEKDAYS} for p in platforms}
        self.fs_today: dict[str, tuple[str, list[str]]] = {}
        self.calls: list[tuple[str, dict[str, Any]]] = []
        # (scope, day sent, today's ISO weekday) of each Family Link call
        self.fl_days: list[tuple[str, str, str]] = []
        self.pending: list[list[Any]] = []
        self.fail: dict[str, Exception] = {}
        # Writes that never show (an app that doesn't take them)
        self.drop = False
        self.today_only = today_only

    def register(self) -> None:
        hass = self.hass
        hass.services.async_register("familylink", "set_bedtime", self._set_bedtime)
        hass.services.async_register("familylink", "enable_bedtime", self._enable)
        if self.today_only:
            schema = None
        else:
            def schema(data):  # upstream's: no today_only
                if "today_only" in data:
                    raise vol.Invalid("extra keys not allowed @ data['today_only']")
                return data
        hass.services.async_register("microsoft_family_safety", "set_screentime_intervals", self._set_intervals,
                                     schema=schema)
        for service in FL_OTHER:
            async_mock_service(hass, "familylink", service)
        for service in FS_OTHER:
            async_mock_service(hass, "microsoft_family_safety", service)

    def _later(self, apply) -> None:
        if self.drop:
            return
        if self.delay == 0:
            apply()
            self.publish()
        else:
            self.pending.append([self.delay, apply])

    async def _set_bedtime(self, call: ServiceCall) -> None:
        data = dict(call.data)
        self.calls.append(("set_bedtime", data))
        self.fl_days.append((data.get("scope", "weekly"), str(data.get("day")), str(dt_util.now().isoweekday())))
        if (err := self.fail.get("set_bedtime")) is not None:
            raise err
        start, end = data["start_time"][:5], data["end_time"][:5]
        today = dt_util.now().date().isoformat()

        def apply():
            if data.get("scope") == "today":
                self.fl_override[today] = [start, end]
            else:
                self.fl_weekly[int(data.get("day") or dt_util.now().isoweekday())] = [start, end]

        self._later(apply)

    async def _enable(self, call: ServiceCall) -> None:
        self.calls.append(("enable_bedtime", dict(call.data)))

        def apply():
            self.switch = True

        self._later(apply)

    async def _set_intervals(self, call: ServiceCall) -> None:
        data = dict(call.data)
        self.calls.append(("set_screentime_intervals", data))
        platform = data["platform"]
        if (err := self.fail.get(platform)) is not None:
            raise err
        window = [_hm(data["start_hour"], data["start_minute"]), _hm(data["end_hour"], data["end_minute"])]
        today = dt_util.now().date()

        def apply():
            if data.get("today_only"):
                self.fs_today[platform] = (today.isoformat(), window)
                return
            weekday = FS_WEEKDAYS[int(data["day_of_week"])]
            self.fs_weekly[platform][weekday] = window
            if weekday == FS_WEEKDAYS[(today.weekday() + 1) % 7]:
                # A weekly write drops a pending today-only value
                self.fs_today.pop(platform, None)

        self._later(apply)

    def poll(self) -> None:
        for item in list(self.pending):
            item[0] -= 1
            if item[0] <= 0:
                self.pending.remove(item)
                item[1]()
        self.publish()

    def _fs_now(self, platform: str, weekday: str) -> list[str]:
        today = dt_util.now().date()
        found = self.fs_today.get(platform)
        if found and found[0] == today.isoformat() and weekday == FS_WEEKDAYS[(today.weekday() + 1) % 7]:
            return found[1]
        return self.fs_weekly[platform][weekday]

    def publish(self) -> None:
        hass = self.hass
        now = dt_util.now()
        today = now.date()
        for iso in range(1, 8):
            start, end = self.fl_weekly[iso]
            for bound, value in (("start", start), ("end", end)):
                hass.states.async_set(
                    f"time.sam_family_link_{FL_WEEKDAYS[iso - 1]}_bedtime_{bound}", f"{value}:00",
                    {"child_id": CHILD, "day": iso},
                )
        hass.states.async_set("switch.sam_family_link_bedtime", "on" if self.switch else "off", {})
        if not self.switch:
            hass.states.async_set(BEDTIME, "off", {"child_id": CHILD})
        else:
            yesterday = today - timedelta(days=1)
            y = self.fl_override.get(yesterday.isoformat()) or self.fl_weekly[yesterday.isoweekday()]
            t = self.fl_override.get(today.isoformat()) or self.fl_weekly[today.isoweekday()]
            zone = dt_util.get_default_time_zone()

            def at(day, clock):
                return datetime.combine(day, datetime.strptime(clock, "%H:%M").time(), zone)

            if now < at(today, y[1]):
                start, end, on = at(yesterday, y[0]), at(today, y[1]), True
            else:
                start, end = at(today, t[0]), at(today + timedelta(days=1), t[1])
                on = now >= start
            hass.states.async_set(
                BEDTIME, "on" if on else "off",
                {"child_id": CHILD, "bedtime_start": start.replace(tzinfo=None).isoformat(),
                 "bedtime_end": end.replace(tzinfo=None).isoformat()},
            )
        hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": ACCOUNT})
        policy: dict[str, Any] = {"user_id": ACCOUNT}
        for platform in self.platforms:
            for weekday in FS_WEEKDAYS:
                begin, end = self._fs_now(platform, weekday)
                if platform == "Xbox":
                    policy[f"xbox_{weekday}_allowed_intervals"] = [{"begin": begin, "end": end}]
                else:
                    b, e = bs.mins(begin) // 30, bs.mins(end) // 30
                    policy[f"{weekday}_allowed_intervals"] = [b <= n < e for n in range(48)]
            begin, end = self._fs_now(platform, FS_WEEKDAYS[(today.weekday() + 1) % 7])
            hass.states.async_set(
                f"sensor.sam_{platform.lower()}_time_remaining", "60",
                {"user_id": ACCOUNT, "platform": platform, "allowed_ranges": [{"begin": begin, "end": end}]},
            )
        hass.states.async_set("sensor.sam_screen_time_policy", "enabled", policy)

    # What was called

    def fl(self, scope: str | None = None) -> list[dict[str, Any]]:
        return [d for s, d in self.calls if s == "set_bedtime" and (scope is None or d.get("scope", "weekly") == scope)]

    def fs(self, today_only: bool | None = None, platform: str | None = None) -> list[dict[str, Any]]:
        return [
            d for s, d in self.calls
            if s == "set_screentime_intervals"
            and (today_only is None or bool(d.get("today_only")) == today_only)
            and (platform is None or d["platform"] == platform)
        ]


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _sync(hass: HomeAssistant) -> bs.BedtimeSync:
    return _household(hass).bedtime_sync


async def _set_up(
    hass: HomeAssistant, hass_client_no_auth, freezer, *, at=(10, 0), on: date = MONDAY, schedule=NIGHTS,
    fl: bool = True, fs: bool = True, **apps_kw
) -> Apps:
    freezer.move_to(datetime.combine(on, datetime.min.time().replace(hour=at[0], minute=at[1]),
                                     dt_util.get_default_time_zone()))
    apps = Apps(hass, **apps_kw)
    apps.register()
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    apps.publish()
    enforce_option = []
    if fl:
        enforce_option.append({"kind": "family_link", "person": SAM, "entity_id": FAMILY_LINK})
    if fs:
        enforce_option.append({"kind": "family_safety", "person": SAM, "entity_id": FAMILY_SAFETY,
                               "platforms": list(apps.platforms), "groups": ["games"]})
    await _options(hass, roles={SAM: "kid"}, enforce=enforce_option, fl_backstop=False)
    if schedule is not None:
        await _call(hass, "set_schedule", {"people": [SAM], "days": ["every_day"], "changes": schedule})
    await _tick(hass, freezer, apps, 0)
    return apps


async def _call(hass: HomeAssistant, service: str, data: dict[str, Any]) -> Any:
    answer = await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=True)
    await hass.async_block_till_done()
    return answer


async def _tick(hass: HomeAssistant, freezer, apps: Apps, minutes: int = 1) -> None:
    """A minute (or [minutes]) later: the apps poll, Hearth recomputes and the sync runs, as the minute's timers do."""
    if minutes:
        freezer.tick(timedelta(minutes=minutes))
    apps.poll()
    household = _household(hass)
    household.recompute()
    household.bedtime_sync.reconcile()
    await hass.async_block_till_done()
    household.bedtime_sync.reconcile()
    await hass.async_block_till_done()


async def _started(hass, hass_client_no_auth, freezer, **kw) -> Apps:
    apps = await _set_up(hass, hass_client_no_auth, freezer, **kw)
    await _call(hass, "sync_bedtimes", {"people": [SAM]})
    for _ in range(3):
        await _tick(hass, freezer, apps)
    return apps


def _ledger(hass: HomeAssistant) -> dict[str, Any]:
    return _sync(hass).people[SAM]


# The model


def test_a_night_and_a_window_from_the_week() -> None:
    modes = default_modes()
    day = [(420, "free"), (1260, "sleep")]
    assert bs.night_of(day, day, modes) == (1260, 420)
    assert bs.window_of(day, "sleep", modes) == (420, 1260)
    # Wake is the next day's first change that allows something
    assert bs.night_of(day, [(390, "free"), (465, "school")], modes) == (1260, 390)
    # A nap in the middle of the day isn't in either
    nap = [(420, "free"), (780, "sleep"), (840, "free"), (1260, "sleep")]
    assert bs.window_of(nap, "sleep", modes) == (420, 1260)
    assert bs.night_of(nap, day, modes) == (1260, 420)
    # No Sleep at the end: no night; Family Safety keeps the day open to midnight
    assert bs.night_of([(420, "free")], day, modes) == "no_bedtime"
    assert bs.window_of([(420, "free")], "sleep", modes) == (420, 1440)
    # A night that runs past the next day can't be one Family Link slot
    assert bs.night_of(day, [(0, "sleep")], modes) == "past_next_day"
    assert bs.window_of([], "sleep", modes) == "asleep_all_day"


def test_family_safety_rounds_outward_and_family_link_is_exact() -> None:
    assert bs.round_out(7 * 60 + 15, 21 * 60 + 15) == (420, 1290)
    assert bs.round_out(420, 1260) == (420, 1260)
    modes = default_modes()
    days = {key: [(420, "free"), (1260, "sleep")] for key in [*DAYS, "day_off"]}
    days["fri"] = [(420, "free"), (1275, "sleep")]
    nights, windows = bs.baseline(days, modes)
    assert bs.fl_plan(nights)["5"] == ["21:15", "07:00"] and bs.fl_plan(nights)["1"] == ["21:00", "07:00"]
    assert bs.fs_plan(windows)["friday"] == ["07:00", "21:30"]
    assert bs.fs_plan(windows)["monday"] == ["07:00", "21:00"]


def test_import_from_family_link_keeps_every_day_awake() -> None:
    """A Family Link week of 21:00 to 06:00, Friday and Saturday 21:30: each night's start is that day's bedtime, its
    end the next day's wake; the Day off gets Saturday's wake and Sunday's bedtime."""
    slots = {i: ("21:00", "06:00") for i in range(1, 8)}
    slots[5] = slots[6] = ("21:30", "06:00")
    nights = bs.import_nights(fl_slots=slots)
    assert nights["mon"] == ("06:00", "21:00")
    assert nights["fri"] == ("06:00", "21:30") and nights["sat"] == ("06:00", "21:30")
    assert nights["day_off"] == ("06:00", "21:00")
    modes = default_modes()
    days = bs.apply_import({key: [] for key in [*DAYS, "day_off"]}, nights, modes)
    assert days["mon"] == [(360, "free"), (1260, "sleep")]
    assert all(any(modes[m]["allows"] != "nothing" for _, m in d) for d in days.values())


def test_import_from_family_safety_takes_the_earliest_end_and_latest_begin() -> None:
    nights = bs.import_nights(fs_windows={"monday": [(420, 1320), (390, 1260)], "saturday": [(480, 1440)]})
    assert nights["mon"] == ("07:00", "21:00")
    # No end before midnight on Saturday: its wake only
    assert nights["sat"] == ("08:00", None)


# The first sync


async def test_nothing_is_written_before_an_adult_starts_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _set_up(hass, hass_client_no_auth, freezer, fl_slots={i: ("21:30", "07:00") for i in range(1, 8)})
    for _ in range(5):
        await _tick(hass, freezer, apps)
    assert apps.calls == []
    assert _sync(hass).state(SAM) == bs.REVIEW
    assert _household(hass).hub.attention.item(bs.REVIEW_KEY) is not None
    preview = (await _call(hass, "sync_bedtimes", {"people": [SAM], "dry_run": True}))[SAM]
    assert preview["start_from"] == "hearth"
    assert [p["start"] for p in preview["family_link"]] == ["21:00"] * 7
    assert all(p["was"] == ["21:30", "07:00"] and p["write"] for p in preview["family_link"])
    assert apps.calls == []


async def test_first_sync_writes_seven_slots_then_switches_family_link_s_bedtime_on(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Sam's Family Link bedtime is off (its hours stored at 21:30): sync owns his bedtime, so it writes the seven
    weekly slots and then switches it on, and writes Family Safety's days that differ."""
    events = async_capture_events(hass, bs.EVENT)
    apps = await _started(
        hass, hass_client_no_auth, freezer, switch=False, fl_slots={i: ("21:30", "07:00") for i in range(1, 8)},
        hours={"saturday": ("00:00", "24:00")},
    )
    names = [s for s, _ in apps.calls]
    assert names[:8] == ["set_bedtime"] * 7 + ["enable_bedtime"]
    assert [d["day"] for d in apps.fl()] == ["1", "2", "3", "4", "5", "6", "7"]
    assert all("scope" not in d and d["start_time"] == "21:00" and d["end_time"] == "07:00" for d in apps.fl())
    assert apps.calls[7][1] == {"child_id": CHILD}
    # Family Safety: only Saturday differed, on both platforms
    assert [(d["platform"], d["day_of_week"], d["end_hour"]) for d in apps.fs()] == [("Windows", 6, 21), ("Xbox", 6, 21)]
    assert _ledger(hass)["fl"]["switched_on"] is True
    assert _sync(hass).state(SAM) == bs.ON
    assert {e.data["action"] for e in events} >= {"started", "written", "confirmed"}
    assert all("123456" not in json.dumps(e.data) and CHILD != e.data.get("child_id") for e in events)
    assert _household(hass).hub.attention.item(bs.REVIEW_KEY) is None
    view = _sync(hass).view(SAM)
    assert [s["status"] for s in view["services"]] == ["in_sync", "in_sync", "in_sync"]


async def test_no_write_loops_whatever_the_echo_delay(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Writes show only after 4 polls (the old value meanwhile): each target is written once, and 200 minutes with no
    edit make no call at all."""
    apps = await _started(hass, hass_client_no_auth, freezer, delay=4,
                          fl_slots={i: ("22:00", "07:00") for i in range(1, 8)}, hours={"monday": ("00:00", "24:00")})
    for _ in range(6):
        await _tick(hass, freezer, apps)
    assert len(apps.fl()) == 7 and len(apps.fs()) == 2
    before = len(apps.calls)
    for _ in range(200):
        await _tick(hass, freezer, apps)
    assert len(apps.calls) == before


# Lane A: tonight only


async def test_tonight_only_reaches_both_apps_for_today_and_reverts(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    assert apps.calls == []  # already in step
    await _call(hass, "change_today", {"people": [SAM], "bedtime": "22:00", "wake": "08:00"})
    await _tick(hass, freezer, apps)
    assert apps.fl() == [{"child_id": CHILD, "start_time": "22:00", "end_time": "08:00", "day": "1", "scope": "today"}]
    assert [(d["platform"], d["end_hour"], d.get("today_only")) for d in apps.fs()] == [
        ("Windows", 22, True), ("Xbox", 22, True)
    ]
    for _ in range(5):
        await _tick(hass, freezer, apps)
    assert len(apps.calls) == 3
    # Back to the schedule: the weekday's hours again, today only
    await _call(hass, "resume_schedule", {"people": [SAM]})
    await _tick(hass, freezer, apps)
    assert apps.fl()[-1] == {"child_id": CHILD, "start_time": "21:00", "end_time": "07:00", "day": "1", "scope": "today"}
    assert [(d["end_hour"], d.get("today_only")) for d in apps.fs()[-2:]] == [(21, True), (21, True)]
    # No weekly-scope call ever
    assert not apps.fl("weekly") and not apps.fs(today_only=False)
    assert _sync(hass).view(SAM)["services"][0]["status"] == "in_sync"


async def test_a_tonight_only_wake_writes_tomorrow_s_window_after_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer, at=(20, 0))
    await _call(hass, "change_today", {"people": [SAM], "wake": "08:30"})
    await _tick(hass, freezer, apps)
    # Tonight's Family Link night ends later; Family Safety's today is unchanged (this morning's begin)
    assert apps.fl() == [{"child_id": CHILD, "start_time": "21:00", "end_time": "08:30", "day": "1", "scope": "today"}]
    assert apps.fs() == []
    # 00:01: Tuesday's window begins at 08:30 for today only; Family Link's override lapsed on its own
    freezer.move_to(datetime.combine(MONDAY + timedelta(days=1), datetime.min.time().replace(minute=1),
                                     dt_util.get_default_time_zone()))
    await _tick(hass, freezer, apps, 0)
    assert [(d["start_hour"], d["start_minute"], d.get("today_only")) for d in apps.fs()] == [
        (8, 30, True), (8, 30, True)
    ]
    assert len(apps.fl()) == 1
    # Wednesday: Hearth's today is gone, Family Safety's today-only lapsed at midnight: nothing to write
    freezer.move_to(datetime.combine(MONDAY + timedelta(days=2), datetime.min.time().replace(minute=1),
                                     dt_util.get_default_time_zone()))
    calls = len(apps.calls)
    await _tick(hass, freezer, apps, 0)
    await _tick(hass, freezer, apps)
    assert len(apps.calls) == calls
    assert _ledger(hass)["fl"].get("today") is None
    assert all(not apps.fl("weekly") for _ in [0]) and not apps.fs(today_only=False)


async def test_a_tonight_change_survives_a_restart_and_reverts_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer, at=(18, 0))
    await _call(hass, "change_today", {"people": [SAM], "bedtime": "22:30"})
    await _tick(hass, freezer, apps)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    await _tick(hass, freezer, apps)
    assert len(apps.fl()) == 1  # not written again after the restart
    freezer.move_to(datetime.combine(MONDAY + timedelta(days=1), datetime.min.time().replace(minute=1),
                                     dt_util.get_default_time_zone()))
    await _tick(hass, freezer, apps, 0)
    await _tick(hass, freezer, apps)
    household = _household(hass)
    assert household.week.data.today.get(SAM) is None
    assert _ledger(hass)["fl"].get("today") is None
    assert not apps.fl("weekly") and not apps.fs(today_only=False)


# Lane B: a weekday for good


async def test_a_weekday_for_good_touches_that_day_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    others = {k: v for k, v in _ledger(hass)["fl"]["weekly"].items() if k not in ("2", "3")}
    fs_others = {k: v for k, v in _ledger(hass)["fs"]["Xbox"]["weekly"].items() if k != "wednesday"}
    before = json.dumps([others, fs_others], sort_keys=True)
    days = _household(hass).week.schedule_of(SAM)["days"]
    plain = json.dumps({k: v for k, v in days.items() if k != "wed"}, sort_keys=True)

    await _call(hass, "set_schedule", {"people": [SAM], "days": ["wed"], "bedtime": "21:30", "wake": "06:30"})
    await _tick(hass, freezer, apps)
    # Family Link: Wednesday's night starts later; Tuesday's night ends earlier (Wednesday's wake)
    assert sorted((d["day"], d["start_time"], d["end_time"]) for d in apps.fl()) == [
        ("2", "21:00", "06:30"), ("3", "21:30", "07:00")
    ]
    assert [(d["day_of_week"], d["start_hour"], d["start_minute"], d["end_hour"], d["end_minute"]) for d in apps.fs()] == [
        (3, 6, 30, 21, 30), (3, 6, 30, 21, 30)
    ]
    for _ in range(3):
        await _tick(hass, freezer, apps)
    others = {k: v for k, v in _ledger(hass)["fl"]["weekly"].items() if k not in ("2", "3")}
    fs_others = {k: v for k, v in _ledger(hass)["fs"]["Xbox"]["weekly"].items() if k != "wednesday"}
    assert json.dumps([others, fs_others], sort_keys=True) == before
    days = _household(hass).week.schedule_of(SAM)["days"]
    assert json.dumps({k: v for k, v in days.items() if k != "wed"}, sort_keys=True) == plain
    assert days["wed"]["changes"] == [["06:30", "free"], ["21:30", "sleep"]]


async def test_school_nights_and_weekend_nights(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["weekend_nights"], "bedtime": "22:00"})
    await _tick(hass, freezer, apps)
    assert sorted(d["day"] for d in apps.fl()) == ["5", "6"]
    assert sorted({d["day_of_week"] for d in apps.fs()}) == [5, 6]


async def test_a_weekly_write_of_today_s_weekday_writes_tonight_s_window_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Safety drops a pending today-only value on a weekly write of that weekday: tonight's is written again."""
    apps = await _started(hass, hass_client_no_auth, freezer, platforms=("Xbox",))
    await _call(hass, "change_today", {"people": [SAM], "bedtime": "22:00"})
    await _tick(hass, freezer, apps)
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["mon"], "bedtime": "21:30"})
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    xbox = [(d.get("today_only", False), d.get("day_of_week"), d["end_hour"], d["end_minute"]) for d in apps.fs()]
    assert xbox == [(True, None, 22, 0), (False, 1, 21, 30), (True, None, 22, 0)]
    assert apps.fs_today["Xbox"][1] == ["07:00", "22:00"]
    # Family Link's tonight-only override stays: only the weekly slot is written
    assert [(d["day"], d.get("scope")) for d in apps.fl()] == [("1", "today"), ("1", None)]


# A parent's change in their app


async def _parent_moves_monday(hass, freezer, apps, start="22:00", end="07:00"):
    apps.fl_weekly[1] = [start, end]
    apps.publish()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)


async def test_a_parent_s_family_link_change_today_follows_tonight_with_an_offer(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _tick(hass, freezer, apps, 5)
    await _parent_moves_monday(hass, freezer, apps)
    household = _household(hass)
    today = household.week.data.today[SAM]
    assert today["by"] == "family_link" and today["changes"][-1] == ["22:00", "sleep"]
    offers = _sync(hass).offers
    assert len(offers) == 1 and offers[0]["day"] == "mon" and offers[0]["bedtime"] == "22:00"
    assert offers[0]["was"] == {"bedtime": "21:00", "wake": "07:00"}
    # Family Link isn't written back; Family Safety follows tonight
    assert apps.fl() == []
    assert [(d["end_hour"], d.get("today_only")) for d in apps.fs()] == [(22, True), (22, True)]
    origins = household.origins_of(SAM)
    assert origins[0]["kind"] == "bedtime" and "changed in Family Link" in origins[0]["text"]
    for _ in range(10):
        await _tick(hass, freezer, apps)
    assert apps.fl() == []
    assert _sync(hass).view(SAM)["services"][0]["status"] == "differs"

    # Every Monday: Hearth's schedule takes it; nothing is written to Family Link
    await _call(hass, "bedtime_offer", {"id": offers[0]["id"], "accept": True})
    await _tick(hass, freezer, apps)
    assert household.week.schedule_of(SAM)["days"]["mon"]["changes"][-1] == ["22:00", "sleep"]
    assert apps.fl() == [] and _sync(hass).offers == []
    assert _sync(hass).view(SAM)["services"][0]["status"] == "in_sync"


async def test_putting_hearth_s_back_writes_the_slot_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _tick(hass, freezer, apps, 5)
    await _parent_moves_monday(hass, freezer, apps)
    offer = _sync(hass).offers[0]
    await _call(hass, "bedtime_offer", {"id": offer["id"], "accept": False})
    await _tick(hass, freezer, apps)
    assert apps.fl("weekly") == [{"child_id": CHILD, "start_time": "21:00", "end_time": "07:00", "day": "1"}]
    assert _household(hass).week.data.today.get(SAM) is None
    for _ in range(5):
        await _tick(hass, freezer, apps)
    assert len(apps.fl("weekly")) == 1


async def test_another_weekday_changed_is_an_offer_then_followed_on_that_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _tick(hass, freezer, apps, 5)
    apps.fl_weekly[3] = ["22:15", "07:00"]
    apps.publish()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    assert _household(hass).week.data.today.get(SAM) is None
    assert [o["day"] for o in _sync(hass).offers] == ["wed"]
    assert apps.calls == []
    # Wednesday comes: that night follows it
    freezer.move_to(datetime.combine(MONDAY + timedelta(days=2), datetime.min.time().replace(hour=9),
                                     dt_util.get_default_time_zone()))
    await _tick(hass, freezer, apps, 0)
    today = _household(hass).week.data.today[SAM]
    assert today["by"] == "family_link" and today["changes"][-1] == ["22:15", "sleep"]
    assert apps.fl() == []


async def test_a_tonight_only_change_in_the_app_is_followed_without_an_offer(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _tick(hass, freezer, apps, 5)
    apps.fl_override[MONDAY.isoformat()] = ["21:45", "07:00"]
    apps.publish()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    assert _household(hass).week.data.today[SAM]["changes"][-1] == ["21:45", "sleep"]
    assert _sync(hass).offers == []
    assert apps.fl() == []


async def test_bedtime_switched_off_in_family_link_lifts_tonight_and_stays_off(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer, at=(20, 0))
    apps.switch = False
    apps.publish()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    household = _household(hass)
    until = household.bedtime_lift.until(SAM)
    assert until is not None and until.hour == 7
    assert not [s for s, _ in apps.calls if s == "enable_bedtime"]
    service = _sync(hass).view(SAM)["services"][0]
    assert service["status"] == "off" and "switched off" in service["reason"]
    for _ in range(10):
        await _tick(hass, freezer, apps)
    assert not [s for s, _ in apps.calls if s == "enable_bedtime"]


async def test_what_is_not_a_parent_s_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """One differing reading, a change within the quiet time, and a value never confirmed are never a parent's."""
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _tick(hass, freezer, apps, 5)
    # One reading, then back
    apps.fl_weekly[1] = ["22:00", "07:00"]
    apps.publish()
    await _tick(hass, freezer, apps)
    apps.fl_weekly[1] = ["21:00", "07:00"]
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    assert _sync(hass).offers == []
    # Within the quiet time after Hearth's own write
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["tue"], "bedtime": "21:30"})
    await _tick(hass, freezer, apps)
    apps.fl_weekly[2] = ["20:00", "07:00"]
    apps.publish()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    assert _sync(hass).offers == []


async def test_a_value_never_shown_is_retried_and_told_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    apps.drop = True
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["thu"], "bedtime": "21:30"})
    await _tick(hass, freezer, apps)
    assert len(apps.fl("weekly")) == 1
    # Never shown: not a parent's change, a value that didn't take; tried again after 5, 10, 20 minutes...
    for _ in range(80):
        await _tick(hass, freezer, apps)
    assert _sync(hass).offers == []
    tries = len(apps.fl("weekly"))
    assert 3 <= tries <= 5
    entry = _ledger(hass)["fl"]["weekly"]["4"]
    assert entry["status"] == "failed" and entry["told"] is True
    assert _household(hass).hub.attention.item(f"hearth_bedtime_sync_failed_{SAM}_family_link_None") is not None


# Failures


async def test_family_link_failing_never_stops_family_safety(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    apps.fail["set_bedtime"] = HomeAssistantError("Family Link said no for child 123456789012345678901")
    apps.fail["Xbox"] = HomeAssistantError("Xbox Family Settings isn't signed in")
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["fri"], "bedtime": "21:30"})
    await _tick(hass, freezer, apps)
    assert [d["platform"] for d in apps.fs()] == ["Windows", "Xbox"]
    assert apps.fs_weekly["Windows"]["friday"] == ["07:00", "21:30"]
    view = _sync(hass).view(SAM)
    statuses = {(s["via"], s["platform"]): s for s in view["services"]}
    assert statuses[("family_link", None)]["status"] == "waiting"
    assert "<id>" in statuses[("family_link", None)]["reason"]
    assert statuses[("family_safety", "Windows")]["status"] == "in_sync"
    assert statuses[("family_safety", "Xbox")]["status"] == "waiting"
    # Explain names what isn't in step
    explained = await _call(hass, "explain", {"person": SAM, "group": "all"})
    assert any("Family Link" in line for line in explained["bedtime_sync"])


async def test_a_schema_refusal_is_unsupported_and_not_retried(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    apps.fail["set_bedtime"] = vol.Invalid("expected str for dictionary value @ data['day']")
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["fri"], "bedtime": "21:30"})
    for _ in range(40):
        await _tick(hass, freezer, apps)
    assert len(apps.fl()) == 1
    assert _ledger(hass)["fl"]["weekly"]["5"]["status"] == "unsupported"


async def test_family_link_not_loaded_yet_waits(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    hass.services.async_remove("familylink", "set_bedtime")
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["sat"], "bedtime": "22:00"})
    await _tick(hass, freezer, apps)
    entry = _ledger(hass)["fl"]["weekly"]["6"]
    assert entry["status"] == "waiting" and "isn't loaded" in entry["reason"]
    hass.services.async_register("familylink", "set_bedtime", apps._set_bedtime)
    await _tick(hass, freezer, apps)
    assert [d["day"] for d in apps.fl()] == ["6"]


async def test_upstream_family_safety_writes_the_weekday_and_puts_it_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A Family Safety without today_only: tonight's window is this weekday's setting, recorded for native_sync to put
    back after midnight."""
    apps = await _started(hass, hass_client_no_auth, freezer, platforms=("Xbox",), today_only=False)
    await _call(hass, "change_today", {"people": [SAM], "bedtime": "22:00"})
    await _tick(hass, freezer, apps)
    assert [(d.get("day_of_week"), d["end_hour"]) for d in apps.fs()] == [(1, 22)]
    assert any(r["weekday"] == "monday" and r["target"] == 22 * 60 for r in _household(hass).sync.windows.values())
    for _ in range(5):
        await _tick(hass, freezer, apps)
    assert _sync(hass).offers == []  # Hearth's own today write isn't a parent's change of Monday


# Other Hearth writers


async def test_while_extra_time_lifts_bedtime_family_link_s_tonight_waits(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer, at=(20, 0))
    household = _household(hass)
    household.bedtime_lift.give(SAM, 30)
    await hass.async_block_till_done()
    await _call(hass, "change_today", {"people": [SAM], "bedtime": "22:00"})
    await _tick(hass, freezer, apps)
    assert apps.fl("today") == []
    assert len(apps.fs(today_only=True)) == 2
    tonight = _ledger(hass)["fl"]
    assert tonight.get("today") is None or tonight["today"].get("written") is None
    # The lift ends: one write of tonight's entry
    for _ in range(32):
        await _tick(hass, freezer, apps)
    assert household.bedtime_lift.until(SAM) is None
    assert [(d["start_time"], d["scope"]) for d in apps.fl("today")] == [("22:00", "today")]


async def test_the_bedtime_lift_s_moved_start_is_not_a_parent_s_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer, at=(20, 50))
    household = _household(hass)
    await _tick(hass, freezer, apps, 15)
    household.bedtime_lift.give(SAM, 30)
    await hass.async_block_till_done()
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    await _tick(hass, freezer, apps)
    assert _sync(hass).offers == []
    assert household.week.data.today.get(SAM) is None


# The device lock as the gap cover (household.sleep_locks_devices)


async def test_a_named_window_that_isn_t_on_locks_after_ten_minutes_of_sleep(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Hearth's Sleep from 21:00, Family Link's bedtime from 21:30 (not in step): the devices lock whole after ten
    minutes of Sleep, not before; never while extra time lifts bedtime."""
    apps = await _set_up(hass, hass_client_no_auth, freezer, at=(20, 55), fs=False,
                         fl_slots={i: ("21:30", "07:00") for i in range(1, 8)})
    household = _household(hass)
    await _tick(hass, freezer, apps, 6)  # 21:01
    assert household.sleep_locks_devices(SAM) is False
    await _tick(hass, freezer, apps, 5)  # 21:06
    assert household.sleep_locks_devices(SAM) is False
    await _tick(hass, freezer, apps, 5)  # 21:11
    assert household.sleep_locks_devices(SAM) is True
    household.bedtime_lift.give(SAM, 10)
    assert household.sleep_locks_devices(SAM) is False
    # The lift ends at 21:21: the grace starts again then
    await _tick(hass, freezer, apps, 11)
    assert household.bedtime_lift.until(SAM) is None
    assert household.sleep_locks_devices(SAM) is False
    # 21:30: Family Link's own bedtime is on
    await _tick(hass, freezer, apps, 10)
    assert household.sleep_locks_devices(SAM) is False


# Import


async def test_a_kid_without_a_sleep_imports_family_link_s_hours(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    slots = {i: ("21:00", "06:00") for i in range(1, 8)}
    slots[5] = slots[6] = ("21:30", "06:00")
    changed = async_capture_events(hass, "hearth_schedule_changed")
    apps = await _set_up(hass, hass_client_no_auth, freezer, schedule=None, fl_slots=slots,
                         hours={wd: ("00:00", "24:00") for wd in FS_WEEKDAYS})
    answer = await _call(hass, "sync_bedtimes", {"people": [SAM]})
    assert answer[SAM]["start_from"] == "family_link" and answer[SAM]["undo"]
    for _ in range(3):
        await _tick(hass, freezer, apps)
    days = _household(hass).week.schedule_of(SAM)["days"]
    assert days["mon"]["changes"] == [["06:00", "free"], ["21:00", "sleep"]]
    assert days["fri"]["changes"] == [["06:00", "free"], ["21:30", "sleep"]]
    assert days["day_off"]["changes"] == [["06:00", "free"], ["21:00", "sleep"]]
    assert any(e.data["by"] == "import" for e in changed)
    # Family Link already holds it; the Xbox and Windows follow
    assert apps.fl() == []
    assert len(apps.fs()) == 14
    assert apps.fs_weekly["Xbox"]["saturday"] == ["06:00", "21:30"]
    # The import can be undone
    _household(hass).week.undo(answer[SAM]["undo"])
    assert not _household(hass).week.schedule_of(SAM)["days"]["mon"]["changes"]


async def test_a_kid_without_family_link_imports_family_safety_s_hours(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _set_up(hass, hass_client_no_auth, freezer, schedule=None, fl=False, platforms=("Xbox",),
                         hours={wd: ("07:00", "22:00") for wd in FS_WEEKDAYS})
    answer = await _call(hass, "sync_bedtimes", {"people": [SAM]})
    assert answer[SAM]["start_from"] == "family_safety"
    await _tick(hass, freezer, apps)
    assert _household(hass).week.schedule_of(SAM)["days"]["tue"]["changes"] == [["07:00", "free"], ["22:00", "sleep"]]
    assert apps.calls == []


async def test_nothing_to_sync_stays_in_review_quietly(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _set_up(hass, hass_client_no_auth, freezer, schedule=None, switch=False,
                         hours={wd: ("00:00", "24:00") for wd in FS_WEEKDAYS})
    answer = await _call(hass, "sync_bedtimes", {"people": [SAM]})
    assert answer[SAM]["started"] is False and _sync(hass).state(SAM) == bs.REVIEW
    assert _household(hass).hub.attention.item(bs.REVIEW_KEY) is None
    assert apps.calls == []


async def test_stop_writes_nothing_more_and_puts_nothing_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    apps = await _started(hass, hass_client_no_auth, freezer)
    await _call(hass, "sync_bedtimes", {"people": [SAM], "stop": True})
    await _call(hass, "set_schedule", {"people": [SAM], "days": ["every_day"], "bedtime": "20:30"})
    for _ in range(3):
        await _tick(hass, freezer, apps)
    assert apps.calls == []
    assert _sync(hass).view(SAM)["state"] == "off"


async def test_the_panel_sees_bedtimes_and_sync(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, hass_ws_client
) -> None:
    client = await hass_ws_client(hass)
    apps = await _set_up(hass, hass_client_no_auth, freezer)
    await client.send_json({"id": 1, "type": "hearth/schedule/sync"})
    answer = await client.receive_json()
    assert answer["success"], answer
    assert answer["result"]["sync"][SAM]["preview"]["start_from"] == "hearth"
    await client.send_json({"id": 2, "type": "hearth/schedule/sync/start", "people": [SAM]})
    answer = await client.receive_json()
    assert answer["success"], answer
    kid = answer["result"]["schedule"]["kids"][0]
    assert kid["sync"]["state"] == "on"
    assert kid["bedtime"]["days"]["mon"] == {"bedtime": "21:00", "wake": "07:00"}
    await client.send_json({"id": 3, "type": "hearth/schedule/bedtime", "person": SAM, "scope": "today",
                            "bedtime": "21:45"})
    answer = await client.receive_json()
    assert answer["success"], answer
    tonight = answer["result"]["schedule"]["kids"][0]["bedtime"]["tonight"]
    assert tonight["bedtime"] == "21:45" and tonight["usual_bedtime"] == "21:00" and tonight["changed"] is True
    await _tick(hass, freezer, apps)
    assert apps.fl("today")[-1]["start_time"] == "21:45"
