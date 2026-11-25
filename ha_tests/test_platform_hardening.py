"""The cross-platform hardening review's findings, each with the case that went wrong: a Family Safety lock or unlock
that applied but raised, the raise to the day's budget on Family Link devices Hearth holds, Family Safety extra time
that fails with a plain error, Hearth's own Family Safety request approval, Hearth's own Family Safety pauses in
explain, a cut short Pending Requests list, one wording for a parent's bonus time, and a person on account-id calls."""

from datetime import date, timedelta

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.enforce import Held
from test_enforce import _add_enforcer, _bonus, _budget, settled  # noqa: F401 - the fixture
from test_fs_upstream import (
    ACCOUNT,
    FS,
    PENDING,
    _held_on_upstream,
    _household,
    _locked_by_hours,
    _pending,
    _request,
    _sam_on_family_safety,
    _sam_with_pending,
    _upstream,
    _xbox,
)
from test_people import _household_with_sam
from test_targets import _windows

KEY = f"{enforce.FAMILY_SAFETY}|person.sam"


def _failing(hass: HomeAssistant, service: str, err: Exception, calls: list | None = None) -> list[ServiceCall]:
    """[service] of Family Safety answers with [err], after Microsoft applied it (the caller shows what it did)."""
    calls = calls if calls is not None else []

    async def handle(call: ServiceCall):
        calls.append(call)
        raise err

    hass.services.async_register(FS, service, handle, supports_response=SupportsResponse.OPTIONAL)
    return calls


# 1. A Family Safety unlock that fails after it went out is Hearth's own, never a parent's unlock


async def test_an_unlock_that_failed_after_it_went_out_is_no_parent_s_unlock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, _ = await _held_on_upstream(hass, hass_client_no_auth, freezer)
    unlocks = _failing(hass, "unlock_platform", HomeAssistantError("timed out"))
    await _bonus(hass, "games", 30)  # time again: the unlock goes out, applies, and its answer is a timeout
    assert [c.data["platform"] for c in unlocks] == ["Xbox"]
    _xbox(hass, "on")  # nothing locked any more
    freezer.tick(timedelta(minutes=2))
    await _bonus(hass, "games", 0)
    assert grants == []
    enforcement = _household(hass).enforcement
    assert "Xbox" not in (enforcement.held.get(KEY) or Held()).items

    # Out of time again: locked again (nothing is left counted as held, no parent's grant lifts it)
    async_mock_service(hass, FS, "unlock_platform")
    freezer.tick(timedelta(minutes=6))
    await _bonus(hass, "games", -30)
    assert len(calls["lock_platform"]) == 2


async def test_a_midnight_unlock_that_failed_after_it_went_out_is_no_parent_s_unlock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    _, enforcement, _ = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    unlocks = _failing(hass, "unlock_platform", HomeAssistantError("timed out"))
    freezer.move_to(enforce.next_midnight() + timedelta(seconds=30))
    await enforcement.async_lock_ends_tick()
    assert [c.data["platform"] for c in unlocks] == ["Xbox"]
    quiet = enforcement._quiet(KEY)
    _xbox(hass, "on")
    freezer.tick(timedelta(minutes=2))
    await _bonus(hass, "games", 0)
    assert grants == []
    # The tick's call is Hearth's own call: the minute after it is quiet, as after the enforcement's
    assert quiet


# 4. A Family Safety lock that applied but raised is Hearth's, and is let go of


async def test_a_lock_that_applied_but_raised_is_hearth_s_and_is_let_go_of(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    locks = _failing(hass, "lock_platform", HomeAssistantError("timed out"))
    unlocked = async_mock_service(hass, FS, "unlock_platform")
    _xbox(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    [lock] = locks
    enforcement = _household(hass).enforcement
    # Microsoft applied it: the lock in force ends when Hearth asked
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until=lock.data["until"])
    assert enforcement.fs_parent_locks("person.sam") == []
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert row["hold"] == "ours"

    # Time again, once the failed call's wait is over: Hearth unlocks what it may have locked
    freezer.tick(timedelta(minutes=6))
    await _bonus(hass, "games", 30)
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]
    held = enforcement.held.get(KEY) or Held()
    assert "Xbox" not in enforce._holding(held) and enforce.FS_LOCKING not in held.restore


async def test_a_lock_refused_by_its_schema_isn_t_possibly_held(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """An older Family Safety refuses the newer call: nothing went out for it, and the call as before locks."""
    calls = _upstream(hass)
    _xbox(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    assert len(calls["lock_platform"]) == 1
    held = _household(hass).enforcement.held[KEY]
    assert held.items == {"Xbox"} and enforce.FS_LOCKING not in held.restore


# 2. The raise to the day's budget waits while Hearth holds the Family Link devices


async def test_a_raise_to_the_day_s_budget_waits_while_hearth_holds_the_family_link_devices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from test_schedule import YEAR, _at, _budget, _set_up, _tick

    limit = async_mock_service(hass, "familylink", "set_daily_limit")
    async_mock_service(hass, "switch", "turn_off")
    day_off = date(2026, 11, 26)
    household = await _set_up(
        hass, hass_client_no_auth, freezer, _at(day_off, 0, 1), {**YEAR, "days_off": "2026-11-26"},
        {"follow_family_link": True},
    )
    await _budget(hass, 180, "other_days")
    enforcement = household.enforcement
    # Hearth's Sleep lock past midnight: the weekday's limit at 0 (the enforcement itself stands still here)
    enforcement._closed = True
    enforcement.held["family_link|person.sam"] = Held(
        {enforce.DEVICES}, "sensor.sam_family_link_daily_screen_time",
        restore={"lock_minutes": 120, "lock_child": "42", "lock_weekday": 4, "lock_day": day_off.isoformat()},
    )
    hass.states.async_set("number.sam_family_link_thursday_limit", "0", {"child_id": "42", "weekly_minutes": 0})
    await _tick(hass, household, freezer, _at(day_off, 0, 6))
    await _tick(hass, household, freezer, _at(day_off, 3, 0))
    assert limit == []

    # Let go in the morning (the weekday's limit back): raised to the day's budget then, once
    del enforcement.held["family_link|person.sam"]
    hass.states.async_set("number.sam_family_link_thursday_limit", "120", {"child_id": "42", "weekly_minutes": 120})
    await _tick(hass, household, freezer, _at(day_off, 7, 0))
    await _tick(hass, household, freezer, _at(day_off, 7, 1))
    assert [c.data for c in limit] == [{"child_id": "42", "daily_minutes": 180}]


# 6. Family Safety extra time that fails with a plain error


async def test_a_plain_error_on_the_xbox_still_gives_windows_and_is_watched(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    _upstream(hass)
    given: list[str] = []

    async def add_time_bonus(call: ServiceCall):
        given.append(call.data["platform"])
        if call.data["platform"] == "Xbox":
            raise RuntimeError("Microsoft's answer couldn't be read")
        return {"added": True, "until": call.data["until"]}

    hass.services.async_register(FS, "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL)
    _xbox(hass, used_minutes=55)
    _windows(hass, used=895)
    await _sam_on_family_safety(hass, hass_client_no_auth, platforms=("Xbox", "Windows"))
    await hass.services.async_call(
        "hearth", "allow", {"people": ["person.sam"], "group": "all", "until": dt_util.now().replace(hour=13).isoformat()},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    assert given == ["Xbox", "Windows"]
    sync = _household(hass).sync
    assert [e["platform"] for e in sync.possibly_given] == ["Xbox"]
    assert sync.fs_bonus_until("person.sam", "Windows") is not None


# 7. Hearth's own approval of a Family Safety request


async def _held_with_request(hass: HomeAssistant, hass_client_no_auth, freezer) -> tuple[dict, object]:
    """Sam's Xbox held by Hearth (upstream's Family Safety), and his request r1 from the Xbox. (calls, the hub)"""
    calls, _ = await _held_on_upstream(hass, hass_client_no_auth, freezer)
    asked = async_capture_events(hass, "hearth_more_time_requested")
    hass.bus.async_fire(
        f"{FS}_request",
        {"account_id": str(ACCOUNT), "request_id": "r1", "platform": "Xbox", "type": "screenTime",
         "requested_time": 1800},
    )
    await hass.async_block_till_done()
    return calls, asked[0].data["id"]


async def test_hearth_s_own_approval_of_a_request_is_no_parent_s_bonus_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, ask_id = await _held_with_request(hass, hass_client_no_auth, freezer)
    approved = async_mock_service(hass, FS, "approve_request")
    await hass.services.async_call("hearth", "answer_request", {"request_id": ask_id, "minutes": 30}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data["extension_minutes"] for c in approved] == [30]
    until = (dt_util.now() + timedelta(minutes=30)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    freezer.tick(timedelta(minutes=2))
    await _bonus(hass, "games", 0)
    assert grants == []
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert row["hold"] == "bonus_ours"
    # Hearth's own extra time on the Xbox: its hold there is let go meanwhile, without an unlock over the approval
    [extra] = _household(hass).device_extra_views("person.sam")
    assert (extra["target"], extra["reason"]) == ("fs:xbox", "Family Safety request approved")
    assert len(calls["lock_platform"]) == 1 and calls["unlock_platform"] == []
    # Over: locked again (games are still out of time)
    _xbox(hass, "on")
    freezer.tick(timedelta(minutes=30))
    await _bonus(hass, "games", 0)
    assert len(calls["lock_platform"]) == 2


async def test_an_approval_that_failed_may_have_gone_through(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from homeassistant.components import persistent_notification

    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, ask_id = await _held_with_request(hass, hass_client_no_auth, freezer)
    _failing(hass, "approve_request", HomeAssistantError("timed out"))
    await hass.services.async_call("hearth", "answer_request", {"request_id": ask_id, "minutes": 30}, blocking=True)
    await hass.async_block_till_done()
    sync = _household(hass).sync
    assert [(e["why"], e["platform"]) for e in sync.possibly_given] == [("ask:r1", "Xbox")]
    notice = next(
        n for key, n in persistent_notification._async_get_or_create_notifications(hass).items()
        if key.startswith("hearth_more_fs_")
    )
    # Not "answer it in the Family Safety app" outright: it may be approved already
    assert "may have gone through" in notice["message"]

    # Microsoft shows it: Hearth's own, kept (never cancelled as an ended reason's), and no parent's grant
    until = (dt_util.now() + timedelta(minutes=30)).replace(microsecond=0)
    freezer.tick(timedelta(minutes=1))
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await sync.async_pending_tick()
    assert sync.possibly_given == [] and calls["cancel_time_bonus"] == []
    freezer.tick(timedelta(minutes=2))
    await _bonus(hass, "games", 0)
    assert grants == []


async def test_a_parent_s_bonus_time_in_the_family_safety_app_is_worded_as_the_others(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _held_on_upstream(hass, hass_client_no_auth, freezer)
    until = (dt_util.now() + timedelta(hours=1)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await _bonus(hass, "games", 0)
    assert grants[0].data["reason"] == "bonus time given in the Family Safety app"


# 8. Hearth's own Family Safety pause isn't a parent's block in explain


async def test_hearth_s_own_family_safety_pause_isn_t_a_parent_s_block(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from test_app_blocks import _call, _recompute
    from test_sources import _option

    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("sensor.sam_family_safety", "ok", {"user_id": "ms-sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": "sensor.sam_family_safety"})

    def applications(paused_apps=None) -> None:
        attrs = {"user_id": "ms-sam", "applications": [
            {"app_id": "x:racer", "app_name": "Racer", "blocked": True, "limit_minutes": None}]}
        if paused_apps is not None:
            attrs["paused_apps"] = paused_apps
        hass.states.async_set("sensor.sam_applications", "1", attrs)

    async def blocked_by() -> list:
        why = await _call(hass, "explain", {"person": "person.sam", "app": "x:racer"}, True)
        return [b["by"] for b in why["blocked_by"] if b["kind"] == "blocked_app"]

    # Family Safety says the pause is Hearth's own (the app wasn't blocked before)
    applications([{"package": "x:racer", "paused": "ours"}])
    await _recompute(hass)
    assert await blocked_by() == []
    # An older Family Safety without paused_apps: Hearth holds it
    applications()
    _household(hass).enforcement.held[KEY] = Held({"x:racer"}, "sensor.sam_family_safety")
    assert await blocked_by() == []
    # A parent's own block stays a parent's
    _household(hass).enforcement.held.pop(KEY)
    assert await blocked_by() == ["sensor.sam_applications"]


# 9. A cut-short Pending Requests list resolves nothing


async def test_a_cut_short_pending_requests_list_resolves_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1
    hass.states.async_set(PENDING, "40", {"user_id": str(ACCOUNT), "requests": [_request("r2")], "truncated": True})
    await hass.async_block_till_done()
    freezer.tick(timedelta(minutes=6))
    hub.fs_requests.check()
    # r1 isn't gone, only left out; r2 is a new ask
    assert {a.external_id for a in hub.asks.pending()} == {"r1", "r2"}


# 10. Family Safety calls name their person and why


async def test_an_account_id_call_names_its_person_and_why(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    async_mock_service(hass, FS, "lock_platform")
    async_mock_service(hass, FS, "unlock_platform")
    await _household_with_sam(hass, hass_client_no_auth)
    await _add_enforcer(hass, {"kind": "family_safety", "person": "person.sam", "entity_id": "987654"})
    await _budget(hass, "games", 5)
    [record] = [r for r in _household(hass).activity.query(kind="call") if r["service"] == f"{FS}.lock_platform"]
    assert (record["person"], record["why"]) == ("person.sam", "hold")
