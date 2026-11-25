"""Where a device is, for a presence reader (docs/contracts/device-presence.md): a phone's or tablet's Last
interaction sensor with whether its posts came straight over the home network, and hearth_tv_profile_changed."""

from datetime import timedelta
from ipaddress import ip_network
from unittest.mock import patch

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.helpers import area_registry as ar, device_registry as dr
from homeassistant.setup import async_setup_component
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_client_contract import _pair_phone
from test_init import PHONE_ID, STATUS, TV_ID, _pair, _set_up

SENSOR = "sensor.person_sam_phone_last_interaction"
IN_USE = {"screen": "on", "app": "Example Game", "app_package": "com.example.game", "seconds_today": 1200}
# A tablet on the home network, asking Home Assistant by its home address
TABLET = "10.0.0.20"
AT_HOME = {"Host": "10.0.0.5:8123"}
EVENT = "hearth_tv_profile_changed"
SAM = {**STATUS, "profile": "Sam", "profile_id": "user:10", "profile_ref": "name:sam", "kids_profile": True}
ALEX = {**STATUS, "profile": "Alex", "profile_id": "user:0", "profile_ref": "name:alex", "kids_profile": False}


async def _phone(hass: HomeAssistant, hass_client_no_auth) -> tuple:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair_phone(hass, client, PHONE_ID, "person.sam", None)
    return client, secret


async def _post(client, secret: str, body: dict, device_id: str = PHONE_ID, headers: dict | None = None):
    return await client.post(
        f"/api/hearth/device/{device_id}/status", json=body, headers={"X-Hearth-Secret": secret, **(headers or {})}
    )


def _from(peer: str | None):
    """The connection's other end, as the server would read it from the socket (a test's is always this machine)."""
    return patch("custom_components.hearth.api._peer", return_value=peer)


# The Last interaction sensor


async def test_a_status_post_from_the_home_network_is_an_interaction_and_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    assert hass.states.get(SENSOR).state == "unknown"

    with _from(TABLET):
        assert (await _post(client, secret, IN_USE, headers=AT_HOME)).status == 200
    await hass.async_block_till_done()
    first = hass.states.get(SENSOR)
    attrs = first.attributes
    assert dt_util.parse_datetime(first.state) == dt_util.utcnow().replace(second=0, microsecond=0)
    # Whose device it is, found by this attribute and never by its entity id
    assert attrs["person"] == "person.sam" and attrs["device_id"] == PHONE_ID
    assert attrs["kind"] == "last_interaction"
    assert attrs["local"] is True and attrs["last_interaction_local"] is True
    assert dt_util.parse_datetime(attrs["last_interaction"]) == dt_util.parse_datetime(first.state)
    assert attrs["last_post"] == attrs["last_interaction"]
    # A phone names no profile: who held it isn't known
    assert attrs["last_user"] is None

    freezer.tick(timedelta(minutes=5))
    with _from(TABLET):
        await _post(client, secret, {**IN_USE, "seconds_today": 1500}, headers=AT_HOME)
    await hass.async_block_till_done()
    later = hass.states.get(SENSOR)
    assert dt_util.parse_datetime(later.state) - dt_util.parse_datetime(first.state) == timedelta(minutes=5)


async def test_a_heartbeat_with_the_screen_off_is_a_post_but_no_interaction(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    day = dt_util.now().date().isoformat()
    with _from(TABLET):
        await _post(client, secret, {**IN_USE, "day": day}, headers=AT_HOME)
    await hass.async_block_till_done()
    used = hass.states.get(SENSOR).state

    freezer.tick(timedelta(minutes=10))
    # Not from the home network this time (a test's own connection is this machine's)
    await _post(client, secret, {**IN_USE, "screen": "off", "day": day})
    await hass.async_block_till_done()
    state = hass.states.get(SENSOR)
    assert state.state == used
    assert state.attributes["last_interaction_local"] is True
    assert state.attributes["local"] is False
    assert dt_util.parse_datetime(state.attributes["last_post"]) - dt_util.parse_datetime(used) == timedelta(minutes=10)

    # Time that grew with the screen already off again is use all the same
    freezer.tick(timedelta(minutes=10))
    await _post(client, secret, {**IN_USE, "screen": "off", "day": day, "seconds_today": 1260})
    await hass.async_block_till_done()
    state = hass.states.get(SENSOR)
    assert dt_util.parse_datetime(state.state) - dt_util.parse_datetime(used) == timedelta(minutes=20)
    assert state.attributes["last_interaction_local"] is False


async def test_it_is_kept_while_the_phone_is_quiet_and_across_a_reload(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    with _from(TABLET):
        await _post(client, secret, IN_USE, headers=AT_HOME)
    await hass.async_block_till_done()
    used = hass.states.get(SENSOR).state

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await entry.runtime_data.async_flush()
    freezer.tick(timedelta(hours=3))
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    state = hass.states.get(SENSOR)
    assert state.state == used
    assert state.attributes["local"] is True and state.attributes["person"] == "person.sam"


async def test_a_tv_has_no_last_interaction_sensor(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    await _post(client, secret, STATUS, TV_ID)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.kitchen_profile") is not None
    assert hass.states.get("sensor.kitchen_last_interaction") is None


# Local or not: anything unsure is not


async def _local_of(hass: HomeAssistant, client, secret: str, **kwargs) -> bool:
    assert (await _post(client, secret, IN_USE, **kwargs)).status == 200
    await hass.async_block_till_done()
    return hass.states.get(SENSOR).attributes["local"]


async def test_a_post_through_home_assistant_cloud_is_never_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    # Even when everything else looks like home
    with _from(TABLET), patch("custom_components.hearth.api._cloud_request", return_value=True):
        assert await _local_of(hass, client, secret, headers=AT_HOME) is False
    with _from(TABLET):
        assert await _local_of(hass, client, secret, headers=AT_HOME) is True


async def test_the_cloud_marker_is_home_assistant_s_own(hass: HomeAssistant) -> None:
    from hass_nabucasa import remote

    from custom_components.hearth.api import _cloud_request

    assert _cloud_request() is False
    token = remote.is_cloud_request.set(True)
    try:
        assert _cloud_request() is True
    finally:
        remote.is_cloud_request.reset(token)


@pytest.mark.parametrize(
    "header",
    ["Forwarded", "X-Forwarded-Host", "X-Forwarded-Proto", "X-Real-IP", "Via", "CF-Connecting-IP", "CF-Ray"],
)
async def test_a_post_a_proxy_or_tunnel_passed_on_is_never_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, header: str
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    with _from(TABLET):
        assert await _local_of(hass, client, secret, headers={**AT_HOME, header: "x"}) is False


@pytest.mark.parametrize(
    "peer",
    [
        None,  # not readable, or not the address Home Assistant goes by (a proxy's header replaced it)
        "127.0.0.1",  # this machine: a proxy or tunnel beside Home Assistant
        "::1",
        "172.30.33.4",  # an add-on (a proxy, a tunnel)
        "203.0.113.9",  # the internet, by a port forward
        "100.64.0.7",  # a VPN's or a carrier's shared range
        "not an address",
    ],
)
async def test_only_a_home_address_at_the_other_end_is_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, peer: str | None
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    with _from(peer):
        assert await _local_of(hass, client, secret, headers=AT_HOME) is False


@pytest.mark.parametrize(
    ("host", "local"),
    [
        ("10.0.0.5:8123", True),
        ("homeassistant.local:8123", True),
        ("homeassistant:8123", True),
        ("ha.home.example:8123", True),  # the internal URL
        ("home.example.org", False),  # the external URL
        ("other.example.net", False),  # some other public name (dynamic DNS)
        ("abcdef0123456789.ui.nabu.casa", False),
        ("203.0.113.9:8123", False),
    ],
)
async def test_the_public_url_is_never_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, host: str, local: bool
) -> None:
    """A router may hand a forwarded connection on as its own, so a home address at the other end isn't enough: the
    device must also have asked for a home address."""
    client, secret = await _phone(hass, hass_client_no_auth)
    hass.config.internal_url = "http://ha.home.example:8123"
    hass.config.external_url = "https://home.example.org"
    with _from(TABLET):
        assert await _local_of(hass, client, secret, headers={"Host": host}) is local


async def test_the_external_url_is_not_local_even_as_the_internal_one(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _phone(hass, hass_client_no_auth)
    hass.config.internal_url = hass.config.external_url = "https://home.example.org"
    with _from(TABLET):
        assert await _local_of(hass, client, secret, headers={"Host": "home.example.org"}) is False


async def test_a_post_through_a_trusted_reverse_proxy_is_never_local(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Home Assistant takes the forwarded address as the request's, so a tablet at home behind the proxy is answered;
    but the proxy also serves the public URL, so it isn't counted as at home."""
    assert await async_setup_component(
        hass, "http", {"http": {"use_x_forwarded_for": True, "trusted_proxies": ["127.0.0.1"]}}
    )
    client, secret = await _phone(hass, hass_client_no_auth)
    # No patch: the real connection, with the proxy's header
    assert await _local_of(hass, client, secret, headers={**AT_HOME, "X-Forwarded-For": TABLET}) is False
    used = hass.states.get(SENSOR).state

    # From outside through the proxy: refused as before, and nothing is noted
    response = await _post(client, secret, IN_USE, headers={"X-Forwarded-For": "203.0.113.9"})
    assert response.status == 403 and (await response.json())["error"] == "not_local"
    assert hass.states.get(SENSOR).state == used

    # The proxy's own address at the other end with no header (one that adds none) isn't local either
    with _from("10.0.0.9"), patch.object(hass.http, "trusted_proxies", [ip_network("10.0.0.9/32")]):
        assert await _local_of(hass, client, secret, headers=AT_HOME) is False


def test_which_addresses_are_the_home_network_s() -> None:
    from custom_components.hearth.api import _home_address

    for home in ("10.0.0.20", "192.168.1.20", "172.16.4.2", "169.254.3.4", "fd00::20", "fe80::1", "::ffff:10.0.0.20"):
        assert _home_address(home), home
    for other in ("127.0.0.1", "::1", "::ffff:127.0.0.1", "172.30.32.1", "198.51.100.7", "2001:db8::1", "", None):
        assert not _home_address(other), other


# hearth_tv_profile_changed


async def _tv(hass: HomeAssistant, hass_client_no_auth) -> tuple:
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "profiles": {"name:sam": "person.sam", "name:alex": "person.alex"}}
    )
    await hass.async_block_till_done()
    return entry, client, secret


async def _tv_post(hass: HomeAssistant, client, secret: str, body: dict) -> None:
    assert (await _post(client, secret, body, TV_ID)).status == 200
    await hass.async_block_till_done()


async def test_a_profile_switch_fires_the_event(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    area = ar.async_get(hass).async_create("Den")
    registry = dr.async_get(hass)
    device = registry.async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id)
    registry.async_update_device(device.id, area_id=area.id)
    await hass.async_block_till_done()
    events = async_capture_events(hass, EVENT)

    # The first report after a start says where the TV is, not that anyone switched
    await _tv_post(hass, client, secret, ALEX)
    assert events == []
    # The same profile again (a heartbeat, another app): nothing
    freezer.tick(timedelta(minutes=2))
    await _tv_post(hass, client, secret, {**ALEX, "app": "Example Music"})
    assert events == []

    freezer.tick(timedelta(minutes=2))
    await _tv_post(hass, client, secret, SAM)
    assert len(events) == 1
    assert events[0].data == {
        "device": TV_ID,
        "name": "Kitchen",
        "area_id": area.id,
        "ha_device_id": device.id,
        "profile_ref": "name:sam",
        "profile_id": "user:10",
        "kids_profile": True,
        "person": "person.sam",
        "from_profile_ref": "name:alex",
        "from_profile_id": "user:0",
        "from_person": "person.alex",
        "at": dt_util.now().isoformat(),
    }

    # A post that names no profile (the chooser in front) changes nothing, either way
    await _tv_post(hass, client, secret, {**SAM, "profile": None, "profile_id": None, "profile_ref": None})
    await _tv_post(hass, client, secret, SAM)
    assert len(events) == 1
    # And back
    await _tv_post(hass, client, secret, ALEX)
    assert len(events) == 2
    assert events[1].data["profile_ref"] == "name:alex" and events[1].data["from_profile_ref"] == "name:sam"
    assert events[1].data["kids_profile"] is False and events[1].data["person"] == "person.alex"


async def test_no_event_for_the_first_report_after_a_reload_or_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT)
    await _tv_post(hass, client, secret, ALEX)
    await entry.runtime_data.async_flush()

    # The household loads again with Alex's profile restored; the TV was switched meanwhile
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.kitchen_profile").attributes["profile_ref"] == "name:alex"
    await _tv_post(hass, client, secret, SAM)
    assert events == []

    # From here on both sides are live reports
    await _tv_post(hass, client, secret, ALEX)
    assert [e.data["from_profile_ref"] for e in events] == ["name:sam"]


async def test_no_event_when_the_tv_comes_back_in_another_profile(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT)
    await _tv_post(hass, client, secret, ALEX)

    # Off, or off the network, past the time it counts as connected
    freezer.tick(timedelta(minutes=16))
    await _tv_post(hass, client, secret, SAM)
    assert events == []
    freezer.tick(timedelta(minutes=2))
    await _tv_post(hass, client, secret, ALEX)
    assert len(events) == 1


async def test_a_ref_learned_later_or_a_renamed_profile_is_no_switch(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    events = async_capture_events(hass, EVENT)
    await _tv_post(hass, client, secret, {**SAM, "profile_ref": None})
    await _tv_post(hass, client, secret, SAM)
    await _tv_post(hass, client, secret, {**SAM, "profile": "Sammy", "profile_ref": "name:sammy"})
    assert events == []

    # An older TV that sends no refs still tells a switch, by its own keys
    await _tv_post(hass, client, secret, {**ALEX, "profile_ref": None})
    assert len(events) == 1
    assert events[0].data["profile_ref"] is None and events[0].data["profile_id"] == "user:0"
    assert events[0].data["from_profile_ref"] == "name:sammy" and events[0].data["from_profile_id"] == "user:10"
    # Mapped by ref only, and it sent none: not known
    assert events[0].data["person"] is None
