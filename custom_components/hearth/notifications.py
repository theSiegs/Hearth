"""Telling an administrator a device is waiting to pair: a notification in Home Assistant's bell, linking to it."""

from __future__ import annotations

from homeassistant.core import HomeAssistant

from .attention import ADMINS, NOTICE, Item, attention


def pairing_notification_id(pairing_id: str) -> str:
    return f"hearth_pairing_{pairing_id}"


def notify_pairing(hass: HomeAssistant, pairing_id: str, name: str) -> None:
    attention(hass).notify(
        Item(
            pairing_notification_id(pairing_id),
            f"**{name}** wants to pair with Hearth. Open [Devices & services](/config/integrations/dashboard), find it "
            "under Discovered, check it shows the same code as the TV or phone, and confirm. It expires in 10 minutes.",
            title="A Hearth device wants to pair",
            urgency=NOTICE,
            audience=ADMINS,
            bell=True,
            phone=False,
        )
    )


def clear_pairing(hass: HomeAssistant, pairing_id: str) -> None:
    """The pairing was answered: its notification goes."""
    attention(hass).clear(pairing_notification_id(pairing_id), audience=ADMINS, bell_too=True)
