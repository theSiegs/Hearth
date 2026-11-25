"""Writes Hearth keeps before the call (docs/hardened-components.md): Family Safety extra time and request approvals,
Family Safety app pauses and resumes, and Family Link bonuses are Hearth's own from before their call. A call that
fails after it went out, or is cut off (a settings save reloads the entry and cancels calls mid-flight), leaves them
possibly given or possibly held; a refusal before it went out leaves nothing."""

import asyncio
import contextlib
from datetime import timedelta

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import Held
from test_enforce import FAMILY_SAFETY, _bonus, _budget, settled  # noqa: F401 - the fixture
from test_fs_upstream import _failed_extra_time, _held_on_upstream, _household, _upstream, _xbox
from test_init import _video_apps
from test_native_sync import PHONE, _allow_all, _phone, _remaining, _sam_with_family_link
from test_people import _household_with_sam
from test_sources import _option

FS = "microsoft_family_safety"
KEY = f"{enforce.FAMILY_SAFETY}|person.sam"
APPS = "sensor.sam_applications"
VIDEO = "x:videoapp"
# enforce.FS_MAYBE_PAUSED
FS_MAYBE_PAUSED = "fs_maybe_paused"


def _cut_off(hass: HomeAssistant, domain: str, service: str, first_only: bool = True) -> list[ServiceCall]:
    """[service] is cut off mid-flight (as a reload cancels it) on its first call; later calls go through."""
    calls: list[ServiceCall] = []

    async def handle(call: ServiceCall):
        calls.append(call)
        if len(calls) == 1 or not first_only:
            raise asyncio.CancelledError
        return {}

    hass.services.async_register(domain, service, handle, supports_response=SupportsResponse.OPTIONAL)
    return calls


# a) Family Safety extra time


async def test_extra_time_is_possibly_given_while_its_call_runs_and_gone_once_it_went_through(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    seen: list[list] = []

    def install(h: HomeAssistant) -> dict:
        calls = _upstream(h)
        given: list[ServiceCall] = []

        async def add_time_bonus(call: ServiceCall):
            given.append(call)
            sync = _household(h).sync
            # Kept (and saved) before the call: Hearth's own end while it runs, never a parent's
            seen.append([(e["platform"], e.get("pending")) for e in sync.possibly_given])
            seen.append(sync.fs_bonus_ends("person.sam", "Xbox"))
            return {"added": True, "until": str(call.data["until"])}

        h.services.async_register(FS, "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL)
        return {**calls, "add_time_bonus": given}

    await _failed_extra_time(hass, hass_client_no_auth, freezer, install)
    assert seen[0] == [("Xbox", True)] and len(seen[1]) == 1
    assert _household(hass).sync.possibly_given == []


async def test_extra_time_cut_off_by_a_reload_is_watched_and_adopted(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")

    def install(h: HomeAssistant) -> dict:
        calls = _upstream(h)
        return {**calls, "add_time_bonus": _cut_off(h, FS, "add_time_bonus")}

    calls, _allow_id, until = await _failed_extra_time(hass, hass_client_no_auth, freezer, install)
    sync = _household(hass).sync
    [entry] = sync.possibly_given
    assert entry["platform"] == "Xbox" and "pending" not in entry
    # Microsoft applied it: Hearth's own, no parent's grant
    freezer.tick(timedelta(minutes=2))
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until)
    await sync.async_pending_tick()
    assert sync.possibly_given == []
    await _bonus(hass, "all", 0)
    assert grants == []
    assert calls["cancel_time_bonus"] == []


async def test_extra_time_refused_before_it_went_out_leaves_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    def install(h: HomeAssistant) -> dict:
        calls = _upstream(h)
        given: list[ServiceCall] = []

        async def refuse(call: ServiceCall):
            given.append(call)
            raise ServiceValidationError("not taken")

        h.services.async_register(FS, "add_time_bonus", refuse, supports_response=SupportsResponse.OPTIONAL)
        return {**calls, "add_time_bonus": given}

    await _failed_extra_time(hass, hass_client_no_auth, freezer, install)
    assert _household(hass).sync.possibly_given == []


async def test_a_write_under_way_at_a_restart_is_cut_off_and_watched(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _failed_extra_time(hass, hass_client_no_auth, freezer, lambda h: _upstream(h, fail_bonus=True))
    sync = _household(hass).sync
    sync.possibly_given[0]["pending"] = True  # stored while its call ran
    await sync.async_flush()
    sync.possibly_given = []
    await sync.async_load()
    [entry] = sync.possibly_given
    assert "pending" not in entry
    freezer.tick(timedelta(minutes=11))
    await sync.async_pending_tick()
    assert sync.possibly_given == []


async def test_a_request_approval_cut_off_may_have_gone_through(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, _ = await _held_on_upstream(hass, hass_client_no_auth, freezer)
    asked = async_capture_events(hass, "hearth_more_time_requested")
    hass.bus.async_fire(
        f"{FS}_request",
        {"account_id": "123456", "request_id": "r1", "platform": "Xbox", "type": "screenTime", "requested_time": 1800},
    )
    await hass.async_block_till_done()
    approvals = _cut_off(hass, FS, "approve_request")
    with contextlib.suppress(asyncio.CancelledError):
        await hass.services.async_call(
            "hearth", "answer_request", {"request_id": asked[0].data["id"], "minutes": 30}, blocking=True
        )
    await hass.async_block_till_done()
    assert len(approvals) == 1
    sync = _household(hass).sync
    assert [(e["why"], e["platform"], e.get("pending")) for e in sync.possibly_given] == [("ask:r1", "Xbox", None)]
    # Microsoft shows it: Hearth's approval after all, kept, never cancelled
    until = (dt_util.now() + timedelta(minutes=30)).replace(microsecond=0)
    freezer.tick(timedelta(minutes=1))
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await sync.async_pending_tick()
    assert sync.possibly_given == [] and calls["cancel_time_bonus"] == []


async def test_a_request_approval_refused_before_it_went_out_leaves_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _held_on_upstream(hass, hass_client_no_auth, freezer)
    asked = async_capture_events(hass, "hearth_more_time_requested")
    hass.bus.async_fire(
        f"{FS}_request",
        {"account_id": "123456", "request_id": "r1", "platform": "Xbox", "type": "screenTime", "requested_time": 1800},
    )
    await hass.async_block_till_done()
    hass.services.async_remove(FS, "approve_request")
    await hass.services.async_call("hearth", "answer_request", {"request_id": asked[0].data["id"], "minutes": 30}, blocking=True)
    await hass.async_block_till_done()
    assert _household(hass).sync.possibly_given == []


# b) Family Safety app pauses


def _applications(hass: HomeAssistant, paused: dict[str, str] | None = None, **attrs) -> None:
    """Sam's Family Safety Applications sensor, with Family Safety's own record of its pauses (app_id rows)."""
    hass.states.async_set(
        APPS, "1",
        {"user_id": 123456, "applications": [{"app_id": VIDEO, "app_name": "Video", "blocked": bool(paused)}],
         "paused_apps": [{"app_id": a, "app_name": a, "paused": who} for a, who in (paused or {}).items()], **attrs},
    )


async def _sam_with_video_on_family_safety(hass: HomeAssistant, hass_client_no_auth) -> None:
    async_mock_service(hass, FS, "lock_platform")
    async_mock_service(hass, FS, "unlock_platform")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    _applications(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _video_apps(hass, [VIDEO])
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})


async def test_a_pause_cut_off_is_possibly_held_and_resumed_when_time_comes_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused = _cut_off(hass, FS, "pause_app", first_only=False)
    resumed = async_mock_service(hass, FS, "resume_app")
    await _sam_with_video_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "video", 10)
    # Each pass pauses it again (a hold of an app possibly held): every call cut off
    assert paused and all(c.data["apps"] == [VIDEO] for c in paused)
    held = _household(hass).enforcement.held[KEY]
    assert held.restore[FS_MAYBE_PAUSED] == [VIDEO] and VIDEO not in held.items
    assert VIDEO in enforce._holding(held)
    # Not used as Hearth's block either: a block or unblock waits while the pause may hold it
    assert VIDEO in _household(hass).blocks._fs_held("person.sam")

    await _bonus(hass, "video", 30)
    assert [c.data["apps"] for c in resumed] == [[VIDEO]]
    assert FS_MAYBE_PAUSED not in _household(hass).enforcement.held.get(KEY, Held()).restore


async def test_a_pause_refused_before_it_went_out_leaves_nothing_held(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    async def refuse(call: ServiceCall):
        raise ServiceValidationError("not taken")

    hass.services.async_register(FS, "pause_app", refuse)
    resumed = async_mock_service(hass, FS, "resume_app")
    await _sam_with_video_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "video", 10)
    held = _household(hass).enforcement.held[KEY]
    assert FS_MAYBE_PAUSED not in held.restore and enforce._holding(held) == set()
    await _bonus(hass, "video", 30)
    assert resumed == []


async def _resume_fails(hass: HomeAssistant, hass_client_no_auth, freezer) -> list[ServiceCall]:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    async_mock_service(hass, FS, "pause_app")
    resumed: list[ServiceCall] = []

    async def resume(call: ServiceCall):
        resumed.append(call)
        if len(resumed) == 1:
            raise HomeAssistantError("Microsoft didn't answer")
        return {"resumed": call.data["apps"], "failed": {}}

    hass.services.async_register(FS, "resume_app", resume, supports_response=SupportsResponse.OPTIONAL)
    await _sam_with_video_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "video", 10)
    await _bonus(hass, "video", 30)
    assert len(resumed) == 1
    held = _household(hass).enforcement.held[KEY]
    assert VIDEO not in held.items and held.restore[FS_MAYBE_PAUSED] == [VIDEO]
    return resumed


async def test_a_resume_that_failed_is_sorted_by_family_safety_s_own_pause_record(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    resumed = await _resume_fails(hass, hass_client_no_auth, freezer)
    # Family Safety still holds it by its pause: held as before, and let go of again
    _applications(hass, {VIDEO: "ours"})
    freezer.tick(timedelta(minutes=6))
    await _bonus(hass, "video", 0)
    assert len(resumed) == 2
    assert FS_MAYBE_PAUSED not in _household(hass).enforcement.held.get(KEY, Held()).restore


async def test_a_resume_that_failed_but_went_through_needs_nothing_more(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    resumed = await _resume_fails(hass, hass_client_no_auth, freezer)
    _applications(hass, {})  # no pause of Family Safety's left
    freezer.tick(timedelta(minutes=6))
    await _bonus(hass, "video", 0)
    assert len(resumed) == 1
    held = _household(hass).enforcement.held.get(KEY, Held())
    assert FS_MAYBE_PAUSED not in held.restore and enforce._holding(held) == set()


async def test_a_resume_that_failed_stays_possibly_held_while_the_list_is_cut_short(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    resumed = await _resume_fails(hass, hass_client_no_auth, freezer)
    _applications(hass, {}, truncated=True)
    freezer.tick(timedelta(minutes=6))
    await _bonus(hass, "video", 0)
    # Not sorted: still possibly held, so letting go resumes it again (harmless for an app that isn't paused)
    assert len(resumed) == 2


async def test_hearth_s_own_pause_is_no_parent_s_block_by_family_safety_s_app_id_rows(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Family Safety's paused_apps rows name the app by app_id: a pause of Hearth's ("ours") isn't a parent's block."""
    async_mock_service(hass, FS, "pause_app")
    async_mock_service(hass, FS, "resume_app")
    await _sam_with_video_on_family_safety(hass, hass_client_no_auth)
    _applications(hass, {VIDEO: "ours"})
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": VIDEO}, blocking=True, return_response=True
    )
    assert [b for b in explained["blocked_by"] if b["kind"] == "blocked_app"] == []


async def test_a_family_safety_pause_of_hearth_s_left_behind_is_released(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Safety still shows Hearth's pause ("ours") after Hearth let go: hearth.release_stray_pauses resumes it,
    never an app Hearth didn't pause, one a parent unblocked since, or one Hearth holds."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    async_mock_service(hass, FS, "pause_app")
    resumed = async_mock_service(hass, FS, "resume_app")
    await _sam_with_video_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "video", 10)
    await _bonus(hass, "video", 30)
    assert len(resumed) == 1
    # The resume didn't take: Family Safety still holds it by Hearth's pause; another app is a parent's pause
    _applications(hass, {VIDEO: "ours", "x:other": "ours", "x:unblocked": "parent"})

    async def release(dry_run: bool) -> dict:
        return await hass.services.async_call(
            DOMAIN, "release_stray_pauses", {"person": "person.sam", "dry_run": dry_run}, blocking=True,
            return_response=True,
        )

    assert "a moment ago" in (await release(True))["family_safety"]["error"]
    freezer.tick(timedelta(minutes=4))
    answer = await release(True)
    assert answer["family_safety"] == {"apps": [VIDEO], "dry_run": True} and len(resumed) == 1
    answer = await release(False)
    assert answer["family_safety"] == {"apps": [VIDEO], "failed": {}}
    assert [c.data for c in resumed[1:]] == [{"entity_id": FAMILY_SAFETY, "apps": [VIDEO]}]
    # A list cut short releases nothing
    _applications(hass, {VIDEO: "ours"}, truncated=True)
    assert "cut short" in (await release(False))["family_safety"]["error"]


# c) Family Link bonus


async def test_a_family_link_bonus_cut_off_is_hearth_s_and_reset_when_the_allow_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = _cut_off(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 10)
    allow_id = await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    assert [c.data["bonus_minutes"] for c in added] == [50]
    household = _household(hass)
    assert household.sync.own_bonus() == {"dev1": 50}
    [entry] = household.sync.fl_pending
    assert "pending" not in entry
    # It went through: the phone shows it, it's Hearth's (no parent's grant) and reset with the allow
    _phone(hass, bonus=50)
    await household.sync.async_pending_tick()
    assert household.sync.fl_pending == []
    await _bonus(hass, "all", 0)
    assert household.grants.of("person.sam") == []
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_a_family_link_bonus_that_failed_and_never_showed_is_taken_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))

    async def fail(call: ServiceCall):
        raise HomeAssistantError("Family Link did not add the time bonus")

    hass.services.async_register("familylink", "add_time_bonus", fail)
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 10)
    await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    sync = _household(hass).sync
    assert sync.own_bonus() == {"dev1": 50} and len(sync.fl_pending) == 1
    freezer.tick(timedelta(minutes=5))
    await sync.async_pending_tick()
    assert sync.own_bonus() == {"dev1": 50}
    freezer.tick(timedelta(minutes=6))
    await sync.async_pending_tick()
    assert sync.own_bonus() == {} and sync.fl_pending == []
    assert all(not r["devices"] for r in sync._given.values())


async def test_a_family_link_bonus_refused_before_it_went_out_is_not_hearth_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))

    async def refuse(call: ServiceCall):
        raise ServiceValidationError("not taken")

    hass.services.async_register("familylink", "add_time_bonus", refuse)
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 10)
    await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    sync = _household(hass).sync
    assert sync.own_bonus() == {} and sync.fl_pending == []
