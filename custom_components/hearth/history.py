"""What happened with each person's time, day by day: a group running out, a request for more, an offer, an answer,
a bonus (to a group or on one device), a suggestion an adult put off for the day and one pushed to the adults'
phones, and a TV notice's button an adult answered. See docs/home-assistant-integration.md, History.

The log is what suggestions are sized and silenced from: "usually gets 30 more games", "not today". It's kept with
Home Assistant's storage helper for HISTORY_DAYS, so it survives a restart, and holds no names or notes: people are
their entity ids, groups and devices their Hearth ids.

Each event is {"at": ISO time, "kind": ..., "person": entity id, ...}, with group, device, minutes, status and key as
the kind needs them.
"""

from __future__ import annotations

from collections import Counter
from datetime import date, datetime, timedelta
from typing import Any

from homeassistant.core import Event, HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

OUT = "out"
ASK = "ask"
OFFER = "offer"
ANSWER = "answer"
BONUS = "bonus"
DEVICE_BONUS = "device_bonus"
DISMISS = "dismiss"
# A suggestion pushed to the adults' phones (suggest_push.py), by its key: once a day
PUSHED = "pushed"
# A TV notice's button an adult answered (notices.py), by Parent PIN on the TV or on their phone (`via`): who
# (`by`: their person, else `user`: their Home Assistant user id), the notice's `key`, the button's `action` number
# and the TV (`device`)
NOTICE_ANSWER = "notice_answer"
KINDS = (OUT, ASK, OFFER, ANSWER, BONUS, DEVICE_BONUS, DISMISS, PUSHED, NOTICE_ANSWER)

HISTORY_DAYS = 90
# A runaway automation mustn't grow this without end
MAX_EVENTS = 20000
# How far back "usually" looks, and how many grants it takes to say so
USUAL_DAYS = 28
USUAL_MIN_GRANTS = 3


class History:
    """The household's event log, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.history.{entry_id}")
        self.events: list[dict[str, Any]] = []

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.events = [e for e in stored.get("events", []) if isinstance(e, dict) and e.get("kind") in KINDS]
        self._prune()

    def _data(self) -> dict[str, Any]:
        return {"events": self.events}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 5)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def _prune(self) -> None:
        since = (dt_util.utcnow() - timedelta(days=HISTORY_DAYS)).isoformat()
        self.events = [e for e in self.events if str(e.get("at", "")) >= since][-MAX_EVENTS:]

    @callback
    def log(self, kind: str, person: str, at: datetime | None = None, **fields: Any) -> dict[str, Any]:
        """One event; fields that are None are left out."""
        event = {
            "at": (at or dt_util.utcnow()).isoformat(),
            "kind": kind,
            "person": person,
            **{k: v for k, v in fields.items() if v is not None},
        }
        self.events.append(event)
        if len(self.events) > MAX_EVENTS:
            self._prune()
        self._save()
        return event

    # The bus events Hearth fires anyway

    @callback
    def on_budget_reached(self, event: Event) -> None:
        if event.data.get("person"):
            self.log(OUT, event.data["person"], group=event.data.get("group"))

    @callback
    def on_requested(self, event: Event) -> None:
        data = event.data
        if not data.get("person"):
            return
        self.log(
            OFFER if data.get("offered") else ASK,
            data["person"],
            id=data.get("id"),
            group=data.get("group"),
            minutes=data.get("minutes"),
            source=data.get("source") if data.get("source") not in (None, "hearth") else None,
        )

    @callback
    def on_answered(self, event: Event) -> None:
        data = event.data
        if not data.get("person"):
            return
        self.log(
            ANSWER,
            data["person"],
            id=data.get("id"),
            status=data.get("status"),
            minutes=data.get("minutes"),
            answered_in=data.get("answered_in"),
        )

    # Reading it back

    def of(
        self, person: str | None = None, since: datetime | None = None, kinds: tuple[str, ...] | None = None
    ) -> list[dict[str, Any]]:
        """The events of a person (or everyone's), since a time, of some kinds; oldest first."""
        after = since.isoformat() if since else ""
        return [
            e
            for e in self.events
            if (person is None or e.get("person") == person)
            and str(e.get("at", "")) >= after
            and (kinds is None or e.get("kind") in kinds)
        ]

    def _local_day(self, event: dict[str, Any]) -> date | None:
        at = dt_util.parse_datetime(str(event.get("at") or ""))
        return dt_util.as_local(at).date() if at else None

    def dismissed(self, person: str, day: date) -> set[str]:
        """The suggestion keys an adult put off for the person on [day] ("not today")."""
        return {
            str(e["key"])
            for e in self.of(person, kinds=(DISMISS,))
            if e.get("key") and self._local_day(e) == day
        }

    def pushed(self, person: str, day: date) -> set[str]:
        """The suggestion keys pushed to the adults' phones for the person on [day]."""
        return {
            str(e["key"])
            for e in self.of(person, kinds=(PUSHED,))
            if e.get("key") and self._local_day(e) == day
        }

    def usual_bonus(self, person: str, group: str, now: datetime | None = None) -> int | None:
        """The bonus an adult most often gives the person for [group] lately: at least USUAL_MIN_GRANTS bonuses in the
        last USUAL_DAYS, the most common amount (the larger on a tie). None when there's no such habit yet."""
        since = (now or dt_util.utcnow()) - timedelta(days=USUAL_DAYS)
        amounts = [
            int(e["minutes"])
            for e in self.of(person, since, (BONUS,))
            if e.get("group") == group and isinstance(e.get("minutes"), int) and e["minutes"] > 0
        ]
        if len(amounts) < USUAL_MIN_GRANTS:
            return None
        counts = Counter(amounts)
        return max(counts, key=lambda m: (counts[m], m))

    def days_summary(self, person: str, days: int = 7, now: datetime | None = None) -> list[dict[str, Any]]:
        """Per local day, newest first: which groups ran out, how many asks, offers and bonus minutes (by group)."""
        now = now or dt_util.utcnow()
        since = now - timedelta(days=days)
        by_day: dict[date, dict[str, Any]] = {}
        for event in self.of(person, since):
            day = self._local_day(event)
            if day is None:
                continue
            row = by_day.setdefault(day, {"date": day.isoformat(), "out": [], "asks": 0, "offers": 0, "bonus": {}})
            if event["kind"] == OUT and event.get("group") and event["group"] not in row["out"]:
                row["out"].append(event["group"])
            elif event["kind"] == ASK:
                row["asks"] += 1
            elif event["kind"] == OFFER:
                row["offers"] += 1
            elif event["kind"] in (BONUS, DEVICE_BONUS) and isinstance(event.get("minutes"), int):
                key = event.get("group") or "all"
                row["bonus"][key] = row["bonus"].get(key, 0) + event["minutes"]
        return [by_day[d] for d in sorted(by_day, reverse=True)]
