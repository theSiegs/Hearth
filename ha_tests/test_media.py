"""The house's media players by room: twins put together, one entity to control each."""

from homeassistant.core import HomeAssistant
from homeassistant.helpers import area_registry as ar, device_registry as dr, entity_registry as er
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.media import media_rooms
from test_people import _household_with_sam


def _player(hass: HomeAssistant, platform: str, object_id: str, name: str, area: str | None = None, model: str | None = None,
            device_class: str | None = None, hidden: bool = False, state: str = "idle") -> str:
    entry = MockConfigEntry(domain=platform)
    entry.add_to_hass(hass)
    device_id = None
    if model:
        device = dr.async_get(hass).async_get_or_create(
            config_entry_id=entry.entry_id, identifiers={(platform, object_id)}, name=name, model=model
        )
        device_id = device.id
    registered = er.async_get(hass).async_get_or_create(
        "media_player", platform, object_id, suggested_object_id=object_id, config_entry=entry, device_id=device_id,
        hidden_by=er.RegistryEntryHider.USER if hidden else None,
    )
    if area:
        # On the device, as Home Assistant has it for an entity without a name of its own
        area_id = ar.async_get(hass).async_get_or_create(area).id
        if device_id:
            dr.async_get(hass).async_update_device(device_id, area_id=area_id)
        else:
            er.async_get(hass).async_update_entity(registered.entity_id, area_id=area_id)
    attributes = {"friendly_name": name, **({"device_class": device_class} if device_class else {})}
    hass.states.async_set(registered.entity_id, state, attributes)
    return registered.entity_id


async def test_a_room_s_players_and_their_twins(hass: HomeAssistant) -> None:
    tv = _player(hass, "androidtv_remote", "lounge_tv", "Lounge TV", "Lounge", "Streaming stick", "tv")
    cast = _player(hass, "music_assistant", "stick1234", "Lounge TV (Music Assistant)", model="Streaming stick")
    shown = _player(hass, "music_assistant", "lounge_tv_2", "Lounge TV", model="Dashboard display", device_class="tv")
    echo = _player(hass, "alexa_media", "lounge_echo", "Lounge Echo", "Lounge", "Echo Dot")
    _player(hass, "alexa_now_playing", "lounge_echo_now_playing", "Lounge Echo Now Playing")
    console = _player(hass, "xbox", "study_xbox", "Study Xbox", "Study", "Xbox Series X", state="off")
    _player(hass, "music_assistant", "study_xbox_music_assistant", "Study Xbox (Music Assistant)", model="Xbox One")
    _player(hass, "alexa_media", "everywhere", "Everywhere", model="Speaker Group")
    _player(hass, "alexa_media", "car_echo", "Car Echo", model="Echo Auto")
    _player(hass, "music_assistant", "old_tv", "Old TV", "Study", "Emulator", hidden=True)

    rooms = {r["room"]: r for r in media_rooms(hass)}
    assert list(rooms) == ["Lounge", "Study", "Everywhere"]
    lounge = rooms["Lounge"]
    assert lounge["entity_id"] == tv and lounge["kind"] == "tv"
    assert sorted(lounge["also"]) == sorted([cast, shown])
    assert [p["entity_id"] for p in lounge["players"]] == [tv, echo]
    assert lounge["players"][1]["also"] == ["media_player.lounge_echo_now_playing"]
    # The console is a TV's; its Music Assistant player is its twin
    assert rooms["Study"]["entity_id"] == console and rooms["Study"]["kind"] == "tv"
    assert rooms["Study"]["also"] == ["media_player.study_xbox_music_assistant"]
    assert rooms["Everywhere"]["kind"] == "group" and rooms["Everywhere"]["area_id"] is None


async def test_a_music_assistant_display_player_is_the_tv_s_twin(hass: HomeAssistant) -> None:
    tv = _player(hass, "androidtv_remote", "lounge_tv", "Lounge TV", "Lounge", "Streaming stick", "tv")
    shown = _player(
        hass, "music_assistant", "lounge_tv_music_assistant_display", "Lounge TV (Music Assistant Display)",
        model="Dashboard display", device_class="tv",
    )
    cast = _player(hass, "music_assistant", "lounge_tv_music_assistant", "Lounge TV (Music Assistant)")

    [lounge] = media_rooms(hass)
    assert lounge["entity_id"] == tv
    assert sorted(lounge["also"]) == sorted([shown, cast])
    assert [p["entity_id"] for p in lounge["players"]] == [tv]


async def test_a_phone_and_the_summary_have_the_rooms(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    _player(hass, "alexa_media", "lounge_echo", "Lounge Echo", "Lounge", "Echo Dot")
    hub = hass.config_entries.async_loaded_entries("hearth")[0].runtime_data
    from test_init import PHONE_ID

    hub.devices[PHONE_ID] = {"kind": "mobile", "person": "person.sam", "name": "Sam's phone"}
    [room] = hub.household.document_for(PHONE_ID)["media_rooms"]
    assert room["room"] == "Lounge" and room["entity_id"] == "media_player.lounge_echo"

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    assert (await ws.receive_json())["result"]["media_rooms"][0]["room"] == "Lounge"
