"""hearth.block_site and hearth.unblock_site: websites an adult blocks by hand, next to the daily website list."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.site_blocks import ON_LIST, OUTSIDE, normalize
from test_enforce import _add_enforcer
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
FAMILY_SAFETY = "sensor.sam_xbox_screen_time"
URL = "https://example.com/blocklist.txt"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


class Sides:
    """Stub Family Link and Family Safety site services that keep their lists."""

    def __init__(self, hass: HomeAssistant) -> None:
        self.fl_blocked: list[str] = []
        self.fl_from_list: list[str] = []
        self.fs_blocked: list[str] = []
        self.writes: list[tuple[str, str, dict]] = []
        self.fail: set[tuple[str, str]] = set()

        async def fl_get(call: ServiceCall):
            return {
                "child_id": "42",
                "blocked": list(self.fl_blocked),
                "approved": [],
                "from_list": [p for p in self.fl_from_list if p in self.fl_blocked],
            }

        async def fs_get(call: ServiceCall):
            return {"blocked": list(self.fs_blocked), "allowed": [], "filter_enabled": True}

        def writer(domain: str, service: str):
            async def write(call: ServiceCall) -> None:
                if (domain, service) in self.fail:
                    raise HomeAssistantError("the provider said no")
                self.writes.append((domain, service, dict(call.data)))
                if domain == "familylink":
                    for site in call.data["sites"]:
                        if service == "block_site" and site not in self.fl_blocked:
                            self.fl_blocked.append(site)
                        elif service == "remove_site" and site in self.fl_blocked:
                            self.fl_blocked.remove(site)
                else:
                    for site in call.data["website"]:
                        url = f"https://{site}/"
                        if service == "block_website" and url not in self.fs_blocked:
                            self.fs_blocked.append(url)
                        elif service == "remove_website" and url in self.fs_blocked:
                            self.fs_blocked.remove(url)

            return write

        hass.services.async_register("familylink", "get_sites", fl_get, supports_response=SupportsResponse.ONLY)
        hass.services.async_register(
            "microsoft_family_safety", "get_sites", fs_get, supports_response=SupportsResponse.OPTIONAL
        )
        for service in ("block_site", "remove_site"):
            hass.services.async_register("familylink", service, writer("familylink", service))
        for service in ("block_website", "remove_website"):
            hass.services.async_register("microsoft_family_safety", service, writer("microsoft_family_safety", service))

    def of(self, domain: str, service: str) -> list[dict]:
        return [data for d, s, data in self.writes if (d, s) == (domain, service)]


async def _sam_with_both(hass: HomeAssistant, hass_client_no_auth):
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "family_safety": FAMILY_SAFETY, "fl_backstop": False},
    )
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _call(hass: HomeAssistant, service: str, **data):
    return await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=True)


def test_a_site_is_cut_down_to_its_domain_and_odd_ones_are_refused() -> None:
    assert normalize("https://www.Example.com:8443/games?x=1#top") == "example.com"
    assert normalize("tumblr.com") == "tumblr.com"
    assert normalize("WWW.tumblr.com.") == "tumblr.com"
    assert normalize("http://user@sub.example.org/") == "sub.example.org"
    for wrong in ("1.2.3.4", "https://10.0.0.1/", "[::1]", "*.example.com", "example.*", "co.uk", "www.co.uk",
                  "localhost", "", "two words.com", "exa_mple.com"):
        with pytest.raises(ValueError):
            normalize(wrong)


async def test_a_site_is_blocked_on_both_sides_in_both_forms_and_shown(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    household = await _sam_with_both(hass, hass_client_no_auth)
    result = await _call(hass, "block_site", people=["person.sam"], sites="https://www.Tumblr.com/dashboard")
    assert result == {
        "person.sam": {
            "family_link": {"done": ["tumblr.com"], "already": [], "failed": []},
            "family_safety": {"done": ["tumblr.com"], "already": [], "failed": []},
        }
    }
    # Family Link's *.example.com may not cover the bare domain: both go
    assert sides.of("familylink", "block_site") == [{"entity_id": FAMILY_LINK, "sites": ["*.tumblr.com", "tumblr.com"]}]
    assert sides.of("microsoft_family_safety", "block_website") == [{"entity_id": FAMILY_SAFETY, "website": ["tumblr.com"]}]
    assert household.exceptions_of("person.sam")["blocked_sites"] == {
        "family_link": ["tumblr.com"],
        "family_safety": ["tumblr.com"],
    }
    assert hass.states.get("sensor.hearth_sam_screen_time_today").attributes["exceptions"]["blocked_sites"] == {
        "family_link": ["tumblr.com"],
        "family_safety": ["tumblr.com"],
    }
    # Again: already blocked, nothing sent
    again = await _call(hass, "block_site", sites=["tumblr.com"])
    assert again["person.sam"]["family_link"] == {"done": [], "already": ["tumblr.com"], "failed": []}
    assert len(sides.writes) == 2
    # Recorded in the action log as Hearth's own calls, by person
    calls = household.activity.query(person="person.sam", kind="call")
    services = {c["service"] for c in calls}
    assert {"familylink.block_site", "microsoft_family_safety.block_website"} <= services


async def test_odd_sites_and_people_without_a_side_are_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    await _sam_with_both(hass, hass_client_no_auth)
    for site in ("192.168.1.1", "*.example.com", "co.uk"):
        with pytest.raises(ServiceValidationError):
            await _call(hass, "block_site", sites=[site])
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    with pytest.raises(ServiceValidationError, match="Alex"):
        await _call(hass, "block_site", people=["person.alex"], sites=["example.com"])
    assert sides.writes == []


async def test_everyone_with_family_link_or_family_safety_by_default(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    await _sam_with_both(hass, hass_client_no_auth)
    # Alex has Family Safety only, by a typed-in account id
    await _add_enforcer(hass, {"kind": "family_safety", "person": "person.alex", "entity_id": "123456"})
    result = await _call(hass, "block_site", sites=["example.org"])
    assert set(result) == {"person.alex", "person.sam"}
    assert set(result["person.alex"]) == {"family_safety"}
    assert set(result["person.sam"]) == {"family_link", "family_safety"}
    assert {"account_id": "123456", "website": ["example.org"]} in sides.of("microsoft_family_safety", "block_website")


async def test_unblock_takes_back_only_what_hearth_added(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    # A parent's own blocks: *.games.example in Family Link, other.example in Family Safety
    sides.fl_blocked = ["*.games.example"]
    sides.fs_blocked = ["https://other.example/"]
    household = await _sam_with_both(hass, hass_client_no_auth)
    await _call(hass, "block_site", sites=["games.example"])
    # Only the form that was missing is Hearth's
    assert sides.of("familylink", "block_site") == [{"entity_id": FAMILY_LINK, "sites": ["games.example"]}]

    result = await _call(hass, "unblock_site", sites=["games.example", "other.example", "never.example"])
    fl = result["person.sam"]["family_link"]
    assert fl["done"] == ["games.example"]
    assert {"site": "games.example", "reason": OUTSIDE, "patterns": ["*.games.example"]} in fl["kept"]
    assert fl["already"] == ["other.example", "never.example"]
    fs = result["person.sam"]["family_safety"]
    assert fs["done"] == ["games.example"]
    assert fs["kept"] == [{"site": "other.example", "reason": OUTSIDE}]
    assert fs["already"] == ["never.example"]
    assert sides.of("familylink", "remove_site") == [{"entity_id": FAMILY_LINK, "sites": ["games.example"]}]
    assert sides.of("microsoft_family_safety", "remove_website") == [{"entity_id": FAMILY_SAFETY, "website": ["games.example"]}]
    assert sides.fl_blocked == ["*.games.example"]
    assert sides.fs_blocked == ["https://other.example/"]
    assert household.exceptions_of("person.sam")["blocked_sites"] == {}


async def test_a_site_on_the_website_list_stays_when_unblocked_by_hand(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    sides.fl_blocked = ["*.listed.example", "listed.example"]
    sides.fl_from_list = ["*.listed.example", "listed.example"]
    household = await _sam_with_both(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    # Hearth's own Family Safety sync added it from the list
    household.scheduler.fs_sites.owned = {FAMILY_SAFETY: {URL: ["listed.example"]}}
    sides.fs_blocked = ["https://listed.example/"]
    result = await _call(hass, "block_site", sites=["listed.example"], people=["person.sam"])
    assert result["person.sam"]["family_link"]["already"] == ["listed.example"]
    assert result["person.sam"]["family_safety"]["already"] == ["listed.example"]
    # Claimed: shown as a hand block too
    assert household.exceptions_of("person.sam")["blocked_sites"] == {
        "family_link": ["listed.example"],
        "family_safety": ["listed.example"],
    }
    result = await _call(hass, "unblock_site", sites=["listed.example"])
    assert result["person.sam"]["family_link"]["kept"] == [{"site": "listed.example", "reason": ON_LIST}]
    assert result["person.sam"]["family_safety"]["kept"] == [{"site": "listed.example", "reason": ON_LIST}]
    assert sides.of("familylink", "remove_site") == [] and sides.of("microsoft_family_safety", "remove_website") == []
    assert household.exceptions_of("person.sam")["blocked_sites"] == {}
    assert entry.state.value == "loaded"


async def test_the_family_link_list_sync_doesn_t_open_a_hand_block(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    sides.fl_blocked = ["*.listed.example", "listed.example", "*.other.example", "other.example"]
    sides.fl_from_list = list(sides.fl_blocked)
    syncs: list[dict] = []

    async def sync(call: ServiceCall) -> None:
        # The list dropped both: its sync takes out what it added
        syncs.append(dict(call.data))
        sides.fl_blocked = [p for p in sides.fl_blocked if p not in sides.fl_from_list]
        sides.fl_from_list = []

    hass.services.async_register("familylink", "sync_site_list", sync)
    household = await _sam_with_both(hass, hass_client_no_auth)
    await _call(hass, "block_site", sites=["listed.example"], people=["person.sam"])
    await household.scheduler._sync_sites(
        "person.sam", "family_link", "familylink", {"entity_id": FAMILY_LINK, "url": URL}
    )
    assert syncs == [{"entity_id": FAMILY_LINK, "url": URL}]
    # The hand block is back; the list's other site is gone
    assert sorted(sides.fl_blocked) == ["*.listed.example", "listed.example"]
    assert sides.of("familylink", "block_site")[-1] == {
        "entity_id": FAMILY_LINK,
        "sites": ["*.listed.example", "listed.example"],
    }
    # Now it's the hand block's alone: an unblock takes it out
    result = await _call(hass, "unblock_site", sites=["listed.example"], people=["person.sam"])
    assert result["person.sam"]["family_link"]["done"] == ["listed.example"]
    assert sides.fl_blocked == []


async def test_hearth_s_own_family_safety_sync_leaves_a_hand_block(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    household = await _sam_with_both(hass, hass_client_no_auth)
    scheduler = household.scheduler
    scheduler.fs_sites.owned = {FAMILY_SAFETY: {URL: ["listed.example", "kept.example"]}}
    sides.fs_blocked = ["https://listed.example/", "https://kept.example/"]
    await _call(hass, "block_site", sites=["listed.example"], people=["person.sam"])
    # The list dropped listed.example
    result = await scheduler._fs_own_sync(
        {"entity_id": FAMILY_SAFETY}, URL, {"domains": ["kept.example"]}, "person.sam"
    )
    assert result["removed"] == []
    assert sides.of("microsoft_family_safety", "remove_website") == []
    assert sorted(sides.fs_blocked) == ["https://kept.example/", "https://listed.example/"]
    # No longer the list's: the hand block's alone
    assert scheduler.fs_sites.owned[FAMILY_SAFETY][URL] == ["kept.example"]
    result = await _call(hass, "unblock_site", sites=["listed.example"], people=["person.sam"])
    assert result["person.sam"]["family_safety"]["done"] == ["listed.example"]
    assert sides.fs_blocked == ["https://kept.example/"]


async def test_hand_blocks_are_kept_over_a_reload(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    await _sam_with_both(hass, hass_client_no_auth)
    await _call(hass, "block_site", sites=["tumblr.com"])
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    household = entry.runtime_data.household
    assert household.exceptions_of("person.sam")["blocked_sites"] == {
        "family_link": ["tumblr.com"],
        "family_safety": ["tumblr.com"],
    }
    result = await _call(hass, "unblock_site", sites=["tumblr.com"])
    assert result["person.sam"]["family_link"]["done"] == ["tumblr.com"]
    assert sides.fl_blocked == [] and sides.fs_blocked == []


async def test_a_failure_on_one_side_doesn_t_stop_the_other(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    sides.fail.add(("microsoft_family_safety", "block_website"))
    household = await _sam_with_both(hass, hass_client_no_auth)
    result = await _call(hass, "block_site", sites=["tumblr.com"])
    assert result["person.sam"]["family_link"]["done"] == ["tumblr.com"]
    fs = result["person.sam"]["family_safety"]
    assert fs["done"] == [] and fs["failed"][0]["site"] == "tumblr.com"
    assert "said no" in fs["failed"][0]["error"]
    # Only what was blocked is recorded
    assert household.exceptions_of("person.sam")["blocked_sites"] == {"family_link": ["tumblr.com"]}


async def test_hand_site_writes_are_never_told_as_outside_changes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    Sides(hass)
    household = await _sam_with_both(hass, hass_client_no_auth)
    told: list[tuple] = []
    household.outside_apps._tell = lambda *args: told.append(args)
    household.outside_apps.check()
    await _call(hass, "block_site", sites=["tumblr.com"])
    await _call(hass, "unblock_site", sites=["tumblr.com"])
    household.outside_apps.check()
    await hass.async_block_till_done()
    assert told == []
    # Every write went through Hearth's action log (activity.call_service), as Hearth's own
    services = [c["service"] for c in household.activity.query(person="person.sam", kind="call")]
    for service in ("familylink.block_site", "familylink.remove_site", "microsoft_family_safety.block_website",
                    "microsoft_family_safety.remove_website"):
        assert service in services


async def test_a_list_sync_that_fails_part_way_still_gives_the_hand_block_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    sides = Sides(hass)
    sides.fl_blocked = ["*.listed.example", "listed.example"]
    sides.fl_from_list = list(sides.fl_blocked)

    async def sync(call: ServiceCall) -> None:
        sides.fl_blocked = []
        sides.fl_from_list = []
        raise HomeAssistantError("Google stopped part-way")

    hass.services.async_register("familylink", "sync_site_list", sync)
    household = await _sam_with_both(hass, hass_client_no_auth)
    await _call(hass, "block_site", sites=["listed.example"], people=["person.sam"])
    await household.scheduler._sync_sites(
        "person.sam", "family_link", "familylink", {"entity_id": FAMILY_LINK, "url": URL}
    )
    assert sorted(sides.fl_blocked) == ["*.listed.example", "listed.example"]
