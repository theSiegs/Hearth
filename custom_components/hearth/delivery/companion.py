"""The Home Assistant companion app (phones.py): an item on its audience's phones, tagged, with its buttons.

A button with a service goes out as HEARTH_ACT|<item key>|<n> (attention.py runs it); one without goes out as its own
id (HEARTH_MORE|..., HEARTH_APP|...), as phones already know it. Every push carries a tag starting with hearth_: a phone
app that shows Hearth's notices (Glint) goes by that prefix.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant

from .. import phones

if TYPE_CHECKING:
    from ..attention import Item


def buttons(item: Item) -> list[dict[str, str]]:
    from ..attention import ACT_PREFIX

    return [
        {"action": f"{ACT_PREFIX}{item.key}|{n}" if action.service or action.dismiss else action.id, "title": action.label}
        for n, action in enumerate(item.actions)
    ]


def send(hass: HomeAssistant, options: Mapping[str, Any], to: list[phones.Phone], item: Item) -> list[str]:
    """The item on the phones [to]; the services told."""
    data: dict[str, Any] = {"tag": item.channel_tag}
    if item.actions:
        data["actions"] = buttons(item)
    return phones.send(hass, options, item.title, item.text, data, ask_id=item.opens, to=to)


def clear(hass: HomeAssistant, options: Mapping[str, Any], to: list[phones.Phone], tag: str) -> None:
    phones.clear(hass, options, tag, to=to)
