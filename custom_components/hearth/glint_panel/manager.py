"""The household's Glint Panels: their store (the one source of truth for their settings), pairing's panel kind, and the
documents pushed to their subscriptions.

One per Home Assistant run (Panels.get), so a panel's subscription outlives the serving entry reloading for some other
reason; the host is attached while the entry is loaded. Saving a panel's settings never touches the config entry.
"""

from __future__ import annotations

import copy
import logging
import secrets
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from homeassistant.const import EVENT_HOMEASSISTANT_STOP, EVENT_LOGBOOK_ENTRY
from homeassistant.core import CALLBACK_TYPE, Event, HomeAssistant, callback
from homeassistant.helpers import area_registry as ar
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_call_later
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import document, hello, start
from .const import (
    CONNECTED_GRACE,
    DEFAULT_PAGE,
    ESPHOME,
    HELLO_DENIED_FOR,
    HELLO_UNSEEN,
    HOUSE_PANEL,
    IDENTIFIER_PREFIX,
    MAX_HELLOS,
    MAX_REPORTS,
    MAX_STARTS,
    NEVER_DEALT_COVERS,
    NEVER_DEALT_DOMAINS,
    NOTHING_ON_TABLET,
    PUSH_DELAY,
    REPORT_WINDOW,
    START_GRID,
    START_VERSIONS,
    STORE_VERSION,
    VIEWS,
    identifier,
    signal,
    signal_added,
    store_key,
    unique_id,
)
from .host import PanelHost

_LOGGER = logging.getLogger(__name__)
MAX_ON_TABLET = 255


@dataclass
class Subscription:
    """One open <d>/panel/subscribe: where the documents go, and the version it last got."""

    send: Callable[[dict[str, Any]], None]
    version: str | None = None


class HelloRefused(Exception):
    """A hello that is refused outright: [code] "taken" (the id is a TV's or a phone's) or "try_later" (too many wait)."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class _Live:
    """What isn't kept: a panel's open subscriptions, and its reports this minute."""

    subs: dict[int, Subscription] = field(default_factory=dict)
    closed_at: datetime | None = None
    reports: list[datetime] = field(default_factory=list)
    starts: list[datetime] = field(default_factory=list)
    login: dict[str, str | None] | None = None


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
        # {"panels": {device_id: record}, "house": {key: value}, "hellos": {hello's device_id: hello}}
        self.data: dict[str, Any] = {"panels": {}, "house": {}, "hellos": {}}
        self._live: dict[str, _Live] = {}
        # Open hello subscriptions, by the hello's device id: {key: (its login's user id, send)}
        self._hello_subs: dict[str, dict[int, tuple[str | None, Callable[[dict[str, Any]], None]]]] = {}
        # An approved hello's secret until the panel takes it up, by the hello's device id: never stored (after a
        # restart the hello gets a fresh one, and the old one stops)
        self._hello_secrets: dict[str, str] = {}
        # When the serving entry last attached: for CONNECTED_GRACE after, every panel counts as connected for a hello
        # (seems_connected), since a healthy panel's socket isn't back yet
        self._attached_at: datetime | None = None
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
        first = not self._loaded
        if first:
            stored = await self._store.async_load() or {}
            panels = stored.get("panels")
            house = stored.get("house")
            hellos = stored.get("hellos")
            self.data = {
                "panels": {k: v for k, v in panels.items() if isinstance(v, dict)} if isinstance(panels, dict) else {},
                "house": dict(house) if isinstance(house, dict) else {},
                "hellos": {k: v for k, v in hellos.items() if isinstance(v, dict)} if isinstance(hellos, dict) else {},
            }
            self._loaded = True
            # The registry's names (a proxy's name comes from its device's) need the entry before the host serves
            self.entry_id = host.entry_id
            if self._give_keys() | self._give_macs() | self._forget_secrets() | self._prune_hellos(host):
                self._save()
            self.hass.bus.async_listen(dr.EVENT_DEVICE_REGISTRY_UPDATED, self._device_updated)
            self.hass.bus.async_listen(ar.EVENT_AREA_REGISTRY_UPDATED, self._area_updated)
            self.hass.bus.async_listen(er.EVENT_ENTITY_REGISTRY_UPDATED, self._entity_updated)
            self.hass.bus.async_listen_once(EVENT_HOMEASSISTANT_STOP, self._stopping)
        self.host = host
        self.entry_id = host.entry_id
        self._attached_at = dt_util.utcnow()
        if first:
            # Hellos still waiting when Home Assistant stopped: their discovered cards again (no second notice)
            for device_id, entry in self.hellos.items():
                if entry.get("status") == "pending":
                    host.hello_waiting(device_id, self._hello_title(entry), again=True)

    def _forget_secrets(self) -> bool:
        """An approved hello's secret is never kept in the store: one stored before (the secret in plain text) is
        dropped (its hello gets a fresh secret). Whether any was."""
        dropped = False
        for entry in self.hellos.values():
            if entry.pop("secret", None) is not None:
                dropped = True
        return dropped

    def _give_keys(self) -> bool:
        """Every panel has its proxy key: one paired before every panel got one (or with a stored key that isn't one)
        gets a fresh one. Whether any did."""
        given = False
        for record in self.panels.values():
            if document.proxy_key(record.get("key")) is None:
                record["key"] = document.new_proxy_key()
                given = True
        return given

    def _give_macs(self) -> bool:
        """Every panel has its proxy MAC, kept for life: one without takes its proxy's MAC from the ESPHome entry named
        as its proxy is (so ESPHome sees the same device), else one derived from its id. Whether any did."""
        given = False
        held = {mac for record in self.panels.values() if (mac := hello.clean_mac(record.get("mac")))}
        entries = self._esphome_entries()
        for device_id in self._ordered():
            record = self.panels[device_id]
            if hello.clean_mac(record.get("mac")):
                continue
            proxy = (record.get("values") or {}).get("proxy_name") or document.proxy_name(self.name(device_id))
            mac = hello.adopted_mac(proxy, entries)
            if mac is None or mac in held:
                mac = hello.mac_from_id(device_id)
            record["mac"] = mac
            held.add(mac)
            given = True
        return given

    def _esphome_entries(self) -> list[tuple[Any, list[Any]]]:
        return [
            (entry.unique_id, [entry.title, entry.data.get("device_name"), entry.data.get("host")])
            for entry in self.hass.config_entries.async_entries(ESPHOME)
        ]

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
        """Pairing asks: is this device id a panel's, or one of its tablets' (so a TV or phone of the same id isn't
        paired over it)."""
        return hello.panel_of(device_id, self.panels) is not None

    def authorized(self, device_id: str, secret: str | None) -> bool:
        """The device secret is this panel's. The panel signs in to Home Assistant with a token the owner made (any
        user's; panels may share one): the secret, not the login, says which panel it is."""
        record = self.panels.get(device_id)
        return (
            record is not None
            and self.host is not None
            and self.host.secret_matches(record.get("secret_hash"), secret)
        )

    def note_login(self, device_id: str, user: str | None, token: str | None, user_id: str | None = None) -> None:
        """Who the panel's subscription signed in as (the user's name and the token's name), for get_panel; the user's
        id is kept with the panel (a hello on the same login is the panel's own: hello.at_once's own_login)."""
        live = self._live.setdefault(device_id, _Live())
        live.login = {"user": user, "token": token}
        record = self.panels.get(device_id)
        if record is not None and user_id and record.get("user_id") != user_id:
            record["user_id"] = user_id
            self._save()

    def logins(self) -> list[tuple[str | None, str | None, str]]:
        """Read only: the Home Assistant logins the panels and the tablets saying hello sign in with, as (user id,
        token name, the panel's name). Hearth never offers such a login as an adult (adult_offer.py)."""
        found: list[tuple[str | None, str | None, str]] = []
        for device_id, record in self.panels.items():
            live = self._live.get(device_id)
            token = (live.login or {}).get("token") if live is not None else None
            found.append((record.get("user_id"), token, self.name(device_id)))
        for entry in self.hellos.values():
            login = entry.get("signed_in_as")
            token = login.get("token") if isinstance(login, dict) else None
            found.append((entry.get("user_id"), token, self._hello_title(entry)))
        return found

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
            start=self.start_section(device_id),
            mac=record.get("mac"),
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
        """An administrator approved a panel's pairing (with an area, or none): its device and its record. Home
        Assistant's own login is the owner's to give the panel (a long-lived token): pairing makes no user. The
        answer's extra fields for the panel (none); None: not now."""
        if self.host is None or hello.panel_of(pairing.device_id, self.panels) not in (None, pairing.device_id):
            # Not over a tablet id of another panel: that tablet says hello and is that panel
            return None
        areas = ar.async_get(self.hass)
        area = areas.async_get_area(area_id) if area_id else None
        if area is None and (known := self.registry_device(pairing.device_id)) is not None:
            # Pairing again without a room keeps the room it has (and so its name)
            area = areas.async_get_area(known.area_id) if known.area_id else None
        self._put_panel(
            pairing.device_id, pairing.model, pairing.sw_version, getattr(pairing, "seed", None), secret_hash, area
        )
        return {}

    def _put_panel(
        self,
        device_id: str,
        model: str | None,
        sw_version: str | None,
        seed: Any,
        secret_hash: str,
        area: ar.AreaEntry | None,
    ) -> None:
        """A panel joins (or joins again, keeping what it has) with [secret_hash]: its device named for [area] and in
        it before any entity is registered (so entity ids are <area>_panel_<key>), then its record, then its
        entities."""
        host = self.host
        assert host is not None
        hass = self.hass
        record = self.panels.get(device_id)
        first = record is None
        devices = dr.async_get(hass)
        device = devices.async_get_or_create(
            config_entry_id=host.entry_id,
            identifiers={identifier(self.domain, device_id)},
            name=f"{area.name} panel" if area else "Panel",
            manufacturer="Glint",
            model=model or "Glint Panel",
            sw_version=sw_version,
            configuration_url=host.page_url(device_id),
        )
        if area is not None:
            device = devices.async_update_device(device.id, area_id=area.id) or device
        name = device.name_by_user or device.name or "Panel"

        if record is not None:
            # Pairing again: the old secret's subscriptions end, and so does an approved hello not taken up yet
            self._end_subscriptions(device_id)
            self._drop_approvals(device_id)

        values: dict[str, Any] = dict(record.get("values", {})) if record else {}
        key = record.get("key") if record else None
        if first:
            seeded, house, kept_key = document.clean_seed(seed, self.known(), self.house)
            values = seeded
            self.house.update(house)
            key = kept_key
        self.panels[device_id] = {
            "name": name,
            "secret_hash": secret_hash,
            "model": model,
            "sw_version": sw_version,
            # The first pairing's: the derived house panel goes by it, so pairing again never moves it
            "paired_at": (record.get("paired_at") if record else None) or dt_util.utcnow().isoformat(),
            **({"repaired_at": dt_util.utcnow().isoformat()} if record else {}),
            "values": values,
            # The panel's ESPHome proxy key: kept across pairings (and from the seed at the first), else a fresh one
            "key": document.proxy_key(key) or document.new_proxy_key(),
            "view": record.get("view") if record else None,
            "on_tablet": record.get("on_tablet") if record else None,
            # The panel's ESPHome proxy MAC, kept for life: a new panel's derived from its id
            "mac": hello.clean_mac(record.get("mac") if record else None) or hello.mac_from_id(device_id),
            # The panel's own Start, its last changes (undo), the room layout and page it last reported stay too, and
            # so do its tablets' ids, the login it last subscribed with and when it was last connected (pairing is
            # from the panel's own id: that is its current tablet again)
            **{
                k: record[k]
                for k in ("start", "start_versions", "room_layout", "page", "tablet_ids", "user_id", "last_connected")
                if record and k in record
            },
        }
        self._save()
        async_dispatcher_send(hass, signal_added(self.domain), device_id)
        self._changed()

    async def async_remove(self, device_id: str, *, from_registry: bool = True) -> bool:
        """A panel leaves: its subscriptions end, and (unless the registry is removing it
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
        # An approved hello not yet taken up goes with it (its secret is dead)
        for gone in [h for h, entry in self.hellos.items() if entry.get("target") == device_id]:
            self.hellos.pop(gone)
            self._hello_secrets.pop(gone, None)
        if from_registry and (device := self.registry_device(device_id)) is not None:
            dr.async_get(self.hass).async_remove_device(device.id)
        await self.async_flush()
        self._changed()
        return True

    async def async_remove_all(self) -> None:
        """The serving entry is deleted: every panel goes."""
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

    def set_proxy_key(self, device_id: str, key: str) -> None:
        """A checked key (document.proxy_key) becomes the panel's proxy key; pushed, so the panel restarts its proxy."""
        self.panels[device_id]["key"] = key
        self._save()
        self._changed()

    def set_proxy_mac(self, device_id: str, mac: str) -> None:
        """A checked MAC (hello.clean_mac) becomes the panel's proxy MAC (an administrator's only); pushed."""
        self.panels[device_id]["mac"] = mac
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
        return self._too_often(device_id, "reports", MAX_REPORTS)

    def too_many_starts(self, device_id: str) -> bool:
        """set_start: at most MAX_STARTS a minute per panel, counted apart from its reports."""
        return self._too_often(device_id, "starts", MAX_STARTS)

    def _too_often(self, device_id: str, kind: str, most: int) -> bool:
        now = dt_util.utcnow()
        live = self._live.setdefault(device_id, _Live())
        times = [t for t in getattr(live, kind) if now - t < REPORT_WINDOW]
        setattr(live, kind, times)
        if len(times) >= most:
            return True
        times.append(now)
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
        if "page" in msg:
            # The panel's page (cols, rows), checked by the command: the page a service's ops fit tiles on
            if msg["page"] is None:
                record.pop("page", None)
            else:
                record["page"] = {"cols": msg["page"]["cols"], "rows": msg["page"]["rows"]}
        if "room_layout" in msg:
            # Checked by the command (start.check_tiles, built-in kinds only); kept only to seed a first change
            if msg["room_layout"] is None:
                record.pop("room_layout", None)
            else:
                record["room_layout"] = msg["room_layout"]
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

    # The panel's own Start

    def never_dealt(self, entity_id: str) -> bool:
        """A normal state, never dealt out: doors, locks, garages, gates (and covers of those classes), sensors,
        people and trackers, alarm panels."""
        domain = entity_id.split(".", 1)[0]
        if domain in NEVER_DEALT_DOMAINS:
            return True
        if domain != "cover":
            return False
        state = self.hass.states.get(entity_id)
        device_class = state.attributes.get("device_class") if state is not None else None
        if device_class is None and (entry := er.async_get(self.hass).async_get(entity_id)) is not None:
            device_class = entry.device_class or entry.original_device_class
        return device_class in NEVER_DEALT_COVERS

    def start_tiles(self, device_id: str) -> list[dict[str, Any]] | None:
        """The panel's placed tiles; None for the room's layout (never changed, or changed back to it)."""
        stored = self.panels[device_id].get("start")
        return copy.deepcopy(stored.get("tiles")) if isinstance(stored, dict) else None

    def page(self, device_id: str) -> tuple[int, int]:
        """The panel's page (cols, rows) a service's ops fit tiles on: the one it last reported, else DEFAULT_PAGE."""
        page = self.panels[device_id].get("page")
        if isinstance(page, dict) and isinstance(page.get("cols"), int) and isinstance(page.get("rows"), int):
            return page["cols"], page["rows"]
        return DEFAULT_PAGE

    def start_grid(self, device_id: str) -> int:
        """The farthest cell a tile may reach in set_start: the larger side, 8, or a larger page the panel reported."""
        return max(START_GRID, *self.page(device_id))

    def start_version(self, device_id: str) -> str | None:
        return start.version_of(self.start_tiles(device_id))

    def start_section(self, device_id: str) -> dict[str, Any] | None:
        """The document's `start`: {tiles, changed, version}; tiles (and version) None once changed back to the room's
        layout; None for a panel whose Start was never changed."""
        stored = self.panels[device_id].get("start")
        if not isinstance(stored, dict):
            return None
        return {
            "tiles": copy.deepcopy(stored.get("tiles")),
            "changed": copy.deepcopy(stored.get("changed")),
            "version": start.version_of(stored.get("tiles")),
        }

    def room_layout(self, device_id: str) -> list[dict[str, Any]]:
        """The room's layout the panel last reported, to start a first change from; NotReady before it said one."""
        layout = self.panels[device_id].get("room_layout")
        if not isinstance(layout, list):
            raise start.NotReady("the panel hasn't said its layout yet")
        return copy.deepcopy(layout)

    def set_start(self, device_id: str, tiles: list[dict[str, Any]] | None, by: str) -> tuple[str | None, str]:
        """Checked [tiles] (None: the room's layout) become the panel's Start, stamped [by] now with a new undo id; the
        Start before is kept for undo (the last START_VERSIONS). Pushed. (The new version, the undo id.)"""
        record = self.panels[device_id]
        versions: list[dict[str, Any]] = record.setdefault("start_versions", [])
        undo = secrets.token_hex(3)
        while any(v.get("undo") == undo for v in versions):
            undo = secrets.token_hex(3)
        at = dt_util.utcnow().replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
        versions.append({"undo": undo, "changed": {"by": by, "at": at}, "start": self.start_tiles(device_id)})
        del versions[:-START_VERSIONS]
        # Back to the room's layout keeps the stamp (tiles None), so the panel can say who changed it
        record["start"] = {"tiles": copy.deepcopy(tiles), "changed": {"by": by, "at": at, "undo": undo}}
        self._save()
        self._changed()
        return start.version_of(tiles), undo

    def undo_start(self, device_id: str, undo: str) -> list[dict[str, Any]] | None:
        """The Start from before change [undo] (one of the kept ones); Refused when it's unknown or expired."""
        for version in self.panels[device_id].get("start_versions", []):
            if version.get("undo") == undo:
                return copy.deepcopy(version.get("start"))
        raise document.Refused(f"no change {undo} to undo (only the last {START_VERSIONS} are kept)")

    def start_versions(self, device_id: str) -> list[dict[str, Any]]:
        """The kept changes, newest first: {undo, changed: {by, at}} (what get_panel shows)."""
        return [
            {"undo": v["undo"], "changed": copy.deepcopy(v.get("changed"))}
            for v in reversed(self.panels[device_id].get("start_versions", []))
        ]

    @callback
    def _entity_updated(self, event: Event) -> None:
        """An entity's id was renamed: rewritten in every panel's settings, Start (and its kept changes) and reported
        room layout, and in the house-wide values; pushed. A removed entity is kept: the panel marks its tile until
        someone removes it."""
        data = event.data
        if data.get("action") != "update" or not data.get("old_entity_id"):
            return
        old, new = data["old_entity_id"], data["entity_id"]
        touched = document.rename_house(self.house, old, new)
        for record in self.panels.values():
            if isinstance(values := record.get("values"), dict) and document.rename_values(values, old, new):
                touched = True
            if isinstance(record.get("room_layout"), list) and start.rename(record["room_layout"], old, new):
                touched = True
            stored = record.get("start")
            if isinstance(stored, dict) and start.rename(stored.get("tiles"), old, new):
                touched = True
            for version in record.get("start_versions", []):
                if start.rename(version.get("start"), old, new):
                    touched = True
        if touched:
            self._save()
            self._changed()

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
        if (record := self.panels.get(device_id)) is not None:
            # Kept, so "offline since" outlives a restart
            record["last_connected"] = live.closed_at.isoformat()
            self._save()

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

    def seems_connected(self, device_id: str) -> bool:
        """connected, or the serving entry attached (Home Assistant started) less than CONNECTED_GRACE ago: a healthy
        panel's socket may not be back yet, so a hello never takes its place or its secret as if it were offline."""
        if self._attached_at is not None and dt_util.utcnow() - self._attached_at < CONNECTED_GRACE:
            return True
        return self.connected(device_id)

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

    # Setting a panel up over its socket (<domain>/panel/hello; hello.py has the rules and the gate)

    @property
    def hellos(self) -> dict[str, dict[str, Any]]:
        return self.data["hellos"]

    def _prune_hellos(self, host: PanelHost | None = None) -> bool:
        """A hello unseen for HELLO_UNSEEN goes, and an approved one whose panel is gone; a waiting one's card and
        notice go with it. Whether any did (the caller saves)."""
        host = host or self.host
        now = dt_util.utcnow()
        gone = []
        for device_id, entry in self.hellos.items():
            seen = dt_util.parse_datetime(entry.get("last_seen") or "")
            if seen is None or now - seen > HELLO_UNSEEN:
                gone.append(device_id)
            elif entry.get("status") == "approved" and entry.get("target") not in self.panels:
                gone.append(device_id)
        for device_id in gone:
            entry = self.hellos.pop(device_id)
            self._hello_secrets.pop(device_id, None)
            if entry.get("status") == "pending" and host is not None:
                host.hello_answered(device_id)
        return bool(gone)

    def _hello_area(self, value: Any) -> ar.AreaEntry | None:
        """The area a hello names: an area id, else an area's name (any case); None when HA has none."""
        if not isinstance(value, str) or not value.strip():
            return None
        areas = ar.async_get(self.hass)
        return areas.async_get_area(value) or areas.async_get_area_by_name(value.strip())

    @staticmethod
    def _hello_title(entry: dict[str, Any]) -> str:
        return entry.get("name") or entry.get("model") or "Panel"

    def hello(
        self, request: dict[str, Any], user: Any, token: str | None, send: Callable[[dict[str, Any]], None]
    ) -> Callable[[], None]:
        """A tablet with no secret says hello on [user]'s login (the token named [token]): it is sent
        {"status": "approved", ...} (hello.at_once), {"status": "pending"} (then approved or denied later on this
        subscription) or {"status": "denied"}. Returns the unsubscribe. HelloRefused: the id is a TV's or a phone's,
        or too many wait."""
        host = self.host
        assert host is not None
        hello_id = request["device_id"]
        if host.taken(hello_id):
            raise HelloRefused("taken", "That id is another device's: a panel never takes a TV's or a phone's")
        if self._prune_hellos():
            self._save()
        now = dt_util.utcnow().isoformat()
        user_id = user.id if user is not None else None
        trusted = host.trusted(user)
        login = {"user": user.name if user is not None else None, "token": token}
        entry = self.hellos.get(hello_id)

        if entry is not None and entry.get("status") == "approved":
            entry["last_seen"] = now
            self._save()
            if trusted or user_id == entry.get("user_id"):
                # Not taken up yet (no subscribe with its secret): approved again (a fresh secret after a restart)
                send(self._approved(hello_id, entry))
                return self._hello_sub(hello_id, user_id, send)
            # Another login never gets the secret: the approval stops (its secret with it) and the hello waits for an
            # approval in HA, on this login, with its card and notice
            self._stop_approval(hello_id, entry)
            return self._wait(hello_id, entry, request, user_id, login, now, send, new=True)

        # A refusal stands for HELLO_DENIED_FOR, whatever the hello names now
        denied_at = dt_util.parse_datetime((entry or {}).get("denied_at") or "")
        if entry is not None and entry.get("status") == "denied" and denied_at is not None:
            if dt_util.utcnow() - denied_at < HELLO_DENIED_FOR:
                entry["last_seen"] = now
                self._save()
                send({"status": "denied"})
                return self._hello_sub(hello_id, user_id, send)

        area = self._hello_area(request.get("area"))
        found = hello.match(
            hello_id, area.id if area else None, request.get("replaces"), self.panels, self.area_id, self.seems_connected
        )
        gate: dict[str, bool] = {}
        if found.rule == hello.KNOWN and found.device_id is not None:
            record = self.panels[found.device_id]
            gate = {
                "own_login": user_id is not None and user_id == record.get("user_id"),
                "connected": self.seems_connected(found.device_id),
                "current": hello_id == hello.current_tablet(found.device_id, record),
            }
        if hello.at_once(found, kid=host.kid(user), trusted=trusted, **gate):
            # A known panel, or one whose place it takes, keeps its room
            target, secret = self._take(found, hello_id, area if found.rule == hello.NEW else None, request)
            was_waiting = entry is not None and entry.get("status") == "pending"
            entry = {
                "status": "approved",
                "target": target,
                "user_id": user_id,
                "signed_in_as": login,
                "name": request.get("name"),
                "model": request.get("model"),
                "first_seen": (entry or {}).get("first_seen") or now,
                "last_seen": now,
            }
            self.hellos[hello_id] = entry
            self._hello_secrets[hello_id] = secret
            self._save()
            if was_waiting:
                host.hello_answered(hello_id)
            send(self._approved(hello_id, entry))
            return self._hello_sub(hello_id, user_id, send)

        new = entry is None or entry.get("status") != "pending"
        if new and sum(1 for e in self.hellos.values() if e.get("status") == "pending") >= MAX_HELLOS:
            raise HelloRefused("try_later", "Too many panels are waiting: approve or refuse them in Home Assistant")
        return self._wait(hello_id, None if new else entry, request, user_id, login, now, send, new=new)

    def _wait(
        self,
        hello_id: str,
        before: dict[str, Any] | None,
        request: dict[str, Any],
        user_id: str | None,
        login: dict[str, str | None],
        now: str,
        send: Callable[[dict[str, Any]], None],
        *,
        new: bool,
    ) -> Callable[[], None]:
        """The hello waits for an approval in HA ([before]: the entry it was, whose first sighting and seed it keeps);
        [new]: its card and the administrators' notice."""
        before = before or {}
        entry = {
            "status": "pending",
            "first_seen": before.get("first_seen") or now,
            "last_seen": now,
            "name": request.get("name"),
            "model": request.get("model"),
            "version": request.get("version"),
            "area": request.get("area"),
            "replaces": request.get("replaces"),
            # A seed comes once (the panel sends it with its first hello): kept from an earlier hello of this entry
            "seed": request.get("seed") if request.get("seed") is not None else before.get("seed"),
            # The login an approval hands the secret to (the card shows its names)
            "user_id": user_id,
            "signed_in_as": login,
        }
        self.hellos[hello_id] = entry
        self._save()
        if new:
            assert self.host is not None
            self.host.hello_waiting(hello_id, self._hello_title(entry))
        send({"status": "pending"})
        return self._hello_sub(hello_id, user_id, send)

    def _stop_approval(self, hello_id: str, entry: dict[str, Any]) -> None:
        """An approved hello not taken up stops: its secret no longer opens its panel (the panel gets one nobody
        holds, until an approval in HA)."""
        self._hello_secrets.pop(hello_id, None)
        if (target := entry.get("target")) in self.panels:
            self._rekey(target)

    def _hello_sub(
        self, hello_id: str, user_id: str | None, send: Callable[[dict[str, Any]], None]
    ) -> Callable[[], None]:
        subs = self._hello_subs.setdefault(hello_id, {})
        key = id(send)
        subs[key] = (user_id, send)

        @callback
        def unsubscribe() -> None:
            subs.pop(key, None)
            if not subs and self._hello_subs.get(hello_id) is subs:
                self._hello_subs.pop(hello_id, None)

        return unsubscribe

    def _tell_hello(self, hello_id: str, message: dict[str, Any], user_id: str | None = None, only: bool = False) -> None:
        """[message] to the hello's open subscriptions ([only]: those on [user_id]'s login)."""
        for sub_user, send in list(self._hello_subs.get(hello_id, {}).values()):
            if not only or sub_user == user_id:
                send(message)

    def _rekey(self, target: str) -> str:
        """The panel [target] gets a new secret, returned: the old one stops at once (its subscriptions are told)."""
        assert self.host is not None
        secret = secrets.token_urlsafe(32)
        record = self.panels[target]
        record["secret_hash"] = self.host.hash_secret(secret)
        record["repaired_at"] = dt_util.utcnow().isoformat()
        self._end_subscriptions(target)
        self._save()
        return secret

    def _drop_approvals(self, target: str, keep: str | None = None) -> None:
        """Approved hellos for [target] not taken up (but [keep]'s) go: the panel's secret changed, theirs is dead."""
        for hello_id in [
            h
            for h, entry in self.hellos.items()
            if h != keep and entry.get("status") == "approved" and entry.get("target") == target
        ]:
            self.hellos.pop(hello_id)
            self._hello_secrets.pop(hello_id, None)

    def _take(
        self, found: hello.Match, hello_id: str, area: ar.AreaEntry | None, request: dict[str, Any]
    ) -> tuple[str, str]:
        """The hello becomes [found]'s panel with a new secret (the old one stops at once): the same panel (KNOWN), the
        offline panel whose place it takes (TAKES_PLACE; its id joins the panel's tablet ids), or a new panel in
        [area] (NEW). The hello's id is the panel's current tablet from now on. A known panel given an [area] (an
        approval in HA) moves there. (The panel's device id, the secret.)"""
        host = self.host
        assert host is not None
        if found.rule == hello.NEW:
            assert area is not None
            secret = secrets.token_urlsafe(32)
            self._put_panel(
                hello_id, request.get("model"), request.get("version"), request.get("seed"), host.hash_secret(secret), area
            )
            return hello_id, secret
        target = found.device_id
        assert target is not None
        record = self.panels[target]
        # Its settings, room, Start, proxy key and MAC and name stay; the old secret's subscriptions end
        secret = self._rekey(target)
        self._drop_approvals(target, keep=hello_id)
        record["current_tablet"] = hello_id
        updates: dict[str, Any] = {}
        for key, said in (("model", "model"), ("sw_version", "version")):
            if isinstance(request.get(said), str) and request[said] and request[said] != record.get(key):
                record[key] = updates[key] = request[said][:64]
        if (device := self.registry_device(target)) is not None:
            if area is not None and device.area_id != area.id:
                # An approval in HA that names another room moves it there
                updates["area_id"] = area.id
            if updates:
                dr.async_get(self.hass).async_update_device(device.id, **updates)
        if found.rule == hello.TAKES_PLACE and hello_id != target:
            tablets = record.setdefault("tablet_ids", [])
            if hello_id not in tablets:
                tablets.append(hello_id)
            room = ar.async_get(self.hass).async_get_area(self.area_id(target) or "")
            entity_id = er.async_get(self.hass).async_get_entity_id(
                "binary_sensor", self.domain, unique_id(target, "connected")
            )
            self.hass.bus.async_fire(
                EVENT_LOGBOOK_ENTRY,
                {
                    "name": f"{room.name} panel" if room else self.name(target),
                    "message": "moved to a new tablet",
                    "domain": self.domain,
                    **({"entity_id": entity_id} if entity_id else {}),
                },
            )
        self._save()
        self._changed()
        return target, secret

    def _approved(self, hello_id: str, entry: dict[str, Any]) -> dict[str, Any]:
        """The approved answer. Its secret is kept in memory only: after a restart the panel gets a fresh one (the
        old one stops)."""
        target = entry["target"]
        assert self.host is not None
        if (secret := self._hello_secrets.get(hello_id)) is None:
            secret = self._hello_secrets[hello_id] = self._rekey(target)
        return {
            "status": "approved",
            "device_id": target,
            "secret": secret,
            "name": self.name(target),
            "area_id": self.area_id(target),
            "urls": self.host.urls(),
        }

    def taken_up(self, device_id: str) -> None:
        """The panel subscribed with its secret: an approved hello for it is done (its secret is never sent again)."""
        gone = [
            h for h, entry in self.hellos.items() if entry.get("status") == "approved" and entry.get("target") == device_id
        ]
        for hello_id in gone:
            self.hellos.pop(hello_id)
            self._hello_secrets.pop(hello_id, None)
        if gone:
            self._save()

    def waiting_hellos(self) -> list[dict[str, Any]]:
        """The hellos waiting for an approval in HA, oldest first, as the cards show them (never a secret)."""
        out = []
        for device_id, entry in sorted(self.hellos.items(), key=lambda kv: (kv[1].get("first_seen") or "", kv[0])):
            if entry.get("status") != "pending":
                continue
            known = hello.panel_of(device_id, self.panels)
            out.append(
                {
                    "device_id": device_id,
                    # What tells two waiting panels apart: the id's last four characters (the tablet shows them too)
                    "short_id": device_id[-4:],
                    "name": entry.get("name"),
                    "model": entry.get("model"),
                    "version": entry.get("version"),
                    "area": entry.get("area"),
                    "signed_in_as": copy.deepcopy(entry.get("signed_in_as")),
                    "first_seen": entry.get("first_seen"),
                    "last_seen": entry.get("last_seen"),
                    # The panel it already is (its id or a tablet id): approved as that panel again
                    "panel": {"device_id": known, "name": self.name(known)} if known else None,
                }
            )
        return out

    def waiting_hello(self, hello_id: str) -> dict[str, Any] | None:
        return next((h for h in self.waiting_hellos() if h["device_id"] == hello_id), None)

    def offline_panels(self) -> list[dict[str, Any]]:
        """The panels a waiting hello may take the place of (not connected: seems_connected, so none right after Home
        Assistant starts), newest offline first."""
        out = []
        for device_id in self.panels:
            if self.seems_connected(device_id):
                continue
            live = self._live.get(device_id)
            since = live.closed_at.isoformat() if live and live.closed_at else self.panels[device_id].get("last_connected")
            out.append(
                {
                    "device_id": device_id,
                    "name": self.name(device_id),
                    "area_id": self.area_id(device_id),
                    "offline_since": since,
                }
            )
        out.sort(key=lambda p: (p["offline_since"] or "", p["device_id"]), reverse=True)
        return out

    def approve_hello(self, hello_id: str, area_id: str | None, replaces: str | None = None) -> bool:
        """An administrator approved a waiting hello in HA, in the room [area_id] (required): as the panel it already
        is (its id becomes the panel's current tablet), in the place of the offline panel [replaces], or as a new
        panel. False: not waiting, no such room, or that panel is gone or connected now (seems_connected)."""
        entry = self.hellos.get(hello_id)
        host = self.host
        if host is None or entry is None or entry.get("status") != "pending" or host.taken(hello_id):
            return False
        area = ar.async_get(self.hass).async_get_area(area_id) if area_id else None
        if area is None:
            return False
        if (known := hello.panel_of(hello_id, self.panels)) is not None:
            found = hello.Match(hello.KNOWN, known)
        elif replaces:
            if replaces not in self.panels or self.seems_connected(replaces):
                return False
            found = hello.Match(hello.TAKES_PLACE, replaces)
        else:
            found = hello.Match(hello.NEW)
        target, secret = self._take(found, hello_id, area, entry)
        approved = {
            "status": "approved",
            "target": target,
            "user_id": entry.get("user_id"),
            "signed_in_as": entry.get("signed_in_as"),
            "name": entry.get("name"),
            "model": entry.get("model"),
            "first_seen": entry.get("first_seen"),
            "last_seen": entry.get("last_seen"),
        }
        self.hellos[hello_id] = approved
        self._hello_secrets[hello_id] = secret
        self._save()
        host.hello_answered(hello_id)
        # Only to the login that said hello (the one the card named)
        self._tell_hello(hello_id, self._approved(hello_id, approved), approved["user_id"], only=True)
        return True

    def deny_hello(self, hello_id: str) -> bool:
        """An administrator refused a waiting hello: it is told, and answered "denied" for HELLO_DENIED_FOR."""
        entry = self.hellos.get(hello_id)
        if self.host is None or entry is None or entry.get("status") != "pending":
            return False
        entry["status"] = "denied"
        entry["denied_at"] = dt_util.utcnow().isoformat()
        entry.pop("seed", None)
        self._save()
        self.host.hello_answered(hello_id)
        self._tell_hello(hello_id, {"status": "denied"})
        return True

    # Answers (get_panel): each value set or derived, never a secret (but the proxy key, to an administrator)

    def describe(self, device_id: str, *, admin: bool = False) -> dict[str, Any]:
        """The panel for get_panel; [admin] (the caller is a Home Assistant administrator) adds its proxy key."""
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
            # Who its subscription signed in as: {"user", "token"} names, null before it first subscribed
            "signed_in_as": live.login if (live := self._live.get(device_id)) is not None else None,
            "view": self.view(device_id),
            "on_the_tablet": self.on_tablet(device_id),
            "up_to_date": record.get("has_version") == doc["version"],
            "document": document.public(doc),
            # The panel's own Start (as in the document; null: the room's layout) and the changes undo can take back
            "start": copy.deepcopy(doc["start"]),
            "start_versions": self.start_versions(device_id),
            # For HA's ESPHome entry of the panel's proxy (its key and MAC), and the tablets that took its place:
            # administrators only
            **(
                {"proxy_key": record.get("key"), "mac": record.get("mac"), "tablet_ids": list(record.get("tablet_ids") or [])}
                if admin
                else {}
            ),
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
