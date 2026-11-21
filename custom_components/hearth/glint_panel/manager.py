"""The household's Glint Panels: their store (the one source of truth for their settings), pairing's panel kind, each
panel's own Home Assistant user, and the documents pushed to their subscriptions.

One per Home Assistant run (Panels.get), so a panel's subscription outlives the serving entry reloading for some other
reason; the host is attached while the entry is loaded. Saving a panel's settings never touches the config entry.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from homeassistant.auth.const import GROUP_ID_USER
from homeassistant.auth.models import TOKEN_TYPE_LONG_LIVED_ACCESS_TOKEN
from homeassistant.const import EVENT_HOMEASSISTANT_STOP
from homeassistant.core import CALLBACK_TYPE, Event, HomeAssistant, callback
from homeassistant.helpers import area_registry as ar
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_call_later
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import document
from .const import (
    CONNECTED_GRACE,
    HOUSE_PANEL,
    IDENTIFIER_PREFIX,
    MAX_REPORTS,
    NOTHING_ON_TABLET,
    PUSH_DELAY,
    REPORT_WINDOW,
    STORE_VERSION,
    TOKEN_CLIENT,
    TOKEN_DAYS,
    VIEWS,
    identifier,
    signal,
    signal_added,
    store_key,
)
from .host import PanelHost

_LOGGER = logging.getLogger(__name__)
MAX_ON_TABLET = 255


@dataclass
class Subscription:
    """One open <d>/panel/subscribe: where the documents go, and the version it last got."""

    send: Callable[[dict[str, Any]], None]
    version: str | None = None


@dataclass
class _Live:
    """What isn't kept: a panel's open subscriptions, and its reports this minute."""

    subs: dict[int, Subscription] = field(default_factory=dict)
    closed_at: datetime | None = None
    reports: list[datetime] = field(default_factory=list)


class Panels:
    """The Glint Panels of the household."""

    def __init__(self, hass: HomeAssistant, domain: str) -> None:
        self.hass = hass
        self.domain = domain
        self.host: PanelHost | None = None
        # The serving config entry the panels' devices belong to (kept while it reloads)
        self.entry_id: str | None = None
        self._store: Store[dict[str, Any]] = Store(hass, STORE_VERSION, store_key(domain))
        self._loaded = False
        # {"panels": {device_id: record}, "house": {key: value}}
        self.data: dict[str, Any] = {"panels": {}, "house": {}}
        self._live: dict[str, _Live] = {}
        self._dirty = False
        self._push_timer: CALLBACK_TYPE | None = None
        self._grace_timers: dict[str, CALLBACK_TYPE] = {}

    @classmethod
    def get(cls, hass: HomeAssistant, domain: str) -> Panels:
        """The run's one Panels (made on first use)."""
        key = f"{domain}_glint_panel"
        if key not in hass.data:
            hass.data[key] = cls(hass, domain)
        return hass.data[key]

    @classmethod
    def find(cls, hass: HomeAssistant, domain: str) -> Panels | None:
        """The run's Panels while the serving entry is loaded."""
        panels = hass.data.get(f"{domain}_glint_panel")
        return panels if panels is not None and panels.host is not None else None

    # Loading and saving

    async def async_attach(self, host: PanelHost) -> None:
        """The serving entry is loaded: load the store (once a run) and serve."""
        if not self._loaded:
            stored = await self._store.async_load() or {}
            panels = stored.get("panels")
            house = stored.get("house")
            self.data = {
                "panels": {k: v for k, v in panels.items() if isinstance(v, dict)} if isinstance(panels, dict) else {},
                "house": dict(house) if isinstance(house, dict) else {},
            }
            self._loaded = True
            self.hass.bus.async_listen(dr.EVENT_DEVICE_REGISTRY_UPDATED, self._device_updated)
            self.hass.bus.async_listen(ar.EVENT_AREA_REGISTRY_UPDATED, self._area_updated)
            self.hass.bus.async_listen_once(EVENT_HOMEASSISTANT_STOP, self._stopping)
        self.host = host
        self.entry_id = host.entry_id

    async def async_detach(self) -> None:
        """The serving entry unloads: saved now; subscriptions stay open for when it's back."""
        await self.async_flush()
        self.host = None

    async def async_flush(self) -> None:
        if self._loaded:
            await self._store.async_save(self._to_save())

    @callback
    def _to_save(self) -> dict[str, Any]:
        return self.data

    @callback
    def _save(self) -> None:
        self._store.async_delay_save(self._to_save, 1)

    @callback
    def _stopping(self, _event: Event) -> None:
        for cancel in [self._push_timer, *self._grace_timers.values()]:
            if cancel:
                cancel()
        self._push_timer = None
        self._grace_timers.clear()

    # The panels

    @property
    def panels(self) -> dict[str, dict[str, Any]]:
        return self.data["panels"]

    @property
    def house(self) -> dict[str, Any]:
        return self.data["house"]

    def has(self, device_id: str) -> bool:
        return device_id in self.panels

    def owns(self, device_id: str) -> bool:
        """Pairing asks: is this device id a panel's (so a TV or phone of the same id isn't paired over it)."""
        return device_id in self.panels

    def authorized(self, device_id: str, secret: str | None, user=None) -> bool:
        """The device secret is this panel's, and the WebSocket's user is the panel's own (or an administrator)."""
        record = self.panels.get(device_id)
        if record is None or self.host is None or not self.host.secret_matches(record.get("secret_hash"), secret):
            return False
        return user is None or user.is_admin or user.id == record.get("user_id")

    def registry_device(self, device_id: str) -> dr.DeviceEntry | None:
        if self.entry_id is None:
            return None
        return dr.async_get(self.hass).async_get_device_by_identifier(identifier(self.domain, device_id), self.entry_id)

    def name(self, device_id: str) -> str:
        device = self.registry_device(device_id)
        if device is not None:
            return device.name_by_user or device.name or "Panel"
        return self.panels.get(device_id, {}).get("name") or "Panel"

    def area_id(self, device_id: str) -> str | None:
        device = self.registry_device(device_id)
        return device.area_id if device is not None else None

    def known(self) -> document.Known:
        hass = self.hass
        entities, areas = er.async_get(hass), ar.async_get(hass)
        return document.Known(
            entity=lambda e: hass.states.get(e) is not None or entities.async_get(e) is not None,
            area=lambda a: areas.async_get_area(a) is not None,
        )

    def _ordered(self) -> list[str]:
        return sorted(self.panels, key=lambda d: (self.panels[d].get("paired_at") or "", d))

    def house_panel(self) -> str | None:
        """The house panel: the one switched on, else (none switched) the first shared-room panel (no people)."""
        chosen = self.house.get(HOUSE_PANEL)
        if chosen is not None:
            return chosen if chosen in self.panels else None
        return next((d for d in self._ordered() if not self.panels[d].get("values", {}).get("people")), None)

    def panel_areas(self) -> list[str]:
        return sorted({a for d in self.panels if (a := self.area_id(d))})

    def document(self, device_id: str) -> dict[str, Any]:
        record = self.panels[device_id]
        return document.build(
            self.domain,
            device_id,
            name=self.name(device_id),
            area_id=self.area_id(device_id),
            values=record.get("values", {}),
            house=self.house,
            house_panel=self.house_panel() == device_id,
            panel_areas=self.panel_areas(),
            key=record.get("key"),
        )

    def value(self, device_id: str, key: str) -> Any:
        """A panel's value for an entity: set, else the default."""
        from .const import SELECTS, SWITCHES

        if key == HOUSE_PANEL:
            return self.house_panel() == device_id
        values = self.panels.get(device_id, {}).get("values", {})
        if key in SWITCHES:
            return values.get(key, SWITCHES[key])
        if key in SELECTS:
            return values.get(key, SELECTS[key][0])
        return values.get(key)

    # Pairing's panel kind (the host's approve calls it)

    async def approve(self, pairing: Any, secret_hash: str, area_id: str | None) -> dict[str, Any] | None:
        """An administrator approved a panel's pairing (with an area, or none): its device, a user of its own with a
        long-lived token, and its record. The answer's extra fields for the panel (its token, once); None: not now."""
        host = self.host
        if host is None:
            return None
        hass = self.hass
        device_id = pairing.device_id
        areas = ar.async_get(hass)
        area = areas.async_get_area(area_id) if area_id else None
        record = self.panels.get(device_id)
        first = record is None
        devices = dr.async_get(hass)
        device = devices.async_get_or_create(
            config_entry_id=host.entry_id,
            identifiers={identifier(self.domain, device_id)},
            name=f"{area.name} panel" if area else "Panel",
            manufacturer="Glint",
            model=pairing.model or "Glint Panel",
            sw_version=pairing.sw_version,
            configuration_url=host.page_url(device_id),
        )
        if area is not None:
            device = devices.async_update_device(device.id, area_id=area.id) or device
        name = device.name_by_user or device.name or "Panel"

        user = await hass.auth.async_create_user(name, group_ids=[GROUP_ID_USER], local_only=True)
        if user.is_owner or user.is_admin:
            # Home Assistant makes the first user its owner: a panel is never that
            await hass.auth.async_remove_user(user)
            return None
        refresh = await hass.auth.async_create_refresh_token(
            user,
            client_name=TOKEN_CLIENT,
            token_type=TOKEN_TYPE_LONG_LIVED_ACCESS_TOKEN,
            access_token_expiration=timedelta(days=TOKEN_DAYS),
        )
        token = hass.auth.async_create_access_token(refresh)
        if record is not None:
            # Pairing again: the old user (and its token) goes, and the old secret's subscriptions end
            await self._remove_user(record.get("user_id"))
            self._end_subscriptions(device_id)

        values: dict[str, Any] = dict(record.get("values", {})) if record else {}
        key = record.get("key") if record else None
        if first:
            seeded, house, kept_key = document.clean_seed(getattr(pairing, "seed", None), self.known(), self.house)
            values = seeded
            self.house.update(house)
            key = kept_key
        self.panels[device_id] = {
            "name": name,
            "secret_hash": secret_hash,
            "user_id": user.id,
            "model": pairing.model,
            "sw_version": pairing.sw_version,
            "paired_at": dt_util.utcnow().isoformat(),
            "values": values,
            "key": key or document.new_proxy_key(),
            "view": record.get("view") if record else None,
            "on_tablet": record.get("on_tablet") if record else None,
        }
        self._save()
        async_dispatcher_send(hass, signal_added(self.domain), device_id)
        self._changed()
        return {"ha_token": token}

    async def _remove_user(self, user_id: str | None) -> None:
        if not user_id:
            return
        user = await self.hass.auth.async_get_user(user_id)
        if user is not None:
            await self.hass.auth.async_remove_user(user)

    async def async_remove(self, device_id: str, *, from_registry: bool = True) -> bool:
        """A panel leaves: its user (and token) goes, its subscriptions end, and (unless the registry is removing it
        already) its device and entities."""
        record = self.panels.pop(device_id, None)
        if record is None:
            return False
        if self.house.get(HOUSE_PANEL) == device_id:
            self.house.pop(HOUSE_PANEL)
        self._end_subscriptions(device_id)
        self._live.pop(device_id, None)
        if cancel := self._grace_timers.pop(device_id, None):
            cancel()
        await self._remove_user(record.get("user_id"))
        if from_registry and (device := self.registry_device(device_id)) is not None:
            dr.async_get(self.hass).async_remove_device(device.id)
        await self.async_flush()
        self._changed()
        return True

    async def async_remove_all(self) -> None:
        """The serving entry is deleted: every panel's user goes."""
        for device_id in list(self.panels):
            await self.async_remove(device_id, from_registry=False)

    # Changing values (the store, then one push)

    def set_values(self, device_id: str, changes: dict[str, Any]) -> None:
        """Checked values for a panel (None: back to derived); house_panel True / False / None."""
        values = self.panels[device_id].setdefault("values", {})
        for key, value in changes.items():
            if key == HOUSE_PANEL:
                self._set_house_panel(device_id, value)
            elif value is None:
                values.pop(key, None)
            else:
                values[key] = value
        self._save()
        self._changed()

    def _set_house_panel(self, device_id: str, on: bool | None) -> None:
        if on is None:
            self.house.pop(HOUSE_PANEL, None)
        elif on:
            self.house[HOUSE_PANEL] = device_id
        elif self.house_panel() == device_id:
            # Switched off: no house panel until one is switched on (not the derived one again)
            self.house[HOUSE_PANEL] = ""

    def set_house(self, changes: dict[str, Any]) -> None:
        for key, value in changes.items():
            if value is None:
                self.house.pop(key, None)
            else:
                self.house[key] = value
        self._save()
        self._changed()

    # Reports

    def too_many_reports(self, device_id: str) -> bool:
        now = dt_util.utcnow()
        live = self._live.setdefault(device_id, _Live())
        live.reports = [t for t in live.reports if now - t < REPORT_WINDOW]
        if len(live.reports) >= MAX_REPORTS:
            return True
        live.reports.append(now)
        return False

    def report(self, device_id: str, msg: dict[str, Any]) -> None:
        record = self.panels[device_id]
        if "view" in msg:
            view = msg["view"].strip().replace(" ", "_") if isinstance(msg["view"], str) else None
            record["view"] = view if view in VIEWS else None
        if "on_tablet" in msg:
            words = msg["on_tablet"]
            if isinstance(words, list):
                words = "; ".join(w for w in words if isinstance(w, str))
            record["on_tablet"] = (words or "").strip()[:MAX_ON_TABLET] or None if isinstance(words, str) else None
        if "version" in msg:
            record["has_version"] = msg["version"] if isinstance(msg["version"], str) else None
        updates: dict[str, Any] = {}
        for key in ("sw_version", "model"):
            if isinstance(msg.get(key), str) and msg[key] and msg[key] != record.get(key):
                record[key] = msg[key][:64]
                updates[key] = record[key]
        if updates and (device := self.registry_device(device_id)) is not None:
            dr.async_get(self.hass).async_update_device(device.id, **updates)
        self._save()
        async_dispatcher_send(self.hass, signal(self.domain, device_id))

    def view(self, device_id: str) -> str | None:
        return self.panels.get(device_id, {}).get("view")

    def on_tablet(self, device_id: str) -> str:
        return self.panels.get(device_id, {}).get("on_tablet") or NOTHING_ON_TABLET

    # Subscriptions

    def subscribe(self, device_id: str, send: Callable[[dict[str, Any]], None]) -> Callable[[], None]:
        """Sends the whole document now, then on every change; returns the unsubscribe."""
        live = self._live.setdefault(device_id, _Live())
        sub = Subscription(send)
        key = id(sub)
        live.subs[key] = sub
        if cancel := self._grace_timers.pop(device_id, None):
            cancel()
        self._send(device_id, sub, force=True)
        async_dispatcher_send(self.hass, signal(self.domain, device_id))

        @callback
        def unsubscribe() -> None:
            if live.subs.pop(key, None) is None:
                return
            if not live.subs:
                self._closed(device_id, live)

        return unsubscribe

    def _closed(self, device_id: str, live: _Live) -> None:
        live.closed_at = dt_util.utcnow()

        @callback
        def over(_now: datetime) -> None:
            self._grace_timers.pop(device_id, None)
            async_dispatcher_send(self.hass, signal(self.domain, device_id))

        if cancel := self._grace_timers.pop(device_id, None):
            cancel()
        self._grace_timers[device_id] = async_call_later(self.hass, CONNECTED_GRACE.total_seconds() + 1, over)

    def _end_subscriptions(self, device_id: str) -> None:
        """The panel was removed or paired again: each subscription is told ({"unpaired": true}) and gets no more."""
        live = self._live.get(device_id)
        if live is None:
            return
        for sub in list(live.subs.values()):
            sub.send({"unpaired": True})
        live.subs.clear()

    def connected(self, device_id: str) -> bool:
        """A subscription is open, or one closed less than CONNECTED_GRACE ago."""
        live = self._live.get(device_id)
        if live is None:
            return False
        if live.subs:
            return True
        return live.closed_at is not None and dt_util.utcnow() - live.closed_at < CONNECTED_GRACE

    @callback
    def _changed(self) -> None:
        """Something in the documents may have changed: entities now, subscriptions in one push a moment later."""
        for device_id in self.panels:
            async_dispatcher_send(self.hass, signal(self.domain, device_id))
        self._dirty = True
        if self._push_timer is None:
            self._push_timer = async_call_later(self.hass, PUSH_DELAY, self._push)

    @callback
    def _push(self, _now: datetime | None = None) -> None:
        self._push_timer = None
        if not self._dirty:
            return
        self._dirty = False
        for device_id, live in self._live.items():
            if device_id in self.panels:
                for sub in list(live.subs.values()):
                    self._send(device_id, sub)

    def _send(self, device_id: str, sub: Subscription, force: bool = False) -> None:
        doc = self.document(device_id)
        if not force and doc["version"] == sub.version:
            return
        sub.version = doc["version"]
        sub.send(doc)

    # The registries: a panel's area or name changed

    @callback
    def _panel_of(self, registry_id: str) -> str | None:
        device = dr.async_get(self.hass).async_get(registry_id)
        if device is None:
            return None
        for domain, ident in device.identifiers:
            if domain == self.domain and ident.startswith(IDENTIFIER_PREFIX) and ident[len(IDENTIFIER_PREFIX):] in self.panels:
                return ident[len(IDENTIFIER_PREFIX):]
        return None

    @callback
    def _device_updated(self, event: Event) -> None:
        if event.data.get("action") != "update":
            return
        device_id = self._panel_of(event.data["device_id"])
        if device_id is None:
            return
        changes = event.data.get("changes", {})
        if "area_id" in changes:
            self._rename(device_id)
        if {"area_id", "name", "name_by_user"} & set(changes):
            self._changed()

    @callback
    def _area_updated(self, event: Event) -> None:
        if event.data.get("action") != "update":
            return
        for device_id in list(self.panels):
            if self.area_id(device_id) == event.data.get("area_id"):
                self._rename(device_id)

    @callback
    def _rename(self, device_id: str) -> None:
        """Named for its area until the owner renames it."""
        device = self.registry_device(device_id)
        if device is None or device.name_by_user:
            return
        area = ar.async_get(self.hass).async_get_area(device.area_id) if device.area_id else None
        name = f"{area.name} panel" if area else "Panel"
        if device.name != name:
            dr.async_get(self.hass).async_update_device(device.id, name=name)
            self.panels[device_id]["name"] = name
            self._save()

    # Answers (get_panel): each value set or derived, never a secret

    def describe(self, device_id: str) -> dict[str, Any]:
        from .const import PANEL_KEYS

        record = self.panels[device_id]
        values = record.get("values", {})
        doc = self.document(device_id)
        settings = {
            key: {"value": self.value(device_id, key), "source": "set" if key in values else "derived"}
            for key in PANEL_KEYS
        }
        settings[HOUSE_PANEL] = {
            "value": self.house_panel() == device_id,
            "source": "set" if self.house.get(HOUSE_PANEL) is not None else "derived",
        }
        device = self.registry_device(device_id)
        return {
            "device_id": device_id,
            "ha_device_id": device.id if device else None,
            "name": self.name(device_id),
            "area_id": self.area_id(device_id),
            "settings": settings,
            "connected": self.connected(device_id),
            "view": self.view(device_id),
            "on_the_tablet": self.on_tablet(device_id),
            "up_to_date": record.get("has_version") == doc["version"],
            "document": document.public(doc),
        }

    def describe_house(self) -> dict[str, Any]:
        from .const import HOUSE_KEYS

        derived = document.build(
            self.domain, "", name="", area_id=None, values={}, house={}, house_panel=False, panel_areas=[], key=None
        )
        defaults = {
            "family_calendars": derived["calendars"]["family"],
            "person_calendars": derived["calendars"]["person"],
            "night": None,
            "doorbell_camera": None,
            "photos": None,
            "routine_windows": derived["routines"]["windows"],
            "commute_window": derived["routines"]["commute"],
        }
        return {
            key: {"value": self.house[key], "source": "set"} if key in self.house else {"value": defaults[key], "source": "derived"}
            for key in HOUSE_KEYS
        }
