"""hearth.release_stray_pauses (stray_pauses.py): apps left at Hearth's 1-minute Family Link pause with no record of
it go back to no app limit, or to the minutes given; nothing else is touched, and the adults aren't told."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import ServiceValidationError
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_app_blocks import CHILD, CHROME, GAME, _call, _household, _sam, settled  # noqa: F401

SAM = "person.sam"
NOTES = "com.example.notes"
VIDEO = "com.example.video"
PARENTS = "com.example.parents_limit"
STILL = "com.example.still_paused"


def _limited(hass: HomeAssistant, apps: dict[str, int], paused=(), truncated: bool = False) -> None:
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits",
        str(len(apps)),
        {
            "child_id": CHILD,
            "apps": [{"package": p, "limit_minutes": m} for p, m in apps.items()],
            "paused_apps": [{"package": p, "pause_intact": True, "prior": -1} for p in paused],
            **({"truncated": True} if truncated else {}),
        },
    )


async def _set_up(hass: HomeAssistant, hass_client_no_auth):
    await _sam(hass, hass_client_no_auth, [CHROME, GAME, NOTES, VIDEO, PARENTS, STILL])
    household = _household(hass)
    # Hearth paused these earlier (its action log); PARENTS it never touched
    household.activity.hold(True, SAM, [CHROME, GAME, NOTES, VIDEO, STILL], "limit", "family_link")
    _limited(hass, {CHROME: 1, GAME: 1, NOTES: 1, VIDEO: 120, PARENTS: 1, STILL: 1}, paused=[STILL])
    return household


async def test_only_hearth_s_unrecorded_1_minute_pauses_go_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass, hass_client_no_auth)
    set_limit = async_mock_service(hass, "familylink", "set_app_daily_limit")
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    # VIDEO isn't at 1 minute, PARENTS was never Hearth's, STILL is in Family Link's own record
    assert preview == {"person": SAM, "dry_run": True, "apps": {CHROME: -1, GAME: -1, NOTES: -1}}
    assert set_limit == []

    done = await _call(hass, "release_stray_pauses", {"person": SAM, "limits": {NOTES: 60}}, response=True)
    assert done == {"person": SAM, "dry_run": False, "apps": {CHROME: -1, GAME: -1, NOTES: 60}, "failed": {}}
    assert sorted((c.data["package_name"], c.data["minutes"], c.data["child_id"]) for c in set_limit) == [
        (CHROME, -1, CHILD), (GAME, -1, CHILD), (NOTES, 60, CHILD)
    ]
    # Hearth's own call: not an outside change for the adults
    _limited(hass, {VIDEO: 120, PARENTS: 1, STILL: 1, NOTES: 60}, paused=[STILL])
    household = _household(hass)
    household.outside_apps.check()
    await hass.async_block_till_done()
    assert household.activity.query(SAM, "outside_app_change") == []


async def test_nothing_while_the_list_is_cut_short(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass, hass_client_no_auth)
    _limited(hass, {CHROME: 1}, truncated=True)
    with pytest.raises(ServiceValidationError, match="cut short"):
        await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True})


async def test_an_app_hearth_holds_now_stays_paused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    household = await _set_up(hass, hass_client_no_auth)
    from custom_components.hearth.enforce import Held

    household.enforcement.held[f"family_link|{SAM}"] = Held(items={GAME})
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    assert set(preview["apps"]) == {CHROME, NOTES}
    # One a pause call may have paused (it failed part-way) counts as held too
    household.enforcement.held[f"family_link|{SAM}"] = Held(restore={"maybe_paused": [NOTES]})
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    assert set(preview["apps"]) == {CHROME, GAME}


def _blocked(hass: HomeAssistant, apps: list[str], truncated: bool = False) -> None:
    hass.states.async_set(
        "sensor.sam_blocked_apps",
        str(len(apps)),
        {"child_id": CHILD, "apps": [{"package": p} for p in apps], **({"truncated": True} if truncated else {})},
    )


async def test_a_blocked_app_is_left_alone_and_an_unknown_blocked_list_refuses(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Writing a limit back to a blocked app can lift its block."""
    await _set_up(hass, hass_client_no_auth)
    set_limit = async_mock_service(hass, "familylink", "set_app_daily_limit")
    _blocked(hass, [GAME])
    done = await _call(hass, "release_stray_pauses", {"person": SAM}, response=True)
    assert done["apps"] == {CHROME: -1, NOTES: -1} and done["failed"] == {}
    assert GAME not in [c.data["package_name"] for c in set_limit]
    # Blocked apps cut short: which apps are blocked isn't known
    _blocked(hass, [], truncated=True)
    with pytest.raises(ServiceValidationError, match="blocked apps"):
        await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True})
    # No Blocked apps list at all
    hass.states.async_remove("sensor.sam_blocked_apps")
    with pytest.raises(ServiceValidationError, match="blocked apps"):
        await _call(hass, "release_stray_pauses", {"person": SAM})
    assert len(set_limit) == 2


async def test_a_limit_that_is_off_isn_t_a_pause(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass, hass_client_no_auth)
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits",
        "2",
        {
            "child_id": CHILD,
            "apps": [
                {"package": CHROME, "limit_minutes": 1, "enabled": True},
                {"package": GAME, "limit_minutes": 1, "enabled": False},
            ],
            "paused_apps": [],
        },
    )
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    assert preview["apps"] == {CHROME: -1}


async def test_nothing_right_after_hearth_let_go_of_a_family_link_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The list may still show the pause of an app resumed a moment ago."""
    household = await _set_up(hass, hass_client_no_auth)
    set_limit = async_mock_service(hass, "familylink", "set_app_daily_limit")
    household.activity.hold(False, SAM, [GAME], "limit", "family_link")
    with pytest.raises(ServiceValidationError, match="a moment ago"):
        await _call(hass, "release_stray_pauses", {"person": SAM})
    with pytest.raises(ServiceValidationError, match="a moment ago"):
        await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True})
    assert set_limit == []
    freezer.tick(timedelta(minutes=4))
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    assert set(preview["apps"]) == {CHROME, GAME, NOTES}


async def test_one_call_failing_with_any_error_leaves_the_others_done(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Family Link's own errors (a session that expired) are plain Exceptions, not Home Assistant's."""
    await _set_up(hass, hass_client_no_auth)
    called: list[str] = []

    class SessionExpiredError(Exception):
        pass

    async def set_limit(call: ServiceCall) -> None:
        called.append(call.data["package_name"])
        if call.data["package_name"] == GAME:
            raise SessionExpiredError("Session expired")

    hass.services.async_register("familylink", "set_app_daily_limit", set_limit)
    done = await _call(hass, "release_stray_pauses", {"person": SAM}, response=True)
    assert sorted(called) == [CHROME, GAME, NOTES]
    assert done == {
        "person": SAM, "dry_run": False, "apps": {CHROME: -1, NOTES: -1}, "failed": {GAME: "Session expired"}
    }


async def test_the_answer_comes_back_when_the_sensor_goes_mid_run(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    household = await _set_up(hass, hass_client_no_auth)

    async def set_limit(call: ServiceCall) -> None:
        # Family Link reloading: its sensors are gone before the last call is back
        hass.states.async_remove("sensor.sam_apps_with_time_limits")

    hass.services.async_register("familylink", "set_app_daily_limit", set_limit)
    done = await _call(hass, "release_stray_pauses", {"person": SAM}, response=True)
    assert done == {"person": SAM, "dry_run": False, "apps": {CHROME: -1, GAME: -1, NOTES: -1}, "failed": {}}

    # Nor does a refresh that can't be asked for lose the answer
    _limited(hass, {CHROME: 1}, paused=[])

    def broken(_entity_id) -> None:
        raise RuntimeError("no refresh")

    monkeypatch.setattr(household.enforcement, "refresh_soon", broken)
    done = await _call(hass, "release_stray_pauses", {"person": SAM}, response=True)
    assert done["apps"] == {CHROME: -1} and done["failed"] == {}
