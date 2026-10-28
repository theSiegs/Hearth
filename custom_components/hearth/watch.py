"""A kids profile's YouTube, for the parents: the videos it started in HearthTube (Hearth posts them to the events
endpoint) and what a parent blocked for it here (handed to the TVs in the state document, as youtube_blocks).

Kept per person: a kid on two TVs is one log. Home Assistant never holds the only copy: each TV's Hearth and HearthTube
keep their own. See HearthTube's docs/parent-channel.md.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import re
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import EVENT_VIDEO_STARTED, SIGNAL_WATCH
from .status import number, text

# The newest this many per person, like HearthTube and Hearth
MAX_LOG = 2000
# The sensor's attribute and the dashboard's list
RECENT = 50
MAX_BLOCKS = 1000
MAX_WORD = 100
# What a post may carry
MAX_EVENTS = 50

VIDEOS = "videos"
CHANNELS = "channels"
WORDS = "words"
KINDS = (VIDEOS, CHANNELS, WORDS)

_ID = re.compile(r"^[A-Za-z0-9_-]{5,40}$")
_VIDEO_URL = re.compile(r"(?:[?&]v=|youtu\.be/|/shorts/|/live/|/embed/)([A-Za-z0-9_-]{11})")
_CHANNEL_URL = re.compile(r"/channel/(UC[A-Za-z0-9_-]{22})")
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
# Before this, a time is a mistake (2020-01-01)
_EARLIEST_MS = 1_577_836_800_000


def video_url(video_id: str) -> str:
    return f"https://www.youtube.com/watch?v={video_id}"


def channel_url(channel_id: str) -> str:
    return f"https://www.youtube.com/channel/{channel_id}"


def video_id_of(value: str) -> str | None:
    """A video id, also out of a YouTube link (watch, youtu.be, shorts, live, embed)."""
    value = value.strip()
    if found := _VIDEO_URL.search(value):
        return found.group(1)
    return value if _ID.match(value) else None


def channel_id_of(value: str) -> str | None:
    """A channel id ("UC..."), also out of a /channel/ link; a handle (@name) can't be turned into one here."""
    value = value.strip()
    if found := _CHANNEL_URL.search(value):
        return found.group(1)
    return value if _ID.match(value) and not value.startswith("@") else None


def clean_word(value: Any) -> str | None:
    """A word to block, as HearthTube matches it: lower case, trimmed, no control characters."""
    if not isinstance(value, str):
        return None
    word = _CONTROL.sub(" ", value).strip().lower()
    return word if word and len(word) <= MAX_WORD else None


def clean_started(raw: Any, now_ms: int) -> dict[str, Any] | None:
    """One started video from a device, made safe; None when it isn't one."""
    if not isinstance(raw, dict) or raw.get("type") != "video_started":
        return None
    time_ms = number(raw.get("t"), _EARLIEST_MS, now_ms + 24 * 3600 * 1000)
    video_id = raw.get("v")
    profile_id = text(raw.get("profile_id"), 128)
    if time_ms is None or not isinstance(video_id, str) or not _ID.match(video_id) or not profile_id:
        return None
    channel_id = raw.get("cid")
    return {
        "profile_id": profile_id,
        "t": time_ms,
        "v": video_id,
        "title": text(raw.get("title")) or "",
        "ch": text(raw.get("ch")) or "",
        "cid": channel_id if isinstance(channel_id, str) and _ID.match(channel_id) else "",
    }


def _readable(entry: dict[str, Any]) -> dict[str, Any]:
    """An entry as services, events and the sensor show it."""
    return {
        "time": dt_util.as_local(dt_util.utc_from_timestamp(entry["t"] / 1000)).isoformat(),
        "video_id": entry["v"],
        "title": entry.get("title", ""),
        "channel": entry.get("ch", ""),
        "channel_id": entry.get("cid", ""),
        "url": video_url(entry["v"]),
        "device": entry.get("device", ""),
    }


class WatchLog:
    """Every person's started videos and blocked lists, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.watch.{entry_id}")
        # person -> entries, oldest first: {"t", "v", "title", "ch", "cid", "device"}
        self.logs: dict[str, list[dict[str, Any]]] = {}
        # person -> kind -> item -> {"label", "at"} (words have no label)
        self.blocks: dict[str, dict[str, dict[str, dict[str, Any]]]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        logs = stored.get("logs")
        blocks = stored.get("blocks")
        self.logs = logs if isinstance(logs, dict) else {}
        self.blocks = blocks if isinstance(blocks, dict) else {}

    def _data(self) -> dict[str, Any]:
        return {"logs": self.logs, "blocks": self.blocks}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # The log

    def add_started(self, person: str, entry: dict[str, Any], device: str) -> bool:
        """Adds a started video to the person's log; False when it is there already (a resend)."""
        entries = self.logs.setdefault(person, [])
        for have in reversed(entries):
            if have["t"] < entry["t"]:
                break
            if have["t"] == entry["t"] and have["v"] == entry["v"]:
                return False
        kept = {key: entry[key] for key in ("t", "v", "title", "ch", "cid")}
        kept["device"] = device
        at = len(entries)
        while at > 0 and entries[at - 1]["t"] > entry["t"]:
            at -= 1
        entries.insert(at, kept)
        del entries[: max(0, len(entries) - MAX_LOG)]
        self._save()
        self.hass.bus.async_fire(EVENT_VIDEO_STARTED, {"person": person, **_readable(kept)})
        return True

    def changed(self) -> None:
        async_dispatcher_send(self.hass, SIGNAL_WATCH)

    def recent(self, person: str, limit: int = RECENT, since: datetime | None = None) -> list[dict[str, Any]]:
        """The person's entries, newest first."""
        since_ms = int(since.timestamp() * 1000) if since else None
        out: list[dict[str, Any]] = []
        for entry in reversed(self.logs.get(person, [])):
            if len(out) >= limit or (since_ms is not None and entry["t"] < since_ms):
                break
            out.append(_readable(entry))
        return out

    def latest(self, person: str) -> dict[str, Any] | None:
        entries = self.logs.get(person)
        return _readable(entries[-1]) if entries else None

    # The lists

    def block(self, person: str, kind: str, item: str, label: str | None = None) -> bool:
        """Blocks a video id, channel id or word for the person; False when it was blocked or the list is full."""
        items = self.blocks.setdefault(person, {}).setdefault(kind, {})
        if item in items or len(items) >= MAX_BLOCKS:
            return False
        items[item] = {"at": dt_util.utcnow().isoformat()}
        if label and kind != WORDS:
            items[item]["label"] = text(label) or ""
        self._save()
        self.changed()
        return True

    def unblock(self, person: str, kind: str, item: str) -> bool:
        items = self.blocks.get(person, {}).get(kind, {})
        if items.pop(item, None) is None:
            return False
        self._save()
        self.changed()
        return True

    def blocks_document(self, person: str) -> dict[str, list[str]]:
        """What a TV is told for the person's profiles: the three lists, in the order they were blocked."""
        mine = self.blocks.get(person, {})
        return {kind: list(mine.get(kind, {})) for kind in KINDS}

    def blocked(self, person: str) -> dict[str, list[dict[str, Any]]]:
        """The person's lists with labels and when, for services and the dashboard."""
        mine = self.blocks.get(person, {})
        out: dict[str, list[dict[str, Any]]] = {}
        for kind in KINDS:
            out[kind] = [
                {
                    "id" if kind != WORDS else "word": item,
                    **({"label": info.get("label", "")} if kind != WORDS else {}),
                    **({"url": video_url(item) if kind == VIDEOS else channel_url(item)} if kind != WORDS else {}),
                    "blocked_at": info.get("at"),
                }
                for item, info in mine.get(kind, {}).items()
            ]
        return out

    # The weekly digest

    def digest(self, person: str, name: str, days: int) -> dict[str, Any]:
        """One document for the last [days]: what the person started, counted per channel and per day, and what a
        parent blocked meanwhile. The readable summary is for a phone; the rest for a reviewer agent."""
        until = dt_util.now()
        since = until - timedelta(days=days)
        entries = list(reversed(self.recent(person, MAX_LOG, since)))
        per_channel: dict[str, dict[str, Any]] = {}
        per_day: dict[str, int] = {}
        for entry in entries:
            key = entry["channel_id"] or entry["channel"] or "?"
            channel = per_channel.setdefault(
                key, {"channel": entry["channel"], "channel_id": entry["channel_id"], "videos": 0}
            )
            channel["videos"] += 1
            day = entry["time"][:10]
            per_day[day] = per_day.get(day, 0) + 1
        channels = sorted(per_channel.values(), key=lambda c: (-c["videos"], c["channel"].lower()))
        blocked_since = {
            kind: [b for b in items if (b.get("blocked_at") or "") >= since.astimezone(dt_util.UTC).isoformat()]
            for kind, items in self.blocked(person).items()
        }
        return {
            "person": person,
            "name": name,
            "from": since.isoformat(),
            "to": until.isoformat(),
            "videos_started": len(entries),
            "entries": entries,
            "per_channel": channels,
            "per_day": dict(sorted(per_day.items())),
            "blocked_in_period": blocked_since,
            "summary": _summary(name, days, entries, channels, blocked_since),
        }


def _summary(
    name: str,
    days: int,
    entries: list[dict[str, Any]],
    channels: list[dict[str, Any]],
    blocked: dict[str, list[dict[str, Any]]],
) -> str:
    """A few plain lines for a phone notification."""
    if not entries:
        lines = [f"{name}: no YouTube videos started in the last {days} days."]
    else:
        top = ", ".join(f"{c['channel'] or 'unknown'} ({c['videos']})" for c in channels[:5])
        lines = [
            f"{name}: {len(entries)} YouTube video{'s' if len(entries) != 1 else ''} started in the last {days} days, "
            f"from {len(channels)} channel{'s' if len(channels) != 1 else ''}.",
            f"Most: {top}.",
        ]
    count = sum(len(items) for items in blocked.values())
    if count:
        lines.append(f"Blocked in that time: {count}.")
    return "\n".join(lines)
