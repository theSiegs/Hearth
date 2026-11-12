"""Temporary limits: a daily limit Hearth raises for one day and puts back itself.

The schedule's extra minutes on a day off or half day (schedule.py) raise a limit that is a setting, not today's alone:
the Switch's Max screentime today (of every day, or of this weekday) and Family Safety's limit of a weekday for Windows
or the Xbox (microsoft_family_safety.set_screentime_limit with day_of_week). Neither has a today-only limit Hearth can
count on, so a raise would stay. Hearth keeps one record per limit it raised (one platform of one child, or one Switch):

- Before writing, what it added to ("base"), what it writes ("target"), the day and weekday, the platform and whose it
  is ("people"), with whatever the platform needs to put it back. Kept across a restart and midnight, so Hearth never
  adds to its own value twice.
- A write that failed is not Hearth's limit: "written_at" stays empty, the raise isn't done, and it's written again
  while it's still today (a write that did reach the platform is found by its reading the target).
- The base goes back 2 minutes before midnight, at once when the day's extra is called off or the day type changed,
  or on the next start when Home Assistant was off then (on the recorded weekday: a weekday's setting can be put back
  any day; the Switch's own way is in schedule.py).
- Only while the limit still reads Hearth's target: a parent's change since (in the Family Safety or Nintendo app, or
  an automation) is theirs and stays. A limit that reads the base right after Hearth's write is waited on for a while
  (the integration may not have read it back yet).

What Hearth does with a raise (the platform's own reading, the call and holds) stays with the platform in schedule.py;
the record and the rules about it are here, shared.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any, Callable

from homeassistant.util import dt as dt_util

from .enforce import QUIET_AFTER_CALL, WEEKDAYS, near_midnight

# What a raise of the day came to: set (Hearth's limit is on), skip (nothing to add to, or a parent's change)
SET, SKIP = "set", "skip"
# What to do with a record now: write (Hearth's limit again, or the base when putting back), wait (not read yet, or
# just written), done (putting back: nothing of Hearth's is left, back already or a parent's)
WRITE, WAIT, DONE = "write", "wait", "done"
# The platforms: a Switch, and Family Safety's two with a weekday limit
SWITCH, WINDOWS, XBOX = "Switch", "Windows", "Xbox"


def _when(value: Any) -> datetime | None:
    parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
    return parsed


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


class TemporaryLimits:
    """The limits Hearth raised for a day, by key (a Switch's entity, or a Family Safety child's platform)."""

    def __init__(self, on_change: Callable[[], None] | None = None) -> None:
        self.held: dict[str, dict[str, Any]] = {}
        self._on_change = on_change

    # Storage

    def load(self, raw: Any, legacy_switch: Any = None) -> None:
        """From storage; [legacy_switch] is the schedule's older sw_limits (Switches only, keyed by entity)."""
        self.held = {}
        sources = [(raw, None), (legacy_switch, SWITCH)]
        for found, platform in sources:
            for key, held in (found or {}).items() if isinstance(found, dict) else ():
                try:
                    kept = {
                        **held,
                        "platform": str(held.get("platform") or platform),
                        "target": int(held["target"]),
                        "base": int(held["base"]),
                        "day": str(held["day"]),
                        "people": list(held.get("people") or []),
                    }
                except (AttributeError, KeyError, TypeError, ValueError):
                    continue
                if kept["platform"] in ("", "None"):
                    continue
                if platform == SWITCH and "written_at" not in held:
                    # An older record was kept only once the write was under way: take it as written
                    kept["written_at"] = dt_util.utcnow().isoformat()
                self.held.setdefault(str(key), kept)

    def dump(self) -> dict[str, dict[str, Any]]:
        return self.held

    def _changed(self) -> None:
        if self._on_change is not None:
            self._on_change()

    # The records

    def get(self, key: str) -> dict[str, Any] | None:
        return self.held.get(key)

    def of(self, platforms: tuple[str, ...]) -> list[tuple[str, dict[str, Any]]]:
        return [(key, held) for key, held in self.held.items() if held.get("platform") in platforms]

    def begin(
        self, key: str, platform: str, base: int, target: int, people: list[str], **extra: Any
    ) -> dict[str, Any]:
        """Kept before the write: one that reached the platform but whose answer was lost is still known as Hearth's.
        Today's day and weekday unless [extra] says them."""
        now = dt_util.now()
        record = {
            "day": now.date().isoformat(),
            "weekday": WEEKDAYS[now.weekday()],
            **extra,
            "platform": platform,
            "target": int(target),
            "base": int(base),
            "people": list(people),
            "written_at": None,
        }
        self.held[key] = record
        self._changed()
        return record

    def written(self, key: str) -> None:
        """The write went through (or Hearth's limit was found on)."""
        record = self.held.get(key)
        if record is not None:
            record["written_at"] = dt_util.utcnow().isoformat()
            self._changed()

    def failed(self, key: str) -> None:
        """The write failed: not Hearth's limit, tried again."""
        record = self.held.get(key)
        if record is not None:
            record["written_at"] = None
            self._changed()

    def drop(self, key: str) -> None:
        if self.held.pop(key, None) is not None:
            self._changed()

    # The rules

    @staticmethod
    def today(record: dict[str, Any], today: date) -> bool:
        return record.get("day") == today.isoformat()

    @staticmethod
    def due(record: dict[str, Any], now: datetime, extra_day: bool, called_off: bool) -> bool:
        """Its base goes back now: a later day (missed at midnight), 2 minutes before midnight, today isn't a day off
        or half day any more, or the day's extra was called off for everyone it's for."""
        return not TemporaryLimits.today(record, now.date()) or near_midnight(now) or not extra_day or called_off

    @staticmethod
    def just_written(record: dict[str, Any], settle: timedelta = QUIET_AFTER_CALL) -> bool:
        written = _when(record.get("written_at"))
        return written is not None and dt_util.utcnow() - written < settle

    def raised(self, key: str, current: Any, settle: timedelta = QUIET_AFTER_CALL) -> str:
        """Today's record, against the limit as it reads now: SET (Hearth's limit is on), WRITE (the last write failed
        and the base is still on: written again), WAIT (not read yet, or just written), SKIP (changed since: a
        parent's, left alone)."""
        record = self.held[key]
        value = _number(current)
        if value is not None and value == record["target"]:
            if record.get("written_at") is None:
                self.written(key)  # it did reach the platform
            return SET
        if value is None:
            return WAIT
        if record.get("written_at") is None:
            return WRITE if value == record["base"] else SKIP
        return WAIT if self.just_written(record, settle) else SKIP

    @staticmethod
    def put_back(record: dict[str, Any], current: Any, settle: timedelta = QUIET_AFTER_CALL) -> str:
        """Putting the base back, against the limit as it reads now: WRITE (still Hearth's target), WAIT (not read, or
        just written and not read back yet), DONE (nothing of Hearth's: back already, never written, a parent's)."""
        value = _number(current)
        if value is None:
            return WAIT
        if value == record["target"]:
            return WRITE
        if record.get("written_at") is None:
            return DONE
        if value == record["base"] and TemporaryLimits.just_written(record, settle):
            return WAIT
        return DONE
