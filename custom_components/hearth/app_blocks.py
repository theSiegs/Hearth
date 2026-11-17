"""App blocks: Hearth's own blocks of a kid's Android apps, through Family Link (docs/home-assistant-integration.md,
Blocked apps).

Every kid control goes through Hearth: an adult blocks an app with hearth.block_app (or on Hearth's page), never with
familylink.block_app directly, so Hearth's pauses, its schedule and its blocks stay in step.

- hearth.block_app / hearth.unblock_app: an adult's standing block of Android apps (package names) for some kids (all
  kids by default). Kept here until an adult unblocks it.
- The household rule "Block browsers Hearth doesn't support" (option block_unsupported_browsers, off by default):
  every browser Hearth finds on a kid's Android devices (a known browser's package, or an app Hearth's app categories
  name a browser) is blocked, but the ones Hearth supports (SUPPORTED_BROWSERS: the browsers whose sites Hearth's
  controls actually filter). The rule also blocks OTHER_APP_STORES: stores that install apps without Family Link's
  approval (the Galaxy Store). An app an adult unblocks stays unblocked (exempt) until an adult blocks it again.

What Hearth blocked itself is kept (applied), so:
- Hearth only ever unblocks an app it blocked: an app a parent blocked in the Family Link app before Hearth wanted it
  stays the parent's (shown as such), and unblocking it in Hearth leaves it blocked.
- A block Hearth wants for an app that isn't installed waits, and is applied when the app shows up in Family Link's app
  lists. One that left the device and comes back unblocked (installed again) is applied again.
- A block Family Link confirmed (listed blocked) that later shows unblocked while the app stays installed was taken
  back by a parent in the Family Link app: Hearth records it (parent_unblocked, shown on its page) and doesn't block it
  again, until an adult blocks the app again in Hearth.
- A block call Family Link takes but never lists is tried MAX_TRIES times (about 10 minutes), then Hearth stops and
  the card says "Family Link didn't block <app>". hearth_app_blocked fires once, when Family Link lists it blocked.
- Only what Family Link lists as blocked (Hearth's confirmed blocks and a parent's) is left out of Hearth's pauses; a
  block Hearth wants that isn't confirmed stays subject to them, so the app is still held meanwhile.
- A browser added to SUPPORTED_BROWSERS later (or the rule turned off) is unblocked, only where Hearth blocked it.

A blocked app is never paused or resumed by Hearth's holds (enforce.py: a budget, a pause, School time, the schedule):
Family Link's resume_app skips a blocked app and keeps its saved setting, and Hearth leaves its own record of the pause
as it was until the app is unblocked. An allow (hearth.allow) doesn't lift a block; hearth.explain names it
(blocked_by kind blocked_app).

Windows and Xbox need no block: Family Safety's web filter (Content filters > Web and search, on for the kid) lets
Windows run only Microsoft Edge, and the Xbox has only Edge. Hearth's page shows, per kid, whether that web filter is
on (web_filter).
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import logging
import re
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_ROLES, SIGNAL_PEOPLE
from .entry_tasks import entry_task
from . import family_link as fl
from .activity import call_service

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
# Options: the household rule (off unless chosen)
CONF_BLOCK_UNSUPPORTED_BROWSERS = "block_unsupported_browsers"

# Why an app is blocked: an adult's block, or the rule (a browser Hearth doesn't support, another app store)
ADULT = "adult"
BROWSER = "browser"
APP_STORE = "app_store"
# Where a wanted block stands
BLOCKED = "blocked"  # blocked by Hearth in Family Link
PARENT = "parent"  # already blocked in Family Link by a parent: theirs, Hearth leaves it alone
WAITING = "not_installed"  # not on the kid's devices: blocked when it shows up
PENDING = "pending"  # a call is under way or due (or failed: see error)

# The browsers Hearth supports: the ones whose sites Hearth's controls actually filter. One list for every platform;
# the rule never blocks these, and unblocks one added here later (where Hearth blocked it).
# - Chrome on Android: Family Link's site filters (and the blocklist Hearth syncs into them, sites.py) apply to the
#   kid's supervised Google account in Chrome only (familylink.block_sites: "Only Chrome is filtered").
# - Microsoft Edge on Windows and Xbox: Family Safety's web filter applies in Edge, and with it on, Windows blocks
#   every other browser and the Xbox has only Edge.
# - NOT Edge on Android: Family Safety's filter there lives inside Edge and applies only while the kid is signed in to
#   Edge with their Microsoft family account; nothing on Android makes them sign in (no OS-level policy as on Windows),
#   and Family Link's site filters don't reach Edge. Signed out, it is an unfiltered browser, so it isn't supported.
SUPPORTED_BROWSERS: tuple[dict[str, Any], ...] = (
    {"name": "Chrome", "platform": "Android", "package": "com.android.chrome", "filtered_by": "Family Link"},
    {"name": "Microsoft Edge", "platform": "Windows", "package": None, "filtered_by": "Family Safety"},
    {"name": "Microsoft Edge", "platform": "Xbox", "package": None, "filtered_by": "Family Safety"},
)
SUPPORTED_ANDROID = frozenset(b["package"] for b in SUPPORTED_BROWSERS if b["platform"] == "Android" and b["package"])

# Android browsers by package (the rule blocks the ones not supported)
BROWSERS: dict[str, str] = {
    "com.android.chrome": "Chrome",
    "com.chrome.beta": "Chrome Beta",
    "com.chrome.dev": "Chrome Dev",
    "com.chrome.canary": "Chrome Canary",
    "com.microsoft.emmx": "Microsoft Edge",
    "com.microsoft.emmx.beta": "Microsoft Edge Beta",
    "com.microsoft.emmx.dev": "Microsoft Edge Dev",
    "com.microsoft.emmx.canary": "Microsoft Edge Canary",
    "com.sec.android.app.sbrowser": "Samsung Internet",
    "com.sec.android.app.sbrowser.beta": "Samsung Internet Beta",
    "org.mozilla.firefox": "Firefox",
    "org.mozilla.firefox_beta": "Firefox Beta",
    "org.mozilla.fenix": "Firefox Nightly",
    "org.mozilla.focus": "Firefox Focus",
    "org.mozilla.klar": "Firefox Klar",
    "com.opera.browser": "Opera",
    "com.opera.browser.beta": "Opera Beta",
    "com.opera.mini.native": "Opera Mini",
    "com.opera.mini.native.beta": "Opera Mini Beta",
    "com.opera.gx": "Opera GX",
    "com.brave.browser": "Brave",
    "com.brave.browser_beta": "Brave Beta",
    "com.brave.browser_nightly": "Brave Nightly",
    "com.duckduckgo.mobile.android": "DuckDuckGo",
    "com.vivaldi.browser": "Vivaldi",
    "com.vivaldi.browser.snapshot": "Vivaldi Snapshot",
    "org.torproject.torbrowser": "Tor Browser",
    "org.torproject.torbrowser_alpha": "Tor Browser Alpha",
    "com.kiwibrowser.browser": "Kiwi Browser",
    "com.UCMobile.intl": "UC Browser",
    "com.uc.browser.en": "UC Browser Mini",
    "com.yandex.browser": "Yandex Browser",
    "com.yandex.browser.lite": "Yandex Browser Lite",
    "com.cloudmosa.puffin": "Puffin",
    "com.cloudmosa.puffinFree": "Puffin",
    "com.cloudmosa.puffinIncognito": "Puffin Incognito",
    "mobi.mgeek.TunnyBrowser": "Dolphin",
    "com.dolphin.browser.express.web": "Dolphin Express",
    "com.mi.globalbrowser": "Mi Browser",
    "com.mi.globalbrowser.mini": "Mi Browser Mini",
    "com.ecosia.android": "Ecosia",
    "com.amazon.cloud9": "Silk",
    "com.aloha.browser": "Aloha",
}
# App stores that install apps without Family Link's approval (Google Play asks a parent; these don't)
OTHER_APP_STORES: dict[str, str] = {
    "com.sec.android.app.samsungapps": "Galaxy Store",
    "com.amazon.venezia": "Amazon Appstore",
    "cm.aptoide.pt": "Aptoide",
    "com.apkpure.aegon": "APKPure",
    "org.fdroid.fdroid": "F-Droid",
    "com.huawei.appmarket": "AppGallery",
    "com.uptodown": "Uptodown",
    "com.xiaomi.mipicks": "GetApps",
}
# An app Hearth's categories know by a name like this (and as none of the ten kinds) is a browser
_BROWSER_NAME = re.compile(r"\b(web )?browser\b", re.IGNORECASE)
_NOT_A_WEB_BROWSER = re.compile(r"\bfiles?\b|photo|music|video|gallery|document|\bpdf\b", re.IGNORECASE)

# A call's change shows in Family Link's lists within a poll or two: no call for the same app again before this
QUIET = timedelta(minutes=3)
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
# Block calls Family Link took without listing the app blocked: after this many (about 10 minutes, QUIET apart) Hearth
# stops trying and the card says "Family Link didn't block <app>"
MAX_TRIES = 3
MAX_APPS = 50


def android_package(app: str) -> bool:
    """An Android package name (com.example.app): the only kind of app a block takes for now."""
    return bool(re.fullmatch(r"[A-Za-z][\w]*(\.[A-Za-z_][\w]*)+", app)) and not app.startswith(("x:", "appx:", "win32:"))


def never_blocked(package: str) -> bool:
    """What holds the rest (Hearth, Family Link, Google Play services, Settings, the phone and messages): never
    blocked, by an adult or the rule."""
    from .enforce import NEVER_PAUSED, essential

    return package in NEVER_PAUSED or essential(package)


class AppBlocks:
    """The household's blocks, brought in step with Family Link (one run at a time)."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.app_blocks.{entry_id}")
        # An adult's blocks: person -> package -> {"at", "name"?}
        self.adult: dict[str, dict[str, dict[str, Any]]] = {}
        # Apps an adult unblocked that the rule would block: person -> packages
        self.exempt: dict[str, set[str]] = {}
        # What Hearth blocked in Family Link itself: person -> package -> {"at", "why", "confirmed"?, "gone"?}
        # (confirmed: Family Link listed it blocked since; gone: it left the device since, so unblocked on its return
        # is a reinstall, not a parent's unblock)
        self.applied: dict[str, dict[str, dict[str, Any]]] = {}
        # Blocks of Hearth's a parent took back in the Family Link app: person -> package -> {"at"}. Hearth leaves
        # them unblocked until an adult blocks the app again in Hearth
        self.parent_unblocked: dict[str, dict[str, dict[str, Any]]] = {}
        # Block calls Family Link hasn't confirmed yet, by (person, package); at MAX_TRIES Hearth stops and says so
        self._tries: dict[tuple[str, str], int] = {}
        # When Hearth last called for an app, and the last error: (person, package) -> ...
        self._called: dict[tuple[str, str], datetime] = {}
        self._errors: dict[tuple[str, str], tuple[str, datetime]] = {}
        self._task: asyncio.Task | None = None
        self._again = False
        self._closed = False

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.adult = {
            p: {pkg: dict(v) for pkg, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("adult") or {}).items()
            if isinstance(apps, dict)
        }
        self.exempt = {p: set(apps) for p, apps in (stored.get("exempt") or {}).items() if isinstance(apps, list)}
        self.applied = {
            p: {pkg: dict(v) for pkg, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("applied") or {}).items()
            if isinstance(apps, dict)
        }
        self.parent_unblocked = {
            p: {pkg: dict(v) for pkg, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("parent_unblocked") or {}).items()
            if isinstance(apps, dict)
        }

    def _data(self) -> dict[str, Any]:
        return {
            "adult": {p: apps for p, apps in self.adult.items() if apps},
            "exempt": {p: sorted(apps) for p, apps in self.exempt.items() if apps},
            "applied": {p: apps for p, apps in self.applied.items() if apps},
            "parent_unblocked": {p: apps for p, apps in self.parent_unblocked.items() if apps},
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 1)

    async def async_flush(self) -> None:
        self._closed = True
        task = self._task
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        await self._store.async_save(self._data())

    # Who and what

    @property
    def rule_on(self) -> bool:
        return bool(self.household.options.get(CONF_BLOCK_UNSUPPORTED_BROWSERS))

    def kids(self) -> list[str]:
        """The household's people who aren't adults."""
        roles = self.household.options.get(CONF_ROLES, {})
        return [p for p in self.household.people() if roles.get(p) != "adult"]

    def target_of(self, person: str) -> tuple[str, str] | None:
        """(the Family Link entity Hearth calls with, the child's id) of a person, None without Family Link."""
        from .enforce import FAMILY_LINK, enforcers_from_options

        enforcer = next(
            (e for e in enforcers_from_options(self.household.options) if e.kind == FAMILY_LINK and e.person == person),
            None,
        )
        if enforcer is None:
            return None
        child = fl.child_of(self.hass, enforcer.entity_id)
        return (enforcer.entity_id, child) if child else None

    def is_browser(self, package: str) -> bool:
        """A known browser's package, or an app Hearth's categories know as a browser (none of the ten kinds, a
        browser's name)."""
        if package in BROWSERS:
            return True
        try:
            hit = self.household.categories_book.lookup(package)
        except Exception:  # noqa: BLE001 - the categories are a hint only
            return False
        name = getattr(hit, "name", None) if hit is not None else None
        return (
            hit is not None
            and hit.category is None
            and isinstance(name, str)
            and bool(_BROWSER_NAME.search(name))
            and not _NOT_A_WEB_BROWSER.search(name)
        )

    def rule_reason(self, package: str) -> str | None:
        """Why the rule blocks [package] (browser, app_store), None when it doesn't."""
        if never_blocked(package) or package in SUPPORTED_ANDROID:
            return None
        if package in OTHER_APP_STORES:
            return APP_STORE
        if self.is_browser(package):
            return BROWSER
        return None

    def wanted(self, person: str, listed: set[str] | None = None) -> dict[str, set[str]]:
        """The apps Hearth blocks for [person] now, with why: an adult's blocks, and (the rule on) the browsers and
        stores among the apps Family Link lists for them ([listed]) or Hearth blocked for the rule before."""
        # A block a parent took back in the Family Link app stays theirs (until an adult blocks it again in Hearth)
        taken_back = set(self.parent_unblocked.get(person, {}))
        found: dict[str, set[str]] = {
            p: {ADULT} for p in self.adult.get(person, {}) if not never_blocked(p) and p not in taken_back
        }
        if self.rule_on:
            if listed is None:
                target = self.target_of(person)
                listed = fl.app_lists(self.hass, target[1])[0] if target else set()
            exempt = self.exempt.get(person, set()) | taken_back
            for package in (listed | set(self.applied.get(person, {}))) - exempt:
                if (reason := self.rule_reason(package)) is not None:
                    found.setdefault(package, set()).add(reason)
        return found

    def blocked_packages(self, person: str) -> set[str]:
        """What is blocked for [person] in Family Link now (Hearth's confirmed blocks and a parent's): never paused or
        resumed by Hearth's other holds (enforce.py). A block Hearth wants but Family Link doesn't list yet stays
        subject to pauses, so an app it failed to block is still held."""
        target = self.target_of(person)
        if target is None:
            return set()
        blocked = fl.app_lists(self.hass, target[1])[1]
        return set(blocked or ())

    def why_blocked(self, person: str, package: str) -> set[str]:
        return self.wanted(person).get(package, set())

    # An adult's blocks

    @callback
    def block(self, people: list[str], packages: list[str]) -> dict[str, list[str]]:
        now = dt_util.utcnow().isoformat()
        done: dict[str, list[str]] = {}
        for person in people:
            mine = self.adult.setdefault(person, {})
            for package in packages:
                mine.setdefault(package, {"at": now})
                self.exempt.get(person, set()).discard(package)
                # An adult blocking it again in Hearth takes back a parent's unblock in the Family Link app
                self.parent_unblocked.get(person, {}).pop(package, None)
                self._tries.pop((person, package), None)
                # A new decision: call now, not after the quiet of an earlier call
                self._called.pop((person, package), None)
                self._errors.pop((person, package), None)
            done[person] = sorted(packages)
        self._save()
        self.sync()
        return done

    @callback
    def unblock(self, people: list[str], packages: list[str]) -> dict[str, list[str]]:
        done: dict[str, list[str]] = {}
        for person in people:
            for package in packages:
                self.adult.get(person, {}).pop(package, None)
                if self.rule_on and self.rule_reason(package) is not None:
                    # The rule would block it again: an adult said no
                    self.exempt.setdefault(person, set()).add(package)
                self._called.pop((person, package), None)
                self._errors.pop((person, package), None)
            done[person] = sorted(packages)
        self._save()
        self.sync()
        return done

    # In step with Family Link

    def _plan(self) -> list[tuple[str, str, str, bool]]:
        """The calls due now: (person, entity, package, block)."""
        now = dt_util.utcnow()
        calls: list[tuple[str, str, str, bool]] = []
        dirty = False
        for person in sorted(set(self.kids()) | set(self.applied) | set(self.adult)):
            target = self.target_of(person)
            if target is None:
                continue
            entity_id, child = target
            listed, blocked = fl.app_lists(self.hass, child)
            applied = self.applied.setdefault(person, {})
            if blocked is not None:
                dirty |= self._confirm(person, applied, listed, blocked)
            want = self.wanted(person, listed) if person in self.kids() else {}
            for package in sorted(want):
                if blocked is None or package in blocked or package not in listed:
                    # Blocked already (Hearth's or a parent's), not installed (waits), or it can't be told yet
                    continue
                if self._tries.get((person, package), 0) >= MAX_TRIES:
                    # Family Link took the call but never listed it blocked: Hearth stops and says so (views)
                    continue
                if self._due(person, package, now):
                    calls.append((person, entity_id, package, True))
            for package in sorted(set(applied) - set(want)):
                if blocked is None:
                    continue
                if package not in blocked:
                    # Unblocked already (gone, or unblocked in the Family Link app): nothing of Hearth's left
                    applied.pop(package, None)
                    dirty = True
                elif self._due(person, package, now):
                    calls.append((person, entity_id, package, False))
        if dirty:
            self._save()
        return calls

    def _confirm(self, person: str, applied: dict[str, dict[str, Any]], listed: set[str], blocked: set[str]) -> bool:
        """What Family Link lists now, against what Hearth blocked: a block it lists is confirmed (its event fires
        once); one that left the device is marked gone (a reinstall comes back unblocked, and is blocked again); one
        confirmed, still installed and now unblocked was taken back by a parent in the Family Link app: recorded,
        and Hearth doesn't block it again. Says whether anything changed."""
        changed = False
        for package, record in list(applied.items()):
            if package in blocked:
                self._tries.pop((person, package), None)
                if not record.get("confirmed") or record.get("gone"):
                    record["confirmed"] = True
                    _LOGGER.debug("block %s for %s: Family Link lists it blocked", package, person)
                    record.pop("gone", None)
                    self.hass.bus.async_fire("hearth_app_blocked", {"person": person, "app": package})
                    changed = True
            elif package not in listed:
                if not record.get("gone"):
                    record["gone"] = True
                    changed = True
            elif record.get("confirmed") and not record.get("gone"):
                applied.pop(package)
                self.parent_unblocked.setdefault(person, {})[package] = {"at": dt_util.utcnow().isoformat()}
                _LOGGER.info("%s: %s was unblocked in the Family Link app; Hearth leaves it unblocked", person, package)
                self.hass.bus.async_fire("hearth_app_unblocked_by_parent", {"person": person, "app": package})
                changed = True
        return changed

    def _due(self, person: str, package: str, now: datetime) -> bool:
        key = (person, package)
        if (error := self._errors.get(key)) is not None and now - error[1] < RETRY:
            return False
        called = self._called.get(key)
        return called is None or now - called >= QUIET

    @callback
    def sync(self) -> None:
        """Brings Family Link in step with the blocks (after each recompute, and after a change here)."""
        if self._closed:
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        calls = self._plan()
        if calls:
            self._task = entry_task(self.hass, self._entry_id, self._async_apply(calls), "hearth app blocks")

    async def _async_apply(self, calls: list[tuple[str, str, str, bool]]) -> None:
        self._again = False
        for person, entity_id, package, block in calls:
            key = (person, package)
            self._called[key] = dt_util.utcnow()
            service = "block_app" if block else "unblock_app"
            try:
                await call_service(self.hass,
                    FL_DOMAIN, service, {"entity_id": entity_id, "package_name": package}, blocking=True,
                    person=person, why=",".join(sorted(self.why_blocked(person, package))) or "unblock",
                )
            except Exception as err:  # noqa: BLE001 - one app failing mustn't stop the others
                _LOGGER.warning("Hearth couldn't %s %s for %s: %s", service.replace("_app", ""), package, person, err)
                self._errors[key] = (str(err)[:200], dt_util.utcnow())
                if block:
                    # It may have gone through all the same (a timeout): kept as Hearth's, unconfirmed, so a block
                    # Family Link lists later is Hearth's to lift, not a parent's
                    self.applied.setdefault(person, {}).setdefault(
                        package, {"at": dt_util.utcnow().isoformat(), "why": sorted(self.why_blocked(person, package))}
                    )
                continue
            self._errors.pop(key, None)
            if block:
                self.applied.setdefault(person, {})[package] = {
                    "at": dt_util.utcnow().isoformat(),
                    "why": sorted(self.why_blocked(person, package)),
                }
                # hearth_app_blocked fires once, when Family Link lists it blocked (_confirm)
                tries = self._tries[key] = self._tries.get(key, 0) + 1
                _LOGGER.debug("block %s for %s: try %s of %s, waiting for Family Link to list it", package, person, tries, MAX_TRIES)
                if tries >= MAX_TRIES:
                    # Shown on the card until Family Link lists it, or an adult blocks it again
                    self._errors[key] = (f"Family Link didn't block {self.name_of(package, person)}", dt_util.utcnow())
            else:
                self.applied.get(person, {}).pop(package, None)
                self.hass.bus.async_fire("hearth_app_unblocked", {"person": person, "app": package})
            self._save()
        if calls:
            self.household.enforcement.refresh_soon(calls[-1][1])
            async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)
        if self._again:
            self._again = False
            self._task = None
            self.sync()

    # Views

    def state_of(self, person: str, package: str, listed: set[str], blocked: set[str] | None) -> str:
        if package in self.applied.get(person, {}) and blocked is not None and package in blocked:
            return BLOCKED
        if blocked is not None and package in blocked:
            return PARENT
        if blocked is not None and package not in listed:
            return WAITING
        return PENDING

    def name_of(self, package: str, person: str | None = None) -> str:
        if package in BROWSERS:
            return BROWSERS[package]
        if package in OTHER_APP_STORES:
            return OTHER_APP_STORES[package]
        return self.household.app_names({package}, person).get(package) or package

    def views(self, person: str) -> list[dict[str, Any]]:
        """A kid's blocks for Hearth's page: [{app, name, why, state, error?}]."""
        target = self.target_of(person)
        listed, blocked = fl.app_lists(self.hass, target[1]) if target else (set(), None)
        out = []
        for package, why in sorted(self.wanted(person, listed if target else None).items()):
            view: dict[str, Any] = {
                "app": package,
                "name": self.name_of(package, person),
                "why": sorted(why),
                "state": self.state_of(person, package, listed, blocked) if target else PENDING,
            }
            if (error := self._errors.get((person, package))) is not None:
                view["error"] = error[0]
            out.append(view)
        return out

    def web_filter(self, person: str) -> dict[str, Any] | None:
        """Whether Family Safety's web filter is on for the kid (Windows runs only Edge then, the Xbox has only
        Edge): {entity_id, on}, on None when its switch isn't found; None when the kid has no Family Safety."""
        from .enforce import FAMILY_SAFETY, enforcers_from_options, fs_account_of

        enforcers = [
            e for e in enforcers_from_options(self.household.options) if e.kind == FAMILY_SAFETY and e.person == person
        ]
        if not enforcers:
            return None
        accounts = {str(a) for e in enforcers if (a := fs_account_of(self.hass, e.entity_id))}
        registry = er.async_get(self.hass)
        for state in self.hass.states.async_all("switch"):
            if str(state.attributes.get("user_id")) not in accounts:
                continue
            entry = registry.async_get(state.entity_id)
            if (entry is not None and entry.unique_id.endswith("_web_filter_switch")) or state.entity_id.endswith(
                "_web_filtering"
            ):
                on = None if state.state in ("unknown", "unavailable") else state.state == "on"
                return {"entity_id": state.entity_id, "on": on}
        return {"entity_id": None, "on": None}

    def page(self) -> dict[str, Any]:
        """For Hearth's page: the rule, the supported browsers, the lists, and each kid's blocks and web filter."""
        return {
            "rule": self.rule_on,
            "supported": [dict(b) for b in SUPPORTED_BROWSERS],
            "browsers": dict(BROWSERS),
            "app_stores": dict(OTHER_APP_STORES),
            "kids": [
                {
                    "person": person,
                    "name": self.household.person_name(person),
                    "family_link": self.target_of(person) is not None,
                    "blocks": self.views(person),
                    "exempt": sorted(self.exempt.get(person, set())),
                    # Blocks of Hearth's a parent took back in the Family Link app (Hearth leaves them unblocked)
                    "parent_unblocked": [
                        {"app": p, "name": self.name_of(p, person), "at": r.get("at")}
                        for p, r in sorted(self.parent_unblocked.get(person, {}).items())
                    ],
                    "web_filter": self.web_filter(person),
                }
                for person in self.kids()
            ],
        }

    def explain(self, person: str, app: str) -> list[dict[str, Any]]:
        """hearth.explain's blocked_by for an app Hearth blocks: [{kind: blocked_app, by, why, until: None}]."""
        why = self.why_blocked(person, app)
        if not why:
            return []
        return [
            {
                "kind": "blocked_app",
                "by": "hearth.block_app" if ADULT in why else CONF_BLOCK_UNSUPPORTED_BROWSERS,
                "app": app,
                "why": sorted(why),
                "until": None,
            }
        ]
