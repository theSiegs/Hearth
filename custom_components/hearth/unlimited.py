"""Unlimited (docs/home-assistant-integration.md, Unlimited): hearth.unlimited and hearth.unlimited_end.

An adult makes a kid's time unlimited until a time ("until 6 PM", "until turned off", the end of the day by default;
always over at midnight). While it lasts nothing Hearth holds for daily time or a category's limit holds them (an allow
of All screen time, exceptions.py), and the time they use **isn't counted**: daily time, every category's limit and
the bonus time pick up where they were when it started.

The window is an exclusion of minutes, kept per person and group: at its start Hearth notes the minutes counted so far
in each group (the first recompute after it starts), and while it lasts, and for SETTLE after it ends, everything counted
above that is left out of today's minutes. It works the same for every source, live (a TV, a console title Hearth times)
or total-only (Family Link's and Family Safety's daily totals, which say only a day's sum): the window's minutes are the
total's growth between the two notes. Totals arrive a few minutes late, so the end is noted SETTLE after the window
ends, and what's counted in that settle goes to the kid (it isn't counted either). At midnight the day's counts start
again, and a window from another day is gone.

Bedtime, School time and Pause screens still lock the kid, unless include_bedtime (then bedtime is lifted for the
window, bedtime_lift.py). Family Link's backstop is a whole day while it lasts (backstop.py).
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .time_model import say_clock, unlimited_span_text, unlimited_text

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

# A total's minutes of the window may arrive this late: the end is noted after it, in the kid's favour
SETTLE = timedelta(minutes=10)
EVENT_STARTED = "hearth_unlimited_started"
EVENT_ENDED = "hearth_unlimited_ended"


def _at(value: Any) -> datetime | None:
    parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
    return dt_util.as_local(parsed) if parsed else None


class Unlimited:
    """Each kid's unlimited windows today: {person: [window]}, a window {id, allow, start, until, open, ended,
    include_bedtime, base {group: seconds} (counted at its start), excluded {group: seconds} (once settled)}."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.unlimited.{entry_id}")
        self.day: str | None = None
        self.windows: dict[str, list[dict[str, Any]]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.windows = {p: [dict(w) for w in ws if isinstance(w, dict)] for p, ws in (stored.get("windows") or {}).items()}

    def _data(self) -> dict[str, Any]:
        return {"day": self.day, "windows": self.windows}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # Starting and ending

    @callback
    def start(self, person: str, allow_id: str, until: datetime, open_ended: bool, include_bedtime: bool) -> dict[str, Any]:
        now = dt_util.now()
        self._new_day(now)
        # One window at a time: another grant while one runs extends it (to the later end), never a second window
        # (its minutes would be left out twice)
        running = self.active(person, now)
        if running is not None:
            ends = [x for x in (_at(running.get("until")), until) if x is not None]
            running["until"] = max(ends).isoformat()
            running["open"] = bool(running.get("open")) or open_ended
            running["include_bedtime"] = bool(running.get("include_bedtime")) or include_bedtime
            self._save()
            return running
        window = {
            "id": secrets.token_hex(6),
            "allow": allow_id,
            "start": now.isoformat(),
            "until": until.isoformat(),
            "open": open_ended,
            "ended": None,
            "include_bedtime": include_bedtime,
            "base": None,
            "excluded": None,
        }
        self.windows.setdefault(person, []).append(window)
        self._save()
        self.hass.bus.async_fire(EVENT_STARTED, {"person": person, "until": until.isoformat(), "open": open_ended})
        return window

    @callback
    def end(self, person: str, now: datetime | None = None) -> dict[str, Any] | None:
        """Ends the person's running window now (unlimited_end); the window, None when none ran."""
        now = now or dt_util.now()
        window = self.active(person, now)
        if window is None:
            return None
        window["until"] = now.isoformat()
        window["ended"] = now.isoformat()
        self._save()
        return window

    @callback
    def extend_to(self, person: str, until: datetime | None, open_ended: bool) -> None:
        """The running window's end, set again from the Unlimited grants still in effect (one of them ended)."""
        running = self.active(person)
        if running is None:
            return
        if until is not None:
            running["until"] = until.isoformat()
        running["open"] = open_ended
        self._save()

    def active(self, person: str, now: datetime | None = None) -> dict[str, Any] | None:
        now = now or dt_util.now()
        for window in self.windows.get(person, []):
            until = _at(window.get("until"))
            if window.get("ended") is None and until is not None and until > now:
                return window
        return None

    def _new_day(self, now: datetime) -> None:
        today = now.date().isoformat()
        if self.day != today:
            # Midnight ends every window, and today's counts start again
            self.day = today
            self.windows = {}
            self._save()

    # Counting

    @callback
    def exclude(self, person: str, seconds: dict[str, float], now: datetime) -> dict[str, float]:
        """[seconds] (today's counted seconds per group) without what windows of today left out. Notes a window's
        start, its end (and the minutes it left out, once settled), and says when one ended (EVENT_ENDED)."""
        self._new_day(now)
        windows = self.windows.get(person)
        if not windows:
            return seconds
        excluded: dict[str, float] = {}
        changed = False
        for window in windows:
            if window.get("base") is None:
                # Its first look: what was counted when it started
                window["base"] = {g: float(s) for g, s in seconds.items()}
                changed = True
            until = _at(window.get("until"))
            if window.get("ended") is None and until is not None and until <= now:
                window["ended"] = window["until"]
                changed = True
            if window.get("excluded") is not None:
                gone = window["excluded"]
            else:
                # While it lasts and SETTLE after: what's counted above its start, a later total's catch-up included
                base = window["base"]
                gone = {g: max(0.0, float(s) - base.get(g, 0.0)) for g, s in seconds.items()}
                ended = _at(window.get("ended"))
                if ended is not None and now - ended >= SETTLE:
                    window["excluded"] = gone
                    changed = True
                    self._told_end(person, window)
            for group, s in gone.items():
                excluded[group] = excluded.get(group, 0.0) + s
        if changed:
            self._save()
        return {g: max(0.0, s - excluded.get(g, 0.0)) for g, s in seconds.items()}

    def _told_end(self, person: str, window: dict[str, Any]) -> None:
        from .counting import ALL
        from .history import UNLIMITED

        minutes = int((window.get("excluded") or {}).get(ALL, 0.0) // 60)
        self.household.history.log(
            UNLIMITED, person, start=window["start"], end=window["ended"], minutes=minutes, open=window.get("open")
        )

    @callback
    def tell_ended(self) -> None:
        """After a recompute: each window that ended since (early or at its time) is told once, with today's time as
        it is again ("Limits back on · 1 h 10 min left today": EVENT_ENDED, and the adults' phones)."""
        for person, windows in self.windows.items():
            for window in windows:
                if window.get("ended") is None or window.get("told"):
                    continue
                window["told"] = True
                self._save()
                text = self.back_on_text(person)
                self.hass.bus.async_fire(EVENT_ENDED, {"person": person, "id": window["id"], "text": text})
                self.household.hub.asks.tell(
                    self.household.person_name(person), text, f"hearth_unlimited_{person}"
                )

    def back_on_text(self, person: str) -> str:
        from .time_model import today_text

        view = self.household.time_view(person)
        line = today_text(view["today_left"], view["bonus_left"]) or "no daily time set"
        return f"Limits back on · {line}"

    # Views

    def view(self, person: str) -> dict[str, Any]:
        """{active: {until, open, include_bedtime, text} | None, today: [{start, end, minutes, text}]}."""
        from .counting import ALL

        now = dt_util.now()
        running = self.active(person, now)
        out: dict[str, Any] = {"active": None, "today": []}
        if running is not None:
            until = _at(running["until"])
            clock = None if running.get("open") else say_clock(until.hour, until.minute)
            out["active"] = {
                "until": until.isoformat(),
                "open": bool(running.get("open")),
                "include_bedtime": bool(running.get("include_bedtime")),
                "text": unlimited_text(clock),
            }
        day = self.household.days.get(person)
        for window in self.windows.get(person, []):
            if window.get("ended") is None:
                continue
            start, end = _at(window["start"]), _at(window["ended"])
            gone = window.get("excluded")
            if gone is None and window.get("base") is not None and day is not None:
                raw = day.raw_groups.get(ALL, 0.0) if hasattr(day, "raw_groups") else 0.0
                seconds = max(0.0, raw - window["base"].get(ALL, 0.0))
            else:
                seconds = (gone or {}).get(ALL, 0.0)
            minutes = int(seconds // 60)
            out["today"].append(
                {
                    "start": start.isoformat(),
                    "end": end.isoformat(),
                    "minutes": minutes,
                    "settled": gone is not None,
                    "text": unlimited_span_text((start.hour, start.minute), (end.hour, end.minute), minutes),
                }
            )
        return out
