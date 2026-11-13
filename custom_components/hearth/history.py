"""What happened with each person's time, day by day: a group running out, a request for more, an offer, an answer,
a bonus (to a group or on one device), a suggestion an adult put off for the day and one pushed to the adults'
phones, a TV notice's button an adult answered, an assistant's action (llm_api.py), each local day's final minutes
per group, and what each person played (a title, game or app, once a play ends). See docs/home-assistant-integration.md,
History.

The log is what suggestions are sized and silenced from: "usually gets 30 more games", "not today". It's kept with
Home Assistant's storage helper for HISTORY_DAYS, so it survives a restart, and holds no names or notes: people are
their entity ids, groups and devices their Hearth ids.

Each event is {"at": ISO time, "kind": ..., "person": entity id, ...}, with group, device, minutes, status and key as
the kind needs them.
"""

from __future__ import annotations

from collections import Counter
from contextvars import ContextVar
from datetime import date, datetime, timedelta
from typing import Any, Callable

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
# A local day's final minutes per group ({"date": "YYYY-MM-DD", "minutes": {group: n}, "budget": {group: n | None}}),
# logged at the day's rollover (or, when Home Assistant was down at midnight, on the first look after it starts): the
# household summary's `week`. `budget` is the day's budget per group without its bonus (None: no limit); records from
# before it was logged have none
DAY = "day"
# What a person played, once a play ends (live.py): {"item": the title, game or app as shown, "device": where (a Hearth
# device id, source:<id> or nintendo:<entity>), "minutes"}. One event per person, item and device a local day (a
# play that ends again adds its minutes to it, `at` is the last end); at most MAX_PLAYED a person a day, kept
# PLAYED_DAYS, and only plays of a minute or more
PLAYED = "played"
MAX_PLAYED = 50
PLAYED_DAYS = 28
# An action an assistant took (MCP or voice, llm_api.py) that logs nothing of its own (a pause, an allow, School time
# off): the `tool`, and what it did (app, group, minutes, device, until, date)
ASSIST = "assist"
KINDS = (OUT, ASK, OFFER, ANSWER, BONUS, DEVICE_BONUS, DISMISS, PUSHED, NOTICE_ANSWER, DAY, PLAYED, ASSIST)
# Who is acting through an assistant (llm_api.run_audited): {"via": "mcp" | "voice", "user": Home Assistant user id},
# added to every event logged meanwhile (a day's record aside)
ACTOR: ContextVar[dict[str, Any] | None] = ContextVar("hearth_actor", default=None)
# How many local days the household summary's `week` holds, today included
WEEK_DAYS = 7

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
        now = dt_util.utcnow()
        since = (now - timedelta(days=HISTORY_DAYS)).isoformat()
        played_since = (now - timedelta(days=PLAYED_DAYS)).isoformat()
        self.events = [
            e for e in self.events
            if str(e.get("at", "")) >= (played_since if e.get("kind") == PLAYED else since)
        ][-MAX_EVENTS:]

    @callback
    def log(self, kind: str, person: str, at: datetime | None = None, **fields: Any) -> dict[str, Any]:
        """One event; fields that are None are left out. During an assistant's action, with who acted (ACTOR)."""
        actor = ACTOR.get() if kind != DAY else None
        event = {
            "at": (at or dt_util.utcnow()).isoformat(),
            "kind": kind,
            "person": person,
            **(actor or {}),
            **{k: v for k, v in fields.items() if v is not None},
        }
        self.events.append(event)
        if len(self.events) > MAX_EVENTS:
            self._prune()
        self._save()
        return event

    @callback
    def log_played(self, person: str, item: str, device: str, minutes: int, at: datetime | None = None) -> bool:
        """A play that ended: added to the person's `played` event of the same item and device today, else a new one
        (not past MAX_PLAYED a day). Says whether it was kept."""
        if minutes < 1 or not item:
            return False
        at = at or dt_util.utcnow()
        item = item[:128]
        day = dt_util.as_local(at).date()
        start = dt_util.start_of_local_day(day).isoformat()
        today = 0
        for event in reversed(self.events):
            if str(event.get("at", "")) < start:
                break
            if event.get("kind") != PLAYED or event.get("person") != person:
                continue
            if event.get("item") == item and event.get("device") == device:
                event["minutes"] = int(event.get("minutes") or 0) + minutes
                event["at"] = at.isoformat()
                self._save()
                return True
            today += 1
        if today >= MAX_PLAYED:
            return False
        self.log(PLAYED, person, at, item=item, device=device, minutes=minutes)
        return True

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

    def has_day(self, person: str, day: date) -> bool:
        """Whether [day]'s minutes are recorded for the person."""
        iso = day.isoformat()
        return any(e.get("kind") == DAY and e.get("person") == person and e.get("date") == iso for e in self.events)

    @callback
    def log_day(
        self, person: str, day: date, minutes: dict[str, int], budget: dict[str, int | None] | None = None
    ) -> bool:
        """Records [day]'s final minutes per group for the person (and its budget per group), once; says whether it
        did."""
        if self.has_day(person, day):
            return False
        extra = {"budget": dict(budget)} if budget is not None else {}
        self.log(DAY, person, date=day.isoformat(), minutes=dict(minutes), **extra)
        return True

    def week(
        self,
        person: str,
        today_minutes: dict[str, int],
        now: datetime | None = None,
        budget_of: Callable[[date], dict[str, int | None]] | None = None,
    ) -> list[dict[str, Any]]:
        """The last WEEK_DAYS local days, newest first, today included: {date, minutes {group: n}, out [groups],
        bonus {group: minutes}, asks, budget {group: n | None}}. Today's minutes are [today_minutes] (live); a past
        day's are its `day` record, {} when there's none (unknown, not zero). A day's budget is its `day` record's,
        else [budget_of] (today's live budget, a past day's from its day type and the budgets now)."""
        today = dt_util.as_local(now or dt_util.utcnow()).date()
        dates = [today - timedelta(days=i) for i in range(WEEK_DAYS)]
        rows = {
            d: {"date": d.isoformat(), "minutes": {}, "out": [], "bonus": {}, "asks": 0, "budget": None} for d in dates
        }
        rows[today]["minutes"] = dict(today_minutes)
        by_iso = {d.isoformat(): d for d in dates}
        # A day's events are at most a day either side of it in UTC
        since = (dt_util.start_of_local_day(dates[-1]) - timedelta(days=1)).isoformat()
        for event in self.events:
            if event.get("person") != person or str(event.get("at", "")) < since:
                continue
            kind = event.get("kind")
            if kind == DAY:
                day = by_iso.get(str(event.get("date")))
                if day is not None and day != today and isinstance(event.get("minutes"), dict):
                    rows[day]["minutes"] = dict(event["minutes"])
                    if isinstance(event.get("budget"), dict):
                        rows[day]["budget"] = dict(event["budget"])
                continue
            if kind not in (OUT, ASK, BONUS, DEVICE_BONUS):
                continue
            row = rows.get(self._local_day(event))  # type: ignore[arg-type]
            if row is None:
                continue
            if kind == OUT and event.get("group") and event["group"] not in row["out"]:
                row["out"].append(event["group"])
            elif kind == ASK:
                row["asks"] += 1
            elif kind in (BONUS, DEVICE_BONUS) and isinstance(event.get("minutes"), int):
                key = event.get("group") or "all"
                row["bonus"][key] = row["bonus"].get(key, 0) + event["minutes"]
        for day, row in rows.items():
            if row["budget"] is None:
                row["budget"] = dict(budget_of(day)) if budget_of is not None else {}
        return [rows[d] for d in dates]
