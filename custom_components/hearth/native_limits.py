"""The parents' own daily limits next to Hearth's budgets: a read-only check (docs/home-assistant-integration.md,
Parents' limits next to the budget).

Each parental control keeps a daily limit of its own: Family Link's per weekday, Family Safety's per weekday for
Windows and the Xbox, the Switch's Max screentime (of every day, or of each weekday). One lower than Hearth's budget
stops the kid first, whatever Hearth allows; a platform with no limit of its own has nothing to stop it while Home
Assistant is down. Here, per kid and platform, each weekday's own limit is set against Hearth's budget of that
weekday's usual day type (Monday to Friday school days within the school year, else no-school days; Saturday and
Sunday weekends; the weekly schedule's own limits without today's changes): the least of the budgets of the groups
the platform's enforcer holds for (a group with no limit leaves it to the others; Family Link's daily limit is the
whole device's, All screen time), a shared Switch the biggest of its kids' (as schedule.py raises it).

A weekday is
- below: the platform's limit cuts in first (short: by how many minutes),
- covered: below, but Hearth raises it to the day's budget each day (Family Link: the backstop, backstop.py, or with
  it off follow_family_link; Family Safety: follow_family_safety; the Switch: follow_nintendo, up to its 360),
- ok: at the budget or over it,
- none: no limit of its own (Family Link's daily limit off or a whole day, Family Safety's 1440, the Switch's -1),
- no_budget: Hearth has no budget for those groups that day (nothing to compare),
- unknown: not readable now (unavailable, missing, or Hearth's own hold or raise in the way).

Nothing is ever written to a platform here. The adults get one notice per kid and platform (a shared Switch: one per
Switch) while any weekday is below and not covered: which days, by how much, and the fix (raise the limit in the
parent's app, or have Hearth follow the budget there). It's said once the same finding was seen on two looks in a row,
kept (across a restart) and said again only when the days or minutes change; it's taken back once nothing is below. A
platform with any weekday unknown changes nothing (no notice, none taken back): a read cut short is never acted on.
"none" is only said in hearth.explain.

Hearth's own values are seen through: a weekday limit Hearth raised today (temporary_limit.py) reads as the one it
raised from; a Switch Hearth holds reads as the limit the hold puts back; Family Link's weekday limit while Hearth holds
the devices (it's at 0 then) is unknown. A Switch whose limit is per weekday shows only today's: the other weekdays
are the ones last read on their own day (kept, at most 8 days old).
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .attention import ADULTS, Item
from .counting import ALL
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    NINTENDO,
    NINTENDO_EACH_DAY,
    WEEKDAYS,
    Enforcer,
    enforcers_from_options,
    fs_app_platform,
    fs_day_limit_entity,
)
from .nintendo import switch_name
from .schooldays import NO_SCHOOL, SCHOOL, WEEKEND, by_rule
from .temporary_limit import SWITCH, WINDOWS, XBOX

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

BELOW = "below"
COVERED = "covered"
OK = "ok"
NONE = "none"
NO_BUDGET = "no_budget"
UNKNOWN = "unknown"

# What raises a platform's limit to the day's budget each day
BY_BACKSTOP = "backstop"
BY_FOLLOW_FL = "follow_family_link"
BY_FOLLOW_FS = "follow_family_safety"
BY_FOLLOW_SWITCH = "follow_nintendo"

# A limit of a whole day or more is no limit
FULL_DAY = 1440
# The most the schedule raises a Switch to (schedule.SWITCH_MAX)
SWITCH_MAX = 360
# A per-weekday Switch's limit read on its own day is kept this long
SWITCH_DAY_KEPT = timedelta(days=8)
NOTICE_PREFIX = "hearth_native_limit_"
_UNREAD = ("unavailable", "unknown", "", None)

VIA_NAMES = {FAMILY_LINK: "Family Link", FAMILY_SAFETY: "Family Safety", NINTENDO: "Nintendo"}
APP_NAMES = {
    FAMILY_LINK: "the Family Link app",
    FAMILY_SAFETY: "the Family Safety app",
    NINTENDO: "the Nintendo Switch Parental Controls app",
}


def _minutes(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


def _said(items: list[str]) -> str:
    return items[0] if len(items) == 1 else f"{', '.join(items[:-1])} and {items[-1]}"


def _day(weekday: str) -> str:
    return weekday.title()


def usual_type(household: Household, day: date) -> str:
    """The day type a weekday usually has: a school day Monday to Friday within the school year (School days' rule),
    a no-school day outside it, a weekend on Saturday and Sunday. One-off days off and half days aren't usual."""
    if day.weekday() >= 5:
        return WEEKEND
    return SCHOOL if by_rule(household.school.config, day) else NO_SCHOOL


class NativeLimits:
    """The check, its last findings per person (for Hearth's page), and what the adults were told."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.native_limits.{entry_id}")
        # Notice key -> the finding told ([[weekday, native, budget], ...])
        self.told: dict[str, list[list[Any]]] = {}
        # A per-weekday Switch: entity -> weekday -> {"native", "read" (ISO date)}
        self.switch_days: dict[str, dict[str, dict[str, Any]]] = {}
        # Notice key -> the finding seen on the last look (said once seen twice in a row)
        self._seen: dict[str, list[list[Any]]] = {}
        # Person -> their rows as of the last look
        self.last: dict[str, list[dict[str, Any]]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        told = stored.get("told")
        self.told = {str(k): v for k, v in told.items() if isinstance(v, list)} if isinstance(told, dict) else {}
        days = stored.get("switch_days")
        self.switch_days = (
            {str(k): dict(v) for k, v in days.items() if isinstance(v, dict)} if isinstance(days, dict) else {}
        )

    def _data(self) -> dict[str, Any]:
        return {"told": self.told, "switch_days": self.switch_days}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # The budgets

    def _week(self, today: date) -> list[tuple[str, date]]:
        """Each weekday with its next date from today (today first)."""
        return [(WEEKDAYS[(today + timedelta(days=n)).weekday()], today + timedelta(days=n)) for n in range(7)]

    def budget(self, person: str, groups: tuple[str, ...], day: date) -> int | None:
        """Hearth's budget of the weekday's usual day type: the least of [groups]' (a group with no limit leaves it
        to the others); None when none has one."""
        limits = self.household.week.resolve(person, day, usual_type(self.household, day), with_today=False).limits
        found = [int(v) for g in groups if (v := _minutes(limits.get(g))) is not None and v >= 0]
        return min(found) if found else None

    # The platforms' own limits (weekday -> minutes, NONE or UNKNOWN; a weekday left out isn't known at all)

    def _family_link(self, person: str, enforcer: Enforcer, week: list[tuple[str, date]]) -> dict[str, Any]:
        child = fl.child_of(self.hass, enforcer.entity_id)
        if child is None:
            return {w: UNKNOWN for w, _ in week}
        switch = fl.daily_limit_switch(self.hass, child)
        switch_state = self.hass.states.get(switch) if switch else None
        if switch_state is not None:
            if switch_state.state in _UNREAD:
                return {w: UNKNOWN for w, _ in week}
            if switch_state.state == "off":
                return {w: NONE for w, _ in week}
        held = self.household.enforcement.family_link_devices_held(person)
        today = week[0][1]
        out: dict[str, Any] = {}
        for weekday, day in week:
            limit = fl.weekday_limit(self.hass, child, day)
            minutes = _minutes(limit.get("weekly_minutes")) if limit else None
            if limit is None or limit.get("state") in _UNREAD or minutes is None or (held and day == today):
                # Hearth's hold sets the weekday's limit to 0: not the parent's
                out[weekday] = UNKNOWN
            elif minutes < 0 or minutes >= FULL_DAY:
                out[weekday] = NONE
            else:
                out[weekday] = int(minutes)
        return out

    def _family_safety(self, enforcer: Enforcer, platform: str, week: list[tuple[str, date]]) -> dict[str, Any]:
        temporary = self.household.scheduler.temporary.get(f"{FAMILY_SAFETY}|{enforcer.entity_id}|{platform}")
        out: dict[str, Any] = {}
        for weekday, _day_ in week:
            entity = fs_day_limit_entity(self.hass, enforcer.entity_id, platform, weekday)
            state = self.hass.states.get(entity) if entity else None
            minutes = _minutes(state.state) if state is not None else None
            if minutes is None:
                out[weekday] = UNKNOWN
                continue
            if temporary is not None and temporary.get("weekday") == weekday and minutes == temporary.get("target"):
                minutes = float(temporary["base"])  # Hearth's own raise: the parent's limit is what it raised from
            out[weekday] = NONE if minutes < 0 or minutes >= FULL_DAY else int(minutes)
        return out

    def _switch(self, entity_id: str, week: list[tuple[str, date]]) -> dict[str, Any]:
        enforcement = self.household.enforcement
        today = week[0][1]
        weekday_now = week[0][0]
        state = self.hass.states.get(entity_id)
        hold = enforcement.switch_hold(entity_id)
        if hold is not None:
            current = _minutes(hold.restore.get("max"))  # what letting go puts back
        elif enforcement.switch_quiet(entity_id) or state is None:
            current = None
        else:
            current = _minutes(state.state)
        temporary = self.household.scheduler.temporary.get(entity_id)
        if (
            current is not None
            and temporary is not None
            and temporary.get("platform") == SWITCH
            and temporary.get("day") == today.isoformat()
            and current == temporary.get("target")
        ):
            current = float(temporary["base"])
        now_value: Any = UNKNOWN if current is None else NONE if current < 0 else int(current)
        mode_entity = enforcement._switch_entity(entity_id, "select", "timer_mode")
        mode_state = self.hass.states.get(mode_entity) if mode_entity else None
        mode = mode_state.state if mode_state is not None else None
        if mode not in _UNREAD and mode != NINTENDO_EACH_DAY:
            self.switch_days.pop(entity_id, None)
            return {w: now_value for w, _ in week}  # one limit for every day
        if mode != NINTENDO_EACH_DAY:
            return {weekday_now: now_value}
        # A limit per weekday: today's as read, the others as last read on their own day
        kept = self.switch_days.setdefault(entity_id, {})
        if now_value != UNKNOWN and kept.get(weekday_now, {}).get("native") != now_value:
            kept[weekday_now] = {"native": now_value, "read": today.isoformat()}
            self._save()
        out: dict[str, Any] = {weekday_now: now_value}
        for weekday, _day_ in week[1:]:
            found = kept.get(weekday)
            try:
                fresh = found is not None and today - date.fromisoformat(found["read"]) <= SWITCH_DAY_KEPT
            except (KeyError, TypeError, ValueError):
                fresh = False
            if fresh:
                out[weekday] = found["native"]
        return out

    # The rows

    def _status(self, native: Any, budget: int | None, covered: bool) -> str:
        if native in (UNKNOWN, NONE):
            return native
        if budget is None:
            return NO_BUDGET
        if native >= budget:
            return OK
        return COVERED if covered else BELOW

    def _row(
        self,
        *,
        key: str,
        platform: str,
        name: str,
        via: str,
        entity_id: str,
        people: list[str],
        groups: tuple[str, ...],
        natives: dict[str, Any],
        budgets: dict[str, int | None],
        covered_by: str | None,
        covers_up_to: int = FULL_DAY,
    ) -> dict[str, Any]:
        days = []
        for weekday in WEEKDAYS:
            if weekday not in natives:
                continue
            native, budget = natives[weekday], budgets.get(weekday)
            covered = covered_by is not None and (budget is None or budget <= covers_up_to)
            status = self._status(native, budget, covered)
            day = {"weekday": weekday, "native": native if isinstance(native, int) else None, "budget": budget,
                   "status": status}
            if status in (BELOW, COVERED):
                day["short"] = int(budget - native)
            days.append(day)
        row = {
            "key": key,
            "platform": platform,
            "name": name,
            "via": via,
            "entity_id": entity_id,
            "people": people,
            "groups": list(groups),
            "covered_by": covered_by,
            "days": days,
        }
        row["lines"] = self._lines(row)
        return row

    def rows(self, now: datetime | None = None) -> dict[str, list[dict[str, Any]]]:
        """Every kid's rows now: person -> [row]. A shared Switch's row is in each of its kids' lists."""
        now = dt_util.as_local(now or dt_util.now())
        week = self._week(now.date())
        household = self.household
        scheduler = household.scheduler
        config = scheduler.config
        enforcers = enforcers_from_options(household.options)
        out: dict[str, list[dict[str, Any]]] = {}

        def budgets(person: str, groups: tuple[str, ...]) -> dict[str, int | None]:
            return {weekday: self.budget(person, groups, day) for weekday, day in week}

        for enforcer in enforcers:
            person = enforcer.person
            if enforcer.kind == FAMILY_LINK:
                if household.backstop.enabled():
                    cover = BY_BACKSTOP
                elif config.follow_family_link and person in scheduler.people(config.people):
                    cover = BY_FOLLOW_FL
                else:
                    cover = None
                out.setdefault(person, []).append(
                    self._row(
                        key=f"{NOTICE_PREFIX}{person}_family_link",
                        platform="family_link",
                        name="Family Link",
                        via=FAMILY_LINK,
                        entity_id=enforcer.entity_id,
                        people=[person],
                        groups=(ALL,),
                        natives=self._family_link(person, enforcer, week),
                        budgets=budgets(person, (ALL,)),
                        covered_by=cover,
                    )
                )
            elif enforcer.kind == FAMILY_SAFETY:
                follows = (
                    config.follow_family_safety
                    and person in scheduler.family_safety_people(config.people)
                    and scheduler._fs_limit_wanted(enforcer, config)
                )
                for platform in enforcer.platforms:
                    if platform not in (WINDOWS, XBOX):
                        continue
                    out.setdefault(person, []).append(
                        self._row(
                            key=f"{NOTICE_PREFIX}{person}_{platform.lower()}",
                            platform=platform.lower(),
                            name=platform,
                            via=FAMILY_SAFETY,
                            entity_id=enforcer.entity_id,
                            people=[person],
                            groups=enforcer.groups,
                            natives=self._family_safety(enforcer, platform, week),
                            budgets=budgets(person, enforcer.groups),
                            covered_by=BY_FOLLOW_FS if follows else None,
                        )
                    )
        # A Switch once, with every kid on it: the biggest of their budgets (a kid with none isn't counted)
        switches: dict[str, list[Enforcer]] = {}
        for enforcer in enforcers:
            if enforcer.kind == NINTENDO:
                switches.setdefault(enforcer.entity_id, []).append(enforcer)
        followed = scheduler.nintendo_switches(config.people) if config.follow_nintendo else {}
        for entity_id, on_it in switches.items():
            people = sorted({e.person for e in on_it})
            per_kid = [budgets(e.person, e.groups) for e in on_it]
            biggest: dict[str, int | None] = {}
            for weekday, _day_ in week:
                found = [b[weekday] for b in per_kid if b[weekday] is not None]
                biggest[weekday] = max(found) if found else None
            groups = tuple(sorted({g for e in on_it for g in e.groups}))
            row = self._row(
                key=f"{NOTICE_PREFIX}switch_{entity_id}",
                platform="switch",
                name=switch_name(self.hass, entity_id),
                via=NINTENDO,
                entity_id=entity_id,
                people=people,
                groups=groups,
                natives=self._switch(entity_id, week),
                budgets=biggest,
                covered_by=BY_FOLLOW_SWITCH if entity_id in followed else None,
                covers_up_to=SWITCH_MAX,
            )
            for person in people:
                out.setdefault(person, []).append(row)
        return out

    # The words

    def _what(self, row: dict[str, Any]) -> str:
        if row["via"] == FAMILY_SAFETY:
            return f"{row['name']} (Family Safety)"
        if row["via"] == NINTENDO:
            return f"{row['name']} (Nintendo)"
        return row["name"]

    def _lines(self, row: dict[str, Any]) -> list[str]:
        what = self._what(row)
        lines = []
        below = [d for d in row["days"] if d["status"] == BELOW]
        covered = [d for d in row["days"] if d["status"] == COVERED]
        none = [d for d in row["days"] if d["status"] == NONE]
        if below:
            lines.append(
                f"{what}: its own limit stops them before Hearth's budget on "
                + _said([f"{_day(d['weekday'])} ({d['native']} of {d['budget']} min, {d['short']} short)" for d in below])
            )
        if covered:
            how = (
                "Hearth's Family Link backstop sets each day's limit from Hearth's time left"
                if row["covered_by"] == BY_BACKSTOP
                else "Hearth raises it to the day's budget each day"
            )
            lines.append(
                f"{what}: below Hearth's budget on "
                + _said([f"{_day(d['weekday'])} ({d['native']} of {d['budget']} min)" for d in covered])
                + f"; {how}"
            )
        if none:
            line = (
                f"{what}: no daily limit of its own on {_said([_day(d['weekday']) for d in none])}: nothing caps it "
                "while Home Assistant is down"
            )
            if row["covered_by"] == BY_BACKSTOP:
                line += " (Hearth's Family Link backstop writes today's limit each day)"
            lines.append(line)
        return lines

    def _fix(self, row: dict[str, Any], below: list[dict[str, Any]]) -> str:
        app = APP_NAMES[row["via"]]
        if row["via"] == FAMILY_LINK:
            return (
                f"Raise it in {app}, or turn Hearth's Family Link backstop on (Configure > Enforce; with it off, "
                "\"Family Link's daily limit follows the day's budget\" in Configure > Schedule)."
            )
        if row["via"] == FAMILY_SAFETY:
            return (
                f"Raise it in {app}, or turn on \"Family Safety's daily limits follow the day's budget\" in Hearth's "
                "Configure > Schedule."
            )
        if row["covered_by"] == BY_FOLLOW_SWITCH or any(d["budget"] > SWITCH_MAX for d in below):
            return f"The Switch's limit goes up to {SWITCH_MAX // 60} hours: set no limit in {app} for those days."
        return (
            f"Raise it (or set no limit) in {app}, or turn on \"The Switch's limit follows the day's budget\" in "
            "Hearth's Configure > Schedule."
        )

    # The check

    def view(self, person: str) -> list[dict[str, Any]]:
        """The person's rows as of the last look (Hearth's page)."""
        return self.last.get(person, [])

    def explain(self, person: str, groups: set[str], app: str | None = None) -> list[dict[str, Any]]:
        """hearth.explain's rows: the platforms holding for any of [groups]; for an app, only the platform it's on
        when that's known from its id (an Xbox or Windows app's, an Android package's)."""
        rows = self.rows().get(person, [])
        found = [r for r in rows if set(r["groups"]) & groups]
        if app is not None:
            platform = fs_app_platform(app)
            if platform is not None:
                found = [r for r in found if r["platform"] == platform.lower()]
            elif "." in app and ":" not in app:
                found = [r for r in found if r["via"] == FAMILY_LINK]
        return found

    def check(self, now: datetime | None = None) -> None:
        """Looks again: the rows for Hearth's page, and the adults' notices."""
        now = dt_util.as_local(now or dt_util.now())
        household = self.household
        if household.today != now.date():
            return  # the day isn't worked out yet
        try:
            found = self.rows(now)
        except Exception:  # noqa: BLE001 - a read gone wrong mustn't stop the household
            _LOGGER.exception("Hearth couldn't check the parents' own limits")
            return
        self.last = found
        rows = {r["key"]: r for person_rows in found.values() for r in person_rows}
        for key, row in rows.items():
            self._tell(key, row)
        # A platform no longer set up: its notice goes
        for key in [k for k in self.told if k not in rows]:
            self.told.pop(key, None)
            self._clear(key)
            self._save()
        for key in [k for k in self._seen if k not in rows]:
            self._seen.pop(key, None)

    def _tell(self, key: str, row: dict[str, Any]) -> None:
        if any(d["status"] == UNKNOWN for d in row["days"]):
            self._seen.pop(key, None)
            return  # not all readable: nothing said or taken back on a read cut short
        below = [d for d in row["days"] if d["status"] == BELOW]
        finding = [[d["weekday"], d["native"], d["budget"]] for d in below]
        if not below:
            self._seen.pop(key, None)
            if key in self.told:
                self.told.pop(key)
                self._save()
                self._clear(key)
            return
        if self.told.get(key) == finding:
            if (attention := self._attention()) is not None and attention.item(key) is None:
                self._notify(row, below, phone=False)  # after a restart: back on the bell, not pushed again
            return
        if self._seen.get(key) != finding:
            self._seen[key] = finding  # said once seen on two looks in a row
            return
        self.told[key] = finding
        self._save()
        self._notify(row, below, phone=True)

    def _attention(self):
        return getattr(self.household.hub, "attention", None)

    def _notify(self, row: dict[str, Any], below: list[dict[str, Any]], *, phone: bool) -> None:
        attention = self._attention()
        if attention is None:
            return
        names = _said([self.household.person_name(p) for p in row["people"]])
        what = self._what(row)
        days = _said([f"{_day(d['weekday'])} {d['native']} of {d['budget']} min ({d['short']} short)" for d in below])
        attention.notify(
            Item(
                row["key"],
                f"{names}'s own limit on {what} is below Hearth's budget, so it stops them first: {days}. "
                + self._fix(row, below),
                title=f"{what} limit stops {names} early",
                audience=ADULTS,
                bell=True,
                phone=phone,
                about={"person": row["people"][0]} if len(row["people"]) == 1 else {},
                kind="native_limit",
            )
        )

    def _clear(self, key: str) -> None:
        attention = self._attention()
        if attention is not None and attention.item(key) is not None:
            attention.clear(key, bell_too=True, phone=True)
