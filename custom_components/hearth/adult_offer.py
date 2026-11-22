"""Make this person an adult? (docs/home-assistant-integration.md, People, Adults' own phones).

An adult's own phone (Glint, or any Hearth client signed in to Home Assistant as their own user) reads the household
only once their person is an adult on Hearth's page (auth.is_adult_user). That step is easy to miss, so when a user who
isn't one is refused a household read (websocket._may_read, glint_api._adult), Hearth asks the administrators once:
"<Name> signed in from a phone. Make them an adult in Hearth?", with Make adult and Not now.

Only someone who could be an adult is offered: an active user Home Assistant didn't make itself, who isn't an
administrator, with exactly one person whose user it is; that person has no role on Hearth's page yet (a kid or an
explicit choice is never overridden), and nothing of a kid's: no parental-controls account (Family Link, Family Safety,
Nintendo), no screen time source, no lock, no budget, schedule or bonus.

A refused read comes on every poll: each user is looked at once per Home Assistant run (kept outside the entry, so an
options change's reload doesn't look again). Each person is asked at most once: asked, declined and made are stored
across restarts. An offer still open after a restart is put back (adopt) so its buttons work.

The buttons run hearth.adult_offer_answer, an administrator's only (only an administrator may grant an adult), which
looks again that the person still qualifies, and sets the role the way Hearth's page does (the entry's options).
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, ServiceResponse, SupportsResponse, callback
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .attention import ADMINS, NOTICE, Action, Item, async_note_admins
from .const import CONF_LOCKS, CONF_ROLES, DOMAIN
from .enforce import CONF_ENFORCE
from .sources import CONF_SOURCES

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

EVENT_ADULT_OFFERED = "hearth_adult_offered"
SERVICE = "adult_offer_answer"
MAKE_ADULT = "adult"
NOT_NOW = "not_now"
# The item's key (only letters, digits, dots and underscores: a phone button sends it between "|"s)
KEY_PREFIX = "hearth_adult_offer_"
# Hearth's page, relative (the companion app adds the address it reaches Home Assistant on)
PAGE = "/hearth"
# What the store keeps per person
ASKED = "asked"
DECLINED = "declined"
MADE = "made"
# Asked, but settled another way (set by hand on Hearth's page, or no longer qualifies): never asked again
SETTLED = "settled"
# The users looked at this run, kept outside the entry
_LOOKED_AT = f"{DOMAIN}_adult_offer_looked_at"


def offer_key(person: str) -> str:
    return KEY_PREFIX + "".join(c if c.isalnum() or c in "._" else "_" for c in person)


def _persons_of(hass: HomeAssistant, user_id: str) -> list[str]:
    return [s.entity_id for s in hass.states.async_all("person") if s.attributes.get("user_id") == user_id]


def kid_signals(hub: HearthHub, person: str) -> list[str]:
    """What makes [person] look like a kid to Hearth (empty: nothing)."""
    options = hub.entry.options
    found: list[str] = []
    if options.get(CONF_ROLES, {}).get(person) == "kid":
        found.append("role")
    if any(isinstance(e, dict) and e.get("person") == person for e in options.get(CONF_ENFORCE, []) or []):
        found.append("enforce")
    if any(isinstance(s, dict) and s.get("person") == person for s in options.get(CONF_SOURCES, []) or []):
        found.append("source")
    if any(isinstance(lock, dict) and lock.get("person") == person for lock in options.get(CONF_LOCKS, []) or []):
        found.append("lock")
    household = hub.household
    limits = household.limits
    budgets = limits.data.budgets.get(person) or {}
    if any(m is not None for kinds in budgets.values() if isinstance(kinds, dict) for m in kinds.values()):
        found.append("budget")
    if any((limits.data.bonus.get(person) or {}).values()) or limits.data.raises.get(person):
        found.append("bonus")
    if household.week.is_set(person):
        found.append("schedule")
    day = household.days.get(person)
    if day is not None and any(state.budget_min is not None for state in day.limits.values()):
        found.append("limit")
    return found


def qualifying_person(hass: HomeAssistant, hub: HearthHub, user) -> str | None:
    """The person to offer for [user], when everything holds; else None."""
    if user is None or user.is_admin or not user.is_active or user.system_generated:
        return None
    persons = _persons_of(hass, user.id)
    if len(persons) != 1:
        return None
    [person] = persons
    if person in hub.entry.options.get(CONF_ROLES, {}):
        return None
    return None if kid_signals(hub, person) else person


class AdultOffers:
    """The offers asked, declined and made, by person, kept across restarts."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"{DOMAIN}.adult_offers.{hub.entry.entry_id}")
        self.people: dict[str, dict[str, Any]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        people = stored.get("people")
        self.people = {p: r for p, r in people.items() if isinstance(r, dict)} if isinstance(people, dict) else {}

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"people": self.people}, 1)

    async def async_flush(self) -> None:
        await self._store.async_save({"people": self.people})

    def _mark(self, person: str, state: str, user_id: str | None = None) -> None:
        record = {**self.people.get(person, {}), "state": state, "at": dt_util.utcnow().isoformat()}
        if user_id:
            record["user"] = user_id
        self.people[person] = record
        self._save()

    def _open_for(self, person: str) -> bool:
        """Asked, unanswered, and the person still qualifies as far as the person shows: still their stored user's
        only person, no role, nothing of a kid's (the user itself is looked at again by async_still_open)."""
        record = self.people.get(person)
        if not record or record.get("state") != ASKED:
            return False
        user_id = record.get("user")
        if not isinstance(user_id, str) or _persons_of(self.hass, user_id) != [person]:
            return False
        return person not in self.hub.entry.options.get(CONF_ROLES, {}) and not kid_signals(self.hub, person)

    async def async_still_open(self, person: str) -> bool:
        """Asked, unanswered, and the person and their user still qualify."""
        if not self._open_for(person):
            return False
        user = await self.hass.auth.async_get_user(self.people[person]["user"])
        return qualifying_person(self.hass, self.hub, user) == person

    def open_offers(self) -> list[dict[str, str]]:
        """The offers waiting for an administrator, for Hearth's page."""
        household = self.hub.household
        return [
            {"person": person, "name": household.person_name(person)}
            for person in sorted(self.people)
            if self._open_for(person)
        ]

    def _item(self, person: str) -> Item:
        name = self.hub.household.person_name(person)
        data = {"person": person}
        return Item(
            offer_key(person),
            f"{name} signed in from a phone. Make them an adult in Hearth? Adults see the kids' time and can give more.",
            title=f"Make {name} an adult?",
            urgency=NOTICE,
            audience=ADMINS,
            actions=(
                Action("make_adult", "Make adult", f"{DOMAIN}.{SERVICE}", {**data, "answer": MAKE_ADULT}),
                Action("not_now", "Not now", f"{DOMAIN}.{SERVICE}", {**data, "answer": NOT_NOW}),
            ),
            about={"person": person},
            # A tap opens Hearth's page, where the offer waits as a card (Today)
            link=PAGE,
            once=True,
        )

    async def async_restore(self) -> None:
        """After a start or a reload: an open offer's item back (its buttons work again); one settled meanwhile (set
        by hand on Hearth's page) off the phones, once."""
        asked = [p for p, r in self.people.items() if r.get("state") == ASKED]
        if not asked:
            return
        await async_note_admins(self.hass)
        attention = self.hub.attention
        for person in asked:
            if await self.async_still_open(person):
                attention.adopt(self._item(person))
            else:
                attention.clear(offer_key(person), audience=ADMINS, phone=True)
                self._mark(person, SETTLED)

    @callback
    def refused(self, user) -> None:
        """A household read refused [user]: offer their person once, when they qualify. Cheap after the first look."""
        if user is None or user.is_admin:
            return
        looked = self.hass.data.setdefault(_LOOKED_AT, set())
        if user.id in looked:
            return
        looked.add(user.id)
        person = qualifying_person(self.hass, self.hub, user)
        if person is None or person in self.people:
            return
        self._mark(person, ASKED, user.id)
        self.hass.async_create_task(self._async_offer(person), "hearth adult offer")

    async def _async_offer(self, person: str) -> None:
        await async_note_admins(self.hass)
        _LOGGER.info("Hearth: asking the administrators whether %s is an adult (signed in from a phone)", person)
        self.hub.attention.notify(self._item(person))
        self.hass.bus.async_fire(EVENT_ADULT_OFFERED, {"person": person})

    async def async_answer(self, person: str, answer: str) -> None:
        """An administrator's Make adult or Not now. Make adult: only while the offer is open and the person still
        qualifies; the role is set as Hearth's page sets it (the entry's options, which reload)."""
        if answer == NOT_NOW:
            if self.people.get(person, {}).get("state") not in (ASKED, DECLINED):
                raise ServiceValidationError("Hearth didn't ask about that person")
            self._mark(person, DECLINED)
            self.hub.attention.clear(offer_key(person), audience=ADMINS, phone=True)
            return
        if not await self.async_still_open(person):
            raise ServiceValidationError("That person can't be made an adult from this offer any more")
        entry = self.hub.entry
        roles = {**entry.options.get(CONF_ROLES, {}), person: "adult"}
        self._mark(person, MADE)
        self.hub.attention.clear(offer_key(person), audience=ADMINS, phone=True)
        self.hass.config_entries.async_update_entry(entry, options={**entry.options, CONF_ROLES: roles})


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


@callback
def note_refused(hass: HomeAssistant, hub, user) -> None:
    """A Hearth household read refused [user] (the adult check): maybe ask the administrators about them."""
    offers = getattr(hub, "adult_offers", None) if hub is not None else None
    if offers is not None:
        offers.refused(user)


def async_register_service(hass: HomeAssistant) -> None:
    """hearth.adult_offer_answer {person, answer: adult | not_now}: an administrator's answer to the offer, from the
    notification on their phone (attention.py runs it as them) or Hearth's page. Administrators only: an automation,
    an adult who isn't an administrator, or anyone else is refused."""

    async def adult_offer_answer(call: ServiceCall) -> ServiceResponse:
        user = await hass.auth.async_get_user(call.context.user_id) if call.context.user_id else None
        if user is None or not user.is_admin:
            raise Unauthorized(context=call.context)
        hub = _hub(hass)
        if hub is None:
            raise ServiceValidationError("Hearth isn't set up")
        await hub.adult_offers.async_answer(call.data["person"], call.data["answer"])
        return {"person": call.data["person"], "answer": call.data["answer"]}

    hass.services.async_register(
        DOMAIN,
        SERVICE,
        adult_offer_answer,
        schema=vol.Schema(
            {
                vol.Required("person"): cv.entity_domain("person"),
                vol.Required("answer"): vol.In((MAKE_ADULT, NOT_NOW)),
            }
        ),
        supports_response=SupportsResponse.OPTIONAL,
    )
