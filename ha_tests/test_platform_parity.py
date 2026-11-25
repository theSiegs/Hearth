"""What Hearth does on each platform alike (docs/home-assistant-integration.md): Hearth's extra time reaches the Switch's
own limit, hearth.block_app works for Xbox and Windows apps, bedtime is lifted on one Family Link device, Xbox or
Switch, and hearth.explain names the Switch's own limit."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import app_blocks, enforce
from custom_components.hearth.const import DOMAIN
from test_enforce import FAMILY_SAFETY, NINTENDO_LIMIT, _budget, _nintendo_services, _nintendo_switch
from test_native_sync import PHONE, _phone, _sam_with_family_link
from test_nintendo_panel import EXTRA, LIMIT, _core_services, _patched_services, _sam_on_the_switch
from test_people import _household_with_sam
from test_phones import _options
from test_sources import _option
from test_weekly import SCHOOL_DAY, _schedule

N = "nintendo_parental_controls"
FS = "microsoft_family_safety"
KEY = f"nintendo|person.sam|{LIMIT}"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _at(freezer, hour: int, minute: int = 0) -> None:
    freezer.move_to(dt_util.now().replace(hour=hour, minute=minute, second=0, microsecond=0))


async def _service(hass: HomeAssistant, service: str, data: dict, response: bool = False):
    result = await hass.services.async_call(
        DOMAIN, service, {"person": "person.sam", **data} if service in ("add_bonus", "remove_bonus", "explain") else data,
        blocking=True, return_response=response,
    )
    await hass.async_block_till_done()
    return result


def _of(calls: list[ServiceCall], service: str) -> list[dict]:
    return [dict(c.data) for c in calls if c.service == service]


def _all_left(hass: HomeAssistant) -> float:
    return _household(hass).days["person.sam"].limits["all"].minutes_left


# Gap 1: Hearth's extra time reaches the Switch's own limit


async def _sam_switch_out(hass: HomeAssistant, hass_client_no_auth, freezer, hour: int = 12, **switch):
    """Sam's Switch has used up its own limit (120 played of 120); Sam isn't playing, so Hearth doesn't hold it."""
    _at(freezer, hour)
    device_id = await _sam_on_the_switch(hass, hass_client_no_auth, **{"left": "0", "played": "120", **switch})
    _nintendo_services(hass)
    return device_id


async def test_extra_time_reaches_the_switch_s_own_limit_and_goes_back_with_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    device_id = await _sam_switch_out(hass, hass_client_no_auth, freezer)
    calls = _patched_services(hass)
    await _budget(hass, "all", 15)  # 15 used: none left
    await _service(hass, "add_bonus", {"minutes": 30})
    assert _all_left(hass) == 30
    # The Switch's own limit would stop Sam now: Nintendo's extra playing time for as long as Hearth lets it run
    assert _of(calls, "add_bonus_time") == [{"device_id": device_id, "bonus_time": 30}]
    status = _household(hass).enforcement.status_of("person.sam")
    assert any((s.get("last") or {}).get("extra_time") == {"Sam's Switch": 30} for s in status.values())
    # Hearth's own: never a parent's grant
    assert _household(hass).grants.of("person.sam") == []

    # Taken back: Hearth's own extra playing time is cancelled
    hass.states.async_set(EXTRA, "30")
    await _service(hass, "remove_bonus", {"minutes": 30})
    assert _of(calls, "cancel_bonus_time") == [{"device_id": device_id}]


async def test_a_parent_s_extra_playing_time_on_top_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_switch_out(hass, hass_client_no_auth, freezer)
    calls = _patched_services(hass)
    await _budget(hass, "all", 15)
    await _service(hass, "add_bonus", {"minutes": 30})
    hass.states.async_set(EXTRA, "60")  # Hearth's 30 and a parent's 30
    await _service(hass, "remove_bonus", {"minutes": 30})
    assert _of(calls, "cancel_bonus_time") == []


async def test_allowing_games_opens_the_switch_s_own_limit_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    device_id = await _sam_switch_out(hass, hass_client_no_auth, freezer)
    calls = _patched_services(hass)
    answer = await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "games", "until": "13:00"},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    assert _of(calls, "add_bonus_time") == [{"device_id": device_id, "bonus_time": 60}]
    # An allow of a group the Switch isn't held for gives none
    await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "messaging", "until": "14:00"}, blocking=True
    )
    await hass.async_block_till_done()
    assert len(_of(calls, "add_bonus_time")) == 1

    hass.states.async_set(EXTRA, "60")
    await hass.services.async_call(DOMAIN, "allow_end", {"id": answer["id"]}, blocking=True)
    await hass.async_block_till_done()
    assert _of(calls, "cancel_bonus_time") == [{"device_id": device_id}]


async def test_switch_extra_time_waits_while_hearth_holds_it_and_is_cancelled_before_a_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Extra playing time opens a held Switch, and while it runs the Switch refuses Hearth's limit of 0."""
    await _sam_switch_out(hass, hass_client_no_auth, freezer)
    calls = _patched_services(hass)
    await _budget(hass, "all", 75)  # 60 left
    household = _household(hass)
    held = household.enforcement.held.setdefault(KEY, enforce.Held(entity_id=LIMIT))
    held.items.add(enforce.SWITCH)
    held.restore = {"max": 120}
    household.sync.mirror_bonus("person.sam")
    await hass.async_block_till_done()
    assert _of(calls, "add_bonus_time") == []

    held.items.clear()
    held.restore = {}
    await household.sync.async_pending_tick()
    await household.sync.async_pending_tick()
    [given] = _of(calls, "add_bonus_time")
    assert given["bonus_time"] == 60

    # Hearth holds the Switch again (a pause, say): its own extra time is cancelled first, then held
    hass.states.async_set(EXTRA, "60")
    set_value = async_mock_service(hass, "number", "set_value")
    await household.enforcement._hold_switch(LIMIT, enforce.Held(entity_id=LIMIT))
    assert len(_of(calls, "cancel_bonus_time")) == 1
    assert [c.data["value"] for c in set_value] == [0]
    # ... and it waits to be given again once the hold is let go
    assert any(isinstance(r.get("sw_wait"), dict) for r in household.sync._given.values())

    # A parent's extra playing time is theirs: the hold waits for it to end, nothing is cancelled
    household.sync.sw_added[LIMIT] = {"day": dt_util.now().date().isoformat(), "minutes": 10}
    hass.states.async_set(EXTRA, "40")
    with pytest.raises(ValueError, match="bonus time is active"):
        await household.enforcement._hold_switch(LIMIT, enforce.Held(entity_id=LIMIT))
    assert len(_of(calls, "cancel_bonus_time")) == 1


async def test_switch_extra_time_never_runs_into_its_bedtime(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Nintendo moves the Switch's bedtime alarm (21:30 here) for extra time that runs into it."""
    await _sam_switch_out(hass, hass_client_no_auth, freezer, hour=21)
    calls = _patched_services(hass)
    await _budget(hass, "all", 75)  # 60 left
    _household(hass).sync.mirror_bonus("person.sam")
    await hass.async_block_till_done()
    assert [c["bonus_time"] for c in _of(calls, "add_bonus_time")] == [30]

    # In its bedtime: none (it waits till the bedtime ends, today: never)
    _at(freezer, 21, 40)
    _household(hass).sync.mirror_bonus("person.sam")
    await hass.async_block_till_done()
    assert len(_of(calls, "add_bonus_time")) == 1


async def test_no_switch_extra_time_where_hearth_couldn_t_cancel_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Home Assistant's own Nintendo integration has no cancel: Hearth couldn't hold the Switch again."""
    await _sam_switch_out(hass, hass_client_no_auth, freezer)
    added = _core_services(hass)
    await _budget(hass, "all", 45)
    _household(hass).sync.mirror_bonus("person.sam")
    await hass.async_block_till_done()
    assert added == []
    status = _household(hass).enforcement.status_of("person.sam")
    assert any("can't cancel" in str((s.get("last") or {}).get("error")) for s in status.values())


async def test_extra_time_on_one_switch_reaches_its_own_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    device_id = await _sam_switch_out(hass, hass_client_no_auth, freezer)
    calls = _patched_services(hass)
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 20, "group": "all", "device": f"nintendo:{LIMIT}"},
        blocking=True,
    )
    await hass.async_block_till_done()
    await _household(hass).sync.async_pending_tick()
    assert _of(calls, "add_bonus_time") == [{"device_id": device_id, "bonus_time": 20}]

    hass.states.async_set(EXTRA, "20")
    await hass.services.async_call(
        DOMAIN, "allow_end", {"people": ["person.sam"], "device": f"nintendo:{LIMIT}"}, blocking=True
    )
    await hass.async_block_till_done()
    assert _of(calls, "cancel_bonus_time") == [{"device_id": device_id}]


# Gap 5: explain names the Switch's own limit


async def test_explain_names_the_switch_s_own_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_switch_out(hass, hass_client_no_auth, freezer)
    explained = await _service(hass, "explain", {"group": "games"}, True)
    assert explained["allowed"] is False
    [limit] = [b for b in explained["blocked_by"] if b["kind"] == "device_limit"]
    assert limit["device"] == "Sam's Switch" and limit["by"] == LIMIT
    # Not for what the Switch isn't held for
    explained = await _service(hass, "explain", {"group": "messaging"}, True)
    assert all(b["kind"] != "device_limit" for b in explained["blocked_by"])
    # Extra playing time on it: the limit doesn't stop it
    hass.states.async_set(EXTRA, "15")
    hass.states.async_set("sensor.sam_s_switch_screen_time_remaining", "15")
    explained = await _service(hass, "explain", {"group": "games"}, True)
    assert all(b["kind"] != "device_limit" for b in explained["blocked_by"])


# Gap 4: bedtime lifted on one Family Link device, Xbox or Switch


async def _lift(hass: HomeAssistant, device: str, until: str) -> dict:
    answer = await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "device": device, "bedtime": True, "until": until},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    return answer


async def _sleep_schedule(hass: HomeAssistant) -> None:
    await _options(hass, roles={"person.sam": "kid"})
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)
    await hass.async_block_till_done()


def _xbox_hours(hass: HomeAssistant, end: str) -> None:
    hass.states.async_set(
        "sensor.sam_xbox_time_remaining", "30",
        {"user_id": 123456, "platform": "Xbox", "allowance_minutes": 600, "used_minutes": 60,
         "allowed_ranges": [{"begin": "07:00:00", "end": end}]},
    )


async def test_bedtime_lifted_on_the_xbox_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """"Xbox until 10 tonight, nothing else": Hearth's Sleep lock of the Xbox goes, Microsoft's allowed hours reach
    10, and daily time still holds it."""
    _at(freezer, 21, 45)
    locked = async_mock_service(hass, FS, "lock_platform")
    unlocked = async_mock_service(hass, FS, "unlock_platform")
    intervals = async_mock_service(hass, FS, "set_screentime_intervals")
    bonus = async_mock_service(hass, FS, "add_time_bonus")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    _xbox_hours(hass, "21:30:00")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _sleep_schedule(hass)
    assert [c.data["platform"] for c in locked] == ["Xbox"]

    answer = await _lift(hass, "fs:xbox", "22:00")
    assert answer["id"].startswith("dx_")
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]
    assert [(c.data["platform"], c.data["end_hour"], c.data["end_minute"]) for c in intervals] == [("Xbox", 22, 0)]
    assert bonus == []  # bedtime alone: no extra time
    household = _household(hass)
    # Everyone else's Sleep still holds; a budget still holds the Xbox
    assert "all" in household.schedule_holds("person.sam")
    await _budget(hass, "all", 10)
    assert [c.data["platform"] for c in locked] == ["Xbox", "Xbox"]


async def test_bedtime_lifted_on_the_xbox_ends_and_is_put_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _at(freezer, 21, 45)
    locked = async_mock_service(hass, FS, "lock_platform")
    async_mock_service(hass, FS, "unlock_platform")
    intervals = async_mock_service(hass, FS, "set_screentime_intervals")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    _xbox_hours(hass, "21:30:00")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _sleep_schedule(hass)
    await _lift(hass, "fs:xbox", "22:30")
    _xbox_hours(hass, "22:30:00")
    # Ended early: Hearth's lock comes back and the allowed hours go back to 21:30
    await hass.services.async_call(DOMAIN, "allow_end", {"people": ["person.sam"], "device": "fs:xbox"}, blocking=True)
    await hass.async_block_till_done()
    assert [(c.data["end_hour"], c.data["end_minute"]) for c in intervals] == [(22, 30), (21, 30)]
    assert [c.data["platform"] for c in locked] == ["Xbox", "Xbox"]


async def test_bedtime_lifted_on_the_switch_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _at(freezer, 21, 45)
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    added = async_mock_service(hass, N, "add_bonus_time")
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _sleep_schedule(hass)
    assert [c.data["value"] for c in set_value] == [0]
    hass.states.async_set(NINTENDO_LIMIT, "0")

    await _lift(hass, f"nintendo:{NINTENDO_LIMIT}", "22:30")
    assert [c.data["value"] for c in set_value] == [0, 120]
    assert added == []  # bedtime alone: no extra playing time
    # Daily time running out still holds it
    hass.states.async_set(NINTENDO_LIMIT, "120")
    await _budget(hass, "games", 1)
    assert [c.data["value"] for c in set_value] == [0, 120, 0]


async def test_bedtime_lifted_on_one_family_link_phone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A bonus on the phone is what opens Family Link's bedtime there; given once the phone is in bedtime, never more
    than All screen time has left, and taken back when the lift ends early."""
    _at(freezer, 21, 0)
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    await _budget(hass, "all", 60)
    await _lift(hass, "fl:dev1", "22:30")
    household = _household(hass)
    assert added == []  # not in bedtime yet: waits

    _at(freezer, 21, 45)
    _phone(hass, bedtime_active=True, school_time_active=False)
    await household.sync.async_pending_tick()
    await household.sync.async_pending_tick()
    left = _all_left(hass)
    assert [c.data for c in added] == [{"entity_id": PHONE, "bonus_minutes": min(45, int(left))}]
    # Hearth's own: no grant
    assert household.grants.of("person.sam") == []

    _phone(hass, bonus=added[0].data["bonus_minutes"], bedtime_active=True)
    await hass.services.async_call(DOMAIN, "allow_end", {"people": ["person.sam"], "device": "fl:dev1"}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_a_phone_bedtime_lift_waits_through_school_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _at(freezer, 21, 45)
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass, bedtime_active=True, school_time_active=True)
    await _lift(hass, "fl:dev1", "22:30")
    await _household(hass).sync.async_pending_tick()
    assert added == []


# Gap 2: hearth.block_app for Xbox and Windows apps

RACER = "x:racer"
PAINT = "appx:Example.Paint"
APPS = "sensor.sam_applications"


def _applications(hass: HomeAssistant, blocked: tuple[str, ...] = (), apps=(RACER, PAINT), **attrs) -> None:
    hass.states.async_set(
        APPS, str(len(apps)),
        {"user_id": 123456, "applications": [
            {"app_id": a, "app_name": {"x:racer": "Racer", PAINT: "Paint"}.get(a, a), "blocked": a in blocked}
            for a in apps
        ], **attrs},
    )


async def _sam_on_family_safety(hass: HomeAssistant, hass_client_no_auth) -> dict:
    calls = {s: async_mock_service(hass, FS, s) for s in ("block_app", "unblock_app", "lock_platform", "unlock_platform")}
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    _applications(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    return calls


async def _page(hass: HomeAssistant, ws_client) -> dict:
    ws = await ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config"})
    return (await ws.receive_json())["result"]["app_blocks"]


async def test_an_xbox_app_is_blocked_through_family_safety_and_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    calls = await _sam_on_family_safety(hass, hass_client_no_auth)
    answer = await _service(hass, "block_app", {"app": RACER}, True)
    assert answer == {"blocked": {"person.sam": [RACER]}}
    assert [dict(c.data) for c in calls["block_app"]] == [{"entity_id": FAMILY_SAFETY, "app_id": RACER}]

    _applications(hass, blocked=(RACER,))
    _household(hass).recompute()
    await hass.async_block_till_done()
    [kid] = (await _page(hass, hass_ws_client))["kids"]
    assert kid["family_safety"] is True
    assert kid["blocks"] == [{"app": RACER, "name": "Racer", "why": ["adult"], "state": "blocked"}]
    assert len(calls["block_app"]) == 1
    # explain: Hearth's block, not a parent's
    explained = await _service(hass, "explain", {"app": RACER}, True)
    assert [(b["kind"], b["by"]) for b in explained["blocked_by"] if b["kind"] == "blocked_app"] == [
        ("blocked_app", "hearth.block_app")
    ]

    await _service(hass, "unblock_app", {"app": RACER})
    assert [dict(c.data) for c in calls["unblock_app"]] == [{"entity_id": FAMILY_SAFETY, "app_id": RACER}]


async def test_a_parent_s_own_family_safety_block_is_never_undone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    calls = await _sam_on_family_safety(hass, hass_client_no_auth)
    _applications(hass, blocked=(RACER,))
    await _service(hass, "block_app", {"app": RACER})
    assert calls["block_app"] == []
    assert (await _page(hass, hass_ws_client))["kids"][0]["blocks"][0]["state"] == "parent"
    await _service(hass, "unblock_app", {"app": RACER})
    _household(hass).recompute()
    await hass.async_block_till_done()
    assert calls["unblock_app"] == []


async def test_an_xbox_block_waits_for_the_app_and_while_hearth_s_pause_holds_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    """Family Safety pauses an app by blocking it and puts back on resume what it was: a block made under Hearth's
    pause would be undone by the resume, so it waits."""
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    calls = await _sam_on_family_safety(hass, hass_client_no_auth)
    _applications(hass, apps=(PAINT,))
    await _service(hass, "block_app", {"app": RACER})
    assert calls["block_app"] == []
    assert (await _page(hass, hass_ws_client))["kids"][0]["blocks"][0]["state"] == "not_installed"

    household = _household(hass)
    held = household.enforcement.held.setdefault("family_safety|person.sam", enforce.Held(entity_id=FAMILY_SAFETY))
    held.items.add(RACER)
    _applications(hass, blocked=(RACER,))  # blocked for the pause
    household.blocks.sync()
    await hass.async_block_till_done()
    assert calls["block_app"] == []
    assert (await _page(hass, hass_ws_client))["kids"][0]["blocks"][0]["state"] == "pending"

    held.items.discard(RACER)
    _applications(hass)  # resumed
    household.blocks.sync()
    await hass.async_block_till_done()
    assert [c.data["app_id"] for c in calls["block_app"]] == [RACER]


async def test_a_list_cut_short_blocks_nothing(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    calls = await _sam_on_family_safety(hass, hass_client_no_auth)
    _applications(hass, truncated=True)
    await _service(hass, "block_app", {"app": RACER})
    assert calls["block_app"] == []


async def test_what_xbox_and_windows_blocks_take(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    # Sam has Family Link only: an Xbox app can't be blocked for them
    blocked = async_mock_service(hass, FS, "block_app")
    await _sam_with_family_link(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError, match="No Family Safety"):
        await _service(hass, "block_app", {"app": RACER, "people": ["person.sam"]})
    with pytest.raises(ServiceValidationError, match="No kid has Family Link or Family Safety"):
        await _service(hass, "block_app", {"app": RACER})
    with pytest.raises(ServiceValidationError, match="Only Android apps"):
        await _service(hass, "block_app", {"app": "x:"})
    assert blocked == []
