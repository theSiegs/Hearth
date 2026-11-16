"""Today's time, caps and bonus time (docs/home-assistant-integration.md, Today's time).

- **Today's time** is the one daily total: All screen time's budget (school days / other days, or the weekly
  schedule's).
- **Caps** are the budgets of the other groups (Games, YouTube, ...): ceilings inside today's time ("Games: at most
  2 h"). A cap never adds time.
- **Bonus time** (the services call it extra time: hearth.add_time) has no category. It adds N minutes to today's
  time, and the kid may spend it anywhere: minutes past a cap are paid from it too, and one N is shared by every cap.
  Chores, approved asks, the day-off bonus and an adult's gift all give it. It ends at midnight.
- **A raised cap** (hearth.raise_cap) lifts one category's ceiling today (by minutes, to minutes, or no cap) until a
  time. Today's time is unchanged.
- **No limits** (hearth.no_limits) is an allow of All screen time (exceptions.py) until a time.

The accounting (account()):

    bonus_used = max(0, minutes over today's base time, sum over capped categories of minutes over each cap)
    bonus_left = max(0, N - bonus_used)
    today_left = max(0, base + N - used)                 (the time the kid can use, bonus included)
    cap_left   = max(0, cap - used_in_category) + bonus_left   (what holds the category: at 0 it's held)
    usable     = min(cap_left, today_left)               (what a person is shown for the category)

Minutes past a cap are part of today's minutes too, so paying them from the bonus and counting them against today's
time is the same minutes seen twice, which is why bonus_used is a max and not a sum. Worked examples are in
ha_tests/test_time_model.py.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import math
from typing import Any

# Family Link's daily limit at most (minutes in a day), and what "no limits" writes there
DAY_MINUTES = 24 * 60
# The backstop's margin over Hearth's own numbers, by default (Configure > Enforce)
BACKSTOP_MARGIN = 30


@dataclass(frozen=True)
class Raise:
    """One category's raised cap today: by [add] minutes, or to [to] minutes, or no cap at all ([no_cap]), until
    [until] (ISO; None: the end of the day)."""

    add: int = 0
    to: int | None = None
    no_cap: bool = False
    until: str | None = None

    def cap(self, base: int | None) -> int | None:
        """The cap in effect, from the configured one ([base]; None: no cap)."""
        if self.no_cap:
            return None
        if self.to is not None:
            return max(0, self.to + self.add)
        if base is None:
            return None
        return max(0, base + self.add)

    def view(self) -> dict[str, Any]:
        return {"add": self.add, "to": self.to, "no_cap": self.no_cap, "until": self.until}

    @staticmethod
    def of(stored: Any) -> Raise | None:
        if not isinstance(stored, dict):
            return None
        to = stored.get("to")
        return Raise(
            int(stored.get("add") or 0),
            int(to) if isinstance(to, (int, float)) else None,
            bool(stored.get("no_cap")),
            stored.get("until") if isinstance(stored.get("until"), str) else None,
        )


@dataclass
class Account:
    """One person's day, as the time model counts it."""

    # Today's base time (None: no daily total) and the bonus given (N, after any time an adult took away)
    base: int | None
    bonus: int
    used: float
    bonus_used: int
    bonus_left: int
    # None without a daily total
    today_left: int | None
    # Per capped category: the cap in effect (None: no cap), what holds it, what a person is shown
    caps: dict[str, int | None] = field(default_factory=dict)
    cap_left: dict[str, int | None] = field(default_factory=dict)
    usable: dict[str, int | None] = field(default_factory=dict)


def split_bonus(base: int | None, given: int) -> tuple[int | None, int]:
    """[given] is today's bonus as stored (an adult's, plus chores'): more than 0 is bonus time; less takes time away
    from today's base instead (never below 0)."""
    if given >= 0 or base is None:
        return base, max(0, given)
    return max(0, base + given), 0


def account(
    base: int | None,
    bonus: int,
    used: float,
    categories: dict[str, tuple[int | None, float]],
) -> Account:
    """[base] today's time, [bonus] N, [used] today's minutes, [categories] {id: (cap in effect or None, minutes used
    in it)}."""
    bonus = max(0, int(bonus))
    over_day = max(0.0, used - base) if base is not None else 0.0
    over_caps = sum(max(0.0, spent - cap) for cap, spent in categories.values() if cap is not None)
    bonus_used = int(math.floor(max(over_day, over_caps)))
    bonus_left = max(0, bonus - bonus_used)
    today_left = None if base is None else max(0, int(base + bonus - used))
    out = Account(base, bonus, used, bonus_used, bonus_left, today_left)
    for gid, (cap, spent) in categories.items():
        out.caps[gid] = cap
        if cap is None:
            out.cap_left[gid] = None
            out.usable[gid] = today_left
            continue
        left = max(0, int(cap - spent)) + bonus_left
        out.cap_left[gid] = left
        out.usable[gid] = left if today_left is None else min(left, today_left)
    return out


def backstop_minutes(
    base: int | None,
    bonus_left: int,
    raises_outside: int,
    margin: int,
    no_limits: bool = False,
) -> int | None:
    """Family Link's daily limit Hearth keeps as a backstop: today's time + the bonus left + raised caps that count on
    the device but not in today's time + a margin, rounded up to 5 minutes (at most a day). No limits today: a whole
    day. None: no daily total, Family Link is left alone."""
    # No daily time: Family Link is Hearth's to leave alone, Unlimited or not (nothing would put it back after)
    if base is None:
        return None
    if no_limits:
        return DAY_MINUTES
    total = max(0, base) + max(0, bonus_left) + max(0, raises_outside) + max(0, margin)
    return min(DAY_MINUTES, int(math.ceil(total / 5) * 5))


def say_minutes(minutes: int) -> str:
    """40 min, 1 h, 1 h 10 min."""
    minutes = max(0, int(minutes))
    hours, rest = divmod(minutes, 60)
    if not hours:
        return f"{rest} min"
    return f"{hours} h" if not rest else f"{hours} h {rest} min"


def say_clock(hour: int, minute: int, suffix: bool = True) -> str:
    """6 PM, 6:30 PM (2:00 without [suffix], for a span's start)."""
    twelve = hour % 12 or 12
    if not suffix:
        return f"{twelve}:{minute:02d}"
    half = "AM" if hour < 12 else "PM"
    return f"{twelve} {half}" if not minute else f"{twelve}:{minute:02d} {half}"


def unlimited_text(until_clock: str | None) -> str:
    """"Unlimited until 6 PM", or "Unlimited (until turned off)" ([until_clock] None)."""
    return f"Unlimited until {until_clock}" if until_clock else "Unlimited (until turned off)"


def unlimited_span_text(start: tuple[int, int], end: tuple[int, int], not_counted: int) -> str:
    """The adults' view and history: "Unlimited 2:00–5:10 PM · 3 h 10 min not counted"."""
    def full(hour: int, minute: int, half: bool) -> str:
        return say_clock(hour, minute, False) + ((" AM" if hour < 12 else " PM") if half else "")

    same_half = (start[0] < 12) == (end[0] < 12)
    return (
        f"Unlimited {full(*start, not same_half)}–{full(*end, True)} · {say_minutes(not_counted)} not counted"
    )


def today_text(today_left: int | None, bonus_left: int, unlimited: str | None = None, adult: bool = False) -> str | None:
    """Today's line as a person is shown it: "1 h 10 min left today", "30 min bonus left" (only bonus time is left),
    "Unlimited until 6 PM" ([unlimited]: unlimited_text's line); an adult's "1 h 10 min left today (includes 30 min
    bonus)"."""
    if unlimited:
        return unlimited
    if today_left is None:
        return None
    if today_left <= 0:
        return "No time left today"
    if not adult and bonus_left > 0 and today_left <= bonus_left:
        return f"{say_minutes(today_left)} bonus left"
    line = f"{say_minutes(today_left)} left today"
    if adult and bonus_left > 0:
        line += f" (includes {say_minutes(min(bonus_left, today_left))} bonus)"
    return line


def category_text(name: str, usable: int | None, today_left: int | None) -> str | None:
    """A category's line: "Games: 25 min left", or "Games are done for today · 40 min left for other things" when its
    limit is reached but daily time remains. None without a limit."""
    if usable is None:
        return None
    if usable <= 0 and today_left:
        return f"{name} are done for today · {say_minutes(today_left)} left for other things"
    return f"{name}: {say_minutes(usable)} left"


ORIGIN_SOURCES = ("hearth", "family_link", "family_safety", "nintendo", "chore", "ask")
_ORIGIN_WHERE = {
    "hearth": "in Hearth",
    "family_link": "in Family Link",
    "family_safety": "in Family Safety",
    "nintendo": "in the Nintendo app",
    "chore": "for a chore",
    "ask": "after an ask",
}


def origin_text(detail: str, source: str, by: str | None, clock: str | None) -> str:
    """Where a status came from, for the "?" on a status line: "Bonus +30 · added by Alex in Hearth · 3:05 PM"."""
    parts = [detail]
    where = _ORIGIN_WHERE.get(source, f"in {source}")
    parts.append(f"added by {by} {where}" if by else f"added {where}")
    if clock:
        parts.append(clock)
    return " · ".join(parts)


def limit_text(name: str, configured: int | None, today: int | None, raised: bool) -> str:
    """An adult's hint: "Games: 2 h limit", "Games: 3 h limit today (raised)", "Games: no limit today (raised)",
    "Games: no limit"."""
    if raised:
        return f"{name}: no limit today (raised)" if today is None else f"{name}: {say_minutes(today)} limit today (raised)"
    return f"{name}: no limit" if configured is None else f"{name}: {say_minutes(configured)} limit"
