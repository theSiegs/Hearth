"""Telling the administrators a device is waiting to pair: Home Assistant's bell, linking to Hearth's page (its code
and Confirm are there), and each administrator's companion app, with Approve and Deny buttons that work from the
notification itself (they run hearth.pairing_answer as the administrator who pressed one; attention.py)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant

from .attention import ADMINS, NOTICE, Action, Item, attention

if TYPE_CHECKING:
    from .hub import Pairing

# Where the bell sends an administrator: Hearth's page lists the devices waiting, with their codes
PAIRING_PAGE = "/hearth"
ROLE_WORDS = {"adult": "an adult", "kid": "a kid"}


def pairing_notification_id(pairing_id: str) -> str:
    return f"hearth_pairing_{pairing_id}"


def asking(pairing: Pairing | Any, name: str | None = None) -> str:
    """Who and what is asking: "Alex's Glint (Pixel 9)", "Kitchen TV"."""
    name = name if name is not None else pairing.name
    model = getattr(pairing, "model", None)
    who = getattr(pairing, "for_name", None)
    what = f"{name} ({model})" if model and model.casefold() != (name or "").casefold() else name
    return f"{who}'s {what}" if who else what


def pairing_text(pairing: Pairing | Any, name: str | None = None) -> str:
    """The notification's headline: "Alex's Glint (Pixel 9) wants to pair as an adult"."""
    role = ROLE_WORDS.get(getattr(pairing, "for_role", None) or "")
    return f"{asking(pairing, name)} wants to pair{f' as {role}' if role else ''}"


def notify_pairing(hass: HomeAssistant, pairing_id: str, name: str, pairing: Pairing | None = None) -> None:
    """The bell (without the code: everyone who uses Home Assistant sees it), and the administrators' phones with the
    code and Approve / Deny. Approve pairs a phone as the person it named, when that's one of the household's people
    (else it's chosen on Hearth's page)."""
    headline = pairing_text(pairing, name) if pairing is not None else f"{name} wants to pair"
    code = getattr(pairing, "code", None)
    actions: tuple[Action, ...] = ()
    if pairing is not None:
        data = {"pairing_id": pairing_id}
        approve = (
            (Action("approve", "Approve", "hearth.pairing_answer", {**data, "answer": "approve", "person": pairing.for_person}),)
            if pairing.kind != "mobile" or pairing.for_person
            else ()
        )
        actions = (*approve, Action("deny", "Deny", "hearth.pairing_answer", {**data, "answer": "deny"}))
    phone_text = (
        f"{headline}. Code {code[:3]} {code[3:]}: approve only if the device shows the same code."
        if code
        else f"{headline}."
    )
    if pairing is not None and pairing.kind == "mobile" and not pairing.for_person:
        phone_text += " Choose whose phone it is on Hearth's page."
    attention(hass).notify(
        Item(
            pairing_notification_id(pairing_id),
            phone_text,
            title="A Hearth device wants to pair",
            urgency=NOTICE,
            audience=ADMINS,
            actions=actions,
            bell=True,
            phone=pairing is not None,
            expires=getattr(pairing, "expires", None),
            once=True,
            bell_text=(
                f"**{headline}**. Open [Hearth's page]({PAIRING_PAGE}), check it shows the same code as the device, "
                "and confirm. An adult in Hearth can confirm their own phone on the phone itself. It expires in 10 "
                "minutes."
            ),
        )
    )


def clear_pairing(hass: HomeAssistant, pairing_id: str) -> None:
    """The pairing was answered: its notification goes, from the bell and the phones."""
    attention(hass).clear(pairing_notification_id(pairing_id), audience=ADMINS, bell_too=True, phone=True)
