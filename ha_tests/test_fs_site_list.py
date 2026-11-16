"""The website block list kept in Family Safety by Hearth itself, on the released Family Safety (no sync_site_list):
the list downloaded once, get_sites read, missing sites blocked, only Hearth's own dropped ones unblocked, failures per
site as upstream names them, and what Hearth added kept across a restart."""

from datetime import date

import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.storage import Store
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_capture_events
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import fs_site_list
from custom_components.hearth.const import DOMAIN
from test_enforce import _add_enforcer
from test_schedule import URL, YEAR, _at, _set_up, _tick, settled  # noqa: F401 - the fixture
from test_sources import _option

FS = "microsoft_family_safety"
SAM_FS = "sensor.sam_xbox_screen_time"
ACCOUNT = "123456"
MONDAY = date(2026, 11, 9)


class FakeFamilySafety:
    """Upstream's get_sites, block_website and remove_website over one kid's lists (Microsoft's absolute URLs).
    [failing]: sites whose write fails, answered as upstream does (the sites done and the sites failed)."""

    def __init__(self, hass: HomeAssistant, blocked=(), allowed=()) -> None:
        self.blocked = [f"https://{s}/" for s in blocked]
        self.allowed = [f"https://{s}/" for s in allowed]
        self.failing: set[str] = set()
        self.calls: list[ServiceCall] = []
        target = {vol.Optional("account_id"): cv.string, vol.Optional("entity_id"): cv.entity_ids}
        websites = vol.All(cv.ensure_list, [cv.string], vol.Length(min=1))
        hass.services.async_register(
            FS, "get_sites", self._get, schema=vol.Schema(target), supports_response=SupportsResponse.ONLY
        )
        for service in ("block_website", "remove_website", "allow_website"):
            hass.services.async_register(
                FS, service, self._write, schema=vol.Schema({**target, vol.Required("website"): websites}),
                supports_response=SupportsResponse.OPTIONAL,
            )

    async def _get(self, call: ServiceCall):
        self.calls.append(call)
        return {"account_id": ACCOUNT, "blocked": list(self.blocked), "allowed": list(self.allowed),
                "filter_enabled": True}

    async def _write(self, call: ServiceCall):
        self.calls.append(call)
        done, failed = [], {}
        for site in call.data["website"]:
            if site in self.failing:
                failed[site] = "HTTP 500"
                continue
            url = f"https://{site}/"
            if call.service == "block_website" and url not in self.blocked:
                self.blocked.append(url)
            elif call.service == "remove_website" and url in self.blocked:
                self.blocked.remove(url)
            done.append(site)
        if failed:
            raise HomeAssistantError(
                f"{call.service}: {len(failed)} of {len(done) + len(failed)} site(s) failed. "
                f"Done: {', '.join(done) or 'none'}. Failed: "
                + "; ".join(f"{site} ({error})" for site, error in failed.items())
            )
        return {"done": done, "failed": []} if call.return_response else None

    def hosts(self) -> list[str]:
        return sorted(u.split("://", 1)[1].rstrip("/") for u in self.blocked)

    def writes(self, service: str) -> list[list[str]]:
        return [list(c.data["website"]) for c in self.calls if c.service == service]


async def _sam(hass, hass_client_no_auth, freezer, aioclient_mock: AiohttpClientMocker, text: str, **lists):
    fs = FakeFamilySafety(hass, **lists)
    aioclient_mock.get(URL, text=text)
    household = await _set_up(hass, hass_client_no_auth, freezer, _at(MONDAY, 7), YEAR, {})
    hass.states.async_set(SAM_FS, "0", {"user_id": ACCOUNT})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": SAM_FS})
    await _option(hass, "site_list", {"url": URL, "time": "07:30:00"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    return fs, household


async def test_hearth_blocks_the_list_s_new_sites_itself(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    events = async_capture_events(hass, "hearth_schedule")
    text = "# games\n0.0.0.0 games.example\nvideos.example\nhand.example\nnot a domain/\nco.uk\nfriend.example\n"
    fs, household = await _sam(
        hass, hass_client_no_auth, freezer, aioclient_mock, text,
        blocked=["hand.example", "parent.example"], allowed=["www.friend.example"],
    )
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    # Only what's missing; friend.example would block the allowed www.friend.example
    assert fs.writes("block_website") == [["games.example", "videos.example"]]
    assert fs.writes("remove_website") == []
    assert fs.hosts() == ["games.example", "hand.example", "parent.example", "videos.example"]
    # Hearth owns what it added, not what was blocked already
    assert household.scheduler.fs_sites.owned[ACCOUNT][URL] == ["games.example", "videos.example"]
    [event] = [e.data for e in events if e.data["action"] == "site_list"]
    assert (event["via"], event["by"], event["added"], event["kept"], event["skipped_allowed"], event["failed"]) == (
        "family_safety", "hearth", 2, 1, 1, []
    )
    # Once a day
    await _tick(hass, household, freezer, _at(MONDAY, 7, 45))
    assert len(fs.writes("block_website")) == 1


async def test_only_hearth_s_own_dropped_sites_are_unblocked_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    fs, household = await _sam(
        hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\nvideos.example\n", blocked=["parent.example"]
    )
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    # A restart: what Hearth added comes back from storage
    await household.scheduler.async_flush()
    household.scheduler.fs_sites.owned = {}
    await household.scheduler.async_load()
    assert household.scheduler.fs_sites.owned[ACCOUNT][URL] == ["games.example", "videos.example"]

    # The next day the list dropped videos.example and parent.example was never Hearth's
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL, text="games.example\n")
    await _tick(hass, household, freezer, _at(date(2026, 11, 10), 7, 30))
    assert fs.writes("remove_website") == [["videos.example"]]
    assert fs.hosts() == ["games.example", "parent.example"]
    assert household.scheduler.fs_sites.owned[ACCOUNT][URL] == ["games.example"]
    # Never through allow_website (that would put it on the allowed list)
    assert fs.writes("allow_website") == []


async def test_a_site_removed_by_hand_isn_t_hearth_s_any_more(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\nvideos.example\n")
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    fs.blocked.remove("https://videos.example/")  # a parent unblocked it in the Family Safety app
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL, text="games.example\nvideos.example\n")
    await _tick(hass, household, freezer, _at(date(2026, 11, 10), 7, 30))
    # Still listed, so blocked again, and Hearth's again
    assert fs.writes("block_website")[-1] == ["videos.example"]


async def test_failures_are_told_per_site_as_family_safety_names_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    events = async_capture_events(hass, "hearth_schedule")
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\nvideos.example\n")
    fs.failing = {"videos.example"}
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    [event] = [e.data for e in events if e.data["action"] == "site_list"]
    assert event["added"] == 1 and event["failed"] == [{"site": "videos.example", "error": "HTTP 500"}]
    # Only what was done is Hearth's (the failed one is tried again the next day)
    assert household.scheduler.fs_sites.owned[ACCOUNT][URL] == ["games.example"]


async def test_every_site_failing_is_tried_again_later(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    events = async_capture_events(hass, "hearth_schedule")
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\n")
    fs.failing = {"games.example"}
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    [failed] = [e.data for e in events if e.data["action"] == "site_list_failed"]
    assert failed["via"] == "family_safety" and failed["failed"] == [{"site": "games.example", "error": "HTTP 500"}]
    fs.failing = set()
    await _tick(hass, household, freezer, _at(MONDAY, 7, 40))
    assert fs.hosts() == ["games.example"]
    assert [e.data["action"] for e in events].count("site_list") == 1


async def test_a_list_that_can_t_be_used_changes_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    events = async_capture_events(hass, "hearth_schedule")
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "<html>Not found</html>\n")
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    assert fs.writes("block_website") == [] and fs.writes("remove_website") == []
    [failed] = [e.data for e in events if e.data["action"] == "site_list_failed"]
    assert "no usable domains" in failed["error"]


async def test_a_list_cut_short_or_an_empty_answer_takes_nothing_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    sites = [f"site{i}.example" for i in range(50)]
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "\n".join(sites))
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    assert len(fs.hosts()) == 50
    # The next day the list has only 10 of them: 40 to take back is more than half
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL, text="\n".join(sites[:10]))
    await _tick(hass, household, freezer, _at(date(2026, 11, 10), 7, 30))
    assert fs.writes("remove_website") == [] and len(fs.hosts()) == 50
    # And Microsoft answering no blocked sites at all isn't trusted either
    fs.blocked = []
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL, text="other.example\n")
    await _tick(hass, household, freezer, _at(date(2026, 11, 11), 7, 30))
    assert fs.writes("block_website") == [sites]


async def test_the_list_is_downloaded_once_for_everyone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\n")
    await _add_enforcer(hass, {"kind": "family_safety", "person": "person.alex", "entity_id": "654321"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    assert aioclient_mock.call_count == 1
    assert [c.data.get("account_id") or c.data.get("entity_id") for c in fs.calls if c.service == "get_sites"] == [
        "654321", [SAM_FS]
    ]


async def test_a_fork_s_record_is_taken_over(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    fs_entry = MockConfigEntry(domain=FS, entry_id="fsentry")
    fs_entry.add_to_hass(hass)
    await Store(hass, 1, f"{FS}.site_sync.fsentry").async_save({ACCOUNT: {URL: ["old.example", "games.example"]}})
    fs, household = await _sam(
        hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\n", blocked=["old.example", "games.example"]
    )
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    # old.example was the fork's (on Hearth's list), dropped since: unblocked
    assert fs.writes("remove_website") == [["old.example"]]
    assert household.scheduler.fs_sites.owned[ACCOUNT][URL] == ["games.example"]


async def test_a_fork_with_sync_site_list_still_does_it_itself(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, aioclient_mock: AiohttpClientMocker
) -> None:
    calls: list[ServiceCall] = []

    async def sync(call: ServiceCall) -> None:
        calls.append(call)

    fs, household = await _sam(hass, hass_client_no_auth, freezer, aioclient_mock, "games.example\n")
    hass.services.async_register(FS, "sync_site_list", sync)
    await _tick(hass, household, freezer, _at(MONDAY, 7, 30))
    assert [c.data for c in calls] == [{"entity_id": SAM_FS, "url": URL}]
    assert fs.calls == [] and aioclient_mock.call_count == 0


def test_the_list_s_text_and_upstream_s_failure_are_read() -> None:
    ignored: list[str] = []
    assert fs_site_list.parse("A.example.\n127.0.0.1\n1.2.3.4\n# x\nb.example # y\na.example\n", ignored) == [
        "a.example", "b.example"
    ]
    assert ignored == ["127.0.0.1", "1.2.3.4"]
    err = HomeAssistantError("block_website: 2 of 3 site(s) failed. Done: a.example. Failed: b.example (HTTP 500 (x)); c.example (nope)")
    done, failed = fs_site_list.split_failure(err, ["a.example", "b.example", "c.example"])
    assert done == ["a.example"] and set(failed) == {"b.example", "c.example"}
    done, failed = fs_site_list.split_failure(HomeAssistantError("Web API not initialized"), ["a.example"])
    assert done == [] and failed == {"a.example": "Web API not initialized"}
