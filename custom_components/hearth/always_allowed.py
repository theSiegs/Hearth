"""Always allowed: apps Hearth keeps "Always allowed" in Family Link (docs/home-assistant-integration.md, Always
allowed apps).

Family Link's whole-device holds (Hearth's own device lock, the daily limit at 0; Family Link's bedtime; its School
time) let only the child's Always allowed apps through. Hearth's own pauses never touch Glint and Glint Phone
(enforce.py NEVER_PAUSED), but a locked phone would still stop them. So Hearth keeps a list of apps (the option
always_allowed: package -> "kids" for every kid, or a list of kids; Glint and Glint Phone for every kid when the
option isn't set) Always allowed in Family Link, for every kid with Family Link, through familylink.set_app_daily_limit
minutes -2:

- Only an app installed on the child's devices (Family Link takes it only then), from whole app lists only: a list
  missing or cut short changes nothing. An app installed later gets it at the next look.
- An app already Always allowed is done: nothing is written ("found"; Hearth puts nothing back for it later).
- The write is Hearth's own before its call (saved: "writing", the setting it had in "before"), so a call cut off by
  a reload or failing after it went out is still Hearth's; a refusal before it went out leaves nothing of it. Each
  write is Hearth's own call in the action log, so the outside-change notices never tell it as a parent's (and
  outside_apps leaves out an app made Always allowed that Hearth keeps so for the kid).
- A write that failed, or went through but never showed, is tried again with a doubling wait (RETRY_FIRST up to
  RETRY_MAX); after TELL_AFTER tries the adults are told once.
- Never fighting: once Family Link showed the app Always allowed, a later change of it in Family Link (a time limit,
  no limit of its own, a block) that Hearth didn't make is a parent's. Hearth records it (parent), tells the adults
  once with a "Keep always allowed" button, and doesn't write again until an adult says so (hearth.always_allow for
  that app and kid, which the button runs). The adult's latest word wins: the parent's change in the Family Link app,
  until an adult asks Hearth again. A change Hearth's own calls made (a pause, resume, block or unblock naming the
  app lately) isn't a parent's: it's written again. An app that left the device and comes back isn't either.
- A block wins: Hearth never writes to a blocked app (a limit written to it would unblock it). Hearth's own block
  (hearth.block_app refuses these apps for the kids they're kept for) waits; a parent's block of an app never shown
  Always allowed waits too.
- Taken off the list (hearth.always_allow remove, or the option changed): what Hearth itself wrote is put back to the
  setting it had (a time limit, or no limit of its own), also marked before the call; an app found Always allowed is
  left as it is.

Bedtime: Family Link's bedtime lets the Always allowed apps through only while the child's "Allow apps with unlimited
time during downtime" is on. It is one setting per child and lets every Always allowed app through bedtime (a
parent's Audible or YouTube Music too), so Hearth leaves it alone unless the household option always_allowed_bedtime
is on (off by default): then it is kept on for each kid with an app on the list, the same way (before the call, a
parent's switching it off is theirs until an adult says so: hearth.always_allow bedtime: true). Turned off again, what
Hearth switched on is switched off. hearth.explain says when the setting is off, so Glint stops at bedtime.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import logging
import re
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .activity import call_service
from .attention import ADULTS, NOTICE, Action, Item
from .const import DOMAIN, SIGNAL_PEOPLE
from .entry_tasks import entry_task

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
# Options: the apps kept Always allowed (package -> EVERY_KID or [person]), and whether the child's "Allow apps with
# unlimited time during downtime" is kept on for them
CONF_ALWAYS_ALLOWED = "always_allowed"
CONF_ALWAYS_ALLOWED_BEDTIME = "always_allowed_bedtime"
EVERY_KID = "kids"
GLINT = "com.thesiegs.glint"
GLINT_PHONE = "com.thesiegs.glint.phone"
# With the option not set: the phone launcher and its dialer, for every kid
DEFAULT_APPS: dict[str, Any] = {GLINT: EVERY_KID, GLINT_PHONE: EVERY_KID}
MAX_APPS = 20
# set_app_daily_limit's minutes: unlimited time (Always allowed); the app's own limit off
UNLIMITED = -2
NO_LIMIT = -1
# A write that failed, or went through but doesn't show, is tried again after this, doubling, up to RETRY_MAX
RETRY_FIRST = timedelta(minutes=2)
RETRY_MAX = timedelta(hours=6)
# After a write that went through: Family Link's lists show it within a refresh or two
SETTLE = timedelta(minutes=5)
# The adults are told once after this many tries
TELL_AFTER = 4
# A change Hearth's own calls made: one of these naming the app this long before the last look, or later
OWN_WINDOW = timedelta(minutes=30)
OWN_SERVICES = frozenset(
    {"familylink.pause_app", "familylink.resume_app", "familylink.block_app", "familylink.unblock_app"}
)
# The record of the child's bedtime setting, next to the apps' records
DOWNTIME = "downtime"

# Where an app stands for a kid
ALLOWED = "always_allowed"
WAITING = "not_installed"
PENDING = "pending"
BLOCKED = "blocked"  # a parent's block in Family Link: Hearth leaves it
BLOCKED_BY_HEARTH = "blocked_by_hearth"
PARENT = "parent_changed"
UNKNOWN = "unknown"  # the app lists are missing or cut short
NO_FAMILY_LINK = "no_family_link"

# What a call does
WRITE = "write"
RELEASE = "release"


def configured(options: Any) -> dict[str, Any]:
    """The apps kept Always allowed: package -> EVERY_KID or a list of people (DEFAULT_APPS when the option isn't
    set; an empty one keeps none)."""
    raw = options.get(CONF_ALWAYS_ALLOWED) if hasattr(options, "get") else None
    if not isinstance(raw, dict):
        return dict(DEFAULT_APPS)
    return {
        package: (EVERY_KID if who == EVERY_KID else sorted({p for p in who if isinstance(p, str)}))
        for package, who in raw.items()
        if isinstance(package, str) and (who == EVERY_KID or isinstance(who, list))
    }


def changed_option(
    current: dict[str, Any], apps: list[str], people: list[str] | None, kids: list[str], remove: bool
) -> dict[str, Any]:
    """The option after hearth.always_allow: [apps] kept for [people] (every kid when None), or taken off them."""
    found = {package: (who if who == EVERY_KID else list(who)) for package, who in current.items()}
    for package in apps:
        who = found.get(package)
        if not remove:
            if people is None or who == EVERY_KID:
                found[package] = EVERY_KID
            else:
                found[package] = sorted(set(who or []) | set(people))
            continue
        if who is None:
            continue
        if people is None:
            found.pop(package)
            continue
        left = sorted(set(kids if who == EVERY_KID else who) - set(people))
        if left:
            found[package] = left
        else:
            found.pop(package)
    return found


def _backoff(tries: int) -> timedelta:
    return min(RETRY_FIRST * (2 ** max(tries - 1, 0)), RETRY_MAX)


def _utc(value: Any) -> datetime | None:
    parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
    return dt_util.as_utc(parsed) if parsed is not None else None


class AlwaysAllowed:
    """The apps kept Always allowed in Family Link, brought in step with it (one run at a time)."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.always_allowed.{entry_id}")
        # person -> package (or DOWNTIME) -> record: writing / releasing (ISO, before the call), before (the minutes
        # it had), wrote (ISO), unsure, done (ISO: Family Link showed it), by (hearth or found), gone, parent ({at,
        # now}), tries, next_at (ISO), error, told
        self.records: dict[str, dict[str, dict[str, Any]]] = {}
        # When each kid's lists were last looked at whole, this run
        self._looked: dict[str, datetime] = {}
        self._task: asyncio.Task | None = None
        self._again = False
        self._closed = False

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.records = {
            str(person): {str(k): dict(v) for k, v in apps.items() if isinstance(v, dict)}
            for person, apps in (stored.get("records") or {}).items()
            if isinstance(apps, dict)
        }

    def _data(self) -> dict[str, Any]:
        return {"records": {p: apps for p, apps in self.records.items() if apps}}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 1)

    async def async_flush(self) -> None:
        self._closed = True
        task = self._task
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        await self._store.async_save(self._data())

    # What is kept

    @property
    def bedtime_on(self) -> bool:
        return bool(self.household.options.get(CONF_ALWAYS_ALLOWED_BEDTIME))

    def configured(self) -> dict[str, Any]:
        return configured(self.household.options)

    def apps_for(self, person: str) -> set[str]:
        """The apps Hearth keeps Always allowed for a kid (none for an adult)."""
        if person not in self.household.blocks.kids():
            return set()
        return {package for package, who in self.configured().items() if who == EVERY_KID or person in who}

    def rearm(self, people: list[str], apps: list[str] | None, bedtime: bool = False) -> list[dict[str, str]]:
        """An adult asked again: a parent's change of these apps (or of the bedtime setting) in Family Link is no
        longer kept; Hearth writes them again. Says which."""
        found: list[dict[str, str]] = []
        for person in people:
            records = self.records.get(person, {})
            for key in ([DOWNTIME] if bedtime else []) + list(apps or []):
                record = records.get(key)
                if record is not None and record.pop("parent", None) is not None:
                    for done in ("done", "by", "gone", "tries", "next_at", "error", "told"):
                        record.pop(done, None)
                    found.append({"person": person, "app": key})
        if found:
            self._save()
        return found

    # Bringing Family Link in step

    @callback
    def sync(self) -> None:
        """After each recompute, and after a change here."""
        if self._closed:
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        calls = self._plan(dt_util.utcnow())
        if calls:
            self._task = entry_task(self.hass, self._entry_id, self._async_apply(calls), "hearth always allowed")

    def _record(self, person: str, key: str) -> dict[str, Any]:
        return self.records.setdefault(person, {}).setdefault(key, {})

    @staticmethod
    def ours(record: dict[str, Any]) -> bool:
        """Hearth wrote it (or may have: a call cut off or failing after it went out)."""
        return bool(record.get("writing") or record.get("wrote"))

    @staticmethod
    def _due(record: dict[str, Any], now: datetime) -> bool:
        at = _utc(record.get("next_at"))
        return at is None or now >= at

    def _hearth_touched(self, person: str, package: str, now: datetime) -> bool:
        activity = getattr(self.household, "activity", None)
        if activity is None:
            return False
        since = self._looked.get(person, now) - OWN_WINDOW
        return activity.own_call(OWN_SERVICES, package, since)

    def _plan(self, now: datetime) -> list[tuple[str, str, str, str, Any]]:
        """The calls due: (person, entity_id, key, WRITE or RELEASE, value)."""
        from .outside_apps import read_family_link

        calls: list[tuple[str, str, str, str, Any]] = []
        blocks = self.household.blocks
        has_limit = self.hass.services.has_service(FL_DOMAIN, "set_app_daily_limit")
        dirty = False
        for person in blocks.kids():
            target = blocks.target_of(person)
            if target is None:
                continue
            entity_id, child = target
            records = self.records.get(person, {})
            # A call cut off by a restart: it may have gone out
            for record in records.values():
                if record.get("writing"):
                    record["wrote"] = record.pop("writing")
                    record["unsure"] = True
                    dirty = True
                if record.get("releasing"):
                    record.pop("releasing")
                    record["unsure"] = True
                    dirty = True
            lists = read_family_link(self.hass, child)
            wanted = self.apps_for(person)
            if lists is not None and has_limit:
                self._looked.setdefault(person, now)
                dirty |= self._plan_apps(person, entity_id, lists, wanted, records, now, calls)
                self._looked[person] = now
            dirty |= self._plan_downtime(person, entity_id, child, bool(wanted), now, calls)
        if dirty:
            self._save()
        return calls

    def _plan_apps(
        self, person: str, entity_id: str, lists: dict[str, Any], wanted: set[str], records: dict[str, dict[str, Any]],
        now: datetime, calls: list,
    ) -> bool:
        dirty = False
        installed, always, blocked = lists["installed"], lists["always"], lists["blocked"]
        # Taken off the list: what Hearth wrote goes back to what it had; one found Always allowed stays
        for package in sorted(set(records) - wanted - {DOWNTIME}):
            record = records[package]
            if package in always and self.ours(record) and isinstance(record.get("before"), int) and package not in blocked:
                if self._due(record, now):
                    calls.append((person, entity_id, package, RELEASE, record["before"]))
                continue
            records.pop(package)
            dirty = True
        for package in sorted(wanted):
            record = records.get(package)
            if package not in installed:
                if record is not None and record.get("done") and not record.get("gone"):
                    # Left the device: Always allowed again when it's back is no parent's change
                    record["gone"] = True
                    dirty = True
                continue
            if package in always:
                record = self._record(person, package)
                if not record.get("done") or record.get("gone") or record.get("parent"):
                    record["done"] = now.isoformat()
                    record["by"] = "hearth" if self.ours(record) else "found"
                    for gone in ("gone", "parent", "tries", "next_at", "error", "told"):
                        record.pop(gone, None)
                    dirty = True
                continue
            if record is not None and record.get("parent"):
                continue
            hearths_block = bool(self.household.blocks.why_blocked(person, package))
            if record is not None and record.get("done") and not record.get("gone"):
                if not hearths_block and not self._hearth_touched(person, package, now):
                    self._parent(person, package, record, lists, now)
                    dirty = True
                    continue
                # Hearth's own call changed it: Always allowed again
                for done in ("done", "by", "tries", "next_at"):
                    record.pop(done, None)
                dirty = True
            if package in blocked:
                # A block wins: a limit written to it would unblock it
                continue
            record = self._record(person, package)
            if self._due(record, now):
                if "before" not in record:
                    minutes = lists["limits"].get(package)
                    record["before"] = int(minutes) if isinstance(minutes, int) and minutes > 0 else NO_LIMIT
                    dirty = True
                calls.append((person, entity_id, package, WRITE, UNLIMITED))
        return dirty

    def _plan_downtime(
        self, person: str, entity_id: str, child: str, has_apps: bool, now: datetime, calls: list
    ) -> bool:
        """The child's "Allow apps with unlimited time during downtime", kept on while the option is on."""
        if not self.hass.services.has_service(FL_DOMAIN, "set_downtime_unlimited_apps"):
            return False
        value = fl.downtime_unlimited(self.hass, child)
        records = self.records.get(person, {})
        record = records.get(DOWNTIME)
        if not (self.bedtime_on and has_apps):
            # Off: what Hearth switched on goes back off; nothing else is touched
            if record is None or value is None:
                return False
            if value is True and self.ours(record) and record.get("done"):
                if self._due(record, now):
                    calls.append((person, entity_id, DOWNTIME, RELEASE, False))
                return False
            records.pop(DOWNTIME, None)
            return True
        if value is None:
            return False
        record = self._record(person, DOWNTIME)
        if value:
            if not record.get("done") or record.get("parent"):
                record["done"] = now.isoformat()
                record["by"] = "hearth" if self.ours(record) else "found"
                for gone in ("parent", "tries", "next_at", "error", "told"):
                    record.pop(gone, None)
                return True
            return False
        if record.get("parent"):
            return False
        if record.get("done"):
            self._parent(person, DOWNTIME, record, None, now)
            return True
        if self._due(record, now):
            calls.append((person, entity_id, DOWNTIME, WRITE, True))
        return False

    async def _async_apply(self, calls: list[tuple[str, str, str, str, Any]]) -> None:
        from .enforce import refused_before_sent

        self._again = False
        for person, entity_id, key, what, value in calls:
            record = self._record(person, key)
            mark = "writing" if what == WRITE else "releasing"
            # Hearth's own before the call: a call cut off or failing after it went out is still Hearth's
            record[mark] = dt_util.utcnow().isoformat()
            self._save()
            if key == DOWNTIME:
                service, data = "set_downtime_unlimited_apps", {"entity_id": entity_id, "allow": value}
            else:
                service, data = "set_app_daily_limit", {"entity_id": entity_id, "package_name": key, "minutes": value}
            try:
                await call_service(
                    self.hass, FL_DOMAIN, service, data, blocking=True, person=person,
                    why="always_allowed" if what == WRITE else "always_allowed_off",
                )
            except Exception as err:  # noqa: BLE001 - one app failing mustn't stop the others
                now = dt_util.utcnow()
                record.pop(mark, None)
                if not refused_before_sent(err):
                    # It may have gone through all the same
                    record["unsure"] = True
                    if what == WRITE:
                        record["wrote"] = now.isoformat()
                record["error"] = str(err)[:200] or type(err).__name__
                self._tried(person, key, record, now)
                _LOGGER.warning("Hearth couldn't %s %s for %s in Family Link: %s",
                                "keep" if what == WRITE else "put back", key, person, err)
                self._save()
                continue
            now = dt_util.utcnow()
            record.pop(mark, None)
            record.pop("error", None)
            if what == RELEASE:
                self.records.get(person, {}).pop(key, None)
            else:
                record["wrote"] = now.isoformat()
                record.pop("unsure", None)
                # Not shown by then: written again (a write Family Link took but never showed)
                self._tried(person, key, record, now, SETTLE)
            self._save()
        if calls:
            self.household.enforcement.refresh_soon(calls[-1][1])
            async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)
        if self._again:
            self._again = False
            self._task = None
            self.sync()

    def _tried(self, person: str, key: str, record: dict[str, Any], now: datetime, least: timedelta = timedelta(0)) -> None:
        tries = record["tries"] = int(record.get("tries") or 0) + 1
        record["next_at"] = (now + max(_backoff(tries), least)).isoformat()
        if tries >= TELL_AFTER and not record.get("told"):
            record["told"] = True
            self._tell_not_taken(person, key)

    # Telling

    def _attention(self):
        return getattr(getattr(self.household, "hub", None), "attention", None)

    def _name(self, key: str, person: str) -> str:
        if key == DOWNTIME:
            return "Unlimited apps during downtime"
        return {GLINT: "Glint", GLINT_PHONE: "Glint Phone"}.get(key) or self.household.blocks.name_of(key, person)

    def _parent(self, person: str, key: str, record: dict[str, Any], lists: dict[str, Any] | None, now: datetime) -> None:
        """A parent changed it in Family Link after it showed: theirs until an adult asks Hearth again."""
        if key == DOWNTIME:
            setting = "off"
        elif key in lists["blocked"]:
            setting = "blocked"
        elif isinstance(minutes := lists["limits"].get(key), int):
            setting = f"limit of {minutes} minutes"
        else:
            setting = "no limit of its own"
        record["parent"] = {"at": now.isoformat(), "now": setting}
        _LOGGER.info("%s: %s was changed in Family Link (%s); Hearth leaves it", person, key, setting)
        self.hass.bus.async_fire("hearth_always_allowed_changed", {"person": person, "app": key, "now": setting})
        activity = getattr(self.household, "activity", None)
        if activity is not None:
            activity.add("outside_app_change", person=person, target=[key], reason="always_allowed_off", by="Family Link")
        attention = self._attention()
        if attention is None:
            return
        kid = self.household.person_name(person)
        name = self._name(key, person)
        if key == DOWNTIME:
            text = (
                f"\"Allow apps with unlimited time during downtime\" was switched off for {kid} in Family Link, not by "
                "Hearth, so Glint and the other always allowed apps stop at bedtime. Hearth leaves it off. Switch it on again?"
            )
            data: dict[str, Any] = {"people": [person], "bedtime": True}
        else:
            text = (
                f"{name} was changed for {kid} in Family Link, not by Hearth ({setting}), so it's no longer always "
                "allowed: it stops when the device locks. Hearth leaves it so. Keep it always allowed?"
            )
            data = {"people": [person], "apps": [key]}
        attention.notify(
            Item(
                re.sub(r"[^A-Za-z0-9._]", "_", f"always_allowed_{person}_{key}"),
                text,
                title=f"{kid}: {name} no longer always allowed" if key != DOWNTIME else f"{kid}: always allowed apps stop at bedtime",
                urgency=NOTICE,
                audience=ADULTS,
                actions=(
                    Action("keep", "Keep always allowed" if key != DOWNTIME else "Switch on", f"{DOMAIN}.always_allow", data),
                    Action("not_now", "Not now", dismiss=True),
                ),
                about={"person": person},
                once=True,
            )
        )

    def _tell_not_taken(self, person: str, key: str) -> None:
        attention = self._attention()
        if attention is None:
            return
        kid = self.household.person_name(person)
        name = self._name(key, person)
        attention.notify(
            Item(
                re.sub(r"[^A-Za-z0-9._]", "_", f"always_allowed_failed_{person}_{key}"),
                f"Hearth couldn't make {name} always allowed for {kid} in Family Link yet. It keeps trying, less often.",
                title=f"{kid}: {name} not always allowed yet",
                urgency=NOTICE,
                audience=ADULTS,
                about={"person": person},
                once=True,
            )
        )

    # Views

    def state_of(self, person: str, package: str, lists: dict[str, Any] | None, target: Any) -> str:
        if target is None:
            return NO_FAMILY_LINK
        if lists is None:
            return UNKNOWN
        record = self.records.get(person, {}).get(package) or {}
        if package not in lists["installed"]:
            return WAITING
        if package in lists["always"]:
            return ALLOWED
        if record.get("parent"):
            return PARENT
        if package in lists["blocked"]:
            return BLOCKED_BY_HEARTH if self.household.blocks.why_blocked(person, package) else BLOCKED
        return PENDING

    def _bedtime_view(self, person: str, child: str | None) -> dict[str, Any]:
        value = fl.downtime_unlimited(self.hass, child) if child else None
        record = self.records.get(person, {}).get(DOWNTIME) or {}
        view: dict[str, Any] = {
            # The child's "Allow apps with unlimited time during downtime": True, False, None (not read)
            "on": value,
            "kept_by_hearth": self.bedtime_on,
        }
        if record.get("parent"):
            view["parent"] = record["parent"]
        if record.get("error"):
            view["error"] = record["error"]
        return view

    def page(self) -> dict[str, Any]:
        """For Hearth's page and hearth/config: the list, the bedtime option, and each kid's apps."""
        from .outside_apps import read_family_link

        kids: list[dict[str, Any]] = []
        blocks = self.household.blocks
        for person in blocks.kids():
            target = blocks.target_of(person)
            lists = read_family_link(self.hass, target[1]) if target else None
            apps = []
            for package in sorted(self.apps_for(person)):
                record = self.records.get(person, {}).get(package) or {}
                view: dict[str, Any] = {
                    "app": package,
                    "name": self._name(package, person),
                    "state": self.state_of(person, package, lists, target),
                }
                if record.get("by"):
                    view["by"] = record["by"]
                if record.get("parent"):
                    view["parent"] = record["parent"]
                if record.get("error"):
                    view["error"] = record["error"]
                apps.append(view)
            kids.append(
                {
                    "person": person,
                    "name": self.household.person_name(person),
                    "family_link": target is not None,
                    "apps": apps,
                    "bedtime": self._bedtime_view(person, target[1] if target else None),
                }
            )
        return {
            "apps": self.configured(),
            "default": not isinstance(self.household.options.get(CONF_ALWAYS_ALLOWED), dict),
            "bedtime": self.bedtime_on,
            "kids": kids,
        }

    def explain(self, person: str, app: str) -> dict[str, Any] | None:
        """hearth.explain's always_allowed: whether the app is Always allowed (kept by Hearth, or a parent's in Family
        Link), where it stands, and whether Family Link's bedtime stops it. None when it's neither."""
        from .outside_apps import read_family_link

        kept = app in self.apps_for(person)
        target = self.household.blocks.target_of(person)
        child = target[1] if target else None
        read = fl.always_allowed_apps(self.hass, child) if child else None
        in_family_link = read is not None and app in read[0]
        if not kept and not in_family_link:
            return None
        lists = read_family_link(self.hass, child) if child else None
        state = self.state_of(person, app, lists, target) if kept else ALLOWED
        if kept and state == UNKNOWN and in_family_link:
            state = ALLOWED
        bedtime = self._bedtime_view(person, child)
        name = self._name(app, person)
        if state == ALLOWED:
            text = f"{name} is always allowed in Family Link" + (" (Hearth keeps it so)" if kept else "") + (
                ": it works through Hearth's device lock and Family Link's daily limit."
            )
            if bedtime["on"] is False:
                text += (
                    " Family Link's bedtime stops it: \"Allow apps with unlimited time during downtime\" is off for "
                    f"{self.household.person_name(person)}."
                )
            elif bedtime["on"] is True:
                text += " It works at bedtime too (\"Allow apps with unlimited time during downtime\" is on)."
            else:
                text += " Whether it works at bedtime isn't known (the downtime setting can't be read)."
        elif state == PARENT:
            text = f"{name} was changed in Family Link by a parent, so it isn't always allowed; Hearth leaves it so."
        elif state == WAITING:
            text = f"{name} isn't installed: Hearth makes it always allowed once Family Link lists it."
        elif state in (BLOCKED, BLOCKED_BY_HEARTH):
            text = f"{name} is blocked in Family Link: a block wins, so Hearth doesn't make it always allowed."
        elif state == NO_FAMILY_LINK:
            text = f"Hearth keeps {name} always allowed for kids with Family Link; none is set up for this kid."
        else:
            text = f"Hearth is making {name} always allowed in Family Link."
        return {
            "by": "hearth" if kept else "family_link",
            "state": state,
            "stopped_at_bedtime": bedtime["on"] is False if state == ALLOWED else None,
            "bedtime": bedtime,
            "text": text,
        }
