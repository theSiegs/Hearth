"""App categories: what each app is, which Hearth keeps itself (docs/home-assistant-integration.md, App categories).

What an app is (one of ten `category` values, or `interface` for System screens, and a finer `detail`: youtube,
streaming, education, companion, system) helps decide which pool it counts in (limits.placer); the household's map
says which pool each value goes to (limits.pool_map). For any app Hearth sees, the answer is the first of:

1. **The owner's override**: an adult said what the app is (options `app_categories`, Hearth's page > Apps). An
   adult's move to a pool or a pool's list (`app_groups`, `group_apps`) wins over any category (limits.placer).
2. **The starter list** shipped with the integration (categories_data/starter.json, made by
   tool/categories_starter.py): the retired App Facts catalog's confirmed answers and hand overrides, the System
   screens set, parental-control apps and big games. An entry may say an app is none of the ten (a browser).
3. **A store's genre**, looked up when a kid first uses an app 1 and 2 don't cover (category_lookup.py) and kept
   with its date: Google Play's, the Microsoft Store's (Windows and Xbox) and Steam's. Only the mappings the old
   catalog's classifier was sure of confirm a category, and never a loose one (messaging, accessibility).
4. **An AI answer**, only with an AI Task entity chosen in the options and only when the store's genre was unclear.
   Never confirmed: it never puts an app in Messaging or Accessibility, nor in System screens.
5. Unknown: the device's own category and where its time came from answer instead (limits.placer).

What leaves the house: a store lookup sends the app's public store id (an Android package, a Microsoft Store or
Xbox id, a package family name, a Steam app id) to that store, and nothing else; at most STORE_PER_DAY a day, one at
a time. An AI question goes to the AI Task entity the owner chose (a local model stays local). Nothing is sent
anywhere else.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import date, timedelta
import json
import logging
from pathlib import Path
import re
from typing import Any
import unicodedata

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.event import async_track_time_interval
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import APP_CATEGORIES

_LOGGER = logging.getLogger(__name__)

# Options
# {key: {"category": value or None, "detail"?: value}}: what an adult said an app is (None: none of the ten)
CONF_APP_CATEGORIES = "app_categories"
# Store lookups (on by default; off sends nothing to any store)
CONF_CATEGORY_LOOKUP = "category_lookup"
# The AI Task entity asked about apps whose store genre is unclear (none by default: no AI is asked)
CONF_CATEGORY_AI = "category_ai_task"

# The finer values Hearth knows, and the category each sits under
DETAILS = {"youtube": "video", "streaming": "video", "education": "productivity", "companion": "productivity",
           "system": "productivity"}
INTERFACE = "interface"
# Categories that loosen limits (Messaging is outside All screen time, Accessibility is never paused): only an
# override or the starter list confirms one, never a store's genre or an AI
LOOSE = frozenset({"messaging", "accessibility"})
# What each value is: its label, the pool Hearth sends it to by default (limits.pool_map is the code), whether it
# loosens a limit, and System screens' counted nowhere and set only by a list (the old catalog's values table, now
# Hearth's own)
BUILTIN_VALUES: dict[str, dict[str, Any]] = {
    "game": {"label": "Games", "pool": "games"},
    "video": {"label": "Video", "pool": "other"},
    "audio": {"label": "Music and audio", "pool": "other", "pool_names": ["music", "audio"]},
    "image": {"label": "Photos and art", "pool": "other"},
    "social": {"label": "Social", "pool": "social"},
    "news": {"label": "News", "pool": "other"},
    "maps": {"label": "Maps", "pool": "other"},
    "productivity": {"label": "Productivity", "pool": "other"},
    "accessibility": {"label": "Accessibility", "pool": "accessibility", "loose": True},
    "messaging": {"label": "Messaging", "pool": "messaging", "outside_all": True, "loose": True},
    INTERFACE: {"label": "System screens", "counted": False, "overrides_only": True},
    "youtube": {"label": "YouTube", "parent": "video", "pool": "other", "pool_names": ["youtube"]},
    "streaming": {"label": "Streaming", "parent": "video", "pool": "other", "pool_names": ["streaming", "tv", "shows"]},
    "education": {"label": "Education", "parent": "productivity", "pool": "other",
                  "pool_names": ["homework", "school", "education", "learning"], "loose": True},
    "companion": {"label": "Companion apps", "parent": "productivity", "pool": "other", "loose": True},
    "system": {"label": "System apps", "parent": "productivity", "pool": "other", "loose": True},
}
# The categories an answer may have: the ten, and System screens (set only by an override or the starter list)
KNOWN_CATEGORIES = (*APP_CATEGORIES, INTERFACE)

# Where an answer came from
OVERRIDE = "override"
STARTER = "starter"
STORE = "store"
AI = "ai"
UNKNOWN = "unknown"

# Name keys tried, in order, for a played title's name when its platform isn't known
NAME_PLATFORMS = ("xbox", "switch", "msstore", "steam")
# Namespaces a store answers for (category_lookup.py), and those an AI may be asked about (a store's, and Family
# Safety's own ids, by the app's name)
STORE_NAMESPACES = ("android", "msstore", "xbox", "pfn", "steam")
AI_NAMESPACES = (*STORE_NAMESPACES, "fs")

# Lookups: one at a time, every TICK, at most STORE_PER_DAY store lookups and AI_PER_DAY AI questions a day
TICK = timedelta(seconds=30)
STORE_PER_DAY = 100
AI_PER_DAY = 20
MAX_QUEUE = 300
# A store's answer is looked at again after RECHECK, an app the store doesn't have after MISSING_RECHECK, a lookup
# that failed (offline, a store answering oddly) the next day; an AI answer stands until the store's answer changes
RECHECK = timedelta(days=90)
MISSING_RECHECK = timedelta(days=30)
FAILED_RECHECK = timedelta(days=1)

DATA_DIR = Path(__file__).parent / "categories_data"
STARTER_FORMAT = "hearth.starter/1"
_STARTER = "hearth_categories_starter"
_PACKAGE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
_SWITCH_ID = re.compile(r"^01[0-9A-Fa-f]{14}$")
_FS_ID = re.compile(r"^x:([a-z0-9]+):([0-9A-Fa-f]{16})$")


# Keys


def normalize_name(name: str) -> str:
    """A played title's name as a key: marks, accents, case, an edition suffix and punctuation dropped (the old
    catalog's normalizer, pinned by ha_tests/catalog_normalize_vectors.json)."""
    for mark in ("™", "®", "©"):
        name = name.replace(mark, "")
    name = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c)).lower()
    name = name.strip()
    for suffix in (" for nintendo switch", " nintendo switch edition", " - nintendo switch", " standard edition", " edition"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    return re.sub(r"[^a-z0-9]+", " ", name).strip()


def category_keys(item: str, platforms: tuple[str, ...] = NAME_PLATFORMS) -> list[str]:
    """The keys an item Hearth counts under is known by (best first): android:<package>, pfn:<package family>,
    fs:<platform>:<hex> (Family Safety's own ids), switch:<application id>, name:<platform>:<normalized name>. None
    for a win32: program or a household's title."""
    if not item or item.startswith(("win32:", "title:")):
        return []
    if item.startswith("a:"):
        return [f"android:{item[2:]}"] if _PACKAGE.match(item[2:]) else []
    if item.startswith("appx:"):
        pfn = item.removeprefix("appx:").removeprefix("windowsplt:")
        return [f"pfn:{pfn.lower()}"] if pfn and " " not in pfn else []
    if match := _FS_ID.match(item):
        return [f"fs:{match.group(1)}:{match.group(2).lower()}"]
    if item.startswith("x:"):
        return []
    if _SWITCH_ID.match(item):
        return [f"switch:{item.upper()}"]
    if _PACKAGE.match(item):
        return [f"android:{item}"]
    name = normalize_name(item)
    return [f"name:{p}:{name}" for p in platforms] if name else []


def override_key(item: str) -> str:
    """The key an adult's override of [item] is kept under: its first key, else the item itself (a win32: program)."""
    keys = category_keys(item)
    return keys[0] if keys else item


def namespace(key: str) -> str:
    return key.split(":", 1)[0] if ":" in key else ""


def clean_answer(category: Any, detail: Any, allowed: Iterable[str] = KNOWN_CATEGORIES) -> tuple[str | None, str | None]:
    """(category, detail) with what Hearth doesn't know dropped: a detail sits under its own category (a category
    given alone with a detail is the detail's)."""
    category = category if isinstance(category, str) and category in allowed else None
    detail = detail if isinstance(detail, str) and detail in DETAILS else None
    if detail is not None and category not in (None, DETAILS[detail]):
        detail = None
    if detail is not None and category is None:
        category = DETAILS[detail]
    return category, detail


@dataclass(frozen=True)
class Hit:
    """What an app is, and where that came from."""

    key: str
    # An override, the starter list or a store's sure mapping (never a loose category from a store, never an AI)
    confirmed: bool
    category: str | None
    detail: str | None
    name: str | None = None
    # System screens from the starter list or an override: counted nowhere (limits.placer)
    uncounted: bool = False
    source: str = STARTER

    @property
    def value(self) -> str | None:
        """The finer value first (detail), then the category."""
        return self.detail or self.category


# The starter list


def read_starter(folder: Path = DATA_DIR) -> dict[str, dict[str, Any]]:
    """The starter list's keys (key -> {category, detail?, app?, name?}); empty if the file can't be read (it always
    should). Runs in the executor."""
    try:
        doc = json.loads((folder / "starter.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        _LOGGER.warning("Hearth's starter list of app categories can't be read: %s", err)
        return {}
    if not isinstance(doc, dict) or doc.get("format") != STARTER_FORMAT or not isinstance(doc.get("keys"), dict):
        _LOGGER.warning("Hearth's starter list of app categories isn't %s", STARTER_FORMAT)
        return {}
    return doc["keys"]


class StarterList:
    """The starter list, looked up by key and through the app's other keys (its slug)."""

    def __init__(self, keys: dict[str, dict[str, Any]] | None = None) -> None:
        self.keys: dict[str, dict[str, Any]] = {}
        self.by_app: dict[str, list[str]] = {}
        for key, entry in (keys or {}).items():
            if not isinstance(key, str) or not isinstance(entry, dict):
                continue
            category, detail = clean_answer(entry.get("category"), entry.get("detail"))
            if category is None and entry.get("category") is not None:
                # A value Hearth doesn't know: as absent (an explicit None is "none of the ten")
                continue
            name = entry.get("name")[:64] if isinstance(entry.get("name"), str) else None
            app = entry.get("app") if isinstance(entry.get("app"), str) else None
            self.keys[key] = {"category": category, "detail": detail, "name": name, "app": app}
        for key in sorted(self.keys):
            if app := self.keys[key]["app"]:
                self.by_app.setdefault(app, []).append(key)

    def __len__(self) -> int:
        return len(self.keys)

    def lookup(self, item: str) -> Hit | None:
        """The starter list's answer for [item]: by its own keys, then its app's other keys; None when it has none."""
        direct = [k for k in category_keys(item) if k in self.keys]
        if not direct:
            return None
        siblings = [
            other for key in direct for other in self.by_app.get(self.keys[key]["app"] or "", []) if other not in direct
        ]
        # A key with a category (its own first, then the app's others); else its own "none of the ten"
        key = next((k for k in direct + siblings if self.keys[k]["category"] is not None), direct[0])
        e = self.keys[key]
        return Hit(key, True, e["category"], e["detail"], e["name"], e["category"] == INTERFACE, STARTER)


# The household's book


def _date(value: Any) -> date | None:
    return dt_util.parse_date(value) if isinstance(value, str) else None


def store_due(store: dict[str, Any] | None, today: date) -> bool:
    """Whether a key's store answer should be looked up (again): never looked up, or its re-check is due."""
    if not store:
        return True
    at = _date(store.get("at"))
    if at is None:
        return True
    wait = {"found": RECHECK, "missing": MISSING_RECHECK}.get(store.get("status"), FAILED_RECHECK)
    return today - at >= wait


def needs_ai(store: dict[str, Any] | None) -> bool:
    """Whether a store's answer leaves the app unclear enough to ask an AI: none, not on the store, or a genre that
    doesn't say (Entertainment, Lifestyle, Education...)."""
    if not store:
        return True
    if store.get("status") == "missing":
        return True
    # A failed lookup waits for its retry; a store's sure answer, or its "none of the ten", stands
    return store.get("status") == "found" and bool(store.get("unclear"))


def ai_due(answers: dict[str, Any], today: date) -> bool:
    """Whether an AI may be asked about a key: never asked, or its last question failed a day ago or more."""
    ai = answers.get("ai")
    if ai is None:
        return True
    at = _date(ai.get("at"))
    return bool(ai.get("failed")) and (at is None or today - at >= FAILED_RECHECK)


class CategoryBook:
    """The household's app categories: the owner's overrides, the starter list, and the store and AI answers looked up
    and kept here (Home Assistant's storage, hearth.categories.<entry>)."""

    def __init__(self, hass: HomeAssistant, entry_id: str, options: dict[str, Any]) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.categories.{entry_id}")
        self.starter = StarterList()
        self.overrides: dict[str, dict[str, Any]] = {}
        for key, value in (options.get(CONF_APP_CATEGORIES) or {}).items():
            if isinstance(key, str) and isinstance(value, dict):
                category, detail = clean_answer(value.get("category"), value.get("detail"))
                self.overrides[key] = {"category": category, "detail": detail}
        self.lookup_on = options.get(CONF_CATEGORY_LOOKUP, True) is not False
        self.ai_entity: str | None = options.get(CONF_CATEGORY_AI) or None
        # key -> {"store": {...}, "ai": {...}} (category_lookup.py's answers, with their dates)
        self.answers: dict[str, dict[str, Any]] = {}
        # Keys waiting to be looked up, oldest first, and the names they were seen with (for an AI's question)
        self.queue: list[str] = []
        self.names: dict[str, str] = {}
        # Today's counts (the day, store lookups, AI questions)
        self.counts: dict[str, Any] = {"day": None, "store": 0, "ai": 0}
        self.on_change: Callable[[], None] | None = None
        self._unsubs: list[Callable[[], None]] = []
        self._run: Callable[[Any], Any] | None = None
        self._busy = False
        self._session = None

    # Store

    async def async_load(self) -> None:
        # Read once per Home Assistant run (a reload doesn't read the file again)
        keys = self.hass.data.get(_STARTER)
        if keys is None:
            keys = self.hass.data[_STARTER] = await self.hass.async_add_executor_job(read_starter)
        self.starter = StarterList(keys)
        stored = await self._store.async_load() or {}
        self.answers = {k: v for k, v in (stored.get("answers") or {}).items() if isinstance(v, dict)}
        self.queue = [k for k in stored.get("queue") or [] if isinstance(k, str)][:MAX_QUEUE]
        self.names = {k: v for k, v in (stored.get("names") or {}).items() if k in self.queue and isinstance(v, str)}
        if isinstance(stored.get("counts"), dict):
            self.counts = {**self.counts, **stored["counts"]}

    def _data(self) -> dict[str, Any]:
        return {"answers": self.answers, "queue": self.queue, "names": self.names, "counts": self.counts}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # Answers

    def lookup(self, item: str) -> Hit | None:
        """What [item] is: the owner's override, the starter list, a store's answer, an AI's; None when unknown (or
        only "none of the ten" from a store)."""
        keys = category_keys(item)
        for key in (*keys, item):
            if key in self.overrides:
                o = self.overrides[key]
                return Hit(key, True, o["category"], o["detail"], None, o["category"] == INTERFACE, OVERRIDE)
        if (hit := self.starter.lookup(item)) is not None:
            return hit
        for key in keys:
            answers = self.answers.get(key) or {}
            store = answers.get("store") or {}
            if store.get("category"):
                return Hit(key, bool(store.get("confirmed")) and store["category"] not in LOOSE, store["category"],
                           store.get("detail"), store.get("name"), False, STORE)
            ai = answers.get("ai") or {}
            if ai.get("category"):
                return Hit(key, False, ai["category"], ai.get("detail"), store.get("name"), False, AI)
        return None

    def describe(self, item: str) -> dict[str, Any]:
        """For Hearth's page: what [item] is and where that came from (override, starter, store, ai or unknown), and
        the store's genre when one was looked up."""
        hit = self.lookup(item)
        keys = category_keys(item)
        store = next(((self.answers.get(k) or {}).get("store") for k in keys if (self.answers.get(k) or {}).get("store")), None)
        found: dict[str, Any] = {"category": None, "detail": None, "source": UNKNOWN, "confirmed": False}
        if hit is not None:
            found = {"category": hit.category, "detail": hit.detail, "source": hit.source, "confirmed": hit.confirmed}
        elif store and store.get("status") == "found" and not store.get("unclear"):
            # Looked up, and the store files it under none of the ten (Shopping, Finance...); an unclear genre
            # (Entertainment) leaves it unknown
            found["source"] = STORE
        if store and store.get("genre"):
            found["genre"] = store["genre"]
        if store and store.get("at"):
            found["checked"] = store["at"]
        key = keys[0] if keys else None
        found["waiting"] = key in self.queue if key else False
        return found

    # Overrides (the options; Hearth's page writes them)

    @staticmethod
    def with_override(options: dict[str, Any], item: str, category: str | None, detail: str | None,
                      clear: bool = False) -> dict[str, Any]:
        """[options] with an adult's answer for [item] (category None: none of the ten), or without one ([clear])."""
        overrides = dict(options.get(CONF_APP_CATEGORIES) or {})
        key = override_key(item)
        if clear:
            overrides.pop(key, None)
        else:
            category, detail = clean_answer(category, detail)
            overrides[key] = {"category": category} | ({"detail": detail} if detail else {})
        return {**options, CONF_APP_CATEGORIES: overrides}

    # Lookups

    def wants_lookup(self, key: str, today: date) -> bool:
        """Whether [key] could use a store lookup or an AI question now."""
        ns = namespace(key)
        answers = self.answers.get(key) or {}
        if ns in STORE_NAMESPACES and self.lookup_on and store_due(answers.get("store"), today):
            return True
        return bool(self.ai_entity) and ns in AI_NAMESPACES and ai_due(answers, today) and needs_ai(answers.get("store"))

    @callback
    def note_used(self, items: dict[str, str | None]) -> None:
        """Apps a kid used ([items]: item -> its name, when known): each the overrides and the starter list don't
        cover joins the lookup queue."""
        if not self.lookup_on and not self.ai_entity:
            return
        today = dt_util.now().date()
        changed = False
        for item, name in items.items():
            keys = category_keys(item)
            if not keys or any(k in self.overrides for k in (*keys, item)) or self.starter.lookup(item) is not None:
                continue
            key = keys[0]
            if key in self.queue or not self.wants_lookup(key, today):
                continue
            if len(self.queue) >= MAX_QUEUE:
                break
            self.queue.append(key)
            if name and name != item:
                self.names[key] = str(name)[:80]
            changed = True
        if changed:
            self._save()

    def _count(self, kind: str) -> bool:
        """Takes one of today's [kind] lookups; False when none are left."""
        today = dt_util.now().date().isoformat()
        if self.counts.get("day") != today:
            self.counts = {"day": today, "store": 0, "ai": 0}
        limit = STORE_PER_DAY if kind == "store" else AI_PER_DAY
        if self.counts.get(kind, 0) >= limit:
            return False
        self.counts[kind] = self.counts.get(kind, 0) + 1
        return True

    @callback
    def start(self, run: Callable[[Any], Any]) -> None:
        """Looks up the next waiting app every TICK, through [run] (the entry's task runner)."""
        self._run = run

        @callback
        def tick(_now=None) -> None:
            if self.queue and not self._busy:
                run(self.async_next())

        self._unsubs.append(async_track_time_interval(self.hass, tick, TICK))

    @callback
    def stop(self) -> None:
        self._run = None
        while self._unsubs:
            self._unsubs.pop()()
        if self._session is not None:
            session, self._session = self._session, None
            self.hass.async_create_task(session.close(), eager_start=True)

    def _http(self):
        """A session of its own that keeps no cookies: a store sees an id, never a returning visitor."""
        if self._session is None:
            import aiohttp

            from homeassistant.helpers.aiohttp_client import async_create_clientsession

            # Closed by stop() (an unload or reload), else when Home Assistant closes
            self._session = async_create_clientsession(self.hass, cookie_jar=aiohttp.DummyCookieJar())
        return self._session

    async def async_next(self) -> str | None:
        """Looks up the oldest waiting key (a store, then maybe an AI); its key, or None when nothing was done."""
        from . import category_lookup as lookup

        if self._busy or not self.queue:
            return None
        self._busy = True
        try:
            key = self.queue[0]
            today = dt_util.now().date()
            answers = dict(self.answers.get(key) or {})
            before = self.lookup_answer(answers)
            ns = namespace(key)
            if ns in STORE_NAMESPACES and self.lookup_on and store_due(answers.get("store"), today):
                if not self._count("store"):
                    return None
                store = await lookup.async_store(self._http(), key)
                store["at"] = today.isoformat()
                if (answers.get("store") or {}).get("category") != store.get("category"):
                    # The store says something new: an AI's answer about the old one goes
                    answers.pop("ai", None)
                answers["store"] = store
            if self.ai_entity and ns in AI_NAMESPACES and ai_due(answers, today) and needs_ai(answers.get("store")):
                if not self._count("ai"):
                    self.answers[key] = answers
                    self._save()
                    return None
                name = (answers.get("store") or {}).get("name") or self.names.get(key)
                ai = await lookup.async_ask_ai(self.hass, self.ai_entity, key, name, (answers.get("store") or {}).get("about"))
                # None: the entity couldn't answer (asked again a day later)
                answers["ai"] = {**(ai if ai is not None else {"failed": True}), "at": today.isoformat()}
            self.answers[key] = answers
            self.queue.pop(0)
            self.names.pop(key, None)
            self._save()
            if self.lookup_answer(answers) != before and self.on_change is not None:
                self.on_change()
            return key
        finally:
            self._busy = False

    @staticmethod
    def lookup_answer(answers: dict[str, Any]) -> tuple[Any, ...]:
        store, ai = answers.get("store") or {}, answers.get("ai") or {}
        return (store.get("category"), store.get("detail"), bool(store.get("confirmed")), ai.get("category"), ai.get("detail"))

    def page(self, items: Iterable[str] = ()) -> dict[str, Any]:
        """For Hearth's page: the settings, the starter list's size, what's waiting, and how the apps in [items] are
        known (a count per source)."""
        sources: dict[str, int] = {OVERRIDE: 0, STARTER: 0, STORE: 0, AI: 0, UNKNOWN: 0}
        for item in items:
            sources[self.describe(item)["source"]] += 1
        return {
            "lookup": self.lookup_on,
            "ai_entity": self.ai_entity,
            "starter": len(self.starter),
            "waiting": len(self.queue),
            "today": {"store": self.counts.get("store", 0), "ai": self.counts.get("ai", 0)}
            if self.counts.get("day") == dt_util.now().date().isoformat() else {"store": 0, "ai": 0},
            "sources": sources,
        }


# The retired shared catalog's options, migrated once


OLD_OPTIONS = ("catalog_fetch", "catalog_share", "catalog_share_asked", "catalog_url", "catalog_relay")
OLD_STORE = "hearth.catalog.{entry_id}"


def _old_key(key: str) -> str | None:
    """A correction's catalog key as an override's key: android:, pfn:, msstore:, xbox:, steam:, switch: stay as
    they are."""
    if isinstance(key, str) and namespace(key) in (*STORE_NAMESPACES, "switch", "fs") and len(key) <= 200:
        return key
    return None


def migrated_options(options: dict[str, Any], corrections: list[dict[str, Any]] | None) -> dict[str, Any] | None:
    """The options without the shared catalog's settings, with each correction an adult chose to share kept as their
    override of what the app is (an override already there wins), and fetching turned off kept as store lookups off;
    None when there's nothing to migrate."""
    if not any(name in options for name in OLD_OPTIONS) and not corrections:
        return None
    out = {k: v for k, v in options.items() if k not in OLD_OPTIONS}
    if options.get("catalog_fetch") is False and CONF_CATEGORY_LOOKUP not in out:
        # An adult who turned off fetching asked Hearth not to look apps up anywhere
        out[CONF_CATEGORY_LOOKUP] = False
    overrides = dict(out.get(CONF_APP_CATEGORIES) or {})
    for correction in corrections or []:
        if not isinstance(correction, dict) or (key := _old_key(correction.get("key"))) is None or key in overrides:
            continue
        category, detail = clean_answer(correction.get("category"), correction.get("detail"), APP_CATEGORIES)
        if category is not None:
            overrides[key] = {"category": category} | ({"detail": detail} if detail else {})
    if overrides:
        out[CONF_APP_CATEGORIES] = overrides
    return out


async def async_migrate_catalog(hass: HomeAssistant, entry) -> bool:
    """Once: the shared catalog's options go, its kept copy is removed, and the corrections an adult queued to share
    become their overrides. Before the update listener, so it doesn't reload. True when something changed."""
    old: Store[dict[str, Any]] = Store(hass, 1, OLD_STORE.format(entry_id=entry.entry_id))
    stored = await old.async_load()
    corrections = (stored or {}).get("corrections") if isinstance(stored, dict) else None
    options = migrated_options(dict(entry.options), corrections if isinstance(corrections, list) else None)
    if options is not None:
        hass.config_entries.async_update_entry(entry, options=options)
    if stored is not None:
        await old.async_remove()
    if options is not None or stored is not None:
        _LOGGER.info("Hearth now keeps app categories itself: the shared catalog's settings and copy are gone%s",
                     f", {len(corrections)} corrections kept as overrides" if corrections else "")
        return True
    return False
