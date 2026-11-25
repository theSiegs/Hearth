"""An allow of an Xbox app while daily time locks the Xbox whole (docs/home-assistant-integration.md, Allowing one app
on a platform locked whole): Hearth swaps the Xbox lock for a pause of every other Xbox app, with Family Link's dwell
and swap breaker, and falls back to the lock (said in hearth.allow's not_on and hearth.explain's platform_lock) when it
can't. Windows is never swapped."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import app_blocks, enforce
from custom_components.hearth.const import DOMAIN
from test_enforce import FAMILY_SAFETY, _budget, settled  # noqa: F401 - the fixture
from test_people import _household_with_sam
from test_sources import _option

FS = "microsoft_family_safety"
APPS = "sensor.sam_applications"
MINECRAFT = "x:1828326430"
RACER = "x:racer"
EDGE = "x:edge"
PARENTS = "x:parents_block"
PAINT = "appx:Example.Paint"
KEY = f"{enforce.FAMILY_SAFETY}|person.sam"
NAMES = {MINECRAFT: "Minecraft", RACER: "Racer", EDGE: "Microsoft Edge", PARENTS: "Shooter", PAINT: "Paint"}


@pytest.fixture(autouse=True)
def swap_on(monkeypatch, request):
    """The swap is off by default (XBOX_SWAP): these tests cover it turned on, but the one about the default."""
    if "swap_off" not in request.keywords:
        monkeypatch.setattr(enforce, "XBOX_SWAP", True)


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _applications(
    hass: HomeAssistant, apps=(MINECRAFT, RACER, EDGE, PARENTS, PAINT), blocked=(PARENTS,), paused=(), **attrs
) -> None:
    """Sam's Family Safety Applications sensor: the parent blocked Shooter in the Family Safety app. [paused] None: a
    Family Safety that keeps no record of its pauses."""
    data = {
        "user_id": 123456,
        "applications": [{"app_id": a, "app_name": NAMES.get(a, a), "blocked": a in blocked} for a in apps],
        "paused_apps": None if paused is None else [{"app_id": a, "app_name": a, "paused": "ours"} for a in paused],
        **attrs,
    }
    if data["paused_apps"] is None:
        del data["paused_apps"]
    hass.states.async_set(APPS, str(len(apps)), data)


def _services(hass: HomeAssistant, pause: bool = True) -> list[tuple[str, dict]]:
    """Family Safety's services, every call in one list, in order."""
    calls: list[tuple[str, dict]] = []
    names = ["lock_platform", "unlock_platform", "block_app", "unblock_app", "add_time_bonus"]
    names += ["pause_app", "resume_app"] if pause else []
    for name in names:

        async def handle(call: ServiceCall, _name=name) -> None:
            calls.append((_name, dict(call.data)))

        hass.services.async_register(FS, name, handle)
    return calls


def _of(calls: list[tuple[str, dict]], service: str) -> list[dict]:
    return [data for name, data in calls if name == service]


async def _sam_out_of_time(
    hass: HomeAssistant, hass_client_no_auth, freezer, platforms=("Xbox",), pause: bool = True, **apps
) -> list[tuple[str, dict]]:
    """Sam with Family Safety on the Xbox (and [platforms]), All screen time used up: the Xbox locked whole."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    calls = _services(hass, pause)
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    _applications(hass, **apps)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(
        hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY, "platforms": list(platforms)}
    )
    await _budget(hass, "all", 5)
    assert [d["platform"] for d in _of(calls, "lock_platform")] == sorted(platforms)
    return calls


async def _allow(hass: HomeAssistant, until: str = "13:00", **what) -> dict:
    answer = await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "until": until, **what}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    return answer


async def _end(hass: HomeAssistant, allow_id: str) -> None:
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()


async def _explain(hass: HomeAssistant, app: str) -> dict:
    return await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": app}, blocking=True, return_response=True
    )


async def test_allowing_an_xbox_app_swaps_the_lock_for_a_pause_of_the_others(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    answer = await _allow(hass, app=MINECRAFT)
    assert "not_on" not in answer
    # Every other Xbox app paused (never the allowed one, Edge, a parent's block or a Windows app), then unlocked
    assert _of(calls, "pause_app") == [{"entity_id": FAMILY_SAFETY, "apps": [RACER]}]
    assert [name for name, _ in calls].index("pause_app") < [name for name, _ in calls].index("unlock_platform")
    held = _household(hass).enforcement.held[KEY]
    assert held.items == {RACER}
    explained = await _explain(hass, MINECRAFT)
    assert explained["allowed"] is True
    assert all(b["kind"] != "platform_lock" for b in explained["blocked_by"])
    # The parent's block still holds Shooter: an allow never lifts a block
    explained = await _explain(hass, PARENTS)
    assert any(b["kind"] == "blocked_app" for b in explained["blocked_by"])

    # The allow ends: the Xbox is locked whole again first, then the apps are resumed
    del calls[:]
    await _end(hass, answer["id"])
    assert [name for name, _ in calls] == ["lock_platform", "resume_app"]
    assert _of(calls, "resume_app") == [{"entity_id": FAMILY_SAFETY, "apps": [RACER]}]
    assert _household(hass).enforcement.held[KEY].items == {"Xbox"}


async def test_allowing_a_group_with_xbox_apps_swaps_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _option(hass, "group_apps", {"games": [MINECRAFT]})
    await _allow(hass, group="games")
    assert _of(calls, "pause_app") == [{"entity_id": FAMILY_SAFETY, "apps": [RACER]}]
    assert _of(calls, "unlock_platform") == [{"entity_id": FAMILY_SAFETY, "platform": "Xbox"}]


async def test_the_swap_waits_after_a_swap_and_the_breaker_keeps_the_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    first = await _allow(hass, app=MINECRAFT, until="15:00")
    await _end(hass, first["id"])
    # Within 10 minutes of the last swap: the lock stays, and the answer says so
    answer = await _allow(hass, app=MINECRAFT, until="15:00")
    assert answer["not_on"][0]["platform"] == "Xbox" and answer["not_on"][0]["why"] == enforce.NOT_ON_DWELL
    assert len(_of(calls, "pause_app")) == 1
    explained = await _explain(hass, MINECRAFT)
    [lock] = [b for b in explained["blocked_by"] if b["kind"] == "platform_lock"]
    assert lock["why"] == enforce.NOT_ON_DWELL
    assert {"service": "hearth.allow", "device": "fs:xbox"} in lock["lift_with"]
    # Past the wait: swapped
    freezer.tick(timedelta(minutes=11))
    await _budget(hass, "all", 5)
    assert len(_of(calls, "pause_app")) == 2
    # The breaker: 4 swaps within the hour keep the lock for an hour
    await _end(hass, answer["id"])  # swap 3
    freezer.tick(timedelta(minutes=11))
    third = await _allow(hass, app=MINECRAFT, until="15:00")  # swap 4
    await _end(hass, third["id"])  # swap 5 back to the lock
    freezer.tick(timedelta(minutes=11))
    answer = await _allow(hass, app=MINECRAFT, until="15:00")
    assert answer["not_on"][0]["why"] == enforce.NOT_ON_DWELL
    assert _household(hass).enforcement._swaps[KEY]["until"] is not None


@pytest.mark.parametrize(
    ("apps", "pause", "why"),
    [
        # enforce.NOT_ON_LIST, NOT_ON_NO_TRACKING, NOT_ON_NOT_INSTALLED, NOT_ON_TOO_MANY, NOT_ON_NO_PAUSE_APP
        ({"truncated": True}, True, "applications_list_unknown"),
        ({"paused": None}, True, "family_safety_pauses_not_readable"),
        ({"apps": (RACER, EDGE)}, True, "allowed_app_not_listed"),
        ({"blocked": (MINECRAFT,)}, True, "allowed_app_blocked"),
        ({"apps": (MINECRAFT, *(f"x:game{i}" for i in range(151)))}, True, "too_many_apps"),
        ({}, False, "family_safety_cannot_pause_apps"),
    ],
)
async def test_the_xbox_stays_locked_whole_when_the_swap_can_t_be_made(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, apps, pause, why
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer, pause=pause, **apps)
    answer = await _allow(hass, app=MINECRAFT)
    assert answer["not_on"] == [
        {"person": "person.sam", "platform": "Xbox", "why": why, "text": answer["not_on"][0]["text"]}
    ]
    assert "fs:xbox" in answer["not_on"][0]["text"]
    assert _of(calls, "pause_app") == [] and _of(calls, "unlock_platform") == []
    assert _household(hass).enforcement.held[KEY].items == {"Xbox"}


async def test_a_pause_or_the_schedule_keeps_the_xbox_locked(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    await hass.services.async_call(DOMAIN, "pause", {"people": ["person.sam"], "minutes": 60}, blocking=True)
    await hass.async_block_till_done()
    answer = await _allow(hass, app=MINECRAFT)
    assert answer["not_on"][0]["why"] == enforce.NOT_ON_HELD
    assert _of(calls, "pause_app") == []


async def test_windows_is_never_swapped(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer, platforms=("Xbox", "Windows"))
    answer = await _allow(hass, app=PAINT)
    assert [(n["platform"], n["why"]) for n in answer["not_on"]] == [("Windows", enforce.NOT_ON_WINDOWS)]
    assert "fs:windows" in answer["not_on"][0]["text"]
    assert _of(calls, "unlock_platform") == [] and _of(calls, "pause_app") == []
    explained = await _explain(hass, PAINT)
    assert explained["allowed"] is False
    [lock] = [b for b in explained["blocked_by"] if b["kind"] == "platform_lock"]
    assert (lock["platform"], lock["why"]) == ("Windows", enforce.NOT_ON_WINDOWS)
    assert lock["lift_with"] == [
        {"service": "hearth.allow", "device": "fs:windows"}, {"service": "hearth.add_bonus", "device": "fs:windows"}
    ]
    # An Xbox app next to it still swaps the Xbox alone
    await _allow(hass, app=MINECRAFT)
    assert _of(calls, "unlock_platform") == [{"entity_id": FAMILY_SAFETY, "platform": "Xbox"}]


async def test_hearth_s_block_of_an_xbox_app_is_left_to_the_block_under_a_swap(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    """hearth.block_app of an app the swap pauses: the swap leaves it out (resumed first, Hearth's block then waits
    for no pause), and Hearth's own block is never paused by a swap."""
    monkeypatch.setattr(app_blocks, "QUIET", timedelta(0))
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _allow(hass, app=MINECRAFT)
    assert _of(calls, "pause_app") == [{"entity_id": FAMILY_SAFETY, "apps": [RACER]}]
    del calls[:]
    await hass.services.async_call(DOMAIN, "block_app", {"people": ["person.sam"], "app": RACER}, blocking=True)
    await hass.async_block_till_done()
    names = [name for name, _ in calls]
    assert names.index("resume_app") < names.index("block_app")
    assert _of(calls, "block_app") == [{"entity_id": FAMILY_SAFETY, "app_id": RACER}]
    # Blocked: never paused by the swap again
    _applications(hass, blocked=(PARENTS, RACER))
    _household(hass).recompute()
    await hass.async_block_till_done()
    assert len(_of(calls, "pause_app")) == 0


@pytest.mark.swap_off
async def test_by_default_the_xbox_stays_locked_and_the_allow_says_why(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Safety's Xbox list doesn't hold every game played, so pausing "every other app" would open the rest."""
    calls = await _sam_out_of_time(hass, hass_client_no_auth, freezer)
    answer = await _allow(hass, app=MINECRAFT)
    assert answer["not_on"][0]["platform"] == "Xbox"
    assert answer["not_on"][0]["why"] == enforce.NOT_ON_UNLISTED
    assert _of(calls, "pause_app") == [] and _of(calls, "unlock_platform") == []
    assert _household(hass).enforcement.held[KEY].items == {"Xbox"}
