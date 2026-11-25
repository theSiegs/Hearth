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
  covers (Games, say), until the pause ends (let go before midnight as above). A parent's grant from the Nintendo app
  lifts it; an allow doesn't, as for any pause.
  A Switch the family shares (switch_play.py) is held only once the person is caught playing it, and then stays held
  until they have time again (or the pause ends, a grant, midnight), whatever the playing sources say after; an
  adult's "Let someone else play" lifts it for a turn, and the person playing in it is caught again at once.
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
  hold Family Safety's platforms and the Switch (schedule_wanted). Family Link keeps its own School time; its bedtime
  follows the schedule's through bedtime_sync.py, and Sleep locks its devices whole where it has none running.

- Extra time at bedtime (bedtime_lift.py): an adult's extra time of All screen time given in bedtime lifts the
  schedule's Sleep and the bedtime locks while it lasts, so Sleep's holds above are let go; Family Link's bedtime
  tonight is moved to start when the extra time ends (a today-only override) and put back after, only while it still
  reads Hearth's start.

An adult's allow (hearth.allow, exceptions.py) takes its app or group out of the holds above while it lasts, but not
out of a platform Family Safety locks whole: on the Xbox, while daily time alone locks it, the lock is swapped for a
pause of every other Xbox app (_xbox_swap, with Family Link's dwell and swap breaker) where that can be done safely;
Windows stays locked, and hearth.allow and hearth.explain say so (platform_open). A parent's grant (a change in the
Family Link, Nintendo or Family Safety app, grants.py) takes out only the hold it came from.

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
from homeassistant.exceptions import ServiceNotFound, ServiceValidationError
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
from . import switch_play as sp

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
# How long a Switch limit Hearth put back may still read 0 (the Nintendo integration polls)
SWITCH_PUT_BACK_FRESH = timedelta(minutes=5)
SETTLE = timedelta(minutes=5)
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
# ... or this soon when the parental control wasn't there yet (its integration still loading after a start)
RETRY_NOT_LOADED = timedelta(seconds=30)
# How long after Hearth starts an unavailable entity counts as still loading (later: a real outage, tried every 5 min)
LOADING_WINDOW = timedelta(minutes=10)
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
# held.restore keys of a Family Link enforcer's app pauses. Apps whose pause call failed or never showed (they may be
# paused all the same: let go like held ones); apps whose pause Family Link has shown intact once (only those can
# later be "changed by a parent"); and apps whose pause never showed: {package: {tries, at}} (said as an error and
# tried again, each time after a longer wait)
MAYBE_PAUSED = "maybe_paused"
PAUSES_INTACT = "pauses_intact"
PAUSES_NOT_TAKEN = "pauses_not_taken"
# A pause Family Link doesn't show intact this long after Hearth's last call didn't take (its lists follow within a
# poll or two)
PAUSE_SHOWS_WITHIN = timedelta(minutes=3)
# The longest wait between tries of a pause that doesn't take (RETRY, doubled each time, up to this)
PAUSE_RETRY_MAX = timedelta(hours=1)
# How held.error starts while a pause didn't take
PAUSE_NOT_TAKEN = "Family Link didn't take the pause"
# held.restore key of a Family Link enforcer: the apps of a resume call that failed or was cut off part-way. Family
# Link resumes a list one app after the other and raises at the first one refused, so some are resumed and the rest
# still paused: the next pass tells them apart by Family Link's own pause records (_reconcile_resume)
RESUME_UNSURE = "resume_unsure"
# held.restore keys: when Hearth started putting a limit back (Family Link's daily limit, a Switch's). A call cut off
# by a reload or a restart, or one that failed after the write went out, leaves the hold in Hearth's books while the
# limit reads what Hearth itself put back: within OWN_PUT_BACK_WITHIN that reading is Hearth's own write, never a
# parent's change
LOCK_PUT_BACK_AT = "lock_put_back_at"
SWITCH_PUT_BACK_AT = "put_back_at"
OWN_PUT_BACK_WITHIN = timedelta(minutes=15)
# held.restore keys of a Family Safety enforcer, kept before the call: a lock under way or that failed (platform -> the
# end it asked for, ISO): it may be in force all the same, so the platform is possibly held (_holding) and a lock
# showing that end is Hearth's; and when Hearth started unlocking a platform (platform -> ISO): within
# OWN_PUT_BACK_WITHIN nothing locked there is Hearth's own unlock (_fs_own_unlock), never a parent's
FS_LOCKING = "fs_locking"
FS_UNLOCKING = "fs_unlocking"
# held.restore keys of a Family Safety enforcer's Xbox and Windows app pauses, kept before the call (pause_app,
# resume_app): the apps a call that failed or was cut off (a reload cancels calls mid-flight) may have left paused
# (possibly held: letting go resumes them, _holding), and when that was. Once the Applications sensor's paused_apps
# has had the time to show it (PAUSE_SHOWS_WITHIN), the next pass keeps as held only the apps Family Safety still has
# a pause of its own of ("ours", _fs_reconcile), and with no whole list keeps them all possibly held
FS_MAYBE_PAUSED = "fs_maybe_paused"
FS_UNSURE_AT = "fs_unsure_at"
# Swapping between the device lock and pausing every app costs a Family Link call per app, each way. After a swap,
# Hearth stays on the device lock at least this long before it pauses every app again
SWAP_DWELL = timedelta(minutes=10)
# This many swaps within SWAP_WINDOW and Hearth stays on the device lock (one call, and it holds everything) for
# SWAP_BREAK, and says so once
MAX_SWAPS = 4
SWAP_WINDOW = timedelta(hours=1)
SWAP_BREAK = timedelta(hours=1)
LOCK_KIND_DEVICES = "devices"
LOCK_KIND_APPS = "apps"
XBOX = "Xbox"
# The Xbox's own parts, never paused when an allow swaps the Xbox lock for a pause of every other Xbox app: the home
# screen (dashboard), the Guide, Settings, the Store and Microsoft Edge, and the companion apps that hold the rest.
# Family Safety lists an Xbox app as x:<its title id>; no id of these was found in Hearth's code or tests nor in
# Family Safety's, so they're matched by the name the Applications sensor gives them (lower case). Add an id to
# XBOX_NEVER_PAUSED once it's seen on a console. Whether these show in the Applications list at all is a live check
XBOX_NEVER_PAUSED: frozenset[str] = frozenset()
XBOX_NEVER_PAUSED_NAMES = frozenset(
    {
        "home",
        "xbox home",
        "dashboard",
        "xbox dashboard",
        "guide",
        "xbox guide",
        "settings",
        "xbox settings",
        "microsoft store",
        "store",
        "microsoft edge",
        "edge",
        "xbox family settings",
        "family safety",
        "microsoft family safety",
        "my games & apps",
    }
)
# Why an allow of an app couldn't open a platform Hearth locks whole (Enforcement.platform_open; hearth.allow's
# not_on, hearth.explain's platform_lock): Windows is never swapped; on the Xbox each reason the swap fell back
NOT_ON_WINDOWS = "windows_locked_whole"
NOT_ON_HELD = "held_otherwise"
NOT_ON_NO_PAUSE_APP = "family_safety_cannot_pause_apps"
NOT_ON_NO_TRACKING = "family_safety_pauses_not_readable"
NOT_ON_LIST = "applications_list_unknown"
NOT_ON_TOO_MANY = "too_many_apps"
NOT_ON_NOT_INSTALLED = "allowed_app_not_listed"
NOT_ON_BLOCKED = "allowed_app_blocked"
NOT_ON_DWELL = "swapped_lately"
NOT_ON_UNLISTED = "xbox_games_not_all_listed"
# The Xbox swap is off: Family Safety's Applications list for an Xbox holds only the apps it has a setting for (blocked,
# limited, asked for), not the games played (a kid playing 3 hours a day had 3 apps listed, all blocked games). Pausing
# "every other app" would pause only those, and unlocking would open every game not listed. Turn it on only once the
# list is known to hold every installed game
XBOX_SWAP = False

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
# Android's own parts and the home screens, by name: the system UI, the phone and its calls, contacts, the stock
# launcher and keyboard, and what installs apps and grants permissions. Never the whole com.android.* prefix: real
# apps live there too (Chrome is com.android.chrome), and those are paused and blocked like any app
SYSTEM_PARTS = frozenset(
    {
        "com.android.systemui",
        "com.android.phone",
        "com.android.server.telecom",
        "com.android.incallui",
        "com.android.dialer",
        "com.android.contacts",
        "com.android.emergency",
        "com.android.inputmethod.latin",
        "com.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.google.android.packageinstaller",
        "com.android.launcher3",
        "com.sec.android.app.launcher",
        "com.google.android.apps.nexuslauncher",
        "com.google.android.launcher",
        "com.google.android.apps.tv.launcherx",
    }
)
ESSENTIAL = TRANSITION_CLIENTS | CLOCKS | SYSTEM_PARTS | frozenset(
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
    """Never paused or blocked: the explicit system list (SYSTEM_NEVER_PAUSED), the same one the whole-device path
    reads (Enforcement._all_apps_but). No com.android.* prefix rule: Chrome and other real apps there are held."""
    return package in SYSTEM_NEVER_PAUSED


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
    # A shared Switch: entities that are on while this person is the one playing (a patched Nintendo integration's
    # player "playing" sensor, or friend presence). With any (or a player's minutes below), the Switch is held only
    # once this person is caught playing, so a brother or sister with time left can play (switch_play.py)
    playing: tuple[str, ...] = ()
    # Family Link: apps paused while the child's School time is on
    school_apps: tuple[str, ...] = ()
    # A shared Switch: the person's player's minutes today ("<nickname> used screen time"): minutes that grow say
    # they're playing
    player: tuple[str, ...] = ()
    # Minutes that grew this many minutes ago still say "playing" (None: switch_play.WINDOW)
    window: int | None = None

    @property
    def shared(self) -> bool:
        """A Switch others play too: something says who's playing it."""
        return self.kind == NINTENDO and bool(self.playing or self.player)

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
        player = tuple(e for e in raw.get("player") or () if isinstance(e, str)) if kind == NINTENDO else ()
        window = raw.get("window") if kind == NINTENDO and isinstance(raw.get("window"), int) else None
        school_apps = (
            tuple(p.strip() for p in raw.get("school_time_apps") or () if isinstance(p, str) and school_pausable(p.strip()))
            if kind == FAMILY_LINK
            else ()
        )
        found.append(Enforcer(kind, person, entity_id, groups, platforms, playing, school_apps, player, window))
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
            held = {ALL_APPS} if lifted is not None and (lifted.open or lifted.open_apps) else {DEVICES}
    else:
        held = set()
    for group_id in closed:
        # essential() is the explicit system list, as the whole-device path reads it (no com.android.* prefix)
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
        # When this started: an entity with no state yet in the first minutes is still loading, not broken
        self._started = dt_util.utcnow()
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
        # Kept over a reload or restart (the store): a change Hearth's own call caused mustn't read as a parent's
        # because Hearth started again in between
        self._quiet_until: dict[str, datetime] = {}
        # Swaps between the device lock and pausing every app, by Family Link enforcer key: {kind, at: [ISO times of
        # the swaps of the last hour], until: ISO time the breaker holds the device lock to} (kept in the store)
        self._swaps: dict[str, dict[str, Any]] = {}
        # Each Family Link child's last whole read of their Always allowed apps (kept in the store)
        self._always_last: dict[str, list[str]] = {}
        # Why each wanted item is held, by enforcer key: {item: budget, school_time or pause} (for Hearth's page)
        self._why: dict[str, dict[str, str]] = {}
        # Family Safety platforms Hearth keeps locked whole although an allow names apps on them, by person:
        # [{platform, why (NOT_ON_*)}] (hearth.allow's not_on, hearth.explain's platform_lock). Worked out each update
        self.platform_open: dict[str, list[dict[str, str]]] = {}
        # The refreshes waiting after a write, by entity: one each at a time
        self._refresh: dict[str, CALLBACK_TYPE] = {}
        # A Switch's limit Hearth just put back, by entity: its number may still read 0 for a moment, and a hold
        # right after (another kid's) must keep the real one (when, what was put back)
        self._switch_put_back: dict[str, tuple[datetime, dict[str, Any]]] = {}
        # When the extra time Hearth last gave on a Family Safety platform today ends: (person, platform) -> datetime
        # or None (native_sync.py sets it). With what Hearth locked, how Hearth tells its own from a parent's
        self.fs_bonus_until = None
        # ... and when each of today's ends: (person, platform) -> [datetime]
        self.fs_bonus_ends = None
        # Cancels the Nintendo extra playing time running on a Switch when it's Hearth's own (async, entity -> bool;
        # native_sync.py sets it): the Switch refuses a new limit while extra time runs
        self.cancel_own_switch_extra = None
        # The values Hearth's Family Link backstop wrote today (backstop.py sets it): never put back as a weekday's limit
        self.backstop_values = None
        # The action log (activity.py; the household sets it): each hold started and ended
        self.activity = None
        # A shared Switch, by enforcer key: caught, someone else's turn, armed (switch_play.py); kept over a restart
        self.switch: dict[str, sp.SwitchWatch] = {}
        # What Hearth has seen of each player's minutes today, by entity
        self.minutes: dict[str, sp.MinutesTrack] = {}
        # Whether each Switch enforcer's person is playing now (None: unknown), as of the last update
        self.playing_now: dict[str, bool | None] = {}
        # ... and what their player's minutes alone say
        self.minutes_playing: dict[str, bool | None] = {}
        # Whether something would hold each Switch enforcer's Switch if its person were playing, as of the last update
        self.switch_reason: dict[str, bool] = {}
        # Play no player's minutes count, by Switch entity, while a kid on it would be held if caught (in memory)
        self.consoles: dict[str, sp.ConsoleWatch] = {}
        # Each Switch's players' and console's minutes sensors, looked up once per update (the registry is read whole)
        self._console_entities: dict[str, tuple[list[str], str | None]] = {}
        # Called with (enforcer, what, details) when a shared Switch's kid is caught, caught again in someone else's
        # turn, a turn ends or the hold is over (household.py tells the adults)
        self.on_switch = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for key, data in stored.get("held", {}).items():
            self.held[key] = Held(
                set(data.get("items", [])), data.get("entity_id"), restore=dict(data.get("restore") or {})
            )
        self.last = {key: dict(record) for key, record in (stored.get("last") or {}).items() if isinstance(record, dict)}
        now = dt_util.utcnow()
        for key, until in (stored.get("quiet") or {}).items():
            # Never longer than Hearth itself sets it (a clock set back mustn't keep parents' changes unseen)
            if (when := _utc(until)) is not None and now < when <= now + QUIET_AFTER_CALL:
                self._quiet_until[key] = when
        self._swaps = {
            key: {"kind": record.get("kind"), "at": list(record.get("at") or []), "until": record.get("until")}
            for key, record in (stored.get("swaps") or {}).items()
            if isinstance(record, dict)
        }
        self._always_last = {
            str(child): [a for a in apps if isinstance(a, str)]
            for child, apps in (stored.get("fl_always_allowed") or {}).items()
            if isinstance(apps, list)
        }
        # Each child's last whole read of their Family Link app lists, back before the first run asks for it: a
        # list cut short by Hearth's own pauses must not read as "apps not known" after a restart
        fl.restore_installed(self.hass, stored.get("fl_installed"))
        fl.on_installed_changed(self.hass, self._installed_changed)
        self.switch = {
            key: sp.SwitchWatch.from_dict(raw) for key, raw in (stored.get("switch") or {}).items() if isinstance(raw, dict)
        }
        self.minutes = {
            key: sp.MinutesTrack.from_dict(raw) for key, raw in (stored.get("minutes") or {}).items() if isinstance(raw, dict)
        }

    @callback
    def _installed_changed(self) -> None:
        if not self._closed:
            self._save()

    def family_link_holding(self, person: str) -> set[str]:
        """The packages Hearth holds for the person through Family Link, with those a pause call may have paused
        (maybe_paused); never the devices."""
        found: set[str] = set()
        for key, held in self.held.items():
            if key_parts(key) == (FAMILY_LINK, person):
                found |= _holding(held)
        return found - {DEVICES}

    def family_link_devices_held(self, person: str) -> bool:
        """Hearth holds the person's Family Link devices (the weekday's daily limit at 0), has started or is ending
        that hold, or just called Family Link: a today-only daily limit written now would open the devices and read
        as a parent's change (schedule.py's day-off bonus waits)."""
        key = f"{FAMILY_LINK}|{person}"
        held = self.held.get(key)
        return (held is not None and DEVICES in _holding(held)) or self._quiet(key)

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
            # Each Family Link child's last whole read of their installed apps (family_link.installed_apps)
            "fl_installed": fl.last_installed(self.hass),
            # ... and of their Always allowed apps
            "fl_always_allowed": self._always_last,
            # Until when a change is Hearth's own call showing, by enforcer
            "quiet": {key: until.isoformat() for key, until in self._quiet_until.items() if until > dt_util.utcnow()},
            "swaps": self._swaps,
            # A shared Switch's caught hold, turn or arming, and each player's minutes Hearth has seen today
            "switch": {key: w.to_dict() for key, w in self.switch.items() if w.caught_at or w.turn or w.since},
            "minutes": {key: t.to_dict() for key, t in self.minutes.items() if t.value is not None},
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
        sleep_locks_devices_of=None,
        device_bedtime_of=None,
        fs_blocks_of=None,
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
        paused when it was blocked stays as held (Family Link's resume_app skips a blocked app anyway);
        [sleep_locks_devices_of]: whether the weekly schedule's Sleep locks a person's Family Link devices whole (no
        Family Link bedtime of their own: household.sleep_locks_devices); [device_bedtime_of]: what a bedtime lift on
        one device lifts of an enforcer's schedule holds (a Family Safety platform, a Switch, in Sleep only);
        [fs_blocks_of]: the Xbox and Windows apps Hearth's own blocks are for (app_blocks.py), never paused by the
        Xbox swap (_xbox_swap)."""
        self.enforcers = enforcers
        now = dt_util.now()
        self._console_entities = {}
        wanted_now: dict[str, set[str]] = {}
        why_now: dict[str, dict[str, str]] = {}
        platform_open: dict[str, list[dict[str, str]]] = {}
        for e in enforcers:
            lifted = lifted_of(e.person) if lifted_of else None
            # A Switch: what would hold it if this person were the one playing; whether to hold it is the caught
            # hold's (_switch_gate, below). Who's playing (verdict) only catches
            verdict = self._playing(e, now)
            playing = True if e.kind == NINTENDO else None
            # [budget_lifted_of]: what lifts a budget hold only: the allows, and a category's own bonus left (its apps
            # run past daily time). Bedtime, School time and pauses aren't lifted by it
            budget_lifted = budget_lifted_of(e.person) if budget_lifted_of else lifted
            budget = wanted(e, days.get(e.person), apps_of, now, playing, budget_lifted, groups_of_app)
            always_allowed, always_known = (
                self._always_allowed_read(e.entity_id) if e.kind == FAMILY_LINK else (set(), True)
            )
            if ALL_APPS in budget:
                every = self._all_apps_but(e, budget_lifted, apps_of, groups_of_app)
                # Which apps have unlimited time can't be told (the list cut short or not read, and no whole read
                # before): pausing every app would pause those too. The device lock spares them by itself
                if DEVICES not in every and not always_known:
                    every = {DEVICES}
                # Swapped too recently or too often: the device lock stays (_may_pause_every_app)
                if DEVICES not in every and not self._may_pause_every_app(e, now):
                    every = {DEVICES}
                budget = (budget - {ALL_APPS}) | every
                self._lock_kind(e.key, LOCK_KIND_DEVICES if DEVICES in every else LOCK_KIND_APPS, now)
            elif e.kind == FAMILY_LINK:
                self._lock_kind(e.key, LOCK_KIND_DEVICES if DEVICES in budget else None, now)
            # An app a parent gave unlimited time in Family Link is never paused for a budget: it stays usable, as on
            # a locked device. The School-time apps are the parent's own choice, so they are paused all the same.
            if e.kind == FAMILY_LINK:
                budget -= always_allowed
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
                # An adult's pause holds the Switch too (a family pause, or a group the enforcer covers), and locks
                # Family Safety's platforms the same way, as Sleep does
                paused_groups = set(paused_groups_of(e.person))
                paused |= paused_switch(e, paused_groups, now, playing)
                if e.kind == FAMILY_SAFETY and (ALL in paused_groups or paused_groups & set(e.groups)):
                    paused |= set(e.platforms)
                # A family pause locks a Family Link child's devices whole, as daily time running out does (a
                # phone or tablet without a Hearth app has nothing else holding it); let go before midnight
                if e.kind == FAMILY_LINK and ALL in paused_groups and not near_midnight(now):
                    paused.add(DEVICES)
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
                scheduled -= always_allowed
                # The schedule's Sleep for a kid without a Family Link bedtime: their devices are locked whole, as a
                # family pause does (nothing else would hold a phone or tablet without a Hearth app)
                if sleep_locks_devices_of and sleep_locks_devices_of(e.person):
                    scheduled.add(DEVICES)
            if device_bedtime_of:
                scheduled -= device_bedtime_of(e)
            device_lifted = device_lifted_of(e) if device_lifted_of else set()
            if e.kind == FAMILY_SAFETY:
                # An allow of Xbox apps while daily time locks the Xbox whole: every other Xbox app paused instead
                budget, not_on = self._xbox_swap(
                    e, budget, paused | scheduled, granted | device_lifted, lifted, apps_of, set(spared),
                    set(fs_blocks_of(e.person)) if fs_blocks_of else set(), now,
                )
                held_whole = (budget | paused | scheduled) - granted - device_lifted
                not_on = [n for n in not_on if n["platform"] in held_whole]
                if not_on:
                    platform_open.setdefault(e.person, []).extend(not_on)
            wanted_now[e.key] = (budget | school | paused | scheduled) - granted - device_lifted - set(spared)
            if e.kind == NINTENDO and not self._switch_gate(e, SWITCH in wanted_now[e.key], verdict, now, days):
                wanted_now[e.key].discard(SWITCH)
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
        self._watch_unattributed(enforcers, now)
        # What an enforcer no longer configured held is let go
        for key in self.held:
            wanted_now.setdefault(key, set())
        self._wanted = wanted_now
        self._why = why_now
        self.platform_open = platform_open
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

    def playing(self, enforcer: Enforcer) -> bool | None:
        """Whether their player's minutes say the person is playing their shared Switch, as the last update judged
        them (None: unknown, or no minutes). Their playing sensors are read where they're needed, as they are now."""
        return self.minutes_playing.get(enforcer.key)

    def _playing(self, enforcer: Enforcer, now: datetime | None = None) -> bool | None:
        """Whether the person is the one playing their shared Switch (switch_play.py): True, False only when a source
        trusts it (an "off" that stayed off, minutes watched a whole window without growing), None when unknown or
        the enforcer has no source (a Switch nobody else plays)."""
        if enforcer.kind != NINTENDO:
            return None
        now = now or dt_util.now()
        binaries, minutes = sp.sources_of(self.hass, enforcer)
        if not binaries and not minutes:
            self.playing_now.pop(enforcer.key, None)
            self.minutes_playing.pop(enforcer.key, None)
            return None
        # A patched copy's playing sensor beside its minutes is the same growth (and flickers off and on at each
        # reading): the minutes are read instead
        verdicts = [sp.binary_verdict(self.hass.states.get(b), now) for b in sp.own_signal(self.hass, binaries)]
        window = sp.window_of(enforcer.window)
        # The console's own minutes and its other players' (adults', guests'): growth after theirs is someone else
        everyone, console = self._console_of(enforcer.entity_id)
        others = [self._track(e, now) for e in [*everyone, *([console] if console else [])] if e not in minutes]
        by_minutes: list[bool | None] = []
        for entity_id in minutes:
            by_minutes.append(self._track(entity_id, now).verdict(now, window, others))
        self.minutes_playing[enforcer.key] = sp.combine(by_minutes)
        found = sp.combine(verdicts + by_minutes)
        self.playing_now[enforcer.key] = found
        return found

    def _console_of(self, entity_id: str) -> tuple[list[str], str | None]:
        if entity_id not in self._console_entities:
            self._console_entities[entity_id] = sp.console_entities(self.hass, entity_id)
        return self._console_entities[entity_id]

    def _track(self, entity_id: str, now: datetime) -> sp.MinutesTrack:
        """A minutes sensor's track, brought up to date (once per update is enough; again is harmless)."""
        track = self.minutes.setdefault(entity_id, sp.MinutesTrack())
        was = track.to_dict()
        track.observe(self.hass.states.get(entity_id), now)
        if track.to_dict() != was:
            self._save()
        return track

    def _switch_minutes(self, enforcer: Enforcer) -> tuple[float | None, list]:
        """The person's player minutes now (None unless every one of theirs is read fresh: one missing would read as
        a drop, and its return as play) and the states of their playing sensors that say more than the minutes."""
        binaries, minutes = sp.sources_of(self.hass, enforcer)
        values = [track.known if (track := self.minutes.get(entity_id)) is not None else None for entity_id in minutes]
        total = sum(values) if values and all(v is not None for v in values) else None
        return total, [self.hass.states.get(b) for b in sp.own_signal(self.hass, binaries)]

    def _watch_unattributed(self, enforcers: list[Enforcer], now: datetime) -> None:
        """Play on a Switch no player's minutes count (software that needs no user, or no user picked) while a kid on
        it would be held if caught: told to the adults with a button to hold it now (switch_play.ConsoleWatch), never
        held for it, since it may be an adult's."""
        waiting: dict[str, list[Enforcer]] = {}
        for e in enforcers:
            if e.kind != NINTENDO or not e.shared or not self.switch_reason.get(e.key):
                continue
            watch = self.switch.get(e.key)
            if watch is not None and (watch.caught_at is not None or watch.turn is not None):
                continue
            waiting.setdefault(e.entity_id, []).append(e)
        for entity_id in list(self.consoles):
            if entity_id not in waiting:
                self.consoles.pop(entity_id)
        for entity_id, kids in waiting.items():
            everyone, console = self._console_of(entity_id)
            if console is None or not everyone:
                continue
            values = [self._track(e, now).known for e in everyone]
            players = sum(values) if all(v is not None for v in values) else None
            found = self.consoles.setdefault(entity_id, sp.ConsoleWatch()).update(
                self._track(console, now).known, players, now
            )
            if found is not None:
                self._tell(kids[0], "unattributed", minutes=int(found), held_for=sorted(k.person for k in kids))

    def _tell(self, enforcer: Enforcer, what: str, **details: Any) -> None:
        self.hass.bus.async_fire(
            "hearth_switch", {"person": enforcer.person, "entity_id": enforcer.entity_id, "what": what, **details}
        )
        if self.on_switch is not None:
            try:
                self.on_switch(enforcer, what, details)
            except Exception:  # noqa: BLE001 - a notice failing mustn't stop the holds
                _LOGGER.exception("Hearth couldn't tell the adults about the Switch")

    def _switch_gate(
        self, enforcer: Enforcer, reason: bool, playing: bool | None, now: datetime, days: dict[str, PersonDay]
    ) -> bool:
        """Whether to hold the Switch for this person now, given whether something would ([reason]): once they're
        caught playing it stays held until the reason is gone (time back, a grant, midnight), but in someone else's
        turn; caught again when they play in it. A Switch nobody else plays is caught at once. What the playing
        sources say never lets a hold go."""
        key = enforcer.key
        today = dt_util.as_local(now).date().isoformat()
        self.switch_reason[key] = reason
        watch = self.switch.get(key)
        if watch is None or watch.day != today:
            watch = self.switch[key] = sp.SwitchWatch(day=today)
        if not reason:
            if watch.caught_at or watch.turn or watch.since:
                told = watch.caught_at is not None or watch.turn is not None
                self.switch[key] = sp.SwitchWatch(day=today)
                self._save()
                if told and enforcer.shared:
                    self._tell(enforcer, "released")
            return False
        minutes, binaries = self._switch_minutes(enforcer)
        if watch.turn:
            other = watch.turn.get("for_person")
            if watch.played_since(minutes, binaries, now):
                watch.turn, watch.caught_at = None, now
                watch.since = watch.baseline = watch.absorb_until = None
                self._save()
                self._tell(enforcer, "caught_in_turn", for_person=other)
                return True
            ran_out = bool(other and out_of_time(days.get(other), enforcer.groups))
            if now < watch.turn["until"] and not ran_out:
                return False
            # The turn is over: open, and held again only once this person plays after it
            watch.turn = None
            watch.arm(now, minutes)
            self._save()
            self._tell(enforcer, "turn_ended", for_person=other)
        held = self.held.get(key)
        if watch.caught_at is None and watch.since is None and held is not None and SWITCH in held.items:
            # Held already (by an older Hearth, or a run under way): that's caught
            watch.caught_at = now
            self._save()
        if watch.caught_at is not None:
            return True
        if not enforcer.shared:
            catch = True
        elif watch.since is not None:
            catch = watch.played_since(minutes, binaries, now)
        else:
            catch = playing is True
        if not catch:
            return False
        watch.caught_at = now
        watch.since = watch.baseline = watch.absorb_until = None
        self._save()
        if enforcer.shared:
            self._tell(enforcer, "caught")
        return True

    def switch_enforcers(self, entity_ids: set[str]) -> list[Enforcer]:
        return [e for e in self.enforcers if e.kind == NINTENDO and e.entity_id in entity_ids]

    def let_someone_play(
        self, entity_ids: set[str], minutes: int, for_person: str | None = None, by: str | None = None
    ) -> list[str]:
        """Let someone else play: Hearth's caught holds on these Switches are lifted for [minutes]. 0 holds the Switch
        now for each kid on it something would hold it for: it ends a turn, or catches a kid not caught yet (an adult
        who sees them playing, or play no player counts). Says whose holds; raises ValueError when there's none."""
        now = dt_util.now()
        today = now.date().isoformat()
        found: list[str] = []
        for e in self.switch_enforcers(entity_ids):
            watch = self.switch.get(e.key)
            if watch is None or watch.day != today:
                continue
            if minutes <= 0:
                if watch.turn is not None or (watch.caught_at is None and self.switch_reason.get(e.key)):
                    watch.turn, watch.caught_at = None, now
                    watch.since = watch.baseline = watch.absorb_until = None
                    found.append(e.person)
                    self._tell(e, "held_now", by=by)
                continue
            if watch.caught_at is None and watch.turn is None:
                continue
            if for_person == e.person:
                raise ValueError("Hearth holds the Switch for them: give them extra time instead")
            value, _ = self._switch_minutes(e)
            # Nintendo's next upload may still carry play from before the hold: forgiven once
            grace = watch.caught_at + sp.UPLOAD_GRACE if watch.caught_at else watch.absorb_until
            watch.turn = {"started": now, "until": now + timedelta(minutes=minutes), "for_person": for_person, "by": by}
            watch.caught_at = None
            watch.since, watch.baseline = now, value
            watch.absorb_until = grace if grace is not None and grace > now else None
            found.append(e.person)
        if not found:
            raise ValueError(
                "Nothing would hold this Switch for anyone now"
                if minutes <= 0
                else "Hearth isn't holding this Switch for anyone"
            )
        self._save()
        return found

    def switch_view(self, entity_id: str) -> dict[str, Any]:
        """For Hearth's page: who Hearth holds this Switch for (caught), someone else's turn, and who's playing."""
        today = dt_util.now().date().isoformat()
        caught: list[str] = []
        # Would be held once caught playing (out of time, paused, Sleep...), not caught yet
        waiting: list[str] = []
        turn: dict[str, Any] | None = None
        playing: dict[str, bool | None] = {}
        for e in self.switch_enforcers({entity_id}):
            if e.key in self.playing_now:
                playing[e.person] = self.playing_now[e.key]
            watch = self.switch.get(e.key)
            if watch is None or watch.day != today:
                continue
            if watch.caught_at is not None:
                caught.append(e.person)
            elif watch.turn is None and self.switch_reason.get(e.key):
                waiting.append(e.person)
            if watch.turn is not None:
                if turn is None:
                    turn = {
                        "until": watch.turn["until"].isoformat(),
                        "for_person": watch.turn.get("for_person"),
                        "held_for": [],
                    }
                turn["held_for"].append(e.person)
        return {"caught": sorted(caught), "waiting": sorted(waiting), "turn": turn, "playing": playing}

    def _switch_holders(self, key: str, entity_id: str | None) -> list[Held]:
        """Another person's hold on the same Switch, wanted still or not."""
        return [
            other
            for other_key, other in self.held.items()
            if other_key != key
            and other_key.startswith(f"{NINTENDO}|")
            and other.entity_id == entity_id
            and SWITCH in _holding(other)
        ]

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
        if want - (held.items - _ended_locks(held)):
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
            if kind == FAMILY_LINK and held.restore.get(RESUME_UNSURE) and entity_id is not None:
                # A resume failed part-way: what's held is what Family Link still has a pause record of
                self._reconcile_resume(held, entity_id)
            if kind == FAMILY_SAFETY and held.restore.get(FS_MAYBE_PAUSED) and entity_id is not None:
                # A pause or resume of apps failed or was cut off: held is what Family Safety still has a pause of
                self._fs_reconcile(held, entity_id)
            # A Family Safety lock that ran out (at midnight) while still wanted (Sleep, a pause) is locked again
            hold = want - (held.items - _ended_locks(held))
            let_go = _holding(held) - want if self._may_let_go() else set()
            if not (hold or let_go) or entity_id is None:
                continue
            # Kept before the calls: a half-done hold is let go through it if the enforcer is removed meanwhile
            if not _holding(held) or held.entity_id is None:
                held.entity_id = entity_id
            outcomes: dict[str, Any] = {}
            # Why each item is held, as it is now: a pause or resume of every app takes minutes, and what's wanted
            # (and why) may be something else by the time it's logged
            why = dict(self._why.get(key, {}))
            self._busy.add(key)
            try:
                # Switching between the whole-device lock and pausing apps one by one (a category open past daily
                # time): the new hold first, so a failure leaves the kid held too much rather than not at all (a
                # failed pause_app keeps the device lock, and is tried again)
                # The Xbox's lock and the pause of its other apps (an allow's swap, _xbox_swap) the same way
                hold_first = DEVICES in hold or DEVICES in let_go or (kind == FAMILY_SAFETY and XBOX in hold | let_go)
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
                    for reason in sorted({why.get(i, "limit") for i in hold}):
                        self.activity.hold(True, person, [i for i in hold if why.get(i, "limit") == reason], reason, kind)
                    if let_go:
                        self.activity.hold(False, person, let_go, None, kind)
            except Exception as err:  # noqa: BLE001 - one parental control failing mustn't stop the others
                loading = _not_loaded_yet(
                    self.hass, err, held.entity_id or entity_id, now - self._started < LOADING_WINDOW
                )
                (_LOGGER.debug if loading else _LOGGER.warning)(
                    "Hearth couldn't %s for %s through %s: %s", "hold" if hold else "let go", person, kind, err
                )
                # Not loaded yet: tried again in 30 s rather than 5 minutes
                held.error, held.failed_at = str(err)[:200], (now - RETRY + RETRY_NOT_LOADED) if loading else now
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
            key = next(k for k, v in self.held.items() if v is held)
            sharing = self._sharing(key, entity_id)
            if hold and not held.restore:
                # Another kid's hold on this Switch (wanted or about to let go) kept the real limit: the same one is
                # kept here, never the 0 Hearth set
                kept = next((o.restore for o in self._switch_holders(key, entity_id) if o.restore), None)
                if kept is None and (recent := self._switch_put_back.get(entity_id)) is not None:
                    at, put_back = recent
                    if dt_util.utcnow() - at < SWITCH_PUT_BACK_FRESH:
                        kept = put_back
                if kept is not None:
                    held.restore = dict(kept)
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
                    held.items.add(DEVICES)
                else:
                    if (outcome := await self._unlock_devices(held)) is not None:
                        outcomes[DEVICES] = outcome
                    # Let go even if resuming the apps below fails: it's never held again otherwise
                    held.items.discard(DEVICES)
            packages = items - {DEVICES}
            if packages:
                service = "pause_app" if hold else "resume_app"
                if hold:
                    # Kept before the call: Family Link pauses a list one app after the other and raises at the
                    # first one refused (or times out), so any of them may be paused by now. Possibly held until a
                    # pause of them goes through or they're resumed, so letting go resumes them (_holding)
                    _maybe_paused(held, packages)
                    self._save()
                try:
                    response = await call_service(self.hass,
                        "familylink",
                        service,
                        {"entity_id": entity_id, "packages": sorted(packages)},
                        blocking=True,
                        return_response=self._responds("familylink", service),
                    )
                except BaseException:  # a reload cutting the call off (CancelledError) too
                    if not hold:
                        # Family Link resumes one app after the other and raises at the first one refused: the
                        # apps before it are open again, the rest still paused. None is held for sure any more
                        # (a hold wanted again pauses them again); all stay possibly held, so letting go tries
                        # again; and the next pass sorts them by Family Link's pause records (_reconcile_resume)
                        held.items -= packages
                        _maybe_paused(held, packages)
                        held.restore[RESUME_UNSURE] = sorted(set(held.restore.get(RESUME_UNSURE) or ()) | packages)
                        # (a reload's flush stores it itself: nothing of this instance saves after that)
                        if not self._closed:
                            self._save()
                    raise
                _maybe_paused(held, packages, False)
                _resume_sure(held, packages)
                if not hold:
                    outcomes.update(_resume_outcomes(response))
                    _forget_pauses(held, packages)
            return outcomes
        apps = {item for item in items if fs_app(item)}
        for platform in sorted(items - apps):
            applied = await self._platform(entity_id, platform, hold, held)
            if not hold and applied is not None:
                outcomes[platform] = applied
            # Each platform as it's done: a later one failing mustn't leave this one counted as held (or not)
            if hold:
                held.items.add(platform)
            else:
                held.items.discard(platform)
        if apps:
            await self._fs_apps(entity_id, apps, hold, held)
        return outcomes

    def _responds(self, domain: str, service: str) -> bool:
        """The service gives an answer (a newer integration): asked for it then. A missing service raises at the call."""
        try:
            return self.hass.services.supports_response(domain, service) != SupportsResponse.NONE
        except Exception:  # noqa: BLE001 - not registered: the call itself says so
            return False

    async def _fs_apps(self, entity_id: str, apps: set[str], hold: bool, held: Held | None = None) -> None:
        """Xbox and Windows apps paused (a block that keeps whether each was blocked before) or resumed. Family
        Safety leaves an app a parent blocked alone, and resuming an app it hasn't paused does nothing (skipped).

        Kept before the call ([held]: FS_MAYBE_PAUSED): Family Safety pauses and resumes one app after the other, keeps
        its record of each pause before its write, and a call that fails or is cut off (a settings save reloads the
        entry and cancels it) may have paused or resumed any of them. Those stay possibly held, so letting go resumes
        them, until the call goes through or was refused before it went out; a resume that failed leaves none of its
        apps held for sure (sorted by _fs_reconcile). Apps the answer names as failed stay possibly held too."""
        if not self.hass.services.has_service(FS_DOMAIN, "pause_app"):
            if hold:
                raise ValueError("Family Safety can't pause apps (update it)")
            # Nothing to resume with: what it held can't have been paused by it
            return
        target = {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}
        service = "pause_app" if hold else "resume_app"
        before = set(held.restore.get(FS_MAYBE_PAUSED) or ()) if held is not None else set()
        if held is not None:
            _fs_maybe_paused(held, apps)
            held.restore[FS_UNSURE_AT] = dt_util.utcnow().isoformat()
            self._save()
        try:
            response = await call_service(self.hass,
                FS_DOMAIN, service, {**target, "apps": sorted(apps)}, blocking=True,
                return_response=self._responds(FS_DOMAIN, service), why="hold" if hold else "let_go",
            )
        except BaseException as err:  # a reload cutting the call off (CancelledError) too
            if held is not None:
                if refused_before_sent(err):
                    # Nothing went out: only what was possibly held before stays so
                    _fs_maybe_paused(held, apps - before, False)
                else:
                    if not hold:
                        # Some may be resumed, the rest still paused: none held for sure any more
                        held.items -= apps
                    held.restore[FS_UNSURE_AT] = dt_util.utcnow().isoformat()
                # (a reload's flush stores it itself: nothing of this instance saves after that)
                if not self._closed:
                    self._save()
            raise
        if held is not None:
            failed = response.get("failed") if isinstance(response, dict) else None
            unsure = {a for a in failed if a in apps} if isinstance(failed, dict) else set()
            _fs_maybe_paused(held, apps - unsure, False)
            if unsure:
                held.restore[FS_UNSURE_AT] = dt_util.utcnow().isoformat()

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
        why = "hold" if hold else "let_go"
        by_hours = False
        if held is not None:
            # Kept before the call: one that times out or is cut off after Microsoft applied it leaves a lock of
            # Hearth's in force (possibly held, FS_LOCKING) or nothing locked by Hearth's own unlock (FS_UNLOCKING),
            # never a parent's lock or unlock
            if hold:
                _restore_map(held, FS_LOCKING)[platform] = dt_util.as_utc(until).isoformat()
            else:
                _restore_map(held, FS_UNLOCKING)[platform] = dt_util.utcnow().isoformat()
            self._save()
        try:
            try:
                response = await self._fs_call(service, data, why)
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
                    if held is not None:
                        _restore_map(held, FS_LOCKING)[platform] = dt_util.as_utc(until).isoformat()
                _LOGGER.debug("Family Safety refused the newer %s call (%s): calling it as before", service, err)
                response = await self._fs_call(service, legacy, why)
                if hold and held is not None and until > end_at:
                    # Whole hours run past midnight: Hearth unlocks it itself then (async_lock_ends_tick)
                    _restore_map(held, FS_UNLOCK_AT)[platform] = dt_util.as_utc(end_at).isoformat()
        except (vol.Invalid, ServiceValidationError, ServiceNotFound):
            # Refused before it went out (no such action, a schema that doesn't take it): nothing changed
            if held is not None:
                _restore_map(held, FS_LOCKING if hold else FS_UNLOCKING).pop(platform, None)
                _tidy_restore(held)
            raise
        if held is not None:
            # Done: neither a lock nor an unlock of Hearth's is under way any more
            _restore_map(held, FS_LOCKING).pop(platform, None)
            _restore_map(held, FS_UNLOCKING).pop(platform, None)
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

    async def _fs_call(self, service: str, data: dict[str, Any], why: str | None = None) -> Any:
        """A Family Safety call, with its answer when the service gives one (an older one doesn't)."""
        responds = self.hass.services.supports_response(FS_DOMAIN, service) != SupportsResponse.NONE
        return await call_service(self.hass,
            FS_DOMAIN, service, data, blocking=True, return_response=responds, why=why
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
        return self._always_allowed_read(entity_id)[0]

    def _always_allowed_read(self, entity_id: str) -> tuple[set[str], bool]:
        """The child's apps with unlimited time in Family Link, and whether they're known. A list cut short
        (truncated) or not readable (its sensor unavailable, or gone) is what it shows plus the last whole read (kept
        over a restart); with no whole read before, they aren't known (False): every app mustn't be paused on that,
        an always-allowed app would be paused with the rest."""
        child = fl.child_of(self.hass, entity_id)
        if not child:
            return set(), True
        read = fl.always_allowed_apps(self.hass, child)
        found, whole = read if read is not None else (set(), False)
        if whole:
            if self._always_last.get(child, []) != sorted(found):
                self._always_last[child] = sorted(found)
                self._save()
            return found, True
        if child in self._always_last:
            return found | set(self._always_last[child]), True
        return found, False

    def _may_pause_every_app(self, enforcer: Enforcer, now: datetime) -> bool:
        """Whether the device lock may be swapped for a pause of every app now. Each swap is a Family Link call per
        app (about 150 for a phone), each way, and whatever opens and closes a category in turn (a place flapping, a
        bonus running out and topped up) swaps again and again. So: not within SWAP_DWELL of the last swap, and after
        MAX_SWAPS swaps within SWAP_WINDOW not for SWAP_BREAK (said once: the log, Hearth's page, the action log).
        Until then the device lock stays: one call, and it holds everything. Only a swap is damped: from nothing
        held, every app is paused at once."""
        record = self._swaps.get(enforcer.key) or {}
        if (until := _utc(record.get("until"))) is not None and now < until:
            return False
        if record.get("kind") != LOCK_KIND_DEVICES:
            return True
        swaps = [w for at in record.get("at") or [] if (w := _utc(at)) is not None and now - w < SWAP_WINDOW]
        if len(swaps) >= MAX_SWAPS:
            until = now + SWAP_BREAK
            self._swaps[enforcer.key] = {**record, "until": dt_util.as_utc(until).isoformat()}
            self._save()
            _LOGGER.warning(
                "Hearth swapped %s's device lock and app pauses %s times within the hour: it keeps the devices locked "
                "until %s rather than pausing every app again",
                enforcer.person, len(swaps), dt_util.as_local(until).strftime("%H:%M"),
            )
            self.note(enforcer.key, swap_breaker=dt_util.as_utc(until).isoformat(), swaps=len(swaps))
            if self.activity is not None:
                self.activity.hold(
                    True, enforcer.person, XBOX if enforcer.kind == FAMILY_SAFETY else DEVICES, "swap_breaker",
                    enforcer.kind,
                )
            return False
        return not swaps or now - max(swaps) >= SWAP_DWELL

    def _lock_kind(self, key: str, kind: str | None, now: datetime) -> None:
        """Keeps how a Family Link kid's daily time out is held now (the device lock, a pause of every app, or
        neither), and when it swapped from one to the other."""
        record = self._swaps.get(key) or {}
        was = record.get("kind")
        if was == kind:
            return
        swaps = [at for at in record.get("at") or [] if (w := _utc(at)) is not None and now - w < SWAP_WINDOW]
        if was is not None and kind is not None:
            swaps.append(dt_util.as_utc(now).isoformat())
        until = record.get("until") if (w := _utc(record.get("until"))) is not None and now < w else None
        if kind is None and not swaps and until is None:
            self._swaps.pop(key, None)
        else:
            self._swaps[key] = {"kind": kind, "at": swaps, "until": until}
        self._save()

    def _xbox_swap(
        self, e: Enforcer, budget: set[str], others: set[str], lifted_whole: set[str], lifted: Lifted | None, apps_of,
        spared: set[str], fs_blocks: set[str], now: datetime,
    ) -> tuple[set[str], list[dict[str, str]]]:
        """An allow of Xbox apps (hearth.allow of an x:... app, or of a group with Xbox apps) while daily time locks
        the Xbox whole (a budget, [budget]): the Xbox lock is swapped for a pause of every other Xbox app of the
        Applications list, so the allowed one opens. Never paused: the allowed apps, blocked ones (Hearth's or a
        parent's: an allow never lifts a block, [fs_blocks] are Hearth's own), the Xbox's own parts
        (XBOX_NEVER_PAUSED, by id or name) and [spared]. Windows is never swapped (its apps can't run alone the same
        way): it stays locked. The lock stays, said in the answer (NOT_ON_*), when the Xbox is held otherwise ([others]:
        a pause, the schedule), Family Safety can't pause apps, the Applications list is missing or cut short, Family
        Safety's record of its pauses (paused_apps: what sorts a pause or resume that failed, fs_maybe_paused) can't be
        read, none of the allowed apps is in the list, there would be more than MAX_PACKAGES apps, or a swap was made
        lately (_may_pause_every_app: SWAP_DWELL, and the breaker after MAX_SWAPS an hour, as Family Link's). Returns
        the budget hold (the Xbox swapped for the apps, or as it was) and the platforms an allow names apps on that stay
        locked whole, with why."""
        not_on: list[dict[str, str]] = []
        if not lifted or lifted.everything:
            self._lock_kind(e.key, LOCK_KIND_DEVICES if XBOX in budget - lifted_whole else None, now)
            return budget, not_on
        if "Windows" in e.platforms and self._allowed_on(e, lifted, apps_of, "Windows"):
            not_on.append({"platform": "Windows", "why": NOT_ON_WINDOWS})
        allowed = self._allowed_on(e, lifted, apps_of, XBOX)
        if XBOX not in budget - lifted_whole or not allowed:
            self._lock_kind(e.key, LOCK_KIND_DEVICES if XBOX in budget - lifted_whole else None, now)
            return budget, not_on
        why = None
        apps: set[str] = set()
        lists = self._fs_xbox_apps(e.entity_id)
        records = fs_pause_records(self.hass, e.entity_id) if lists is not None else None
        if XBOX in others:
            why = NOT_ON_HELD  # a pause or the schedule: an allow doesn't lift those
        elif not self.hass.services.has_service(FS_DOMAIN, "pause_app"):
            why = NOT_ON_NO_PAUSE_APP
        elif lists is None:
            why = NOT_ON_LIST
        elif records is None:
            why = NOT_ON_NO_TRACKING
        elif not XBOX_SWAP:
            why = NOT_ON_UNLISTED
        else:
            installed, blocked, names = lists
            # Family Safety pauses an app by blocking it: an app blocked by a pause (its own record says "ours", or
            # Hearth holds it) isn't blocked by anyone, and stays in the swap's pause
            held = self.held.get(e.key)
            blocked -= {app for app, who in records.items() if who == FS_HOLD_OURS}
            blocked -= _holding(held) if held is not None else set()
            apps = {
                app
                for app in installed
                if app not in allowed and app not in blocked and app not in fs_blocks and app not in spared
                and app not in XBOX_NEVER_PAUSED and (names.get(app) or "").strip().lower() not in XBOX_NEVER_PAUSED_NAMES
            }
            if not allowed & installed:
                why = NOT_ON_NOT_INSTALLED
            elif not (allowed & installed) - blocked - fs_blocks:
                why = NOT_ON_BLOCKED  # a block stays: unlocking the Xbox would open nothing allowed
            elif len(apps) > MAX_PACKAGES:
                why = NOT_ON_TOO_MANY
            elif not self._may_pause_every_app(e, now):
                why = NOT_ON_DWELL
        if why is not None:
            self._lock_kind(e.key, LOCK_KIND_DEVICES, now)
            not_on.append({"platform": XBOX, "why": why})
            return budget, not_on
        self._lock_kind(e.key, LOCK_KIND_APPS, now)
        return (budget - {XBOX}) | apps, not_on

    @staticmethod
    def _allowed_on(e: Enforcer, lifted: Lifted, apps_of, platform: str) -> set[str]:
        """The apps of [platform] an adult's allows name for the enforcer's person: an app itself, or a group's."""
        found = {app for app in lifted.apps if fs_app_platform(app) == platform}
        for group_id in lifted.groups:
            if group_id != ALL:
                found |= {app for app in apps_of(group_id, e.person) if fs_app_platform(app) == platform}
        return found

    def _fs_xbox_apps(self, entity_id: str) -> tuple[set[str], set[str], dict[str, str]] | None:
        """The child's Xbox apps as Family Safety's Applications sensors list them: (installed, blocked, names), None
        when a list is missing or cut short (never "no apps")."""
        states = fs_applications(self.hass, entity_id)
        if not states:
            return None
        installed: set[str] = set()
        blocked: set[str] = set()
        names: dict[str, str] = {}
        for state in states:
            applications = state.attributes.get("applications")
            if state.attributes.get("truncated") or not isinstance(applications, list):
                return None
            for row in applications:
                app = row.get("app_id") if isinstance(row, dict) else None
                if not isinstance(app, str) or fs_app_platform(app) != XBOX:
                    continue
                installed.add(app)
                if row.get("blocked"):
                    blocked.add(app)
                if isinstance(row.get("app_name"), str):
                    names[app] = row["app_name"]
        return installed, blocked, names

    def _reconcile_resume(self, held: Held, entity_id: str) -> None:
        """After a resume that failed part-way: the apps Family Link still has a pause record of are held as before,
        the others were resumed and are let go of. While the records can't be read (no such list, or cut short), all
        of them stay possibly held: letting go resumes them again, a hold pauses them again."""
        unsure = set(held.restore.get(RESUME_UNSURE) or ()) & set(held.restore.get(MAYBE_PAUSED) or ())
        child = fl.child_of(self.hass, entity_id)
        records = self._pause_records(child) if child else None
        if unsure and records is None:
            return
        if unsure:
            still = unsure & records
            _maybe_paused(held, unsure, False)
            held.items |= still
            _forget_pauses(held, unsure - still)
        held.restore.pop(RESUME_UNSURE, None)
        self._save()

    def _fs_reconcile(self, held: Held, entity_id: str) -> None:
        """After a Family Safety pause or resume of apps that failed or was cut off (FS_MAYBE_PAUSED), once the
        Applications sensor has had the time to show it: the apps Family Safety still holds by a pause of its own
        ("ours" in paused_apps) are held as before, the others aren't (resumed, never paused, or unblocked by a parent
        since). Only from whole lists: while they can't be read, all of them stay possibly held (letting go resumes
        them again, harmless for an app that isn't paused; a hold pauses them again)."""
        unsure = set(held.restore.get(FS_MAYBE_PAUSED) or ())
        at = _utc(held.restore.get(FS_UNSURE_AT))
        if not unsure or (at is not None and dt_util.utcnow() - at < PAUSE_SHOWS_WITHIN):
            return
        records = fs_pause_records(self.hass, entity_id)
        if records is None:
            return
        ours = {app for app in unsure if records.get(app) == FS_HOLD_OURS}
        held.items = (held.items - unsure) | ours
        _fs_maybe_paused(held, unsure, False)
        self._save()
        _LOGGER.debug("Family Safety pauses sorted after a call that failed: %s held, %s not", sorted(ours), sorted(unsure - ours))

    def _pause_records(self, child: str) -> set[str] | None:
        """The packages Family Link has a pause record of for the child (paused_apps of their With time limits
        sensor); None when that can't be told (no such list, or cut short)."""
        found: set[str] | None = None
        for state in self.hass.states.async_all("sensor"):
            paused = state.attributes.get("paused_apps")
            if str(state.attributes.get("child_id")) != str(child) or not isinstance(paused, list):
                continue
            if state.attributes.get("truncated"):
                return None
            found = (found or set()) | {str(p.get("package")) for p in paused if isinstance(p, dict)}
        return found

    def _all_apps_but(self, enforcer: Enforcer, lifted: Lifted, apps_of, groups_of_app) -> set[str]:
        """Daily time out while a category stays open: every app the child has installed (Family Link's lists) but
        that category's and an explicit system list (ESSENTIAL and NEVER_PAUSED by name, never the com.android.*
        prefix, so Chrome and any other launchable com.android app are paused; launchers, keyboards and accessibility
        apps are spared later, household.never_held). The whole-device lock when the installed apps aren't known."""
        child = fl.child_of(self.hass, enforcer.entity_id)
        installed = fl.installed_apps(self.hass, child, self.family_link_holding(enforcer.person)) if child else None
        if not installed:
            return {DEVICES}
        # A standing rule's apps (Messages while out without an adult) stay open too
        open_apps: set[str] = set(lifted.open_apps)
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
        a half-done hold mustn't keep the 0). A lock of an earlier day (Sleep past midnight) first puts that weekday's
        limit back, then locks today's."""
        if "lock_minutes" in held.restore and held.restore.get("lock_day") != dt_util.now().date().isoformat():
            await self._unlock_devices(held)
            self._save()
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
        # Locked (again): a put-back that didn't finish is over, and the 0 has to show again
        if LOCK_PUT_BACK_AT in held.restore:
            held.restore.pop(LOCK_PUT_BACK_AT, None)
            held.restore.pop("lock_seen_zero", None)
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
                # Kept before the call: cut off by a reload, or failed after the write went out, the limit then
                # reads what Hearth put back while the hold is still in its books (never a parent's change)
                restore[LOCK_PUT_BACK_AT] = dt_util.utcnow().isoformat()
                self._save()
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
        # Bonus time given in the Nintendo app: the Switch refuses a new limit until it's over (said, not retried blind).
        # Hearth's own (its extra time's mirror, native_sync.py) is cancelled first
        if self.switch_extended(entity_id) and not (
            self.cancel_own_switch_extra is not None and await self.cancel_own_switch_extra(entity_id)
        ):
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
        elif SWITCH_PUT_BACK_AT in held.restore:
            # Held again: a put-back that didn't finish is over, and the 0 has to show again
            held.restore.pop(SWITCH_PUT_BACK_AT, None)
            held.restore.pop("seen_zero", None)
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
            # Kept before the call, as for Family Link's daily limit (_unlock_devices)
            restore[SWITCH_PUT_BACK_AT] = dt_util.utcnow().isoformat()
            self._save()
            await call_service(self.hass,
                "number", "set_value", {"entity_id": entity_id, "value": limit}, blocking=True
            )
        suspend = restore.get("suspend")
        if suspend and restore.get("suspend_was") == "off":
            await call_service(self.hass, "switch", "turn_off", {"entity_id": suspend}, blocking=True)
        self._switch_put_back[entity_id] = (
            dt_util.utcnow(), {k: v for k, v in restore.items() if k != SWITCH_PUT_BACK_AT}
        )
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
                    if state is not None and not quiet and self._fs_own_unlock(held, platform, state):
                        continue
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
        elif (
            current is not None
            and current == held.restore.get("max")
            and _own_put_back(held.restore.get(SWITCH_PUT_BACK_AT))
        ):
            # Hearth's own put-back, cut off (a reload, a restart) or failed after the write went out: not a parent's
            # change. The Switch isn't held any more; still wanted, it's held again, else let go of as usual
            held.items.discard(SWITCH)
            held.restore.pop(SWITCH_PUT_BACK_AT, None)
            held.restore.pop("seen_zero", None)
            self._save()
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
            elif (
                current is not None
                and current == restore["lock_minutes"]
                and _own_put_back(restore.get(LOCK_PUT_BACK_AT))
            ):
                # Hearth's own put-back, cut off (a reload, a restart) or failed after the write went out: the limit
                # reads what Hearth itself wrote, not a parent's change. The devices aren't locked any more: still
                # wanted, they're locked again (the kept limit stays), else let go of as usual
                held.items.discard(DEVICES)
                restore.pop(LOCK_PUT_BACK_AT, None)
                restore.pop("lock_seen_zero", None)
                self._save()
                return
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
            # The bonus the devices showed at the hold's start has Hearth's own mirrored bonus in it already: only
            # what Hearth mirrors after that start (its own, as first seen under this hold) is Hearth's on top
            if "lock_own" not in restore:
                restore["lock_own"] = {str(k): v for k, v in (own_bonus or {}).items()}
                self._save()
            own_at_start = restore["lock_own"]
            for device in fl.devices(self.hass, str(child)):
                watch.add(device.entity_id)
                device_id = str(device.attributes.get("device_id"))
                bonus = _number(device.attributes.get("bonus_minutes")) or 0
                own = (own_bonus or {}).get(device_id, 0)
                own_since = max(0, own - own_at_start.get(device_id, own))
                if bonus > (base.get(device_id) or 0) + own_since:
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
            # Only a pause Hearth has once seen intact can later be "changed by a parent" (as seen_zero for a
            # Switch, lock_seen_zero for the daily limit). Google takes some apps' 1-minute limit (the call
            # succeeds) and never shows it: that pause didn't take, nobody changed it
            intact = set(restore.get(PAUSES_INTACT) or ())
            seen = set(intact)
            never: set[str] = set()
            called = self._quiet_until.get(e.key)
            # Family Link's lists have had the time to show Hearth's last call (not known after a restart: long ago)
            shown = not quiet and (
                called is None or dt_util.utcnow() >= called - QUIET_AFTER_CALL + PAUSE_SHOWS_WITHIN
            )
            for state in self.hass.states.async_all("sensor"):
                paused = state.attributes.get("paused_apps")
                if str(state.attributes.get("child_id")) != str(child) or not isinstance(paused, list):
                    continue
                watch.add(state.entity_id)
                for app in paused:
                    if not isinstance(app, dict) or app.get("package") not in packages:
                        continue
                    if app.get("pause_intact") is True:
                        seen.add(app["package"])
                    elif app.get("pause_intact") is False:
                        if app["package"] in intact:
                            grant(g.APP, app["package"], g.APP_CHANGED)
                        elif shown:
                            never.add(app["package"])
            self._pauses_not_taken(e, held, seen, never - seen)

    def _pauses_not_taken(self, e: Enforcer, held: Held, intact: set[str], never: set[str]) -> None:
        """Keeps which app pauses Family Link has shown intact ([intact]) and handles those it never showed ([never]):
        said once as an error (the kid's Family Link line, the action log), and paused again after RETRY, then after
        twice as long each time (up to PAUSE_RETRY_MAX). Until then the app stays as held; for the next try it becomes
        possibly held, so the hold pauses it again and letting go still resumes it."""
        restore = held.restore
        was = (restore.get(PAUSES_INTACT) or [], restore.get(PAUSES_NOT_TAKEN) or {})
        # Of what's held still (an app waiting for its next try is possibly held)
        holding = _holding(held)
        intact = intact & holding
        records = {p: r for p, r in was[1].items() if p in holding and p not in intact}
        now = dt_util.utcnow()
        new: set[str] = set()
        again: set[str] = set()
        for package in sorted(never):
            record = records.get(package)
            if record is None:
                records[package] = {"tries": 1, "at": now.isoformat()}
                new.add(package)
                continue
            tries = max(1, int(record.get("tries") or 1))
            wait = min(RETRY * 2 ** min(tries - 1, 8), PAUSE_RETRY_MAX)
            if (at := _utc(record.get("at"))) is None or now - at >= wait:
                records[package] = {"tries": tries + 1, "at": now.isoformat()}
                again.add(package)
        if again:
            held.items -= again
            _maybe_paused(held, again)
        if (sorted(intact), records) != (sorted(was[0]), was[1]):
            restore[PAUSES_INTACT] = sorted(intact)
            restore[PAUSES_NOT_TAKEN] = records
            for key in (PAUSES_INTACT, PAUSES_NOT_TAKEN):
                if not restore[key]:
                    del restore[key]
            self._save()
        if records:
            names = sorted(records)
            text = f"{PAUSE_NOT_TAKEN} of {', '.join(names[:3])}" + (f" and {len(names) - 3} more" if len(names) > 3 else "")
            # A failed call's own error stays (it's being retried)
            if held.failed_at is None:
                held.error = f"{text}; Hearth tries again"[:200]
            if new:
                _LOGGER.warning("Family Link never showed Hearth's pause of %s for %s", sorted(new), e.person)
                self.note(e.key, not_taken=sorted(new), error=held.error)
                if self.activity is not None:
                    self.activity.hold(False, e.person, new, "pause_not_taken", e.kind)
        elif held.failed_at is None and (held.error or "").startswith(PAUSE_NOT_TAKEN):
            held.error = None

    def fs_mine(self, e: Enforcer, platform: str) -> dict[str, Any]:
        """What Hearth itself asked of a Family Safety platform of the enforcer's: whether it holds it, when its lock
        ends (None: not known, a lock from before Hearth kept it) and when the extra time it last gave there today
        ends."""
        held = self.held.get(e.key)
        # A lock by whole hours Hearth ended itself on time is over, as one with an end would be
        holds = bool(held and platform in held.items and platform not in (held.restore.get(FS_LOCK_ENDED) or {}))
        sent = (held.restore.get("fs_lock_until") or {}).get(platform) if held else None
        bonus = self.fs_bonus_until(e.person, platform) if self.fs_bonus_until is not None else None
        bonus_ends = self.fs_bonus_ends(e.person, platform) if self.fs_bonus_ends is not None else None
        # A lock call under way or that failed (its end), and an unlock of Hearth's started lately
        locking = _utc((held.restore.get(FS_LOCKING) or {}).get(platform)) if held else None
        unlocking = bool(held) and _own_put_back((held.restore.get(FS_UNLOCKING) or {}).get(platform))
        return {
            "held": holds, "lock_until": _utc(sent) if holds else None, "bonus_until": bonus,
            "bonus_ends": bonus_ends, "locking_until": locking, "unlocking": unlocking,
        }

    def _fs_own_unlock(self, held: Held, platform: str, state: dict[str, Any]) -> bool:
        """Hearth's own unlock of [platform], cut off or failed after it went out (FS_UNLOCKING, within
        OWN_PUT_BACK_WITHIN), with nothing locked there now: not a parent's unlock. The platform isn't held any more
        (locked again if still wanted, else let go of as usual), as for Family Link's put-back (_own_put_back)."""
        if not _own_put_back((held.restore.get(FS_UNLOCKING) or {}).get(platform)):
            return False
        if state.get("override") in (FS_BLOCK_UNTIL, FS_ALLOW_UNTIL) or state.get("hold") not in (
            FS_HOLD_NONE, FS_HOLD_PARENT
        ):
            return False
        held.items.discard(platform)
        for key in ("fs_lock_until", FS_UNLOCK_AT, FS_LOCK_ENDED, FS_LOCKING, FS_UNLOCKING):
            _restore_map(held, key).pop(platform, None)
        _tidy_restore(held)
        self._save()
        _LOGGER.info("Family Safety %s: Hearth's own unlock went through after all", platform)
        return True

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
                # Kept before the call, as any unlock of Hearth's (_platform): one that fails after it went out
                # leaves nothing locked, which is Hearth's own unlock, never a parent's
                _restore_map(held, FS_UNLOCKING)[platform] = now.isoformat()
                self._save()
                try:
                    try:
                        await self._fs_call("unlock_platform", {**target, "platform": platform}, "lock_ended")
                    except (vol.Invalid, ServiceValidationError):
                        await self._fs_call(
                            "unlock_platform", {"account_id": self._account_id(enforcer.entity_id), "platform": platform},
                            "lock_ended",
                        )
                except Exception as err:  # noqa: BLE001 - tried again next minute, until the lock's own end
                    _LOGGER.warning("Hearth couldn't end its %s lock for %s on time: %s", platform, enforcer.person, err)
                    if ends is None or now >= ends:
                        due.pop(platform, None)
                        changed = True
                    continue
                finally:
                    self._busy.discard(key)
                    # What changes now is Hearth's own call showing (as after any call of the enforcement's)
                    self._quiet_until[key] = dt_util.utcnow() + QUIET_AFTER_CALL
                _restore_map(held, FS_UNLOCKING).pop(platform, None)
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
    for key in ("fs_lock_until", FS_UNLOCK_AT, FS_LOCK_ENDED, FS_LOCKING, FS_UNLOCKING):
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
      isn't shown after Family Safety restarts), or ending when a lock call of Hearth's that failed or is under way
      asked (locking_until): ours; any other lock: parent;
    - extra time ending when the extra time Hearth gave there does: bonus_ours; any other: parent;
    - nothing in force while Hearth's lock should be (its end not passed): parent, override none (a parent unlocked
      it), unless Hearth's own extra time replaced that lock today or Hearth itself started unlocking it lately
      (unlocking: none) or Hearth doesn't know when its lock ends (None: can't tell);
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
    # A lock call of Hearth's under way or that failed: a lock in force ending when it asked is Hearth's
    locking: datetime | None = mine.get("locking_until")
    if not known:
        hold = None
    elif override == FS_BLOCK_UNTIL:
        own = lock_live and (until is None or lock_until is None or _close(until, lock_until))
        own = own or (locking is not None and (until is None or _close(until, locking)))
        hold = FS_HOLD_OURS if own else FS_HOLD_PARENT
    elif override == FS_ALLOW_UNTIL:
        own = bonus_until is not None and (_close(until, bonus_until) or (until is None and bonus_until > now))
        # Any extra time of Hearth's today, not only the latest (an approved request's next to a mirrored bonus)
        own = own or any(_close(until, end) for end in mine.get("bonus_ends") or ())
        hold = FS_HOLD_BONUS_OURS if own else FS_HOLD_PARENT
    elif lock_live and bonus_until is not None and bonus_until > now - FS_OWN_TOLERANCE:
        hold = FS_HOLD_NONE  # Hearth's own extra time (still running) replaced its lock
    elif lock_live and mine.get("unlocking"):
        hold = FS_HOLD_NONE  # Hearth's own unlock, cut off or failed after it went out
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
        return {"reason": "bonus time given in the Family Safety app", "until": until, "end_with": g.END_CANCEL_BONUS}
    if override == "none":  # null is unreadable: nothing said
        return {"reason": "unlocked in the Family Safety app", "until": None, "end_with": g.END_RELOCK}
    return None


def _clock(value: Any) -> str | None:
    """A time entity's state as HH:MM:SS, or None when it's not a time or bedtime is off (00:00)."""
    if not isinstance(value, str) or len(value) < 5 or not (value[:2].isascii() and value[:2].isdigit()):
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
    # Family Link apps whose pause call failed part-way, or never showed: they may be paused all the same
    started |= set(held.restore.get(MAYBE_PAUSED) or ())
    # Family Safety platforms whose lock call failed or was cut off: they may be locked all the same
    started |= set(held.restore.get(FS_LOCKING) or ())
    # Family Safety apps whose pause or resume call failed or was cut off: they may be paused all the same
    started |= set(held.restore.get(FS_MAYBE_PAUSED) or ())
    return held.items | started


def _fs_maybe_paused(held: Held, apps: set[str], add: bool = True) -> None:
    """Family Safety apps that may be paused without Hearth holding them for sure (held.restore, kept over a
    restart): added before a pause or resume call, taken out when it went through or was refused before it went out."""
    was = set(held.restore.get(FS_MAYBE_PAUSED) or ())
    now = was | apps if add else was - apps
    if now:
        held.restore[FS_MAYBE_PAUSED] = sorted(now)
    else:
        held.restore.pop(FS_MAYBE_PAUSED, None)
        held.restore.pop(FS_UNSURE_AT, None)


def refused_before_sent(err: BaseException) -> bool:
    """A call refused before it went out (its schema, a validation, no such action): surely not applied. Any other
    error, and a call cut off (CancelledError), may have been applied all the same."""
    return isinstance(err, (vol.Invalid, ServiceValidationError, ServiceNotFound))


def _maybe_paused(held: Held, packages: set[str], add: bool = True) -> None:
    """Family Link apps that may be paused without Hearth holding them for sure (held.restore, kept over a restart):
    added before a pause call, taken out when a pause or a resume of them went through."""
    was = set(held.restore.get(MAYBE_PAUSED) or ())
    now = was | packages if add else was - packages
    if now:
        held.restore[MAYBE_PAUSED] = sorted(now)
    else:
        held.restore.pop(MAYBE_PAUSED, None)


def _resume_sure(held: Held, packages: set[str]) -> None:
    """A pause or resume of [packages] went through: they're no longer left over from a resume that failed."""
    unsure = set(held.restore.get(RESUME_UNSURE) or ()) - packages
    if unsure:
        held.restore[RESUME_UNSURE] = sorted(unsure)
    else:
        held.restore.pop(RESUME_UNSURE, None)


def _own_put_back(at: Any) -> bool:
    """Hearth started putting a limit back at [at] and it's recent enough for the limit's reading to be that write."""
    when = _utc(at)
    return when is not None and timedelta(0) <= dt_util.utcnow() - when < OWN_PUT_BACK_WITHIN


def _forget_pauses(held: Held, packages: set[str]) -> None:
    """Apps let go: whether their pause was seen intact, and whether it never took, is over with the pause."""
    intact = set(held.restore.get(PAUSES_INTACT) or ()) - packages
    if intact:
        held.restore[PAUSES_INTACT] = sorted(intact)
    else:
        held.restore.pop(PAUSES_INTACT, None)
    not_taken = {p: r for p, r in (held.restore.get(PAUSES_NOT_TAKEN) or {}).items() if p not in packages}
    if not_taken:
        held.restore[PAUSES_NOT_TAKEN] = not_taken
    else:
        held.restore.pop(PAUSES_NOT_TAKEN, None)


def _not_loaded_yet(hass: HomeAssistant, err: Exception, entity_id: str | None, starting: bool) -> bool:
    """Whether a failed call failed only because the parental control's integration hasn't loaded yet (just after
    Home Assistant starts): its action isn't registered, or ([starting]) its entity has no state yet."""
    if isinstance(err, ServiceNotFound):
        return True
    if not starting:
        return False
    state = hass.states.get(entity_id) if entity_id else None
    return state is None or state.state in ("unavailable", "unknown")


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


def _ended_locks(held: Held, now: datetime | None = None) -> set[str]:
    """Family Safety platforms Hearth locked whose lock is over (its end passed, or Hearth ended it at midnight), and
    Family Link's device lock of a day that's over: it's that weekday's daily limit at 0, so on the next day the
    devices are open again (a hold still wanted past midnight, Sleep, is made again on the new weekday)."""
    now = now or dt_util.utcnow()
    ended = set((held.restore.get(FS_LOCK_ENDED) or {}).keys())
    day = held.restore.get("lock_day")
    if DEVICES in held.items and day and day != dt_util.as_local(now).date().isoformat():
        ended.add(DEVICES)
    for platform, at in (held.restore.get("fs_lock_until") or {}).items():
        if (when := _utc(at)) is not None and when <= now:
            ended.add(platform)
    return ended & held.items


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


def fs_applications(hass: HomeAssistant, entity_id: str) -> list[Any]:
    """The Family Safety child's Applications sensors (an applications list among their attributes): on the device of
    [entity_id], or naming its account (user_id)."""
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id) if "." in entity_id else None
    device = entry.device_id if entry is not None else None
    account = fs_account_of(hass, entity_id)
    if device is None and account is None:
        return []
    found = []
    for state in hass.states.async_all("sensor"):
        if not isinstance(state.attributes.get("applications"), list):
            continue
        other = registry.async_get(state.entity_id)
        if (account is not None and str(state.attributes.get("user_id")) == account) or (
            device is not None and other is not None and other.platform == FS_DOMAIN and other.device_id == device
        ):
            found.append(state)
    return sorted(found, key=lambda s: s.entity_id)


def fs_row_app(row: Any) -> str | None:
    """The app id of a paused_apps row (app_id; an older Family Safety's package)."""
    if not isinstance(row, dict):
        return None
    app = row.get("app_id") or row.get("package")
    return app if isinstance(app, str) and app else None


def fs_pause_records(hass: HomeAssistant, entity_id: str) -> dict[str, str] | None:
    """Family Safety's own record of the apps its pause_app paused for the child (paused_apps of their Applications
    sensors): app id -> "ours" (still blocked by the pause) or "parent" (unblocked since). None when that can't be
    told: no Applications sensor, a list cut short (truncated), or a Family Safety that keeps no such record."""
    states = fs_applications(hass, entity_id)
    if not states:
        return None
    found: dict[str, str] = {}
    for state in states:
        rows = state.attributes.get("paused_apps")
        if state.attributes.get("truncated") or not isinstance(rows, list):
            return None
        for row in rows:
            if (app := fs_row_app(row)) is not None:
                found[app] = str(row.get("paused") or FS_HOLD_OURS)
    return found


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
