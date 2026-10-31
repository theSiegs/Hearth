import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flutter_test/flutter_test.dart';

HaEntity _e(String id, String state, [String? name]) =>
    HaEntity(id, state, attributes: {if (name != null) "friendly_name": name});

Map<String, HaEntity> _all(List<HaEntity> entities) => {for (final e in entities) e.entityId: e};

void main() {
  test("follows each Hearth TV's sensors and the car occupant sensors, nothing else", () {
    final ids = GlintHouseFeed.followed([
      {"entity_id": "sensor.den_tv_media_title"},
      {"entity_id": "sensor.den_tv_profile"},
      {"entity_id": "sensor.den_tv_state"},
      {"entity_id": "binary_sensor.den_tv_connected"},
      // A media title without a profile beside it isn't a Hearth TV
      {"entity_id": "sensor.speaker_media_title"},
      {"entity_id": "sensor.wagon_occupants"},
      {"entity_id": "light.porch"},
      "not a state",
    ]);
    expect(ids, {
      "sensor.den_tv_media_title",
      "sensor.den_tv_profile",
      "sensor.den_tv_state",
      "binary_sensor.den_tv_connected",
      "sensor.wagon_occupants",
    });
  });

  test("a TV playing something: its name, who and what, and the app", () {
    final items = GlintHouseFeed.itemsFrom(_all([
      _e("sensor.den_tv_media_title", "Bluey", "Den TV Media title"),
      _e("sensor.den_tv_profile", "Sam"),
      _e("sensor.den_tv_state", "playing"),
      _e("sensor.den_tv_media_app", "HearthTube"),
      _e("binary_sensor.den_tv_connected", "on"),
    ]));
    expect(items, const [GlintHouseItem("Den TV", "Sam · Bluey", "HearthTube")]);
  });

  test("a TV that's off, asleep or showing nothing isn't listed", () {
    expect(
        GlintHouseFeed.itemsFrom(_all([
          _e("sensor.den_tv_media_title", "Bluey"),
          _e("binary_sensor.den_tv_connected", "off"),
        ])),
        isEmpty);
    expect(
        GlintHouseFeed.itemsFrom(_all([
          _e("sensor.den_tv_media_title", "Bluey"),
          _e("sensor.den_tv_state", "standby"),
        ])),
        isEmpty);
    expect(GlintHouseFeed.itemsFrom(_all([_e("sensor.den_tv_media_title", "unavailable")])), isEmpty);
  });

  test("without a friendly name, a TV is named from its id; without a profile, just the title", () {
    final items = GlintHouseFeed.itemsFrom(_all([_e("sensor.play_room_tv_media_title", "News")]));
    expect(items, const [GlintHouseItem("Play Room Tv", "News")]);
  });

  test("cars with someone in them, after the TVs; empty cars aren't listed", () {
    final items = GlintHouseFeed.itemsFrom(_all([
      _e("sensor.wagon_occupants", "Alex, Sam", "Wagon occupants"),
      _e("sensor.truck_occupants", "none", "Truck occupants"),
      _e("sensor.den_tv_media_title", "Bluey", "Den TV Media title"),
    ]));
    expect(items, const [
      GlintHouseItem("Den TV", "Bluey"),
      GlintHouseItem("In the Wagon", "Alex, Sam"),
    ]);
  });
}
