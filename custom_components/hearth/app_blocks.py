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
- The household rule "Block AI companion apps" (option block_ai_companions, on unless an adult turns it off): AI
  companion and character role-play chat apps Hearth knows by package (AI_COMPANIONS, each checked on Google Play) are
  blocked the same way, with the same exemptions. An app that is one only by its name (Family Link's, Hearth's
  catalog's or app categories') is never blocked by the rule: the adults get one notice per app and kid, with a Block
  button (hearth.block_app) and Not now; either way that app and kid aren't asked again (asked, kept). General
  assistants and tools (NOT_AI_COMPANIONS: Gemini, Copilot, ChatGPT, Claude, Perplexity, Meta AI, Grok), messaging and
  school apps get neither. Each rule's blocks are its own: turning one off unblocks only what it blocked.

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
- A browser added to SUPPORTED_BROWSERS later (or a rule turned off) is unblocked, only where Hearth blocked it.
- A Blocked apps list that is missing or cut short (truncated) is unknown, never "nothing is blocked": Hearth then
  blocks and unblocks nothing (_plan), and what is left out of its pauses and resumes is the last whole list
  (last_blocked, kept over a restart) with what the list shows now. With no whole list ever read (blocked_known is
  False), a standing rule's apps don't swap the device lock for app pauses (household.open_apps).

A blocked app is never paused or resumed by Hearth's holds (enforce.py: a budget, a pause, School time, the schedule):
Family Link's resume_app skips a blocked app and keeps its saved setting, and Hearth leaves its own record of the pause
as it was until the app is unblocked. An allow (hearth.allow) doesn't lift a block; hearth.explain names it
(blocked_by kind blocked_app).

Xbox and Windows apps: hearth.block_app takes Family Safety's app ids too (x:..., appx:..., win32:..., as its
Applications sensor lists them), for a kid with a Family Safety enforcer, through Family Safety's block_app and
unblock_app (the account's, every platform's). They're kept the same way, in fs_applied: only Hearth's own blocks
are ever unblocked (one a parent made in the Family Safety app stays theirs), a block waits until the app is in the
Applications list, a list cut short or missing changes nothing, an unconfirmed block is tried MAX_TRIES times, and one
a parent unblocked in the Family Safety app is left unblocked. Family Safety pauses an app (Hearth's holds) by
blocking it and puts back on resume what it was before the pause: so a block or unblock of an app Hearth's pause holds
waits until the app is resumed (a block made under the pause would be undone by the resume, an unblock would lift the
pause). The browser and AI companion rules stay Android's: Family Safety's web filter (Content filters > Web and
search, on for the kid) lets Windows run only Microsoft Edge, and the Xbox has only Edge. Hearth's page shows, per kid,
whether that web filter is on (web_filter).
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

from .attention import ADULTS, NOTICE, Action, Item
from .const import CONF_ROLES, DOMAIN, SIGNAL_PEOPLE
from .entry_tasks import entry_task
from . import family_link as fl
from .activity import call_service

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
# Options: the household rules (browsers: off unless chosen; AI companions: on unless turned off)
CONF_BLOCK_UNSUPPORTED_BROWSERS = "block_unsupported_browsers"
CONF_BLOCK_AI_COMPANIONS = "block_ai_companions"

# Why an app is blocked: an adult's block, or a rule (a browser Hearth doesn't support, another app store; an AI
# companion app)
ADULT = "adult"
BROWSER = "browser"
APP_STORE = "app_store"
AI_COMPANION = "ai_companion"
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
# AI companion and character role-play chat apps by package (each checked on its Google Play page)
AI_COMPANIONS: dict[str, str] = {
    "ai.character.app": "Character AI",
    "com.weaver.app.prod": "Talkie",
    "com.Beauchamp.Messenger.external": "Chai",
    "ai.replika.app": "Replika",
    "ai.nomi.twa": "Nomi",
    "com.kindroid.app": "Kindroid",
    "ai.socialapps.speakmaster": "PolyBuzz",
    "com.aigc.ushow.ichat": "Linky AI",
    "com.xverse.aistory": "Saylo",
    "ai.botify.app": "Botify AI",
    "com.withfeelingai.test": "Paradot",
    "com.ifriend.app": "EVA AI",
    "com.hiwaifu.app": "HiWaifu",
    "com.romanticai.romanticai": "Romantic AI",
    # NextDayAI's, the maker of SpicyChat (which has no Play app of its own)
    "ai.nextday.mobile.android.pixelchat": "PixelChat",
}
# Never blocked by the AI companion rule, whatever their names say: general assistants and tools (a separate
# decision), and Google Chat
NOT_AI_COMPANIONS = frozenset(
    {
        "com.google.android.apps.bard",  # Gemini
        "com.microsoft.copilot",
        "com.microsoft.office.officehubrow",  # Microsoft 365 Copilot
        "com.openai.chatgpt",
        "com.anthropic.claude",
        "ai.perplexity.app.android",
        "com.facebook.stella",  # Meta AI
        "ai.x.grok",
        "com.google.android.apps.dynamite",  # Google Chat
    }
)
# An app named like this may be an AI companion or character role-play chat app: the adults are asked, it isn't
# blocked (conservative all the same: "AI chat" alone is a general assistant's name too, so it isn't enough)
_AI_COMPANION_NAME = re.compile(
    r"\bAI[\s-]+(companions?|girl ?friends?|boy ?friends?|gf|bf|friends?|characters?|role[\s-]?play(ing|s)?|waifus?"
    r"|husbandos?|lovers?|soul ?mates?|crush(es)?)\b"
    r"|\bcharacter[\s.]*ai\b"
    r"|\bchat\s+with\s+(ai\s+)?(characters?|personas?)\b"
    r"|\bvirtual\s+(girl ?friends?|boy ?friends?)\b"
    r"|\b(companion|girlfriend|boyfriend|waifu)\s+(ai|chat\s*bot)\b"
    r"|\brole[\s-]?play\s+(ai|chat|chat\s*bot)s?\b",
    re.IGNORECASE,
)
# Never one, whatever else the name says: assistants and tools, messaging, school and learning
_NOT_AI_COMPANION_NAME = re.compile(
    r"gemini|copilot|chat\s*gpt|\bclaude\b|perplexity|\bmeta ai\b|\bgrok\b|google chat|assistant|messag|whatsapp"
    r"|telegram|\bsignal\b|discord|school|classroom|homework|tutor|study|learn|\bmath|keyboard|translat|language"
    r"|english|\boffice\b",
    re.IGNORECASE,
)
# Hearth's app categories that are never an AI companion app by name (messaging; school and learning)
_NOT_AI_COMPANION_KINDS = frozenset({"messaging", "education"})

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
    """An Android package name (com.example.app), blocked through Family Link."""
    return bool(re.fullmatch(r"[A-Za-z][\w]*(\.[A-Za-z_][\w]*)+", app)) and not app.startswith(("x:", "appx:", "win32:"))


def fs_app_id(app: str) -> bool:
    """A Family Safety app id (x:..., x:windowsplt:..., appx:..., win32:...: an Xbox or Windows app), blocked through
    Family Safety."""
    from .enforce import fs_app

    return fs_app(app) and len(app) <= 256 and not any(c.isspace() for c in app) and app.split(":")[-1] != ""


# Home screens: a blocked one can leave a device with nothing to open apps from
LAUNCHERS = frozenset(
    {
        "com.sec.android.app.launcher",
        "com.google.android.apps.nexuslauncher",
        "com.google.android.launcher",
        "com.google.android.apps.tv.launcherx",
    }
)


def never_blocked(package: str) -> bool:
    """What holds the rest (Hearth, Family Link, Google Play services, Settings, the phone and messages, keyboards,
    the home screen): never blocked, by an adult or the rule."""
    from .enforce import KEYBOARDS, NEVER_PAUSED, essential

    return package in NEVER_PAUSED or package in KEYBOARDS or package in LAUNCHERS or essential(package)


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
        # The same for Xbox and Windows apps Hearth blocked in Family Safety itself
        self.fs_applied: dict[str, dict[str, dict[str, Any]]] = {}
        # Blocks of Hearth's a parent took back in the Family Link app: person -> package -> {"at"}. Hearth leaves
        # them unblocked until an adult blocks the app again in Hearth
        self.parent_unblocked: dict[str, dict[str, dict[str, Any]]] = {}
        # Apps the adults were asked about (one only by its name): person -> package -> {"at", "name"}; never asked again
        self.asked: dict[str, dict[str, dict[str, Any]]] = {}
        # Family Link's Blocked apps list at its last whole read: person -> packages. What blocked_packages goes by
        # while the list is missing or cut short
        self.last_blocked: dict[str, set[str]] = {}
        # Apps whose name was looked at and isn't a companion's, this run: person -> packages (not looked at again)
        self._not_named: dict[str, set[str]] = {}
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
        self.fs_applied = {
            p: {app: dict(v) for app, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("fs_applied") or {}).items()
            if isinstance(apps, dict)
        }
        self.parent_unblocked = {
            p: {pkg: dict(v) for pkg, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("parent_unblocked") or {}).items()
            if isinstance(apps, dict)
        }
        self.asked = {
            p: {pkg: dict(v) for pkg, v in apps.items() if isinstance(v, dict)}
            for p, apps in (stored.get("asked") or {}).items()
            if isinstance(apps, dict)
        }
        self.last_blocked = {
            p: {a for a in apps if isinstance(a, str) and a}
            for p, apps in (stored.get("last_blocked") or {}).items()
            if isinstance(apps, list)
        }

    def _data(self) -> dict[str, Any]:
        return {
            "adult": {p: apps for p, apps in self.adult.items() if apps},
            "exempt": {p: sorted(apps) for p, apps in self.exempt.items() if apps},
            "applied": {p: apps for p, apps in self.applied.items() if apps},
            "fs_applied": {p: apps for p, apps in self.fs_applied.items() if apps},
            "parent_unblocked": {p: apps for p, apps in self.parent_unblocked.items() if apps},
            "asked": {p: apps for p, apps in self.asked.items() if apps},
            # An empty list is a read too ("nothing is blocked" is known)
            "last_blocked": {p: sorted(apps) for p, apps in self.last_blocked.items()},
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
        """The browser rule (off unless chosen)."""
        return bool(self.household.options.get(CONF_BLOCK_UNSUPPORTED_BROWSERS))

    @property
    def companion_rule_on(self) -> bool:
        """The AI companion rule: on for a household that hasn't set it."""
        return bool(self.household.options.get(CONF_BLOCK_AI_COMPANIONS, True))

    def _rule_of(self, reason: str) -> bool:
        """Whether the rule behind [reason] is on."""
        return self.companion_rule_on if reason == AI_COMPANION else self.rule_on

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

    def fs_target_of(self, person: str) -> str | None:
        """The Family Safety entity (or typed-in account id) Hearth calls with for a person, None without Family
        Safety."""
        from .enforce import FAMILY_SAFETY, enforcers_from_options

        return next(
            (
                e.entity_id
                for e in enforcers_from_options(self.household.options)
                if e.kind == FAMILY_SAFETY and e.person == person
            ),
            None,
        )

    def fs_lists(self, person: str) -> tuple[set[str], set[str] | None, dict[str, str]]:
        """The person's Xbox and Windows apps as Family Safety's Applications sensors list them: (installed, blocked,
        names). blocked is None when a list is missing or cut short (unknown, never "nothing is blocked")."""
        from .outside_apps import read_family_safety

        sensors = self.household.outside_apps._fs_applications(person, er.async_get(self.hass))
        if not sensors:
            return set(), None, {}
        installed: set[str] = set()
        blocked: set[str] = set()
        names: dict[str, str] = {}
        for entity_id in sensors:
            state = self.hass.states.get(entity_id)
            lists = read_family_safety(dict(state.attributes)) if state is not None else None
            if lists is None:
                return installed, None, names
            installed |= lists["installed"]
            blocked |= lists["blocked"]
            names.update(lists["names"])
        return installed, blocked, names

    def _fs_held(self, person: str) -> set[str]:
        """The Xbox and Windows apps Hearth's holds pause now (Family Safety blocks them for the pause)."""
        from .enforce import FAMILY_SAFETY

        held = self.household.enforcement.held.get(f"{FAMILY_SAFETY}|{person}")
        return {a for a in held.items if fs_app_id(a)} if held is not None else set()

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

    @staticmethod
    def is_ai_companion(package: str) -> bool:
        """A known AI companion app's package (AI_COMPANIONS): the only kind the rule blocks."""
        return package in AI_COMPANIONS

    def named_ai_companion(self, package: str, name: str | None = None) -> bool:
        """An app that isn't a known one but whose name ([name]: Hearth's catalog's or Family Link's, and Hearth's app
        categories') says it may be an AI companion app: the adults are asked, never blocked by the rule. Never one of
        AI_COMPANIONS (blocked) or NOT_AI_COMPANIONS, an app named like an assistant, a tool, a messaging or school app,
        or one Hearth's categories know as messaging or education."""
        if package in AI_COMPANIONS or package in NOT_AI_COMPANIONS or never_blocked(package):
            return False
        names = [name] if isinstance(name, str) and name else []
        try:
            hit = self.household.categories_book.lookup(package)
        except Exception:  # noqa: BLE001 - the categories are a hint only
            hit = None
        if hit is not None:
            if hit.category in _NOT_AI_COMPANION_KINDS or hit.detail in _NOT_AI_COMPANION_KINDS:
                return False
            if isinstance(hit.name, str) and hit.name:
                names.append(hit.name)
        if any(_NOT_AI_COMPANION_NAME.search(n) for n in names):
            return False
        return any(_AI_COMPANION_NAME.search(n) for n in names)

    def _reasons(self, package: str) -> list[str]:
        """Every rule that would block [package], on or off, the one shown first (Android apps only)."""
        if never_blocked(package) or package in SUPPORTED_ANDROID or not android_package(package):
            return []
        found = []
        if package in OTHER_APP_STORES:
            found.append(APP_STORE)
        elif self.is_browser(package):
            found.append(BROWSER)
        if self.is_ai_companion(package):
            found.append(AI_COMPANION)
        return found

    def rule_reason(self, package: str) -> str | None:
        """Why a rule (on or off) blocks [package] (browser, app_store, ai_companion), None when none does."""
        return next(iter(self._reasons(package)), None)

    def active_reason(self, package: str) -> str | None:
        """Why a rule that is on blocks [package], None when none does."""
        return next((r for r in self._reasons(package) if self._rule_of(r)), None)

    def wanted(self, person: str, listed: set[str] | None = None) -> dict[str, set[str]]:
        """The apps Hearth blocks for [person] now, with why: an adult's blocks, and (a rule on) the browsers and
        stores, and the AI companion apps, among the apps Family Link lists for them ([listed]) or Hearth blocked for a
        rule before."""
        # A block a parent took back in the Family Link app stays theirs (until an adult blocks it again in Hearth)
        taken_back = set(self.parent_unblocked.get(person, {}))
        found: dict[str, set[str]] = {
            p: {ADULT} for p in self.adult.get(person, {}) if not never_blocked(p) and p not in taken_back
        }
        if self.rule_on or self.companion_rule_on:
            if listed is None:
                target = self.target_of(person)
                listed = fl.app_lists(self.hass, target[1])[0] if target else set()
            exempt = self.exempt.get(person, set()) | taken_back
            applied = self.applied.get(person, {})
            candidates = (listed | set(applied)) - exempt
            for package in candidates:
                reason = self.active_reason(package)
                if reason is not None:
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
        if blocked is not None:
            if self.last_blocked.get(person) != blocked:
                self.last_blocked[person] = set(blocked)
                if not self._closed:
                    self._save()
            return set(blocked)
        # The list is missing or cut short. That is unknown, not "nothing is blocked": read as nothing, every blocked
        # app became one Hearth pauses and resumes (a limit written to a blocked app can lift its block). The last
        # whole list stands, with what the list shows now
        return set(self.last_blocked.get(person, ())) | fl.blocked_shown(self.hass, target[1])

    def blocked_known(self, person: str) -> bool:
        """Whether blocked_packages can be gone by for [person]: Family Link's Blocked apps list is whole now, or was
        read whole before (kept over a restart). False while it is missing or cut short and never was whole: which
        apps are blocked isn't known then, and a caller does the careful thing."""
        target = self.target_of(person)
        if target is None:
            return True
        return fl.app_lists(self.hass, target[1])[1] is not None or person in self.last_blocked

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
            # What the rules block for them, worked out once (an adult's blocks don't count here)
            ruled = self.wanted(person)
            for package in packages:
                self.adult.get(person, {}).pop(package, None)
                if self.active_reason(package) is not None or ruled.get(package, set()) - {ADULT}:
                    # A rule would block it again: an adult said no
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
            if blocked is not None and self.companion_rule_on and person in self.kids():
                dirty |= self._ask_named(person, listed, blocked, want)
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
        fs_calls, fs_dirty = self._plan_fs(now)
        if dirty or fs_dirty:
            self._save()
        return calls + fs_calls

    def _plan_fs(self, now: datetime) -> tuple[list[tuple[str, str, str, bool]], bool]:
        """The Family Safety calls due now (Xbox and Windows apps), as _plan's; and whether anything changed."""
        calls: list[tuple[str, str, str, bool]] = []
        dirty = False
        kids = self.kids()
        for person in sorted(set(kids) | set(self.fs_applied) | set(self.adult)):
            entity_id = self.fs_target_of(person)
            want = {a for a in self.wanted(person, set()) if fs_app_id(a)} if person in kids else set()
            applied = self.fs_applied.setdefault(person, {})
            if entity_id is None or not (want or applied):
                continue
            installed, blocked, _names = self.fs_lists(person)
            if blocked is None:
                continue  # a list missing or cut short: nothing is blocked or unblocked
            held = self._fs_held(person)
            # An app Hearth's pause holds reads blocked for the pause: not a confirmation, nor a parent's unblock
            part = {a: r for a, r in applied.items() if a not in held}
            dirty |= self._confirm(person, part, installed, blocked)
            for app in [a for a in applied if a not in held and a not in part]:
                applied.pop(app)  # taken back by a parent in the Family Safety app
            for app in sorted(want):
                if app in held or app in blocked or app not in installed:
                    continue  # held by a pause (blocked once resumed), blocked already, or not installed (waits)
                if self._tries.get((person, app), 0) >= MAX_TRIES:
                    continue
                if self._due(person, app, now):
                    calls.append((person, entity_id, app, True))
            for app in sorted(set(applied) - want):
                if app in held:
                    continue  # an unblock now would lift Hearth's pause: done once it's resumed
                if app not in blocked:
                    applied.pop(app, None)
                    dirty = True
                elif self._due(person, app, now):
                    calls.append((person, entity_id, app, False))
        return calls, dirty

    def _ask_named(self, person: str, listed: set[str], blocked: set[str], want: dict[str, set[str]]) -> bool:
        """The adults are asked (once per app and kid, kept) about an app on [person]'s devices that may be an AI
        companion app only by its name: a notice with Block (hearth.block_app) and Not now. Never blocked by the rule.
        Says whether anything changed."""
        asked = self.asked.setdefault(person, {})
        looked = self._not_named.setdefault(person, set())
        skip = (
            blocked | set(want) | set(asked) | looked | self.exempt.get(person, set())
            | set(self.parent_unblocked.get(person, {}))
        )
        fresh = {p for p in listed - skip if p not in SUPPORTED_ANDROID and not never_blocked(p)}
        if not fresh:
            return False
        names = self.household.app_names(fresh, person)
        changed = False
        for package in sorted(fresh):
            name = names.get(package)
            if not self.named_ai_companion(package, name):
                if name:
                    # A name that isn't one: not looked at again this run
                    looked.add(package)
                continue
            shown = name or self.name_of(package, person)
            asked[package] = {"at": dt_util.utcnow().isoformat(), "name": shown}
            changed = True
            self._tell_named(person, package, shown)
        return changed

    def _tell_named(self, person: str, package: str, name: str) -> None:
        _LOGGER.info("%s: %s (%s) may be an AI companion app by its name; the adults are asked", person, package, name)
        self.hass.bus.async_fire("hearth_ai_companion_asked", {"person": person, "app": package, "name": name})
        attention = getattr(getattr(self.household, "hub", None), "attention", None)
        if attention is None:
            return
        kid = self.household.person_name(person)
        attention.notify(
            Item(
                # Only letters, digits, dots and underscores: a phone button sends the key between "|"s
                re.sub(r"[^A-Za-z0-9._]", "_", f"ai_companion_{person}_{package}"),
                f"{name} on {kid}'s devices may be an AI companion app (by its name). Hearth blocks only the companion "
                "apps it knows, so it left this one alone. Block it?",
                title=f"{kid}: {name} may be an AI companion app",
                urgency=NOTICE,
                audience=ADULTS,
                actions=(
                    Action("block", "Block", f"{DOMAIN}.block_app", {"people": [person], "apps": [package]}),
                    Action("not_now", "Not now", dismiss=True),
                ),
                about={"person": person},
                once=True,
            )
        )

    def _confirm(self, person: str, applied: dict[str, dict[str, Any]], listed: set[str], blocked: set[str]) -> bool:
        """What Family Link (or Family Safety) lists now, against what Hearth blocked: a block it lists is confirmed
        (its event fires once); one that left the device is marked gone (a reinstall comes back unblocked, and is
        blocked again); one confirmed, still installed and now unblocked was taken back by a parent in the Family Link
        (or Family Safety) app: recorded, and Hearth doesn't block it again. Says whether anything changed."""
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
            fs = fs_app_id(package)
            applied = self.fs_applied if fs else self.applied
            provider = "Family Safety" if fs else "Family Link"
            try:
                await call_service(self.hass,
                    *((FS_DOMAIN, service, self._fs_data(entity_id, package)) if fs else
                      (FL_DOMAIN, service, {"entity_id": entity_id, "package_name": package})),
                    blocking=True,
                    person=person, why=",".join(sorted(self.why_blocked(person, package))) or "unblock",
                )
            except Exception as err:  # noqa: BLE001 - one app failing mustn't stop the others
                _LOGGER.warning("Hearth couldn't %s %s for %s: %s", service.replace("_app", ""), package, person, err)
                self._errors[key] = (str(err)[:200], dt_util.utcnow())
                if block:
                    # It may have gone through all the same (a timeout): kept as Hearth's, unconfirmed, so a block
                    # Family Link lists later is Hearth's to lift, not a parent's
                    applied.setdefault(person, {}).setdefault(
                        package, {"at": dt_util.utcnow().isoformat(), "why": sorted(self.why_blocked(person, package))}
                    )
                continue
            self._errors.pop(key, None)
            if block:
                applied.setdefault(person, {})[package] = {
                    "at": dt_util.utcnow().isoformat(),
                    "why": sorted(self.why_blocked(person, package)),
                }
                # hearth_app_blocked fires once, when Family Link lists it blocked (_confirm)
                tries = self._tries[key] = self._tries.get(key, 0) + 1
                _LOGGER.debug("block %s for %s: try %s of %s, waiting for %s to list it", package, person, tries, MAX_TRIES, provider)
                if tries >= MAX_TRIES:
                    # Shown on the card until Family Link lists it, or an adult blocks it again
                    self._errors[key] = (f"{provider} didn't block {self.name_of(package, person)}", dt_util.utcnow())
            else:
                applied.get(person, {}).pop(package, None)
                self.hass.bus.async_fire("hearth_app_unblocked", {"person": person, "app": package})
            self._save()
        if calls:
            self.household.enforcement.refresh_soon(calls[-1][1])
            async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)
        if self._again:
            self._again = False
            self._task = None
            self.sync()

    def _fs_data(self, entity_id: str, app: str) -> dict[str, Any]:
        """Family Safety's block_app / unblock_app data: the child's entity where the installed Family Safety takes
        one, else their account id (upstream's)."""
        from .enforce import fs_accepts, fs_account_of

        data = {"entity_id": entity_id, "app_id": app} if "." in entity_id else {"account_id": entity_id, "app_id": app}
        if "entity_id" in data and not fs_accepts(self.hass, "block_app", data):
            data = {"account_id": fs_account_of(self.hass, entity_id) or entity_id, "app_id": app}
        return data

    # Views

    def state_of(self, person: str, package: str, listed: set[str], blocked: set[str] | None) -> str:
        if fs_app_id(package):
            installed, fs_blocked, _names = self.fs_lists(person)
            if package in self._fs_held(person):
                return PENDING  # held by a pause: blocked once it's resumed
            if package in self.fs_applied.get(person, {}) and fs_blocked is not None and package in fs_blocked:
                return BLOCKED
            if fs_blocked is not None and package in fs_blocked:
                return PARENT
            if fs_blocked is not None and package not in installed:
                return WAITING
            return PENDING
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
        if package in AI_COMPANIONS:
            return AI_COMPANIONS[package]
        if fs_app_id(package) and person is not None and (name := self.fs_lists(person)[2].get(package)):
            return name
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
                "state": self.state_of(person, package, listed, blocked) if target or fs_app_id(package) else PENDING,
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
        """For Hearth's page: the rules, the supported browsers, the lists, and each kid's blocks and web filter."""
        return {
            "rule": self.rule_on,
            "ai_companion_rule": self.companion_rule_on,
            "ai_companions": dict(AI_COMPANIONS),
            "supported": [dict(b) for b in SUPPORTED_BROWSERS],
            "browsers": dict(BROWSERS),
            "app_stores": dict(OTHER_APP_STORES),
            "kids": [
                {
                    "person": person,
                    "name": self.household.person_name(person),
                    "family_link": self.target_of(person) is not None,
                    # Xbox and Windows apps can be blocked too (hearth.block_app with Family Safety's app ids)
                    "family_safety": self.fs_target_of(person) is not None,
                    "blocks": self.views(person),
                    "exempt": sorted(self.exempt.get(person, set())),
                    # Blocks of Hearth's a parent took back in the Family Link app (Hearth leaves them unblocked)
                    # Apps only named like an AI companion app the adults were asked about (never blocked by the rule)
                    "asked": [
                        {"app": p, "name": r.get("name") or p, "at": r.get("at")}
                        for p, r in sorted(self.asked.get(person, {}).items())
                    ],
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
                "by": "hearth.block_app"
                if ADULT in why
                else CONF_BLOCK_UNSUPPORTED_BROWSERS
                if why & {BROWSER, APP_STORE}
                else CONF_BLOCK_AI_COMPANIONS,
                "app": app,
                "why": sorted(why),
                "until": None,
            }
        ]
