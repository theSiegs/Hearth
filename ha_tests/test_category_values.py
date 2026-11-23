"""Hearth's app-category values in a phone's state document (category_values, docs/contracts/device-api.md): the
same table Hearth decides by, versioned, additive, and never in the TV's part."""

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.categories import BUILTIN_VALUES, VALUES_FORMAT, values_document
from test_init import PHONE_ID, TV_ID
from test_people import _household_with_sam


def test_the_document_is_the_builtin_table() -> None:
    sent = values_document()
    assert set(sent) == {"format", "version", "categories"}
    assert sent["format"] == VALUES_FORMAT == "hearth.values/1"
    assert sent["categories"] == BUILTIN_VALUES
    assert len(sent["version"]) == 16 and values_document()["version"] == sent["version"]
    # A copy: a change to what was sent never reaches the table Hearth decides by
    sent["categories"]["game"]["pool"] = "other"
    sent["categories"]["audio"]["pool_names"].append("radio")
    assert BUILTIN_VALUES["game"]["pool"] == "games" and BUILTIN_VALUES["audio"]["pool_names"] == ["music", "audio"]
    assert values_document()["categories"] == BUILTIN_VALUES


async def test_a_phone_gets_the_values_and_a_tv_does_not(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hub = hass.config_entries.async_loaded_entries("hearth")[0].runtime_data
    hub.devices[PHONE_ID] = {"kind": "mobile", "person": "person.sam", "name": "Sam's phone"}

    document = hub.household.document_for(PHONE_ID)
    assert document["category_values"] == values_document()
    assert document["category_values"]["categories"] == BUILTIN_VALUES
    # hearth/me is the same phone body
    assert hub.household.own_document("person.sam")["category_values"] == values_document()

    # Additive: a client that doesn't know the key reads the rest as before
    known = {"person", "media_rooms", "client_settings", "version", "contract"}
    assert set(document) - {"category_values"} <= known
    assert document["person"]["person"] == "person.sam" and document["contract"] == 3
    # The version is stable from one read to the next
    assert hub.household.document_for(PHONE_ID)["version"] == document["version"]

    # The TV's part of the document is unchanged
    hub.devices[TV_ID] = {"kind": "tv", "name": "Kitchen"}
    assert "category_values" not in hub.household.document_for(TV_ID)
