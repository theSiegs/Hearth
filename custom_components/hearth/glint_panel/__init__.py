"""Glint Panel: wall tablets configured from Home Assistant (docs/contracts/panel-config.md).

A package of its own so it can move: to its own glint_panel integration, or partly into a voice integration. It
imports nothing of the integration serving it; what it needs comes through PanelHost (host.py). The serving
integration's setup attaches a host (Panels.get(...).async_attach) and registers the commands and services once
(async_register); its platform files add the entities (entities.async_setup_platform).
"""

from __future__ import annotations

from homeassistant.core import HomeAssistant

from .const import IDENTIFIER_PREFIX, KIND, signal_added
from .entities import async_setup_platform
from .host import PanelHost
from .manager import Panels
from .services import async_register_services
from .ws import async_register_commands

__all__ = [
    "IDENTIFIER_PREFIX",
    "KIND",
    "PanelHost",
    "Panels",
    "async_register",
    "async_setup_platform",
    "signal_added",
]


def async_register(hass: HomeAssistant, domain: str) -> None:
    """The panels' WebSocket commands and services, once a Home Assistant run."""
    async_register_commands(hass, domain)
    async_register_services(hass, domain)
