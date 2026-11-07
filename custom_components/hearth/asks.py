"""Asking for more time (docs/home-assistant-integration.md, Ask for more): one pipeline for every device.

A kid's device asks (a TV for its profile's person, a phone for its own) for 15, 30, 45 or 60 minutes of a group. The
request gets an id and an expiry; the adults are told (an event, an actionable notification on the chosen phone, the
household summary's approvals), and the first adult to answer decides, once: more time is extra time today
(add_bonus), maybe another amount than asked; "not now" starts a cooldown before that person may ask again. The asking
device sees the answer in its next status answer (the person's state document, "request").

An offer goes the other way (Configure > Offer more time): when a chosen group of a kid's runs out, the adults are
asked whether to give some more, with the same buttons; nothing is asked of the kid, and their devices aren't told
about it as a request of theirs. "Not now" to an offer starts no cooldown.

A request made on an Xbox or Windows PC (Microsoft Family Safety's microsoft_family_safety_request event) becomes an
ask too, for the person whose Family Safety account it is (Configure > Enforce), once per request id. The adults
answer it as any other; Hearth then approves it in Family Safety with the minutes chosen (approve_request takes 15 to
480) or denies it. Family Safety's requested time is passed on as it came (requested_time): its unit isn't documented,
so it isn't shown, and the adults pick the minutes. It gives no Hearth bonus and starts no cooldown, and it doesn't
stand in the way of a request from a Hearth device.

Requests are kept outside the entry (an options change reloads it) but not across a restart: one left open then
expires, as it would have in the meantime.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import secrets
from typing import Any

import logging

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .const import DOMAIN, SIGNAL_PAIRINGS

_LOGGER = logging.getLogger(__name__)

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
# Options: [{"person", "group", "minutes"}]: offer the adults more time when that group runs out
CONF_OFFER_MORE = "offer_more"

# Where a request came from: a Hearth device (or an offer), or Microsoft Family Safety
HEARTH = "hearth"
FAMILY_SAFETY = "family_safety"
FS_DOMAIN = "microsoft_family_safety"
# What a Family Safety request is offered as (its own requested time has no documented unit), and what
# approve_request takes
FS_SUGGESTED = 30
FS_MIN, FS_MAX = 15, 480

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
    # Offered to the adults when the group ran out, not asked by the kid
    offered: bool = False
    # A Family Safety request: its request id, platform, app and requested time as Microsoft gave them
    source: str = HEARTH
    external_id: str | None = None
    platform: str | None = None
    app_name: str | None = None
    requested_time: Any = None
    # Answered in the first-party app instead (family_safety), not by an adult in Hearth
    answered_in: str | None = None

    @property
    def external(self) -> bool:
        return self.source != HEARTH

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
            "offered": self.offered,
            "source": self.source,
            "status": self.status,
            "answered_in": self.answered_in,
            **(
                {"platform": self.platform, "app_name": self.app_name, "requested_time": self.requested_time}
                if self.external
                else {}
            ),
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
        mine = [a for a in self._s.asks.values() if a.person == person and not a.offered and not a.external]
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
        open_one = next(
            (a for a in self._s.asks.values() if a.person == person and a.status == PENDING and not a.external), None
        )
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
    def offer(self, person: str, group: str, minutes: int) -> Ask | None:
        """The adults are offered to give [minutes] more of [group] (it just ran out); one open per person."""
        if self.hub.household.group(group) is None or minutes <= 0:
            return None
        self._tidy()
        if any(a.person == person and a.status == PENDING and not a.external for a in self._s.asks.values()):
            return None
        ask = Ask(
            id=secrets.token_urlsafe(9),
            person=person,
            minutes=int(minutes),
            group=group,
            note="",
            device_id="",
            asked=dt_util.utcnow(),
            offered=True,
        )
        self._s.asks[ask.id] = ask
        self.hass.bus.async_fire(EVENT_MORE_TIME_REQUESTED, ask.approval_view(self.hub.household.person_name))
        self._tell_adults(ask)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return ask

    @callback
    def from_family_safety(self, person: str, data: dict[str, Any]) -> Ask | None:
        """A Family Safety request (its microsoft_family_safety_request event) as an ask of [person]'s; None for a
        request id already taken."""
        request_id = str(data.get("request_id") or "")
        if not request_id:
            return None
        self._tidy()
        if any(a.source == FAMILY_SAFETY and a.external_id == request_id for a in self._s.asks.values()):
            return None
        ask = Ask(
            id=secrets.token_urlsafe(9),
            person=person,
            minutes=FS_SUGGESTED,
            group="all",
            note="",
            device_id="",
            asked=dt_util.utcnow(),
            source=FAMILY_SAFETY,
            external_id=request_id,
            platform=str(data["platform"])[:32] if data.get("platform") else None,
            app_name=str(data["app_name"])[:80] if data.get("app_name") else None,
            requested_time=data.get("requested_time"),
        )
        self._s.asks[ask.id] = ask
        self.hass.bus.async_fire(EVENT_MORE_TIME_REQUESTED, ask.approval_view(self.hub.household.person_name))
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
            if not ask.offered and not ask.external:
                self._s.cooldown[ask.person] = now + COOLDOWN
        elif ask.source == FAMILY_SAFETY:
            ask.status = APPROVED
            ask.granted = max(FS_MIN, min(FS_MAX, int(minutes)))
        else:
            ask.status = APPROVED
            ask.granted = int(minutes)
            self.hub.household.add_bonus(ask.person, ask.group, ask.granted)
        if ask.source == FAMILY_SAFETY:
            self.hass.async_create_task(self._answer_family_safety(ask), "hearth family safety answer")
        self.hass.bus.async_fire(
            EVENT_MORE_TIME_ANSWERED,
            {"id": ask.id, "person": ask.person, "status": ask.status, "minutes": ask.granted, "by": by},
        )
        self._clear_notification(ask)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        # The device hears it in its next status answer: everyone's documents again now
        self.hub.household.recompute()
        return ask

    @callback
    def resolved_elsewhere(self, request_id: str, outcome: str | None, minutes: Any = None) -> Ask | None:
        """A Family Safety request answered in the Family Safety app (microsoft_family_safety_request_resolved, via
        app): its open ask closes as answered there. None when no open ask has that request id."""
        self._tidy()
        ask = next(
            (
                a
                for a in self._s.asks.values()
                if a.source == FAMILY_SAFETY and a.external_id == str(request_id) and a.status == PENDING
            ),
            None,
        )
        if ask is None:
            return None
        ask.answered = dt_util.utcnow()
        ask.answered_in = FAMILY_SAFETY
        ask.status = {"approved": APPROVED, "denied": DENIED}.get(str(outcome or "").lower(), EXPIRED)
        if ask.status == APPROVED and isinstance(minutes, (int, float)) and minutes > 0:
            ask.granted = int(minutes)
        self.hass.bus.async_fire(
            EVENT_MORE_TIME_ANSWERED,
            {
                "id": ask.id,
                "person": ask.person,
                "status": ask.status,
                "minutes": ask.granted,
                "by": None,
                "answered_in": FAMILY_SAFETY,
            },
        )
        self._clear_notification(ask)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        self.hub.household.recompute()
        return ask

    def answered_elsewhere(self, person: str) -> list[dict[str, Any]]:
        """The person's asks answered in a first-party app lately (shown for a while, as answered asks are)."""
        self._tidy()
        return [
            {
                "id": a.id,
                "status": a.status,
                "answered_in": a.answered_in,
                "text": "answered in the Family Safety app",
                "platform": a.platform,
                "answered": a.answered.isoformat() if a.answered else None,
            }
            for a in sorted(self._s.asks.values(), key=lambda a: a.asked)
            if a.person == person and a.answered_in
        ]

    async def _answer_family_safety(self, ask: Ask) -> None:
        """The answer in Family Safety: approve_request with the minutes, or deny_request. A failure is told."""
        approve = ask.status == APPROVED
        service = "approve_request" if approve else "deny_request"
        data: dict[str, Any] = {"request_id": ask.external_id}
        if approve:
            data["extension_minutes"] = ask.granted
        try:
            if not self.hass.services.has_service(FS_DOMAIN, service):
                raise ValueError(f"{FS_DOMAIN}.{service} isn't there")
            await self.hass.services.async_call(FS_DOMAIN, service, data, blocking=True)
        except Exception as err:  # noqa: BLE001 - told to the adults instead
            _LOGGER.warning("Hearth couldn't answer the Family Safety request %s: %s", ask.external_id, err)
            who = self.hub.household.person_name(ask.person)
            persistent_notification.async_create(
                self.hass,
                f"Hearth couldn't {'approve' if approve else 'deny'} {who}'s request in Family Safety ({err}). "
                "Answer it in the Family Safety app.",
                title="Family Safety request",
                notification_id=f"hearth_more_fs_{ask.id}",
            )

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
        if ask.offered:
            name = "screen time" if ask.group == "all" or group is None else group.name
            title = f"{who}'s {name} is used up"
            message = f"Give {who} {ask.minutes} more minutes today?"
        elif ask.source == FAMILY_SAFETY:
            where = f" on {ask.platform}" if ask.platform else ""
            app = f" for {ask.app_name}" if ask.app_name else ""
            title = "More time?"
            message = f"{who} asks for more time{where}{app} (Family Safety)."
        else:
            title = "More time?"
            message = f"{who} asks for {ask.minutes} more minutes{what}." + (f" “{ask.note}”" if ask.note else "")
        persistent_notification.async_create(
            self.hass,
            message + " Answer on Hearth's page or your phone.",
            title=title,
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
                    "title": title,
                    "message": message,
                    "data": {"tag": f"hearth_more_{ask.id}", "actions": actions},
                },
                blocking=False,
            )
        )

    def tell(self, title: str, message: str, tag: str) -> None:
        """News for the adults, the way requests reach them: a notification here, and on the chosen phone."""
        persistent_notification.async_create(self.hass, message, title=title, notification_id=tag)
        phone = self._phone()
        if phone is None:
            return
        self.hass.async_create_task(
            self.hass.services.async_call(
                phone[0], phone[1], {"title": title, "message": message, "data": {"tag": tag}}, blocking=False
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
