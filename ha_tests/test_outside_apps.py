"""App limits loosened outside Hearth (outside_apps.py): an unblock, a raised or removed limit, or Always allowed (a
Switch's allow list) made in Family Link, Family Safety or Nintendo is told to the adults; Hearth's own changes and
tightening are not."""

from homeassistant.core import HomeAssistant, ServiceCall
from pytest_homeassistant_custom_component.common import async_mock_service
from test_app_blocks import CHILD, _call, _household, _recompute, _sam, settled  # noqa: F401 - fixture

from custom_components.hearth import attention, outside_apps

APP = "com.example.pins"
OTHER = "com.example.other"
VIDEO = "com.example.video"


def _set(hass: HomeAssistant, installed, blocked=(), limits=None, always=(), paused=()) -> None:
    limits = limits or {}
    free = [p for p in installed if p not in blocked and p not in limits and p not in always]
    hass.states.async_set("sensor.sam_blocked_apps", str(len(blocked)),
                          {"child_id": CHILD, "apps": [{"package": p, "name": "Pins"} for p in blocked]})
    hass.states.async_set("sensor.sam_apps_without_limits", str(len(free)),
                          {"child_id": CHILD, "apps": [{"package": p} for p in free]})
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits", str(len(limits)),
        {"child_id": CHILD, "apps": [{"package": p, "limit_minutes": m, "enabled": True} for p, m in limits.items()],
         "paused_apps": [{"package": p} for p in paused]},
    )
    hass.states.async_set("sensor.sam_always_allowed_apps", str(len(always)),
                          {"child_id": CHILD, "apps": [{"package": p} for p in always]})


def _notices(hass: HomeAssistant) -> dict:
    return {k: i for k, i in attention._items(hass).items() if k.startswith("outside_app_")}


async def _look(hass: HomeAssistant, **lists) -> dict:
    _set(hass, **lists)
    await _recompute(hass)
    return _notices(hass)


async def test_unblock_in_family_link_is_told_with_block_again(hass: HomeAssistant, hass_client_no_auth) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[APP, OTHER], blocked=[APP])
    events = []
    hass.bus.async_listen(outside_apps.EVENT, events.append)
    assert await _look(hass, installed=[APP, OTHER], blocked=[APP]) == {}

    notices = await _look(hass, installed=[APP, OTHER])
    item = notices[f"outside_app_person.sam_family_link_{APP}"]
    assert "was unblocked in Family Link, not by Hearth" in item.text
    assert item.text.startswith("Pins ")
    assert [a.label for a in item.actions] == ["Block again"]
    assert item.actions[0].service == "hearth.block_outside_app"
    assert item.actions[0].data == {"source": "person.sam|family_link", "app": APP}
    assert [(e.data["change"], e.data["provider"]) for e in events] == [("unblocked", "Family Link")]
    assert not calls["block"]
    # The button: Hearth's own block in Family Link
    await _call(hass, "block_outside_app", item.actions[0].data)
    assert [c.data["package_name"] for c in calls["block"]] == [APP]


async def test_hearths_own_unblock_is_not_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[APP])
    await _call(hass, "block_app", {"people": ["person.sam"], "app": APP})
    assert [c.data["package_name"] for c in calls["block"]] == [APP]
    await _look(hass, installed=[APP], blocked=[APP])

    await _call(hass, "unblock_app", {"people": ["person.sam"], "app": APP})
    assert [c.data["package_name"] for c in calls["unblock"]] == [APP]
    assert await _look(hass, installed=[APP]) == {}


async def test_limits_raised_removed_and_always_allowed_are_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    await _sam(hass, hass_client_no_auth, installed=[APP, OTHER, VIDEO])
    await _look(hass, installed=[APP, OTHER, VIDEO], limits={APP: 30, VIDEO: 60})

    notices = await _look(hass, installed=[APP, OTHER, VIDEO], limits={APP: 90}, always=[OTHER])
    assert "went from 30 to 90 minutes" in notices[f"outside_app_person.sam_family_link_{APP}"].text
    assert "(60 minutes) was taken off" in notices[f"outside_app_person.sam_family_link_{VIDEO}"].text
    assert "Always allowed" in notices[f"outside_app_person.sam_family_link_{OTHER}"].text


async def test_tightening_uninstalls_and_pauses_are_not_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    await _sam(hass, hass_client_no_auth, installed=[APP, OTHER, VIDEO])
    await _look(hass, installed=[APP, OTHER, VIDEO], blocked=[OTHER], limits={APP: 60, VIDEO: 30})
    # Lower limit, a new block, an uninstalled blocked app: nothing loosened
    assert await _look(hass, installed=[APP, VIDEO], limits={APP: 15, VIDEO: 30}, blocked=[VIDEO]) == {}
    # Hearth's pause hides an app's limit, and its resume puts it back: neither is told
    await _look(hass, installed=[APP, VIDEO], limits={APP: 1}, paused=[APP], blocked=[VIDEO])
    assert await _look(hass, installed=[APP, VIDEO], blocked=[VIDEO]) == {}


async def test_nothing_told_while_a_list_is_cut_short(hass: HomeAssistant, hass_client_no_auth) -> None:
    await _sam(hass, hass_client_no_auth, installed=[APP], blocked=[APP])
    await _look(hass, installed=[APP], blocked=[APP])
    hass.states.async_set("sensor.sam_blocked_apps", "0", {"child_id": CHILD, "apps": [], "truncated": True})
    await _recompute(hass)
    assert _notices(hass) == {}


async def test_family_safety_unblock_and_limit_are_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    from test_sources import _option

    await _sam(hass, hass_client_no_auth, installed=[APP])
    hass.states.async_set("sensor.sam_family_safety", "ok", {"user_id": "ms-sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": "sensor.sam_family_safety"})

    def fs(racer_blocked: bool, chat_limit, paused=()):
        hass.states.async_set("sensor.sam_applications", "2", {
            "user_id": "ms-sam",
            "applications": [
                {"app_id": "x:racer", "app_name": "Racer", "blocked": racer_blocked, "limit_minutes": None},
                {"app_id": "x:chat", "app_name": "Chat", "blocked": False, "limit_minutes": chat_limit,
                 "limit_enabled": True},
            ],
            "paused_apps": [{"package": p, "paused": "ours"} for p in paused],
        })

    fs(True, 30)
    await _recompute(hass)
    assert _notices(hass) == {}
    fs(False, 60)
    await _recompute(hass)
    notices = _notices(hass)
    racer = notices["outside_app_person.sam_fs_sensor.sam_applications_x_racer"]
    assert racer.text.startswith("Racer was unblocked in Family Safety, not by Hearth")
    assert [a.label for a in racer.actions] == ["Block again"]
    blocked = async_mock_service(hass, "microsoft_family_safety", "block_app")
    await _call(hass, "block_outside_app", racer.actions[0].data)
    assert [(c.data["entity_id"], c.data["app_id"]) for c in blocked] == [("sensor.sam_applications", "x:racer")]
    assert "went from 30 to 60 minutes in Family Safety" in notices["outside_app_person.sam_fs_sensor.sam_applications_x_chat"].text


async def test_a_switch_game_put_on_the_allow_list_is_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    from homeassistant.core import SupportsResponse
    from test_enforce import NINTENDO_LIMIT, _add_enforcer, _nintendo_switch

    await _sam(hass, hass_client_no_auth)
    _nintendo_switch(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": NINTENDO_LIMIT})
    allowed: set[str] = set()

    async def listing(call: ServiceCall):
        return {"applications": [
            {"application_id": "0100AAA", "name": "Blaster Arena", "allowed": "0100AAA" in allowed},
            {"application_id": "0100BBB", "name": "Puzzle Pals", "allowed": "0100BBB" in allowed},
        ]}

    hass.services.async_register("nintendo_parental_controls", "list_applications", listing,
                                 supports_response=SupportsResponse.ONLY)
    outside = _household(hass).outside_apps
    outside._nintendo_at = None
    await _recompute(hass)
    assert _notices(hass) == {}

    allowed.add("0100AAA")
    outside._nintendo_at = None
    await _recompute(hass)
    [item] = _notices(hass).values()
    assert item.text.startswith("Blaster Arena was put on the allow list (it starts whatever its age rating) on ")
    assert "in Nintendo, not by Hearth" in item.text
    assert [a.label for a in item.actions] == ["Take off allow list"]
    taken: list[ServiceCall] = []

    async def set_allowed(call: ServiceCall):
        taken.append(call)

    hass.services.async_register("nintendo_parental_controls", "set_app_allowed", set_allowed)
    await _call(hass, "block_outside_app", item.actions[0].data)
    assert [(c.data["application_id"], c.data["allowed"]) for c in taken] == [("0100AAA", False)]

    # Not looked at again before it's due
    allowed.add("0100BBB")
    await _recompute(hass)
    assert len(_notices(hass)) == 1


async def test_hearths_own_nintendo_allow_is_not_told(hass: HomeAssistant, hass_client_no_auth) -> None:
    from homeassistant.core import SupportsResponse
    from test_enforce import NINTENDO_LIMIT, _add_enforcer, _nintendo_switch

    from custom_components.hearth.activity import call_service

    await _sam(hass, hass_client_no_auth)
    _nintendo_switch(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": NINTENDO_LIMIT})
    allowed: set[str] = set()

    async def listing(call: ServiceCall):
        return {"applications": [{"application_id": "0100AAA", "name": "Blaster Arena", "allowed": bool(allowed)}]}

    async def set_allowed(call: ServiceCall):
        allowed.add(call.data["application_id"])

    hass.services.async_register("nintendo_parental_controls", "list_applications", listing,
                                 supports_response=SupportsResponse.ONLY)
    hass.services.async_register("nintendo_parental_controls", "set_app_allowed", set_allowed)
    outside = _household(hass).outside_apps
    outside._nintendo_at = None
    await _recompute(hass)
    await call_service(hass, "nintendo_parental_controls", "set_app_allowed",
                       {"device_id": "d", "application_id": "0100AAA", "allowed": True}, blocking=True)
    outside._nintendo_at = None
    await _recompute(hass)
    assert _notices(hass) == {}


async def test_explain_names_a_parent_s_own_block(hass: HomeAssistant, hass_client_no_auth) -> None:
    from test_sources import _option

    await _sam(hass, hass_client_no_auth, installed=[APP, OTHER])
    _set(hass, installed=[APP, OTHER], blocked=[APP])
    await _recompute(hass)
    await _call(hass, "allow", {"people": ["person.sam"], "app": APP})

    why = await _call(hass, "explain", {"person": "person.sam", "app": APP}, True)
    assert why["allowed"] is False
    assert {"kind": "blocked_app", "by": "family_link", "provider": "Family Link", "app": APP, "why": ["parent"],
            "until": None} in why["blocked_by"]
    assert (await _call(hass, "explain", {"person": "person.sam", "app": OTHER}, True))["allowed"] is True

    hass.states.async_set("sensor.sam_family_safety", "ok", {"user_id": "ms-sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": "sensor.sam_family_safety"})
    hass.states.async_set("sensor.sam_applications", "1", {"user_id": "ms-sam", "applications": [
        {"app_id": "x:racer", "app_name": "Racer", "blocked": True, "limit_minutes": None}]})
    await _recompute(hass)
    racer = await _call(hass, "explain", {"person": "person.sam", "app": "x:racer"}, True)
    assert racer["allowed"] is False
    assert [b["by"] for b in racer["blocked_by"] if b["kind"] == "blocked_app"] == ["sensor.sam_applications"]


async def test_hearths_own_block_is_explained_once(hass: HomeAssistant, hass_client_no_auth) -> None:
    await _sam(hass, hass_client_no_auth, installed=[APP])
    await _call(hass, "block_app", {"people": ["person.sam"], "app": APP})
    _set(hass, installed=[APP], blocked=[APP])
    await _recompute(hass)
    why = await _call(hass, "explain", {"person": "person.sam", "app": APP}, True)
    assert [b["by"] for b in why["blocked_by"] if b["kind"] == "blocked_app"] == ["hearth.block_app"]


async def test_the_button_only_takes_lists_hearth_looks_at(hass: HomeAssistant, hass_client_no_auth) -> None:
    import pytest
    from homeassistant.exceptions import ServiceValidationError

    await _sam(hass, hass_client_no_auth, installed=[APP])
    await _look(hass, installed=[APP])
    for data in ({"source": "person.nobody|family_link", "app": APP}, {"source": "nintendo:other", "app": "0100"},
                 {"source": "person.sam|family_link", "app": "com.android.settings"}):
        with pytest.raises(ServiceValidationError):
            await _call(hass, "block_outside_app", data)
