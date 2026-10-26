"""Screen time sources: other integrations' entities the household adds (see docs/home-assistant-integration.md).

Two sorts:

- **Totals**: a sensor of time today (Family Link's Daily Screen Time, Family Safety's Screen Time, Nintendo's Used
  screen time). Its state is the time; an `apps` attribute of `{"package", "minutes"}` (Family Link's) breaks it down.
- **Live**: a sensor whose state is what's being played now (Xbox's Now playing, a Switch presence Game sensor), or
  empty. The integration times it (live.py).

A source can be "the same device" as a Hearth device or another source, so their minutes are counted once.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any

from homeassistant.const import STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant

from .counting import Reading

CONF_SOURCES = "sources"
CONF_TITLES = "titles"

# A live sensor saying one of these isn't playing anything
NOT_PLAYING = {"", "none", "offline", "online", "idle", "home", "away", "not playing", STATE_UNKNOWN, STATE_UNAVAILABLE}

_UNITS = {"s": 1, "sec": 1, "min": 60, "h": 3600, "hr": 3600, "d": 86400}


@dataclass(frozen=True)
class Source:
    id: str
    entity_id: str
    person: str
    name: str
    live: bool = False
    # Another source's id, or "hearth:<device_id>": the same device, counted once
    same_as: str | None = None
    # The group its time is in when it can't say which app (games, for a Switch or Xbox)
    group: str | None = None

    @property
    def reading_source(self) -> str:
        return f"{'live' if self.live else 'source'}:{self.id}"


def sources_from_options(options: dict[str, Any]) -> list[Source]:
    return [
        Source(
            id=s["id"],
            entity_id=s["entity_id"],
            person=s["person"],
            name=s.get("name") or s["entity_id"],
            live=bool(s.get("live")),
            same_as=s.get("same_as") or None,
            group=s.get("group") or None,
        )
        for s in options.get(CONF_SOURCES, [])
    ]


def device_key(source: Source, sources: dict[str, Source]) -> str:
    """The device a source's time is on: followed through "same as" (a Hearth device is its own id)."""
    seen: set[str] = set()
    current = source
    while current.same_as and current.id not in seen:
        seen.add(current.id)
        if current.same_as.startswith("hearth:"):
            return current.same_as.removeprefix("hearth:")
        nxt = sources.get(current.same_as)
        if nxt is None:
            break
        current = nxt
    return f"source:{current.id}"


def _seconds(value: Any, unit: str | None) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or number < 0:
        return None
    return number * _UNITS.get((unit or "min").lower(), 60)


def totals_reading(hass: HomeAssistant, source: Source) -> Reading | None:
    """A totals source's reading now; None while its sensor has no number."""
    state = hass.states.get(source.entity_id)
    if state is None:
        return None
    total = _seconds(state.state, state.attributes.get("unit_of_measurement"))
    if total is None:
        return None
    items: dict[str, float] = {}
    apps = state.attributes.get("apps")
    if isinstance(apps, list):
        for app in apps[:200]:
            if not isinstance(app, dict):
                continue
            package = app.get("package") or app.get("name")
            seconds = _seconds(app.get("minutes"), "min")
            if seconds is None:
                seconds = _seconds(app.get("seconds"), "s")
            if isinstance(package, str) and package and seconds is not None:
                items[package[:128]] = max(items.get(package[:128], 0.0), seconds)
    return Reading(source.reading_source, min(total, 86400.0), items, source.group)


def now_playing(hass: HomeAssistant, source: Source) -> str | None:
    """What a live source says is being played, or None."""
    state = hass.states.get(source.entity_id)
    if state is None:
        return None
    value = (state.state or "").strip()
    if value.lower() in NOT_PLAYING:
        return None
    return value[:128]


def normalize(name: str) -> str:
    """A name for matching: lower case, letters and digits, without "edition" and trademark marks."""
    name = name.lower().replace("™", "").replace("®", "")
    name = re.sub(r"\b(edition|for nintendo switch|nintendo switch 2 edition|java|bedrock)\b", " ", name)
    return re.sub(r"[^a-z0-9]+", " ", name).strip()


@dataclass(frozen=True)
class Title:
    id: str
    name: str
    matches: frozenset[str]  # normalized names and packages
    raw: tuple[str, ...] = ()  # as the adult chose them (packages, played names)


def titles_from_options(options: dict[str, Any]) -> list[Title]:
    return [
        Title(
            t["id"],
            t["name"],
            frozenset(normalize(m) for m in [t["name"], *t.get("matches", [])]),
            tuple(t.get("matches", [])),
        )
        for t in options.get(CONF_TITLES, [])
    ]


def title_key(titles: list[Title], item: str) -> str:
    """The key an app or played name counts under: its title's, when one matches."""
    wanted = normalize(item)
    for title in titles:
        if wanted in title.matches:
            return f"title:{title.id}"
    return item
