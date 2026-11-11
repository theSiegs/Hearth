"""One-shot commands for a Hearth TV (hearth.play_on_tv): queued here, handed to the TV in its state document.

Home Assistant can't reach a TV: the TV posts its status, and the answer carries its state document. A command waits in
the document's `commands` until the TV says it's done (`commands_done` in a later status) or it expires, so an answer
that never arrived is simply handed over again; the TV runs each id once. Kept outside the entry, so an options change
(which reloads it) doesn't lose one; not kept across a restart (they last minutes).
See docs/home-assistant-integration.md, Play on a TV.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
import re
import secrets
from typing import Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .const import DOMAIN, SIGNAL_COMMANDS
from .status import text
from .watch import video_id_of

EVENT_COMMAND_DONE = "hearth_command_done"

PLAY = "play"
# A command waits this long for the TV (it posts at least every 2 minutes while it's on)
COMMAND_EXPIRES = timedelta(minutes=3)
# A new play replaces one still waiting for the TV: only the last ask is played
MAX_URL = 2048

_PACKAGE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_URL = re.compile(r"^https?://[^\s/]+\S*$", re.IGNORECASE)
_PROFILE = re.compile(r"^user:\d+(:[a-z0-9._-]+)?$")


def what_to_play(what: str) -> dict[str, str] | None:
    """{"video_id"} for a YouTube or HearthTube video (an id or a YouTube link), {"package"} for an app, {"url"} for
    any other http(s) link; None when it's none of them."""
    value = what.strip()
    if not value or len(value) > MAX_URL or any(c in value for c in "\r\n\t"):
        return None
    if _VIDEO_ID.match(value):
        return {"video_id": value}
    if _URL.match(value):
        if re.match(r"^https?://([a-z0-9-]+\.)*(youtube\.com|youtu\.be)/", value, re.IGNORECASE) and (
            video := video_id_of(value)
        ):
            if _VIDEO_ID.match(video):
                return {"video_id": video}
        return {"url": value}
    if _PACKAGE.match(value) and len(value) <= 255:
        return {"package": value}
    return None


def is_profile_id(value: str) -> bool:
    return bool(_PROFILE.match(value))


@dataclass
class Command:
    id: str
    device_id: str
    type: str
    target: dict[str, str]
    profile_id: str | None
    created: datetime
    expires: datetime

    def document(self) -> dict[str, Any]:
        """What the TV is handed."""
        return {
            "id": self.id,
            "type": self.type,
            **self.target,
            "profile_id": self.profile_id,
            "created": self.created.isoformat(),
            "expires": self.expires.isoformat(),
        }


def _queue(hass: HomeAssistant) -> dict[str, list[Command]]:
    return hass.data.setdefault(f"{DOMAIN}_commands", {})


class Commands:
    """The household's waiting commands, per TV."""

    def __init__(self, hass: HomeAssistant) -> None:
        self.hass = hass

    @property
    def _by_tv(self) -> dict[str, list[Command]]:
        return _queue(self.hass)

    @callback
    def play(self, device_id: str, target: dict[str, str], profile_id: str | None) -> Command:
        """Queues a play for the TV: it replaces one still waiting there (only the last ask is played)."""
        now = dt_util.utcnow()
        self.prune(now)
        waiting = self._by_tv.setdefault(device_id, [])
        for old in [c for c in waiting if c.type == PLAY]:
            waiting.remove(old)
            self._done(old, "replaced", None)
        command = Command(
            id=secrets.token_urlsafe(12),
            device_id=device_id,
            type=PLAY,
            target=target,
            profile_id=profile_id,
            created=now,
            expires=now + COMMAND_EXPIRES,
        )
        waiting.append(command)
        # The TV holding a wait hears it in seconds, not at its next post
        async_dispatcher_send(self.hass, SIGNAL_COMMANDS)
        return command

    def document_for(self, device_id: str) -> list[dict[str, Any]]:
        now = dt_util.utcnow()
        return [c.document() for c in self._by_tv.get(device_id, []) if c.expires > now]

    @callback
    def prune(self, now: datetime | None = None) -> None:
        """Drops expired commands, each told as expired."""
        now = now or dt_util.utcnow()
        for device_id, waiting in list(self._by_tv.items()):
            for gone in [c for c in waiting if c.expires <= now]:
                waiting.remove(gone)
                self._done(gone, "expired", None)
            if not waiting:
                del self._by_tv[device_id]

    @callback
    def take_done(self, device_id: str, reported: list[dict[str, Any]]) -> None:
        """The TV's `commands_done`: each one it ran (or couldn't) leaves the queue and is told once."""
        waiting = self._by_tv.get(device_id, [])
        for report in reported:
            command = next((c for c in waiting if c.id == report["id"]), None)
            if command is None:
                continue
            waiting.remove(command)
            self._done(command, report["result"], report.get("error"))
        if not waiting:
            self._by_tv.pop(device_id, None)

    @callback
    def forget(self, device_id: str) -> None:
        self._by_tv.pop(device_id, None)

    def _done(self, command: Command, result: str, error: str | None) -> None:
        self.hass.bus.async_fire(
            EVENT_COMMAND_DONE,
            {
                "device_id": command.device_id,
                "id": command.id,
                "type": command.type,
                "result": result,
                "error": error,
            },
        )

