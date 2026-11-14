"""The shared app catalog: Glint's signed catalog of app facts, which Hearth reads to put apps in pools.

Glint's catalog (glint-recipes) publishes, at a stable URL, a signed index (`glint.exchange/1`) naming one shard per
platform (`glint.catalog/1`): for each key (android:<package>, pfn:<package family>, xbox:<title id>, name:switch:<name>
and so on) what the app is (`category`, one of the ten Android categories, and the finer `detail`: youtube,
streaming, education, companion, system), its app slug (`app`, shared by the same app's keys on every platform) and
whether that's `confirmed` (an owner's override, a store rule, a passing review) or only `suggested`.

Hearth's side, as the catalog's contract says (docs/home-assistant-integration.md, Shared app catalog):

- **Fetch**: once a day at a random minute, and at startup when the copy is over a day old; never per app. The index
  with If-None-Match (ETag), then only the shards whose SHA-256 changed. A generic user agent and nothing else.
- **Verify**, in order, and any failure keeps the last good copy: the index's Ed25519 signature over its exact bytes
  with one of the two pinned keys (catalog_data/keys), its format, its `seq` (lower than the copy's is a rollback,
  refused), and each shard's SHA-256, format and platform.
- **Keep** the last good copy in a Home Assistant Store with no expiry; offline it's used forever. Before the first
  fetch, the snapshot bundled with the integration (catalog_data/snapshot) is checked the same way and used.
- **Look up** what Hearth sees (an Android package, Family Safety's a:/appx:/x: ids, a Nintendo application id, an
  Xbox or Switch game's name) under the catalog's keys, then the app's other keys through its slug. win32: ids are
  never looked up.
- **Send upward** (off until an HA administrator turns it on, asked once): weekly, at most 20 public store ids the
  catalog lacks and 10 corrections an adult chose to share, with no household, person or device id, no usage and no
  times. Until the relay's /propose is deployed (a 404), nothing happens and the queue waits.

Facts only come from the catalog; which pool a fact goes to is the household's (limits.pool_map).
"""

from __future__ import annotations

import base64
import binascii
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
import hashlib
import json
import logging
from pathlib import Path
import random
import re
from typing import Any
import unicodedata

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.event import async_call_later, async_track_time_change
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import APP_CATEGORIES

_LOGGER = logging.getLogger(__name__)

DEFAULT_URL = "https://thesiegs.github.io/glint-recipes/"
DEFAULT_RELAY = "https://glint-relay.glint-tiles.workers.dev/"
EXCHANGE_FORMAT = "glint.exchange/1"
CATALOG_FORMAT = "glint.catalog/1"
PROPOSE_FORMAT = "glint.catalog-propose/1"
# Options (Hearth's own tile exchange setting, with Glint's defaults: fetching on, sending off until asked)
CONF_CATALOG_FETCH = "catalog_fetch"
CONF_CATALOG_SHARE = "catalog_share"
CONF_CATALOG_ASKED = "catalog_share_asked"
CONF_CATALOG_URL = "catalog_url"
CONF_CATALOG_RELAY = "catalog_relay"

# The finer values (glint.catalog/1 `detail`) Hearth knows, and the category each sits under
DETAILS = {"youtube": "video", "streaming": "video", "education": "productivity", "companion": "productivity",
           "system": "productivity"}
# The shards Hearth reads (an unknown one is skipped, as is an unknown namespace)
SHARDS = ("android", "msstore", "xbox", "pfn", "fs", "steam", "switch", "web", "name")
# Namespaces of public store ids the relay may be sent (fs: stays in the household until the catalog accepts it)
PROPOSABLE = ("msstore", "xbox", "pfn", "steam", "switch")
# Name keys tried, in order, for a played title's name when its platform isn't known
NAME_PLATFORMS = ("xbox", "switch", "msstore", "steam")

USER_AGENT = "Hearth"
MAX_BYTES = 8 * 1024 * 1024
TIMEOUT_S = 30
STALE = timedelta(hours=24)
SEND_EVERY = timedelta(days=7)
MAX_KEYS = 20
MAX_CORRECTIONS = 10
# A key sent once isn't sent again for this long (the relay dedupes for 30 days too)
RESEND_AFTER = timedelta(days=30)
# A candidate not seen again for this long is forgotten
FORGET_AFTER = timedelta(days=30)
MAX_CANDIDATES = 200

DATA_DIR = Path(__file__).parent / "catalog_data"
_BUNDLED = "hearth_catalog_bundled"
_SHARD_PATH = re.compile(r"^k/[a-z]+\.[0-9a-f]{16}\.json$")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_PACKAGE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
_SWITCH_ID = re.compile(r"^01[0-9A-Fa-f]{14}$")
_FS_ID = re.compile(r"^x:([a-z0-9]+):([0-9A-Fa-f]{16})$")


class CatalogError(Exception):
    """The fetched catalog fails a check: the last good copy stays."""


# Verifying


def load_keys(folder: Path) -> list[bytes]:
    """The pinned public keys (base64 of a raw 32-byte Ed25519 key, one per file)."""
    keys = []
    for path in sorted(folder.glob("*.pub")):
        raw = base64.b64decode(path.read_text(encoding="ascii").strip(), validate=True)
        if len(raw) == 32:
            keys.append(raw)
    return keys


def verify_index(index_bytes: bytes, sig_text: bytes | str, keys: list[bytes]) -> dict[str, Any]:
    """The index, once its signature verifies with one of [keys] and it's glint.exchange/1; else CatalogError."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    if isinstance(sig_text, bytes):
        sig_text = sig_text.decode("ascii", errors="replace")
    try:
        sig = base64.b64decode(sig_text.strip(), validate=True)
    except (binascii.Error, ValueError) as err:
        raise CatalogError("the signature isn't base64") from err
    if len(sig) != 64:
        raise CatalogError("the signature isn't 64 bytes")
    for raw in keys:
        try:
            Ed25519PublicKey.from_public_bytes(raw).verify(sig, index_bytes)
            break
        except (InvalidSignature, ValueError):
            continue
    else:
        raise CatalogError("the signature verifies with no pinned key")
    try:
        index = json.loads(index_bytes.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as err:
        raise CatalogError("the index isn't JSON") from err
    if not isinstance(index, dict) or index.get("format") != EXCHANGE_FORMAT:
        raise CatalogError("the index isn't glint.exchange/1")
    if not isinstance(index.get("seq"), int) or isinstance(index.get("seq"), bool):
        raise CatalogError("the index has no seq")
    return index


def check_seq(index: dict[str, Any], cached: int | None) -> None:
    if cached is not None and index["seq"] < cached:
        raise CatalogError(f"seq {index['seq']} is lower than the copy's {cached}: a rollback")


def shard_list(index: dict[str, Any]) -> dict[str, tuple[str, str]]:
    """The shards Hearth reads: name -> (path, sha256). None listed (an older index) is an empty catalog."""
    catalog = index.get("catalog")
    if catalog is None:
        return {}
    if not isinstance(catalog, dict) or catalog.get("format") != CATALOG_FORMAT:
        raise CatalogError("the index's catalog isn't glint.catalog/1")
    found: dict[str, tuple[str, str]] = {}
    for name, entry in (catalog.get("shards") or {}).items():
        if name not in SHARDS:
            continue
        path, digest = (entry or {}).get("path"), (entry or {}).get("sha256")
        if not isinstance(path, str) or not _SHARD_PATH.match(path) or not isinstance(digest, str) or not _HEX64.match(digest):
            raise CatalogError(f"the index's {name} shard is malformed")
        found[name] = (path, digest)
    return found


def check_shard(name: str, digest: str, data: bytes) -> dict[str, Any]:
    """A shard's keys, once its bytes' SHA-256 is the index's and it's glint.catalog/1 for [name]."""
    if hashlib.sha256(data).hexdigest() != digest:
        raise CatalogError(f"the {name} shard's SHA-256 isn't the index's")
    try:
        doc = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as err:
        raise CatalogError(f"the {name} shard isn't JSON") from err
    if not isinstance(doc, dict) or doc.get("format") != CATALOG_FORMAT or doc.get("platform") != name:
        raise CatalogError(f"the {name} shard isn't glint.catalog/1 for {name}")
    keys = doc.get("keys")
    if not isinstance(keys, dict):
        raise CatalogError(f"the {name} shard has no keys")
    return keys


def read_bundled(folder: Path = DATA_DIR) -> tuple[list[bytes], dict[str, Any] | None, dict[str, dict[str, Any]]]:
    """The pinned keys and the bundled snapshot, verified as a fetch is: (keys, index, shards), or no index if it
    fails (it never should; the catalog is empty until the first fetch then). Runs in the executor."""
    keys = load_keys(folder / "keys")
    snapshot = folder / "snapshot"
    try:
        index = verify_index((snapshot / "index.json").read_bytes(), (snapshot / "index.json.sig").read_bytes(), keys)
        shards = {
            name: check_shard(name, digest, (snapshot / path).read_bytes())
            for name, (path, digest) in shard_list(index).items()
        }
    except (OSError, CatalogError) as err:
        _LOGGER.warning("Hearth's bundled app catalog can't be used: %s", err)
        return keys, None, {}
    return keys, index, shards


# Keys


def normalize_name(name: str) -> str:
    """The catalog's name normalizer (glint-recipes catalog/normalize-vectors.json pins it)."""
    for mark in ("™", "®", "©"):
        name = name.replace(mark, "")
    name = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c)).lower()
    name = name.strip()
    for suffix in (" for nintendo switch", " nintendo switch edition", " - nintendo switch", " standard edition", " edition"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    return re.sub(r"[^a-z0-9]+", " ", name).strip()


def catalog_keys(item: str, platforms: tuple[str, ...] = NAME_PLATFORMS) -> list[str]:
    """The catalog keys an item Hearth counts under is looked up by (best first); none for a win32: program, a
    household's title or anything else the catalog can't know."""
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


def proposable_key(item: str) -> str | None:
    """The key an item could be sent to the relay under (a public store id), else None."""
    keys = catalog_keys(item)
    return keys[0] if len(keys) == 1 and keys[0].split(":", 1)[0] in PROPOSABLE else None


def correctable_key(item: str) -> str | None:
    """The key an adult's correction of an item could be shared under (an Android package or a public store id)."""
    keys = catalog_keys(item)
    return keys[0] if len(keys) == 1 and keys[0].split(":", 1)[0] in ("android", *PROPOSABLE) else None


@dataclass(frozen=True)
class Hit:
    """What the catalog says an item is."""

    key: str
    confirmed: bool
    category: str | None
    detail: str | None
    name: str | None = None

    @property
    def value(self) -> str | None:
        """The finer value first (detail), then the category."""
        return self.detail or self.category


def _clean(entry: Any) -> dict[str, Any] | None:
    if not isinstance(entry, dict):
        return None
    category = entry.get("category") if entry.get("category") in APP_CATEGORIES else None
    detail = entry.get("detail") if entry.get("detail") in DETAILS else None
    app = entry.get("app") if isinstance(entry.get("app"), str) else None
    name = entry.get("name")[:64] if isinstance(entry.get("name"), str) else None
    return {"category": category, "detail": detail, "app": app, "name": name, "confirmed": entry.get("state") == "confirmed"}


class CatalogData:
    """The catalog's keys, looked up by key and by app slug."""

    def __init__(self, shards: dict[str, dict[str, Any]] | None = None) -> None:
        self.keys: dict[str, dict[str, Any]] = {}
        self.by_app: dict[str, list[str]] = {}
        for name, keys in (shards or {}).items():
            if name not in SHARDS:
                continue
            for key, entry in keys.items():
                if not isinstance(key, str) or not key.startswith(f"{name}:"):
                    continue
                if (clean := _clean(entry)) is not None:
                    self.keys[key] = clean
        for key in sorted(self.keys):
            if app := self.keys[key]["app"]:
                self.by_app.setdefault(app, []).append(key)

    def __len__(self) -> int:
        return len(self.keys)

    def has(self, key: str) -> bool:
        return key in self.keys

    def _hit(self, key: str) -> Hit | None:
        e = self.keys[key]
        if e["category"] is None and e["detail"] is None:
            return None
        return Hit(key, e["confirmed"], e["detail"] and DETAILS[e["detail"]] if e["category"] is None else e["category"],
                   e["detail"], e["name"])

    def lookup(self, item: str) -> Hit | None:
        """What the catalog says [item] is: a confirmed answer by its key, then by its app's other keys; else a
        suggested one the same way; else None."""
        direct = [k for k in catalog_keys(item) if k in self.keys]
        if not direct:
            return None
        siblings: list[str] = []
        for key in direct:
            for other in self.by_app.get(self.keys[key]["app"] or "", []):
                if other not in direct and other not in siblings:
                    siblings.append(other)
        hits = [h for k in direct + siblings if (h := self._hit(k)) is not None]
        return next((h for h in hits if h.confirmed), None) or next(iter(hits), None)


# Keeping and fetching


class CatalogKeeper:
    """The household's copy of the catalog (fetched, verified and kept), and what may be sent upward."""

    def __init__(self, hass: HomeAssistant, entry_id: str, options: dict[str, Any]) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.catalog.{entry_id}")
        self.fetch_on = options.get(CONF_CATALOG_FETCH, True) is not False
        self.share_on = bool(options.get(CONF_CATALOG_SHARE))
        self.url = _base(options.get(CONF_CATALOG_URL) or DEFAULT_URL)
        self.relay = _base(options.get(CONF_CATALOG_RELAY) or DEFAULT_RELAY)
        self.keys: list[bytes] = []
        self.data = CatalogData()
        self.seq: int | None = None
        self.issued: str | None = None
        self.etag: str | None = None
        self.fetched: str | None = None
        self.origin = "none"  # "bundled" or "fetched"
        self.error: str | None = None
        self._raw: dict[str, dict[str, Any]] = {}
        self._digests: dict[str, str] = {}
        # Upward: public store ids seen (key -> last seen, ISO date), corrections an adult chose to share, and keys
        # sent lately (key -> when)
        self.candidates: dict[str, str] = {}
        self.corrections: list[dict[str, str]] = []
        self.sent: dict[str, str] = {}
        self.next_send: str | None = None
        self.on_change: Callable[[], None] | None = None
        self._unsubs: list[Callable[[], None]] = []

    # Store

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        # Read once per Home Assistant run (a reload doesn't read the files again)
        bundled = self.hass.data.get(_BUNDLED)
        if bundled is None:
            bundled = self.hass.data[_BUNDLED] = await self.hass.async_add_executor_job(read_bundled)
        self.keys, index, shards = bundled
        bundled_seq = index["seq"] if index else None
        if stored.get("shards") is not None and (bundled_seq is None or (stored.get("seq") or 0) >= bundled_seq):
            self._raw = stored["shards"]
            self._digests = dict(stored.get("digests") or {})
            self.seq, self.issued = stored.get("seq"), stored.get("issued")
            self.etag, self.fetched = stored.get("etag"), stored.get("fetched")
            self.origin = stored.get("origin", "fetched")
        elif index is not None:
            # First run (or a newer integration than the copy): the bundled snapshot
            self._use(index, shards, {n: d for n, (_p, d) in shard_list(index).items()}, origin="bundled")
            self.fetched = stored.get("fetched")
        self.data = CatalogData(self._raw)
        if self.share_on:
            self.candidates = dict(stored.get("candidates") or {})
            self.corrections = list(stored.get("corrections") or [])[-MAX_CORRECTIONS:]
            self.sent = dict(stored.get("sent") or {})
            self.next_send = stored.get("next_send")
        elif stored.get("candidates") or stored.get("corrections"):
            # Turned off: nothing waits to be sent
            self._save()

    def _data(self) -> dict[str, Any]:
        return {
            "seq": self.seq,
            "issued": self.issued,
            "etag": self.etag,
            "fetched": self.fetched,
            "origin": self.origin,
            "digests": self._digests,
            "shards": self._raw,
            "candidates": self.candidates,
            "corrections": self.corrections,
            "sent": self.sent,
            "next_send": self.next_send,
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def _use(self, index: dict[str, Any], shards: dict[str, dict[str, Any]], digests: dict[str, str], origin: str) -> None:
        self._raw, self._digests = shards, digests
        self.seq = index["seq"]
        self.issued = index.get("issued") if isinstance(index.get("issued"), str) else None
        self.origin = origin
        self.data = CatalogData(shards)

    # Timing

    @callback
    def start(self, run: Callable[[Any], Any]) -> None:
        """Fetches once a day at a random time (and soon, if the copy is over a day old) and maybe sends once a week,
        through [run] (the entry's task runner)."""
        rng = random.SystemRandom()

        @callback
        def daily(_now=None) -> None:
            run(self.async_daily())

        self._unsubs.append(
            async_track_time_change(self.hass, daily, hour=rng.randrange(24), minute=rng.randrange(60), second=rng.randrange(60))
        )
        if self.fetch_on and self.stale():
            self._unsubs.append(async_call_later(self.hass, rng.uniform(60, 600), daily))

    @callback
    def stop(self) -> None:
        while self._unsubs:
            self._unsubs.pop()()

    def stale(self, now: datetime | None = None) -> bool:
        fetched = dt_util.parse_datetime(self.fetched) if self.fetched else None
        return fetched is None or (now or dt_util.utcnow()) - fetched > STALE

    async def async_daily(self) -> None:
        if self.fetch_on:
            await self.async_fetch()
        if self.share_on:
            await self.async_maybe_send()

    async def _get(self, url: str, headers: dict[str, str] | None = None) -> tuple[int, bytes, str | None]:
        import aiohttp

        session = async_get_clientsession(self.hass)
        async with session.get(
            url, headers={"User-Agent": USER_AGENT, **(headers or {})}, timeout=aiohttp.ClientTimeout(total=TIMEOUT_S)
        ) as resp:
            if resp.status != 200:
                return resp.status, b"", None
            data = await resp.content.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise CatalogError(f"{url} is too large")
            return resp.status, data, resp.headers.get("ETag")

    async def async_fetch(self) -> bool:
        """Fetches and checks the catalog; True when a newer copy is now in use. Any failure keeps the copy."""
        try:
            headers = {"If-None-Match": self.etag} if self.etag and self.origin == "fetched" else {}
            status, index_bytes, etag = await self._get(self.url + "index.json", headers)
            if status == 304:
                self.fetched, self.error = dt_util.utcnow().isoformat(), None
                self._save()
                return False
            if status != 200:
                raise CatalogError(f"index.json answered {status}")
            status, sig, _ = await self._get(self.url + "index.json.sig")
            if status != 200:
                raise CatalogError(f"index.json.sig answered {status}")
            index = verify_index(index_bytes, sig, self.keys)
            check_seq(index, self.seq)
            listed = shard_list(index)
            shards: dict[str, dict[str, Any]] = {}
            for name, (path, digest) in listed.items():
                if self._digests.get(name) == digest and name in self._raw:
                    shards[name] = self._raw[name]
                    continue
                status, data, _ = await self._get(self.url + path)
                if status != 200:
                    raise CatalogError(f"{path} answered {status}")
                shards[name] = check_shard(name, digest, data)
        except CatalogError as err:
            self.error = str(err)
            _LOGGER.warning("Hearth kept its copy of the shared app catalog: %s", err)
            return False
        except Exception as err:  # noqa: BLE001 - offline, a timeout, a refused connection: the copy stays
            self.error = f"couldn't reach the catalog ({type(err).__name__})"
            _LOGGER.debug("Hearth couldn't fetch the shared app catalog: %s", err)
            return False
        changed = index["seq"] != self.seq or self.origin != "fetched"
        self._use(index, shards, {n: d for n, (_p, d) in listed.items()}, origin="fetched")
        self.etag, self.fetched, self.error = etag, dt_util.utcnow().isoformat(), None
        self._save()
        if changed and self.on_change is not None:
            self.on_change()
        return changed

    # Upward

    @callback
    def note_seen(self, items: dict[str, set[str]], may_share: Callable[[str], bool], never: Callable[[str], bool]) -> None:
        """Notes the public store ids the catalog lacks among [items] (item -> who it was seen on), when one of those
        may share (may_share) and the app isn't one never sent (never: a messaging app)."""
        if not self.share_on:
            return
        today = dt_util.now().date().isoformat()
        changed = False
        for item, people in items.items():
            key = proposable_key(item)
            if key is None or self.data.has(key) or never(item) or not any(may_share(p) for p in people):
                continue
            if self.candidates.get(key) != today:
                if key not in self.candidates and len(self.candidates) >= MAX_CANDIDATES:
                    continue
                self.candidates[key] = today
                changed = True
        if changed:
            self._save()

    @callback
    def queue_correction(self, key: str, category: str | None, detail: str | None) -> bool:
        """An adult's correction to share (the catalog's key and value, never a pool); False when sharing is off."""
        if not self.share_on or (category is None and detail is None):
            return False
        correction = {"key": key} | ({"category": category} if category else {}) | ({"detail": detail} if detail else {})
        self.corrections = [c for c in self.corrections if c["key"] != key][-(MAX_CORRECTIONS - 1):] + [correction]
        self._save()
        return True

    def batch(self, now: datetime) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
        """What the next send carries: keys the catalog still lacks and that weren't sent lately, and corrections."""
        recent = {k for k, at in self.sent.items() if (when := dt_util.parse_datetime(at)) and now - when < RESEND_AFTER}
        keys = sorted(k for k in self.candidates if not self.data.has(k) and k not in recent)[:MAX_KEYS]
        corrections = sorted(self.corrections, key=lambda c: c["key"])[:MAX_CORRECTIONS]
        return [{"key": k} for k in keys], corrections

    async def async_maybe_send(self, now: datetime | None = None) -> str | None:
        """Sends once a week (at a random time within the day after the week is up); the outcome, else None."""
        now = now or dt_util.utcnow()
        due = dt_util.parse_datetime(self.next_send) if self.next_send else None
        if due is None:
            # The first week only starts the clock: nothing goes out the day sharing is turned on
            self._schedule_next(now)
            return None
        if now < due:
            return None
        outcome = await self.async_send(now)
        self._schedule_next(now)
        return outcome

    def _schedule_next(self, now: datetime) -> None:
        self.next_send = (now + SEND_EVERY + timedelta(seconds=random.SystemRandom().uniform(0, 86400))).isoformat()
        self._save()

    async def async_send(self, now: datetime | None = None) -> str:
        """One submission: "off", "nothing", "sent", "absent" (the relay has no /propose yet: nothing changes),
        "refused" (dropped, not resent), "busy" or "failed" (kept for next time)."""
        import aiohttp

        now = now or dt_util.utcnow()
        # Forget what wasn't seen for a while, and what was sent long ago
        self.candidates = {
            k: d for k, d in self.candidates.items()
            if (day := dt_util.parse_date(d)) is not None and now.date() - day < FORGET_AFTER
        }
        self.sent = {k: at for k, at in self.sent.items() if (w := dt_util.parse_datetime(at)) and now - w < RESEND_AFTER}
        if not self.share_on:
            return "off"
        keys, corrections = self.batch(now)
        if not keys and not corrections:
            return "nothing"
        session = async_get_clientsession(self.hass)
        headers = {"User-Agent": USER_AGENT, "Content-Type": "application/json"}
        timeout = aiohttp.ClientTimeout(total=TIMEOUT_S)
        try:
            async with session.post(self.relay + "challenge", json={"format": PROPOSE_FORMAT}, headers=headers,
                                    timeout=timeout) as resp:
                if resp.status == 404:
                    return "absent"
                if resp.status != 200:
                    return "busy" if resp.status == 429 else "failed"
                token = (await resp.json(content_type=None) or {}).get("token")
            if not isinstance(token, str) or not token:
                return "failed"
            body = {"format": PROPOSE_FORMAT, "optIn": True, "token": token, "keys": keys, "corrections": corrections}
            async with session.post(self.relay + "propose", json=body, headers=headers, timeout=timeout) as resp:
                status = resp.status
        except Exception as err:  # noqa: BLE001 - offline or the relay down: it waits for next week
            _LOGGER.debug("Hearth couldn't reach the catalog's relay: %s", err)
            return "failed"
        if status == 404:
            _LOGGER.debug("The catalog's relay takes no proposals yet; Hearth's wait")
            return "absent"
        if status == 429:
            return "busy"
        if status in (200, 202, 400, 403):
            # Taken (or refused: never resent as it is)
            for k in keys:
                self.sent[k["key"]] = now.isoformat()
                self.candidates.pop(k["key"], None)
            sent = {c["key"] for c in corrections}
            self.corrections = [c for c in self.corrections if c["key"] not in sent]
            self._save()
            return "sent" if status in (200, 202) else "refused"
        return "failed"

    def page(self) -> dict[str, Any]:
        """For Hearth's page: the copy in use and the setting."""
        return {
            "fetch": self.fetch_on,
            "share": self.share_on,
            "seq": self.seq,
            "issued": self.issued,
            "fetched": self.fetched,
            "origin": self.origin,
            "keys": len(self.data),
            "error": self.error,
            "waiting": {"keys": len(self.candidates), "corrections": len(self.corrections)},
        }


def _base(url: str) -> str:
    return url if url.endswith("/") else url + "/"
