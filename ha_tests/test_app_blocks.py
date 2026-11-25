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


def _lists(hass: HomeAssistant, installed: list[str], blocked: list[str] = (), names: dict[str, str] | None = None) -> None:
    """Sam's Family Link app lists: [blocked] in Blocked apps (without names), the rest without limits (with their
    [names])."""
    free = [p for p in installed if p not in blocked]
    named = lambda p: {"package": p, **({"name": names[p]} if names and p in names else {})}  # noqa: E731
    hass.states.async_set("sensor.sam_blocked_apps", str(len(blocked)), {"child_id": CHILD, "apps": [{"package": p} for p in blocked]})
    hass.states.async_set("sensor.sam_apps_without_limits", str(len(free)), {"child_id": CHILD, "apps": [named(p) for p in free]})
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
    # Nor a keyboard or a home screen: either could leave the device unusable
    for package in ("com.google.android.inputmethod.latin", "com.sec.android.app.launcher"):
        with pytest.raises(ServiceValidationError, match="never blocks"):
            await _call(hass, "block_app", {"app": package})
    with pytest.raises(ServiceValidationError, match="Only Android apps"):
        await _call(hass, "block_app", {"app": "not an app"})
    # An Xbox app: through Family Safety, which Sam doesn't have here (test_platform_parity)
    with pytest.raises(ServiceValidationError, match="No Family Safety"):
        await _call(hass, "block_app", {"app": "x:9NBLGGH4R315", "people": ["person.sam"]})
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
    # Family Link lists it blocked (only then is it left out of Hearth's pauses)
    _lists(hass, [GAME, other], [GAME])
    await _call(hass, "pause_end", {"app": GAME, "people": ["person.sam"]})
    await _recompute(hass)
    assert calls["resume"] == []
    held = _household(hass).enforcement.status_of("person.sam")["family_link"]
    assert held["held"] == [GAME] and held["why"] == {GAME: "blocked_app"}

    # Blocked first, then paused: never paused
    await _call(hass, "block_app", {"app": other})
    _lists(hass, [GAME, other], [GAME, other])
    await _recompute(hass)
    await _call(hass, "pause", {"app": other, "minutes": 30, "people": ["person.sam"]})
    assert all(other not in c.data["packages"] for c in calls["pause"])

    # An allow doesn't lift it; explain names it
    await _call(hass, "allow", {"people": ["person.sam"], "app": other})
    why = await _call(hass, "explain", {"person": "person.sam", "app": other}, True)
    assert why["allowed"] is False
    assert {"kind": "blocked_app", "by": "hearth.block_app", "app": other, "why": ["adult"], "until": None} in why["blocked_by"]

    # Unblocked: the pause Hearth kept is let go as usual (no pause of GAME is left)
    await _call(hass, "unblock_app", {"app": GAME})
    _lists(hass, [GAME, other], [other])
    await _recompute(hass)
    assert [GAME] in [c.data["packages"] for c in calls["resume"]]


async def test_a_block_family_link_hasn_t_confirmed_is_still_paused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    await _call(hass, "block_app", {"app": GAME})
    assert _household(hass).blocks.blocked_packages("person.sam") == set()
    await _call(hass, "pause", {"app": GAME, "minutes": 30, "people": ["person.sam"]})
    assert any(GAME in c.data["packages"] for c in calls["pause"])
    # Confirmed: now Family Link's block holds it
    _lists(hass, [GAME], [GAME])
    assert _household(hass).blocks.blocked_packages("person.sam") == {GAME}


async def test_an_unconfirmed_block_is_tried_three_times_then_said(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, hass_ws_client
) -> None:
    from pytest_homeassistant_custom_component.common import async_capture_events

    events = async_capture_events(hass, "hearth_app_blocked")
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    await _call(hass, "block_app", {"app": GAME})
    for _ in range(4):
        freezer.tick(timedelta(minutes=4))
        await _recompute(hass)
    # Family Link took the calls but never listed it: three tries, then Hearth stops and says so
    assert _packages(calls["block"]) == [GAME, GAME, GAME]
    [view] = _household(hass).blocks.views("person.sam")
    assert view["error"] == f"Family Link didn't block {view['name']}"
    assert events == []
    # Listed at last: the event fires once
    _lists(hass, [GAME], [GAME])
    await _recompute(hass)
    await _recompute(hass)
    assert len(events) == 1


async def test_a_parent_s_unblock_in_family_link_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    await _call(hass, "block_app", {"app": GAME})
    _lists(hass, [GAME], [GAME])
    await _recompute(hass)
    blocks = _household(hass).blocks
    assert blocks.applied["person.sam"][GAME]["confirmed"]
    # A parent unblocks it in the Family Link app: recorded, never blocked again by Hearth
    _lists(hass, [GAME], [])
    for _ in range(3):
        freezer.tick(timedelta(minutes=4))
        await _recompute(hass)
    assert _packages(calls["block"]) == [GAME]
    assert GAME in blocks.parent_unblocked["person.sam"] and GAME not in blocks.wanted("person.sam")
    assert blocks.page()["kids"][0]["parent_unblocked"][0]["app"] == GAME
    # An adult blocks it again in Hearth: it's Hearth's again
    await _call(hass, "block_app", {"app": GAME})
    assert _packages(calls["block"]) == [GAME, GAME]


async def test_an_app_reinstalled_unblocked_is_blocked_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME])
    await _call(hass, "block_app", {"app": GAME})
    _lists(hass, [GAME], [GAME])
    await _recompute(hass)
    # Uninstalled, then installed again (Family Link lists it unblocked)
    _lists(hass, [], [])
    await _recompute(hass)
    _lists(hass, [GAME], [])
    freezer.tick(timedelta(minutes=4))
    await _recompute(hass)
    assert _packages(calls["block"]) == [GAME, GAME]
    assert "person.sam" not in _household(hass).blocks.parent_unblocked


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


async def test_a_block_that_timed_out_but_went_through_is_hearth_s_to_lift(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    from homeassistant.exceptions import HomeAssistantError

    calls = await _sam(hass, hass_client_no_auth, installed=[GAME, FIREFOX])
    unblocked = calls["unblock"]

    async def timed_out(call):
        raise HomeAssistantError("timeout")

    hass.services.async_register("familylink", "block_app", timed_out)
    await _call(hass, "block_app", {"app": FIREFOX}, True)
    # It went through all the same: Family Link lists it blocked
    _lists(hass, [GAME, FIREFOX], [FIREFOX])
    await _recompute(hass)
    [kid] = (await _page(hass, hass_ws_client))["kids"]
    assert kid["blocks"][0]["state"] == "blocked"
    await _call(hass, "unblock_app", {"apps": [FIREFOX], "people": ["person.sam"]})
    assert _packages(unblocked) == [FIREFOX]


def test_chrome_is_blocked_like_any_app_but_android_s_own_parts_are_not() -> None:
    """Chrome's package is com.android.chrome: no com.android.* prefix rule spares it (enforce.essential is the
    explicit system list)."""
    assert not app_blocks.never_blocked("com.android.chrome")
    assert not enforce.essential("com.android.chrome")
    for package in ("com.android.systemui", "com.android.phone", "com.android.launcher3", "com.android.settings", "android"):
        assert app_blocks.never_blocked(package) and enforce.essential(package)


# The AI companion rule (block_ai_companions): on unless turned off
CHARACTER_AI = "ai.character.app"
REPLIKA = "ai.replika.app"
PAL = "com.example.pal"
GEMINI = "com.google.android.apps.bard"
CHATGPT = "com.openai.chatgpt"
COPILOT = "com.microsoft.copilot"
CLAUDE = "com.anthropic.claude"
GOOGLE_CHAT = "com.google.android.apps.dynamite"
HELPER = "com.example.helper"
TEXTS = "com.example.texts"
HOMEWORK = "com.example.homework"
COMPANION_NAMES = {
    PAL: "Pal: AI Girlfriend & Roleplay",
    HELPER: "Helper - AI Chat Assistant",
    TEXTS: "Texts: Messages with AI friends",
    HOMEWORK: "Homework Buddy: AI Friend for School",
    # Assistants named like a companion app are never blocked by the rule
    GEMINI: "Gemini: chat with AI characters",
    CHATGPT: "ChatGPT",
    COPILOT: "Copilot - AI companion",
    CLAUDE: "Claude by Anthropic",
    GOOGLE_CHAT: "Google Chat",
}
ASSISTANTS = [GEMINI, CHATGPT, COPILOT, CLAUDE, GOOGLE_CHAT, HELPER, TEXTS, HOMEWORK]


def _asked(hass: HomeAssistant) -> dict:
    """The notices asking the adults about an app named like an AI companion app, by key."""
    attention = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.attention
    return {i.key: i for i in attention.items() if i.key.startswith("ai_companion_")}


async def test_ai_companion_apps_are_blocked_by_default_and_assistants_never(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    installed = [GAME, CHARACTER_AI, REPLIKA, PAL, *ASSISTANTS]
    calls = await _sam(hass, hass_client_no_auth)
    # A household that never set it: on
    assert "block_ai_companions" not in hass.config_entries.async_entries(DOMAIN)[0].options
    _lists(hass, installed, names=COMPANION_NAMES)
    await _recompute(hass)
    # Only the known packages are blocked: an app named like one isn't, nor a general assistant, a messaging or a
    # school app
    assert sorted(_packages(calls["block"])) == sorted([CHARACTER_AI, REPLIKA])

    # Family Link lists them blocked (its Blocked apps list without names): they stay blocked
    _lists(hass, installed, [CHARACTER_AI, REPLIKA], names=COMPANION_NAMES)
    for _ in range(3):
        await _recompute(hass)
    assert calls["unblock"] == [] and len(calls["block"]) == 2
    page = await _page(hass, hass_ws_client)
    assert page["ai_companion_rule"] is True and page["rule"] is False
    assert page["ai_companions"][CHARACTER_AI] == "Character AI"
    assert {b["app"]: (b["why"], b["state"]) for b in page["kids"][0]["blocks"]} == {
        CHARACTER_AI: (["ai_companion"], "blocked"),
        REPLIKA: (["ai_companion"], "blocked"),
    }
    why = await _call(hass, "explain", {"person": "person.sam", "app": CHARACTER_AI}, True)
    assert {"kind": "blocked_app", "by": "block_ai_companions", "app": CHARACTER_AI, "why": ["ai_companion"], "until": None} in why["blocked_by"]

    # An adult unblocks one: it stays unblocked, and the other stays blocked
    await _call(hass, "unblock_app", {"app": REPLIKA})
    assert _packages(calls["unblock"]) == [REPLIKA]
    _lists(hass, installed, [CHARACTER_AI], names=COMPANION_NAMES)
    await _recompute(hass)
    assert len(calls["block"]) == 2
    assert (await _page(hass, hass_ws_client))["kids"][0]["exempt"] == [REPLIKA]


async def test_an_app_only_named_like_a_companion_is_asked_about_once_never_blocked(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    other = "com.example.crush"
    names = {**COMPANION_NAMES, other: "Crush: AI Lovers"}
    installed = [GAME, CHARACTER_AI, PAL, other, *ASSISTANTS]
    calls = await _sam(hass, hass_client_no_auth)
    fired = []
    hass.bus.async_listen("hearth_ai_companion_asked", fired.append)
    _lists(hass, installed, names=names)
    await _recompute(hass)
    assert _packages(calls["block"]) == [CHARACTER_AI]

    # One notice per app and kid, for the ones named like a companion app only: never a known package (blocked) nor
    # an assistant
    asked = _asked(hass)
    assert sorted(asked) == ["ai_companion_person.sam_com.example.crush", "ai_companion_person.sam_com.example.pal"]
    pal = asked["ai_companion_person.sam_com.example.pal"]
    assert "Pal: AI Girlfriend & Roleplay" in pal.title and pal.audience == "adults" and pal.once
    block, not_now = pal.actions
    assert (block.label, block.service, dict(block.data)) == (
        "Block", "hearth.block_app", {"people": ["person.sam"], "apps": [PAL]}
    )
    assert not_now.label == "Not now" and not_now.dismiss and not_now.service is None
    assert sorted(e.data["app"] for e in fired) == sorted([PAL, other])

    # Asked once: not again on later looks, nor after Not now took it off the phones
    attention = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.attention
    attention.clear(pal.key)
    for _ in range(3):
        await _recompute(hass)
    assert len(fired) == 2 and pal.key not in _asked(hass)
    page = await _page(hass, hass_ws_client)
    assert [a["app"] for a in page["kids"][0]["asked"]] == [other, PAL]
    assert {b["app"] for b in page["kids"][0]["blocks"]} == {CHARACTER_AI}
    # Kept: a restart doesn't ask again
    assert set(_household(hass).blocks._data()["asked"]["person.sam"]) == {PAL, other}

    # Block, pressed: the app is the adult's block
    crush = _asked(hass)["ai_companion_person.sam_com.example.crush"]
    assert await attention.run(crush.actions[0], None)
    await hass.async_block_till_done()
    assert other in _packages(calls["block"])
    _lists(hass, installed, [CHARACTER_AI, other], names=names)
    await _recompute(hass)
    assert {b["app"]: b["why"] for b in (await _page(hass, hass_ws_client))["kids"][0]["blocks"]}[other] == ["adult"]
    assert PAL not in _packages(calls["block"]) and calls["unblock"] == []

    # The rule off: nobody is asked
    await _set_option(hass, hass_ws_client, "block_ai_companions", False)
    _lists(hass, [*installed, "com.example.waifu"], [other], names={**names, "com.example.waifu": "AI Waifu Chat"})
    await _recompute(hass)
    assert len(fired) == 2


async def test_turning_the_ai_companion_rule_off_unblocks_only_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    # Replika was blocked by a parent in Family Link: theirs
    installed = [GAME, CHROME, FIREFOX, CHARACTER_AI, REPLIKA]
    calls = await _sam(hass, hass_client_no_auth, installed=installed, blocked=[REPLIKA])
    await _set_option(hass, hass_ws_client, "block_unsupported_browsers", True)
    await _call(hass, "block_app", {"app": GAME})
    await _recompute(hass)
    assert set(_packages(calls["block"])) == {GAME, FIREFOX, CHARACTER_AI}
    _lists(hass, installed, [GAME, FIREFOX, CHARACTER_AI, REPLIKA])
    await _recompute(hass)

    await _set_option(hass, hass_ws_client, "block_ai_companions", False)
    await _recompute(hass)
    # Only what the rule blocked: not the browser rule's, an adult's or a parent's
    assert _packages(calls["unblock"]) == [CHARACTER_AI]
    _lists(hass, installed, [GAME, FIREFOX, REPLIKA])
    await _recompute(hass)
    assert _packages(calls["unblock"]) == [CHARACTER_AI]
    page = await _page(hass, hass_ws_client)
    assert page["ai_companion_rule"] is False
    assert {b["app"] for b in page["kids"][0]["blocks"]} == {GAME, FIREFOX}

    # On again (in Configure, next to the browser rule): blocked again
    before = _packages(calls["block"]).count(CHARACTER_AI)
    await _option(hass, "blocked_apps", {"block_unsupported_browsers": True, "block_ai_companions": True})
    await _recompute(hass)
    assert _packages(calls["block"]).count(CHARACTER_AI) > before
    assert REPLIKA not in _packages(calls["block"])
    assert hass.config_entries.async_entries(DOMAIN)[0].options["block_unsupported_browsers"] is True


async def test_what_the_ai_companion_rule_takes_for_one(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    from custom_components.hearth.categories import Hit

    await _sam(hass, hass_client_no_auth, installed=[GAME])
    blocks = _household(hass).blocks
    companions = [
        "Pal: AI Companion",
        "AI Girlfriend: Virtual Love",
        "My AI Boyfriend",
        "Character AI: Chat, Talk, Text",
        "Character.AI",
        "Chat with AI Characters",
        "Anime: chat with characters",
        "AI Waifu Chat",
        "Virtual Girlfriend Simulator",
        "AI Roleplay Stories",
        "AI role-play chat",
        "Roleplay Chat: Stories",
        "Waifu AI",
    ]
    others = [
        "AI Chat - Ask Anything",
        "Nova: AI Chat Assistant",
        "Gemini",
        "Microsoft Copilot: AI Chat",
        "Google Chat",
        "AI Friend: Learn English",
        "Homework AI: math tutor",
        "Messages: AI friends",
        "Roblox",
        "AI Photo Editor",
        "Friendly AI keyboard",
        "Air Friends",
    ]
    # A name alone is asked about, never a rule's reason to block
    for name in companions:
        assert blocks.named_ai_companion("com.example.x", name), name
    assert blocks.rule_reason("com.example.x") is None
    for name in others:
        assert not blocks.named_ai_companion("com.example.x", name), name
    # Known packages need no name, and are blocked (never asked about); the assistants are never one, whatever
    # they're called
    for package in app_blocks.AI_COMPANIONS:
        assert blocks.rule_reason(package) == "ai_companion"
        assert not blocks.named_ai_companion(package, "AI Girlfriend")
    for package in app_blocks.NOT_AI_COMPANIONS:
        assert blocks.rule_reason(package) is None
        assert not blocks.named_ai_companion(package, "AI Girlfriend")
    assert not set(app_blocks.AI_COMPANIONS) & app_blocks.NOT_AI_COMPANIONS
    assert all(app_blocks.android_package(p) for p in app_blocks.AI_COMPANIONS)

    # A name Hearth's categories know counts too (for asking), but not for an app they know as messaging or education
    names = {"com.example.pal": "Pal: AI Friend", "com.example.chatty": "Chatty: AI Friend", "com.example.tutor": "Tutor: AI Friend"}
    kinds = {"com.example.chatty": ("messaging", None), "com.example.tutor": ("productivity", "education")}
    monkeypatch.setattr(
        blocks.household.categories_book,
        "lookup",
        lambda item: Hit(item, True, *kinds.get(item, ("social", None)), names.get(item)),
    )
    assert blocks.named_ai_companion("com.example.pal")
    assert not blocks.named_ai_companion("com.example.chatty")
    assert not blocks.named_ai_companion("com.example.tutor")
    assert blocks.rule_reason("com.example.pal") is None


async def test_a_blocked_list_cut_short_is_not_nothing_blocked(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """A Blocked apps list that is cut short (or missing) is unknown. Read as "nothing is blocked", every blocked app
    became one Hearth pauses and resumes."""
    other = "com.example.other"
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME, other], blocked=[GAME])
    blocks = _household(hass).blocks
    assert blocks.blocked_packages("person.sam") == {GAME} and blocks.blocked_known("person.sam")

    # Cut short, showing none of them: the last whole list stands
    hass.states.async_set("sensor.sam_blocked_apps", "80", {"child_id": CHILD, "apps": [], "truncated": True})
    await _recompute(hass)
    assert blocks.blocked_packages("person.sam") == {GAME} and blocks.blocked_known("person.sam")
    await _call(hass, "pause", {"app": GAME, "minutes": 30, "people": ["person.sam"]})
    await _call(hass, "pause", {"app": other, "minutes": 30, "people": ["person.sam"]})
    paused = {p for c in calls["pause"] for p in c.data["packages"]}
    assert other in paused and GAME not in paused
    # And nothing is blocked or unblocked on a list that can't be read
    await _call(hass, "block_app", {"app": other})
    await _call(hass, "unblock_app", {"app": GAME})
    assert not calls["block"] and not calls["unblock"]

    # Missing altogether: the same
    hass.states.async_remove("sensor.sam_blocked_apps")
    await _recompute(hass)
    assert blocks.blocked_packages("person.sam") == {GAME}

    # What a cut-short list does show counts too
    hass.states.async_set(
        "sensor.sam_blocked_apps", "80", {"child_id": CHILD, "apps": [{"package": other}], "truncated": True}
    )
    assert blocks.blocked_packages("person.sam") == {GAME, other}

    # Kept over a restart
    await blocks.async_flush()
    again = app_blocks.AppBlocks(hass, _household(hass), blocks._store.key.removeprefix("hearth.app_blocks."))
    await again.async_load()
    assert again.last_blocked == {"person.sam": {GAME}}

    # Whole again with nothing blocked: that is known, and replaces the last list
    _lists(hass, [GAME, other])
    assert blocks.blocked_packages("person.sam") == set() and blocks.blocked_known("person.sam")
    assert blocks.last_blocked == {"person.sam": set()}


async def test_a_blocked_list_never_read_whole_is_unknown(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = await _sam(hass, hass_client_no_auth, installed=[GAME], blocked=[GAME])
    blocks = _household(hass).blocks
    blocks.last_blocked.clear()
    hass.states.async_set(
        "sensor.sam_blocked_apps", "80", {"child_id": CHILD, "apps": [{"package": GAME}], "truncated": True}
    )
    assert not blocks.blocked_known("person.sam")
    assert blocks.blocked_packages("person.sam") == {GAME}
    assert blocks.last_blocked == {}
    # Someone with no Family Link has nothing to know
    assert blocks.blocked_known("person.nobody") and blocks.blocked_packages("person.nobody") == set()
    assert not calls["block"] and not calls["unblock"]
