"""Home Assistant's bell (persistent notifications): an item's notice, by its tag, for everyone who uses Home
Assistant."""

from __future__ import annotations

from typing import TYPE_CHECKING

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant

if TYPE_CHECKING:
    from ..attention import Item


def show(hass: HomeAssistant, item: Item) -> None:
    """The item in the bell (in place of one with its tag): its bell text when it has one, else its text."""
    persistent_notification.async_create(
        hass, item.bell_text or item.text, title=item.title, notification_id=item.channel_tag
    )


def dismiss(hass: HomeAssistant, tag: str) -> None:
    persistent_notification.async_dismiss(hass, tag)
