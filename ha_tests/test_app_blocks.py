"""Hearth's app blocks (app_blocks.py): hearth.block_app / unblock_app through Family Link, the rule "Block browsers
Hearth doesn't support", and how blocks sit with Hearth's pauses, allows and explain."""

from datetime import timedelta

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import app_blocks, enforce
from custom_components.hearth.const import DOMAIN
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
CHILD = "42"
FIREFOX = "org.mozilla.firefox"
SAMSUNG = "com.sec.android.app.sbrowser"
GALAXY_STORE = "com.sec.android.app.samsungapps"
CHROME = "com.android.chrome"
EDGE = "com.microsoft.emmx"
GAME = "com.example.game"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _lists(hass: HomeAssistant, installed: list[str], blocked: list[str] = ()) -> None:
    """Sam's Family Link app lists: [blocked] in Blocked apps, the rest without limits."""
    free = [p for p in installed if p not in blocked]
    hass.states.async_set("sensor.sam_blocked_apps", str(len(blocked)), {"child_id": CHILD, "apps": [{"package": p} for p in blocked]})
    hass.states.async_set("sensor.sam_apps_without_limits", str(len(free)), {"child_id": CHILD, "apps": [{"package": p} for p in free]})
    hass.states.async_set("sensor.sam_apps_with_time_limits", "0", {"child_id": CHILD, "apps": []})
    hass.states.async_set("sensor.sam_always_allowed_apps", "0", {"child_id": CHILD, "apps": []})


async def _sam(hass: HomeAssistant, hass_client_no_auth, installed=(), blocked=()):
    calls = {
        "block": async_mock_service(hass, "familylink", "block_app"),
        "unblock": async_mock_service(hass, "familylink", "unblock_app"),
        "pause": async_mock_service(hass, "familylink", "pause_app"),
        "resume": async_mock_service(hass, "familylink", "resume_app"),
    }
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    _lists(hass, list(installed), list(blocked))
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    return calls


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _recompute(hass: HomeAssistant) -> None:
    _household(hass).recompute()
    await hass.async_block_till_done()


async def _call(hass: HomeAssistant, service: str, data: dict, response: bool = False):
    result = await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=response)
    await hass.async_block_till_done()
    return result


def _packages(calls) -> list[str]:
    return [c.data["package_name"] for c in calls]


async def _set_option(hass: HomeAssistant, ws_client, key: str, value) -> None:
    ws = await ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config/set", "key": key, "value": value})
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()


async def _page(hass: HomeAssistant, ws_client) -> dict:
    ws = await ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config"})
    return (await ws.receive_json())["result"]["app_blocks"]


async def test_an_adult_s_block_goes_through_family_link_and_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME, FIREFOX])

    answer = await _call(hass, "block_app", {"app": FIREFOX}, True)
    assert answer == {"blocked": {"person.sam": [FIREFOX]}}
    assert _packages(calls["block"]) == [FIREFOX]
    assert calls["block"][0].data["entity_id"] == FAMILY_LINK

    # Family Link shows it blocked: Hearth's own
    _lists(hass, [GAME, FIREFOX], [FIREFOX])
    await _recompute(hass)
    [kid] = (await _page(hass, hass_ws_client))["kids"]
    assert kid["blocks"] == [{"app": FIREFOX, "name": "Firefox", "why": ["adult"], "state": "blocked"}]
    assert len(calls["block"]) == 1

    await _call(hass, "unblock_app", {"apps": [FIREFOX], "people": ["person.sam"]})
    assert _packages(calls["unblock"]) == [FIREFOX]
    _lists(hass, [GAME, FIREFOX])
    await _recompute(hass)
    assert (await _page(hass, hass_ws_client))["kids"][0]["blocks"] == []
    assert len(calls["block"]) == 1 and len(calls["unblock"]) == 1


async def test_a_parent_s_own_block_is_never_undone(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME, FIREFOX], blocked=[FIREFOX])

    await _call(hass, "block_app", {"app": FIREFOX})
    assert calls["block"] == []
    [kid] = (await _page(hass, hass_ws_client))["kids"]
    assert kid["blocks"][0]["state"] == "parent"

    await _call(hass, "unblock_app", {"app": FIREFOX})
    await _recompute(hass)
    assert calls["unblock"] == []


async def test_a_block_waits_for_the_app_and_comes_back_with_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])

    await _call(hass, "block_app", {"app": FIREFOX, "people": ["person.sam"]})
    assert calls["block"] == []
    assert (await _page(hass, hass_ws_client))["kids"][0]["blocks"][0]["state"] == "not_installed"

    # Installed: blocked
    _lists(hass, [GAME, FIREFOX])
    await _recompute(hass)
    assert _packages(calls["block"]) == [FIREFOX]
    _lists(hass, [GAME, FIREFOX], [FIREFOX])
    await _recompute(hass)

    # Uninstalled, then installed again unblocked: Hearth blocks it again
    _lists(hass, [GAME])
    await _recompute(hass)
    assert len(calls["block"]) == 1 and calls["unblock"] == []
    _lists(hass, [GAME, FIREFOX])
    await _recompute(hass)
    assert _packages(calls["block"]) == [FIREFOX, FIREFOX]


async def test_what_may_be_blocked_and_by_whom(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user
) -> None:
    await _sam(hass, hass_client_no_auth, installed=[GAME])
    with pytest.raises(ServiceValidationError, match="never blocks"):
        await _call(hass, "block_app", {"app": "com.thesiegs.hearth"})
    with pytest.raises(ServiceValidationError, match="Only Android apps"):
        await _call(hass, "block_app", {"app": "x:9NBLGGH4R315"})
    with pytest.raises(ServiceValidationError, match="kids"):
        await _call(hass, "block_app", {"app": FIREFOX, "people": ["person.someone"]})

    # A user who isn't an adult on Hearth's page (a kid's own Home Assistant user, say)
    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "block_app", {"app": FIREFOX}, blocking=True, context=Context(user_id=hass_read_only_user.id)
        )


async def test_the_browser_rule_blocks_what_hearth_doesn_t_filter(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    installed = [GAME, CHROME, EDGE, FIREFOX, SAMSUNG, GALAXY_STORE]
    calls = await _sam(hass, hass_client_no_auth, installed=installed)
    await _recompute(hass)
    assert calls["block"] == []

    await _set_option(hass, hass_ws_client, "block_unsupported_browsers", True)
    await _recompute(hass)
    # Chrome is filtered (Family Link); Edge on Android isn't (Family Safety's filter needs the kid signed in to Edge)
    assert sorted(_packages(calls["block"])) == sorted([EDGE, FIREFOX, SAMSUNG, GALAXY_STORE])
    _lists(hass, installed, [EDGE, FIREFOX, SAMSUNG, GALAXY_STORE])
    await _recompute(hass)

    page = await _page(hass, hass_ws_client)
    assert page["rule"] is True
    assert {"name": "Chrome", "platform": "Android", "package": CHROME, "filtered_by": "Family Link"} in page["supported"]
    whys = {b["app"]: b["why"] for b in page["kids"][0]["blocks"]}
    assert whys == {EDGE: ["browser"], FIREFOX: ["browser"], SAMSUNG: ["browser"], GALAXY_STORE: ["app_store"]}

    # An adult unblocks one: it stays unblocked
    await _call(hass, "unblock_app", {"app": FIREFOX})
    assert _packages(calls["unblock"]) == [FIREFOX]
    _lists(hass, installed, [EDGE, SAMSUNG, GALAXY_STORE])
    await _recompute(hass)
    assert FIREFOX not in _packages(calls["block"])[4:]
    assert (await _page(hass, hass_ws_client))["kids"][0]["exempt"] == [FIREFOX]

    # A browser Hearth supports later is unblocked, as Hearth blocked it
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    monkeypatch.setattr(app_blocks, "SUPPORTED_ANDROID", frozenset({CHROME, EDGE}))
    await _recompute(hass)
    assert _packages(calls["unblock"]) == [FIREFOX, EDGE]
    _lists(hass, installed, [SAMSUNG, GALAXY_STORE])

    # The rule off: Hearth unblocks the rest it blocked for it
    await _set_option(hass, hass_ws_client, "block_unsupported_browsers", False)
    await _recompute(hass)
    assert sorted(_packages(calls["unblock"])[2:]) == sorted([SAMSUNG, GALAXY_STORE])
    assert len(calls["block"]) == 4


async def test_the_rule_leaves_a_parent_s_block_and_unsupported_ones_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    installed = [GAME, CHROME, FIREFOX]
    calls = await _sam(hass, hass_client_no_auth, installed=installed, blocked=[FIREFOX])
    await _set_option(hass, hass_ws_client, "block_unsupported_browsers", True)
    await _recompute(hass)
    assert calls["block"] == []
    await _set_option(hass, hass_ws_client, "block_unsupported_browsers", False)
    await _recompute(hass)
    # The parent's block of Firefox stays
    assert calls["unblock"] == []


async def test_a_blocked_app_is_never_paused_or_resumed_and_explain_says_so(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    other = "com.example.other"
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME, other])

    # Paused first, then blocked: not resumed (Family Link's resume_app skips a blocked app; Hearth doesn't ask)
    await _call(hass, "pause", {"app": GAME, "minutes": 30, "people": ["person.sam"]})
    assert calls["pause"] and GAME in calls["pause"][0].data["packages"]
    await _call(hass, "block_app", {"app": GAME})
    assert _packages(calls["block"]) == [GAME]
    await _call(hass, "pause_end", {"app": GAME, "people": ["person.sam"]})
    await _recompute(hass)
    assert calls["resume"] == []
    held = _household(hass).enforcement.status_of("person.sam")["family_link"]
    assert held["held"] == [GAME] and held["why"] == {GAME: "blocked_app"}

    # Blocked first, then paused: never paused
    await _call(hass, "block_app", {"app": other})
    await _call(hass, "pause", {"app": other, "minutes": 30, "people": ["person.sam"]})
    assert all(other not in c.data["packages"] for c in calls["pause"])

    # An allow doesn't lift it; explain names it
    await _call(hass, "allow", {"people": ["person.sam"], "app": other})
    why = await _call(hass, "explain", {"person": "person.sam", "app": other}, True)
    assert why["allowed"] is False
    assert {"kind": "blocked_app", "by": "hearth.block_app", "app": other, "why": ["adult"], "until": None} in why["blocked_by"]

    # Unblocked: the pause Hearth kept is let go as usual (no pause of GAME is left)
    await _call(hass, "unblock_app", {"app": GAME})
    await _recompute(hass)
    assert [GAME] in [c.data["packages"] for c in calls["resume"]]


async def test_windows_and_xbox_show_family_safety_s_web_filter(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _sam(hass, hass_client_no_auth, installed=[GAME])
    assert (await _page(hass, hass_ws_client))["kids"][0]["web_filter"] is None

    hass.states.async_set("sensor.sam_xbox_screen_time", "10", {"user_id": "123456", "unit_of_measurement": "min"})
    hass.states.async_set("switch.sam_web_filtering", "on", {"user_id": "123456"})
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "family_safety": "sensor.sam_xbox_screen_time"},
    )
    page = await _page(hass, hass_ws_client)
    assert page["kids"][0]["web_filter"] == {"entity_id": "switch.sam_web_filtering", "on": True}

    hass.states.async_set("switch.sam_web_filtering", "off", {"user_id": "123456"})
    assert (await _page(hass, hass_ws_client))["kids"][0]["web_filter"]["on"] is False


async def test_an_app_the_categories_know_as_a_browser_is_one(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    from custom_components.hearth.categories import Hit

    await _sam(hass, hass_client_no_auth, installed=[GAME])
    blocks = _household(hass).blocks
    names = {"com.example.webby": "Webby: Fast Web Browser", "com.example.files": "File Browser", GAME: "Browser Quest"}
    monkeypatch.setattr(
        blocks.household.categories_book,
        "lookup",
        lambda item: Hit(item, True, "game" if item == GAME else None, None, names.get(item)),
    )
    assert blocks.rule_reason("com.example.webby") == "browser"
    assert blocks.rule_reason("com.example.files") is None
    # A game named like one isn't
    assert blocks.rule_reason(GAME) is None
    assert blocks.rule_reason(CHROME) is None and blocks.rule_reason(GALAXY_STORE) == "app_store"


def test_supported_browsers_are_never_blocked_by_the_rule() -> None:
    for package in app_blocks.SUPPORTED_ANDROID:
        assert package in app_blocks.BROWSERS
    assert app_blocks.SUPPORTED_ANDROID == {CHROME}
    assert not set(app_blocks.OTHER_APP_STORES) & set(app_blocks.BROWSERS)
    assert app_blocks.android_package(FIREFOX) and not app_blocks.android_package("appx:Foo")
