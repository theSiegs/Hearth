"""Setting up the household, pairing each device (Hearth on a TV, Hearth Mobile on a phone or tablet), and the
household's options (who's who, groups).

The household is set up once (Settings > Devices & services > Add > Hearth). A device then asks to pair from its own
settings: it shows a code, and Home Assistant shows the same code as a discovered Hearth device. An administrator who
sees the codes match confirms (and, for a phone, says whose it is), and the device gets its own secret. No token or
webhook ID is typed anywhere.
"""

from __future__ import annotations

import re
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.const import CONF_NAME
from homeassistant.components import persistent_notification
from homeassistant.core import callback
from homeassistant.helpers.selector import (
    EntitySelector,
    EntitySelectorConfig,
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    TextSelector,
)

from .const import CONF_GROUP_APPS, CONF_GROUPS, CONF_LOCKS, CONF_PERSON, CONF_PROFILES, DOMAIN, KIND_MOBILE
from .limits import BUILTIN_GROUPS, GAMES, VIDEO, slug
from .notifications import pairing_notification_id
from .sources import CONF_SOURCES, CONF_TITLES

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
            persistent_notification.async_dismiss(self.hass, pairing_notification_id(self._pairing_id))
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
                "add_group",
                "group_apps",
                "remove_group",
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
        seen = self._household().seen_profiles()
        for profile_id in mapped:
            seen.setdefault(profile_id, None)
        labels = {f"{name or 'Profile'} ({profile_id})": profile_id for profile_id, name in sorted(seen.items())}
        errors: dict[str, str] = {}
        if user_input is not None:
            profiles = {labels[label]: person for label, person in user_input.items() if label in labels and person}
            # A profile no TV has reported yet (nobody used it today): its id typed in, as Hearth shows it
            extra_id = (user_input.get("profile_id") or "").strip()
            if extra_id:
                if not re.fullmatch(r"user:\d+(:[a-z0-9._-]+)?", extra_id) or not user_input.get("profile_person"):
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
                        "group": user_input.get("group") or None,
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
