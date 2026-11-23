"""The Hearth TV contract (docs/contracts/hearth-tv.md): the TV's state document's top-level keys and the contract
version, read out of the page's marked block, against what Home Assistant sends and against the shared fixture
(contract_fixtures/tv_state_document.json, "document"), which Hearth TV's own test reads too. A change to one needs the
page, this test and the TV's fixture test changed together."""

import json
from pathlib import Path
import re

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import CONTRACT, DOMAIN

from test_init import TV_ID, _post
from test_parent_pin import _adults
from test_people import _tv_status
from test_phones import _options, _two_adults
from test_sources import _option

PAGE = Path(__file__).parents[1] / "docs" / "contracts" / "hearth-tv.md"
FIXTURE = json.loads((Path(__file__).parent / "contract_fixtures" / "tv_state_document.json").read_text("utf-8"))
SECOND_TV = "tv-fedcba9876543210"
TV_CLIENT = {"id": "com.thesiegs.hearth", "version": "2026.11.53", "contract": 3}
PIN = "4826"


def _page_block() -> dict[str, list[str]]:
    """The page's block between the two `hearth-tv-contract:state-document` markers: `name: word word ...` lines."""
    text = PAGE.read_text("utf-8")
    found = re.search(
        r"<!-- hearth-tv-contract:state-document -->\s*```text\n(.*?)```\s*<!-- /hearth-tv-contract:state-document -->",
        text,
        re.S,
    )
    assert found, f"{PAGE.name} lost its marked state-document block"
    block: dict[str, list[str]] = {}
    for line in found.group(1).splitlines():
        if line.strip():
            name, _, words = line.partition(":")
            block[name.strip()] = words.split()
    return block


BLOCK = _page_block()
ALWAYS = set(BLOCK["always"])
OPTIONAL = set(BLOCK["optional"])


def test_the_page_s_contract_is_the_integration_s() -> None:
    assert BLOCK["contract"] == [str(CONTRACT)]
    assert ALWAYS and OPTIONAL and not ALWAYS & OPTIONAL


def test_the_shared_fixture_carries_every_key_the_page_lists() -> None:
    document = FIXTURE["document"]
    assert set(document) == ALWAYS | OPTIONAL
    assert document["contract"] == CONTRACT


async def test_a_tv_s_document_has_the_page_s_keys_and_no_others(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    # Sam a kid on the first TV; Alex an adult with a phone and a Parent PIN, on the owner profile
    client, secret, _alex, _jordan = await _two_adults(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await _options(hass, profiles={**entry.options.get("profiles", {}), "name:owner": "person.alex"})
    await _adults(hass, "person.alex")
    await _option(hass, "parent_pin", {"person": "person.alex", "pin": PIN, "pin_again": PIN})

    # A TV paired before contract 3 (no client) that never said its caps: the keys every TV gets, and only listed ones
    plain = (await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json())["state"]
    assert ALWAYS <= set(plain) <= ALWAYS | OPTIONAL, set(plain) ^ ALWAYS
    assert plain["contract"] == CONTRACT

    # Another TV of the household, vouched for by the first (a ticket), as Hearth TV pairs today: its client, and the
    # notices cap. Every key the page lists, and no other
    ticket = await client.post(
        f"/api/hearth/device/{TV_ID}/ticket", json={"kind": "tv"}, headers={"X-Hearth-Secret": secret}
    )
    assert ticket.status == 200
    redeemed = await client.post(
        "/api/hearth/pair/redeem",
        json={"ticket": (await ticket.json())["ticket"], "device_id": SECOND_TV, "kind": "tv", "name": "The TV",
              "client": TV_CLIENT},
    )
    assert redeemed.status == 200
    second = (await redeemed.json())["secret"]
    await hass.async_block_till_done()
    full = await _post(client, second, body={**_tv_status(hearthtube_s=60), "caps": ["events", "notices"],
                                             "client": TV_CLIENT}, device_id=SECOND_TV)
    assert full.status == 200
    answer = await full.json()
    assert answer["contract"] == CONTRACT
    document = answer["state"]
    assert set(document) == ALWAYS | OPTIONAL, set(document) ^ (ALWAYS | OPTIONAL)

    # The fixture's document is that shape: each key's value of the same JSON type as Home Assistant's
    for key, value in FIXTURE["document"].items():
        assert type(document[key]) is type(value), f"{key}: {type(document[key]).__name__}"


def test_the_block_check_catches_a_change() -> None:
    text = PAGE.read_text("utf-8")
    assert "<!-- hearth-tv-contract:state-document -->" in text and "<!-- /hearth-tv-contract:state-document -->" in text
    # A key the integration sends but the page doesn't list would fail the document test: the page must list them all
    assert "profiles" in ALWAYS and "version" in ALWAYS and "contract" in ALWAYS
