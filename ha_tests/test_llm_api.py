"""Hearth for assistants (llm_api.py): the "hearth" LLM API that Home Assistant's MCP Server and Assist offer. Adults
read and act (as themselves, with the specific result back); a kid gets nothing; voice gets nothing while its option is
off, and with it on its actions go to the adults' phones first. Never a budget, never a parent's block lifted."""

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import llm
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import ASSIST, BONUS
from custom_components.hearth.llm_api import SENT, VOICE_TAG, HouseholdTool
from test_asks import _ask
from test_attention import _household, _hub, _press
from test_phones import _options

BONUS_ENTITY = "number.hearth_sam_video_bonus_today"
READ = {"hearth_get_household", "hearth_get_person", "hearth_explain", "hearth_get_suggestions", "hearth_get_requests"}
ACTIONS = {
    "hearth_add_bonus",
    "hearth_pause",
    "hearth_pause_end",
    "hearth_allow",
    "hearth_allow_end",
    "hearth_answer_request",
    "hearth_dismiss_suggestion",
    "hearth_school_time_off",
    "hearth_school_time_off_cancel",
}


def _context(user=None, platform: str = "mcp_server") -> llm.LLMContext:
    return llm.LLMContext(
        platform=platform,
        context=Context(user_id=user.id if user else None),
        language="*",
        assistant="conversation",
        device_id=None,
    )


async def _api(hass: HomeAssistant, user=None, platform: str = "mcp_server") -> llm.APIInstance:
    return await llm.async_get_api(hass, "hearth", _context(user, platform))


async def _call(api: llm.APIInstance, tool: str, **args):
    """As APIInstance.async_call_tool does (it also traces the call in conversation, which needs hassil)."""
    found = next(t for t in api.tools if t.name == tool)
    return await found.async_call(api.api.hass, llm.ToolInput(tool_name=tool, tool_args=args), api.llm_context)


def _sent_to(sent, phone: str = "alex_phone") -> list:
    return [c for c in sent[phone] if str(c.data.get("data", {}).get("tag", "")).startswith(VOICE_TAG)]


async def test_an_adult_gets_the_read_and_action_tools_and_no_budget(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, _sent = await _household(hass, hass_client_no_auth)
    assert "hearth" in {api.id for api in llm.async_get_apis(hass)}
    api = await _api(hass, users["alex"])
    names = {tool.name for tool in api.tools}
    assert names == READ | ACTIONS
    assert not any("budget" in name for name in names)
    assert "children" in api.api_prompt
    # Each tool's input converts as the MCP Server and Assist send it to a model (where the converter is installed)
    try:
        from voluptuous_openapi import convert
    except ImportError:
        convert = None
    for tool in api.tools if convert else []:
        schema = convert(tool.parameters, custom_serializer=llm.selector_serializer)
        assert schema["type"] == "object", tool.name
    # An administrator too
    admin = await hass.auth.async_create_user("Admin", group_ids=["system-admin"])
    assert {tool.name for tool in (await _api(hass, admin)).tools} == READ | ACTIONS


async def test_the_read_tools(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, users, _sent = await _household(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 30}, blocking=True)
    response = await _ask(client, secret, minutes=30, profile_id="user:10", note="One more episode")
    request = (await response.json())["request"]
    await hass.async_block_till_done()
    api = await _api(hass, users["alex"])

    household = await _call(api, "hearth_get_household")
    sam = next(p for p in household["people"] if p["id"] == "person.sam")
    assert sam["name"] == "Sam"
    video = next(g for g in sam["groups"] if g["id"] == "video")
    assert (video["used_minutes"], video["minutes_left"], video["budget"]) == (10, 20, 30)
    # Nothing an assistant mustn't have: no TV profile keys, no pairing codes
    assert "tv_profiles" not in sam and "targets" not in sam
    assert [r["id"] for r in household["requests"]] == [request["id"]]
    assert household["devices"][0]["name"] == "Kitchen"

    person = await _call(api, "hearth_get_person", person="sam")
    assert len(person["week"]) == 7 and person["week"][0]["minutes"]["video"] == 10
    assert person["devices"] and {"id", "name", "kind"} <= set(person["devices"][0])
    assert person["apps_today"]

    explain = await _call(api, "hearth_explain", person="Sam", group="Video")
    assert explain["allowed"] is True and explain["group_name"] == "Video"

    suggestions = await _call(api, "hearth_get_suggestions")
    assert isinstance(suggestions["suggestions"], list)
    assert all("actions" not in s for s in suggestions["suggestions"])

    requests = await _call(api, "hearth_get_requests")
    [waiting] = requests["requests"]
    assert (waiting["id"], waiting["person"], waiting["minutes"], waiting["note"]) == (
        request["id"], "person.sam", 30, "One more episode"
    )

    with pytest.raises(HomeAssistantError, match="No one called Robin"):
        await _call(api, "hearth_get_person", person="Robin")


async def test_an_adult_s_action_runs_as_them_and_says_what_changed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, _sent = await _household(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 30}, blocking=True)
    api = await _api(hass, users["alex"])

    result = await _call(api, "hearth_add_bonus", person="Sam", minutes=15, group="video")
    await hass.async_block_till_done()
    assert hass.states.get(BONUS_ENTITY).state == "15"
    assert result["done"] == "give Sam 15 more minutes of Video today"
    assert (result["person"], result["group"], result["minutes"]) == ("Sam", "Video", 15)
    assert (result["minutes_left_now"], result["budget_today"], result["bonus_today"]) == (35, 30, 15)
    assert "-15" in result["undo"]
    # The history says it was the MCP, and who
    [event] = result["logged"]
    assert (event["kind"], event["via"], event["user"], event["minutes"]) == (BONUS, "mcp", users["alex"].id, 15)
    assert _hub(hass).household.history.events[-1]["via"] == "mcp"

    # Corrected: taken back
    result = await _call(api, "hearth_add_bonus", person="Sam", minutes=-15, group="video")
    await hass.async_block_till_done()
    assert hass.states.get(BONUS_ENTITY).state == "0"
    assert result["minutes_left_now"] == 20

    # A pause logs nothing of its own: an assist event says what was done
    result = await _call(api, "hearth_pause", people=["Sam"], minutes=20, reason="dinner")
    assert result["paused_now"]["Sam"]["reason"] == "dinner"
    [event] = result["logged"]
    assert (event["kind"], event["tool"], event["via"], event["user"], event["minutes"]) == (
        ASSIST, "hearth_pause", "mcp", users["alex"].id, 20
    )
    assert "reason" not in event
    result = await _call(api, "hearth_pause_end", people=["Sam"])
    assert result["still_paused"] == {"Sam": None}

    # An allow names its id (to end it) and whether it's open now
    result = await _call(api, "hearth_allow", person="Sam", group="Video", until="21:00")
    assert result["id"] and result["now"]["allowed"] is True
    result = await _call(api, "hearth_allow_end", id=result["id"])
    assert len(result["ended"]) == 1

    # A request answered: as Alex
    response = await _ask(client, secret, minutes=30, profile_id="user:10")
    request = (await response.json())["request"]
    await hass.async_block_till_done()
    result = await _call(api, "hearth_answer_request", request_id=request["id"], minutes=10)
    assert (result["status"], result["minutes"], result["person"]) == ("approved", 10, "Sam")
    assert _hub(hass).asks.get(request["id"]).answered_by == users["alex"].id
    with pytest.raises(HomeAssistantError, match="isn't open"):
        await _call(api, "hearth_answer_request", request_id=request["id"], deny=True)


async def test_a_kid_is_refused(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _household(hass, hass_client_no_auth)
    api = await _api(hass, users["sam"])
    assert api.tools == []
    # Even a tool called directly
    with pytest.raises(HomeAssistantError, match="Only an adult"):
        await HouseholdTool().async_call(hass, llm.ToolInput("hearth_get_household", {}), _context(users["sam"]))
    # And by voice they'd be asking without a user: see the voice tests


async def test_voice_with_the_option_off_gets_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household(hass, hass_client_no_auth)
    api = await _api(hass, platform="openai_conversation")
    assert api.tools == []
    assert "off for voice" in api.api_prompt
    with pytest.raises(HomeAssistantError, match="Voice assistants are off"):
        await HouseholdTool().async_call(hass, llm.ToolInput("hearth_get_household", {}), _context(None, "x"))


async def test_a_voice_action_asks_the_adults_phones_and_runs_once_as_the_one_who_taps(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, voice_assistants=True)
    api = await _api(hass, platform="openai_conversation")
    assert {tool.name for tool in api.tools} == READ | ACTIONS
    assert "approval" in api.api_prompt
    # Reads answer directly
    assert (await _call(api, "hearth_get_household"))["people"]

    result = await _call(api, "hearth_add_bonus", person="Sam", minutes=30, group="video")
    await hass.async_block_till_done()
    assert result["message"] == SENT
    # Nothing ran yet
    assert hass.states.get(BONUS_ENTITY).state == "0"
    [push] = _sent_to(sent)
    assert push.data["title"] == "Approve: give Sam 30 more minutes of Video today?"
    [run, dont] = push.data["data"]["actions"]
    assert (run["title"], dont["title"]) == ("+30 min", "Don't allow")
    assert run["action"].startswith("HEARTH_ACT|voice:")
    # Every adult's phone; never the kid's
    assert _sent_to(sent, "jordan_iphone") and not _sent_to(sent, "sam_phone")

    # The kid pressing it: nothing
    _press(hass, run["action"], users["sam"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS_ENTITY).state == "0"
    # Alex's tap runs it as Alex, logged as voice
    _press(hass, run["action"], users["alex"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS_ENTITY).state == "30"
    event = _hub(hass).household.history.events[-1]
    assert (event["kind"], event["via"], event["user"], event["minutes"]) == (BONUS, "voice", users["alex"].id, 30)
    # Once
    _press(hass, run["action"], users["jordan"])
    await hass.async_block_till_done()
    assert hass.states.get(BONUS_ENTITY).state == "30"

    # "Don't allow" runs nothing
    result = await _call(api, "hearth_pause", people=["Sam"], minutes=10)
    await hass.async_block_till_done()
    push = _sent_to(sent)[-1]
    _press(hass, push.data["data"]["actions"][1]["action"], users["alex"])
    await hass.async_block_till_done()
    assert (await _call(api, "hearth_get_person", person="Sam")).get("pause") is None

    # Turned off again: no tools
    await _options(hass, voice_assistants=False)
    assert (await _api(hass, platform="openai_conversation")).tools == []


async def test_a_parent_s_block_is_never_lifted(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    hass.states.async_set("sensor.sam_phone_family_link", "ok", {"child_id": "42"})
    hass.states.async_set(
        "sensor.sam_blocked_apps", "1", {"child_id": "42", "apps": [{"name": "Shooter Game", "package": "com.example.shooter"}]}
    )
    hass.states.async_set("sensor.sam_family_safety", "ok", {"user_id": "ms-sam"})
    hass.states.async_set(
        "sensor.sam_applications",
        "2",
        {
            "user_id": "ms-sam",
            "applications": [
                {"app_id": "x:racer", "app_name": "Racer", "blocked": True},
                {"app_id": "x:paused", "app_name": "Paused By Hearth", "blocked": True},
            ],
            "paused_apps": [{"package": "x:paused", "name": "Paused By Hearth", "paused": "ours"}],
        },
    )
    await _options(
        hass,
        enforce=[
            {"kind": "family_link", "person": "person.sam", "entity_id": "sensor.sam_phone_family_link"},
            {"kind": "family_safety", "person": "person.sam", "entity_id": "sensor.sam_family_safety", "platforms": ["Xbox"]},
        ],
        voice_assistants=True,
    )
    api = await _api(hass, users["alex"])
    for app in ("com.example.shooter", "Shooter Game", "x:racer", "Racer"):
        with pytest.raises(HomeAssistantError, match="A parent blocked"):
            await _call(api, "hearth_allow", person="Sam", app=app)
    # Not by voice either: nothing goes to the phones
    voice = await _api(hass, platform="openai_conversation")
    with pytest.raises(HomeAssistantError, match="A parent blocked"):
        await _call(voice, "hearth_allow", person="Sam", app="Shooter Game")
    assert not _sent_to(sent)
    # explain says so
    explain = await _call(api, "hearth_explain", person="Sam", app="com.example.shooter")
    assert explain["allowed"] is False and explain["parent_block"]["in"] == "Family Link"
    # An app Hearth itself paused isn't a parent's block
    result = await _call(api, "hearth_allow", person="Sam", app="x:paused")
    assert result["id"]


async def test_a_switch_game_off_its_allow_list_is_never_allowed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from homeassistant.core import ServiceCall, SupportsResponse

    from test_enforce import NINTENDO_LIMIT, _add_enforcer, _nintendo_switch

    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    _nintendo_switch(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": NINTENDO_LIMIT})
    asked: list[ServiceCall] = []

    async def list_applications(call: ServiceCall):
        asked.append(call)
        return {
            "applications": [
                {"application_id": "0100AAA", "name": "Blaster Arena", "allowed": False},
                {"application_id": "0100BBB", "name": "Puzzle Pals", "allowed": True},
            ]
        }

    hass.services.async_register(
        "nintendo_parental_controls", "list_applications", list_applications, supports_response=SupportsResponse.ONLY
    )
    await _options(hass, voice_assistants=True)
    api = await _api(hass, users["alex"])
    for app in ("Blaster Arena", "blaster arena", "0100AAA"):
        with pytest.raises(HomeAssistantError, match="allow list of Sam's Switch in the Nintendo app"):
            await _call(api, "hearth_allow", person="Sam", app=app)
    assert asked and asked[0].data["device_id"]
    # Not by voice either: nothing goes to the phones
    voice = await _api(hass, platform="openai_conversation")
    with pytest.raises(HomeAssistantError, match="Nintendo app"):
        await _call(voice, "hearth_allow", person="Sam", app="Blaster Arena")
    assert not _sent_to(sent)
    # A game on the allow list isn't refused for Nintendo (Hearth just doesn't know it as an app), and an app that
    # isn't a Switch game goes ahead
    with pytest.raises(HomeAssistantError, match="doesn't know an app called Puzzle Pals"):
        await _call(api, "hearth_allow", person="Sam", app="Puzzle Pals")
    assert (await _call(api, "hearth_allow", person="Sam", app="com.example.other"))["id"]
