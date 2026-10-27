"""School days: which budget applies today, the school-day one or the other-day one.

A household says how it knows, in any mix (Configure > School days); the first that answers decides:

1. Dates typed in: extra days off, and extra school days (single dates or "2026-12-24..2027-01-01" ranges).
2. An entity whose state says what today is (a helper an automation keeps, the Workday integration's sensor, an
   input_boolean): the states listed mean a school day, any other state means not. Unavailable passes the question on.
3. A calendar: either its events (those whose title has one of the words, or any when no words are given) mean no
   school, or its events are the school days.
4. The rule: Monday to Friday, within the school year when one is given.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import logging
import re
from typing import Any

from homeassistant.const import STATE_UNAVAILABLE
from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util

_LOGGER = logging.getLogger(__name__)

CONF_SCHOOL_DAYS = "school_days"
CALENDAR_OFF = "off_days"
CALENDAR_SCHOOL = "school_days"
DEFAULT_SCHOOL_STATES = ("on", "school", "true", "yes")

_RANGE = re.compile(r"^(\d{4}-\d{2}-\d{2})\s*(?:\.\.|to|–|-\s)\s*(\d{4}-\d{2}-\d{2})$")


def parse_dates(text: str | None) -> set[date]:
    """Dates from "2026-11-26, 2026-12-24..2027-01-01" (commas, spaces or new lines between); bad parts are skipped."""
    found: set[date] = set()
    for part in re.split(r"[,;\n]+", text or ""):
        part = part.strip()
        if not part:
            continue
        match = _RANGE.match(part)
        try:
            if match:
                start, end = date.fromisoformat(match[1]), date.fromisoformat(match[2])
                if start <= end and (end - start).days <= 400:
                    found |= {start + timedelta(days=i) for i in range((end - start).days + 1)}
            else:
                found.add(date.fromisoformat(part))
        except ValueError:
            continue
    return found


@dataclass
class SchoolDaysConfig:
    entity: str | None = None
    school_states: tuple[str, ...] = DEFAULT_SCHOOL_STATES
    calendar: str | None = None
    calendar_mode: str = CALENDAR_OFF
    keywords: tuple[str, ...] = ()
    year_start: date | None = None
    year_end: date | None = None
    days_off: set[date] = field(default_factory=set)
    extra_school_days: set[date] = field(default_factory=set)

    @classmethod
    def from_options(cls, options: dict[str, Any]) -> SchoolDaysConfig:
        raw = options.get(CONF_SCHOOL_DAYS) or {}

        def day(value: Any) -> date | None:
            try:
                return date.fromisoformat(value) if value else None
            except (TypeError, ValueError):
                return None

        def words(value: Any) -> tuple[str, ...]:
            return tuple(w.strip().lower() for w in re.split(r"[,\n]+", value or "") if w.strip())

        return cls(
            entity=raw.get("entity") or None,
            school_states=words(raw.get("school_states")) or DEFAULT_SCHOOL_STATES,
            calendar=raw.get("calendar") or None,
            calendar_mode=raw.get("calendar_mode") or CALENDAR_OFF,
            keywords=words(raw.get("keywords")),
            year_start=day(raw.get("year_start")),
            year_end=day(raw.get("year_end")),
            days_off=parse_dates(raw.get("days_off")),
            extra_school_days=parse_dates(raw.get("extra_school_days")),
        )


def by_rule(config: SchoolDaysConfig, today: date) -> bool:
    if today.weekday() >= 5:
        return False
    if config.year_start and today < config.year_start:
        return False
    if config.year_end and today > config.year_end:
        return False
    return True


class SchoolDays:
    """Today's answer, worked out when asked to (at midnight, when the entity changes, every hour)."""

    def __init__(self, hass: HomeAssistant) -> None:
        self.hass = hass
        self.config = SchoolDaysConfig()
        self.day: date | None = None
        self.school = False
        self.reason = "rule"
        self._calendar_answer: tuple[date, bool | None] | None = None

    def configure(self, options: dict[str, Any]) -> None:
        self.config = SchoolDaysConfig.from_options(options)
        self._calendar_answer = None

    def watched_entities(self) -> list[str]:
        return [e for e in (self.config.entity, self.config.calendar) if e]

    def decide(self, today: date) -> tuple[bool, str]:
        """Today's answer from what's known now (the calendar's last answer for today, if it has one)."""
        config = self.config
        if today in config.days_off:
            return False, "date"
        if today in config.extra_school_days:
            return True, "date"
        if config.entity:
            state = self.hass.states.get(config.entity)
            if state is not None and state.state != STATE_UNAVAILABLE:
                return state.state.lower() in config.school_states, "entity"
        if config.calendar and self._calendar_answer and self._calendar_answer[0] == today:
            answer = self._calendar_answer[1]
            if answer is not None:
                return answer, "calendar"
        return by_rule(config, today), "rule"

    async def async_refresh(self, today: date | None = None) -> bool:
        """Works out today's answer (asking the calendar once a day, again if it failed); says whether it changed."""
        today = today or dt_util.now().date()
        if self.config.calendar and (self._calendar_answer is None or self._calendar_answer[0] != today or self._calendar_answer[1] is None):
            self._calendar_answer = (today, await self._ask_calendar(today))
        before = (self.day, self.school)
        self.day = today
        self.school, self.reason = self.decide(today)
        return before != (self.day, self.school)

    async def _ask_calendar(self, today: date) -> bool | None:
        """From the calendar: True or False for today, None when it couldn't be read."""
        config = self.config
        start = dt_util.as_local(datetime.combine(today, time.min, tzinfo=dt_util.get_default_time_zone()))
        try:
            response = await self.hass.services.async_call(
                "calendar",
                "get_events",
                {"start_date_time": start.isoformat(), "end_date_time": (start + timedelta(days=1)).isoformat()},
                target={"entity_id": config.calendar},
                blocking=True,
                return_response=True,
            )
        except Exception as err:  # noqa: BLE001 - a calendar that can't be read leaves the question to the rule
            _LOGGER.debug("School days: couldn't read %s: %s", config.calendar, err)
            return None
        events = ((response or {}).get(config.calendar) or {}).get("events") or []
        titles = [str(e.get("summary") or "").lower() for e in events]
        if config.calendar_mode == CALENDAR_SCHOOL:
            return bool(titles)
        matching = [t for t in titles if not config.keywords or any(k in t for k in config.keywords)]
        if matching:
            return False
        return by_rule(config, today)
