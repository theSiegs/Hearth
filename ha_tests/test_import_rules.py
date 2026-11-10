"""A TV's own screen-time rules, from before it was paired, become a kid's first budgets."""

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.status import local_rules
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status

RULES = {
    KID: {
        "all": {"weekday": 120, "weekend": 180},
        "groups": [
            {"id": "games", "name": "Games", "weekday": 30, "category": "game", "apps": []},
            {"id": "made_up", "name": "Made up", "weekday": 5},
        ],
        "bedtime": {"from": "20:30", "to": "07:00", "days": "all"},
    }
}


def _limits(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household.limits


async def test_the_tv_rules_are_a_kid_s_first_budgets(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert (await _post(client, secret, body={**_tv_status(), "local_rules": RULES})).status == 200
    await hass.async_block_till_done()

    limits = _limits(hass)
    assert limits.budget("person.sam", "all", "weekday") == 120
    assert limits.budget("person.sam", "all", "weekend") == 180
    assert limits.budget("person.sam", "games", "weekday") == 30
    # Only the groups Home Assistant has; nothing for a kind of day the TV left without a limit
    assert "made_up" not in limits.data.budgets["person.sam"]
    assert limits.budget("person.sam", "games", "weekend") is None


async def test_taken_once_and_never_over_home_assistant_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    limits = _limits(hass)
    hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household.set_budget("person.sam", "all", "weekday", 60)
    assert (await _post(client, secret, body={**_tv_status(), "local_rules": RULES})).status == 200
    assert limits.budget("person.sam", "all", "weekday") == 60
    assert limits.budget("person.sam", "games", "weekday") is None

    # Cleared later on Hearth's page: the TV's old rules don't come back
    limits.data.budgets.clear()
    assert (await _post(client, secret, body={**_tv_status(), "local_rules": RULES})).status == 200
    assert limits.budget("person.sam", "all", "weekday") is None


async def test_a_profile_mapped_to_no_one_waits(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    rules = {"user:11": RULES[KID]}
    assert (await _post(client, secret, body={**_tv_status(), "local_rules": rules})).status == 200
    assert _limits(hass).data.imported == []


def test_the_rules_are_cleaned() -> None:
    assert local_rules(None) is None
    # Out of range or not a number: no limit; a group id that isn't one is left out
    assert local_rules(
        {"user:10": {"all": {"weekday": 99999, "weekend": 90}, "groups": [{"id": "Bad Id", "weekday": 5}]}}
    ) == {"user:10": {"all": {"weekend": 90}}}
    assert local_rules({"not a key": {"all": {"weekday": 5}}}) == {}
