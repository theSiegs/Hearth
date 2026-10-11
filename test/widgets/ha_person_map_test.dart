/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';

import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/widgets/ha_panel/ha_image_cache.dart';
import 'package:flauncher/widgets/ha_panel/ha_person_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ha_panel_helpers.dart';

/// A 1 x 1 PNG, standing in for every map tile.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

// A made-up home and places around it (not anyone's real address)
const _home = (lat: 40.0, lon: -75.0);
const _nearby = (lat: 40.02, lon: -74.98);
const _faraway = (lat: 40.5, lon: -74.0);

void main() {
  late Directory dir;
  late List<Uri> fetched;

  setUp(() {
    dir = Directory.systemTemp.createTempSync("ha_person_map");
    fetched = [];
    HaMapTiles.reset();
    HaImageCache.directory = () async => dir;
    HaImageCache.fetch = (uri, headers) async {
      fetched.add(uri);
      expect(headers["User-Agent"], startsWith("Hearth/"));
      return _png;
    };
  });

  tearDown(() => dir.deleteSync(recursive: true));

  FakeHaPanelService people() {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {"type": "tile", "entity": "person.alex", "name": "Alex"},
      {"type": "tile", "entity": "person.sam", "name": "Sam"},
    ]));
    service.setState("zone.home", "0", {"latitude": _home.lat, "longitude": _home.lon});
    return service;
  }

  /// Fetches the tiles around home for real, before the panel opens; inside the panel's fake time it never would.
  Future<void> fetchTiles(WidgetTester tester) async {
    final ok = await tester.runAsync(() => HaMapTiles.ready(HaMapTiles.worldPixel(_home.lat, _home.lon)));
    expect(ok, isTrue);
  }

  /// Lets real file work (reading tiles) finish, and the panel draw it.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  test("Tile maths: positions, the area around home and its tiles", () {
    final home = HaMapTiles.worldPixel(_home.lat, _home.lon);
    final (x, y) = HaMapTiles.tileOf(home);
    expect(HaMapTiles.around(home), hasLength(81));
    expect(HaMapTiles.around(home), contains((x, y)));
    expect(HaMapTiles.area(home).contains(home), isTrue);
    expect(HaMapTiles.area(home).contains(HaMapTiles.worldPixel(_nearby.lat, _nearby.lon)), isTrue);
    expect(HaMapTiles.area(home).contains(HaMapTiles.worldPixel(_faraway.lat, _faraway.lon)), isFalse);
    // Null Island sits at the middle of the world map
    final middle = HaMapTiles.worldPixel(0, 0);
    expect(middle.dx, closeTo(HaMapTiles.tileSize * (1 << HaMapTiles.zoom) / 2, 0.001));
    expect(middle.dy, closeTo(HaMapTiles.tileSize * (1 << HaMapTiles.zoom) / 2, 0.001));
  });

  test("Home's zone is followed only when the dashboard has someone to locate", () {
    expect(HaPanelService.followed(layoutOf([{"type": "tile", "entity": "person.alex"}])),
        {"person.alex", "zone.home"});
    expect(HaPanelService.followed(layoutOf([{"type": "tile", "entity": "light.desk"}])), {"light.desk"});
  });

  testWidgets("The focused person's tile shows them on a map; the others don't", (tester) async {
    final service = people();
    service.setState("person.alex", "not_home", {"latitude": _nearby.lat, "longitude": _nearby.lon, "gps_accuracy": 100});
    service.setState("person.sam", "home", {"latitude": _home.lat, "longitude": _home.lon});
    await fetchTiles(tester);
    await openPanel(tester, service);
    await settle(tester);
    expect(focused(tester, "Alex"), isTrue);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsOneWidget);
    expect(find.byKey(const ValueKey("ha-person-map-accuracy")), findsOneWidget);
    expect(find.text("© OpenStreetMap"), findsOneWidget);

    // Moving on to Sam (beside Alex): Sam's map instead
    await press(tester, LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(focused(tester, "Sam"), isTrue);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsOneWidget);
  });

  testWidgets("Tiles asked for depend on home only, never on where the person is", (tester) async {
    final service = people();
    service.setState("person.alex", "not_home", {"latitude": _nearby.lat, "longitude": _nearby.lon});
    service.setState("person.sam", "home", {"latitude": _home.lat, "longitude": _home.lon});
    await fetchTiles(tester);
    final home = HaMapTiles.worldPixel(_home.lat, _home.lon);
    final expected = {for (final (x, y) in HaMapTiles.around(home)) Uri.parse(HaMapTiles.url(x, y))};
    expect(fetched.toSet(), expected);
    expect(fetched, hasLength(81));

    // Showing Alex, then Sam, at different places: nothing more is asked for
    await openPanel(tester, service);
    await settle(tester);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsOneWidget);
    expect(fetched, hasLength(81));
  });

  testWidgets("Outside the area around home, or without a position, there's no map and nothing is fetched",
      (tester) async {
    final service = people();
    service.setState("person.alex", "not_home", {"latitude": _faraway.lat, "longitude": _faraway.lon});
    service.setState("person.sam", "unknown");
    await openPanel(tester, service);
    await settle(tester);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsNothing);
    expect(fetched, isEmpty);
  });

  testWidgets("Without home's position there's no map", (tester) async {
    final service = FakeHaPanelService(
        fakeLayout: layoutOf([
      {"type": "tile", "entity": "person.alex", "name": "Alex"},
    ]));
    service.setState("person.alex", "not_home", {"latitude": _nearby.lat, "longitude": _nearby.lon});
    await openPanel(tester, service);
    await settle(tester);
    expect(find.byKey(const ValueKey("ha-person-map-marker")), findsNothing);
    expect(fetched, isEmpty);
  });
}
