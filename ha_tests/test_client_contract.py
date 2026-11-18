"""Contract 3, the generic client contract: a device's client (locked at pairing) and its checks, the never-paused
exemption, PIN grants, client settings, share_app_data, and catalog_categories no longer read."""

import json
from datetime import timedelta
from pathlib import Path

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.__init__ import share_app_data_retired
from custom_components.hearth.client import clean_checks, clean_client, device_contract
from custom_components.hearth.client_settings import (
    ADULT,
    ADULT_DEVICE,
    KID_DEVICE,
    MAX_CLIENT_BYTES,
    MAX_DATA_BYTES,
    MAX_DOCS,
    TV_DEVICE,
    may_read,
    parse_scope,
    write_access,
)
from custom_components.hearth.const import DOMAIN

from test_bedtime_lift import _bonus as _bonus_at_bedtime, _sam as _sam_at_bedtime
from test_init import NONCE, _post, _set_up, _video_apps
from test_parent_pin import _adults
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option
from test_time_model import _call, _set

LAUNCHER = "com.example.launcher"
DIALER = "com.example.launcher.phone"
CLIENT = {"id": LAUNCHER, "version": "1.4.2", "contract": 3, "companions": [DIALER]}
SAM_PHONE = "phone-sam-0123456789"
ALEX_PHONE = "phone-alex-012345678"
FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
PIN = "4826"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


# The client and its checks


def test_a_client_names_only_its_own_family() -> None:
    assert clean_client(CLIENT) == {"id": LAUNCHER, "version": "1.4.2", "contract": 3, "companions": [DIALER]}
    assert clean_client({"id": LAUNCHER}) == {"id": LAUNCHER, "version": None, "contract": None, "companions": []}
    # A companion outside the id's family, or a bare prefix match, or too many: not a client
    assert clean_client({"id": LAUNCHER, "companions": ["com.example.game"]}) is None
    assert clean_client({"id": LAUNCHER, "companions": ["com.example.launcherx"]}) is None
    assert clean_client({"id": LAUNCHER, "companions": [f"{LAUNCHER}.p{n}" for n in range(5)]}) is None
    for bad in (None, "x", {"id": "launcher"}, {"id": "a." + "b" * 130}, {"id": "com.example/launcher"}):
        assert clean_client(bad) is None


def test_a_device_s_contract_is_the_highest_it_spoke() -> None:
    """Contract 4 decides whether a TV is sent parent PIN hashes (household.py): the pairing's contract or the
    status's, whichever is higher, so a post can't name an older one to get them."""
    pinned = {"client": {"id": LAUNCHER, "contract": 4}}
    assert device_contract(pinned, {"client": {"id": LAUNCHER, "contract": 3}}) == 4
    assert device_contract({"client": {"id": LAUNCHER, "contract": 3}}, {"client": {"id": LAUNCHER, "contract": 4}}) == 4
    assert device_contract({}, {"client": {"id": LAUNCHER, "contract": None}}) == 0
    assert device_contract({}, None) == 0
    assert device_contract({"client": None}, {}) == 0


def test_checks_are_kept_as_given_within_limits() -> None:
    checks = clean_checks(
        [
            {"id": "home_app", "ok": True, "label": "Home app"},
            {"id": "home_app", "ok": False},  # once
            {"id": "Bad-Id", "ok": True},
            {"id": "hearth_client", "ok": True},  # Hearth's own
            {"id": "notify", "ok": "yes"},
            {"id": "notify", "ok": False, "label": "x" * 60},
        ]
        + [{"id": f"c{n}", "ok": True} for n in range(20)]
    )
    assert checks[0] == {"id": "home_app", "ok": True, "label": "Home app"}
    assert checks[1] == {"id": "notify", "ok": False, "label": "x" * 40}
    assert len(checks) <= 10
    assert clean_checks("nope") is None


# Pairing and status


async def _pair_phone(hass, client, device_id: str, person: str, body_client=CLIENT) -> str:
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    body = {"device_id": device_id, "kind": "mobile", "name": f"{person} phone", "nonce": NONCE}
    if body_client is not None:
        body["client"] = body_client
    response = await client.post("/api/hearth/pair", json=body)
    assert response.status == 200
    pairing_id = (await response.json())["pairing_id"]
    await hass.async_block_till_done()
    flow = next(
        f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN)
        if f["context"].get("title_placeholders", {}).get("name") == f"{person} phone"
    )
    shown = hass.config_entries.flow.async_get(flow["flow_id"])
    result = await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": person})
    assert result["reason"] == "paired", shown
    await hass.async_block_till_done()
    answer = await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json()
    assert answer["status"] == "approved"
    assert answer["contract"] == 4
    return answer["secret"]


async def _household(hass: HomeAssistant, hass_client_no_auth):
    """Sam (a kid) with a phone running the launcher, Alex (an adult, with a Parent PIN) with one too."""
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    entry = await _set_up(hass)
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {"person.sam": "kid"}})
    await hass.async_block_till_done()
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})
    client = await hass_client_no_auth()
    sam = await _pair_phone(hass, client, SAM_PHONE, "person.sam")
    alex = await _pair_phone(hass, client, ALEX_PHONE, "person.alex")
    # Each phone's first post after pairing: nothing counted yet today (what came before pairing never counts)
    await _status(client, sam, seconds_today=0, app_seconds_today={})
    await _status(client, alex, device_id=ALEX_PHONE, seconds_today=0, app_seconds_today={})
    return entry, client, sam, alex


def _phone_status(**extra):
    return {
        "screen": "on",
        "day": dt_util.now().date().isoformat(),
        "seconds_today": 1200,
        "app_seconds_today": {"com.example.tube": 600, LAUNCHER: 300, DIALER: 300},
        "app_categories": {"com.example.tube": "video", LAUNCHER: "video", DIALER: "video"},
        "client": CLIENT,
        **extra,
    }


async def _status(http, secret, device_id=SAM_PHONE, **extra):
    response = await http.post(
        f"/api/hearth/device/{device_id}/status", json=_phone_status(**extra), headers={"X-Hearth-Secret": secret}
    )
    assert response.status == 200
    return await response.json()


async def test_the_client_is_locked_at_pairing(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    devices = entry.data["devices"]
    assert devices[SAM_PHONE]["client"] == {"id": LAUNCHER, "companions": [DIALER]}

    # A client that names something outside its family is refused at pairing
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    bad = await client.post(
        "/api/hearth/pair",
        json={"device_id": "phone-bad-0123456789", "kind": "mobile", "nonce": NONCE,
              "client": {"id": LAUNCHER, "companions": ["com.example.game"]}},
    )
    assert bad.status == 400

    # The adult saw it while approving
    from custom_components.hearth.config_flow import client_line

    assert client_line({"id": LAUNCHER, "companions": [DIALER]}) == f"App: **{LAUNCHER}** (and {DIALER}). "
    assert client_line(None) == ""


async def test_another_client_later_raises_a_check_and_changes_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    failed = async_capture_events(hass, "hearth_device_check_failed")
    await _status(client, sam, checks=[{"id": "home_app", "ok": True, "label": "Home app"}])
    await hass.async_block_till_done()
    assert failed == []

    hub = entry.runtime_data
    await _status(client, sam, client={"id": "com.example.game"}, checks=[{"id": "home_app", "ok": False, "label": "Home app"}])
    await hass.async_block_till_done()
    assert sorted(e.data["check"] for e in failed) == ["hearth_client", "home_app"]
    assert {c["id"]: c["ok"] for c in hub.checks(SAM_PHONE)} == {"home_app": False, "hearth_client": False}
    # Still the client it paired with
    assert entry.data["devices"][SAM_PHONE]["client"]["id"] == LAUNCHER
    assert "com.example.game" not in hub.household.client_exempt()("person.sam")

    # Told once, not on every post
    await _status(client, sam, client={"id": "com.example.game"})
    await hass.async_block_till_done()
    assert len(failed) == 2


# Never paused


async def test_a_paired_client_is_never_paused_for_its_person(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _status(client, sam)
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 1}, blocking=True
    )
    await hass.async_block_till_done()
    assert paused
    held = set(paused[-1].data["packages"])
    assert "com.example.tube" in held
    assert LAUNCHER not in held and DIALER not in held
    # Only for Sam: nobody else's exemption
    assert entry.runtime_data.household.client_exempt()("person.alex") == {LAUNCHER, DIALER}

    # A kid's device writing its own device documents never changes what's held
    response = await client.put(
        f"/api/hearth/device/{SAM_PHONE}/settings/device:{SAM_PHONE}/layout",
        json={"schema": "example.layout/1", "data": {"hide": ["com.example.tube"], "pause": False}},
        headers={"X-Hearth-Secret": sam},
    )
    assert response.status == 200
    await _status(client, sam)
    await hass.async_block_till_done()
    wanted = entry.runtime_data.household.enforcement._wanted
    assert set(wanted["family_link|person.sam"]) == held

    # The household puts the launcher in a pool: it's held like any app (its companion still isn't)
    await _video_apps(hass, [LAUNCHER])
    await _status(client, sam)
    await hass.async_block_till_done()
    wanted = entry.runtime_data.household.enforcement._wanted
    assert LAUNCHER in wanted["family_link|person.sam"] and DIALER not in wanted["family_link|person.sam"]


async def test_the_launcher_literal_is_transitional_only() -> None:
    # Kept only until phones have re-paired with contract 3; nothing else rides on the transition list
    assert enforce.TRANSITION_CLIENTS == {"com.thesiegs.glint", "com.thesiegs.glint.phone"}
    assert enforce.TRANSITION_CLIENTS <= enforce.ESSENTIAL and enforce.TRANSITION_CLIENTS <= enforce.NEVER_PAUSED
    for kept in ("com.thesiegs.hearth", "com.thesiegs.hearth.mobile", "com.thesiegs.hearthtube.mobile",
                 "com.google.android.apps.kids.familylink"):
        assert enforce.essential(kept)


# Who may write and read client settings


def test_the_permission_table() -> None:
    household, sam, alex = ("household", None), ("person", "person.sam"), ("person", "person.alex")
    own, other = ("device", "phone-1"), ("device", "phone-2")

    def access(writer, scope, person="person.sam"):
        return write_access(writer, scope, person=person, device="phone-1")

    # An adult in Home Assistant: everything
    for scope in (household, sam, own, other):
        assert access(ADULT, scope) == ("adult", False)
    # An adult's device: household and every person; only its own device
    assert access(ADULT_DEVICE, household, "person.alex") == ("adult", False)
    assert access(ADULT_DEVICE, sam, "person.alex") == ("adult", False)
    assert access(ADULT_DEVICE, own, "person.alex") == ("adult", False)
    assert access(ADULT_DEVICE, other, "person.alex") == (None, False)
    # A kid's device: never household (no grant helps), its own person only with a grant, its own device alone
    assert access(KID_DEVICE, household) == (None, False)
    assert access(KID_DEVICE, sam) == (None, True)
    assert access(KID_DEVICE, alex) == (None, False)
    assert access(KID_DEVICE, sam, person=None) == (None, False)
    assert access(KID_DEVICE, own) == ("kid_device", False)
    assert access(KID_DEVICE, other) == (None, False)
    # A TV: its own device alone, household and person with a grant
    assert access(TV_DEVICE, own, None) == ("device", False)
    assert access(TV_DEVICE, household, None) == (None, True)
    assert access(TV_DEVICE, sam, None) == (None, True)

    assert may_read(KID_DEVICE, household, person="person.sam", device="phone-1")
    assert may_read(KID_DEVICE, sam, person="person.sam", device="phone-1")
    assert not may_read(KID_DEVICE, alex, person="person.sam", device="phone-1")
    assert not may_read(KID_DEVICE, other, person="person.sam", device="phone-1")
    assert may_read(ADULT_DEVICE, sam, person="person.alex", device="phone-1")
    assert may_read(TV_DEVICE, sam, device="tv-1", people={"person.sam"})
    assert not may_read(TV_DEVICE, alex, device="tv-1", people={"person.sam"})

    assert parse_scope("person:person.sam") == sam
    for bad in ("person:sam", "device:x", "everyone", "household:x", None):
        assert parse_scope(bad) is None


def _url(device_id: str, scope: str, name: str) -> str:
    return f"/api/hearth/device/{device_id}/settings/{scope}/{name}"


async def _put(client, secret, scope, name, data=None, device_id=SAM_PHONE, **extra):
    return await client.put(
        _url(device_id, scope, name),
        json={"schema": "example.kids/2", "data": data if data is not None else {"tier": 1}, **extra},
        headers={"X-Hearth-Secret": secret},
    )


async def _grant(client, secret, device_id=SAM_PHONE) -> str:
    answer = await (
        await client.post(f"/api/hearth/device/{device_id}/verify_pin", json={"pin": PIN}, headers={"X-Hearth-Secret": secret})
    ).json()
    assert answer["ok"] is True
    return answer["grant"]


async def test_a_kid_s_device_needs_a_grant_for_its_person(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    entry, client, sam, alex = await _household(hass, hass_client_no_auth)
    changed = async_capture_events(hass, "hearth_client_settings_changed")

    # Its own device: no PIN needed
    response = await _put(client, sam, f"device:{SAM_PHONE}", "layout")
    assert response.status == 200 and (await response.json())["updated_by"] == "kid_device"
    # Its person, household, another device: refused without a grant
    assert (await _put(client, sam, "person:person.sam", "kids")).status == 403
    assert (await _put(client, sam, "household", "kids")).status == 403
    assert (await _put(client, sam, f"device:{ALEX_PHONE}", "layout")).status == 403

    grant = await _grant(client, sam)
    response = await _put(client, sam, "person:person.sam", "kids", grant=grant)
    assert response.status == 200 and (await response.json())["updated_by"] == "pin"
    doc = await (await client.get(_url(SAM_PHONE, "person:person.sam", "kids"), headers={"X-Hearth-Secret": sam})).json()
    assert doc["updated_by"] == "pin" and doc["format"] == "hearth.client-settings/1" and doc["client"] == LAUNCHER
    # Never household, not with a grant; never another person
    assert (await _put(client, sam, "household", "kids", grant=grant)).status == 403
    assert (await _put(client, sam, "person:person.alex", "kids", grant=grant)).status == 403
    # Another device's grant is no good here
    alex_grant = await _grant(client, alex, ALEX_PHONE)
    assert (await _put(client, sam, "person:person.sam", "rules", grant=alex_grant)).status == 403
    # Eight writes at most (one spent above)
    for n in range(7):
        assert (await _put(client, sam, "person:person.sam", f"n{n}", grant=grant)).status == 200
    assert (await _put(client, sam, "person:person.sam", "more", grant=grant)).status == 403
    # Two minutes at most
    grant = await _grant(client, sam)
    freezer.tick(timedelta(seconds=121))
    assert (await _put(client, sam, "person:person.sam", "late", grant=grant)).status == 403

    # Reads: household and its own person and device; never another person's
    assert (await client.get(_url(SAM_PHONE, "person:person.alex", "kids"), headers={"X-Hearth-Secret": sam})).status == 403
    assert (await client.get(_url(SAM_PHONE, "household", "none"), headers={"X-Hearth-Secret": sam})).status == 404
    await hass.async_block_till_done()
    assert {"client": LAUNCHER, "scope": "person:person.sam", "name": "kids"} in [e.data for e in changed]
    assert all("data" not in e.data for e in changed)


async def test_an_adult_s_device_writes_household_and_person(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, sam, alex = await _household(hass, hass_client_no_auth)
    for scope in ("household", "person:person.sam", f"device:{ALEX_PHONE}"):
        response = await _put(client, alex, scope, "kids", device_id=ALEX_PHONE)
        assert response.status == 200 and (await response.json())["updated_by"] == "adult"
    assert (await _put(client, alex, f"device:{SAM_PHONE}", "kids", device_id=ALEX_PHONE)).status == 403


async def test_limits_etags_and_the_state_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, sam, alex = await _household(hass, hass_client_no_auth)
    own = f"device:{SAM_PHONE}"
    before = (await _status(client, sam))["state"]
    assert before["client_settings"] == {}

    # A kid's own device documents, up to the cap and no further
    big = {"blob": "x" * (MAX_DATA_BYTES - 20)}
    assert (await _put(client, sam, own, "big", big)).status == 200
    too_big = await _put(client, sam, own, "bigger", {"blob": "x" * MAX_DATA_BYTES})
    assert too_big.status == 413 and (await too_big.json())["error"] == "too_large"
    for n in range(MAX_DOCS - 1):
        assert (await _put(client, sam, own, f"d{n}")).status == 200
    many = await _put(client, sam, own, "one-more")
    assert many.status == 413 and (await many.json())["error"] == "too_many"
    # Replacing one at the cap is fine
    first = await (await _put(client, sam, own, "d0", {"tier": 2})).json()

    # Optimistic: a stale etag is refused with the current one
    stale = await _put(client, sam, own, "d0", {"tier": 3}, if_etag="0000")
    assert stale.status == 409 and (await stale.json())["etag"] == first["etag"]
    assert (await _put(client, sam, own, "d0", {"tier": 3}, if_etag=first["etag"])).status == 200
    assert (await _put(client, sam, own, "d0", if_etag=None)).status == 409  # null: only when there's none yet

    # The state document carries the etags it may read, and its version changed with them
    after = (await _status(client, sam))["state"]
    assert f"{own}/d0" in after["client_settings"] and after["version"] != before["version"]
    assert not any(k.startswith(f"device:{ALEX_PHONE}") for k in after["client_settings"])

    # A label is kept, control characters stripped; over 40 is refused
    labelled = await _put(client, alex, "household", "rules", device_id=ALEX_PHONE, label="Example \x07rules")
    assert labelled.status == 200
    doc = entry.runtime_data.client_settings.get(LAUNCHER, ("household", None), "rules")
    assert doc["label"] == "Example rules"
    assert (await _put(client, alex, "household", "rules", device_id=ALEX_PHONE, label="x" * 41)).status == 400
    summary = entry.runtime_data.client_settings.summary()[LAUNCHER]
    assert "Example rules" in summary["labels"] and f"{LAUNCHER} · big" in summary["labels"]

    # Removing the device deletes its device documents; the household's stay
    await entry.runtime_data.async_remove_device(SAM_PHONE)
    assert not any(d["scope"] == own for d in entry.runtime_data.client_settings.listing())
    assert entry.runtime_data.client_settings.get(LAUNCHER, ("household", None), "rules") is not None


def test_the_caps_are_as_the_contract_says() -> None:
    assert (MAX_DATA_BYTES, MAX_DOCS, MAX_CLIENT_BYTES) == (65536, 16, 1048576)


async def test_a_device_paired_without_a_client_keeps_none(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair_phone(hass, client, SAM_PHONE, "person.sam", body_client=None)
    state = (await _status(client, secret))["state"]
    assert "client_settings" not in state
    assert (await _put(client, secret, f"device:{SAM_PHONE}", "layout")).status == 403
    # Reporting a client later doesn't lock one or exempt it: pairing again does
    assert "client" not in entry.data["devices"][SAM_PHONE]
    assert entry.runtime_data.household.client_exempt()("person.sam") == set()


# The WebSocket


async def test_adults_read_and_write_on_the_websocket(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    entry, client, sam, alex = await _household(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/client_settings/subscribe", "client": LAUNCHER, "person": "person.sam"})
    assert (await ws.receive_json())["success"]

    await ws.send_json({"id": 2, "type": "hearth/client_settings/set", "client": LAUNCHER, "scope": "person:person.sam",
                        "name": "notification-rules", "schema": "example.rules/1", "data": {"hide": []},
                        "label": "Example rules"})
    # The change is told as it happens, so its event may come before the answer
    got = {m["id"]: m for m in [await ws.receive_json(), await ws.receive_json()]}
    set_answer, event = got[2], got[1]
    assert set_answer["success"] and set_answer["result"]["updated_by"] == "adult"
    assert event["event"] == {
        "client": LAUNCHER, "scope": "person:person.sam", "name": "notification-rules", "etag": set_answer["result"]["etag"]
    }

    # Alex's person documents aren't Sam's; Sam's phone's device documents are
    await ws.send_json({"id": 3, "type": "hearth/client_settings/set", "client": LAUNCHER, "scope": "person:person.alex",
                        "name": "kids", "schema": "example.kids/2", "data": {}})
    assert (await ws.receive_json())["success"]
    assert (await _put(client, sam, f"device:{SAM_PHONE}", "candidates")).status == 200
    event = await ws.receive_json()
    assert event["id"] == 1 and event["event"]["scope"] == f"device:{SAM_PHONE}"

    await ws.send_json({"id": 4, "type": "hearth/client_settings/get", "client": LAUNCHER, "scope": "person:person.sam",
                        "name": "notification-rules"})
    assert (await ws.receive_json())["result"]["data"] == {"hide": []}
    await ws.send_json({"id": 5, "type": "hearth/client_settings/list"})
    listed = (await ws.receive_json())["result"]["documents"]
    assert len(listed) == 3 and all("data" not in d for d in listed)
    await ws.send_json({"id": 6, "type": "hearth/client_settings/clear", "client": LAUNCHER})
    # Sam's two documents going are told to the subscription; Alex's isn't
    got = [await ws.receive_json() for _ in range(3)]
    assert next(m for m in got if m["id"] == 6)["result"] == {"removed": 3}
    assert sorted(m["event"]["scope"] for m in got if m["id"] == 1) == ["device:" + SAM_PHONE, "person:person.sam"]
    assert all(m["event"]["etag"] is None for m in got if m["id"] == 1)

    # Someone who isn't an adult
    hass_admin_user.groups = []
    await ws.send_json({"id": 7, "type": "hearth/client_settings/list"})
    assert not (await ws.receive_json())["success"]


# share_app_data and catalog_categories


def test_share_app_data_is_retired() -> None:
    assert share_app_data_retired({"roles": {}}) is None
    assert share_app_data_retired({"share_app_data": ["person.a"], "roles": {}}) == {"roles": {}}
    assert share_app_data_retired({"tile_exchange_share": ["person.b"], "roles": {}}) == {"roles": {}}


async def test_the_sharing_options_go_at_load(hass: HomeAssistant) -> None:
    entry = await _set_up(hass)
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "tile_exchange_share": ["person.sam"], "share_app_data": ["person.sam"]}
    )
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert "share_app_data" not in entry.options
    assert "tile_exchange_share" not in entry.options


async def test_catalog_categories_are_no_longer_read(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    await _status(client, sam, catalog_categories={"com.example.newgame": "game"},
                  app_seconds_today={"com.example.newgame": 60})
    hub = entry.runtime_data
    assert "catalog_categories" not in hub.state(SAM_PHONE).status
    assert hub.household.placement()("com.example.newgame").why != "declared"


def test_a_build_suffix_family_names_its_companions_with_the_same_suffix() -> None:
    from custom_components.hearth.client import in_family

    assert in_family("com.example.launcher.debug", "com.example.launcher.phone.debug")
    assert in_family("com.example.launcher.nightly", "com.example.launcher.phone.nightly")
    assert in_family("com.example.launcher", "com.example.launcher.phone")
    # Not another suffix, not a different base, not a bare suffix
    assert not in_family("com.example.launcher.debug", "com.example.launcher.phone.nightly")
    assert not in_family("com.example.launcher.debug", "com.example.other.debug")
    assert not in_family("com.example.launcher.beta", "com.example.launcher.phone.beta")
    assert not in_family("com.example.launcher", "com.example.game")
    assert in_family("com.example.launcher.debug", "com.example.launcher.debug.x")


# System screens and the time from before pairing

PIXEL_HOME = "com.google.android.apps.nexuslauncher"
LOCK_SCREEN = "com.google.android.gms.supervision"


def _minutes_today(hass: HomeAssistant) -> str:
    return hass.states.get("sensor.hearth_sam_screen_time_today").state


async def test_system_screens_are_never_screen_time_nor_paused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """A phone that says its home screen was in front all night: those 22 hours are no one's screen time."""
    paused = async_mock_service(hass, "familylink", "pause_app")
    async_mock_service(hass, "familylink", "resume_app")
    async_mock_service(hass, "familylink", "set_daily_limit")
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "all", "minutes": 120}, blocking=True
    )
    await _status(
        client,
        sam,
        seconds_today=22 * 3600 + 900,
        app_seconds_today={PIXEL_HOME: 22 * 3600, LOCK_SCREEN: 300, "com.example.tube": 600},
        app_categories={PIXEL_HOME: "video", "com.example.tube": "video"},
    )
    await hass.async_block_till_done()
    # The device's total is its kept apps' sum: 10 minutes, so All screen time has 110 left and nothing is locked
    household = entry.runtime_data.household
    assert _minutes_today(hass) == "10"
    assert household.days["person.sam"].limits["all"].minutes_left == 110
    assert household.placement()(PIXEL_HOME).pool == "interface"
    # A device's own category doesn't take it out of System screens
    assert household.membership()(PIXEL_HOME) == {"all", "interface"}

    # Never paused either, whatever runs out
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 1}, blocking=True
    )
    await hass.async_block_till_done()
    held = set(paused[-1].data["packages"])
    assert "com.example.tube" in held and PIXEL_HOME not in held and LOCK_SCREEN not in held

    # An adult's move puts an app there too
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "app_groups": {"com.example.tube": "interface"}}
    )
    await hass.async_block_till_done()
    await _status(client, sam, seconds_today=600, app_seconds_today={"com.example.tube": 600})
    await hass.async_block_till_done()
    assert entry.runtime_data.household.days["person.sam"].groups["all"] == 0


def test_only_a_list_puts_an_app_in_system_screens() -> None:
    """Not another answer of what the app is, not a device's category, not an adult's map of a whole kind of app."""
    from custom_components.hearth.limits import groups_from_options, placer, pool_map

    groups = groups_from_options({})
    assert pool_map(groups, {"system": "interface"})["system"] == "other"

    class Hit:
        confirmed = True
        detail = "system"
        category = "productivity"
        value = "system"

    place = placer(
        groups,
        {"com.example.tool": "productivity"},
        lookup=lambda item: Hit(),
        pools={"system": "interface", "productivity": "interface"},
    )
    assert place("com.example.tool").pool is None
    assert (place(PIXEL_HOME).pool, place(PIXEL_HOME).why) == ("interface", "starter")
    moved = placer(groups, {}, {"com.example.tool": "interface"})
    assert moved("com.example.tool").pool == "interface"


async def test_time_from_before_pairing_doesn_t_count_that_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """The first post after pairing carries the day so far: it's the baseline, taken off the rest of the day, after a
    restart too. Pairing again takes a new one."""
    entry, client, sam, _alex = await _household(hass, hass_client_no_auth)
    # Pairing again counts as newly paired
    sam = await _pair_phone(hass, client, SAM_PHONE, "person.sam")
    await _status(client, sam, seconds_today=3000, app_seconds_today={"com.example.tube": 3000})
    await hass.async_block_till_done()
    assert _minutes_today(hass) == "0"

    apps = {"com.example.tube": 3600, "com.example.game": 120}
    await _status(client, sam, seconds_today=3720, app_seconds_today=apps)
    await hass.async_block_till_done()
    assert _minutes_today(hass) == "12"

    # Kept over a restart
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    hub = entry.runtime_data
    assert hub.state(SAM_PHONE).baseline["apps"] == {"com.example.tube": 3000}
    apps = {"com.example.tube": 3660, "com.example.game": 120}
    await _status(client, sam, seconds_today=3780, app_seconds_today=apps)
    await hass.async_block_till_done()
    assert _minutes_today(hass) == "13"

    # Another day's counts are its own
    tomorrow = (dt_util.now().date() + timedelta(days=1)).isoformat()
    reading = hub.household._device_reading(
        SAM_PHONE, {"day": tomorrow, "seconds_today": 600, "app_seconds_today": {"com.example.tube": 600}}
    )
    assert reading.total_s == 600 and reading.items == {"com.example.tube": 600}


# The state document a TV holds by, against the fixture the TV's own tests read (TvStateDocumentFixtureTest): each
# moment is built here as Home Assistant sends it, and must still say what the fixture says


FIXTURE = json.loads((Path(__file__).parent / "contract_fixtures" / "tv_state_document.json").read_text("utf-8"))


def _fits(want, got, path: str = "") -> None:
    """[got] (Home Assistant's) says at least what [want] (the fixture) says: each key of a mapping, a list of mappings
    with ids by the same ids, a list of strings as a part of it, a time as a time, anything else as written."""
    if isinstance(want, dict):
        assert isinstance(got, dict), f"{path}: {got!r} is no mapping"
        for key, value in want.items():
            assert key in got, f"{path}.{key} is no longer sent"
            _fits(value, got[key], f"{path}.{key}")
    elif isinstance(want, list) and any(isinstance(item, dict) for item in want):
        assert isinstance(got, list), f"{path}: {got!r} is no list"
        by_id = {item.get("id"): item for item in got if isinstance(item, dict)}
        assert sorted(by_id) == sorted(item["id"] for item in want), f"{path}: ids {sorted(by_id)}"
        for item in want:
            _fits(item, by_id[item["id"]], f"{path}[{item['id']}]")
    elif isinstance(want, list):
        assert isinstance(got, list) and set(want) <= set(got), f"{path}: {set(want) - set(got or [])} missing"
    elif isinstance(want, str) and len(want) >= 19 and want[10:11] == "T" and dt_util.parse_datetime(want):
        assert isinstance(got, str) and dt_util.parse_datetime(got), f"{path}: {got!r} is no time"
    else:
        assert type(got) is type(want) and got == want, f"{path}: {got!r}, the fixture says {want!r}"


async def _tv_document(client, secret) -> dict:
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    return body["state"]["profiles"][KID]


async def test_the_tv_document_in_the_evening(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """8 PM: Daily time and Video left, bedtime next at 9:30 PM, the weekly schedule's wake time."""
    client, secret, _set_bedtime = await _sam_at_bedtime(hass, hass_client_no_auth, freezer, 20, 0)
    await _set(hass, "video", 30)
    _fits(FIXTURE["moments"]["evening"], await _tv_document(client, secret))


async def test_the_tv_document_at_bedtime(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, _set_bedtime = await _sam_at_bedtime(hass, hass_client_no_auth, freezer, 21, 45)
    _fits(FIXTURE["moments"]["bedtime"], await _tv_document(client, secret))


async def test_the_tv_document_with_bedtime_lifted(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """30 minutes of extra time at 9:45 PM: no lock, bedtime_lifted until 10:15 PM, and no next_lock for it."""
    client, secret, _set_bedtime = await _sam_at_bedtime(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus_at_bedtime(hass, 30)
    document = await _tv_document(client, secret)
    _fits(FIXTURE["moments"]["lifted"], document)
    assert "lock" not in document


async def test_the_tv_document_while_paused(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 45, "reason": "Dinner"}, blocking=True)
    _fits(FIXTURE["moments"]["paused"], await _tv_document(client, secret))


async def test_the_tv_document_with_youtube_allowed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Daily time used up, then a Video bonus: Video is left out and its apps are Daily time's exceptions."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 15)
    await _set(hass, "video", 10)
    await _call(hass, "add_time", {"person": "person.sam", "minutes": 15, "category": "video"})
    _fits(FIXTURE["moments"]["allowed"], await _tv_document(client, secret))


def test_the_fixture_check_catches_a_change() -> None:
    evening = FIXTURE["moments"]["evening"]
    for changed in (
        {**evening, "groups": evening["groups"][:1]},
        {**evening, "next_lock": {**evening["next_lock"], "kind": "school_time"}},
        {**evening, "next_lock": {**evening["next_lock"], "at": "9:30 PM"}},
        {key: value for key, value in evening.items() if key != "schedule"},
    ):
        with pytest.raises(AssertionError):
            _fits(evening, changed)
    _fits(evening, json.loads(json.dumps(evening)))
