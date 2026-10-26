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
from homeassistant.helpers.selector import (
    EntitySelector,
    EntitySelectorConfig,
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    TextSelector,
)

from .const import CONF_GROUP_APPS, CONF_GROUPS, CONF_PERSON, CONF_PROFILES, DOMAIN, KIND_MOBILE
from .limits import BUILTIN_GROUPS, GAMES, VIDEO, slug

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
        return self.async_show_menu(step_id="init", menu_options=["people", "add_group", "group_apps", "remove_group"])

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
        if not labels:
            return self.async_abort(reason="no_profiles")
        if user_input is not None:
            profiles = {labels[label]: person for label, person in user_input.items() if label in labels and person}
            return self.async_create_entry(data={**options, CONF_PROFILES: profiles})
        schema = vol.Schema(
            {
                vol.Optional(label, description={"suggested_value": mapped.get(profile_id)}): PERSON_SELECTOR
                for label, profile_id in labels.items()
            }
        )
        return self.async_show_form(step_id="people", data_schema=schema)

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
