"""Exceptions: an adult lets a person use an app or a group for a while (hearth.allow), and why something is held
(hearth.explain). See docs/home-assistant-integration.md, Exceptions.

An allow names people, one app (a package) or one group (a Hearth group, or "all"), until when (a time, the end of
their School time today, or the end of the day) and why. While it lasts, Hearth doesn't hold that app or group for
those people anywhere it holds things: their TVs' and phones' state documents (the group is left out, the app is taken
out of every group's apps and added to All screen time's exceptions), Family Link (the budget hold and the School-time
pause), Family Safety and Nintendo (for a group they hold). Bedtime, School time itself and a family pause still lock
the person: an allow lifts Hearth's holds, not those locks (a TV can't open one app through a lock without a TV-side
change, and Family Link's own bedtime still locks the phone). It ends on its own (or with hearth.allow_end), and what
should hold then is held again with the next recompute.

Allows are kept with Home Assistant's storage helper, so they survive a restart.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, time, timedelta
import secrets
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .counting import ALL

SCHOOL_TIME_END = "school_time_end"
END_OF_DAY = "end_of_day"
MAX_REASON = 120
MAX_ALLOWS = 200


@dataclass
class Allow:
    id: str
    # person -> when it ends for them
    until: dict[str, datetime]
    app: str | None = None
    group: str | None = None
    reason: str = ""
    created: datetime = field(default_factory=dt_util.utcnow)
    # Ends for a person sooner when their place says so: {"arrive": <place key>} or {"leave": <place key>} (places.py)
    ends_on: dict[str, str] | None = None

    def view(self, person: str | None = None) -> dict[str, Any]:
        people = [person] if person else sorted(self.until)
        return {
            "id": self.id,
            "people": people,
            "app": self.app,
            "group": self.group,
            "until": (
                dt_util.as_local(self.until[person]).isoformat()
                if person
                else {p: dt_util.as_local(u).isoformat() for p, u in sorted(self.until.items())}
            ),
            "reason": self.reason,
            # Only when it has one, so an allow without it looks as before
            **({"ends_on": dict(self.ends_on)} if self.ends_on else {}),
        }


def end_of_day(now: datetime) -> datetime:
    return dt_util.start_of_local_day(now + timedelta(days=1))


def at_time(now: datetime, when: time) -> datetime:
    """Today's [when], or tomorrow's when it has passed."""
    at = dt_util.as_local(now).replace(hour=when.hour, minute=when.minute, second=0, microsecond=0)
    return at if at > now else at + timedelta(days=1)


class Allows:
    """The household's allows, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.exceptions.{entry_id}")
        self.allows: dict[str, Allow] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for raw in stored.get("allows", []):
            until = {
                person: parsed
                for person, value in (raw.get("until") or {}).items()
                if (parsed := dt_util.parse_datetime(value)) is not None
            }
            if until and raw.get("id"):
                self.allows[raw["id"]] = Allow(
                    raw["id"], until, raw.get("app"), raw.get("group"), raw.get("reason") or "",
                    dt_util.parse_datetime(raw.get("created") or "") or dt_util.utcnow(),
                    dict(raw["ends_on"]) if isinstance(raw.get("ends_on"), dict) and raw["ends_on"] else None,
                )

    def _data(self) -> dict[str, Any]:
        return {
            "allows": [
                {
                    "id": a.id,
                    "until": {p: u.isoformat() for p, u in a.until.items()},
                    "app": a.app,
                    "group": a.group,
                    "reason": a.reason,
                    "created": a.created.isoformat(),
                    "ends_on": a.ends_on,
                }
                for a in self.allows.values()
            ]
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def add(
        self,
        until: dict[str, datetime],
        app: str | None,
        group: str | None,
        reason: str | None,
        ends_on: dict[str, str] | None = None,
    ) -> Allow:
        self.prune()
        if len(self.allows) >= MAX_ALLOWS:
            # The oldest goes: a runaway automation mustn't grow this without end
            del self.allows[min(self.allows.values(), key=lambda a: a.created).id]
        allow = Allow(
            secrets.token_hex(6), until, app, group, (reason or "").strip()[:MAX_REASON], ends_on=ends_on or None
        )
        self.allows[allow.id] = allow
        self._save()
        return allow

    def end(self, allow_id: str | None, people: list[str] | None, app: str | None, group: str | None) -> list[str]:
        """Ends one by its id, or the people's (those of an app or a group, when given); says which ended."""
        ended: list[str] = []
        for allow in list(self.allows.values()):
            if allow_id is not None:
                if allow.id != allow_id:
                    continue
                del self.allows[allow.id]
                ended.append(allow.id)
                continue
            if app is not None and allow.app != app:
                continue
            if group is not None and allow.group != group:
                continue
            gone = [p for p in allow.until if people is None or p in people]
            if not gone:
                continue
            for person in gone:
                del allow.until[person]
            if not allow.until:
                del self.allows[allow.id]
            ended.append(allow.id)
        if ended:
            self._save()
        return ended

    def end_for(self, allow_id: str, person: str) -> bool:
        """Ends one allow for one person (their place said so); the others' part goes on."""
        allow = self.allows.get(allow_id)
        if allow is None or person not in allow.until:
            return False
        del allow.until[person]
        if not allow.until:
            del self.allows[allow_id]
        self._save()
        return True

    def prune(self, now: datetime | None = None) -> bool:
        """Drops what has ended; says whether anything did."""
        now = now or dt_util.utcnow()
        changed = False
        for allow in list(self.allows.values()):
            for person in [p for p, u in allow.until.items() if u <= now]:
                del allow.until[person]
                changed = True
            if not allow.until:
                del self.allows[allow.id]
        if changed:
            self._save()
        return changed

    def of(self, person: str, now: datetime | None = None) -> list[Allow]:
        now = now or dt_util.utcnow()
        return sorted(
            (a for a in self.allows.values() if person in a.until and a.until[person] > now),
            key=lambda a: a.created,
        )

    def lifted(self, person: str, now: datetime | None = None) -> Lifted:
        """What the person's allows lift now."""
        found = Lifted()
        for allow in self.of(person, now):
            if allow.group == ALL:
                found.everything = True
            elif allow.group:
                found.groups.add(allow.group)
            elif allow.app:
                found.apps.add(allow.app)
        return found


@dataclass
class Lifted:
    """What a person's allows lift: every hold (All), some groups, some apps."""

    everything: bool = False
    groups: set[str] = field(default_factory=set)
    apps: set[str] = field(default_factory=set)

    def group(self, group_id: str) -> bool:
        return self.everything or group_id in self.groups

    def app(self, package: str, groups_of_app: set[str] | None = None) -> bool:
        """The app is allowed: itself, its group, or everything."""
        return self.everything or package in self.apps or bool(groups_of_app and groups_of_app & self.groups)

    def __bool__(self) -> bool:
        return self.everything or bool(self.groups) or bool(self.apps)
