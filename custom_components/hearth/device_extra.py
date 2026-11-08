"""Extra time on one device (docs/home-assistant-integration.md, Extra time on one device): hearth.add_bonus and
hearth.allow with a `device` (a target id, targets.py). The person's shared pool keeps counting, and every other
device still reads it; only that device may go past it, today.

    bonus  N more minutes there from now, pool or not, till midnight at most
    allow  a group open there until a time

What it does depends on the device:

- A Hearth TV or phone (hearth:<id>): that device's state document shows the group with the minutes it has left
  there (a bonus: N less what that device used of the group since; an allow: the group isn't held there).
- A Family Link device (fl:<id>): a Family Link bonus on that device (add_time_bonus), as Hearth gives for an allow
  of All screen time, so Google's own limit (the one Hearth sets to 0 when All screen time is out) lets that device
  alone go on; Google counts it down. Family Link's app pauses are the child's, every device's, so only All screen
  time can be given on one Family Link device.
- A Family Safety platform (fs:xbox, fs:windows): Hearth's lock of that platform is let go while it lasts, and
  Microsoft's own allowance gets extra time until then where it would stop it. By the clock: N minutes from now.
- A Switch (nintendo:<entity>): Hearth's hold of the Switch is let go while it lasts (the Switch's own limit, put
  back, still applies). By the clock: N minutes from now.

Kept with Home Assistant's storage helper for today; a new day starts empty.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import secrets
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

BONUS = "bonus"
ALLOW = "allow"


@dataclass
class DeviceExtra:
    id: str
    person: str
    target: str
    via: str
    kind: str
    group: str
    until: datetime
    minutes: int | None = None
    # A Hearth device's bonus: that device's seconds in the group when it was given
    base_s: float = 0.0
    reason: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "person": self.person,
            "target": self.target,
            "via": self.via,
            "kind": self.kind,
            "group": self.group,
            "until": self.until.isoformat(),
            "minutes": self.minutes,
            "base_s": self.base_s,
            "reason": self.reason,
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> DeviceExtra | None:
        until = dt_util.parse_datetime(raw.get("until") or "")
        if until is None:
            return None
        return cls(
            raw["id"], raw["person"], raw["target"], raw["via"], raw["kind"], raw["group"], until,
            raw.get("minutes"), float(raw.get("base_s") or 0.0), raw.get("reason") or "",
        )


class DeviceExtras:
    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.device_extra.{entry_id}")
        self.extras: dict[str, DeviceExtra] = {}
        self.day: str | None = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        for raw in stored.get("extras", []):
            if (extra := DeviceExtra.from_dict(raw)) is not None:
                self.extras[extra.id] = extra

    def _data(self) -> dict[str, Any]:
        return {"day": self.day, "extras": [e.to_dict() for e in self.extras.values()]}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 5)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def add(
        self,
        person: str,
        target: str,
        via: str,
        kind: str,
        group: str,
        until: datetime,
        minutes: int | None = None,
        base_s: float = 0.0,
        reason: str | None = None,
    ) -> DeviceExtra:
        self.prune()
        extra = DeviceExtra(
            f"dx_{secrets.token_hex(5)}", person, target, via, kind, group, until, minutes, base_s, (reason or "")[:80]
        )
        self.extras[extra.id] = extra
        self._save()
        return extra

    def prune(self, now: datetime | None = None) -> bool:
        now = now or dt_util.now()
        today = now.date().isoformat()
        gone = [k for k, e in self.extras.items() if e.until <= now or self.day != today]
        self.day = today
        for key in gone:
            del self.extras[key]
        if gone:
            self._save()
        return bool(gone)

    def of(self, person: str, target: str | None = None) -> list[DeviceExtra]:
        now = dt_util.now()
        return [
            e
            for e in sorted(self.extras.values(), key=lambda e: (e.until, e.id))
            if e.person == person and e.until > now and (target is None or e.target == target)
        ]

    def end(self, extra_id: str | None, people: list[str] | None, target: str | None) -> list[DeviceExtra]:
        ended = [
            e
            for e in self.extras.values()
            if (extra_id is None or e.id == extra_id)
            and (people is None or e.person in people)
            and (target is None or e.target == target)
        ]
        for extra in ended:
            del self.extras[extra.id]
        if ended:
            self._save()
        return ended
