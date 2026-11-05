"""Asking for more time (docs/home-assistant-integration.md, Ask for more): one pipeline for every device.

A kid's device asks (a TV for its profile's person, a phone for its own) for 15, 30, 45 or 60 minutes of a group. The
request gets an id and an expiry; the adults are told (an event, an actionable notification on the chosen phone, the
household summary's approvals), and the first adult to answer decides, once: more time is extra time today
(add_bonus), maybe another amount than asked; "not now" starts a cooldown before that person may ask again. The asking
device sees the answer in its next status answer (the person's state document, "request").

Requests are kept outside the entry (an options change reloads it) but not across a restart: one left open then
expires, as it would have in the meantime.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import secrets
from typing import Any

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .const import DOMAIN, SIGNAL_PAIRINGS

EVENT_MORE_TIME_REQUESTED = "hearth_more_time_requested"
EVENT_MORE_TIME_ANSWERED = "hearth_more_time_answered"
# A phone notification's buttons: HEARTH_MORE|<id>|<minutes> (0: not now)
ACTION_PREFIX = "HEARTH_MORE|"
AMOUNTS = (15, 30, 45, 60)
OPEN_FOR = timedelta(minutes=30)
# An answered or expired request is still told to the device this long
SHOWN_FOR = timedelta(hours=2)
COOLDOWN = timedelta(minutes=10)
MAX_NOTE = 120

PENDING = "pending"
APPROVED = "approved"
DENIED = "denied"
EXPIRED = "expired"


@dataclass
class Ask:
    id: str
    person: str
    minutes: int
    group: str
    note: str
    device_id: str
    asked: datetime
    status: str = PENDING
    granted: int | None = None
    answered: datetime | None = None
    answered_by: str | None = None

    @property
    def expires(self) -> datetime:
        return self.asked + OPEN_FOR

    def device_view(self) -> dict[str, Any]:
        """What the asking device is told."""
        return {
            "id": self.id,
            "status": self.status,
            "minutes": self.granted if self.status == APPROVED else self.minutes,
            "asked_minutes": self.minutes,
            "group": self.group,
            "expires": self.expires.isoformat(),
            # When it was answered (or expired); null while pending
            "answered": self.answered.isoformat() if self.answered else None,
        }

    def approval_view(self, names) -> dict[str, Any]:
        """What an adult sees among the approvals."""
        return {
            "type": "more_time",
            "id": self.id,
            "person": self.person,
            "person_name": names(self.person),
            "minutes": self.minutes,
            "group": self.group,
            "note": self.note,
            "device_id": self.device_id,
            "asked": self.asked.isoformat(),
            "expires": self.expires.isoformat(),
        }


@dataclass
class _Store:
    asks: dict[str, Ask] = field(default_factory=dict)
    # person -> when a "not now" lets them ask again
    cooldown: dict[str, datetime] = field(default_factory=dict)


def _store(hass: HomeAssistant) -> _Store:
    return hass.data.setdefault(f"{DOMAIN}_asks", _Store())


class AskError(Exception):
    """Why a request wasn't taken: already_open (with the open one), cooldown (with seconds), bad_request."""

    def __init__(self, code: str, detail: Any = None) -> None:
        super().__init__(code)
        self.code = code
        self.detail = detail


class Asks:
    """The household's requests for more time."""

    def __init__(self, hass: HomeAssistant, hub) -> None:
        self.hass = hass
        self.hub = hub

    @property
    def _s(self) -> _Store:
        return _store(self.hass)

    def _tidy(self) -> None:
        now = dt_util.utcnow()
        for ask in list(self._s.asks.values()):
            if ask.status == PENDING and ask.expires <= now:
                ask.status = EXPIRED
                ask.answered = ask.expires
                self._clear_notification(ask)
            if ask.status != PENDING and (ask.answered or ask.asked) + SHOWN_FOR <= now:
                del self._s.asks[ask.id]

    def pending(self) -> list[Ask]:
        self._tidy()
        return sorted((a for a in self._s.asks.values() if a.status == PENDING), key=lambda a: a.asked)

    def latest_for(self, person: str) -> Ask | None:
        self._tidy()
        mine = [a for a in self._s.asks.values() if a.person == person]
        return max(mine, key=lambda a: a.asked) if mine else None

    def get(self, ask_id: str) -> Ask | None:
        self._tidy()
        return self._s.asks.get(ask_id)

    @callback
    def ask(self, person: str, minutes: int, group: str, note: str | None, device_id: str) -> Ask:
        """A new request; one open per person, none during a cooldown after "not now"."""
        if minutes not in AMOUNTS or self.hub.household.group(group) is None:
            raise AskError("bad_request")
        self._tidy()
        open_one = next((a for a in self._s.asks.values() if a.person == person and a.status == PENDING), None)
        if open_one is not None:
            raise AskError("already_open", open_one)
        now = dt_util.utcnow()
        until = self._s.cooldown.get(person)
        if until is not None and until > now:
            raise AskError("cooldown", int((until - now).total_seconds()) + 1)
        ask = Ask(
            id=secrets.token_urlsafe(9),
            person=person,
            minutes=minutes,
            group=group,
            note=(note or "").strip()[:MAX_NOTE],
            device_id=device_id,
            asked=now,
        )
        self._s.asks[ask.id] = ask
        names = self.hub.household.person_name
        self.hass.bus.async_fire(EVENT_MORE_TIME_REQUESTED, ask.approval_view(names))
        self._tell_adults(ask)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return ask

    @callback
    def answer(self, ask_id: str, minutes: int | None, by: str | None) -> Ask:
        """The first answer decides: minutes (any of the amounts, or another positive number) is more time, None is
        "not now". A later answer, or one to an expired request, is refused (not_open)."""
        ask = self.get(ask_id)
        if ask is None or ask.status != PENDING:
            raise AskError("not_open", ask)
        now = dt_util.utcnow()
        ask.answered = now
        ask.answered_by = by
        if minutes is None or minutes <= 0:
            ask.status = DENIED
            self._s.cooldown[ask.person] = now + COOLDOWN
        else:
            ask.status = APPROVED
            ask.granted = int(minutes)
            self.hub.household.add_bonus(ask.person, ask.group, ask.granted)
        self.hass.bus.async_fire(
            EVENT_MORE_TIME_ANSWERED,
            {"id": ask.id, "person": ask.person, "status": ask.status, "minutes": ask.granted, "by": by},
        )
        self._clear_notification(ask)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        # The device hears it in its next status answer: everyone's documents again now
        self.hub.household.recompute()
        return ask

    # Telling the adults

    def _phone(self) -> tuple[str, str] | None:
        from .apps import CONF_ASK_NOTIFY

        service = self.hub.entry.options.get(CONF_ASK_NOTIFY)
        if not service or "." not in service:
            return None
        domain, name = service.split(".", 1)
        return (domain, name) if self.hass.services.has_service(domain, name) else None

    def _tell_adults(self, ask: Ask) -> None:
        who = self.hub.household.person_name(ask.person)
        group = self.hub.household.group(ask.group)
        what = "" if ask.group == "all" or group is None else f" of {group.name}"
        message = f"{who} asks for {ask.minutes} more minutes{what}." + (f" “{ask.note}”" if ask.note else "")
        persistent_notification.async_create(
            self.hass,
            message + " Answer on Hearth's page or your phone.",
            title="More time?",
            notification_id=f"hearth_more_{ask.id}",
        )
        phone = self._phone()
        if phone is None:
            return
        # The asked amount first; Android shows three buttons, so: asked, the next one up, not now
        amounts = [ask.minutes] + [m for m in AMOUNTS if m > ask.minutes][:1]
        actions = [{"action": f"{ACTION_PREFIX}{ask.id}|{m}", "title": f"+{m} min"} for m in amounts]
        actions.append({"action": f"{ACTION_PREFIX}{ask.id}|0", "title": "Not now"})
        self.hass.async_create_task(
            self.hass.services.async_call(
                phone[0],
                phone[1],
                {
                    "title": "More time?",
                    "message": message,
                    "data": {"tag": f"hearth_more_{ask.id}", "actions": actions},
                },
                blocking=False,
            )
        )

    def _clear_notification(self, ask: Ask) -> None:
        persistent_notification.async_dismiss(self.hass, f"hearth_more_{ask.id}")
        phone = self._phone()
        if phone is not None:
            self.hass.async_create_task(
                self.hass.services.async_call(
                    phone[0],
                    phone[1],
                    {"message": "clear_notification", "data": {"tag": f"hearth_more_{ask.id}"}},
                    blocking=False,
                )
            )

    @callback
    def phone_answer(self, action: str, user_id: str | None) -> bool:
        """A button on the notification: HEARTH_MORE|<id>|<minutes>."""
        if not action.startswith(ACTION_PREFIX):
            return False
        parts = action.split("|")
        if len(parts) != 3 or not parts[2].isdigit():
            return True
        try:
            self.answer(parts[1], int(parts[2]) or None, user_id)
        except AskError:
            pass
        return True
