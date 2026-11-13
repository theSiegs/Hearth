"""A button of a TV's notice (docs/home-assistant-integration.md, The device's side of the API, Notices).

A TV that shows notices (cap "notices") shows the attention items for TVs in its adult profiles. Its secret alone never
runs anything: a press comes with a Parent PIN, checked as verify_pin checks one (the same per-adult PINs and the
device's shared lockout), and the button's service then runs as that adult; or it asks a parent's phone, and an adult's
tap there runs it as them (an attention item of its own, cleared with the notice, gone after APPROVE_FOR). Either way
the history says who answered.

The adult behind a PIN: the PIN is one adult person's (Configure > Parent PINs); the service runs as that person's
Home Assistant user when they have one that's an adult (or an administrator), else as the household's own (no user,
like an automation), and the history names the person either way.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timedelta
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .attention import ADULTS, NOTICE, Action, Item, attention
from .auth import is_adult_user
from .const import CAP_NOTICES, KIND_TV
from .history import NOTICE_ANSWER

if TYPE_CHECKING:
    from .hub import HearthHub

# A phone approval waits this long for an adult's tap
APPROVE_FOR = timedelta(minutes=10)
# Its item key: approve:<notice key>:<button>:<random>; its phone tag: hearth_approve:<notice key> (one per notice)
APPROVE_PREFIX = "approve:"
APPROVE_TAG = "hearth_approve:"
VIA_PIN = "pin"
VIA_PHONE = "phone"


def shown(hub: HearthHub, device_id: str) -> dict[str, Item]:
    """The items this device's state document has as notices, by key: a TV's with the cap only."""
    if hub.kind(device_id) != KIND_TV or not hub.has_cap(device_id, CAP_NOTICES):
        return {}
    people = {p for p in hub.household.device_profile_people(device_id).values() if p}
    return {item.key: item for item in hub.attention.tv_items(people)}


async def adult_user(hass: HomeAssistant, hub: HearthHub, person: str) -> str | None:
    """The Home Assistant user a PIN's adult acts as: their person's user, when it's an adult's (or an
    administrator's); else None (the household's own, as an automation)."""
    state = hass.states.get(person)
    user_id = state.attributes.get("user_id") if state else None
    user = await hass.auth.async_get_user(user_id) if isinstance(user_id, str) else None
    return user.id if user is not None and is_adult_user(hass, hub, user) else None


def _person_of(hass: HomeAssistant, user_id: str | None) -> str | None:
    if not user_id:
        return None
    return next((s.entity_id for s in hass.states.async_all("person") if s.attributes.get("user_id") == user_id), None)


@callback
def log_answer(
    hub: HearthHub | None, about: Mapping[str, Any], via: str, *, person: str | None = None, user_id: str | None = None
) -> None:
    """Who answered a notice's button, in the history: their person (else their user id), about the kid it's for."""
    if hub is None:
        return
    by = person or _person_of(hub.hass, user_id)
    hub.household.history.log(
        NOTICE_ANSWER,
        about.get("person") or by or "",
        key=about.get("notice"),
        action=about.get("action"),
        device=about.get("device"),
        via=via,
        by=by,
        user=None if by else user_id,
    )


def ask_phone(hub: HearthHub, device_id: str, notice: Item, n: int) -> Item:
    """Asks the adults' phones to approve button [n] of [notice], pressed on the TV [device_id]: an item with that one
    button (run as the adult who taps it, as any item's) and "Don't allow"; replaces an earlier one for the notice,
    goes with it, and comes off the phones after APPROVE_FOR."""
    hass = hub.hass
    chosen = notice.actions[n]
    kid = notice.about.get("person")
    who = hub.household.person_name(kid) if kid else None
    label = chosen.label[:1].lower() + chosen.label[1:]
    tv = hub.devices.get(device_id, {}).get("name") or "a TV"
    key = f"{APPROVE_PREFIX}{notice.key}:{n}:{secrets.token_hex(4)}"
    tag = f"{APPROVE_TAG}{notice.key}"
    item = Item(
        key,
        f"{notice.title}. Asked on {tv}." if notice.title else f"Asked on {tv}.",
        title=f"Approve {label} for {who}?" if who else f"Approve {label}?",
        urgency=NOTICE,
        audience=ADULTS,
        actions=(
            Action(chosen.id, chosen.label, chosen.service, dict(chosen.data)),
            Action("dont_allow", "Don't allow", dismiss=True),
        ),
        tag=tag,
        # About a kid: never on Home Assistant's bell
        bell=False,
        expires=dt_util.utcnow() + APPROVE_FOR,
        about={"person": kid, "notice": notice.key, "action": n, "device": device_id},
        follows=notice.key,
        once=True,
    )

    @callback
    def expired(_now: datetime) -> None:
        # Off the phones (an answer, "Don't allow", the notice going or a newer approval cancelled this first). Gone
        # from the items by now, so cleared by its tag
        item.on_clear = None
        layer = attention(hass)
        if layer.item(key) is not None:
            layer.clear(key)
        else:
            layer.clear(tag, phone=True)

    item.on_clear = async_call_later(hass, APPROVE_FOR, expired)
    hub.attention.notify(item)
    return item
