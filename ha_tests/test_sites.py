"""hearth.copy_sites: websites copied between Family Link and Family Safety, only ever added."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.sites import host_of
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
FAMILY_SAFETY = "sensor.sam_xbox_screen_time"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def test_a_site_is_compared_by_its_host() -> None:
    assert host_of("https://www.Example.org/") == "example.org"
    assert host_of("*.example.org") == "example.org"
    assert host_of("example.org/") == "example.org"
    assert host_of("http://sub.example.org") == "sub.example.org"
    # A path or another wildcard would widen it
    assert host_of("example.org/games") is None
    assert host_of("https://example.org/page?x=1") is None
    assert host_of("*.example.*") is None
    assert host_of("localhost") is None


class Sides:
    """Stub Family Link and Family Safety site services, with their lists."""

    def __init__(self, hass: HomeAssistant, fl: dict, fs: dict, fs_fails: bool = False) -> None:
        self.fl, self.fs = fl, fs
        self.writes: list[tuple[str, str, dict]] = []

        def reader(lists):
            async def read(call: ServiceCall):
                return dict(lists)

            return read

        def writer(domain: str, service: str, fails: bool = False):
            async def write(call: ServiceCall) -> None:
                if fails:
                    raise HomeAssistantError("Microsoft said no")
                self.writes.append((domain, service, dict(call.data)))

            return write

        hass.services.async_register("familylink", "get_sites", reader(fl), supports_response=SupportsResponse.ONLY)
        hass.services.async_register(
            "microsoft_family_safety", "get_sites", reader(fs), supports_response=SupportsResponse.OPTIONAL
        )
        for service in ("block_site", "allow_site"):
            hass.services.async_register("familylink", service, writer("familylink", service))
        for service in ("block_website", "allow_website"):
            hass.services.async_register(
                "microsoft_family_safety", service, writer("microsoft_family_safety", service, fs_fails)
            )


async def _sam_with_both(hass: HomeAssistant, hass_client_no_auth) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(
        hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "family_safety": FAMILY_SAFETY}
    )


async def _copy(hass: HomeAssistant, **data):
    return await hass.services.async_call(DOMAIN, "copy_sites", data, blocking=True, return_response=True)


FL_LISTS = {
    "child_id": "42",
    "filter_level": "block_mature",
    "blocked": ["*.games.example", "games.example", "example.org/chat", "*.both.example", "*.listed.example",
                "conflict.example"],
    "approved": ["school.example"],
    "from_list": ["*.listed.example"],
    "from_list_by_url": {},
}
FS_LISTS = {
    "blocked": ["https://www.both.example/", "https://fs-only.example/", "https://fslisted.example/"],
    "allowed": ["https://conflict.example/"],
    "filter_enabled": True,
    "from_list": ["fslisted.example"],
    "from_list_by_url": {},
}


async def test_blocked_sites_are_copied_both_ways_and_only_added(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass, FL_LISTS, FS_LISTS)
    await _sam_with_both(hass, hass_client_no_auth)
    result = (await _copy(hass))["person.sam"]
    assert result["added_to_fs"] == {"blocked": ["games.example"]}
    assert result["added_to_fl"] == {"blocked": ["fs-only.example"]}
    assert result["skipped_from_list"] == ["fslisted.example", "listed.example"]
    assert result["conflicts"] == [{"site": "conflict.example", "family_link": "blocked", "family_safety": "allowed"}]
    assert result["not_copyable"] == [{"site": "example.org/chat", "from": "family_link", "list": "blocked"}]
    assert sorted((d, s) for d, s, _ in sides.writes) == [
        ("familylink", "block_site"),
        ("microsoft_family_safety", "block_website"),
    ]
    fl_write = next(data for d, _, data in sides.writes if d == "familylink")
    # As Family Link's own list sync writes a domain
    assert fl_write == {"entity_id": FAMILY_LINK, "sites": ["*.fs-only.example", "fs-only.example"]}
    fs_write = next(data for d, _, data in sides.writes if d == "microsoft_family_safety")
    assert fs_write == {"entity_id": FAMILY_SAFETY, "website": ["games.example"]}


async def test_a_dry_run_writes_nothing_and_one_side_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass, FL_LISTS, FS_LISTS)
    await _sam_with_both(hass, hass_client_no_auth)
    result = (await _copy(hass, **{"from": "family_safety", "lists": "both", "dry_run": True}))["person.sam"]
    assert result["added_to_fl"] == {"blocked": ["fs-only.example"], "allowed": []}
    assert result["added_to_fs"] == {"blocked": [], "allowed": []}
    assert result["conflicts"][0]["site"] == "conflict.example"
    assert sides.writes == []


async def test_allowed_sites_go_to_family_link_as_the_site_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass, FL_LISTS, {**FS_LISTS, "allowed": ["https://homework.example/"]})
    await _sam_with_both(hass, hass_client_no_auth)
    result = (await _copy(hass, lists="allowed"))["person.sam"]
    assert result["added_to_fl"] == {"allowed": ["homework.example"]}
    assert result["added_to_fs"] == {"allowed": ["school.example"]}
    assert ("familylink", "allow_site", {"entity_id": FAMILY_LINK, "sites": ["homework.example"]}) in sides.writes
    assert (
        "microsoft_family_safety",
        "allow_website",
        {"entity_id": FAMILY_SAFETY, "website": ["school.example"]},
    ) in sides.writes


async def test_a_person_missing_a_side_is_said_and_a_failure_is_told(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass, FL_LISTS, FS_LISTS, fs_fails=True)
    await _sam_with_both(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.alex", "family_link": "sensor.alex_family_link_daily_screen_time"})
    # Everyone with both by default: Alex isn't one
    assert list(await _copy(hass)) == ["person.sam"]
    result = await _copy(hass, people=["person.sam", "person.alex"])
    assert result["person.alex"] == {"missing": ["family_safety"]}
    assert result["person.sam"]["added_to_fs"] == {"blocked": []}
    assert "Microsoft said no" in result["person.sam"]["error"]
    # Family Link's side still went
    assert result["person.sam"]["added_to_fl"] == {"blocked": ["fs-only.example"]}
    assert any(d == "familylink" for d, _, _ in sides.writes)
    with pytest.raises(ServiceValidationError):
        await _copy(hass, people=["person.nobody"])


async def test_an_older_family_safety_without_get_sites_is_a_missing_side(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.services.async_register(
        "familylink", "get_sites", lambda call: dict(FL_LISTS), supports_response=SupportsResponse.ONLY
    )
    await _sam_with_both(hass, hass_client_no_auth)
    assert (await _copy(hass))["person.sam"] == {"missing": ["family_safety"]}
