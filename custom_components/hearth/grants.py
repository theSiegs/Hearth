"""Parent grants: a parent's change in a first-party app (Family Link, Nintendo, Microsoft Family Safety) that lets a
kid use what Hearth holds. See docs/home-assistant-integration.md, Keeping the parents' apps in step.

A parent who gives bonus time or raises a limit in their own app has decided, as an adult: Hearth adopts it and doesn't
fight it. Such a change becomes a grant {id, person, via, target {kind, value}, until, reason, since}. It lifts only the
hold it came from (the Family Link device lock of that child, the paused app, the Switch, the Family Safety platform),
not a whole group everywhere as hearth.allow does, and budgets keep counting. It ends on its own (by the end of the
day, or when the bonus it came from is over); an adult may end one early with hearth.allow_end (its id), and enforcing
then goes on as usual.

Grants are kept with Home Assistant's storage helper, so they survive a restart.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
import secrets
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

# Where a grant came from (the enforcer kinds of enforce.py)
FAMILY_LINK = "family_link"
FAMILY_SAFETY = "family_safety"
NINTENDO = "nintendo"
SOURCES = {
    FAMILY_LINK: "from the Family Link app",
    FAMILY_SAFETY: "from the Family Safety app",
    NINTENDO: "from the Nintendo app",
}
# What a grant lifts: a child's Family Link devices (their lock), an app, a Family Safety platform, a Switch
DEVICE = "device"
APP = "app"
PLATFORM = "platform"
SWITCH = "switch"
# How an adult may end one early through the first-party app (None: Hearth can't undo it there, shown read-only)
END_RESET_BONUS = "family_link_reset_bonus"
END_RELOCK = "relock"
END_CANCEL_BONUS = "family_safety_cancel_bonus"
# Ends when the Family Link bonus it came from is over (as well as by [until])
WHILE_BONUS = "family_link_bonus"
MAX_GRANTS = 100


@dataclass
class Grant:
    id: str
    person: str
    via: str
    kind: str
    # The item the enforcer holds (enforce.py: Devices, a package, a platform, Switch)
    value: str
    until: datetime
    reason: str = ""
    since: datetime = field(default_factory=dt_util.utcnow)
    end_with: str | None = None
    ends_with: str | None = None

    def view(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "type": "grant",
            "person": self.person,
            "people": [self.person],
            "via": self.via,
            "source": SOURCES.get(self.via, self.via),
            "target": {"kind": self.kind, "value": self.value},
            "until": dt_util.as_local(self.until).isoformat(),
            "since": dt_util.as_local(self.since).isoformat(),
            "reason": self.reason,
            "endable": self.end_with is not None,
            "end_with": self.end_with,
        }


class Grants:
    """The household's parent grants, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.grants.{entry_id}")
        self.grants: dict[str, Grant] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for raw in stored.get("grants", []):
            until = dt_util.parse_datetime(raw.get("until") or "")
            if until is None or not raw.get("id") or not raw.get("person"):
                continue
            self.grants[raw["id"]] = Grant(
                raw["id"],
                raw["person"],
                raw.get("via") or "",
                raw.get("kind") or "",
                raw.get("value") or "",
                until,
                raw.get("reason") or "",
                dt_util.parse_datetime(raw.get("since") or "") or dt_util.utcnow(),
                raw.get("end_with"),
                raw.get("ends_with"),
            )

    def _data(self) -> dict[str, Any]:
        return {
            "grants": [
                {
                    "id": g.id,
                    "person": g.person,
                    "via": g.via,
                    "kind": g.kind,
                    "value": g.value,
                    "until": g.until.isoformat(),
                    "reason": g.reason,
                    "since": g.since.isoformat(),
                    "end_with": g.end_with,
                    "ends_with": g.ends_with,
                }
                for g in self.grants.values()
            ]
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def find(self, person: str, via: str, value: str, now: datetime | None = None) -> Grant | None:
        now = now or dt_util.utcnow()
        return next(
            (
                g
                for g in self.grants.values()
                if g.person == person and g.via == via and g.value == value and g.until > now
            ),
            None,
        )

    def add(
        self,
        person: str,
        via: str,
        kind: str,
        value: str,
        until: datetime,
        reason: str,
        end_with: str | None = None,
        ends_with: str | None = None,
    ) -> tuple[Grant, bool]:
        """A grant, or the one already lifting the same hold (its end moved later when this one lasts longer).
        Says whether it's new."""
        self.prune()
        if (found := self.find(person, via, value)) is not None:
            if until > found.until:
                found.until = until
                self._save()
            return found, False
        if len(self.grants) >= MAX_GRANTS:
            del self.grants[min(self.grants.values(), key=lambda g: g.since).id]
        grant = Grant(secrets.token_hex(6), person, via, kind, value, until, reason[:120], end_with=end_with,
                      ends_with=ends_with)
        self.grants[grant.id] = grant
        self._save()
        return grant, True

    def end(self, grant_id: str) -> Grant | None:
        grant = self.grants.pop(grant_id, None)
        if grant is not None:
            self._save()
        return grant

    def prune(self, now: datetime | None = None) -> bool:
        now = now or dt_util.utcnow()
        gone = [g.id for g in self.grants.values() if g.until <= now]
        for grant_id in gone:
            del self.grants[grant_id]
        if gone:
            self._save()
        return bool(gone)

    def of(self, person: str, now: datetime | None = None) -> list[Grant]:
        now = now or dt_util.utcnow()
        return sorted((g for g in self.grants.values() if g.person == person and g.until > now), key=lambda g: g.since)

    def lifted(self, person: str, now: datetime | None = None) -> dict[str, set[str]]:
        """What the person's grants lift, by enforcer kind: the held items (enforce.py) they cover."""
        found: dict[str, set[str]] = {}
        for grant in self.of(person, now):
            found.setdefault(grant.via, set()).add(grant.value)
        return found
