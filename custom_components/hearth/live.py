"""Live play: what people are playing now, timed, and when they're playing the same title together.

Each look (recompute, at least once a minute and whenever a live sensor or device changes) is a set of observations:
a person playing an item on a device. Live sources' time accrues between two looks that saw the same item (a source
that skips a look loses that minute, never gains one). Hearth devices' items aren't timed here (their own counts are
better) but count for "together". Two or more people on the same title (or the same item, when no title matches) are
playing together; each one's together time accrues the same way. Kept across restarts; starts again each local day.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

# A look this long after the last one doesn't add the time between (Home Assistant was stopped, say)
MAX_GAP_S = 180


@dataclass(frozen=True)
class Observation:
    person: str
    device: str
    item: str  # a title key, or the app or played name
    source: str | None  # a live source's reading name, when it's timed here; None for a Hearth device
    label: str  # how to show it (the title's name, the app's)


@dataclass
class Together:
    key: str
    label: str
    people: list[str]
    devices: list[str]
    since: str


class LiveTracker:
    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.live.{entry_id}")
        self.day: str | None = None
        # source -> item -> seconds today
        self.seconds: dict[str, dict[str, float]] = {}
        # person -> seconds together today
        self.together_s: dict[str, float] = {}
        self._last: datetime | None = None
        self._last_seen: set[tuple[str, str]] = set()  # (source, item) seen at the last look
        self._last_together: dict[str, set[str]] = {}  # key -> people
        self.together: dict[str, Together] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.seconds = stored.get("seconds", {})
        self.together_s = stored.get("together_s", {})

    def _data(self) -> dict[str, Any]:
        return {"day": self.day, "seconds": self.seconds, "together_s": self.together_s}

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def look(self, now: datetime, today: date, observations: list[Observation]) -> tuple[list[Together], list[Together]]:
        """Takes a look; answers the togethers that started and ended since the last."""
        if self.day != today.isoformat():
            self.day = today.isoformat()
            self.seconds = {}
            self.together_s = {}
        elapsed = (now - self._last).total_seconds() if self._last else 0.0
        if elapsed < 0 or elapsed > MAX_GAP_S:
            elapsed = 0.0

        seen = {(o.source, o.item) for o in observations if o.source}
        for source, item in seen & self._last_seen:
            by_item = self.seconds.setdefault(source, {})
            by_item[item] = by_item.get(item, 0.0) + elapsed

        # Together: two or more people on the same item now
        people_on: dict[str, set[str]] = {}
        for o in observations:
            people_on.setdefault(o.item, set()).add(o.person)
        now_together = {key: people for key, people in people_on.items() if len(people) >= 2}
        for key, people in now_together.items():
            for person in people & self._last_together.get(key, set()):
                self.together_s[person] = self.together_s.get(person, 0.0) + elapsed

        started: list[Together] = []
        current: dict[str, Together] = {}
        for key, people in now_together.items():
            label = next(o.label for o in observations if o.item == key)
            devices = sorted({o.device for o in observations if o.item == key})
            previous = self.together.get(key)
            together = Together(
                key, label, sorted(people), devices, previous.since if previous else dt_util.as_utc(now).isoformat()
            )
            current[key] = together
            if previous is None:
                started.append(together)
        ended = [t for key, t in self.together.items() if key not in current]

        self.together = current
        self._last_together = now_together
        self._last_seen = seen
        self._last = now
        self._store.async_delay_save(self._data, 60)
        return started, ended
