"""Enforcing: when a person's group is out of time, the other parental controls hold its apps too.

Hearth's own devices are told in their state document (a TV or phone stops the group's apps itself). The household can
add, per person, the parental controls of other integrations (Configure > Enforce):

- Family Link (the HAFamilyLink integration): the group's Android apps are paused (familylink.pause_app: a 1 minute
  daily limit, the app stays installed) and resumed (resume_app puts back the setting they had). Google TV ignores app
  limits, which is why a TV is held by Hearth. All screen time out of time locks the person's devices instead: today's
  daily limit goes to 0 (familylink.set_daily_limit, every device of the child), so apps a parent gave unlimited time
  (YouTube Music, say) still work, as when Family Link's own limit is reached. The limit they had is kept and put back
  when there's time again, and before midnight: it's the weekday's setting, not today's only. It's put back only while
  the limit still reads 0: a limit a parent changed meanwhile in the Family Link app is theirs and stays (kept_current).
- Microsoft Family Safety: a platform (Xbox, Windows) is locked until midnight while one of the chosen groups (Games, All
  screen time) is out of time, and unlocked when it isn't (lock_platform with until, naming the child by the chosen
  entity; an older Family Safety, upstream's, gets the account sensor's user_id and whole hours, and Hearth unlocks
  it itself at midnight while it's still Hearth's: async_lock_ends_tick). An unlock that finds the hold ran out, a
  parent's own lock in force, or nothing locked is fine: Family Safety leaves a parent's lock alone (upstream's 2.3.0
  cancels any lock in force; from the release with its #94 it puts back what the lock replaced).
  When the lock ends is kept with what's held: where Family Safety doesn't say whose a lock is (no hold attribute:
  the released one), Hearth tells its own from a parent's by it (fs_derived_hold).
  A group may list Xbox and Windows apps too (Family Safety's app ids: x:... Xbox, appx:... or win32:... Windows).
  While any group with such apps is out of time, those of the chosen platforms are paused (microsoft_family_safety.
  pause_app: a block that keeps whether the app was blocked before; a parent's own block is left alone) and resumed
  when it has time again, unless their platform is locked anyway. An older Family Safety without pause_app is skipped.
- Nintendo Switch Parental Controls (built in): while one of the chosen groups (Games, All screen time) is out of time,
  the Switch's Max screentime today is set to 0 with Suspend software on, which suspends the game. Letting go puts back
  the limit and the Suspend software setting it had (kept with what's held). The limit is a setting of the Switch's (of
  every day, or of this weekday), not of today only, so it's put back before midnight. As with Family Link, only while
  it still reads 0: a limit a parent set meanwhile in the Nintendo app stays, with the Switch's other settings.
  An adult's pause holds the Switch the same way: a family pause of the person, or a pause of a group the enforcer
  covers (Games, say), until the pause ends (a shared Switch only while the person is the one playing, let go before
  midnight as above). A parent's grant from the Nintendo app lifts it; an allow doesn't, as for any pause.
  The schedule's extra minutes on a day off or half day (schedule.py, bonus_nintendo) go into the limit a hold puts
  back while it holds, and come out of it again when they're called off or the day ends.

- Hearth's own app blocks (app_blocks.py): an app Hearth blocks is left out of every Family Link hold below; one held
  when it was blocked stays as held (no resume) until it is unblocked.

- School time (Family Link): the apps chosen per person ("During School time, pause these apps", Google Messages by
  default in the form) are paused while the child's School time is on (any of their devices says so), through the same
  hold: Family Link's pause_app keeps one saved setting per child and app, and any resume puts it back, so Hearth is the
  only one pausing and resuming, and an app is resumed only when no reason to hold it is left (its group out of time,
  School time). Chosen apps may include ones a budget never holds (Messages), never Hearth's own or Family Link's.

- The weekly schedule (weekly.py): a mode that closes groups (Homework) holds them through the same holds as a group
  out of time (Family Link's app pauses, Family Safety's platform lock and app pauses, the Switch), and Sleep and School
  hold Family Safety's platforms and the Switch (schedule_wanted). Family Link keeps its own bedtime and School time.

- Extra time at bedtime (bedtime_lift.py): an adult's extra time of All screen time given in bedtime lifts the
  schedule's Sleep and the bedtime locks while it lasts, so Sleep's holds above are let go; Family Link's bedtime
  tonight is moved to start when the extra time ends (a today-only override) and put back after, only while it still
  reads Hearth's start.

An adult's allow (hearth.allow, exceptions.py) takes its app or group out of every hold above while it lasts. A
parent's grant (a change in the Family Link, Nintendo or Family Safety app, grants.py) takes out only the hold it came
from.

An app in the built-in Accessibility pool (Voice Access, Lookout, Live Transcribe) or System screens (the home screen,
Family Link's lock screen, keyboards) is never paused by any of these: a budget, a pause, School time's apps or the
schedule (household.never_held). Family Link's whole-device lock (All
screen time out of time) is Google's and spares only the apps a parent gave unlimited time there.

What's held is kept with Home Assistant's storage helper, so only what Hearth held is let go, after a restart too. A
group gets time again (a bonus, a new day, a higher budget) and its apps are let go. Right after Home Assistant starts,
nothing is let go for a few minutes: the sources haven't all reported yet, and the counts would look low.

Another parental control is another kind here: what it holds, and the services that hold and let go.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging
import math
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import CALLBACK_TYPE, HomeAssistant, SupportsResponse, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_call_later
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import DOMAIN, SIGNAL_PEOPLE
from .entry_tasks import entry_task
from . import family_link as fl
from .counting import ALL
from .exceptions import Lifted, end_of_day
from .activity import call_service

if TYPE_CHECKING:
    from .household import PersonDay

_LOGGER = logging.getLogger(__name__)

CONF_ENFORCE = "enforce"
FAMILY_LINK = "family_link"
FAMILY_SAFETY = "family_safety"
NINTENDO = "nintendo"
KINDS = (FAMILY_LINK, FAMILY_SAFETY, NINTENDO)
PLATFORMS = ("Xbox", "Windows", "Mobile")
DEFAULT_FS_GROUPS = ("games", ALL)
DEFAULT_NINTENDO_GROUPS = ("games", ALL)
NINTENDO_DOMAIN = "nintendo_parental_controls"
FS_DOMAIN = "microsoft_family_safety"
# What unlock_platform answers when Hearth's lock is gone without undoing anything: all fine
UNLOCK_DONE = ("hold_expired", "left_parent_override", "not_locked", "bonus_kept")
# What a Nintendo enforcer holds: the person's Switch (its entity is the Switch's Max screentime today)
SWITCH = "Switch"
# What a Family Link enforcer holds for All screen time: the child's devices, locked by a daily limit of 0 (never a
# package name: those have dots)
DEVICES = "Devices"
# What wanted() asks for when daily time is out but a category stays open: every installed app but that category's
# and the system's (Enforcement.update fills it in; never held as such)
ALL_APPS = "@all_apps"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
# A Switch's limit is put back this long before midnight: after it, "today" is another day's setting
NINTENDO_LET_GO_BEFORE_MIDNIGHT = timedelta(minutes=2)
NINTENDO_EACH_DAY = "each_day_of_the_week"
# Nothing is let go this long after Home Assistant starts (the sources report in first)
SETTLE = timedelta(minutes=5)
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
# Family Link's lock_override_code of a device a parent unlocked
FL_UNLOCK_CODE = 4
# Family Safety's hold attribute (Allowed Now sensors, platform lock switches): who decides the lock now
FS_HOLD_OURS = "ours"
FS_HOLD_PARENT = "parent"
FS_HOLD_BONUS_OURS = "bonus_ours"
FS_HOLD_NONE = "none"
# held.restore keys of a Family Safety lock by whole hours: when Hearth unlocks it itself (platform -> ISO), and the
# platforms it did (its lock over on time, as a lock with an end would be)
FS_UNLOCK_AT = "fs_unlock_at"
FS_LOCK_ENDED = "fs_lock_ended"
FS_ALLOW_UNTIL = "allowUntil"
FS_BLOCK_UNTIL = "blockUntil"
# A lock or extra time Microsoft shows ending within this of the end Hearth asked for is Hearth's (its clock and
# Microsoft's differ by seconds)
FS_OWN_TOLERANCE = timedelta(minutes=2)
# Where a hold state came from: Family Safety's own hold attributes (a Family Safety that keeps them), or Hearth's own
# record of what it asked for against what Family Safety shows (upstream's)
FS_FROM_ATTRIBUTES = "attributes"
FS_FROM_HEARTH = "hearth"
# What letting go did: put back what was there before, or kept what a parent set meanwhile
RESTORED = "restored"
KEPT_CURRENT = "kept_current"
# Why an item is held (status_of's why)
WHY_BUDGET = "budget"
WHY_SCHOOL = "school_time"
WHY_PAUSE = "pause"
WHY_SCHEDULE = "schedule"
# A Family Link pause Hearth keeps as it was while the app is blocked (app_blocks.py): neither paused nor resumed
WHY_BLOCKED = "blocked_app"
# A change seen this soon after Hearth's own call is taken as Hearth's (the integration catching up), not a parent's
QUIET_AFTER_CALL = timedelta(minutes=1)
# After a write to Family Link, Family Safety or Nintendo, their entities are refreshed once this much later (their own
# polling is a minute to five): what Hearth locked or let go shows within seconds
REFRESH_AFTER_WRITE = timedelta(seconds=10)
MAX_PACKAGES = 150

# Never paused, whatever category they're in: calls (the dialer and contacts, so an emergency call always works), the
# system, and the apps that hold the rest. Messages apps are NOT here: daily time, a limit, bedtime
# and Pause screens pause them like any app, and hearth.block_app may block them. A paired client's
# own packages are kept out per person instead (Enforcement.update's exempt_of, from the client locked at pairing).
# TRANSITION: the phone launcher's two packages stay listed until its phones have re-paired with contract 3 (then
# they're exempt by their locked client id); remove them in the release after that.
TRANSITION_CLIENTS = frozenset({"com.thesiegs.glint", "com.thesiegs.glint.phone"})
# Clock and alarm apps: a kid can always set a morning alarm, even with no time left, at bedtime or in School time.
# Google's, AOSP's, Samsung's, OnePlus's, OPPO's and realme's, LG's
CLOCKS = frozenset(
    {
        "com.google.android.deskclock",
        "com.android.deskclock",
        "com.sec.android.app.clockpackage",
        "com.oneplus.deskclock",
        "com.coloros.alarmclock",
        "com.lge.clock",
    }
)
ESSENTIAL = TRANSITION_CLIENTS | CLOCKS | frozenset(
    {
        "com.thesiegs.hearth",
        "com.thesiegs.hearth.mobile",
        "com.thesiegs.hearthtube.mobile",
        "com.google.android.gms",
        "com.google.android.dialer",
        "com.google.android.contacts",
        "com.google.android.apps.kids.familylink",
        "com.google.android.apps.kids.familylinkhelper",
        "com.samsung.android.dialer",
        "com.samsung.android.app.contacts",
        "com.android.settings",
        "com.android.vending",
    }
)


def essential(package: str) -> bool:
    return package in ESSENTIAL or package.startswith("com.android.") or package == "android"


# Never paused for School time either: what holds the rest, and the system
NEVER_PAUSED = TRANSITION_CLIENTS | CLOCKS | frozenset(
    {
        "com.thesiegs.hearth",
        "com.thesiegs.hearth.mobile",
        "com.google.android.gms",
        "com.google.android.apps.kids.familylink",
        "com.google.android.apps.kids.familylinkhelper",
        "com.android.settings",
        "com.android.vending",
    }
)
DEFAULT_SCHOOL_TIME_APPS = ("com.google.android.apps.messaging",)
# Keyboards and voice typing: pausing one breaks typing in the apps left open (Messages during a Messaging bonus).
# Gboard, Samsung Keyboard, SwiftKey (and its beta), Fleksy, Grammarly's keyboard, and Google's speech services (Gboard's
# voice typing runs there). Not the Google app (googlequicksearchbox): it's a whole app with search and browsing, and
# voice typing doesn't need it. Anything Hearth's categories confidently put in System screens is spared too
# (household.never_held)
KEYBOARDS = frozenset(
    {
        "com.google.android.inputmethod.latin",
        "com.samsung.android.honeyboard",
        "com.touchtype.swiftkey",
        "com.touchtype.swiftkey.beta",
        "com.syntellia.fleksy.keyboard",
        "com.grammarly.android.keyboard",
        "com.google.android.tts",
    }
)
# The explicit system list: never paused, by name (calls, the clock, Settings, Play services, Family Link, the Play
# Store, Hearth and Glint, the keyboards). The per-app path (Enforcement._all_apps_but) and the state document's
# never_paused both read it
SYSTEM_NEVER_PAUSED = ESSENTIAL | NEVER_PAUSED | KEYBOARDS | frozenset({"android"})

# Family Safety's app ids that pause_app takes, by platform (a: is a phone app: not paused, Family Link has the phone)
# First match wins: Microsoft Store apps are x:windowsplt:..., so that prefix comes before the Xbox's plain x:
FS_APP_PREFIXES = {"x:windowsplt:": "Windows", "x:": "Xbox", "appx:": "Windows", "win32:": "Windows"}


def fs_app_platform(item: str) -> str | None:
    """The platform of a Family Safety app id (x:windowsplt:..., appx:... or win32:... Windows; other x:... Xbox), None for
    anything else."""
    return next((platform for prefix, platform in FS_APP_PREFIXES.items() if item.startswith(prefix)), None)


def fs_app(item: str) -> bool:
    return fs_app_platform(item) is not None


def school_pausable(package: str) -> bool:
    return package not in NEVER_PAUSED and package != "android" and "." in package and " " not in package


@dataclass(frozen=True)
class Enforcer:
    """One parental control holding one person's apps."""

    kind: str
    person: str
    entity_id: str
    groups: tuple[str, ...] = ()
    platforms: tuple[str, ...] = ()
    # A shared Switch: entities that are on while this person is the one playing (the Nintendo integration's player
    # "playing" sensor, or friend presence). With any, the Switch is held only while one of them is on, so a brother
    # or sister with time left can play
    playing: tuple[str, ...] = ()
    # Family Link: apps paused while the child's School time is on
    school_apps: tuple[str, ...] = ()

    @property
    def key(self) -> str:
        # A person can be on two Switches: each is its own hold
        if self.kind == NINTENDO:
            return f"{self.kind}|{self.person}|{self.entity_id}"
        return f"{self.kind}|{self.person}"


def key_parts(key: str) -> tuple[str, str]:
    """(kind, person) of an enforcer's key (a Switch's key also names its entity)."""
    parts = key.split("|")
    return parts[0], parts[1] if len(parts) > 1 else ""


def enforcers_from_options(options: dict[str, Any]) -> list[Enforcer]:
    found: list[Enforcer] = []
    for raw in options.get(CONF_ENFORCE, []):
        kind, person, entity_id = raw.get("kind"), raw.get("person"), raw.get("entity_id")
        if kind not in KINDS or not person or not entity_id:
            continue
        groups = tuple(raw.get("groups") or ())
        platforms = tuple(p for p in raw.get("platforms") or () if p in PLATFORMS)
        if kind == FAMILY_SAFETY:
            groups = groups or DEFAULT_FS_GROUPS
            platforms = platforms or ("Xbox",)
        elif kind == NINTENDO:
            groups = groups or DEFAULT_NINTENDO_GROUPS
        playing = tuple(e for e in raw.get("playing") or () if isinstance(e, str)) if kind == NINTENDO else ()
        school_apps = (
            tuple(p.strip() for p in raw.get("school_time_apps") or () if isinstance(p, str) and school_pausable(p.strip()))
            if kind == FAMILY_LINK
            else ()
        )
        found.append(Enforcer(kind, person, entity_id, groups, platforms, playing, school_apps))
    return found


def out_of_time(day: PersonDay | None, groups: tuple[str, ...], lifted: Lifted | None = None) -> list[str]:
    """The person's groups (of [groups], or any) with no minutes left, but those an allow lifts."""
    if day is None:
        return []
    return sorted(
        group_id
        for group_id, state in day.limits.items()
        if state.minutes_left == 0
        and (not groups or group_id in groups)
        and not (lifted is not None and lifted.group(group_id))
    )


def wanted(
    enforcer: Enforcer,
    day: PersonDay | None,
    apps_of,
    now: datetime | None = None,
    playing: bool | None = None,
    lifted: Lifted | None = None,
    groups_of_app=None,
) -> set[str]:
    """What the enforcer should hold now for budgets: packages for Family Link, platforms for Family Safety, the
    Switch for Nintendo ([playing]: whether the person is the one on a shared Switch, None when that isn't known).
    What an allow lifts ([lifted]; an app's groups from [groups_of_app]) isn't held."""
    closed = out_of_time(day, enforcer.groups, lifted)
    if enforcer.kind == FAMILY_SAFETY:
        platforms = set(enforcer.platforms) if closed else set()
        # The Xbox and Windows apps of any group out of time, on the chosen platforms that aren't locked whole
        apps: set[str] = set()
        for group_id in out_of_time(day, (), lifted):
            if group_id != ALL:
                apps |= {
                    p
                    for p in apps_of(group_id, enforcer.person)
                    if fs_app_platform(p) in enforcer.platforms and fs_app_platform(p) not in platforms
                }
        if lifted:
            apps = {p for p in apps if not lifted.app(p, groups_of_app(p) if groups_of_app else None)}
        return platforms | set(sorted(apps)[:MAX_PACKAGES])
    if enforcer.kind == NINTENDO:
        return {SWITCH} if closed and not near_midnight(now) and playing is not False else set()
    packages: set[str] = set()
    if enforcer.kind == FAMILY_LINK and ALL in closed:
        # All screen time out of time: the devices are locked (apps with unlimited time still work); let go just
        # before midnight, as the limit is the weekday's. While a category stays open (lifted.open: its own bonus
        # or an allow, spendable, with an app of it installed), every installed app of the kid but that category's
        # and the system's is paused instead (ALL_APPS: Enforcement.update fills it in from Family Link's lists)
        closed = [g for g in closed if g != ALL]
        if near_midnight(now):
            held = set()
        else:
            held = {ALL_APPS} if lifted is not None and lifted.open else {DEVICES}
    else:
        held = set()
    for group_id in closed:
        # essential() spares com.android.* here: a category's own apps are never Android's system packages but by
        # a misfiled sort, and those mustn't be paused; the whole-device path below names its exceptions instead
        packages |= {p for p in apps_of(group_id, enforcer.person) if not essential(p) and not fs_app(p)}
    if lifted:
        packages = {p for p in packages if not lifted.app(p, groups_of_app(p) if groups_of_app else None)}
    # No cap: Family Link's pause_app takes any number (Enforcement.update keeps the installed ones first)
    return held | packages


def near_midnight(now: datetime | None = None) -> bool:
    """Too close to midnight to hold a weekday's setting (a Switch's limit, Family Link's daily limit): let go now."""
    now = now or dt_util.now()
    return dt_util.start_of_local_day(now + timedelta(days=1)) - now <= NINTENDO_LET_GO_BEFORE_MIDNIGHT


def paused_switch(
    enforcer: Enforcer, groups: set[str], now: datetime | None = None, playing: bool | None = None
) -> set[str]:
    """The Switch, held for an adult's pause ([groups]: the person's paused groups, All screen time for a family
    pause): a family pause holds it, a pause of a group holds it when the enforcer covers that group (Games, say).
    As for a budget, a shared Switch only while the person is the one playing, and let go before midnight."""
    if enforcer.kind != NINTENDO or not groups:
        return set()
    if ALL not in groups and not groups & set(enforcer.groups):
        return set()
    return {SWITCH} if not near_midnight(now) and playing is not False else set()


def school_wanted(enforcer: Enforcer, school_time: bool, lifted: Lifted | None = None, groups_of_app=None) -> set[str]:
    """The School-time apps to pause now (Family Link): while School time is on, but those an allow lifts."""
    if enforcer.kind != FAMILY_LINK or not school_time:
        return set()
    return {
        p
        for p in enforcer.school_apps
        if not (lifted and lifted.app(p, groups_of_app(p) if groups_of_app else None))
    }


def paused_wanted(enforcer: Enforcer, packages: set[str], fs_pauses_apps: bool = True) -> set[str]:
    """The apps an adult paused for the person (hearth.pause with an app or group): Family Link's packages, Family
    Safety's Xbox and Windows apps on its chosen platforms. An allow doesn't lift them."""
    if enforcer.kind == FAMILY_LINK:
        return set(sorted(p for p in packages if not essential(p) and not fs_app(p))[:MAX_PACKAGES])
    if enforcer.kind == FAMILY_SAFETY and fs_pauses_apps:
        return set(sorted(p for p in packages if fs_app(p) and fs_app_platform(p) in enforcer.platforms)[:MAX_PACKAGES])
    return set()


def schedule_wanted(
    enforcer: Enforcer,
    closed: set[str],
    apps_of,
    now: datetime | None = None,
    playing: bool | None = None,
    lifted: Lifted | None = None,
    groups_of_app=None,
    fs_pauses_apps: bool = True,
) -> set[str]:
    """What the weekly schedule holds now (weekly.py): [closed] is the groups its mode closes (Homework's), and All
    screen time during Sleep and School. Family Link pauses the closed groups' apps (its own bedtime and School time do
    the rest); Family Safety locks a chosen platform when one of its groups is closed (or All, at bedtime) and pauses
    the closed groups' Xbox and Windows apps; the Switch is held when one of its groups is closed. An allow of a group
    or app lifts a closed group as it lifts a budget's hold; Sleep and School are locks, which an allow doesn't lift."""
    if not closed:
        return set()
    groups = {g for g in closed if g == ALL or not (lifted and lifted.group(g))}
    if not groups:
        return set()
    if enforcer.kind == NINTENDO:
        return paused_switch(enforcer, groups, now, playing)
    found: set[str] = set()
    if enforcer.kind == FAMILY_SAFETY:
        if ALL in groups or groups & set(enforcer.groups):
            found |= set(enforcer.platforms)
        if fs_pauses_apps:
            for group_id in groups - {ALL}:
                found |= {
                    p
                    for p in apps_of(group_id, enforcer.person)
                    if fs_app(p) and fs_app_platform(p) in enforcer.platforms and fs_app_platform(p) not in found
                }
    elif enforcer.kind == FAMILY_LINK:
        for group_id in groups - {ALL}:
            found |= {p for p in apps_of(group_id, enforcer.person) if not essential(p) and not fs_app(p)}
    if lifted:
        found = {p for p in found if p in enforcer.platforms or not lifted.app(p, groups_of_app(p) if groups_of_app else None)}
    return set(sorted(found)[:MAX_PACKAGES])


@dataclass
class Held:
    items: set[str] = field(default_factory=set)
    entity_id: str | None = None
    error: str | None = None
    failed_at: datetime | None = None
    # What letting go puts back (a Switch's limit and Suspend software, as they were before the hold)
    restore: dict[str, Any] = field(default_factory=dict)


class Enforcement:
    """What each enforcer holds, brought in step with what it should (after every recompute, one run at a time)."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._entry_id = entry_id
        # Set by async_flush (the entry is unloading): no new enforcement pass starts after it
        self._closed = False
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.enforce.{entry_id}")
        self.held: dict[str, Held] = {}
        self.enforcers: list[Enforcer] = []
        # When Home Assistant started, not this entry: an entry reload (any setting saved) mustn't hold everything
        # for another SETTLE. Kept outside the entry, as the pairings are
        self.started: datetime = hass.data.setdefault(f"{DOMAIN}_enforce_started", {}).setdefault(
            entry_id, dt_util.utcnow()
        )
        self._wanted: dict[str, set[str]] = {}
        self._task: asyncio.Task | None = None
        self._again = False
        # What Hearth last did through each parental control, by enforcer key: {at, held, let_go, outcomes, error}
        self.last: dict[str, dict[str, Any]] = {}
        # Enforcers whose calls are under way, and when changes they cause have surely shown (not a parent's)
        self._busy: set[str] = set()
        # Called after each run (native_sync.py watches what's held then)
        self.on_applied = None
        self._quiet_until: dict[str, datetime] = {}
        # Why each wanted item is held, by enforcer key: {item: budget, school_time or pause} (for Hearth's page)
        self._why: dict[str, dict[str, str]] = {}
        # The refreshes waiting after a write, by entity: one each at a time
        self._refresh: dict[str, CALLBACK_TYPE] = {}
        # When the extra time Hearth last gave on a Family Safety platform today ends: (person, platform) -> datetime
        # or None (native_sync.py sets it). With what Hearth locked, how Hearth tells its own from a parent's
        self.fs_bonus_until = None
        # The values Hearth's Family Link backstop wrote today (backstop.py sets it): never put back as a weekday's limit
        self.backstop_values = None
        # The action log (activity.py; the household sets it): each hold started and ended
        self.activity = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for key, data in stored.get("held", {}).items():
            self.held[key] = Held(
                set(data.get("items", [])), data.get("entity_id"), restore=dict(data.get("restore") or {})
            )
        self.last = {key: dict(record) for key, record in (stored.get("last") or {}).items() if isinstance(record, dict)}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    def _data(self) -> dict[str, Any]:
        return {
            "held": {
                key: {"items": sorted(h.items), "entity_id": h.entity_id, "restore": h.restore}
                for key, h in self.held.items()
                if h.items or h.restore
            },
            # What Hearth last did through each parental control: kept over a restart for Hearth's page
            "last": self.last,
        }

    async def async_flush(self) -> None:
        self._closed = True
        for cancel in self._refresh.values():
            cancel()
        self._refresh.clear()
        task = self._task
        if task is not None and not task.done():
            task.cancel()
            # Wait for it to stop, so nothing of this instance saves after the store below (a reload's new
            # instance loads from it)
            await asyncio.gather(task, return_exceptions=True)
        await self._store.async_save(self._data())

    def held_for(self, person: str) -> dict[str, Any]:
        """A person's held things and the last error, for their sensor."""
        found: dict[str, Any] = {}
        for key, held in self.held.items():
            kind, who = key_parts(key)
            if who == person and (held.items or held.error):
                was = found.get(kind, {"held": [], "error": None})
                found[kind] = {"held": sorted(set(was["held"]) | held.items), "error": was["error"] or held.error}
        return found

    @callback
    def note(self, key: str, **what: Any) -> None:
        """What Hearth just did through a parental control (and whether it took), for Hearth's page: the last of
        each enforcer, kept over a restart."""
        record = {"at": dt_util.utcnow().isoformat(), "ok": not what.get("error")}
        record.update({k: v for k, v in what.items() if v not in (None, [], {})})
        self.last[key] = record
        self._save()

    def status_of(self, person: str) -> dict[str, Any]:
        """Per parental control of the person's: what's held now, the last error and what Hearth last did."""
        found: dict[str, Any] = {}
        keys = {e.key for e in self.enforcers if e.person == person}
        keys |= {k for k in self.held if key_parts(k)[1] == person}
        keys |= {k for k in self.last if key_parts(k)[1] == person}
        for key in sorted(keys):
            kind = key_parts(key)[0]
            held = self.held.get(key) or Held()
            was = found.get(kind)
            # Two Switches of one person show as one Nintendo line: what either holds, the first error, the latest
            last = self.last.get(key)
            if was is not None and was["last"] is not None and (last is None or was["last"]["at"] > last["at"]):
                last = was["last"]
            why = {**(was["why"] if was else {}), **{i: r for i, r in self._why.get(key, {}).items() if i in held.items}}
            found[kind] = {
                "held": sorted(set(was["held"] if was else []) | held.items),
                # Why each held item is held: budget, school_time or pause
                "why": why,
                "error": (was["error"] if was else None) or held.error,
                "failed_at": (was["failed_at"] if was else None)
                or (held.failed_at.isoformat() if held.failed_at else None),
                "last": last,
            }
        return found

    @callback
    def update(
        self,
        enforcers: list[Enforcer],
        days: dict[str, PersonDay],
        apps_of,
        lifted_of=None,
        school_time_of=None,
        groups_of_app=None,
        granted_of=None,
        paused_of=None,
        device_lifted_of=None,
        paused_groups_of=None,
        closed_of=None,
        spared=frozenset(),
        exempt_of=None,
        blocked_of=None,
        budget_lifted_of=None,
    ) -> None:
        """[apps_of]: a group id's packages for a person (for All screen time, every app of theirs). [lifted_of]: what
        a person's allows lift (Lifted); [school_time_of]: whether an enforcer's child is in School time now;
        [groups_of_app]: an app's groups; [granted_of]: what a person's parent grants lift, by enforcer kind (the
        held items: grants.py); [paused_of]: the packages an adult paused for a person; [device_lifted_of]: what extra
        time on one device lifts of an enforcer's holds (a Family Safety platform, a Switch: device_extra.py);
        [paused_groups_of]: the groups an adult paused for a person, All screen time for a family pause (a Switch);
        [closed_of]: the groups the weekly schedule closes for a person now, All screen time in Sleep and School;
        [spared]: packages never paused, for any reason (the accessibility apps: household.never_held);
        [exempt_of]: the packages Family Link never pauses for a person (their paired devices' clients);
        [blocked_of]: the packages Hearth's blocks hold for a person (app_blocks.py): never paused or resumed, so one
        paused when it was blocked stays as held (Family Link's resume_app skips a blocked app anyway)."""
        self.enforcers = enforcers
        now = dt_util.now()
        wanted_now: dict[str, set[str]] = {}
        why_now: dict[str, dict[str, str]] = {}
        for e in enforcers:
            lifted = lifted_of(e.person) if lifted_of else None
            playing = self._playing(e)
            # [budget_lifted_of]: what lifts a budget hold only: the allows, and a category's own bonus left (its apps
            # run past daily time). Bedtime, School time and pauses aren't lifted by it
            budget_lifted = budget_lifted_of(e.person) if budget_lifted_of else lifted
            budget = wanted(e, days.get(e.person), apps_of, now, playing, budget_lifted, groups_of_app)
            if ALL_APPS in budget:
                budget = (budget - {ALL_APPS}) | self._all_apps_but(e, budget_lifted, apps_of, groups_of_app)
            # An app a parent gave unlimited time in Family Link is never paused for a budget: it stays usable, as on
            # a locked device. The School-time apps are the parent's own choice, so they are paused all the same.
            if e.kind == FAMILY_LINK:
                budget -= self._always_allowed(e.entity_id)
            # An older Family Safety can't pause an app: only its platforms
            if e.kind == FAMILY_SAFETY and not self.hass.services.has_service(FS_DOMAIN, "pause_app"):
                budget = {item for item in budget if not fs_app(item)}
            school = school_wanted(e, bool(school_time_of and school_time_of(e)), lifted, groups_of_app)
            # A parent's grant lifts only the hold it came from (that enforcer's item)
            granted = (granted_of(e.person) or {}).get(e.kind, set()) if granted_of else set()
            paused = (
                paused_wanted(e, paused_of(e.person), self.hass.services.has_service(FS_DOMAIN, "pause_app"))
                if paused_of
                else set()
            )
            if paused_groups_of:
                # An adult's pause holds the Switch too (a family pause, or a group the enforcer covers)
                paused |= paused_switch(e, set(paused_groups_of(e.person)), now, playing)
            scheduled = (
                schedule_wanted(
                    e,
                    set(closed_of(e.person)),
                    apps_of,
                    now,
                    playing,
                    lifted,
                    groups_of_app,
                    self.hass.services.has_service(FS_DOMAIN, "pause_app"),
                )
                if closed_of
                else set()
            )
            if e.kind == FAMILY_LINK:
                scheduled -= self._always_allowed(e.entity_id)
            device_lifted = device_lifted_of(e) if device_lifted_of else set()
            wanted_now[e.key] = (budget | school | paused | scheduled) - granted - device_lifted - set(spared)
            if e.kind == FAMILY_LINK and exempt_of:
                wanted_now[e.key] -= exempt_of(e.person)
            if e.kind == FAMILY_LINK:
                # Only apps the child has: pausing one they don't would only cost a call (and read as a parent's
                # change later, its pause never showing)
                wanted_now[e.key] = self._installed_only(e.entity_id, wanted_now[e.key])
            frozen: set[str] = set()
            if e.kind == FAMILY_LINK and blocked_of and (blocked := blocked_of(e.person)):
                frozen = (self.held.get(e.key) or Held()).items & blocked
                wanted_now[e.key] = (wanted_now[e.key] - blocked) | frozen
            # School time first, then an adult's pause, then a budget: the reason a parent would name
            why_now[e.key] = {
                item: WHY_BLOCKED
                if item in frozen
                else WHY_SCHOOL
                if item in school
                else WHY_PAUSE
                if item in paused
                else WHY_SCHEDULE
                if item in scheduled and item not in budget
                else WHY_BUDGET
                for item in wanted_now[e.key]
            }
        # What an enforcer no longer configured held is let go
        for key in self.held:
            wanted_now.setdefault(key, set())
        self._wanted = wanted_now
        self._why = why_now
        for key, want in wanted_now.items():
            self._clear_stale_error(key, want)
        if any(self._differs(key) for key in wanted_now):
            self._run()

    def _clear_stale_error(self, key: str, want: set[str]) -> None:
        """An enforcer with nothing to hold and nothing held has nothing to retry: its last error is over (a sync error
        otherwise stays on the kid's card until the next call, which may be days away). A successful call clears it
        too (note)."""
        held = self.held.get(key)
        if want or (held is not None and _holding(held)):
            return
        if held is not None:
            held.error, held.failed_at = None, None
        last = self.last.get(key)
        # A hold or let-go that failed (not another write's error: extra time Hearth couldn't give, say)
        if last is not None and last.get("error") and (last.get("held") or last.get("let_go")):
            self.last[key] = {**{k: v for k, v in last.items() if k != "error"}, "ok": True, "error_cleared": True}
            self._save()

    def _playing(self, enforcer: Enforcer) -> bool | None:
        """Whether the person is the one playing a shared Switch (any of their playing entities on); None when the
        enforcer has none, or none of them has a state yet (the whole Switch is held, as before)."""
        if not enforcer.playing:
            return None
        states = [self.hass.states.get(e) for e in enforcer.playing]
        known = [s for s in states if s is not None and s.state not in ("unknown", "unavailable")]
        if not known:
            return None
        return any(s.state == "on" for s in known)

    def _sharing(self, key: str, entity_id: str | None) -> list[Held]:
        """Another person's hold on the same Switch, still wanted."""
        return [
            other
            for other_key, other in self.held.items()
            if other_key != key
            and other_key.startswith(f"{NINTENDO}|")
            and other.entity_id == entity_id
            and SWITCH in _holding(other)
            and SWITCH in self._wanted.get(other_key, set())
        ]

    def _differs(self, key: str) -> bool:
        held = self.held.get(key) or Held()
        want = self._wanted.get(key, set())
        if want - held.items:
            return True
        return bool(_holding(held) - want) and self._may_let_go()

    def _may_let_go(self) -> bool:
        return dt_util.utcnow() - self.started >= SETTLE

    def _run(self) -> None:
        if self._closed:
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        self._task = entry_task(self.hass, self._entry_id, self._async_apply(), "hearth enforcement")

    async def _async_apply(self) -> None:
        self._again = False
        now = dt_util.utcnow()
        by_key = {e.key: e for e in self.enforcers}
        for key, want in list(self._wanted.items()):
            held = self.held.setdefault(key, Held())
            if held.failed_at and now - held.failed_at < RETRY:
                continue
            enforcer = by_key.get(key)
            kind, person = key_parts(key)
            entity_id = enforcer.entity_id if enforcer else held.entity_id
            hold = want - held.items
            let_go = _holding(held) - want if self._may_let_go() else set()
            if not (hold or let_go) or entity_id is None:
                continue
            # Kept before the calls: a half-done hold is let go through it if the enforcer is removed meanwhile
            if not _holding(held) or held.entity_id is None:
                held.entity_id = entity_id
            outcomes: dict[str, Any] = {}
            self._busy.add(key)
            try:
                # Switching between the whole-device lock and pausing apps one by one (a category open past daily
                # time): the new hold first, so a failure leaves the kid held too much rather than not at all (a
                # failed pause_app keeps the device lock, and is tried again)
                hold_first = DEVICES in hold or DEVICES in let_go
                if hold and hold_first:
                    held.entity_id = entity_id
                    await self._call(kind, entity_id, hold, True, held)
                    held.items |= hold
                if let_go:
                    # Through what held it: a Switch changed meanwhile gets the hold, the old one its limit back
                    outcomes = await self._call(kind, held.entity_id or entity_id, let_go, False, held)
                    held.items -= let_go
                if hold and not hold_first:
                    held.entity_id = entity_id
                    await self._call(kind, entity_id, hold, True, held)
                    held.items |= hold
                held.error, held.failed_at = None, None
                self.hass.bus.async_fire(
                    "hearth_enforced",
                    {
                        "person": person,
                        "by": kind,
                        "held": sorted(hold),
                        "let_go": sorted(let_go),
                        **({"outcomes": outcomes} if outcomes else {}),
                    },
                )
                self.note(key, held=sorted(hold), let_go=sorted(let_go), outcomes=outcomes)
                if self.activity is not None:
                    why = self._why.get(key, {})
                    for reason in sorted({why.get(i, "limit") for i in hold}):
                        self.activity.hold(True, person, [i for i in hold if why.get(i, "limit") == reason], reason, kind)
                    if let_go:
                        self.activity.hold(False, person, let_go, None, kind)
            except Exception as err:  # noqa: BLE001 - one parental control failing mustn't stop the others
                _LOGGER.warning("Hearth couldn't %s for %s through %s: %s", "hold" if hold else "let go", person, kind, err)
                held.error, held.failed_at = str(err)[:200], now
                self.note(key, held=sorted(hold), let_go=sorted(let_go), error=held.error)
            finally:
                self._busy.discard(key)
                self._quiet_until[key] = dt_util.utcnow() + QUIET_AFTER_CALL
                # What's held shows now (the held sensor, Hearth's page), not at the next recompute; the parental
                # control's own entities are read again shortly
                async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)
                self.refresh_soon(held.entity_id or entity_id)
            if not _holding(held) and not held.error and enforcer is None:
                self.held.pop(key, None)
            self._save()
        if self._again:
            self._run()
        elif self.on_applied is not None:
            self.on_applied()

    @callback
    def refresh_soon(self, entity_id: str | None) -> None:
        """Asks the integration of [entity_id] (Family Link, Family Safety, Nintendo) for fresh data once, a few
        seconds after a write of Hearth's (homeassistant.update_entity: a coordinator's entity refreshes it). One
        waiting refresh per entity: writes meanwhile don't add more, and the refresh writes nothing."""
        if self._closed or not entity_id or "." not in entity_id or entity_id in self._refresh:
            return

        @callback
        def _due(_now: datetime) -> None:
            self._refresh.pop(entity_id, None)
            if not self._closed and self.hass.states.get(entity_id) is not None:
                entry_task(self.hass, self._entry_id, self._update_entity(entity_id), "hearth refresh after a write")

        self._refresh[entity_id] = async_call_later(self.hass, REFRESH_AFTER_WRITE, _due)

    async def _update_entity(self, entity_id: str) -> None:
        if not self.hass.services.has_service("homeassistant", "update_entity"):
            return
        try:
            await call_service(self.hass,
                "homeassistant", "update_entity", {"entity_id": entity_id}, blocking=True
            )
        except Exception as err:  # noqa: BLE001 - only a refresh: the integration's own polling still comes
            _LOGGER.debug("Couldn't refresh %s after a write: %s", entity_id, err)

    async def _call(self, kind: str, entity_id: str, items: set[str], hold: bool, held: Held) -> dict[str, Any]:
        """Holds or lets go of [items]; says what letting go did, by item (restored, kept_current, ...), where the
        parental control says so."""
        outcomes: dict[str, Any] = {}
        if kind == NINTENDO:
            # One Switch, two kids: the first hold keeps its limit; letting go while the other is still held hands
            # what to put back over instead of putting it back
            sharing = self._sharing(next(k for k, v in self.held.items() if v is held), entity_id)
            if sharing:
                if not hold and held.restore:
                    sharing[0].restore = sharing[0].restore or held.restore
                held.restore = {} if not hold else held.restore
                return {SWITCH: "shared"} if not hold else {}
            if hold:
                await self._hold_switch(entity_id, held)
            elif (outcome := await self._let_go_switch(entity_id, held)) is not None:
                outcomes[SWITCH] = outcome
            return outcomes
        if kind == FAMILY_LINK:
            if DEVICES in items:
                if hold:
                    await self._lock_devices(entity_id, held)
                elif (outcome := await self._unlock_devices(held)) is not None:
                    outcomes[DEVICES] = outcome
            packages = items - {DEVICES}
            if packages:
                service = "pause_app" if hold else "resume_app"
                response = await call_service(self.hass,
                    "familylink",
                    service,
                    {"entity_id": entity_id, "packages": sorted(packages)},
                    blocking=True,
                    return_response=self._responds("familylink", service),
                )
                if not hold:
                    outcomes.update(_resume_outcomes(response))
            return outcomes
        apps = {item for item in items if fs_app(item)}
        for platform in sorted(items - apps):
            applied = await self._platform(entity_id, platform, hold, held)
            if not hold and applied is not None:
                outcomes[platform] = applied
        if apps:
            await self._fs_apps(entity_id, apps, hold)
        return outcomes

    def _responds(self, domain: str, service: str) -> bool:
        """The service gives an answer (a newer integration): asked for it then. A missing service raises at the call."""
        try:
            return self.hass.services.supports_response(domain, service) != SupportsResponse.NONE
        except Exception:  # noqa: BLE001 - not registered: the call itself says so
            return False

    async def _fs_apps(self, entity_id: str, apps: set[str], hold: bool) -> None:
        """Xbox and Windows apps paused (a block that keeps whether each was blocked before) or resumed. Family
        Safety leaves an app a parent blocked alone."""
        if not self.hass.services.has_service(FS_DOMAIN, "pause_app"):
            if hold:
                raise ValueError("Family Safety can't pause apps (update it)")
            # Nothing to resume with: what it held can't have been paused by it
            return
        target = {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}
        await call_service(self.hass,
            FS_DOMAIN, "pause_app" if hold else "resume_app", {**target, "apps": sorted(apps)}, blocking=True
        )

    async def _platform(self, entity_id: str, platform: str, hold: bool, held: Held | None = None) -> str | None:
        """Locks a Family Safety platform until the next local midnight, or unlocks it. The child is named by the
        configured entity (any of the child's Family Safety entities) or by a typed-in account id. An older Family
        Safety (no entity_id or until fields: upstream's) is called as before: the account sensor's user_id and whole
        hours (the lock then ends up to an hour after midnight). When the lock ends is kept in [held] (fs_lock_until):
        with it Hearth tells its own lock from a parent's where Family Safety doesn't say (fs_derived_hold)."""
        target = {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}
        data: dict[str, Any] = {**target, "platform": platform}
        until = next_midnight()
        if hold:
            data["until"] = until.isoformat()
        service = "lock_platform" if hold else "unlock_platform"
        by_hours = False
        try:
            response = await self._fs_call(service, data)
        except (vol.Invalid, ServiceValidationError) as err:
            try:
                account = self._account_id(entity_id)
            except ValueError:
                raise err from None
            legacy: dict[str, Any] = {"account_id": account, "platform": platform}
            end_at, by_hours = until, hold
            if hold:
                legacy["duration_hours"] = hours_to_midnight()
                until = dt_util.now() + timedelta(hours=legacy["duration_hours"])
            _LOGGER.debug("Family Safety refused the newer %s call (%s): calling it as before", service, err)
            response = await self._fs_call(service, legacy)
            if hold and held is not None and until > end_at:
                # Whole hours run past midnight: Hearth unlocks it itself then (async_lock_ends_tick)
                _restore_map(held, FS_UNLOCK_AT)[platform] = dt_util.as_utc(end_at).isoformat()
        if held is not None:
            sent = _restore_map(held, "fs_lock_until")
            if hold:
                sent[platform] = dt_util.as_utc(until).isoformat()
            else:
                sent.pop(platform, None)
            if not by_hours:
                # An end Family Safety keeps itself, or let go: nothing for Hearth to end
                _restore_map(held, FS_UNLOCK_AT).pop(platform, None)
            # Locked again or let go: not a lock that ended on time any more
            _restore_map(held, FS_LOCK_ENDED).pop(platform, None)
            _tidy_restore(held)
        applied = response.get("applied") if isinstance(response, dict) else None
        if not hold and applied in UNLOCK_DONE:
            # Nothing of Hearth's left to undo: the hold ran out, a parent's own lock stays, or it wasn't locked
            _LOGGER.info("Family Safety %s for %s: %s", platform, entity_id, applied)
        elif applied is not None:
            _LOGGER.debug("Family Safety %s %s for %s: %s", service, platform, entity_id, applied)
        return applied if isinstance(applied, str) else None

    async def _fs_call(self, service: str, data: dict[str, Any]) -> Any:
        """A Family Safety call, with its answer when the service gives one (an older one doesn't)."""
        responds = self.hass.services.supports_response(FS_DOMAIN, service) != SupportsResponse.NONE
        return await call_service(self.hass,
            FS_DOMAIN, service, data, blocking=True, return_response=responds
        )

    def _account_id(self, entity_id: str) -> str:
        """The Family Safety account: the user_id of the person's account sensor (or the id itself, typed in)."""
        account = fs_account_of(self.hass, entity_id)
        if account is None:
            raise ValueError(f"{entity_id} has no user_id")
        return account

    def _switch_entity(self, entity_id: str, domain: str, key: str) -> str | None:
        """Another entity of the Switch whose Max screentime today is [entity_id] (by its key: suspend_software)."""
        registry = er.async_get(self.hass)
        entry = registry.async_get(entity_id)
        if entry is not None and entry.device_id:
            for other in er.async_entries_for_device(registry, entry.device_id):
                if other.domain == domain and other.platform == NINTENDO_DOMAIN and other.unique_id.endswith(f"_{key}"):
                    return other.entity_id
        # Not in the registry (or renamed oddly): the id Home Assistant gives it from the Switch's name
        guess = f"{domain}.{entity_id.split('.', 1)[-1].removesuffix('_max_screentime_today')}_{key}"
        return guess if self.hass.states.get(guess) is not None else None

    def _always_allowed(self, entity_id: str) -> set[str]:
        """The child's apps with unlimited time in Family Link (its Always allowed apps sensor, by the child's id)."""
        state = self.hass.states.get(entity_id)
        child = state.attributes.get("child_id") if state else None
        if not child:
            return set()
        found: set[str] = set()
        for other in self.hass.states.async_all("sensor"):
            if other.entity_id.endswith("_always_allowed_apps") and str(other.attributes.get("child_id")) == str(child):
                for app in other.attributes.get("apps") or []:
                    package = app.get("package") if isinstance(app, dict) else app
                    if isinstance(package, str) and package:
                        found.add(package)
        return found

    def _all_apps_but(self, enforcer: Enforcer, lifted: Lifted, apps_of, groups_of_app) -> set[str]:
        """Daily time out while a category stays open: every app the child has installed (Family Link's lists) but
        that category's and an explicit system list (ESSENTIAL and NEVER_PAUSED by name, never the com.android.*
        prefix, so Chrome and any other launchable com.android app are paused; launchers, keyboards and accessibility
        apps are spared later, household.never_held). The whole-device lock when the installed apps aren't known."""
        child = fl.child_of(self.hass, enforcer.entity_id)
        installed = fl.installed_apps(self.hass, child) if child else None
        if not installed:
            return {DEVICES}
        open_apps: set[str] = set()
        for group_id in lifted.open:
            open_apps |= set(apps_of(group_id, enforcer.person))
        return {
            p
            for p in installed
            if p not in SYSTEM_NEVER_PAUSED
            and p not in open_apps
            and not fs_app(p)
            and not (groups_of_app is not None and groups_of_app(p) & lifted.open)
        }

    def _installed_only(self, entity_id: str, items: set[str]) -> set[str]:
        """[items] without the packages not installed on the child's devices (all of them when that isn't known)."""
        child = fl.child_of(self.hass, entity_id)
        installed = fl.installed_apps(self.hass, child) if child else None
        if installed is None:
            return items
        return {item for item in items if item == DEVICES or item in installed}

    def _family_link_child(self, entity_id: str) -> tuple[str, str | None]:
        """The child's id (an attribute of their Family Link entities) and today's weekday limit entity."""
        registry = er.async_get(self.hass)
        entry = registry.async_get(entity_id)
        others = (
            er.async_entries_for_device(registry, entry.device_id) if entry is not None and entry.device_id else []
        )
        child = None
        for candidate in [entity_id, *(o.entity_id for o in others)]:
            state = self.hass.states.get(candidate)
            if state is not None and state.attributes.get("child_id"):
                child = str(state.attributes["child_id"])
                break
        if child is None:
            raise ValueError(f"{entity_id} names no Family Link child")
        # The child's weekday limits are number entities carrying their child_id (Monday limit ... Sunday limit)
        weekday = WEEKDAYS[dt_util.now().weekday()]
        limit = next(
            (
                state.entity_id
                for state in self.hass.states.async_all("number")
                if state.entity_id.endswith(f"_{weekday}_limit") and str(state.attributes.get("child_id")) == child
            ),
            None,
        )
        return child, limit

    async def _lock_devices(self, entity_id: str, held: Held) -> None:
        """Today's daily limit to 0 on every device of the child. The limit it had is kept first (once: a retry after
        a half-done hold mustn't keep the 0)."""
        if "lock_minutes" not in held.restore:
            child, limit_entity = self._family_link_child(entity_id)
            state = self.hass.states.get(limit_entity) if limit_entity else None
            # The weekday's own limit (weekly_minutes): the state reads today's override, which may be Hearth's
            # backstop (backstop.py) or a whole day for Unlimited, and must never become the weekday's setting
            limit = _number(state.attributes.get("weekly_minutes")) if state else None
            from_state = limit is None
            if limit is None:
                limit = _number(state.state if state else None)
            if limit is None:
                raise ValueError(f"{entity_id}: no daily limit to keep for today")
            now = dt_util.now()
            held.restore = {
                **held.restore,
                "lock_minutes": int(limit),
                # Read from the state (an older Family Link without weekly_minutes): may be an override
                **({"lock_from_state": True} if from_state else {}),
                "lock_child": child,
                "lock_weekday": now.isoweekday(),
                "lock_day": now.date().isoformat(),
                # What the devices showed when the hold started: a bonus or an unlock beyond it is a parent's
                "lock_bonus": {
                    str(d.attributes.get("device_id")): _number(d.attributes.get("bonus_minutes")) or 0
                    for d in fl.devices(self.hass, child)
                },
                "lock_unlocked": sorted(
                    str(d.attributes.get("device_id"))
                    for d in fl.devices(self.hass, child)
                    if d.attributes.get("lock_override_code") == FL_UNLOCK_CODE
                ),
            }
            # Daily limits switched off: Family Link then only rewrites the weekly row, nothing locks. Hearth switches
            # them on for the hold, and says so, so letting go switches them off again
            switch = fl.daily_limit_switch(self.hass, child)
            switch_state = self.hass.states.get(switch) if switch else None
            if switch_state is not None and switch_state.state == "off":
                held.restore["lock_switched_on"] = True
            self._save()
        if held.restore.get("lock_switched_on"):
            switch = fl.daily_limit_switch(self.hass, held.restore["lock_child"])
            switch_state = self.hass.states.get(switch) if switch else None
            if switch_state is not None and switch_state.state == "off":
                await call_service(self.hass, "switch", "turn_on", {"entity_id": switch}, blocking=True)
        await call_service(self.hass,
            "familylink",
            "set_daily_limit",
            {"child_id": held.restore["lock_child"], "daily_minutes": 0, "day": held.restore["lock_weekday"]},
            blocking=True,
        )

    def _held_weekday_limit(self, restore: dict[str, Any]) -> float | None:
        """What the held weekday's daily limit entity reads now (None when it can't be told)."""
        child, weekday = restore.get("lock_child"), restore.get("lock_weekday")
        if not child or not isinstance(weekday, int) or not 1 <= weekday <= 7:
            return None
        suffix = f"_{WEEKDAYS[weekday - 1]}_limit"
        state = next(
            (
                s
                for s in self.hass.states.async_all("number")
                if s.entity_id.endswith(suffix) and str(s.attributes.get("child_id")) == str(child)
            ),
            None,
        )
        return _number(state.state if state else None)

    def _backstop_value(self, minutes: Any) -> bool:
        """[minutes] came from an override, not a weekday's own limit: a whole day (Unlimited) or a backstop value."""
        written = self.backstop_values() if self.backstop_values else set()
        return minutes is not None and (int(minutes) >= 1440 or int(minutes) in written)

    async def _unlock_devices(self, held: Held) -> str | None:
        """The weekday's daily limit back as it was (that weekday's, even after midnight), only while it still reads
        what Hearth set (0): a limit a parent changed meanwhile in the Family Link app is theirs, and stays. Says what
        it did (restored, kept_current), None with nothing kept."""
        restore = held.restore
        outcome = None
        if "lock_minutes" in restore:
            current = self._held_weekday_limit(restore)
            if restore.get("lock_from_state") and self._backstop_value(restore["lock_minutes"]):
                # Kept from an override, not the weekday's own limit: never made the weekday's setting
                _LOGGER.warning(
                    "Family Link's daily limit for child %s: %s was Hearth's backstop or a whole day, not the weekday's "
                    "own limit; not put back as the weekday's setting",
                    restore.get("lock_child"), restore["lock_minutes"],
                )
                outcome = KEPT_CURRENT
            elif restore.get("lock_adopted") or (current is not None and current not in (0, restore["lock_minutes"])):
                _LOGGER.info(
                    "Family Link's daily limit for child %s changed to %s while Hearth held it: kept, %s not put back",
                    restore.get("lock_child"), current, restore["lock_minutes"],
                )
                outcome = KEPT_CURRENT
            else:
                await call_service(self.hass,
                    "familylink",
                    "set_daily_limit",
                    {
                        "child_id": restore["lock_child"],
                        "daily_minutes": restore["lock_minutes"],
                        "day": restore["lock_weekday"],
                    },
                    blocking=True,
                )
                outcome = RESTORED
                # The daily limits Hearth switched on for the hold go off again (unless a parent already did)
                if restore.get("lock_switched_on"):
                    switch = fl.daily_limit_switch(self.hass, str(restore["lock_child"]))
                    switch_state = self.hass.states.get(switch) if switch else None
                    if switch_state is not None and switch_state.state == "on":
                        await call_service(self.hass,
                            "switch", "turn_off", {"entity_id": switch}, blocking=True
                        )
        held.restore = {k: v for k, v in restore.items() if not k.startswith("lock_")}
        return outcome

    async def _hold_switch(self, entity_id: str, held: Held) -> None:
        """Max screentime today to 0 with Suspend software on: the game is suspended. What they were is kept first
        (once: a retry after a half-done hold mustn't keep the 0)."""
        # Bonus time given in the Nintendo app: the Switch refuses a new limit until it's over (said, not retried blind)
        if self.switch_extended(entity_id):
            raise ValueError("bonus time is active on the Switch; held when it's over")
        if not held.restore:
            state = self.hass.states.get(entity_id)
            limit = _number(state.state if state else None)
            if limit is None:
                raise ValueError(f"{entity_id} has no limit to keep")
            suspend = self._switch_entity(entity_id, "switch", "suspend_software")
            suspend_state = self.hass.states.get(suspend) if suspend else None
            held.restore = {
                "max": int(limit),
                "suspend": suspend,
                "suspend_was": suspend_state.state if suspend_state else None,
                **self.switch_day(entity_id),
            }
            self._save()
        suspend = held.restore.get("suspend")
        if suspend and held.restore.get("suspend_was") != "on":
            await call_service(self.hass, "switch", "turn_on", {"entity_id": suspend}, blocking=True)
        await call_service(self.hass,
            "number", "set_value", {"entity_id": entity_id, "value": 0}, blocking=True
        )

    # A Switch's settings, for the schedule's extra minutes too (schedule.py)

    def switch_extended(self, entity_id: str) -> bool:
        """Bonus time given in the Nintendo app runs on the Switch (its time-extended sensor): it refuses a new limit."""
        extended = self._switch_entity(entity_id, "sensor", "time_extended") or self._switch_entity(
            entity_id, "binary_sensor", "time_extended"
        )
        state = self.hass.states.get(extended) if extended else None
        return state is not None and state.state not in ("0", "0.0", "off", "unknown", "unavailable", "")

    def switch_day(self, entity_id: str) -> dict[str, Any]:
        """What putting today's limit back after midnight needs: the day and weekday, the Switch's device, and the
        day's bedtime (putting a weekday's limit back sets its bedtime with it)."""
        found: dict[str, Any] = {}
        for key in ("bedtime_alarm", "bedtime_end_time"):
            time_entity = self._switch_entity(entity_id, "time", key)
            time_state = self.hass.states.get(time_entity) if time_entity else None
            found[key] = time_state.state if time_state else None
        entry = er.async_get(self.hass).async_get(entity_id)
        now = dt_util.now()
        return {
            "day": now.date().isoformat(),
            "weekday": WEEKDAYS[now.weekday()],
            "device_id": entry.device_id if entry else None,
            **found,
        }

    def switch_each_day(self, entity_id: str) -> bool:
        """The Switch has a limit per weekday (its timer mode), so after midnight its limit is another day's."""
        mode = self._switch_entity(entity_id, "select", "timer_mode")
        mode_state = self.hass.states.get(mode) if mode else None
        return mode_state is not None and mode_state.state == NINTENDO_EACH_DAY

    def switch_hold(self, entity_id: str) -> Held | None:
        """Hearth's hold of the Switch (the one that kept its limit), while there is one."""
        return next(
            (
                held
                for key, held in self.held.items()
                if key.startswith(f"{NINTENDO}|") and held.entity_id == entity_id and "max" in held.restore
            ),
            None,
        )

    def switch_quiet(self, entity_id: str) -> bool:
        """Hearth's hold of the Switch is being changed, or just was: its limit may not read what it is yet."""
        keys = {e.key for e in self.enforcers if e.kind == NINTENDO and e.entity_id == entity_id}
        keys |= {k for k, h in self.held.items() if k.startswith(f"{NINTENDO}|") and h.entity_id == entity_id}
        return any(self._quiet(key) for key in keys)

    def save(self) -> None:
        self._save()

    async def put_back_weekday(self, entity_id: str, restore: dict[str, Any], limit: int | None) -> None:
        data = _held_weekday_call(restore, limit)
        if data is None or not self.hass.services.has_service(NINTENDO_DOMAIN, "update_daily_restrictions"):
            _LOGGER.warning(
                "Hearth held %s past midnight; its limit of %s minutes for %s wasn't put back (check it in the "
                "Nintendo app)", entity_id, limit, restore.get("day")
            )
            return
        await call_service(self.hass, NINTENDO_DOMAIN, "update_daily_restrictions", data, blocking=True)

    async def _let_go_switch(self, entity_id: str, held: Held) -> str | None:
        """The limit and Suspend software back as they were, only while the limit still reads what Hearth set (0): a
        limit a parent changed meanwhile in the Nintendo app is theirs, and stays with the Switch's other settings.
        On a later day (Home Assistant was off over midnight), a Switch with a limit per weekday shows another day's
        now: that one is left alone, and said so. Says what it did (restored, kept_current)."""
        restore = held.restore
        limit = restore.get("max")
        state = self.hass.states.get(entity_id)
        current = _number(state.state if state else None)
        later_day = restore.get("day") not in (None, dt_util.now().date().isoformat())
        if not later_day and (
            restore.get("adopted") or (current is not None and limit is not None and current not in (0, limit))
        ):
            _LOGGER.info("%s changed to %s while Hearth held it: kept, %s not put back", entity_id, current, limit)
            held.restore = {}
            return KEPT_CURRENT
        if later_day and self.switch_each_day(entity_id):
            # Held past midnight (Home Assistant was off): today's limit is another weekday's now, so the held
            # weekday's own is put back, with its bedtime
            await self.put_back_weekday(entity_id, restore, limit)
        elif limit is None:
            _LOGGER.warning("Hearth had no limit kept for %s: left as it is (check it in the Nintendo app)", entity_id)
        else:
            await call_service(self.hass,
                "number", "set_value", {"entity_id": entity_id, "value": limit}, blocking=True
            )
        suspend = restore.get("suspend")
        if suspend and restore.get("suspend_was") == "off":
            await call_service(self.hass, "switch", "turn_off", {"entity_id": suspend}, blocking=True)
        held.restore = {}
        return RESTORED

    # A parent's changes in their own app (native_sync.py makes them grants)

    def _quiet(self, key: str) -> bool:
        """Hearth's own calls are under way or just made: what changes now is Hearth's, not a parent's."""
        until = self._quiet_until.get(key)
        return key in self._busy or (until is not None and dt_util.utcnow() < until)

    @callback
    def parent_changes(self, own_bonus=None, watch: set[str] | None = None) -> list[dict[str, Any]]:
        """What parents changed in the Family Link, Nintendo or Family Safety app that lifts something Hearth holds:
        grant specs {person, via, kind, value, until, reason, end_with, ends_with}. A changed limit is adopted (what
        letting go would put back is the parent's, so nothing is written over it). [own_bonus]: the Family Link bonus
        minutes Hearth itself added, by device id; [watch] gets the entities read."""
        from . import grants as g

        found: list[dict[str, Any]] = []
        midnight = end_of_day(dt_util.now())
        watch = watch if watch is not None else set()
        for e in self.enforcers:
            held = self.held.get(e.key)
            if held is None or not held.items:
                continue
            # Hearth's own calls just made: watched, but what changes now is taken as Hearth's
            quiet = self._quiet(e.key)

            def grant(kind, value, reason, until=midnight, end_with=None, ends_with=None, _e=e, _quiet=quiet) -> None:
                if _quiet:
                    return
                found.append(
                    {
                        "person": _e.person,
                        "via": _e.kind,
                        "kind": kind,
                        "value": value,
                        "until": until,
                        "reason": reason,
                        "end_with": end_with,
                        "ends_with": ends_with,
                    }
                )

            if e.kind == FAMILY_LINK:
                self._family_link_changes(e, held, grant, own_bonus, watch, quiet)
            elif e.kind == NINTENDO and SWITCH in held.items:
                self._switch_changes(e, held, grant, watch, quiet)
            elif e.kind == FAMILY_SAFETY:
                for platform in sorted(held.items & set(PLATFORMS)):
                    state = self.fs_state(e, platform, watch)
                    spec = family_safety_grant(state) if state is not None else None
                    if spec is not None:
                        grant(g.PLATFORM, platform, spec["reason"], spec["until"] or midnight, spec["end_with"])
        return found

    def _switch_changes(self, e: Enforcer, held: Held, grant, watch: set[str], quiet: bool = False) -> None:
        from . import grants as g

        state = self.hass.states.get(e.entity_id)
        watch.add(e.entity_id)
        current = _number(state.state if state else None)
        if current == 0:
            if not held.restore.get("seen_zero"):
                held.restore["seen_zero"] = True
                self._save()
        elif quiet:
            return
        elif current is not None and "max" in held.restore and (
            current != held.restore["max"] or held.restore.get("seen_zero")
        ):
            held.restore["adopted"] = True
            self._save()
            grant(g.SWITCH, SWITCH, "the limit was changed in the Nintendo app", end_with=g.END_RELOCK)
            return
        extended = self._switch_entity(e.entity_id, "sensor", "time_extended") or self._switch_entity(
            e.entity_id, "binary_sensor", "time_extended"
        )
        if extended:
            watch.add(extended)
            ext = self.hass.states.get(extended)
            if not quiet and ext is not None and ext.state not in ("0", "0.0", "off", "unknown", "unavailable", ""):
                held.restore["adopted"] = True
                self._save()
                grant(g.SWITCH, SWITCH, "bonus time given in the Nintendo app")

    def _family_link_changes(
        self, e: Enforcer, held: Held, grant, own_bonus, watch: set[str], quiet: bool = False
    ) -> None:
        from . import grants as g

        restore = held.restore
        child = restore.get("lock_child") or fl.child_of(self.hass, e.entity_id)
        if DEVICES in held.items and "lock_minutes" in restore and not restore.get("lock_adopted"):
            current = self._held_weekday_limit(restore)
            watch.update(
                s.entity_id
                for s in self.hass.states.async_all("number")
                if s.entity_id.endswith("_limit") and str(s.attributes.get("child_id")) == str(child)
            )
            if current == 0:
                if not restore.get("lock_seen_zero"):
                    restore["lock_seen_zero"] = True
                    self._save()
            elif quiet:
                pass
            elif current is not None and (current != restore["lock_minutes"] or restore.get("lock_seen_zero")):
                # Adopted: letting go doesn't write over it
                restore["lock_adopted"] = True
                restore["lock_minutes"] = int(current)
                self._save()
                grant(g.DEVICE, DEVICES, "the daily limit was changed in the Family Link app")
                return
        if DEVICES in held.items and child:
            base = restore.get("lock_bonus") or {}
            unlocked = set(restore.get("lock_unlocked") or [])
            for device in fl.devices(self.hass, str(child)):
                watch.add(device.entity_id)
                device_id = str(device.attributes.get("device_id"))
                bonus = _number(device.attributes.get("bonus_minutes")) or 0
                own = (own_bonus or {}).get(device_id, 0)
                if bonus > (base.get(device_id) or 0) + own:
                    grant(
                        g.DEVICE,
                        DEVICES,
                        "bonus time given in the Family Link app",
                        end_with=g.END_RESET_BONUS,
                        ends_with=g.WHILE_BONUS,
                    )
                    return
                if device.attributes.get("lock_override_code") == FL_UNLOCK_CODE and device_id not in unlocked:
                    grant(g.DEVICE, DEVICES, "unlocked in the Family Link app")
                    return
        packages = held.items - {DEVICES}
        if packages and child:
            # A newer Family Link says which apps pause_app paused a parent changed since (pause_intact false). An app
            # the child doesn't have never shows its pause, so its pause_intact is false too: never a parent's change
            installed = fl.installed_apps(self.hass, str(child))
            if installed is not None:
                packages &= installed
            for state in self.hass.states.async_all("sensor"):
                paused = state.attributes.get("paused_apps")
                if str(state.attributes.get("child_id")) != str(child) or not isinstance(paused, list):
                    continue
                watch.add(state.entity_id)
                for app in paused:
                    if isinstance(app, dict) and app.get("package") in packages and app.get("pause_intact") is False:
                        grant(g.APP, app["package"], "the app's limit was changed in the Family Link app")

    def fs_mine(self, e: Enforcer, platform: str) -> dict[str, Any]:
        """What Hearth itself asked of a Family Safety platform of the enforcer's: whether it holds it, when its lock
        ends (None: not known, a lock from before Hearth kept it) and when the extra time it last gave there today
        ends."""
        held = self.held.get(e.key)
        # A lock by whole hours Hearth ended itself on time is over, as one with an end would be
        holds = bool(held and platform in held.items and platform not in (held.restore.get(FS_LOCK_ENDED) or {}))
        sent = (held.restore.get("fs_lock_until") or {}).get(platform) if held else None
        bonus = self.fs_bonus_until(e.person, platform) if self.fs_bonus_until is not None else None
        return {"held": holds, "lock_until": _utc(sent) if holds else None, "bonus_until": bonus}

    def fs_state(self, e: Enforcer, platform: str, watch: set[str] | None = None) -> dict[str, Any] | None:
        """Who decides the enforcer's Family Safety platform now (fs_hold_state), with what Hearth asked for."""
        return fs_hold_state(self.hass, e.entity_id, platform, watch, self.fs_mine(e, platform))

    async def async_lock_ends_tick(self) -> None:
        """Ends Hearth's Family Safety locks by whole hours on time (every minute: a time missed while Home
        Assistant was off is caught up at the first one after the start, once Family Safety reads). A Family Safety whose lock_platform takes no end (upstream's
        duration_hours) keeps a lock locked to the next whole hour after midnight; Hearth unlocks it itself at midnight
        (held.restore fs_unlock_at), as a lock with an end would end.

        Only a lock that's still Hearth's (fs_state: ours) is unlocked. A parent's change since (their own lock, an
        unlock, extra time: parent) drops the plan at once: a parent's change stays. Anything else at midnight (the
        lock gone, Hearth's own extra time over it, a lock that can't be read) waits, in case the lock comes back
        (a Family Safety that puts a lock back after extra time), and is dropped once the lock's own end has passed. The platform stays held, as with an end that ran out: letting go later finds nothing locked."""
        if self._closed or (self._task is not None and not self._task.done()):
            return
        now = dt_util.utcnow()
        by_key = {e.key: e for e in self.enforcers}
        for key, held in list(self.held.items()):
            due = held.restore.get(FS_UNLOCK_AT)
            enforcer = by_key.get(key)
            if not isinstance(due, dict) or not due or key in self._busy:
                continue
            if enforcer is None or enforcer.kind != FAMILY_SAFETY:
                continue
            changed = False
            for platform, at in list(due.items()):
                when = _utc(at)
                state = self.fs_state(enforcer, platform) if platform in held.items else None
                hold = state.get("hold") if state else None
                ends = _utc((held.restore.get("fs_lock_until") or {}).get(platform))
                if when is None or platform not in held.items or hold == FS_HOLD_PARENT:
                    # Let go, or a parent's change: not Hearth's to end
                    due.pop(platform, None)
                    changed = True
                    continue
                if now < when:
                    continue
                if hold != FS_HOLD_OURS:
                    # Gone, Hearth's extra time over it, or unreadable: wait, but not past the lock's own end
                    if ends is None or now >= ends:
                        due.pop(platform, None)
                        changed = True
                    continue
                target = (
                    {"entity_id": enforcer.entity_id} if "." in enforcer.entity_id else {"account_id": enforcer.entity_id}
                )
                self._busy.add(key)
                try:
                    try:
                        await self._fs_call("unlock_platform", {**target, "platform": platform})
                    except (vol.Invalid, ServiceValidationError):
                        await self._fs_call(
                            "unlock_platform", {"account_id": self._account_id(enforcer.entity_id), "platform": platform}
                        )
                except Exception as err:  # noqa: BLE001 - tried again next minute, until the lock's own end
                    _LOGGER.warning("Hearth couldn't end its %s lock for %s on time: %s", platform, enforcer.person, err)
                    if ends is None or now >= ends:
                        due.pop(platform, None)
                        changed = True
                    continue
                finally:
                    self._busy.discard(key)
                due.pop(platform, None)
                _restore_map(held, FS_LOCK_ENDED)[platform] = now.isoformat()
                changed = True
                _LOGGER.info("Hearth ended its %s lock for %s at midnight", platform, enforcer.person)
                self.note(key, let_go=[], held=[], outcomes={platform: "ended_on_time"})
                self.refresh_soon(enforcer.entity_id)
            if changed:
                _tidy_restore(held)
                self._save()

    def fs_parent_locks(self, person: str) -> list[dict[str, Any]]:
        """Family Safety platforms a parent locked themselves (hold parent, a blockUntil that isn't Hearth's)."""
        found = []
        for e in self.enforcers:
            if e.person != person or e.kind != FAMILY_SAFETY:
                continue
            for platform in e.platforms:
                state = self.fs_state(e, platform)
                if state and state.get("hold") == FS_HOLD_PARENT and state.get("override") == FS_BLOCK_UNTIL:
                    found.append(
                        {"platform": platform, "until": state.get("override_until"), "by": state.get("entity_id")}
                    )
        return found


def fs_hold_state(
    hass: HomeAssistant,
    entity_id: str,
    platform: str,
    watch: set[str] | None = None,
    mine: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Who decides a Family Safety platform's lock now: {hold, override, override_until, allow_until, entity_id,
    source}. hold is ours, bonus_ours (Hearth's extra time), parent or none; None when it can't be told.

    A Family Safety that keeps hold attributes on its Allowed Now sensors or platform lock switches says so itself
    (source attributes). Upstream's doesn't: there Hearth tells it from what Family Safety shows in force (Allowed Now's
    override and override_until, else the lock switch) against what Hearth itself asked for ([mine], Enforcement.
    fs_mine): a lock or extra time Hearth didn't ask for is a parent's (source hearth, fs_derived_hold). None without
    either (an older Family Safety, or no [mine])."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    for domain in ("binary_sensor", "switch"):
        for state in hass.states.async_all(domain):
            attrs = state.attributes
            if "hold" not in attrs or str(attrs.get("user_id")) != account or not _platform_of(state, platform):
                continue
            if watch is not None:
                watch.add(state.entity_id)
            return {
                "hold": attrs.get("hold"),
                "override": attrs.get("override"),
                "override_until": attrs.get("override_until"),
                "allow_until": attrs.get("allow_until"),
                "entity_id": state.entity_id,
                "source": FS_FROM_ATTRIBUTES,
            }
    if mine is None:
        return None
    return fs_derived_hold(hass, account, platform, mine, watch)


def _platform_of(state: Any, platform: str) -> bool:
    named = state.attributes.get("platform") or ("Xbox" if "xbox" in state.entity_id else "Windows")
    return str(named).lower() == platform.lower()


def _utc(value: Any) -> datetime | None:
    """A time as given (an ISO string or a datetime) in UTC; one without an offset is local."""
    parsed = value if isinstance(value, datetime) else dt_util.parse_datetime(str(value or ""))
    if parsed is None:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt_util.get_default_time_zone())
    return dt_util.as_utc(parsed)


def _restore_map(held: Held, key: str) -> dict[str, Any]:
    found = held.restore.get(key)
    if not isinstance(found, dict):
        found = held.restore[key] = {}
    return found


def _tidy_restore(held: Held) -> None:
    for key in ("fs_lock_until", FS_UNLOCK_AT, FS_LOCK_ENDED):
        if not held.restore.get(key):
            held.restore.pop(key, None)


def _close(a: datetime | None, b: datetime | None) -> bool:
    return a is not None and b is not None and abs(a - b) <= FS_OWN_TOLERANCE


def fs_derived_hold(
    hass: HomeAssistant, account: str, platform: str, mine: dict[str, Any], watch: set[str] | None = None
) -> dict[str, Any] | None:
    """The hold state of a platform from upstream's Family Safety, which shows what's in force but not whose.

    Read from the platform's Allowed Now sensor (override blockUntil or allowUntil, override_until), else its lock
    switch (on: a lock, with no end). Against [mine] (held, lock_until, bonus_until: what Hearth asked for):

    - a lock while Hearth holds the platform, ending when Hearth's does (or either end unknown: a Windows lock's end
      isn't shown after Family Safety restarts): ours; any other lock: parent;
    - extra time ending when the extra time Hearth gave there does: bonus_ours; any other: parent;
    - nothing in force while Hearth's lock should be (its end not passed): parent, override none (a parent unlocked
      it), unless Hearth's own extra time replaced that lock today (none) or Hearth doesn't know when its lock ends
      (None: can't tell);
    - nothing in force and no lock of Hearth's: none.

    None while Family Safety can't read the platform's locks (unknown), or there's no such entity. A Windows lock a
    parent sets while Hearth holds Windows reads as Hearth's: Family Safety shows no end for it."""
    found = None
    for domain, marker in (("binary_sensor", "override"), ("switch", "blocked")):
        for state in hass.states.async_all(domain):
            attrs = state.attributes
            if marker in attrs and str(attrs.get("user_id")) == account and _platform_of(state, platform):
                found = state
                break
        if found is not None:
            break
    if found is None:
        return None
    if watch is not None:
        watch.add(found.entity_id)
    attrs = found.attributes
    if found.domain == "binary_sensor":
        override = attrs.get("override") if attrs.get("override") in (FS_BLOCK_UNTIL, FS_ALLOW_UNTIL) else None
        until = _utc(attrs.get("override_until"))
        known = override is not None or (found.state in ("on", "off") and attrs.get("reason") != "unknown")
    else:
        override = FS_BLOCK_UNTIL if found.state == "on" else None
        until = None
        known = found.state in ("on", "off")
    now = dt_util.utcnow()
    lock_until: datetime | None = mine.get("lock_until")
    bonus_until: datetime | None = mine.get("bonus_until")
    lock_live = bool(mine.get("held")) and (lock_until is None or lock_until > now - FS_OWN_TOLERANCE)
    if not known:
        hold = None
    elif override == FS_BLOCK_UNTIL:
        own = lock_live and (until is None or lock_until is None or _close(until, lock_until))
        hold = FS_HOLD_OURS if own else FS_HOLD_PARENT
    elif override == FS_ALLOW_UNTIL:
        own = bonus_until is not None and (_close(until, bonus_until) or (until is None and bonus_until > now))
        hold = FS_HOLD_BONUS_OURS if own else FS_HOLD_PARENT
    elif lock_live and bonus_until is not None:
        hold = FS_HOLD_NONE  # Hearth's own extra time replaced its lock
    elif lock_live:
        hold = FS_HOLD_PARENT if lock_until is not None else None
    else:
        hold = FS_HOLD_NONE
    local = dt_util.as_local(until).isoformat() if until is not None else None
    return {
        "hold": hold,
        "override": override or ("none" if known else None),
        "override_until": local,
        "allow_until": local if override == FS_ALLOW_UNTIL else None,
        "entity_id": found.entity_id,
        "source": FS_FROM_HEARTH,
    }


def family_safety_grant(state: dict[str, Any]) -> dict[str, Any] | None:
    """The Family Safety hook: what a platform's hold state ({hold: ours|parent|bonus_ours|none, override,
    allow_until}) means while Hearth holds it. A parent's extra time (allowUntil) is a grant until it ends (ended early
    by cancelling it); a parent's cancelled lock (no override left) is a grant for the day (ended early by locking
    again); a parent's own lock (blockUntil) is no grant but a parent lock. None when nothing is a parent's."""
    from . import grants as g

    if state.get("hold") != FS_HOLD_PARENT:
        return None
    override = state.get("override")
    if override == FS_ALLOW_UNTIL:
        until = dt_util.parse_datetime(str(state.get("allow_until") or ""))
        if until is not None and until.tzinfo is None:
            until = until.replace(tzinfo=dt_util.get_default_time_zone())
        return {"reason": "extra time given in the Family Safety app", "until": until, "end_with": g.END_CANCEL_BONUS}
    if override == "none":  # null is unreadable: nothing said
        return {"reason": "unlocked in the Family Safety app", "until": None, "end_with": g.END_RELOCK}
    return None


def _clock(value: Any) -> str | None:
    """A time entity's state as HH:MM:SS, or None when it's not a time or bedtime is off (00:00)."""
    if not isinstance(value, str) or len(value) < 5 or not value[:2].isdigit():
        return None
    text = value if len(value) == 8 else f"{value[:5]}:00"
    return None if text.startswith("00:00") else text


def _held_weekday_call(restore: dict[str, Any], limit: int | None) -> dict[str, Any] | None:
    """The update_daily_restrictions call that puts a held weekday back as it was (None without a device or day)."""
    if not restore.get("device_id") or restore.get("weekday") not in WEEKDAYS:
        return None
    data: dict[str, Any] = {"device_id": restore["device_id"], "day_of_week": restore["weekday"]}
    # No limit (-1) is left out: that's "no limit" to the service
    if limit is not None and 0 <= limit <= 360:
        data["max_play_time"] = int(limit)
    start, end = _clock(restore.get("bedtime_alarm")), _clock(restore.get("bedtime_end_time"))
    if start and end:
        data["bedtime_start"], data["bedtime_end"] = start, end
    return data


def _resume_outcomes(response: Any) -> dict[str, Any]:
    """What a resume_app answer says of each app (restored, kept_current, ...); nothing from an older Family Link."""
    if not isinstance(response, dict):
        return {}
    results = response.get("results")
    if isinstance(results, dict):
        return {str(k): v for k, v in results.items()}
    found: dict[str, Any] = {}
    for outcome in (RESTORED, KEPT_CURRENT):
        for package in response.get("resumed" if outcome == RESTORED else outcome) or {}:
            found[str(package)] = outcome
    return found


def _holding(held: Held) -> set[str]:
    """What's held, with a Switch or a child's devices whose hold was started (the limit kept) but didn't finish."""
    started = set()
    if "max" in held.restore:
        started.add(SWITCH)
    if "lock_minutes" in held.restore:
        started.add(DEVICES)
    return held.items | started


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


def next_midnight(now: datetime | None = None) -> datetime:
    """The next local midnight (with its offset): when a Family Safety lock of Hearth's ends."""
    now = now or dt_util.now()
    return dt_util.start_of_local_day(now + timedelta(days=1))


def fs_account_of(hass: HomeAssistant, entity_id: str) -> str | None:
    """The Family Safety account (Microsoft user id) of an entity: the id itself when typed in, the entity's user_id,
    else the user_id of another entity of its device (the child's account device)."""
    if "." not in entity_id:
        return entity_id or None
    candidates = [entity_id]
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id)
    if entry is not None and entry.device_id:
        candidates += [o.entity_id for o in er.async_entries_for_device(registry, entry.device_id)]
    for candidate in candidates:
        state = hass.states.get(candidate)
        account = state.attributes.get("user_id") if state else None
        if account not in (None, ""):
            return str(account)
    return None


def fs_accepts(hass: HomeAssistant, service: str, data: dict[str, Any]) -> bool:
    """The installed Family Safety's [service] takes [data] (its schema accepts it): how Hearth tells what this Family
    Safety can do (upstream's add_time_bonus and cancel_time_bonus take the Xbox only, a newer one Windows too; the
    schedule's set_screentime_limit with day_of_week, by entity or by account id). False when it has no [service]."""
    found = hass.services.async_services_for_domain(FS_DOMAIN).get(service)
    if found is None:
        return False
    if found.schema is None:
        return True
    try:
        found.schema(dict(data))
    except vol.Invalid:
        return False
    return True


def fs_day_limit_entity(hass: HomeAssistant, entity_id: str, platform: str, weekday: str) -> str | None:
    """The Family Safety child's limit of a weekday ("monday"...) for Windows or the Xbox: the integration's per-day
    limit number (unique id <entry>_<account>_limit_<weekday>, the Xbox's <entry>_<account>_xbox_limit_<weekday>; the
    Xbox's exists once the child's Xbox schedule is on). None when there's none."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    suffix = f"_{account}_xbox_limit_{weekday}" if platform == "Xbox" else f"_{account}_limit_{weekday}"
    return next(
        (
            entry.entity_id
            for entry in er.async_get(hass).entities.values()
            if entry.domain == "number" and entry.platform == FS_DOMAIN and str(entry.unique_id).endswith(suffix)
        ),
        None,
    )


def hours_to_midnight(now: datetime | None = None) -> int:
    """Whole hours until the next local midnight (at least 1): a lock that lasts the day, and ends with it."""
    now = now or dt_util.now()
    midnight = dt_util.start_of_local_day(now + timedelta(days=1))
    return max(1, min(24, math.ceil((midnight - now).total_seconds() / 3600)))
