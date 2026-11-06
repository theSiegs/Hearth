"""Push to phones (H-6): a contentless "changed" ping over ntfy when a phone's state document changes.

Optional, off unless the household names an ntfy server (Configure > Push to phones, or Hearth's page). Each phone gets
its own random topic when it pairs (the topic is the only thing that addresses it, so it's as long as a secret), handed
to it with its pair and status answers. When the phone's state document has a version the phone hasn't had (not in a
status answer, not in an earlier ping), the integration publishes "changed" to its topic, a few seconds after the
change (many come together) and at most every PUSH_MIN_GAP per phone. The phone then posts its status, with its secret,
and gets the document in the answer. Nothing else is ever published: no name, no number, no version.
See docs/home-assistant-integration.md, Away from home.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any
from urllib.parse import urlsplit

import aiohttp
import voluptuous as vol

from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .const import (
    CONF_KIND,
    CONF_PUSH_SERVER,
    CONF_PUSH_TOPIC,
    DOMAIN,
    KIND_MOBILE,
    SIGNAL_PAIRINGS,
    SIGNAL_PEOPLE,
    SIGNAL_WATCH,
)

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

# Changes come together (a status post recomputes everyone): one ping for them, this long after the first
PUSH_DEBOUNCE = timedelta(seconds=5)
# A phone is pinged at most this often (a playing kid's minutes left change every minute)
PUSH_MIN_GAP = timedelta(seconds=30)
PUSH_TIMEOUT = 10
# All a ping ever says
PING_BODY = "changed"


def new_topic() -> str:
    """A phone's topic: 32 characters of ntfy's topic alphabet (A-Z a-z 0-9 _ -), random, so nobody can guess it."""
    return secrets.token_urlsafe(24)


def clean_server(value: Any) -> str | None:
    """An ntfy server's address, http(s)://host[:port][/path], without a trailing slash; None for none. Raises
    vol.Invalid for anything else (credentials, a query or a fragment in it included)."""
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    if not isinstance(value, str):
        raise vol.Invalid("Give the server's address, like https://ntfy.example.com")
    url = value.strip().rstrip("/")
    try:
        parts = urlsplit(url)
        parts.port  # noqa: B018 - a bad port raises
    except ValueError as err:
        raise vol.Invalid("Give the server's address, like https://ntfy.example.com") from err
    if (
        parts.scheme not in ("http", "https")
        or not parts.hostname
        or parts.username
        or parts.password
        or parts.query
        or parts.fragment
        or any(c.isspace() for c in url)
        or len(url) > 255
    ):
        raise vol.Invalid("Give the server's address, like https://ntfy.example.com")
    return url


def _shared(hass: HomeAssistant) -> dict[str, dict[str, Any]]:
    """What each phone has had (version) and when it was last pinged: kept while the household reloads."""
    return hass.data.setdefault(f"{DOMAIN}_push", {"known": {}, "pinged": {}})


def push_answer(server: str | None, topic: str | None) -> dict[str, str] | None:
    return {"server": server, "topic": topic} if server and topic else None


class PushChannel:
    """The household's pings to its phones."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._cancel: CALLBACK_TYPE | None = None
        self._unsubs: list[CALLBACK_TYPE] = []

    @property
    def server(self) -> str | None:
        try:
            return clean_server(self.hub.entry.options.get(CONF_PUSH_SERVER))
        except vol.Invalid:
            return None

    def answer_for(self, device_id: str) -> dict[str, str] | None:
        """What a phone is told: {"server", "topic"}, or None while there's no server (or it's a TV)."""
        device = self.hub.devices.get(device_id, {})
        if device.get(CONF_KIND) != KIND_MOBILE:
            return None
        return push_answer(self.server, device.get(CONF_PUSH_TOPIC))

    @callback
    def delivered(self, device_id: str, version: str) -> None:
        """The phone has this version (a status answer carried it): no ping for it."""
        _shared(self.hass)["known"][device_id] = version

    @callback
    def start(self) -> None:
        self._unsubs = [
            async_dispatcher_connect(self.hass, signal, self.changed)
            for signal in (SIGNAL_PEOPLE, SIGNAL_WATCH, SIGNAL_PAIRINGS)
        ]
        # Anything that changed while the household reloaded (an options change) or Home Assistant was stopped
        self.changed()

    @callback
    def stop(self) -> None:
        for unsub in self._unsubs:
            unsub()
        self._unsubs = []
        if self._cancel is not None:
            self._cancel()
            self._cancel = None

    @callback
    def changed(self, *_args: Any) -> None:
        if self.server is None or self._cancel is not None:
            return
        self._cancel = async_call_later(self.hass, PUSH_DEBOUNCE, self._check)

    async def _check(self, _now: datetime | None = None) -> None:
        self._cancel = None
        server = self.server
        if server is None:
            return
        shared = _shared(self.hass)
        now = dt_util.utcnow()
        later: datetime | None = None
        topics: list[str] = []
        for device_id, device in self.hub.devices.items():
            topic = device.get(CONF_PUSH_TOPIC)
            if device.get(CONF_KIND) != KIND_MOBILE or not topic:
                continue
            version = self.hub.household.document_for(device_id)["version"]
            if shared["known"].get(device_id) == version:
                continue
            last = shared["pinged"].get(device_id)
            if last is not None and now - last < PUSH_MIN_GAP:
                due = last + PUSH_MIN_GAP
                later = due if later is None else min(later, due)
                continue
            shared["known"][device_id] = version
            shared["pinged"][device_id] = now
            topics.append(topic)
        if later is not None:
            self._cancel = async_call_later(self.hass, (later - now).total_seconds(), self._check)
        if topics:
            await asyncio.gather(*(self._publish(server, topic) for topic in topics))

    async def _publish(self, server: str, topic: str) -> None:
        """POST "changed" to the phone's topic. A failure is logged (never the topic) and not retried: the phone
        still gets the document with its next status answer."""
        session = async_get_clientsession(self.hass)
        try:
            async with asyncio.timeout(PUSH_TIMEOUT):
                async with session.post(
                    f"{server}/{topic}", data=PING_BODY, headers={"Content-Type": "text/plain"}
                ) as response:
                    if response.status >= 400:
                        _LOGGER.warning("The push server %s answered %s to a ping", server, response.status)
        except (aiohttp.ClientError, TimeoutError) as err:
            _LOGGER.warning("Couldn't reach the push server %s: %s", server, err.__class__.__name__)
