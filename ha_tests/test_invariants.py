"""Property-style invariants, checked over many seeded random cases (no hypothesis library: random.Random(seed)).

A. The time model (time_model.account, split_bonus): left values never negative, whole minutes, a category's usable
   never more than today's left plus its own bonus, a closed category never takes bonus time, monotonic in used and
   in bonus.
B. Counting (counting.merge, group_seconds): the merged total is never below a reading's total or the items' sum, and
   a live reading beside an itemized one only ever counts as a total.
C. A day in Home Assistant: a kid's phone posting, a totals source going up, down and away, bonus time, budgets,
   Pause screens, allows, reloads and midnight, with the promised invariants checked after every step.
D. Presence and Messages when away: over random outings (fixes, gaps, adults out of reach, restarts) the rule never
   flaps, unknown never changes it but the 6-hour end, it never opens at home, a restart leaves it as it was; and in
   Home Assistant it never lifts School time, a pause or a block, nor touches an allow.

Every assertion names its seed: rerun one case with `-k "seed_<n>"` (or the pure test with that seed in SEEDS).
"""

from __future__ import annotations

from datetime import timedelta
import math
import random

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.counting import ALL, LIVE_PREFIX, Reading, group_seconds, merge
from custom_components.hearth.household import TOTALS_CORRECTION_S, TOTALS_NEW_DAY_BY
from custom_components.hearth.pause import pause_of
from custom_components.hearth.time_model import account, split_bonus

from test_client_contract import _household as _phones_household, _status
from test_sources import _option

PURE_SEEDS = list(range(200))
DAY_SEEDS = list(range(25))
SAM = "person.sam"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


# A. The time model


def _random_day(rng: random.Random):
    base = None if rng.random() < 0.2 else rng.randint(0, 300)
    given = rng.randint(-60, 120)
    used = round(rng.uniform(0, 400), 2)
    categories: dict[str, tuple[int | None, float]] = {}
    for n in range(rng.randint(0, 4)):
        cap = None if rng.random() < 0.25 else (0 if rng.random() < 0.15 else rng.randint(0, 240))
        categories[f"g{n}"] = (cap, round(rng.uniform(0, used), 2))
    cat_bonuses: dict[str, tuple[int, float, bool]] = {}
    for gid, (_cap, spent) in categories.items():
        if rng.random() < 0.3:
            cat_bonuses[gid] = (rng.randint(1, 60), spent, rng.random() < 0.8)
    return base, given, used, categories, cat_bonuses


def _lefts(day) -> dict[str, int | None]:
    """Every "left" value an Account has, by a stable name."""
    out: dict[str, int | None] = {"today_left": day.today_left, "bonus_left": day.bonus_left}
    for gid, value in day.cap_left.items():
        out[f"cap_left:{gid}"] = value
    for gid, value in day.usable.items():
        out[f"usable:{gid}"] = value
    for gid, value in day.cat_left.items():
        out[f"cat_left:{gid}"] = value
    return out


def _not_more(seed: int, what: str, before: dict, after: dict) -> None:
    for key, old in before.items():
        new = after.get(key)
        if old is None or new is None:
            assert old is None and new is None, f"seed {seed}: {what}: {key} went {old} -> {new}"
            continue
        assert new <= old, f"seed {seed}: {what}: {key} rose {old} -> {new}"


def _not_less(seed: int, what: str, before: dict, after: dict) -> None:
    for key, old in before.items():
        new = after.get(key)
        if old is None or new is None:
            assert old is None and new is None, f"seed {seed}: {what}: {key} went {old} -> {new}"
            continue
        assert new >= old, f"seed {seed}: {what}: {key} fell {old} -> {new}"


def test_split_bonus_never_negative() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        base = None if rng.random() < 0.2 else rng.randint(0, 300)
        given = rng.randint(-400, 400)
        new_base, bonus = split_bonus(base, given)
        assert bonus >= 0, f"seed {seed}"
        if base is None:
            assert new_base is None and bonus == max(0, given), f"seed {seed}"
        else:
            assert new_base is not None and new_base >= 0, f"seed {seed}"
            # Taking time away never takes more than the base; giving keeps it
            assert new_base == (base if given >= 0 else max(0, base + given)), f"seed {seed}"


def test_the_accounting_invariants() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        raw_base, given, used, categories, cat_bonuses = _random_day(rng)
        base, bonus = split_bonus(raw_base, given)
        day = account(base, bonus, used, categories, cat_bonuses)
        case = f"seed {seed}: base {base} bonus {bonus} used {used} cats {categories} own {cat_bonuses}"

        # Never negative
        for key, value in _lefts(day).items():
            assert value is None or value >= 0, f"{case}: {key} = {value}"
        assert day.bonus_used >= 0 and day.bonus_left == max(0, bonus - day.bonus_used), case

        if base is None:
            assert day.today_left is None, case
        else:
            # Whole minutes: a minute counts once it's over. A category's own bonus only ever takes minutes off
            # what's counted, so without one the rule is exact, and with one today_left is never less.
            plain = max(0, base + bonus - math.floor(used))
            if not cat_bonuses:
                assert day.today_left == plain, case
            else:
                assert day.today_left >= plain, case

        for gid, (cap, _spent) in categories.items():
            own = day.cat_left.get(gid, 0)
            if cap is None:
                assert day.cap_left[gid] is None, f"{case}: {gid}"
            if day.today_left is not None:
                assert day.usable[gid] is not None, f"{case}: {gid}"
                assert day.usable[gid] <= day.today_left + own, f"{case}: {gid}"
            if cap is not None:
                assert day.usable[gid] <= day.cap_left[gid], f"{case}: {gid}"
            if cap is not None and cap <= 0:
                assert gid in day.closed, f"{case}: {gid}"
                # Closed: no bonus time in it, only its own bonus
                assert day.cap_left[gid] == own, f"{case}: {gid}"
                if gid not in cat_bonuses:
                    # ... and its minutes never count in bonus_used
                    rest = {g: v for g, v in categories.items() if g != gid}
                    without = account(base, bonus, used, rest, cat_bonuses)
                    assert without.bonus_used == day.bonus_used, f"{case}: {gid}"
            else:
                assert gid not in day.closed, f"{case}: {gid}"


def test_more_used_never_leaves_more() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        raw_base, given, used, categories, cat_bonuses = _random_day(rng)
        base, bonus = split_bonus(raw_base, given)
        case = f"seed {seed}: base {base} bonus {bonus} used {used} cats {categories} own {cat_bonuses}"
        before = _lefts(account(base, bonus, used, categories, cat_bonuses))
        # A minute more of something outside every category
        after = _lefts(account(base, bonus, used + 1, categories, cat_bonuses))
        _not_more(seed, f"{case}: +1 used", before, after)
        # A minute more in one category (in daily time too)
        if categories:
            gid = rng.choice(sorted(categories))
            cap, spent = categories[gid]
            more = {**categories, gid: (cap, spent + 1)}
            own = dict(cat_bonuses)
            if gid in own:
                own[gid] = (own[gid][0], spent + 1, own[gid][2])
            after = _lefts(account(base, bonus, used + 1, more, own))
            _not_more(seed, f"{case}: +1 in {gid}", before, after)


def test_more_bonus_never_leaves_less() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        raw_base, given, used, categories, cat_bonuses = _random_day(rng)
        base, bonus = split_bonus(raw_base, given)
        case = f"seed {seed}: base {base} bonus {bonus} used {used} cats {categories} own {cat_bonuses}"
        extra = rng.randint(1, 60)
        before = _lefts(account(base, bonus, used, categories, cat_bonuses))
        after = _lefts(account(base, bonus + extra, used, categories, cat_bonuses))
        _not_less(seed, f"{case}: +{extra} bonus", before, after)
        # A category's own bonus more never leaves less anywhere either
        if categories:
            gid = rng.choice(sorted(categories))
            own = dict(cat_bonuses)
            had, spent, in_all = own.get(gid, (0, categories[gid][1], True))
            own[gid] = (had + extra, spent, in_all)
            after = _lefts(account(base, bonus, used, categories, own))
            _not_less(seed, f"{case}: +{extra} own bonus in {gid}", before, after)


# B. Counting


def _random_readings(rng: random.Random) -> list[Reading]:
    apps = [f"app{n}" for n in range(5)]
    sources = ["source:a", "source:b", "live:x", "live:y", "hearth"]
    readings = []
    for source in rng.sample(sources, rng.randint(1, len(sources))):
        items = {app: round(rng.uniform(0, 3600), 1) for app in rng.sample(apps, rng.randint(0, 3))}
        # A total that may be above, at or (a source's own rounding) below its items' sum
        total = max(0.0, sum(items.values()) + rng.uniform(-600, 3600))
        readings.append(Reading(source, round(total, 1), items, rng.choice([None, "games", "video"])))
    return readings


def test_the_merged_total_is_never_below_what_a_source_says() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        readings = _random_readings(rng)
        usage = merge(readings)
        case = f"seed {seed}: {readings}"
        known = sum(usage.items.values())
        assert usage.total_s >= known - 1e-6, case
        assert usage.rest_s >= -1e-6, case
        for reading in readings:
            assert usage.total_s >= reading.total_s - 1e-6, f"{case}: {reading.source}"
            if not reading.source.startswith(LIVE_PREFIX):
                assert usage.total_s >= sum(reading.items.values()) - 1e-6, f"{case}: {reading.source}"
                for item, seconds in reading.items.items():
                    assert usage.items[item] >= seconds, f"{case}: {reading.source} {item}"
        # Each minute once: never more than the larger of the sources' totals and the items' most
        most_items: dict[str, float] = {}
        for reading in readings:
            for item, seconds in reading.items.items():
                most_items[item] = max(most_items.get(item, 0.0), seconds)
        assert usage.total_s <= max([r.total_s for r in readings] + [sum(most_items.values())]) + 1e-6, case


def test_a_live_reading_beside_an_itemized_one_is_a_total_only() -> None:
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        readings = [r for r in _random_readings(rng) if not r.source.startswith(LIVE_PREFIX)]
        if not any(r.items for r in readings):
            readings.append(Reading("source:z", 600.0, {"app0": 600.0}))
        live = Reading(
            f"{LIVE_PREFIX}t",
            round(rng.uniform(0, 7200), 1),
            {f"title{n}": round(rng.uniform(0, 3600), 1) for n in range(rng.randint(1, 3))},
        )
        case = f"seed {seed}: {readings} + {live}"
        without = merge(readings)
        both = merge(readings + [live])
        assert both.total_s == pytest.approx(max(without.total_s, live.total_s)), case
        assert both.items == without.items, case


def test_group_seconds_count_each_device_once() -> None:
    groups_of_app = {f"app{n}": {"games"} if n % 2 else {"video", "youtube"} for n in range(5)}
    for seed in PURE_SEEDS:
        rng = random.Random(seed)
        devices = {f"d{n}": merge(_random_readings(rng)) for n in range(rng.randint(1, 3))}
        out = group_seconds(devices, lambda item: groups_of_app.get(item, set()))
        case = f"seed {seed}"
        assert out[ALL] == pytest.approx(sum(u.total_s for u in devices.values())), case
        for group, seconds in out.items():
            assert 0 <= seconds <= out[ALL] + 1e-6, f"{case}: {group}"


# C. A day in Home Assistant

TOTALS = "sensor.sam_tablet_screen_time"
TUBE = "com.example.tube"


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


class _Day:
    """What the test knows of Sam's day, independently of Hearth."""

    def __init__(self) -> None:
        self.date = dt_util.now().date()
        self.used_s = 0.0
        self.phone_s = 0
        self.totals_min: float | None = 0.0  # None: unavailable
        self.kept_s = 0.0  # what Hearth keeps of the totals source today (household._higher)
        self.budget: int | None = None
        self.bonus = 0
        self.pause_until = None
        self.allow = False
        self.log: list[str] = []

    def keep_totals(self, now) -> float:
        """Hearth's kept reading of the totals source now, as documented (household._higher): a drop of at most
        TOTALS_CORRECTION_S is taken, a bigger one keeps the higher total, early in the morning any drop is taken;
        never more than the day so far. Returns how much it went down (the documented lowering)."""
        before = self.kept_s
        if self.totals_min is None:
            return 0.0
        since_midnight = (now - dt_util.start_of_local_day(now)).total_seconds()
        reading = min(self.totals_min * 60, since_midnight)
        if now.hour < TOTALS_NEW_DAY_BY or reading >= self.kept_s - TOTALS_CORRECTION_S:
            self.kept_s = reading
        return max(0.0, before - self.kept_s)


async def _settle(hass: HomeAssistant) -> None:
    await hass.async_block_till_done()


async def _service(hass: HomeAssistant, service: str, data: dict) -> None:
    await hass.services.async_call(DOMAIN, service, data, blocking=True)
    await hass.async_block_till_done()


def _check(hass: HomeAssistant, seed: int, day: _Day, lowered_s: float) -> None:
    case = f"seed {seed}, after: {' | '.join(day.log[-6:])}"
    household = _household(hass)
    # (4) No exception escapes a recompute
    try:
        household.recompute()
    except Exception as err:  # noqa: BLE001
        raise AssertionError(f"{case}: recompute raised {err!r}") from err
    person_day = household.days[SAM]
    now = dt_util.now()

    # (1) Today's count never goes down, but for a totals source's documented correction
    used = person_day.groups.get(ALL, 0.0)
    if now.date() == day.date:
        assert used >= day.used_s - lowered_s - 1e-6, f"{case}: used went {day.used_s:.0f}s -> {used:.0f}s"
        shown = int(hass.states.get("sensor.hearth_sam_screen_time_today").state)
        assert shown >= int(day.used_s // 60) - int(lowered_s // 60) - 1, f"{case}: shown {shown}"
    day.used_s = used

    state = person_day.limits[ALL]
    paused = day.pause_until is not None and now < day.pause_until - timedelta(seconds=1)
    if day.pause_until is not None and now >= day.pause_until:
        day.pause_until = None

    # (3) Pause screens lock the person
    if paused:
        assert pause_of(hass, SAM) is not None, f"{case}: pause lost"
        assert hass.states.get("binary_sensor.hearth_sam_locked").state == "on", f"{case}: not locked while paused"

    # (2) Daily time left, whole minutes: base + bonus - minutes counted
    if day.budget is not None and not paused and not day.allow:
        assert state.bonus_min == day.bonus, f"{case}: bonus {state.bonus_min}, expected {day.bonus}"
        expected = max(0, day.budget + day.bonus - math.floor(state.counted_min))
        left = hass.states.get("sensor.hearth_sam_all_screen_time_minutes_left").state
        assert int(left) == expected, (
            f"{case}: left {left}, expected {expected} (budget {day.budget}, bonus {day.bonus}, "
            f"counted {state.counted_min:.2f})"
        )
        assert state.minutes_left == expected, case

    # (5) Out of daily time, nothing allowed: held
    if day.budget is not None and not day.allow and state.minutes_left == 0:
        assert household.limits.is_reached(SAM, ALL), f"{case}: 0 left but not marked reached"
        why = household.explain(SAM, group=ALL)
        assert why["allowed"] is False, f"{case}: 0 left but allowed: {why}"
        assert {"kind": "budget", "by": ALL} in [
            {"kind": b["kind"], "by": b["by"]} for b in why["blocked_by"]
        ], f"{case}: {why['blocked_by']}"


async def _run_day(hass: HomeAssistant, hass_client_no_auth, freezer, seed: int, steps=None) -> None:
    rng = random.Random(seed)
    freezer.move_to(dt_util.now().replace(hour=9, minute=0, second=0, microsecond=0))
    entry, client, sam, _alex = await _phones_household(hass, hass_client_no_auth)
    hass.states.async_set(TOTALS, "0", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": TOTALS, "person": SAM, "name": "Sam's tablet"})
    day = _Day()
    _check(hass, seed, day, 0.0)

    count = rng.randint(20, 40)
    kinds = [
        ("phone", 4), ("totals_up", 3), ("totals_drop", 2), ("totals_away", 1), ("bonus", 2), ("budget", 2),
        ("pause", 1), ("pause_end", 1), ("allow", 1), ("allow_end", 1), ("tick", 4), ("reload", 1), ("midnight", 0.3),
    ]
    plan = steps if steps is not None else [rng.choices([k for k, _ in kinds], [w for _, w in kinds])[0]
                                            for _ in range(count)]
    for kind in plan:
        now = dt_util.now()
        if kind == "phone":
            day.phone_s += rng.randint(30, 1800)
            day.log.append(f"phone {day.phone_s}s")
            await _status(client, sam, seconds_today=day.phone_s, app_seconds_today={TUBE: day.phone_s},
                          app_categories={TUBE: "video"})
        elif kind == "totals_up":
            day.totals_min = (day.totals_min or 0) + rng.randint(1, 45)
            day.log.append(f"totals {day.totals_min}")
            hass.states.async_set(TOTALS, str(day.totals_min), {"unit_of_measurement": "min"})
        elif kind == "totals_drop":
            day.totals_min = 0 if rng.random() < 0.5 else max(0, (day.totals_min or 0) - rng.randint(1, 5))
            day.log.append(f"totals {day.totals_min}")
            hass.states.async_set(TOTALS, str(day.totals_min), {"unit_of_measurement": "min"})
        elif kind == "totals_away":
            day.totals_min = None
            day.log.append("totals unavailable")
            hass.states.async_set(TOTALS, "unavailable", {"unit_of_measurement": "min"})
        elif kind == "bonus":
            minutes = rng.choice([-30, -15, -5, 5, 10, 15, 30, 60])
            day.log.append(f"add_bonus {minutes}")
            await _service(hass, "add_bonus", {"person": SAM, "minutes": minutes})
            day.bonus = max(0, day.bonus + minutes)
        elif kind == "budget":
            day.budget = rng.randrange(0, 301, 5)
            day.log.append(f"set_budget {day.budget}")
            await _service(hass, "set_budget", {"person": SAM, "group": "all", "minutes": day.budget})
        elif kind == "pause":
            minutes = rng.randint(1, 90)
            day.log.append(f"pause {minutes}")
            await _service(hass, "pause", {"people": [SAM], "minutes": minutes})
            day.pause_until = now + timedelta(minutes=minutes)
        elif kind == "pause_end":
            day.log.append("pause_end")
            await _service(hass, "pause_end", {"people": [SAM]})
            day.pause_until = None
        elif kind == "allow":
            day.log.append("allow all")
            await _service(hass, "allow", {"people": [SAM], "group": "all"})
            day.allow = True
        elif kind == "allow_end":
            if not day.allow:
                continue
            day.log.append("allow_end all")
            await _service(hass, "allow_end", {"people": [SAM], "group": "all"})
            day.allow = False
        elif kind == "tick":
            minutes = rng.randint(1, 30)
            day.log.append(f"tick {minutes}")
            freezer.tick(timedelta(minutes=minutes))
            async_fire_time_changed(hass)
        elif kind == "reload":
            day.log.append("reload")
            assert await hass.config_entries.async_reload(entry.entry_id), f"seed {seed}: reload failed"
        elif kind == "midnight":
            day.log.append("midnight")
            tomorrow = dt_util.start_of_local_day(now) + timedelta(days=1, minutes=rng.randint(0, 20))
            freezer.move_to(tomorrow)
            async_fire_time_changed(hass)
        await _settle(hass)

        now = dt_util.now()
        if now.date() != day.date:
            # A new day: the phone and the totals source start again from nothing, bonus time and allows are over
            day.date = now.date()
            day.used_s = 0.0
            day.phone_s = 0
            day.kept_s = 0.0
            day.bonus = 0
            day.allow = False
            day.totals_min = 0.0
            hass.states.async_set(TOTALS, "0", {"unit_of_measurement": "min"})
            await _status(client, sam, seconds_today=0, app_seconds_today={}, app_categories={TUBE: "video"})
            await _settle(hass)
        lowered = day.keep_totals(now)
        _check(hass, seed, day, lowered)


@pytest.mark.parametrize("seed", DAY_SEEDS, ids=[f"seed_{s}" for s in DAY_SEEDS])
async def test_a_random_day_keeps_its_promises(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, seed: int
) -> None:
    await _run_day(hass, hass_client_no_auth, freezer, seed)


# D. Presence and Messages when away (presence.py, presence_rules.py): random outings of fixes, gaps and restarts


from datetime import UTC, datetime  # noqa: E402
import json  # noqa: E402

from custom_components.hearth.places import AWAY, HOME  # noqa: E402
from custom_components.hearth.presence import (  # noqa: E402
    APART,
    AT,
    DWELL,
    WITH_ADULT,
    YES,
    AdultNow,
    Core,
    Fact,
    Fix,
    KidNow,
)
from custom_components.hearth.presence_rules import BACK_AFTER, UNKNOWN_FOR, AwayMessages  # noqa: E402

PRESENCE_SEEDS = list(range(60))
_HOME = (40.0, -75.0, 100.0)
_M = 111195.0


class _FakeHousehold:
    """What the rule reads of the household: the options, no Family Link lists (Google Messages), a name."""

    def __init__(self) -> None:
        self.options: dict = {}
        self.hass = None

    def family_link_child(self, person):
        return None

    def person_name(self, person):
        return "Sam"


class _FakePresence:
    def __init__(self) -> None:
        self.core = Core({})
        self.rules: dict = {}

    def kids(self):
        return [SAM]

    def fact(self, person, name):
        return self.core.facts.get(person, {}).get(name) or Fact()

    def save(self) -> None:
        pass


def _outing(rng: random.Random):
    """Minute by minute: (kid's position in metres north of home or None for no new fix, the adult's position or None
    when they can't be located, whether Home Assistant restarts this minute)."""
    steps = []
    kid, adult = 0.0, 0.0
    while len(steps) < 900:
        kind = rng.choice(("home", "together", "apart", "near", "gap", "adult_gone", "drive"))
        span = rng.randint(2, 90 if kind != "gap" else 420)
        spot = rng.uniform(500, 8000)
        for n in range(span):
            if kind == "home":
                kid, adult = rng.uniform(0, 40), 0.0
            elif kind == "together":
                kid = adult = spot
            elif kind == "apart":
                kid, adult = spot, rng.choice((0.0, spot + rng.uniform(600, 5000)))
            elif kind == "near":
                kid, adult = spot, spot + rng.uniform(150, 320)
            elif kind == "drive":
                adult = kid = n * 900.0
            fresh = kind != "gap" and rng.random() < 0.7
            steps.append((kid if fresh else None, None if kind == "adult_gone" else adult, rng.random() < 0.01))
    return steps


def _simulate(seed: int):
    """The rule's changes [(minute, opened, the facts then, the state before)], over one random outing."""
    rng = random.Random(seed)
    household, presence = _FakeHousehold(), _FakePresence()
    rule = AwayMessages(household, presence)
    start = datetime(2026, 11, 17, 8, 0, tzinfo=UTC)
    kid_fix: KidNow | None = None
    adult_seen: tuple[float, datetime] | None = None
    settle_until = None
    changes = []
    states = []
    for minute, (kid, adult, restart) in enumerate(_outing(rng)):
        now = start + timedelta(minutes=minute)
        if restart:
            # A restart: the positions in memory are gone, the facts and the rule's state come back from the store
            before = (presence.core.data(), json.dumps(presence.rules))
            stored = presence.core.data()
            presence.core = Core({})
            presence.core.load(stored)
            assert (presence.core.data(), json.dumps(presence.rules)) == before, f"seed_{seed}: restart"
            settle_until = now + timedelta(minutes=2)
        if kid is not None:
            place = HOME if kid < 100 else AWAY
            kid_fix = KidNow(Fix(now, _HOME[0] + kid / _M, _HOME[1], 10), place, place, now, now, True)
        adults = {}
        if adult is None:
            adults["person.alex"] = None
        else:
            if adult_seen is None or adult_seen[0] != adult:
                adult_seen = (adult, now)
            adults["person.alex"] = AdultNow(Fix(adult_seen[1], _HOME[0] + adult / _M, _HOME[1], 10), adult < 100)
        settling = settle_until is not None and now < settle_until
        kids = {SAM: kid_fix if kid_fix is not None else KidNow(None)}
        state_before = json.dumps(presence.rules)
        presence.core.step(now, kids, adults, _HOME, settling)
        if settling:
            assert json.dumps(presence.rules) == state_before, f"seed_{seed}: changed while settling"
            continue
        before = dict(presence.rules.get("away_messages", {}).get(SAM) or {})
        for person, opened in rule.check(now):
            facts = {name: (presence.fact(SAM, name).value, presence.fact(SAM, name).sure) for name in (AT, WITH_ADULT, APART)}
            changes.append((now, opened, facts, before))
        states.append((now, rule.on(SAM)))
    return changes, states


@pytest.mark.parametrize("seed", PRESENCE_SEEDS[:20], ids=[f"seed_{s}" for s in PRESENCE_SEEDS[:20]])
def test_messages_when_away_never_flaps(seed: int) -> None:
    """No two changes less than 5 minutes apart; no open, close, open within 15 minutes; open at least 10 minutes."""
    changes, _states = _simulate(seed)
    for (a, opened_a, *_), (b, opened_b, *_) in zip(changes, changes[1:]):
        assert b - a >= DWELL, f"seed_{seed}: {a} {b}"
        assert opened_a != opened_b, f"seed_{seed}: the same change twice"
    for first, _, third in zip(changes, changes[1:], changes[2:]):
        if first[1]:
            assert third[0] - first[0] >= timedelta(minutes=15), f"seed_{seed}"


@pytest.mark.parametrize("seed", PRESENCE_SEEDS[20:40], ids=[f"seed_{s}" for s in PRESENCE_SEEDS[20:40]])
def test_unknown_never_changes_messages_when_away_but_the_6_hour_end(seed: int) -> None:
    changes, _states = _simulate(seed)
    for now, opened, facts, before in changes:
        if opened:
            assert facts[APART] == (YES, True), f"seed_{seed}: opened at {now} on {facts}"
            continue
        back = facts[AT] == (HOME, True) or facts[WITH_ADULT] == (YES, True)
        unknown_since = before.get("unknown_since")
        long_unknown = unknown_since is not None and now - datetime.fromisoformat(unknown_since) >= UNKNOWN_FOR
        assert back or long_unknown, f"seed_{seed}: closed at {now} on {facts}"
        if back:
            assert before.get("back_since") and now - datetime.fromisoformat(before["back_since"]) >= BACK_AFTER - timedelta(
                minutes=1
            ), f"seed_{seed}"


@pytest.mark.parametrize("seed", PRESENCE_SEEDS[40:], ids=[f"seed_{s}" for s in PRESENCE_SEEDS[40:]])
def test_messages_when_away_never_opens_at_home_and_survives_restarts(seed: int) -> None:
    """While the kid's confirmed place is home, it never opens (home alone isn't away). Every restart in the outing
    left the state as it was (checked inside _simulate)."""
    changes, _states = _simulate(seed)
    for now, opened, facts, _before in changes:
        if opened:
            assert facts[AT][0] != HOME, f"seed_{seed}: opened at home at {now}"


HOLD_SEEDS = list(range(6))


@pytest.mark.parametrize("seed", HOLD_SEEDS, ids=[f"seed_{s}" for s in HOLD_SEEDS])
async def test_messages_when_away_never_lifts_school_time_a_pause_or_a_block(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, seed: int
) -> None:
    """Whatever an adult does while it's open (School time, pauses, blocks, allows), Messages is held when one of those
    holds it, and the rule never adds, changes or ends an allow."""
    from test_app_blocks import _lists
    from test_messaging import FAMILY_LINK, MESSAGES, _out_of_time

    rng = random.Random(seed)
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    await _out_of_time(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": SAM, "family_link": FAMILY_LINK, "school_time_apps": [MESSAGES]})
    school = "binary_sensor.sam_phone_school_time_active"
    hass.states.async_set(school, "off", {"child_id": "42"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    # The rule on, as after an outing
    household.presence.rules["away_messages"] = {SAM: {"on": True, "since": dt_util.utcnow().isoformat()}}
    installed = ["com.google.android.apps.messaging", "com.android.chrome", "com.example.game"]
    allows_made: list[str] = []
    for step in range(12):
        what = rng.choice(("school", "pause", "block", "allow", "nothing"))
        on = rng.random() < 0.5
        if what == "school":
            hass.states.async_set(school, "on" if on else "off", {"child_id": "42", "schooltime_end": "2030-01-01T15:00:00"})
        elif what == "pause":
            if on:
                await hass.services.async_call(DOMAIN, "pause", {"people": [SAM], "app": MESSAGES, "minutes": 30}, blocking=True)
            else:
                await hass.services.async_call(DOMAIN, "pause_end", {"people": [SAM], "app": MESSAGES}, blocking=True)
        elif what == "block":
            _lists(hass, installed, blocked=[MESSAGES] if on else [])
        elif what == "allow" and on:
            answer = await hass.services.async_call(
                DOMAIN, "allow", {"people": [SAM], "app": "com.example.game", "until": "end_of_day"},
                blocking=True, return_response=True,
            )
            allows_made.append(answer["id"])
        await hass.async_block_till_done()
        household.recompute()
        await hass.async_block_till_done()
        assert household.away.on(SAM), f"seed_{seed}"
        held = household.enforcement.held_for(SAM).get("family_link", {}).get("held", [])
        child = household.family_link_child(SAM)
        from custom_components.hearth import family_link as fl
        from custom_components.hearth.pause import app_pauses_of

        blocked = MESSAGES in (fl.app_lists(hass, child)[1] or set())
        held_by_school = hass.states.get(school).state == "on"
        paused = any(p["app"] == MESSAGES for p in app_pauses_of(hass, SAM))
        if held_by_school or paused:
            assert MESSAGES in held, f"seed_{seed} step {step}: {what}"
        if held_by_school or paused or blocked:
            assert MESSAGES not in household.open_apps(SAM), f"seed_{seed} step {step}"
            assert "Devices" in held, f"seed_{seed} step {step}: the device lock swapped for app pauses"
        # The allows are the adults' own, untouched by the rule
        assert sorted(a.id for a in household.allows.of(SAM)) == sorted(allows_made), f"seed_{seed}"
