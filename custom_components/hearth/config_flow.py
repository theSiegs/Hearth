"""Setting up the household, pairing each device (Hearth on a TV, Hearth Mobile on a phone or tablet), and the
household's options (who's who, groups).

The household is set up once (Settings > Devices & services > Add > Hearth). A device then asks to pair from its own
settings: it shows a code, and Home Assistant shows the same code as a discovered Hearth device. An administrator who
sees the codes match confirms (and, for a phone, says whose it is), and the device gets its own secret. No token or
webhook ID is typed anywhere.
"""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.const import CONF_NAME
from homeassistant.core import callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.selector import (
    BooleanSelector,
    DateSelector,
    NumberSelector,
    NumberSelectorConfig,
    NumberSelectorMode,
    TimeSelector,
    EntitySelector,
    EntitySelectorConfig,
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)

from .const import (
    CONF_GROUP_APPS,
    CONF_GROUPS,
    CONF_LOCKS,
    CONF_OUTSIDE_ALL,
    CONF_ROLES,
    CONF_TILE_EXCHANGE,
    CONF_PERSON,
    CONF_PROFILES,
    CONF_PUSH_SERVER,
    DOMAIN,
    KIND_MOBILE,
)
from .counting import ALL
from .limits import BUILTIN_GROUPS, GAMES, VIDEO, slug
from .apps import CONF_APP_WATCH, CONF_ASK_NOTIFY, OTHER, options_with_app_in_group, update_notification
from .enforce import (
    CONF_ENFORCE,
    DEFAULT_SCHOOL_TIME_APPS,
    school_pausable,
    DEFAULT_FS_GROUPS,
    DEFAULT_NINTENDO_GROUPS,
    FAMILY_LINK,
    FAMILY_SAFETY,
    NINTENDO,
    NINTENDO_DOMAIN,
    PLATFORMS,
)
from .notifications import clear_pairing
from .schooldays import CALENDAR_OFF, CALENDAR_SCHOOL, CONF_SCHOOL_DAYS, SCHOOL_BUDGET
from .schedule import CONF_SCHEDULE, CONF_SITE_LIST
from .chores import CONF_CHORES, DEFAULT_MINUTES
from .asks import AMOUNTS, CONF_OFFER_MORE
from .sources import CONF_SOURCES, CONF_TITLES
from . import parent_pin
from . import phones as adult_phones
from .push import clean_server
from .profiles import is_local_key, is_ref, is_tv_key
from .places import CONF_PLACES, FAVORITES, MAX_FAVORITES, MAX_NAME, SCHOOLS, TRACKERS, favorite_key

PERSON_SELECTOR = EntitySelector(EntitySelectorConfig(domain="person"))


def _loaded_hub(hass):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


class HearthConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    _pairing_id: str

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        return HearthOptionsFlow()

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        # One household (not the manifest's single_config_entry: that would also stop the devices' pairing flows)
        if self._async_current_entries(include_ignore=False):
            return self.async_abort(reason="single_instance_allowed")
        if user_input is not None:
            return self.async_create_entry(title=user_input[CONF_NAME], data={CONF_NAME: user_input[CONF_NAME]})
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({vol.Required(CONF_NAME, default="Home"): str}),
        )

    async def async_step_integration_discovery(self, discovery_info: dict[str, Any]) -> ConfigFlowResult:
        """A device asked to pair (see api.PairStartView)."""
        self._pairing_id = discovery_info["pairing_id"]
        pairing = self._hub_pairing()
        if pairing is None:
            return self.async_abort(reason="expired")
        self.context["title_placeholders"] = {"name": pairing.name}
        return await self.async_step_confirm()

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        pairing = self._hub_pairing()
        if pairing is None:
            return self.async_abort(reason="expired")
        if user_input is not None:
            hub = _loaded_hub(self.hass)
            if hub is None or not await hub.async_approve(self._pairing_id, user_input.get(CONF_PERSON)):
                return self.async_abort(reason="expired")
            clear_pairing(self.hass, self._pairing_id)
            return self.async_abort(reason="paired", description_placeholders={"name": pairing.name})
        # A phone is one person's: say whose (a TV's profiles are mapped in the options)
        schema = (
            vol.Schema({vol.Optional(CONF_PERSON): PERSON_SELECTOR}) if pairing.kind == KIND_MOBILE else vol.Schema({})
        )
        return self.async_show_form(
            step_id="confirm",
            data_schema=schema,
            description_placeholders={"name": pairing.name, "code": pairing.code},
        )

    def _hub_pairing(self):
        hub = _loaded_hub(self.hass)
        return hub.pairing(self._pairing_id) if hub else None


class HearthOptionsFlow(OptionsFlow):
    """The household's options: who each TV profile is, and the groups budgets are set on."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return self.async_show_menu(
            step_id="init",
            menu_options=[
                "people",
                "add_source",
                "remove_source",
                "add_title",
                "remove_title",
                "locks",
                "enforce",
                "school_days",
                "schedule",
                "places",
                "site_list",
                "chores",
                "offer_more",
                "sort_apps",
                "new_apps",
                "add_group",
                "group_apps",
                "not_screen_time",
                "remove_group",
                "tile_exchange",
                "parent_pin",
                "push",
            ],
        )

    def _options(self) -> dict[str, Any]:
        return {**self.config_entry.options}

    def _household(self):
        return self.config_entry.runtime_data.household

    def _app_selector(self, chosen: list[str]) -> SelectSelector:
        known = self._household().known_apps()
        for package in chosen:
            known.setdefault(package, package)
        choices = [
            SelectOptionDict(value=package, label=name if name == package else f"{name} ({package})")
            for package, name in sorted(known.items(), key=lambda kv: kv[1].lower())
        ]
        return SelectSelector(SelectSelectorConfig(options=choices, multiple=True, custom_value=True))

    async def async_step_people(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Each TV profile the TVs have reported, with its person (or nobody: a guest or shared profile)."""
        options = self._options()
        mapped: dict[str, str] = dict(options.get(CONF_PROFILES, {}))
        # By household ref (one choice for every TV) or one TV's key; an old bare key isn't offered: saving drops it
        seen = {key: label for key, label in self._household().seen_profiles().items() if not is_local_key(key)}
        labels = {f"{label} ({key})": key for key, label in sorted(seen.items(), key=lambda kv: kv[1].lower())}
        errors: dict[str, str] = {}
        if user_input is not None:
            profiles = {labels[label]: person for label, person in user_input.items() if label in labels and person}
            # A profile no TV has reported yet: its ref ("name:sam") or one TV's key ("<device id>/user:11")
            extra_id = (user_input.get("profile_id") or "").strip()
            if extra_id:
                if not (is_ref(extra_id) or is_tv_key(extra_id)) or not user_input.get("profile_person"):
                    errors["profile_id"] = "bad_profile_id"
                else:
                    profiles[extra_id] = user_input["profile_person"]
            if not errors:
                return self.async_create_entry(data={**options, CONF_PROFILES: profiles})
        fields: dict[Any, Any] = {
            vol.Optional(label, description={"suggested_value": mapped.get(profile_id)}): PERSON_SELECTOR
            for label, profile_id in labels.items()
        }
        fields[vol.Optional("profile_id")] = TextSelector()
        fields[vol.Optional("profile_person")] = PERSON_SELECTOR
        return self.async_show_form(step_id="people", data_schema=vol.Schema(fields), errors=errors)

    async def async_step_add_group(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """A group of one's own (YouTube: YouTube and HearthTube on every device)."""
        options = self._options()
        groups: list[dict[str, Any]] = list(options.get(CONF_GROUPS, []))
        errors: dict[str, str] = {}
        if user_input is not None:
            name = user_input[CONF_NAME].strip()
            group_id = slug(name)
            taken = {g.id for g in BUILTIN_GROUPS} | {g["id"] for g in groups}
            if not name or group_id in taken:
                errors[CONF_NAME] = "name_taken"
            else:
                groups.append({"id": group_id, "name": name, "apps": list(user_input.get("apps", []))})
                return self.async_create_entry(data={**options, CONF_GROUPS: groups})
        schema = vol.Schema(
            {vol.Required(CONF_NAME): TextSelector(), vol.Optional("apps", default=[]): self._app_selector([])}
        )
        return self.async_show_form(step_id="add_group", data_schema=schema, errors=errors)

    async def async_step_group_apps(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Apps an adult adds to Video or Games (Android's categories miss some)."""
        options = self._options()
        added: dict[str, list[str]] = {k: list(v) for k, v in options.get(CONF_GROUP_APPS, {}).items()}
        if user_input is not None:
            added[VIDEO] = list(user_input.get(VIDEO, []))
            added[GAMES] = list(user_input.get(GAMES, []))
            return self.async_create_entry(data={**options, CONF_GROUP_APPS: added})
        schema = vol.Schema(
            {
                vol.Optional(VIDEO, default=added.get(VIDEO, [])): self._app_selector(added.get(VIDEO, [])),
                vol.Optional(GAMES, default=added.get(GAMES, [])): self._app_selector(added.get(GAMES, [])),
            }
        )
        return self.async_show_form(step_id="group_apps", data_schema=schema)

    async def async_step_not_screen_time(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Groups whose time isn't screen time (music, say): not counted in All screen time, not held when it runs
        out. Their own budget still applies."""
        options = self._options()
        if user_input is not None:
            return self.async_create_entry(data={**options, CONF_OUTSIDE_ALL: list(user_input.get("groups", []))})
        groups = [g for g in self._household().groups if g.id != ALL]
        schema = vol.Schema(
            {
                vol.Optional("groups", default=list(options.get(CONF_OUTSIDE_ALL, []))): SelectSelector(
                    SelectSelectorConfig(
                        options=[SelectOptionDict(value=g.id, label=g.name) for g in groups], multiple=True
                    )
                )
            }
        )
        return self.async_show_form(step_id="not_screen_time", data_schema=schema)

    async def async_step_tile_exchange(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """The people whose phone may share with the launcher's tile exchange (scrubbed notification layouts, never
        content). Off for everyone until chosen here."""
        options = self._options()
        if user_input is not None:
            return self.async_create_entry(data={**options, CONF_TILE_EXCHANGE: list(user_input.get("people", []))})
        schema = vol.Schema(
            {
                vol.Optional("people", default=list(options.get(CONF_TILE_EXCHANGE, []))): EntitySelector(
                    EntitySelectorConfig(domain="person", multiple=True)
                )
            }
        )
        return self.async_show_form(step_id="tile_exchange", data_schema=schema)

    async def async_step_push(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """The ntfy server the phones are pinged through when their state changes (push.py); empty: no pings."""
        options = self._options()
        errors: dict[str, str] = {}
        if user_input is not None:
            try:
                server = clean_server(user_input.get("server"))
            except vol.Invalid:
                errors["server"] = "bad_server"
            else:
                return self.async_create_entry(data={**options, CONF_PUSH_SERVER: server})
        schema = vol.Schema(
            {
                vol.Optional("server", description={"suggested_value": options.get(CONF_PUSH_SERVER)}): TextSelector(
                    TextSelectorConfig(type=TextSelectorType.URL)
                )
            }
        )
        return self.async_show_form(step_id="push", data_schema=schema, errors=errors)

    async def async_step_parent_pin(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """An adult's parent PIN, which paired TVs and phones check (kept as a hash; see parent_pin.py). Typed twice;
        "Remove" clears that adult's."""
        options = self._options()
        pins = parent_pin.stored_pins(options)
        errors: dict[str, str] = {}
        if user_input is not None:
            person = user_input[CONF_PERSON]
            if user_input.get("remove"):
                pins.pop(person, None)
                return self.async_create_entry(data={**options, parent_pin.CONF_PARENT_PINS: pins})
            pin = (user_input.get("pin") or "").strip()
            if options.get(CONF_ROLES, {}).get(person) != "adult":
                errors[CONF_PERSON] = "not_adult"
            elif not parent_pin.PIN.match(pin):
                errors["pin"] = "bad_pin"
            elif pin != (user_input.get("pin_again") or "").strip():
                errors["pin_again"] = "pins_differ"
            else:
                pins[person] = await self.hass.async_add_executor_job(parent_pin.make, pin)
                return self.async_create_entry(data={**options, parent_pin.CONF_PARENT_PINS: pins})
        password = TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD))
        schema = vol.Schema(
            {
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("pin"): password,
                vol.Optional("pin_again"): password,
                vol.Optional("remove", default=False): BooleanSelector(),
            }
        )
        return self.async_show_form(
            step_id="parent_pin",
            data_schema=schema,
            errors=errors,
            description_placeholders={
                "people": ", ".join(self._household().person_name(p) for p in sorted(pins)) or "nobody yet"
            },
        )

    async def async_step_remove_group(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        options = self._options()
        groups: list[dict[str, Any]] = list(options.get(CONF_GROUPS, []))
        if not groups:
            return self.async_abort(reason="no_groups")
        if user_input is not None:
            gone = set(user_input.get("groups", []))
            return self.async_create_entry(data={**options, CONF_GROUPS: [g for g in groups if g["id"] not in gone]})
        schema = vol.Schema(
            {
                vol.Required("groups"): SelectSelector(
                    SelectSelectorConfig(
                        options=[SelectOptionDict(value=g["id"], label=g["name"]) for g in groups], multiple=True
                    )
                )
            }
        )
        return self.async_show_form(step_id="remove_group", data_schema=schema)


    def _remove_from(self, key: str, step_id: str, user_input: dict[str, Any] | None) -> ConfigFlowResult:
        options = self._options()
        items: list[dict[str, Any]] = list(options.get(key, []))
        if not items:
            return self.async_abort(reason="nothing_to_remove")
        if user_input is not None:
            gone = set(user_input.get("items", []))
            return self.async_create_entry(data={**options, key: [i for i in items if i["id"] not in gone]})
        schema = vol.Schema(
            {
                vol.Required("items"): SelectSelector(
                    SelectSelectorConfig(
                        options=[SelectOptionDict(value=i["id"], label=i["name"]) for i in items], multiple=True
                    )
                )
            }
        )
        return self.async_show_form(step_id=step_id, data_schema=schema)

    async def async_step_add_source(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Another integration's screen time (a sensor of time today) or now playing (a sensor of what's played)."""
        options = self._options()
        sources: list[dict[str, Any]] = list(options.get(CONF_SOURCES, []))
        errors: dict[str, str] = {}
        if user_input is not None:
            entity_id = user_input["entity_id"]
            if any(s["entity_id"] == entity_id for s in sources):
                errors["entity_id"] = "already_added"
            else:
                state = self.hass.states.get(entity_id)
                name = user_input.get(CONF_NAME) or (state.name if state else entity_id)
                base = slug(name)
                source_id, n = base, 2
                while any(s["id"] == source_id for s in sources):
                    source_id, n = f"{base}_{n}", n + 1
                sources.append(
                    {
                        "id": source_id,
                        "entity_id": entity_id,
                        "person": user_input[CONF_PERSON],
                        "name": name,
                        "live": user_input.get("live", False),
                        "same_as": user_input.get("same_as") or None,
                        "group": user_input.get("group") or self._source_group(entity_id),
                    }
                )
                return self.async_create_entry(data={**options, CONF_SOURCES: sources})
        hub = self.config_entry.runtime_data
        same_as = [
            SelectOptionDict(value=f"hearth:{device_id}", label=device.get("name") or device_id)
            for device_id, device in hub.devices.items()
        ] + [SelectOptionDict(value=s["id"], label=s["name"]) for s in sources]
        groups = [SelectOptionDict(value=g.id, label=g.name) for g in hub.household.groups if g.id != "all"]
        schema = vol.Schema(
            {
                vol.Required("entity_id"): EntitySelector(EntitySelectorConfig(domain="sensor")),
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional(CONF_NAME): TextSelector(),
                vol.Optional("live", default=False): bool,
                vol.Optional("same_as"): SelectSelector(SelectSelectorConfig(options=same_as)),
                vol.Optional("group"): SelectSelector(SelectSelectorConfig(options=groups)),
            }
        )
        return self.async_show_form(step_id="add_source", data_schema=schema, errors=errors)

    def _source_group(self, entity_id: str) -> str | None:
        """The group a source's time is in when none was chosen: a Switch's (Nintendo's sensors) is games."""
        entry = er.async_get(self.hass).async_get(entity_id)
        return GAMES if entry is not None and entry.platform == NINTENDO_DOMAIN else None

    async def async_step_remove_source(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return self._remove_from(CONF_SOURCES, "remove_source", user_input)

    async def async_step_add_title(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """One game (or app) by every name it has: the Android package, the Xbox and Switch names, the PC app."""
        options = self._options()
        titles: list[dict[str, Any]] = list(options.get(CONF_TITLES, []))
        errors: dict[str, str] = {}
        if user_input is not None:
            name = user_input[CONF_NAME].strip()
            title_id = slug(name)
            if not name or any(t["id"] == title_id for t in titles):
                errors[CONF_NAME] = "name_taken"
            else:
                matches = [m for m in user_input.get("matches", []) if not m.startswith("title:")]
                titles.append({"id": title_id, "name": name, "matches": matches})
                return self.async_create_entry(data={**options, CONF_TITLES: titles})
        schema = vol.Schema(
            {vol.Required(CONF_NAME): TextSelector(), vol.Optional("matches", default=[]): self._app_selector([])}
        )
        return self.async_show_form(step_id="add_title", data_schema=schema, errors=errors)

    async def async_step_remove_title(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return self._remove_from(CONF_TITLES, "remove_title", user_input)

    async def async_step_locks(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """A person's locks: entities that are on while they may not watch (Family Link's bedtime or school time
        sensors). Choosing a person's again replaces theirs; none clears them."""
        options = self._options()
        locks: list[dict[str, Any]] = list(options.get(CONF_LOCKS, []))
        if user_input is not None:
            person = user_input[CONF_PERSON]
            kept = [lock for lock in locks if lock.get("person") != person]
            kept += [{"entity_id": entity_id, "person": person} for entity_id in user_input.get("entities", [])]
            return self.async_create_entry(data={**options, CONF_LOCKS: kept})
        schema = vol.Schema(
            {
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("entities", default=[]): EntitySelector(
                    EntitySelectorConfig(domain=["binary_sensor", "input_boolean", "switch"], multiple=True)
                ),
            }
        )
        return self.async_show_form(step_id="locks", data_schema=schema)

    async def async_step_enforce(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """The other parental controls that hold a person's apps when a group is out of time (see enforce.py).
        Choosing a person again replaces theirs; leaving them all empty stops it, and what was held is let go."""
        options = self._options()
        enforce: list[dict[str, Any]] = list(options.get(CONF_ENFORCE, []))
        if user_input is not None:
            person = user_input[CONF_PERSON]
            kept = [e for e in enforce if e.get("person") != person]
            if user_input.get("family_link"):
                kept.append(
                    {
                        "kind": FAMILY_LINK,
                        "person": person,
                        "entity_id": user_input["family_link"],
                        # Paused while their School time is on (none: nothing)
                        "school_time_apps": [
                            p.strip() for p in user_input.get("school_time_apps") or [] if school_pausable(p.strip())
                        ],
                    }
                )
            if user_input.get("family_safety"):
                kept.append(
                    {
                        "kind": FAMILY_SAFETY,
                        "person": person,
                        "entity_id": user_input["family_safety"],
                        "platforms": list(user_input.get("platforms") or ["Xbox"]),
                        "groups": list(user_input.get("groups") or DEFAULT_FS_GROUPS),
                    }
                )
            if user_input.get("nintendo"):
                kept.append(
                    {
                        "kind": NINTENDO,
                        "person": person,
                        "entity_id": user_input["nintendo"],
                        "groups": list(user_input.get("nintendo_groups") or DEFAULT_NINTENDO_GROUPS),
                        **({"playing": list(user_input["nintendo_playing"])} if user_input.get("nintendo_playing") else {}),
                    }
                )
            return self.async_create_entry(data={**options, CONF_ENFORCE: kept})
        groups = [SelectOptionDict(value=g.id, label=g.name) for g in self._household().groups]
        schema = vol.Schema(
            {
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("family_link"): EntitySelector(EntitySelectorConfig(integration="familylink")),
                vol.Optional("school_time_apps", default=list(DEFAULT_SCHOOL_TIME_APPS)): self._app_selector(
                    list(DEFAULT_SCHOOL_TIME_APPS)
                ),
                vol.Optional("family_safety"): EntitySelector(
                    EntitySelectorConfig(integration="microsoft_family_safety", domain="sensor")
                ),
                vol.Optional("platforms", default=["Xbox"]): SelectSelector(
                    SelectSelectorConfig(options=list(PLATFORMS), multiple=True)
                ),
                vol.Optional("groups", default=list(DEFAULT_FS_GROUPS)): SelectSelector(
                    SelectSelectorConfig(options=groups, multiple=True)
                ),
                vol.Optional("nintendo"): EntitySelector(
                    EntitySelectorConfig(integration=NINTENDO_DOMAIN, domain="number")
                ),
                vol.Optional("nintendo_groups", default=list(DEFAULT_NINTENDO_GROUPS)): SelectSelector(
                    SelectSelectorConfig(options=groups, multiple=True)
                ),
                # A shared Switch: held only while one of these is on (this person is the one playing)
                vol.Optional("nintendo_playing"): EntitySelector(
                    EntitySelectorConfig(domain="binary_sensor", multiple=True)
                ),
            }
        )
        return self.async_show_form(step_id="enforce", data_schema=schema)

    async def async_step_new_apps(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Where new apps are noticed (sensors listing a kid's allowed apps, such as Family Link's), and which phone
        is asked to sort them."""
        options = self._options()
        if user_input is not None:
            return self.async_create_entry(
                data={
                    **options,
                    CONF_APP_WATCH: list(user_input.get("entities", [])),
                    CONF_ASK_NOTIFY: user_input.get("notify") or None,
                    adult_phones.CONF_ASK_NOTIFY_OFF: list(user_input.get("ask_off", [])),
                    adult_phones.CONF_ASK_DEEP_LINK: list(user_input.get("ask_deep_link", [])),
                }
            )
        phones = sorted(
            f"notify.{name}" for name in self.hass.services.async_services().get("notify", {}) if name.startswith("mobile_app_")
        )
        adults = [
            SelectOptionDict(value=p, label=(self.hass.states.get(p).name if self.hass.states.get(p) else p))
            for p in adult_phones.adults(options)
        ]
        schema = vol.Schema(
            {
                vol.Optional("entities", default=list(options.get(CONF_APP_WATCH, []))): EntitySelector(
                    EntitySelectorConfig(domain="sensor", multiple=True)
                ),
                vol.Optional("notify", description={"suggested_value": options.get(CONF_ASK_NOTIFY)}): SelectSelector(
                    SelectSelectorConfig(options=[SelectOptionDict(value=p, label=p) for p in phones])
                ),
                # Every adult's own phones get requests too, unless switched off here
                vol.Optional("ask_off", default=list(options.get(adult_phones.CONF_ASK_NOTIFY_OFF, []))): SelectSelector(
                    SelectSelectorConfig(options=adults, multiple=True)
                ),
                vol.Optional(
                    "ask_deep_link", default=list(options.get(adult_phones.CONF_ASK_DEEP_LINK, []))
                ): SelectSelector(SelectSelectorConfig(options=adults, multiple=True)),
            }
        )
        return self.async_show_form(step_id="new_apps", data_schema=schema)

    async def async_step_sort_apps(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Each new app, and the group it counts in (Other: All screen time only)."""
        household = self._household()
        waiting = household.apps.new_apps()[:25]
        if not waiting:
            return self.async_abort(reason="no_new_apps")
        labels = {f"{e.name} ({e.package})": e for e in waiting}
        choices = [SelectOptionDict(value=g.id, label=g.name) for g in household.groups if g.id != "all"]
        choices.append(SelectOptionDict(value=OTHER, label="Other (All screen time only)"))
        if user_input is not None:
            options = self._options()
            for label, entry in labels.items():
                group = user_input.get(label)
                if not group:
                    continue
                household.apps.sort(entry.package, group)
                if group != OTHER:
                    options = options_with_app_in_group(options, entry.package, group)
            update_notification(self.hass, household.apps.new_apps(), household.groups)
            return self.async_create_entry(data=options)
        schema = vol.Schema(
            {
                vol.Optional(label, description={"suggested_value": entry.suggested}): SelectSelector(
                    SelectSelectorConfig(options=choices)
                )
                for label, entry in labels.items()
            }
        )
        return self.async_show_form(step_id="sort_apps", data_schema=schema)

    async def async_step_school_days(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """How the household knows a school day (any mix; see schooldays.py for the order they're asked in)."""
        options = self._options()
        current: dict[str, Any] = dict(options.get(CONF_SCHOOL_DAYS) or {})
        if user_input is not None:
            kept = {k: v for k, v in user_input.items() if v not in (None, "", [])}
            return self.async_create_entry(data={**options, CONF_SCHOOL_DAYS: kept})

        def suggested(key: str) -> dict[str, Any]:
            return {"suggested_value": current.get(key)}

        schema = vol.Schema(
            {
                vol.Optional("entity", description=suggested("entity")): EntitySelector(EntitySelectorConfig()),
                vol.Optional("school_states", description=suggested("school_states")): TextSelector(),
                vol.Optional("calendar", description=suggested("calendar")): EntitySelector(
                    EntitySelectorConfig(domain="calendar")
                ),
                vol.Optional(
                    "calendar_mode", description={"suggested_value": current.get("calendar_mode", CALENDAR_OFF)}
                ): SelectSelector(
                    SelectSelectorConfig(
                        options=[
                            SelectOptionDict(value=CALENDAR_OFF, label="Its events are days off"),
                            SelectOptionDict(value=CALENDAR_SCHOOL, label="Its events are the school days"),
                        ]
                    )
                ),
                vol.Optional("keywords", description=suggested("keywords")): TextSelector(),
                vol.Optional("year_start", description=suggested("year_start")): DateSelector(),
                vol.Optional("year_end", description=suggested("year_end")): DateSelector(),
                vol.Optional("days_off", description=suggested("days_off")): TextSelector(
                    TextSelectorConfig(multiline=True)
                ),
                vol.Optional("extra_school_days", description=suggested("extra_school_days")): TextSelector(
                    TextSelectorConfig(multiline=True)
                ),
                vol.Optional("half_days", description=suggested("half_days")): TextSelector(
                    TextSelectorConfig(multiline=True)
                ),
                vol.Optional("half_states", description=suggested("half_states")): TextSelector(),
                vol.Optional("half_keywords", description=suggested("half_keywords")): TextSelector(),
                vol.Optional(
                    "half_day_budget", description={"suggested_value": current.get("half_day_budget", "other_days")}
                ): SelectSelector(
                    SelectSelectorConfig(
                        options=[
                            SelectOptionDict(value="other_days", label="The other-day budget"),
                            SelectOptionDict(value=SCHOOL_BUDGET, label="The school-day budget"),
                        ]
                    )
                ),
            }
        )
        return self.async_show_form(step_id="school_days", data_schema=schema)

    def _notify_selector(self) -> SelectSelector:
        phones = sorted(
            f"notify.{name}" for name in self.hass.services.async_services().get("notify", {}) if name.startswith("mobile_app_")
        )
        return SelectSelector(SelectSelectorConfig(options=[SelectOptionDict(value=p, label=p) for p in phones], custom_value=True))

    def _group_selector(self, multiple: bool = False, with_all: bool = True) -> SelectSelector:
        groups = [
            SelectOptionDict(value=g.id, label=g.name) for g in self._household().groups if with_all or g.id != ALL
        ]
        return SelectSelector(SelectSelectorConfig(options=groups, multiple=multiple))

    async def async_step_schedule(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """What each day type does to the kids' Family Link (schedule.py): School time off on days off, School time
        ending early on half days, extra time on both (Family Link, and when chosen Family Safety and the Switch)."""
        options = self._options()
        current: dict[str, Any] = dict(options.get(CONF_SCHEDULE) or {})
        if user_input is not None:
            kept = {k: v for k, v in user_input.items() if v not in (None, "", [])}
            return self.async_create_entry(data={**options, CONF_SCHEDULE: kept})

        def suggested(key: str, default: Any = None) -> dict[str, Any]:
            return {"suggested_value": current.get(key, default)}

        minutes = NumberSelector(
            NumberSelectorConfig(min=0, max=720, step=5, unit_of_measurement="min", mode=NumberSelectorMode.BOX)
        )
        schema = vol.Schema(
            {
                vol.Optional("day_off_school_time_off", default=bool(current.get("day_off_school_time_off"))): BooleanSelector(),
                vol.Optional("day_off_bonus", description=suggested("day_off_bonus", 0)): minutes,
                vol.Optional("half_day_hours_early", description=suggested("half_day_hours_early", 0)): NumberSelector(
                    NumberSelectorConfig(min=0, max=12, step=0.5, unit_of_measurement="h", mode=NumberSelectorMode.BOX)
                ),
                vol.Optional("half_day_bonus", description=suggested("half_day_bonus", 0)): minutes,
                vol.Optional("bonus_family_link", default=current.get("bonus_family_link", True)): BooleanSelector(),
                vol.Optional(
                    "bonus_family_safety", default=current.get("bonus_family_safety", False)
                ): BooleanSelector(),
                vol.Optional("bonus_nintendo", default=current.get("bonus_nintendo", False)): BooleanSelector(),
                vol.Optional("bonus_group", description=suggested("bonus_group")): self._group_selector(),
                vol.Optional("people", description=suggested("people")): EntitySelector(
                    EntitySelectorConfig(domain="person", multiple=True)
                ),
                vol.Optional("notify", description=suggested("notify")): self._notify_selector(),
                vol.Optional("watchdog", description=suggested("watchdog", "10:00:00")): TimeSelector(),
            }
        )
        return self.async_show_form(step_id="schedule", data_schema=schema)

    async def async_step_site_list(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """A website block list synced into each kid's Family Link every day (familylink.sync_site_list)."""
        options = self._options()
        current: dict[str, Any] = dict(options.get(CONF_SITE_LIST) or {})
        errors: dict[str, str] = {}
        if user_input is not None:
            url = (user_input.get("url") or "").strip()
            if url and not url.startswith("https://"):
                errors["url"] = "not_https"
            else:
                kept = {k: v for k, v in {**user_input, "url": url}.items() if v not in (None, "", [])}
                return self.async_create_entry(data={**options, CONF_SITE_LIST: kept})
        schema = vol.Schema(
            {
                vol.Optional("url", description={"suggested_value": current.get("url")}): TextSelector(
                    TextSelectorConfig(type=TextSelectorType.URL)
                ),
                vol.Optional("time", description={"suggested_value": current.get("time", "07:30:00")}): TimeSelector(),
                vol.Optional("people", description={"suggested_value": current.get("people")}): EntitySelector(
                    EntitySelectorConfig(domain="person", multiple=True)
                ),
            }
        )
        return self.async_show_form(step_id="site_list", data_schema=schema, errors=errors)

    async def async_step_chores(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """A person's chores list: each item checked off adds minutes to a group today. Choosing a person again
        replaces theirs; no list stops it."""
        options = self._options()
        chores: list[dict[str, Any]] = list(options.get(CONF_CHORES, []))
        if user_input is not None:
            person = user_input[CONF_PERSON]
            kept = [c for c in chores if c.get("person") != person]
            if user_input.get("todo") and user_input.get("group"):
                kept.append(
                    {
                        "person": person,
                        "todo": user_input["todo"],
                        "group": user_input["group"],
                        "minutes": int(user_input.get("minutes") or DEFAULT_MINUTES),
                    }
                )
            return self.async_create_entry(data={**options, CONF_CHORES: kept})
        schema = vol.Schema(
            {
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("todo"): EntitySelector(EntitySelectorConfig(domain="todo")),
                vol.Optional("group"): self._group_selector(),
                vol.Optional("minutes", default=DEFAULT_MINUTES): NumberSelector(
                    NumberSelectorConfig(min=1, max=240, step=1, unit_of_measurement="min", mode=NumberSelectorMode.BOX)
                ),
            }
        )
        return self.async_show_form(step_id="chores", data_schema=schema)

    async def async_step_places(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Places are zones (places.py): a kid's school zone and Family Link tracker (choosing a kid again replaces
        theirs), and favorite places added or removed."""
        options = self._options()
        places: dict[str, Any] = dict(options.get(CONF_PLACES) or {})
        schools: dict[str, str] = dict(places.get(SCHOOLS) or {})
        trackers: dict[str, str] = dict(places.get(TRACKERS) or {})
        favorites: list[dict[str, str]] = [dict(f) for f in places.get(FAVORITES) or []]
        errors: dict[str, str] = {}
        if user_input is not None:
            if person := user_input.get(CONF_PERSON):
                schools.pop(person, None)
                trackers.pop(person, None)
                if user_input.get("school"):
                    schools[person] = user_input["school"]
                if user_input.get("tracker"):
                    trackers[person] = user_input["tracker"]
            gone = set(user_input.get("remove_favorites") or [])
            favorites = [f for f in favorites if f.get("key") not in gone]
            name = (user_input.get("favorite_name") or "").strip()[:MAX_NAME]
            if name and not user_input.get("favorite_zone"):
                errors["favorite_zone"] = "no_favorite_zone"
            elif zone := user_input.get("favorite_zone"):
                if len(favorites) >= MAX_FAVORITES:
                    errors["favorite_zone"] = "too_many_favorites"
                else:
                    state = self.hass.states.get(zone)
                    name = name or (state.name if state else zone.split(".", 1)[1].replace("_", " ").title())
                    key = favorite_key(name, {f["key"] for f in favorites})
                    favorites.append({"key": key, "zone": zone, "name": name})
            if not errors:
                return self.async_create_entry(
                    data={**options, CONF_PLACES: {SCHOOLS: schools, TRACKERS: trackers, FAVORITES: favorites}}
                )
        zone = EntitySelector(EntitySelectorConfig(domain="zone"))
        schema = vol.Schema(
            {
                vol.Optional(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("school"): zone,
                # Family Link's only: a router's or Wi-Fi tracker is never used
                vol.Optional("tracker"): EntitySelector(
                    EntitySelectorConfig(integration="familylink", domain="device_tracker")
                ),
                vol.Optional("favorite_zone"): zone,
                vol.Optional("favorite_name"): TextSelector(),
                vol.Optional("remove_favorites", default=[]): SelectSelector(
                    SelectSelectorConfig(
                        options=[
                            SelectOptionDict(value=f["key"], label=f"{f['name']} ({f['key']})") for f in favorites
                        ],
                        multiple=True,
                    )
                ),
            }
        )
        listed = ", ".join(f"{f['name']} ({f['key']})" for f in favorites) or "none"
        return self.async_show_form(
            step_id="places", data_schema=schema, errors=errors, description_placeholders={"favorites": listed}
        )

    async def async_step_offer_more(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """When one of these groups of a person's runs out, the adults are offered to give more. Choosing a person
        again replaces theirs; no groups stops it."""
        options = self._options()
        offers: list[dict[str, Any]] = list(options.get(CONF_OFFER_MORE, []))
        if user_input is not None:
            person = user_input[CONF_PERSON]
            kept = [o for o in offers if o.get("person") != person]
            minutes = int(user_input.get("minutes") or 30)
            kept += [{"person": person, "group": g, "minutes": minutes} for g in user_input.get("groups") or []]
            return self.async_create_entry(data={**options, CONF_OFFER_MORE: kept})
        schema = vol.Schema(
            {
                vol.Required(CONF_PERSON): PERSON_SELECTOR,
                vol.Optional("groups", default=[]): self._group_selector(multiple=True),
                vol.Optional("minutes", default="30"): SelectSelector(
                    SelectSelectorConfig(options=[str(m) for m in AMOUNTS])
                ),
            }
        )
        return self.async_show_form(step_id="offer_more", data_schema=schema)
