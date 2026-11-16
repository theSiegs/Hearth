"""Phone approval of a switch into a PIN-locked Google TV profile, asked by the integration for a paired TV.

A paired TV that has no Home Assistant token of its own can't call notify services or listen for the phone's answer.
It asks the integration instead (docs/home-assistant-integration.md, "Phone approval through the integration"):

- POST /api/hearth/device/<id>/switch_approval {"profile_id", "phone"?} starts a request for that TV profile. The
  profile must be mapped to a person who is an adult on Hearth's page. The phones asked are "phone" (the companion
  app's notify service chosen on the household's TVs) when Home Assistant has it, else the person's companion apps
  (phones.py person_phones). Each gets Allow and Deny (action ids HEARTH_SWITCH_ALLOW_<id> and
  HEARTH_SWITCH_DENY_<id>); the id is 128 random bits, used once.
- GET /api/hearth/device/<id>/switch_approval/<request id>?timeout=<s> answers its status as soon as it isn't
  "pending" (or after <s> seconds): pending, allowed, denied, expired or withdrawn.
- DELETE the same withdraws it (someone at the TV uses the remote, or the PIN screen went).

The first answer decides; the notification then leaves every phone asked (and Home Assistant's own list). Anyone with
Home Assistant's app may answer (the household's choice: whoever holds the profile owner's phone); who answered is
logged and in the hearth_switch_approval event. Only the TV that asked can read or withdraw a request.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime
import logging
import re
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import CALLBACK_TYPE, Event, HomeAssistant, callback
from homeassistant.helpers.event import async_call_later

from .const import CONF_ROLES
from .phones import person_phones

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

ACTION_PREFIX = "HEARTH_SWITCH_"
ALLOW = "ALLOW_"
DENY = "DENY_"
TAG_PREFIX = "hearth-switch-"
EVENT_SWITCH_APPROVAL = "hearth_switch_approval"
# How long the phones have to answer (as the TV's own phone approval)
ANSWER_SECONDS = 120
# A finished request stays readable this long, for a TV whose wait was cut off
KEEP_SECONDS = 300
# A status wait is held at most this long
WAIT_MAX = 55

PENDING = "pending"
ALLOWED = "allowed"
DENIED = "denied"
EXPIRED = "expired"
WITHDRAWN = "withdrawn"

_SERVICE = re.compile(r"^mobile_app_[a-z0-9_]{1,100}$")
_ID = re.compile(r"^[0-9a-f]{32}$")


class SwitchApprovalError(Exception):
    """Why a request couldn't start: no_person, not_adult, no_phone or not_sent."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass
class SwitchRequest:
    id: str
    device_id: str
    profile_id: str
    person: str
    services: list[str]
    status: str = PENDING
    answered_by: str | None = None
    changed: asyncio.Event = field(default_factory=asyncio.Event)
    unsub: CALLBACK_TYPE | None = None

    def view(self) -> dict[str, Any]:
        return {"id": self.id, "status": self.status}


def valid_service(service: Any) -> bool:
    return isinstance(service, str) and bool(_SERVICE.match(service))


def valid_id(request_id: Any) -> bool:
    return isinstance(request_id, str) and bool(_ID.match(request_id))


def parse_action(action: str) -> tuple[str, bool] | None:
    """(request id, allowed) for one of these requests' action ids, else None."""
    if not action.startswith(ACTION_PREFIX):
        return None
    rest = action[len(ACTION_PREFIX):]
    for prefix, allowed in ((ALLOW, True), (DENY, False)):
        if rest.startswith(prefix) and valid_id(rest[len(prefix):]):
            return rest[len(prefix):], allowed
    return None


class SwitchApprovals:
    """The requests waiting for a phone, and the finished ones for a while; at most one waiting per TV."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._requests: dict[str, SwitchRequest] = {}
        self._unsub: CALLBACK_TYPE | None = None

    def start(self) -> None:
        self._unsub = self.hass.bus.async_listen("mobile_app_notification_action", self._on_action)

    def stop(self) -> None:
        if self._unsub:
            self._unsub()
            self._unsub = None
        for request in list(self._requests.values()):
            if request.unsub:
                request.unsub()
            request.unsub = None
        self._requests.clear()

    def phones_for(self, person: str, chosen: str | None) -> list[str]:
        """The chosen phone when Home Assistant has it, else the person's companion apps."""
        if valid_service(chosen) and self.hass.services.has_service("notify", chosen):
            return [chosen]
        return [service for service, _ in person_phones(self.hass, person)]

    async def ask(self, device_id: str, profile_id: str, chosen: str | None) -> SwitchRequest:
        person = self.hub.household.profile_person(device_id, profile_id)
        if not person:
            raise SwitchApprovalError("no_person")
        if self.hub.entry.options.get(CONF_ROLES, {}).get(person) != "adult":
            raise SwitchApprovalError("not_adult")
        services = self.phones_for(person, chosen)
        if not services:
            raise SwitchApprovalError("no_phone")
        # A TV's newer request replaces its waiting one (another PIN screen)
        for old in [r for r in self._requests.values() if r.device_id == device_id and r.status == PENDING]:
            await self._finish(old, WITHDRAWN)
        request = SwitchRequest(secrets.token_hex(16), device_id, profile_id, person, services)
        name = self.hub.household.person_name(person)
        tv = self.hub.devices.get(device_id, {}).get("name") or "the TV"
        sent = 0
        for service in services:
            try:
                await self.hass.services.async_call(
                    "notify",
                    service,
                    {
                        "title": f"TV: switch to {name}'s profile?",
                        "message": "Someone at the TV wants to open your profile. Allow it, and Hearth enters your "
                        "Google TV PIN.",
                        "data": push_data(request.id),
                    },
                    blocking=True,
                )
                sent += 1
            except Exception as err:  # noqa: BLE001 - one phone failing doesn't stop the others
                _LOGGER.warning("A switch approval couldn't reach %s: %s", service, err)
        if not sent:
            raise SwitchApprovalError("not_sent")
        self._persistent(request, name, tv)
        self._requests[request.id] = request
        request.unsub = async_call_later(self.hass, ANSWER_SECONDS, self._expired(request))
        _LOGGER.info("Asked %s's phone(s) to allow a switch on %s", person, tv)
        return request

    def get(self, device_id: str, request_id: str) -> SwitchRequest | None:
        """A request of this TV's, or None (another TV's is never shown)."""
        request = self._requests.get(request_id)
        return request if request is not None and request.device_id == device_id else None

    async def wait(self, request: SwitchRequest, timeout: float) -> str:
        if request.status == PENDING:
            try:
                await asyncio.wait_for(request.changed.wait(), timeout)
            except asyncio.TimeoutError:
                pass
        return request.status

    async def withdraw(self, request: SwitchRequest) -> None:
        if request.status == PENDING:
            _LOGGER.info("A switch approval was withdrawn by the TV")
            await self._finish(request, WITHDRAWN)

    async def _on_action(self, event: Event) -> None:
        parsed = parse_action(str(event.data.get("action") or ""))
        if parsed is None:
            return
        request_id, allowed = parsed
        request = self._requests.get(request_id)
        # Used once: an answer after the first (or after it ended) does nothing
        if request is None or request.status != PENDING:
            return
        user_id = event.context.user_id
        by = _person_of(self.hass, user_id)
        request.answered_by = by or user_id
        _LOGGER.info(
            "A switch into %s's profile was %s by %s",
            request.person,
            "allowed" if allowed else "denied",
            by or (f"user {user_id}" if user_id else "someone without a user"),
        )
        self.hass.bus.async_fire(
            EVENT_SWITCH_APPROVAL,
            {
                "device_id": request.device_id,
                "profile_id": request.profile_id,
                "person": request.person,
                "answer": ALLOWED if allowed else DENIED,
                "by": by,
                "user_id": user_id,
            },
        )
        await self._finish(request, ALLOWED if allowed else DENIED)

    def _expired(self, request: SwitchRequest):
        @callback
        def expired(_now: datetime) -> None:
            request.unsub = None
            if request.status == PENDING:
                self.hass.async_create_task(self._finish(request, EXPIRED))
            else:
                self._requests.pop(request.id, None)

        return expired

    async def _finish(self, request: SwitchRequest, status: str) -> None:
        if request.status != PENDING:
            return
        request.status = status
        request.changed.set()
        if request.unsub:
            request.unsub()
        # Readable a while longer, then gone
        request.unsub = async_call_later(self.hass, KEEP_SECONDS, self._expired(request))
        await self._clear(request)

    async def _clear(self, request: SwitchRequest) -> None:
        """Off every phone asked, and Home Assistant's own list."""
        for service in request.services:
            try:
                await self.hass.services.async_call(
                    "notify",
                    service,
                    {"message": "clear_notification", "data": {"tag": TAG_PREFIX + request.id}},
                    blocking=True,
                )
            except Exception as err:  # noqa: BLE001
                _LOGGER.debug("Couldn't clear a switch approval on %s: %s", service, err)
        try:
            from homeassistant.components import persistent_notification

            persistent_notification.async_dismiss(self.hass, TAG_PREFIX + request.id)
        except Exception:  # noqa: BLE001
            pass

    def _persistent(self, request: SwitchRequest, name: str, tv: str) -> None:
        try:
            from homeassistant.components import persistent_notification

            persistent_notification.async_create(
                self.hass,
                f"Someone at {tv} wants to open this profile. Answer from the notification on the phone (Allow or "
                f"Deny). The request ends by itself after 2 minutes.",
                title=f"TV: switch to {name}'s profile?",
                notification_id=TAG_PREFIX + request.id,
            )
        except Exception:  # noqa: BLE001
            pass


def push_data(request_id: str) -> dict[str, Any]:
    """The companion app's extras: Allow and Deny; a tap on the notification itself does nothing and keeps it."""
    return {
        "actions": [
            {"action": f"{ACTION_PREFIX}{ALLOW}{request_id}", "title": "Allow"},
            {"action": f"{ACTION_PREFIX}{DENY}{request_id}", "title": "Deny"},
        ],
        "tag": TAG_PREFIX + request_id,
        "priority": "high",
        "ttl": 0,
        "timeout": ANSWER_SECONDS,
        "channel": "Hearth",
        "sticky": "true",
        "clickAction": "noAction",
    }


def _person_of(hass: HomeAssistant, user_id: str | None) -> str | None:
    if not user_id:
        return None
    return next((s.entity_id for s in hass.states.async_all("person") if s.attributes.get("user_id") == user_id), None)
