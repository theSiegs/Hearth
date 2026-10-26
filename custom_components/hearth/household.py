"""People, their screen time today, and their limits: from what the household's devices post.

The people are Home Assistant persons the household maps to (options): each TV profile, each phone. A person's day is
counted from the devices (counting.py), against the budgets of each group (limits.py), and what each device is told
(its state document) comes from here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
import hashlib
import json
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .const import CONF_KIND, CONF_PERSON, CONF_PROFILES, DOMAIN, EVENT_BUDGET_REACHED, KIND_TV, SIGNAL_PEOPLE
from .counting import ALL, DeviceUsage, Reading, group_seconds, merge
from .limits import Group, GroupState, Limits, groups_from_options, groups_of

if TYPE_CHECKING:
    from .hub import HearthHub

SOURCE_HEARTH = "hearth"


@dataclass
class Playing:
    app: str | None
    package: str | None
    device: str
    state: str | None


@dataclass
class PersonDay:
    person: str
    devices: dict[str, DeviceUsage] = field(default_factory=dict)
    groups: dict[str, float] = field(default_factory=dict)  # seconds
    limits: dict[str, GroupState] = field(default_factory=dict)
    playing: list[Playing] = field(default_factory=list)

    @property
    def total_s(self) -> float:
        return self.groups.get(ALL, 0.0)


class Household:
    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self.limits = Limits(hass, hub.entry.entry_id)
        self.days: dict[str, PersonDay] = {}
        self.groups: list[Group] = []
        self.categories: dict[str, str] = {}

    async def async_load(self) -> None:
        await self.limits.async_load()

    # The mapping

    @property
    def options(self) -> dict[str, Any]:
        return dict(self.hub.entry.options)

    def profile_people(self) -> dict[str, str]:
        return dict(self.options.get(CONF_PROFILES, {}))

    def device_person(self, device_id: str) -> str | None:
        return self.hub.devices.get(device_id, {}).get(CONF_PERSON)

    def people(self) -> list[str]:
        """Everyone the household maps something to, in a stable order."""
        found = {p for p in self.profile_people().values() if p}
        found |= {d.get(CONF_PERSON) for d in self.hub.devices.values() if d.get(CONF_PERSON)}
        return sorted(found)

    def person_name(self, person: str) -> str:
        state = self.hass.states.get(person)
        return state.name if state else person.split(".", 1)[-1].replace("_", " ").title()

    def seen_profiles(self) -> dict[str, str | None]:
        """TV profiles the TVs have reported: profile_id -> its name, for the options."""
        found: dict[str, str | None] = {}
        for device_id in self.hub.devices:
            status = self.hub.state(device_id).status or {}
            for profile_id, usage in (status.get("usage_today") or {}).items():
                found.setdefault(profile_id, usage.get("profile_name"))
            if status.get("profile_id"):
                found[status["profile_id"]] = status.get("profile") or found.get(status["profile_id"])
        return found

    def known_apps(self) -> dict[str, str]:
        """Apps the devices have reported today: package -> its name where known (else the package)."""
        apps: dict[str, str] = {}
        for device_id in self.hub.devices:
            status = self.hub.state(device_id).status or {}
            for usage in (status.get("usage_today") or {}).values():
                for package in usage.get("apps", {}):
                    apps.setdefault(package, package)
            for package in status.get("app_seconds_today") or {}:
                apps.setdefault(package, package)
            if status.get("app_package"):
                apps[status["app_package"]] = status.get("app") or status["app_package"]
        return apps

    # Counting

    def _today(self) -> date:
        return dt_util.now().date()

    @callback
    def recompute(self) -> None:
        today = self._today()
        new_day = self.limits.new_day(today)
        readings: dict[str, dict[str, list[Reading]]] = {}
        playing: dict[str, list[Playing]] = {}
        categories: dict[str, str] = {}
        profiles = self.profile_people()

        for device_id, device in self.hub.devices.items():
            state = self.hub.state(device_id)
            status = state.status
            if status is None:
                continue
            categories.update(status.get("app_categories") or {})
            name = device.get("name") or device_id
            # Yesterday's counts from a TV that hasn't posted since midnight don't count today
            fresh = status.get("day") == today.isoformat()
            if device.get(CONF_KIND) == KIND_TV:
                if fresh:
                    for profile_id, usage in (status.get("usage_today") or {}).items():
                        person = profiles.get(profile_id)
                        if person:
                            readings.setdefault(person, {}).setdefault(device_id, []).append(
                                Reading(SOURCE_HEARTH, float(usage.get("seconds") or 0), usage.get("apps") or {})
                            )
                person = profiles.get(status.get("profile_id") or "")
            else:
                person = device.get(CONF_PERSON)
                if person and fresh:
                    readings.setdefault(person, {}).setdefault(device_id, []).append(
                        Reading(
                            SOURCE_HEARTH,
                            float(status.get("seconds_today") or 0),
                            status.get("app_seconds_today") or {},
                        )
                    )
            if person and status.get("screen") == "on" and self.hub.connected(device_id) and status.get("app_package"):
                playing.setdefault(person, []).append(
                    Playing(status.get("app"), status.get("app_package"), name, status.get("state"))
                )

        self.categories = categories
        self.groups = groups_from_options(self.options)
        membership = groups_of(self.groups, categories)
        days: dict[str, PersonDay] = {}
        for person in self.people():
            devices = {device_id: merge(r) for device_id, r in readings.get(person, {}).items()}
            seconds = group_seconds(devices, membership)
            day = PersonDay(person, devices, seconds, playing=playing.get(person, []))
            for group in self.groups:
                state = self.limits.state(person, group.id, seconds.get(group.id, 0.0) / 60, today)
                day.limits[group.id] = state
                if state.minutes_left == 0:
                    if self.limits.mark_reached(person, group.id):
                        self.hass.bus.async_fire(
                            EVENT_BUDGET_REACHED, {"person": person, "group": group.id, "group_name": group.name}
                        )
                elif state.minutes_left is not None:
                    self.limits.clear_reached(person, group.id)
            days[person] = day
        self.days = days
        async_dispatcher_send(self.hass, SIGNAL_PEOPLE, new_day)

    # What a device is told

    def _person_document(self, person: str) -> dict[str, Any]:
        day = self.days.get(person)
        known = self.known_apps()
        membership = groups_of(self.groups, self.categories)
        groups = []
        for group in self.groups:
            state = day.limits.get(group.id) if day else None
            if state is None or state.budget_min is None:
                continue
            apps = sorted(group.apps | {p for p in known if group.id in membership(p)}) if group.id != ALL else []
            groups.append(
                {"id": group.id, "name": group.name, "minutes_left": state.minutes_left, "apps": apps}
            )
        return {"person": person, "groups": groups}

    def document_for(self, device_id: str) -> dict[str, Any]:
        """The device's state document: per TV profile (or, for a phone, its person) what's left today."""
        device = self.hub.devices.get(device_id, {})
        if device.get(CONF_KIND) == KIND_TV:
            status = self.hub.state(device_id).status or {}
            profile_ids = set((status.get("usage_today") or {}).keys())
            if status.get("profile_id"):
                profile_ids.add(status["profile_id"])
            profiles = self.profile_people()
            body: dict[str, Any] = {
                "profiles": {
                    profile_id: self._person_document(profiles[profile_id])
                    for profile_id in sorted(profile_ids)
                    if profiles.get(profile_id)
                }
            }
        else:
            person = device.get(CONF_PERSON)
            body = {"person": self._person_document(person) if person else None}
        body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        return body

    # Changes from services and entities

    def group(self, group_id: str) -> Group | None:
        return next((g for g in self.groups if g.id == group_id), None)

    @callback
    def add_bonus(self, person: str, group: str, minutes: int) -> None:
        self.limits.set_bonus(person, group, self.limits.bonus(person, group) + minutes)
        self.recompute()

    @callback
    def set_bonus(self, person: str, group: str, minutes: int) -> None:
        self.limits.set_bonus(person, group, minutes)
        self.recompute()

    @callback
    def set_budget(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        self.limits.set_budget(person, group, kind, minutes)
        self.recompute()


def person_identifier(person: str) -> tuple[str, str]:
    return (DOMAIN, f"person:{person}")
