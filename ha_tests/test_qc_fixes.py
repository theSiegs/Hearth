"""Fixes from a QC run of a phone client against a test Home Assistant: who a pause holds, grants that ended, a device
whose clock moved, the clock app, a mode until tomorrow morning, and pairing a phone without an administrator beside
you."""

from datetime import timedelta

from unittest.mock import patch

import pytest

from homeassistant.components import persistent_notification
from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import SYSTEM_NEVER_PAUSED, school_pausable
from custom_components.hearth.glance import household_glance
from custom_components.hearth.pause import pause_of

from test_client_contract import SAM_PHONE, _household as _phones_household, _phone_status
from test_init import NONCE, _set_up
from test_parent_pin import _adults
from test_people import _household_with_sam
from test_phones import _companion_app
from test_time_model import _call, _end

SAM = "person.sam"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


# 1. Pause everyone is every kid; adults are never paused


async def test_pause_everyone_pauses_the_kids_and_never_an_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _phones_household(hass, hass_client_no_auth)
    answer = await hass.services.async_call(DOMAIN, "pause", {"minutes": 30}, blocking=True, return_response=True)
    assert answer["paused"] == [SAM] and "not_paused" not in answer
    assert pause_of(hass, SAM) is not None
    assert pause_of(hass, "person.alex") is None

    # An adult named is left out, and the answer says so
    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True)
    answer = await hass.services.async_call(
        DOMAIN, "pause", {"minutes": 30, "people": ["person.alex", SAM]}, blocking=True, return_response=True
    )
    assert answer["paused"] == [SAM] and answer["not_paused"] == ["person.alex"]
    assert pause_of(hass, "person.alex") is None
    # Only adults: refused, nothing paused
    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True)
    with pytest.raises(ServiceValidationError, match="Adults aren't paused"):
        await hass.services.async_call(DOMAIN, "pause", {"minutes": 30, "people": ["person.alex"]}, blocking=True)
    assert pause_of(hass, "person.alex") is None and pause_of(hass, SAM) is None

    # Every kid paused reads as everyone, whatever the adults
    until = (dt_util.now() + timedelta(minutes=30)).isoformat()
    people = [
        {"id": SAM, "name": "Sam", "kind": "kid", "pause": {"until": until}},
        {"id": "person.alex", "name": "Alex", "kind": "adult"},
    ]
    assert household_glance(people, [])["headline"]["text"].startswith("everyone paused")


# 2-4. A grant ended stays ended, says so, and a status line points at what's still on


async def test_an_ended_bonus_never_takes_again_and_says_who_ended_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": hass_admin_user.id})
    household = _hub(hass).household
    first = (await _call(hass, "add_time", {"person": SAM, "minutes": 15}))["origin_id"]
    assert (await _call(hass, "end_grant", {"origin_id": first}, hass_admin_user))["taken"] == 15
    with pytest.raises(ServiceValidationError, match="Nothing of it is left to end"):
        await _end(hass, first)
    # More bonus after it: the ended one stays ended and takes nothing from the newer
    second = (await _call(hass, "add_time", {"person": SAM, "minutes": 30}))["origin_id"]
    view = household.time_view(SAM)
    ended = next(o for o in view["origins"] if o["id"] == first)
    assert ended["endable"] is False and ended["end"] is None
    assert ended["ended_at"] and ended["ended_by"] == "Alex"
    with pytest.raises(ServiceValidationError, match="Nothing of it is left to end"):
        await _end(hass, first)
    view = household.time_view(SAM)
    assert view["bonus"] == 30 and view["bonus_left"] == 30
    live = next(o for o in view["origins"] if o["id"] == second)
    assert live["endable"] is True and live["ended_at"] is None and live["ended_by"] is None
    assert view["bonus_origin"] == second


async def test_after_one_of_two_unlimited_grants_ends_the_status_points_at_the_one_still_on(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    household = _hub(hass).household
    now = dt_util.now()
    first = (await _call(hass, "unlimited", {"person": SAM, "until": (now + timedelta(hours=1)).isoformat()}))["origin_id"]
    second = (await _call(hass, "unlimited", {"person": SAM, "until": (now + timedelta(hours=2)).isoformat()}))["origin_id"]
    assert household.time_view(SAM)["unlimited"]["origin"] == second
    assert (await _end(hass, second))["still_on"] is True
    view = household.time_view(SAM)
    assert view["unlimited"]["origin"] == first
    assert next(o for o in view["origins"] if o["id"] == second)["ended_at"]
    # And ending the one still on (through the status's origin) works
    assert (await _end(hass, view["unlimited"]["origin"]))["still_on"] is False
    assert household.time_view(SAM)["unlimited"] is None


async def test_an_ended_pause_is_marked_ended(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    household = _hub(hass).household
    first = (await _call(hass, "pause", {"people": [SAM], "minutes": 10}))["origin_id"]
    second = (await _call(hass, "pause", {"people": [SAM], "minutes": 20}))["origin_id"]
    origins = {o["id"]: o for o in household.time_view(SAM)["origins"]}
    # Replaced by the second: over, and only the pause that's on can be ended
    assert origins[first]["endable"] is False and origins[first]["ended_at"]
    assert origins[second]["endable"] is True and origins[second]["ended_at"] is None
    await hass.services.async_call(DOMAIN, "pause_end", {"people": [SAM]}, blocking=True)
    origins = {o["id"]: o for o in household.time_view(SAM)["origins"]}
    assert origins[second]["endable"] is False and origins[second]["ended_at"]


# 5. Hearth judges the day by its own clock


async def _post(http, secret, **extra):
    response = await http.post(
        f"/api/hearth/device/{SAM_PHONE}/status", json=_phone_status(**extra), headers={"X-Hearth-Secret": secret}
    )
    assert response.status == 200
    return await response.json()


def _used(hass: HomeAssistant) -> float:
    return hass.states.get("sensor.hearth_sam_screen_time_today").attributes["groups"]["all"]


async def test_a_moved_clock_never_wipes_today_s_count(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, http, sam, _alex = await _phones_household(hass, hass_client_no_auth)
    hub = _hub(hass)
    today = dt_util.now().date()
    apps = {"com.example.tube": 780}
    answer = await _post(http, sam, seconds_today=780, app_seconds_today=apps)
    assert answer["day"] == today.isoformat() and "clock_off" not in answer
    await hass.async_block_till_done()
    used = _used(hass)
    assert used > 0

    # The phone's clock moved to tomorrow: a fresh day there, but not here
    tomorrow = (today + timedelta(days=1)).isoformat()
    with patch.object(hub.attention, "notify") as notify:
        answer = await _post(http, sam, day=tomorrow, seconds_today=0, app_seconds_today={})
        await hass.async_block_till_done()
        # The adults hear of it once, not at every status
        await _post(http, sam, day=tomorrow, seconds_today=0, app_seconds_today={})
        await hass.async_block_till_done()
    told = [c.args[0] for c in notify.call_args_list if c.args[0].key == f"hearth_clock_{SAM_PHONE}"]
    assert len(told) == 1 and "its date was changed" in told[0].text and told[0].audience == "adults"
    assert answer["clock_off"] is True and answer["day"] == today.isoformat()
    assert _used(hass) == used
    assert {"id": "hearth_clock", "ok": False, "label": "Its date differs from Home Assistant's"} in hub.checks(SAM_PHONE)

    # Back to today, but counting from nothing: never less than it counted today
    answer = await _post(http, sam, seconds_today=120, app_seconds_today={"com.example.tube": 120})
    await hass.async_block_till_done()
    assert "clock_off" not in answer
    assert _used(hass) == used
    assert all(c["id"] != "hearth_clock" for c in hub.checks(SAM_PHONE))
    # A clock moved back (yesterday) doesn't count either
    await _post(http, sam, day=(today - timedelta(days=1)).isoformat(), seconds_today=0, app_seconds_today={})
    await hass.async_block_till_done()
    assert _used(hass) == used
    # And more today still counts
    await _post(http, sam, seconds_today=900, app_seconds_today={"com.example.tube": 900})
    await hass.async_block_till_done()
    assert _used(hass) > used


# 6. The clock app is never paused


def test_clock_apps_are_never_paused() -> None:
    for clock in ("com.google.android.deskclock", "com.android.deskclock", "com.sec.android.app.clockpackage"):
        assert clock in SYSTEM_NEVER_PAUSED
        assert not school_pausable(clock)


async def test_the_state_document_says_the_clock_is_never_paused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, http, sam, _alex = await _phones_household(hass, hass_client_no_auth)
    answer = await _post(http, sam)
    assert "com.google.android.deskclock" in str(answer["state"])


# 7. A mode until a clock time earlier than now runs until tomorrow morning


async def test_sleep_until_seven_in_the_evening_runs_until_tomorrow_morning(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=21, minute=10, second=0, microsecond=0))
    await _household_with_sam(hass, hass_client_no_auth)
    week = _hub(hass).household.week
    await hass.services.async_call(
        DOMAIN, "change_today", {"people": [SAM], "mode": "sleep", "until": "07:00"}, blocking=True, return_response=True
    )
    today = dt_util.now().date()
    tomorrow = today + timedelta(days=1)
    assert week.resolve(SAM, today).changes[-1] == (21 * 60, "sleep")
    morning = week.resolve(SAM, tomorrow).changes
    assert morning[0] == (0, "sleep") and morning[1][0] == 7 * 60 and morning[1][1] != "sleep"
    # It stays past midnight, and goes the day after
    assert week.new_day(tomorrow) == []
    assert week.resolve(SAM, tomorrow).changes[0] == (0, "sleep")
    assert week.new_day(tomorrow + timedelta(days=1)) == [SAM]
    # A time later today still ends today; the same time as now is refused
    await hass.services.async_call(
        DOMAIN, "change_today", {"people": [SAM], "mode": "sleep", "until": "22:00"}, blocking=True, return_response=True
    )
    changes = week.resolve(SAM, today).changes
    assert changes[-2] == (21 * 60, "sleep") and changes[-1][0] == 22 * 60
    assert not week.data.today[SAM].get("next_morning")
    assert week.resolve(SAM, tomorrow).changes[:1] != [(0, "sleep")]
    with pytest.raises(ServiceValidationError, match="It has to end after it starts"):
        await hass.services.async_call(
            DOMAIN, "change_today", {"people": [SAM], "mode": "sleep", "until": "21:05"}, blocking=True,
            return_response=True,
        )
    # Until midnight ends at midnight: tomorrow isn't Sleep all day
    await hass.services.async_call(
        DOMAIN, "change_today", {"people": [SAM], "mode": "sleep", "until": "00:00"}, blocking=True, return_response=True
    )
    assert week.resolve(SAM, today).changes[-1] == (21 * 60, "sleep")
    assert week.resolve(SAM, tomorrow).changes[:1] != [(0, "sleep")]


# 9. Pairing a phone: who's asked, Approve / Deny from the notification, and an adult confirming their own phone


async def _start(http, device_id: str, **extra) -> dict:
    response = await http.post(
        "/api/hearth/pair",
        json={"device_id": device_id, "kind": "mobile", "name": "Glint", "model": "Pixel 9", "nonce": NONCE, **extra},
    )
    assert response.status == 200
    return await response.json()


async def _poll(http, pairing_id: str) -> dict:
    return await (await http.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json()


async def _pairing_household(hass: HomeAssistant, hass_client_no_auth):
    """Alex (an administrator, with a phone), Jordan (an adult in Hearth, not an administrator), Sam (a kid)."""
    hass.states.async_set(SAM, "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    alex = await hass.auth.async_create_user("Alex", group_ids=["system-admin"])
    _companion_app(hass, "Alex Phone", "Android", user_id=alex.id)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": alex.id})
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan"})
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {SAM: "kid"}})
    await hass.async_block_till_done()
    await _adults(hass, "person.alex", "person.jordan")
    sent = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    return await hass_client_no_auth(), alex, sent


def _clear_asked(hass: HomeAssistant) -> None:
    hass.data[f"{DOMAIN}_pairing"]["asked_at"].clear()


async def test_a_phone_s_pairing_asks_the_administrators_who_approve_from_the_notification(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    http, alex, sent = await _pairing_household(hass, hass_client_no_auth)
    started = await _start(http, "glint-jordan-0123456", person_name="Jordan", role="adult")
    await hass.async_block_till_done()
    # Who will be asked, by name, and whether a phone of theirs got it
    assert {"name": "Alex", "phone": True} in started["approvers"]

    key = f"hearth_pairing_{started['pairing_id']}"
    [push] = sent
    code = started["code"]
    assert push.data["title"] == "A Hearth device wants to pair"
    assert push.data["message"] == (
        f"Jordan's Glint (Pixel 9) wants to pair as an adult. Code {code[:3]} {code[3:]}: approve only if the device "
        "shows the same code."
    )
    assert [b["title"] for b in push.data["data"]["actions"]] == ["Approve", "Deny"]
    # The bell links to Hearth's page, never Devices & services, and doesn't show the code (everyone sees the bell)
    bell = persistent_notification._async_get_or_create_notifications(hass)[key]
    assert "(/hearth)" in bell["message"] and "/config/integrations" not in bell["message"] and code not in bell["message"]
    assert bell["message"].startswith("**Jordan's Glint (Pixel 9) wants to pair as an adult**")

    # Someone else's press is ignored (Jordan isn't an administrator)
    jordan = await hass.auth.async_create_user("Jordan")
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": jordan.id})
    approve = push.data["data"]["actions"][0]["action"]
    hass.bus.async_fire("mobile_app_notification_action", {"action": approve}, context=Context(user_id=jordan.id))
    await hass.async_block_till_done()
    assert (await _poll(http, started["pairing_id"]))["status"] == "pending"
    # The administrator's Approve pairs it as the person it named, and the phone hears it on its poll
    hass.bus.async_fire("mobile_app_notification_action", {"action": approve}, context=Context(user_id=alex.id))
    await hass.async_block_till_done()
    answer = await _poll(http, started["pairing_id"])
    assert answer["status"] == "approved" and answer["person"] == "person.jordan" and answer["role"] == "adult"
    assert key not in persistent_notification._async_get_or_create_notifications(hass)

    # Deny: the phone hears "denied"
    _clear_asked(hass)
    started = await _start(http, "glint-other-01234567")
    await hass.async_block_till_done()
    assert [b["title"] for b in sent[-1].data["data"]["actions"]] == ["Deny"]  # whose phone: chosen on the page
    deny = sent[-1].data["data"]["actions"][0]["action"]
    hass.bus.async_fire("mobile_app_notification_action", {"action": deny}, context=Context(user_id=alex.id))
    await hass.async_block_till_done()
    assert (await _poll(http, started["pairing_id"]))["status"] == "denied"


async def test_the_answer_service_is_an_administrator_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from homeassistant.exceptions import Unauthorized

    http, _alex, _sent = await _pairing_household(hass, hass_client_no_auth)
    started = await _start(http, "glint-jordan-0123456", person_name="Jordan", role="adult")
    jordan = await hass.auth.async_create_user("Jordan")
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": jordan.id})
    data = {"pairing_id": started["pairing_id"], "answer": "approve", "person": "person.jordan"}
    for context in (Context(), Context(user_id=jordan.id)):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(DOMAIN, "pairing_answer", data, blocking=True, context=context)
    assert (await _poll(http, started["pairing_id"]))["status"] == "pending"


async def test_an_adult_who_isn_t_an_administrator_confirms_their_own_phone_with_its_code(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    http, _alex, _sent = await _pairing_household(hass, hass_client_no_auth)
    # The WebSocket's user is Jordan, an adult in Hearth who isn't an administrator
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": hass_admin_user.id})
    hass_admin_user.groups = []
    ws = await hass_ws_client(hass)
    started = await _start(http, "glint-jordan-0123456")
    code = started["code"]
    wrong = f"{(int(code) + 1) % 1_000_000:06d}"

    async def answer(n: int, **data) -> dict:
        await ws.send_json({"id": n, "type": "hearth/pairing", "answer": "approve", **data})
        return await ws.receive_json()

    assert (await answer(1))["error"]["code"] == "wrong_code"
    assert (await answer(2, code=wrong))["error"]["code"] == "wrong_code"
    result = await answer(3, pairing_id=started["pairing_id"], code=code, person="person.sam")
    # As themselves, whoever was named
    assert result["success"] and result["result"]["person"] == "person.jordan"
    polled = await _poll(http, started["pairing_id"])
    assert polled["status"] == "approved" and polled["person"] == "person.jordan" and polled["role"] == "adult"

    # A phone paired for someone else isn't theirs to pair again
    hub = _hub(hass)
    _clear_asked(hass)
    await _start(http, "glint-sam-012345678")
    sam_pairing = next(p for p in hub.pending_pairings() if p.device_id == "glint-sam-012345678")
    assert await hub.async_approve(sam_pairing.pairing_id, SAM)
    await hass.async_block_till_done()
    _clear_asked(hass)
    again = await _start(http, "glint-sam-012345678")
    result = await answer(4, code=again["code"])
    assert result["error"]["code"] == "unauthorized"
    assert (await _poll(http, again["pairing_id"]))["status"] == "pending"

    # Too many wrong codes: a wait
    for n in range(5, 9):
        await answer(n, code=wrong)
    assert (await answer(9, code=again["code"]))["error"]["code"] == "too_many_tries"


@pytest.mark.parametrize("role", ["kid", None])
async def test_a_kid_or_someone_who_isn_t_a_hearth_adult_can_t_confirm(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, role
) -> None:
    http, _alex, _sent = await _pairing_household(hass, hass_client_no_auth)
    person = SAM if role == "kid" else "person.riley"
    hass.states.async_set(person, "home", {"friendly_name": person.split(".")[1].title(), "user_id": hass_admin_user.id})
    hass_admin_user.groups = []
    ws = await hass_ws_client(hass)
    started = await _start(http, "glint-someone-0123456")
    await ws.send_json({"id": 1, "type": "hearth/pairing", "answer": "approve", "code": started["code"]})
    result = await ws.receive_json()
    assert result["error"]["code"] == "unauthorized"
    assert (await _poll(http, started["pairing_id"]))["status"] == "pending"


# 7. A pool that's gone takes its entities with it


async def test_a_pool_that_s_gone_takes_its_entities_with_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from homeassistant.helpers import entity_registry as er

    await _household_with_sam(hass, hass_client_no_auth)
    registry = er.async_get(hass)
    entry = hass.config_entries.async_entries(DOMAIN)[0]

    def sam_entities(pool: str) -> list[str]:
        return [
            e.entity_id
            for e in er.async_entries_for_config_entry(registry, entry.entry_id)
            if e.unique_id.startswith(f"{entry.entry_id}_{SAM}_") and e.unique_id.endswith(f"_{pool}")
        ]

    assert len(sam_entities("video")) == 5  # two budgets, the bonus, today's time and the minutes left
    kept = sam_entities("all")
    assert kept

    # The Video pool is removed: its entities go on the reload instead of staying unavailable for good
    groups = [g for g in entry.options.get("groups", []) if g["id"] != "video"]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "groups": groups})
    await hass.async_block_till_done()
    assert sam_entities("video") == []
    assert sam_entities("all") == kept
    assert all(hass.states.get(e) is not None for e in kept)


# 8. Minutes a phone counted offline count on its first post back


async def test_minutes_counted_offline_count_on_the_first_post_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    from test_client_contract import _household as _phones, _status

    _entry, client, sam, _alex = await _phones(hass, hass_client_no_auth)
    await _status(client, sam, seconds_today=600, app_seconds_today={"com.example.tube": 600})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "10"
    # Half an hour offline, counting all along; Hearth hears nothing meanwhile
    freezer.tick(timedelta(minutes=30))
    async_fire_time_changed(hass, dt_util.utcnow())
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "10"
    await _status(client, sam, seconds_today=2400, app_seconds_today={"com.example.tube": 2400})
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "40"


# 9. A limit reached before a restart stays held while the sources settle


async def test_a_limit_reached_stays_held_while_the_sources_settle(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed

    from custom_components.hearth import household
    from test_init import _post
    from test_people import _tv_status

    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    reached = async_capture_events(hass, "hearth_budget_reached")
    await hass.services.async_call(DOMAIN, "set_budget", {"person": SAM, "group": "video", "minutes": 30}, blocking=True)
    await _post(client, secret, body=_tv_status(hearthtube_s=1900))
    await hass.async_block_till_done()
    left = "sensor.hearth_sam_video_minutes_left"
    assert hass.states.get(left).state == "0" and len(reached) == 1

    # Home Assistant starts again: for a moment the count is short (here: an adult's bonus stands in for it), and
    # the group a kid was out of stays held until the sources have settled
    monkeypatch.setattr(household, "STARTUP_SETTLE", timedelta(seconds=90))
    _hub(hass).household._settle_until = None
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": SAM, "group": "video", "minutes": 15}, blocking=True)
    await hass.async_block_till_done()
    assert hass.states.get(left).state == "0"
    assert _hub(hass).household.limits.is_reached(SAM, "video")

    # Settled: it opens by itself, and reaching 0 again later fires once more
    freezer.tick(timedelta(seconds=95))
    async_fire_time_changed(hass, dt_util.utcnow())
    await hass.async_block_till_done()
    assert int(hass.states.get(left).state) > 0
    assert len(reached) == 1

    # A reload (a setting changed) finds the sources loaded: a bonus opens a reached limit at once
    await _post(client, secret, body=_tv_status(hearthtube_s=3600))
    await hass.async_block_till_done()
    assert hass.states.get(left).state == "0"
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": SAM, "group": "video", "minutes": 30}, blocking=True)
    await hass.async_block_till_done()
    assert int(hass.states.get(left).state) > 0
