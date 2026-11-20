"""App limits loosened outside Hearth (outside_apps.py): an unblock, a raised or removed limit, or Always allowed made
in the Family Link app is told to the adults; Hearth's own changes and tightening are not."""

from homeassistant.core import HomeAssistant

from custom_components.hearth import attention, outside_apps
from test_app_blocks import CHILD, _call, _household, _recompute, _sam, settled  # noqa: F401 - fixture

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
    return {k: i for k, i in attention._items(hass).items() if k.startswith("outside_app_")}  # noqa: SLF001


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
    item = notices[f"outside_app_person.sam_{APP}"]
    assert "was unblocked in Family Link, not by Hearth" in item.text
    assert item.text.startswith("Pins ")
    assert [a.label for a in item.actions] == ["Block again"]
    assert item.actions[0].service == "hearth.block_app"
    assert item.actions[0].data == {"people": ["person.sam"], "app": APP}
    assert [e.data["change"] for e in events] == ["unblocked"]
    assert not calls["block"]


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
    assert "went from 30 to 90 minutes" in notices[f"outside_app_person.sam_{APP}"].text
    assert "(60 minutes) was taken off" in notices[f"outside_app_person.sam_{VIDEO}"].text
    assert "Always allowed" in notices[f"outside_app_person.sam_{OTHER}"].text


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
