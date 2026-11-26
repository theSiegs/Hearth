"""Share Bluetooth with Home Assistant: a paired Hearth TV as an ESPHome Bluetooth proxy (docs/contracts/hearth-tv.md,
"Bluetooth sharing").

Each TV that says it can (cap `bluetooth_proxy`) gets a switch, off by default. The setting is one value with a
revision, kept here: the state document carries `bluetooth_proxy` `{on, rev, area}`; the TV's status carries its own
`{on, rev, changed, state, ...}`. Hearth takes a change made on the TV when it was made against Hearth's current
revision (or a revision Hearth no longer has), and raises the revision; a change here raises it too. So the later
change wins, on either side, without comparing clocks.

While on, the TV sends how ESPHome reaches its proxy (host, port, MAC, node name) and the proxy's encryption key (a
Noise pre-shared key the TV made once). The key is kept here (never in the status store, an entity or a log) and
Hearth adds the TV to Home Assistant's ESPHome integration itself, by going through ESPHome's own setup steps (host and
port, then the key) as a person would. When that can't be done (ESPHome not installed, an entry for the device already
there, the TV not answering), nothing is forced: the result is shown on the TV's Bluetooth sensor, and an
administrator reads the key with `hearth.get_tv_bluetooth` and enters it in ESPHome.
"""

from __future__ import annotations

import base64
import binascii
from datetime import datetime, timedelta
import ipaddress
import logging
import re
from typing import TYPE_CHECKING, Any

from homeassistant.config_entries import SOURCE_IGNORE, SOURCE_USER
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant, callback
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.helpers import area_registry as ar, device_registry as dr
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import DOMAIN

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

STORAGE_KEY = "hearth.bt_proxy"
STORAGE_VERSION = 1
SIGNAL_BT_PROXY = "hearth_bt_proxy_{}"
# A TV said for the first time that it can share its Bluetooth: the switch platform loads (__init__.py)
SIGNAL_BT_CAPABLE = "hearth_bt_proxy_capable"
ESPHOME = "esphome"
NOISE_PSK = "noise_psk"
DEFAULT_PORT = 6053

# What the TV says the setting comes to
OFF = "off"
RUNNING = "running"
NEEDS_PERMISSION = "needs_permission"
BLUETOOTH_OFF = "bluetooth_off"
LOCATION_OFF = "location_off"
STOPPED = "stopped"
STATES = [OFF, RUNNING, NEEDS_PERMISSION, BLUETOOTH_OFF, LOCATION_OFF, STOPPED]

# Hearth's adding the TV to ESPHome: not yet, done, an entry for it was already there, or couldn't (with why)
SETUP_WAITING = "waiting"
SETUP_ADDED = "added"
SETUP_EXISTS = "exists"
SETUP_FAILED = "failed"
SETUP_UNAVAILABLE = "esphome_unavailable"
# Added (or found there) once, then deleted in ESPHome: not added again until the switch is turned off and on
SETUP_REMOVED = "removed"
# A failed try is tried again this long after (the TV may have been asleep or away)
RETRY_AFTER = timedelta(minutes=10)

_NAME = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,29}[a-z0-9])?$")
_MAC = re.compile(r"^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$")
MAX_REV = 2**31 - 1


def proxy_key(value: Any) -> str | None:
    """An ESPHome API encryption key (32 bytes, base64), or None."""
    if not isinstance(value, str) or len(value) != 44:
        return None
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        return None
    return value if len(raw) == 32 else None


def _host(value: Any) -> str | None:
    """A private or link-local IPv4 address (a TV on the home network), else None."""
    if not isinstance(value, str):
        return None
    try:
        address = ipaddress.IPv4Address(value)
    except ValueError:
        return None
    return value if (address.is_private or address.is_link_local) and not address.is_loopback else None


def _mac(value: Any) -> str | None:
    """A unicast MAC, lowercase with colons (as ESPHome's entries' unique ids)."""
    if not isinstance(value, str):
        return None
    mac = value.strip().lower().replace("-", ":")
    if not _MAC.match(mac) or int(mac[:2], 16) & 1:
        return None
    return mac


def clean_report(raw: Any) -> dict[str, Any] | None:
    """A status's `bluetooth_proxy`, made safe (status.py); None when the TV sent none or it isn't an object."""
    if not isinstance(raw, dict) or not isinstance(raw.get("on"), bool):
        return None
    from .status import number, text

    rev = number(raw.get("rev"), 0, MAX_REV)
    state = raw.get("state")
    name = raw.get("name")
    port = number(raw.get("port"), 1, 65535)
    return {
        "on": raw["on"],
        "rev": rev if rev is not None else 0,
        "changed": raw.get("changed") is True,
        "state": state if state in STATES else None,
        "name": name if isinstance(name, str) and _NAME.match(name) else None,
        "friendly_name": text(raw.get("friendly_name"), 64),
        "mac": _mac(raw.get("mac")),
        "host": _host(raw.get("host")),
        "port": port if port is not None else DEFAULT_PORT,
        "key": proxy_key(raw.get("key")),
    }


def public(report: dict[str, Any] | None) -> dict[str, Any] | None:
    """The report without its key: what the status store and the entities keep."""
    if report is None:
        return None
    return {k: v for k, v in report.items() if k != "key"}


class BluetoothProxies:
    """The household's TVs' Bluetooth sharing: the setting by TV, and the proxy details each TV sent."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{STORAGE_KEY}.{hub.entry.entry_id}")
        # device -> {"on", "rev", "key", "mac", "host", "port", "name", "friendly_name", "esphome_added" (the key
        # Hearth added it to ESPHome with)}
        self._tvs: dict[str, dict[str, Any]] = {}
        # device -> (what happened, when, why) of Hearth's adding it to ESPHome; not kept over a restart
        self._setup: dict[str, tuple[str, datetime, str | None]] = {}
        self._setting_up: set[str] = set()

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for device_id, kept in stored.items():
            if isinstance(kept, dict) and device_id in self.hub.devices:
                self._tvs[device_id] = kept

    async def async_flush(self) -> None:
        await self._store.async_save(self._tvs)

    @callback
    def _save(self) -> None:
        self._store.async_delay_save(lambda: self._tvs, 5)

    def _tv(self, device_id: str) -> dict[str, Any]:
        return self._tvs.setdefault(device_id, {"on": False, "rev": 0})

    def wanted(self, device_id: str) -> bool:
        return bool(self._tvs.get(device_id, {}).get("on"))

    def rev(self, device_id: str) -> int:
        return int(self._tvs.get(device_id, {}).get("rev") or 0)

    def area_name(self, device_id: str) -> str | None:
        """The area of the TV's device in Home Assistant, for ESPHome's suggested area."""
        registry = dr.async_get(self.hass)
        device = registry.async_get_device_by_identifier((DOMAIN, device_id), self.hub.entry.entry_id)
        if device is None or not device.area_id:
            return None
        area = ar.async_get(self.hass).async_get_area(device.area_id)
        return area.name if area else None

    def document_for(self, device_id: str) -> dict[str, Any]:
        """The state document's `bluetooth_proxy`."""
        return {"on": self.wanted(device_id), "rev": self.rev(device_id), "area": self.area_name(device_id)}

    @callback
    def set(self, device_id: str, on: bool) -> None:
        """An adult (or an automation) turned it on or off in Home Assistant: the TV gets it with its next word."""
        tv = self._tv(device_id)
        if tv.get("on") == on:
            return
        tv["on"] = on
        tv["rev"] = min(int(tv.get("rev") or 0) + 1, MAX_REV)
        self._turned(device_id, tv)
        self._save()
        self._changed(device_id)
        self.hub.waits.changed()

    @callback
    def _changed(self, device_id: str) -> None:
        async_dispatcher_send(self.hass, SIGNAL_BT_PROXY.format(device_id))

    @callback
    def on_report(self, device_id: str, report: dict[str, Any]) -> None:
        """What the TV said in its status: a change made on it is taken when it's the later one; the proxy's details
        are kept; a TV running its proxy is added to ESPHome."""
        tv = self._tv(device_id)
        rev = int(tv.get("rev") or 0)
        changed = False
        if report["on"] != bool(tv.get("on")) and (
            report["changed"] and report["rev"] == rev or report["rev"] > rev
        ):
            tv["on"] = report["on"]
            tv["rev"] = min(max(rev, report["rev"]) + 1, MAX_REV)
            self._turned(device_id, tv)
            changed = True
            # The TV hears it's taken (its revision goes up) with this very answer
            self.hub.waits.changed()
        elif report["rev"] > rev:
            # The same value at a revision Hearth lost (its store started again): carried on from the TV's
            tv["rev"] = report["rev"]
            changed = True
        for field in ("mac", "host", "port", "name", "friendly_name", "key"):
            if report.get(field) is not None and tv.get(field) != report[field]:
                tv[field] = report[field]
                changed = True
        if changed:
            self._save()
        self._changed(device_id)
        if tv.get("on") and report.get("state") == RUNNING:
            self._maybe_add_to_esphome(device_id)

    def _turned(self, device_id: str, tv: dict[str, Any]) -> None:
        """Turned on or off: an ESPHome entry deleted since Hearth added it is added again the next time it runs."""
        tv.pop("esphome_added", None)
        self._setup.pop(device_id, None)

    @callback
    def forget(self, device_id: str) -> None:
        if self._tvs.pop(device_id, None) is not None:
            self._save()
        self._setup.pop(device_id, None)

    def setup_state(self, device_id: str) -> tuple[str, str | None]:
        """Hearth's adding the TV to ESPHome: (state, why), SETUP_EXISTS when an entry for it is there now."""
        tv = self._tvs.get(device_id, {})
        added = tv.get("esphome_added") is not None and tv.get("esphome_added") == tv.get("key")
        if self.esphome_entry(tv.get("mac"), tv.get("host")) is not None:
            found = self._setup.get(device_id)
            return (SETUP_ADDED if added or found and found[0] == SETUP_ADDED else SETUP_EXISTS), None
        if added:
            return SETUP_REMOVED, None
        found = self._setup.get(device_id)
        return (found[0], found[2]) if found else (SETUP_WAITING, None)

    def details(self, device_id: str) -> dict[str, Any]:
        """Everything about the TV's proxy, its key included: for administrators only (hearth.get_tv_bluetooth)."""
        tv = self._tvs.get(device_id, {})
        state, why = self.setup_state(device_id)
        status = (self.hub.state(device_id).status or {}).get("bluetooth_proxy") or {}
        return {
            "on": bool(tv.get("on")),
            "state": status.get("state"),
            "name": tv.get("name"),
            "friendly_name": tv.get("friendly_name"),
            "host": tv.get("host"),
            "port": tv.get("port") or DEFAULT_PORT,
            "mac": tv.get("mac"),
            NOISE_PSK: tv.get("key"),
            "esphome": state,
            "esphome_detail": why,
        }

    def esphome_entry(self, mac: str | None, host: str | None) -> Any:
        """Home Assistant's ESPHome entry for this proxy (by its MAC, the entry's unique id, or its host), ignored
        ones included; None when there is none."""
        for entry in self.hass.config_entries.async_entries(ESPHOME, include_ignore=True):
            if mac and entry.unique_id and entry.unique_id.lower() == mac:
                return entry
            if host and entry.source != SOURCE_IGNORE and entry.data.get(CONF_HOST) == host:
                return entry
        return None

    @callback
    def _maybe_add_to_esphome(self, device_id: str) -> None:
        tv = self._tvs.get(device_id, {})
        if not (tv.get("key") and tv.get("host") and tv.get("mac")) or device_id in self._setting_up:
            return
        if self.esphome_entry(tv["mac"], tv["host"]) is not None or tv.get("esphome_added") == tv["key"]:
            return
        last = self._setup.get(device_id)
        if last is not None and last[0] != SETUP_WAITING and dt_util.utcnow() - last[1] < RETRY_AFTER:
            return
        self._setting_up.add(device_id)
        self.hub.entry.async_create_background_task(
            self.hass, self._async_add_to_esphome(device_id), f"hearth add {device_id} to esphome"
        )

    def _note(self, device_id: str, state: str, why: str | None = None) -> None:
        self._setup[device_id] = (state, dt_util.utcnow(), why)
        self._changed(device_id)

    def _mark_added(self, device_id: str, key: str) -> None:
        """Kept: an entry deleted later in ESPHome is the owner's choice, not added back on its own."""
        if (tv := self._tvs.get(device_id)) is not None and tv.get("key") == key:
            tv["esphome_added"] = key
            self._save()

    async def _async_add_to_esphome(self, device_id: str) -> None:
        """ESPHome's own setup, as a person goes through it: host and port, then the encryption key. Anything other
        than those two steps is left alone (the flow is ended) and noted; never logged with the key."""
        tv = dict(self._tvs.get(device_id, {}))
        flows = self.hass.config_entries.flow
        flow_id: str | None = None
        try:
            result = await flows.async_init(
                ESPHOME,
                context={"source": SOURCE_USER},
                data={CONF_HOST: tv["host"], CONF_PORT: tv.get("port") or DEFAULT_PORT},
            )
            if result["type"] is FlowResultType.FORM and result.get("step_id") == "encryption_key":
                flow_id = result["flow_id"]
                result = await flows.async_configure(flow_id, {NOISE_PSK: tv["key"]})
            if result["type"] is FlowResultType.CREATE_ENTRY:
                flow_id = None
                self._mark_added(device_id, tv["key"])
                self._note(device_id, SETUP_ADDED)
                _LOGGER.info("Added %s to ESPHome", tv.get("name") or device_id)
            elif result["type"] is FlowResultType.ABORT:
                flow_id = None
                reason = str(result.get("reason") or "")
                if reason == "already_configured":
                    self._mark_added(device_id, tv["key"])
                self._note(device_id, SETUP_EXISTS if reason == "already_configured" else SETUP_FAILED, reason)
            else:
                flow_id = result.get("flow_id")
                errors = result.get("errors") or {}
                self._note(device_id, SETUP_FAILED, str(errors.get("base") or result.get("step_id") or "form"))
        except Exception as err:  # noqa: BLE001: ESPHome not installed or not loadable, or its flow failing
            name = type(err).__name__
            unavailable = name in ("UnknownHandler", "IntegrationNotFound", "RequirementsNotFound")
            self._note(device_id, SETUP_UNAVAILABLE if unavailable else SETUP_FAILED, name)
            _LOGGER.debug("Couldn't add %s to ESPHome: %s", device_id, name)
        finally:
            if flow_id is not None:
                # A step Hearth doesn't answer (a name conflict, a wrong key): nothing is left waiting
                try:
                    flows.async_abort(flow_id)
                except Exception:  # noqa: BLE001
                    pass
            self._setting_up.discard(device_id)


def async_register_service(hass: HomeAssistant) -> None:
    """hearth.get_tv_bluetooth: each TV's Bluetooth proxy, its encryption key included, for entering it in ESPHome by
    hand when Hearth couldn't add it. Administrators only (as a Glint Panel's proxy key)."""
    import voluptuous as vol

    from homeassistant.core import ServiceCall, ServiceResponse, SupportsResponse
    from homeassistant.exceptions import ServiceValidationError, Unauthorized
    import homeassistant.helpers.config_validation as cv

    schema = vol.Schema({vol.Optional("device_id"): vol.All(cv.ensure_list, [cv.string])})

    async def get_tv_bluetooth(call: ServiceCall) -> ServiceResponse:
        user = await hass.auth.async_get_user(call.context.user_id) if call.context.user_id else None
        if user is None or not user.is_active or not user.is_admin:
            raise Unauthorized(context=call.context, user_id=call.context.user_id)
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't loaded")
        hub = entries[0].runtime_data
        from .const import KIND_TV

        tvs = [d for d in hub.devices if hub.kind(d) == KIND_TV]
        if given := call.data.get("device_id"):
            registry = dr.async_get(hass)
            wanted: list[str] = []
            for one in given:
                if one in tvs:
                    wanted.append(one)
                    continue
                device = registry.async_get(one)
                found = [i for d, i in (device.identifiers if device else ()) if d == DOMAIN and i in tvs]
                if not found:
                    raise ServiceValidationError(f"{one} isn't one of the household's Hearth TVs")
                wanted.extend(found)
            tvs = wanted
        return {
            "tvs": {
                device_id: {"tv": hub.devices[device_id].get("name"), **hub.bt_proxy.details(device_id)}
                for device_id in tvs
            }
        }

    hass.services.async_register(
        DOMAIN, "get_tv_bluetooth", get_tv_bluetooth, schema=schema, supports_response=SupportsResponse.ONLY
    )
