"""Telling an administrator a device is waiting to pair: a notification in Home Assistant's bell, linking to it."""

from __future__ import annotations

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant


def pairing_notification_id(pairing_id: str) -> str:
    return f"hearth_pairing_{pairing_id}"


def notify_pairing(hass: HomeAssistant, pairing_id: str, name: str) -> None:
    persistent_notification.async_create(
        hass,
        f"**{name}** wants to pair with Hearth. Open [Devices & services](/config/integrations/dashboard), find it under "
        "Discovered, check it shows the same code as the TV or phone, and confirm. It expires in 10 minutes.",
        title="A Hearth device wants to pair",
        notification_id=pairing_notification_id(pairing_id),
    )
