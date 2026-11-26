"""Apps Hearth keeps Always allowed in Family Link (always_allowed.py): Glint and Glint Phone by default, written once
an app is installed, kept before the call, tried again with a doubling wait, never fighting a parent's change, put
back when taken off the list; Hearth's own holds never pause them; the bedtime setting is left alone unless chosen."""

import asyncio
from datetime import timedelta

import pytest

from homeassistant.core import Context, HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError, Unauthorized
from homeassistant.helpers import entity_registry as er
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import always_allowed, enforce
from custom_components.hearth.const import DOMAIN
from test_app_blocks import CHILD, FAMILY_LINK, GAME, _household, _recompute, _sam

SAM = "person.sam"
GLINT = "com.thesiegs.glint"
GLINT_PHONE = "com.thesiegs.glint.phone"
KEPT = "com.example.audiobooks"
DOWNTIME_SWITCH = "switch.sam_unlimited_apps_during_downtime"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _lists(
    hass: HomeAssistant,
    free: list[str] = (),
    always: list[str] = (),
    limits: dict[str, int] | None = None,
    blocked: list[str] = (),
) -> None:
    """Sam's Family Link app lists: [free] without limits, [always] Always allowed, [limits] with a time limit."""
    limits = limits or {}
    hass.states.async_set("sensor.sam_blocked_apps", str(len(blocked)), {"child_id": CHILD, "apps": [{"package": p} for p in blocked]})
    hass.states.async_set("sensor.sam_apps_without_limits", str(len(free)), {"child_id": CHILD, "apps": [{"package": p} for p in free]})
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits", str(len(limits)),
        {"child_id": CHILD, "apps": [{"package": p, "limit_minutes": m, "enabled": True} for p, m in limits.items()]},
    )
    hass.states.async_set("sensor.sam_always_allowed_apps", str(len(always)), {"child_id": CHILD, "apps": [{"package": p} for p in always]})


async def _set_up(hass: HomeAssistant, hass_client_no_auth, **lists) -> dict:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    calls["limit"] = async_mock_service(hass, "familylink", "set_app_daily_limit")
    _lists(hass, **{"free": [GAME], **lists})
    await _recompute(hass)
    return calls


async def _call(hass: HomeAssistant, service: str, data: dict, response: bool = False):
    result = await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=response)
    await hass.async_block_till_done()
    return result


def _writes(calls) -> list[tuple[str, int]]:
    return [(c.data["package_name"], c.data["minutes"]) for c in calls]


def _kid(hass: HomeAssistant) -> dict:
    [kid] = _household(hass).always.page()["kids"]
    return kid


def _states(hass: HomeAssistant) -> dict[str, str]:
    return {a["app"]: a["state"] for a in _kid(hass)["apps"]}


async def _later(hass: HomeAssistant, freezer, minutes: float) -> None:
    freezer.tick(timedelta(minutes=minutes))
    await _recompute(hass)


async def test_glint_is_made_always_allowed_once_installed_and_only_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _set_up(hass, hass_client_no_auth)
    # Not installed: nothing to write (Family Link takes it only for an installed app)
    assert calls["limit"] == []
    assert _states(hass) == {GLINT: "not_installed", GLINT_PHONE: "not_installed"}

    _lists(hass, free=[GAME, GLINT])
    await _recompute(hass)
    assert _writes(calls["limit"]) == [(GLINT, -2)]
    assert calls["limit"][0].data["entity_id"] == FAMILY_LINK
    # Not shown yet: not written again before Family Link had time to show it
    await _later(hass, freezer, 1)
    assert len(calls["limit"]) == 1

    _lists(hass, free=[GAME], always=[GLINT])
    await _recompute(hass)
    assert _states(hass) == {GLINT: "always_allowed", GLINT_PHONE: "not_installed"}
    assert _kid(hass)["apps"][0]["by"] == "hearth"
    await _later(hass, freezer, 60)
    assert len(calls["limit"]) == 1

    # Glint Phone installed later gets it too
    _lists(hass, free=[GAME, GLINT_PHONE], always=[GLINT])
    await _recompute(hass)
    assert _writes(calls["limit"]) == [(GLINT, -2), (GLINT_PHONE, -2)]


async def test_an_app_already_always_allowed_is_done_and_left_as_is_when_taken_off(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, always=[GLINT, GLINT_PHONE])
    assert calls["limit"] == []
    assert {a["app"]: a.get("by") for a in _kid(hass)["apps"]} == {GLINT: "found", GLINT_PHONE: "found"}

    answer = await _call(hass, "always_allow", {"apps": [GLINT_PHONE], "remove": True}, response=True)
    assert answer["always_allowed"] == {GLINT: "kids"}
    await _recompute(hass)
    # Hearth didn't write it: nothing is put back
    assert calls["limit"] == []
    assert [a["app"] for a in _kid(hass)["apps"]] == [GLINT]


async def test_taken_off_the_list_what_hearth_wrote_goes_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, free=[GAME, GLINT_PHONE], limits={GLINT: 45})
    assert sorted(_writes(calls["limit"])) == [(GLINT, -2), (GLINT_PHONE, -2)]
    _lists(hass, free=[GAME], always=[GLINT, GLINT_PHONE])
    await _recompute(hass)

    await _call(hass, "always_allow", {"apps": [GLINT, GLINT_PHONE], "people": [SAM], "remove": True})
    await _recompute(hass)
    # Each back to the setting it had: Glint's 45 minutes, Glint Phone's no limit of its own
    assert sorted(_writes(calls["limit"])[2:]) == [(GLINT, 45), (GLINT_PHONE, -1)]
    _lists(hass, free=[GAME, GLINT_PHONE], limits={GLINT: 45})
    await _recompute(hass)
    assert len(calls["limit"]) == 4
    assert _household(hass).always.records.get(SAM, {}) == {}


async def test_a_parent_s_change_is_kept_until_an_adult_asks_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, free=[GAME, GLINT])
    _lists(hass, free=[GAME], always=[GLINT])
    await _recompute(hass)
    changed = async_capture_events(hass, "hearth_always_allowed_changed")

    # A parent gives Glint a 30-minute limit in the Family Link app: theirs, not written over
    freezer.tick(timedelta(hours=1))
    _lists(hass, free=[GAME], limits={GLINT: 30})
    await _recompute(hass)
    assert len(calls["limit"]) == 1
    assert _states(hass)[GLINT] == "parent_changed"
    assert [e.data for e in changed] == [{"person": SAM, "app": GLINT, "now": "limit of 30 minutes"}]
    [item] = [i for i in _household(hass).hub.attention.items() if "always" in i.key]
    assert [a.service for a in item.actions if a.service] == [f"{DOMAIN}.always_allow"]
    await _later(hass, freezer, 24 * 60)
    assert len(calls["limit"]) == 1 and len(changed) == 1

    # An adult says so: Hearth writes it again
    answer = await _call(hass, "always_allow", {"people": [SAM], "apps": [GLINT]}, response=True)
    assert answer["asked_again"] == [{"person": SAM, "app": GLINT}]
    await _recompute(hass)
    assert _writes(calls["limit"]) == [(GLINT, -2), (GLINT, -2)]


async def test_hearth_s_own_pause_of_the_app_is_no_parent_s_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, free=[GAME, GLINT])
    _lists(hass, free=[GAME], always=[GLINT])
    await _recompute(hass)
    household = _household(hass)
    # A call of Hearth's named Glint (an older Hearth's pause, say): the change is Hearth's, written again
    token = household.activity.begin("familylink.pause_app", {"entity_id": FAMILY_LINK, "packages": [GLINT]})
    household.activity.finish(token)
    _lists(hass, free=[GAME], limits={GLINT: 1})
    await _recompute(hass)
    assert _writes(calls["limit"]) == [(GLINT, -2), (GLINT, -2)]
    assert _states(hass)[GLINT] == "pending"


async def test_a_failed_write_is_hearth_s_and_tried_again_with_a_doubling_wait(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    tried: list[ServiceCall] = []

    async def failing(call: ServiceCall):
        tried.append(call)
        raise HomeAssistantError("Google didn't answer")

    hass.services.async_register("familylink", "set_app_daily_limit", failing)
    _lists(hass, free=[GAME, GLINT])
    await _recompute(hass)
    record = _household(hass).always.records[SAM][GLINT]
    # It may have gone through: Hearth's own (put back if taken off), and its error shown
    assert record["unsure"] and record["wrote"] and record["before"] == -1 and record["tries"] == 1
    assert _kid(hass)["apps"][0]["error"] == "Google didn't answer"
    await _later(hass, freezer, 1)
    assert len(tried) == 1
    await _later(hass, freezer, 1.1)
    assert len(tried) == 2
    # 4 minutes next
    await _later(hass, freezer, 3)
    assert len(tried) == 2
    await _later(hass, freezer, 1.1)
    assert len(tried) == 3
    # Told once after TELL_AFTER tries, not on each one after
    await _later(hass, freezer, 8.1)
    await _later(hass, freezer, 16.1)
    assert len(tried) == 5
    told = [i for i in _household(hass).hub.attention.items() if i.key.startswith("always_allowed_failed")]
    assert len(told) == 1
    assert calls["block"] == []


async def test_a_refusal_before_it_went_out_leaves_nothing_of_hearth_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _sam(hass, hass_client_no_auth, installed=[GAME])

    async def refused(call: ServiceCall):
        raise ServiceValidationError("no such child")

    hass.services.async_register("familylink", "set_app_daily_limit", refused)
    _lists(hass, free=[GAME, GLINT])
    await _recompute(hass)
    record = _household(hass).always.records[SAM][GLINT]
    assert not always_allowed.AlwaysAllowed.ours(record) and "unsure" not in record
    assert record["error"] == "no such child"


async def test_a_write_cut_off_by_a_reload_is_hearth_s_and_never_told_as_a_parent_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam(hass, hass_client_no_auth, installed=[GAME])
    told = async_capture_events(hass, "hearth_outside_app_change")
    _lists(hass, free=[GAME, GLINT], limits={KEPT: 20})
    await _recompute(hass)
    # The outside-change look has seen the lists once
    seen: list[ServiceCall] = []

    async def cut_off(call: ServiceCall):
        seen.append(call)
        raise asyncio.CancelledError

    hass.services.async_register("familylink", "set_app_daily_limit", cut_off)
    await _recompute(hass)
    record = _household(hass).always.records[SAM][GLINT]
    # Marked before the call, and left so by the cut-off
    assert record["writing"] and record["before"] == -1
    # Saved: the reload's new household reads it back as possibly written
    await hass.config_entries.async_reload(hass.config_entries.async_entries(DOMAIN)[0].entry_id)
    await hass.async_block_till_done()
    freezer.tick(timedelta(hours=2))
    _lists(hass, free=[GAME], always=[GLINT], limits={KEPT: 20})
    await _recompute(hass)
    record = _household(hass).always.records[SAM][GLINT]
    assert record["by"] == "hearth" and record["unsure"]
    assert told == []


async def test_an_app_made_always_allowed_that_hearth_keeps_is_not_told(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Another writer (an adult's one-time call, the Family Link app) makes Glint Always allowed: that's what Hearth
    wants for the kid, so the adults aren't told. Any other app made Always allowed still is."""
    await _sam(hass, hass_client_no_auth, installed=[GAME])
    told = async_capture_events(hass, "hearth_outside_app_change")
    _lists(hass, free=[GAME, GLINT])
    await _recompute(hass)
    freezer.tick(timedelta(hours=2))
    _lists(hass, always=[GAME, GLINT])
    await _recompute(hass)
    assert [(e.data["app"], e.data["change"]) for e in told] == [(GAME, "always_allowed")]


async def test_hearth_never_pauses_or_blocks_an_app_it_keeps_always_allowed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, free=[GAME, KEPT, GLINT])
    await _call(hass, "always_allow", {"apps": [KEPT], "people": [SAM]})
    household = _household(hass)
    assert household.always.apps_for(SAM) == {GLINT, GLINT_PHONE, KEPT}
    # Glint is never paused by any of Hearth's holds, nor blocked
    assert GLINT in enforce.NEVER_PAUSED and GLINT_PHONE in enforce.NEVER_PAUSED
    with pytest.raises(ServiceValidationError, match="never blocks"):
        await _call(hass, "block_app", {"app": GLINT})
    with pytest.raises(ServiceValidationError, match="always allowed"):
        await _call(hass, "block_app", {"app": KEPT, "people": [SAM]})
    # ... and the other way round: an app Hearth blocks isn't made always allowed
    await _call(hass, "block_app", {"app": GAME, "people": [SAM]})
    with pytest.raises(ServiceValidationError, match="unblock them first"):
        await _call(hass, "always_allow", {"apps": [GAME]})

    # An adult's pause of the app (or of everything) never pauses it through Family Link
    pauses = len(calls["pause"])
    await _call(hass, "pause", {"people": [SAM], "app": KEPT, "minutes": 60})
    assert not any(KEPT in (c.data.get("packages") or [c.data.get("package_name")]) for c in calls["pause"][pauses:])
    assert KEPT in household._exempt_of()(SAM)


async def test_who_may_change_the_list(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user
) -> None:
    await _set_up(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError, match="Only Android apps"):
        await _call(hass, "always_allow", {"apps": ["not an app"]})
    with pytest.raises(ServiceValidationError, match="kids"):
        await _call(hass, "always_allow", {"apps": [KEPT], "people": ["person.someone"]})
    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "always_allow", {"apps": [KEPT]}, blocking=True, context=Context(user_id=hass_read_only_user.id)
        )


def test_the_option_after_each_change() -> None:
    kids = ["person.alex", "person.sam"]
    start = dict(always_allowed.DEFAULT_APPS)
    assert always_allowed.changed_option(start, [KEPT], ["person.sam"], kids, False) == {**start, KEPT: ["person.sam"]}
    assert always_allowed.changed_option(start, [GLINT], ["person.sam"], kids, True) == {
        GLINT: ["person.alex"], GLINT_PHONE: "kids"
    }
    assert always_allowed.changed_option(start, [GLINT], None, kids, True) == {GLINT_PHONE: "kids"}
    assert always_allowed.changed_option({KEPT: ["person.sam"]}, [KEPT], ["person.sam"], kids, True) == {}
    assert always_allowed.configured({}) == start
    assert always_allowed.configured({"always_allowed": {}}) == {}


# Stray pauses and the pause of every other app


async def test_release_stray_pauses_leaves_an_always_allowed_app_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, always=[GLINT])
    preview = await _call(hass, "release_stray_pauses", {"person": SAM, "dry_run": True}, response=True)
    assert GLINT not in preview["apps"]
    assert calls["limit"] == []


async def test_pausing_every_other_app_leaves_the_kept_apps(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from test_away_messages import _held, _opened
    from test_messaging import CHROME, LATE
    from test_presence import sam_out_of_time

    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer, always_allowed={GAME: "kids"})
    await _opened(hass, freezer)
    held = set(_held(hass))
    assert "Devices" not in held and {CHROME, LATE} <= held
    assert GAME not in held
    assert not any(GAME in c.data["packages"] for c in calls["pause"])


# Bedtime: "Allow apps with unlimited time during downtime"


def _downtime(hass: HomeAssistant, on: bool) -> None:
    er.async_get(hass).async_get_or_create(
        "switch", "familylink", f"familylink_{CHILD}_downtime_unlimited_apps", suggested_object_id="sam_unlimited_apps_during_downtime"
    )
    hass.states.async_set(DOWNTIME_SWITCH, "on" if on else "off", {"child_id": CHILD})


async def test_bedtime_setting_is_left_alone_unless_chosen_and_explain_says_glint_stops(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _set_up(hass, hass_client_no_auth, always=[GLINT])
    downtime = async_mock_service(hass, "familylink", "set_downtime_unlimited_apps")
    _downtime(hass, False)
    await _recompute(hass)
    assert downtime == []
    explained = _household(hass).explain(SAM, GLINT)["always_allowed"]
    assert explained["by"] == "hearth" and explained["state"] == "always_allowed"
    assert explained["stopped_at_bedtime"] is True and "bedtime stops it" in explained["text"]
    assert _kid(hass)["bedtime"] == {"on": False, "kept_by_hearth": False}

    # Chosen: switched on once, kept as Hearth's
    answer = await _call(hass, "always_allow", {"bedtime": True}, response=True)
    assert answer["bedtime"] is True
    await _recompute(hass)
    assert [c.data for c in downtime] == [{"entity_id": FAMILY_LINK, "allow": True}]
    _downtime(hass, True)
    await _recompute(hass)
    assert _household(hass).explain(SAM, GLINT)["always_allowed"]["stopped_at_bedtime"] is False

    # A parent switches it off in Family Link: theirs until an adult asks again
    _downtime(hass, False)
    await _later(hass, freezer, 60)
    assert len(downtime) == 1
    assert _kid(hass)["bedtime"]["parent"]["now"] == "off"
    await _call(hass, "always_allow", {"bedtime": True})
    await _recompute(hass)
    assert len(downtime) == 2
    _downtime(hass, True)
    await _recompute(hass)

    # Turned off again: what Hearth switched on goes back off
    await _call(hass, "always_allow", {"bedtime": False})
    await _recompute(hass)
    assert [c.data["allow"] for c in downtime] == [True, True, False]
    assert calls["limit"] == []


async def test_explain_names_a_parent_s_always_allowed_app_and_nothing_for_others(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _set_up(hass, hass_client_no_auth, free=[GAME], always=[KEPT])
    household = _household(hass)
    assert household.explain(SAM, KEPT)["always_allowed"]["by"] == "family_link"
    assert "always_allowed" not in household.explain(SAM, GAME)
