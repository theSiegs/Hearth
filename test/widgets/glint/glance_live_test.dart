import 'package:flauncher/gradients.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_page.dart';
import 'package:flauncher/widgets/glint/glance_rotation.dart';
import 'package:flauncher/widgets/glint/glance_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  group("GlanceRotation", () {
    late DateTime now;
    GlanceRotation rotation() => GlanceRotation(settle: Duration.zero, clock: () => now)..running = true;
    setUp(() => now = DateTime(2026, 11, 6, 18));

    test("one tile at a time, in turn; a tile with one face never turns", () {
      final r = rotation()
        ..setFaces("today", 3)
        ..setFaces("time", 1)
        ..setFaces("family", 4);
      expect(r.turning, ["today", "family"]);
      expect([r.tick(), r.tick(), r.tick()], ["today", "family", "today"]);
      expect(r.indexOf("today").value, 2);
      expect(r.indexOf("family").value, 1);
      expect(r.indexOf("time").value, 0);
      r.dispose();
    });

    test("the shared beat: about the period per tile, never closer than the gap", () {
      final r = rotation();
      for (final id in ["a", "b"]) {
        r.setFaces(id, 2);
      }
      expect(r.every, const Duration(seconds: 4));
      for (final id in ["c", "d", "e", "f", "g", "h"]) {
        r.setFaces(id, 2);
      }
      expect(r.every, r.minGap);
      r.dispose();
    });

    test("the selected tile holds still, and waits a little once the selection leaves", () {
      final r = rotation()
        ..setFaces("family", 3)
        ..setFaces("lists", 2);
      r.focus("family", true);
      for (var i = 0; i < 6; i++) {
        r.tick();
      }
      expect(r.indexOf("family").value, 0, reason: "frozen while selected");
      expect(r.indexOf("lists").value, 6, reason: "the others go on");
      r.focus("family", false);
      r.tick();
      r.tick();
      expect(r.indexOf("family").value, 0, reason: "not straight after the selection leaves");
      now = now.add(r.resumeAfter);
      r.tick();
      r.tick();
      expect(r.indexOf("family").value, 1, reason: "then it turns again");
      r.dispose();
    });

    test("nothing turns while it isn't running (Motion: Still, the page hidden) or before the page settles", () {
      final r = rotation()..setFaces("today", 3);
      r.running = false;
      expect(r.tick(), isNull);
      expect(r.indexOf("today").value, 0);
      r.dispose();

      final settling = GlanceRotation(clock: () => now)
        ..setFaces("today", 3)
        ..running = true;
      expect(settling.tick(), isNull);
      now = now.add(settling.settle);
      expect(settling.tick(), "today");
      settling.dispose();
    });
  });

  group("pressing never depends on the face", () {
    final inputs = GlanceInputs(
      lock: const HaLockState(
        paired: true,
        kids: true,
        groups: [
          HaGroupLeft("a", "Games", 10),
          HaGroupLeft("b", "Video", 20),
          HaGroupLeft("c", "Apps", 30),
          HaGroupLeft("d", "All", 40),
        ],
      ),
      people: const [GlancePerson("Alex", "home"), GlancePerson("Sam", "school"), GlancePerson("Robin", "")],
      lists: const [GlanceList("Chores", 3, entity: "todo.chores", next: ["Dishes", "Bins"])],
      weather: GlanceWeather(
        icon: Icons.wb_sunny_outlined,
        temp: 12,
        hours: [GlanceWeatherHour(DateTime(2026, 11, 6, 20), 10, Icons.cloud_outlined)],
      ),
      now: DateTime(2026, 11, 6, 18),
    );

    test("each tile has one view, whatever its face", () {
      final tiles = glanceTilesFor(inputs);
      final views = {for (final t in tiles) t.id: t.view};
      expect(views, {
        "screen-time": GlanceView.screenTime,
        "today": GlanceView.today,
        "weather": GlanceView.weather,
        "family": GlanceView.family,
        "lists": GlanceView.lists,
        "all-apps": null,
        "settings": null,
      });
      final faces = {for (final t in tiles) if (!t.action) t.id: t.faces};
      expect(faces["family"], 3, reason: "everyone, then Alex, then Sam (Robin has no place)");
      expect(faces["lists"], 2);
      expect(faces["weather"], 2);
      expect(faces["screen-time"], 2);
    });

    testWidgets("the family tile opens the family view on every face, and holds still while selected", (tester) async {
      final wallpaper = MockWallpaperService();
      when(wallpaper.gradient).thenReturn(FLauncherGradients.greatWhale);
      when(wallpaper.focusedAppColor).thenReturn(null);
      when(wallpaper.wallpaper).thenReturn(null);
      when(wallpaper.version).thenReturn(0);
      var now = DateTime(2026, 11, 6, 18);
      final rotation = GlanceRotation(settle: Duration.zero, clock: () => now)..running = true;
      final family = glanceTilesFor(inputs).firstWhere((t) => t.id == "family");
      rotation.setFaces(family.id, family.faces);
      final opened = <GlanceView>[];
      final focus = FocusNode();

      await tester.pumpWidget(ChangeNotifierProvider<WallpaperService>.value(
        value: wallpaper,
        child: MaterialApp(
          home: Material(
            child: Column(
              children: [
                Focus(focusNode: focus, child: const SizedBox(width: 10, height: 10)),
                SizedBox(
                  width: 420,
                  height: 112,
                  child: GlanceLiveTile(tile: family, rotation: rotation, onOpen: opened.add),
                ),
              ],
            ),
          ),
        ),
      ));
      Future<void> pressTile() async {
        await tester.tap(find.byKey(const Key("glance_family")));
        await tester.pumpAndSettle();
      }

      // Face 0: everyone
      expect(find.text("—"), findsOneWidget, reason: "Robin, with no tracker, is there with a quiet dash");
      await pressTile();
      expect(opened, [GlanceView.family]);

      // Turned to Alex alone: pressing still opens the family view, not Alex
      rotation.tick();
      await tester.pumpAndSettle();
      expect(rotation.indexOf("family").value, 1);
      expect(find.text("Home"), findsOneWidget);
      await pressTile();
      expect(opened, [GlanceView.family, GlanceView.family]);

      // Selected, it holds still
      Focus.of(tester.element(find.descendant(of: find.byKey(const Key("glance_family")), matching: find.byType(Row)).first))
          .requestFocus();
      await tester.pump();
      expect(rotation.focused, "family");
      for (var i = 0; i < 5; i++) {
        rotation.tick();
      }
      await tester.pumpAndSettle();
      expect(rotation.indexOf("family").value, 1);
      expect(find.text("Home"), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, [GlanceView.family, GlanceView.family, GlanceView.family]);

      focus.requestFocus();
      await tester.pump();
      expect(rotation.focused, isNull);
      now = now.add(rotation.resumeAfter);
      rotation.tick();
      await tester.pumpAndSettle();
      expect(rotation.indexOf("family").value, 2, reason: "turns again once the selection has gone");
      expect(find.text("School"), findsOneWidget);
      rotation.dispose();
    });
  });

  group("the weather tile", () {
    test("Home Assistant's weather: °F to °C, today's high and low, the next hours and days", () {
      final now = DateTime(2026, 11, 6, 18, 20);
      final w = GlanceWeather.fromHa(
        state: "partlycloudy",
        temperature: 50,
        unit: "°F",
        hourly: [
          for (var h = 18; h < 24; h++) {"datetime": DateTime(2026, 11, 6, h).toIso8601String(), "temperature": 48, "condition": "rainy"},
        ],
        daily: [
          {"datetime": DateTime(2026, 11, 6, 12).toIso8601String(), "temperature": 59, "templow": 41},
          {"datetime": DateTime(2026, 11, 7, 12).toIso8601String(), "temperature": 61, "templow": 43, "condition": "sunny"},
        ],
        now: now,
      )!;
      expect(w.condition, "Partly cloudy");
      expect(GlanceWeather.degrees(w.temp, fahrenheit: true), "50°");
      expect(GlanceWeather.degrees(w.temp, fahrenheit: false), "10°");
      expect(GlanceWeather.degrees(w.high, fahrenheit: true), "59°");
      expect(GlanceWeather.degrees(w.low, fahrenheit: true), "41°");
      expect([for (final h in w.hours) h.time.hour], [19, 21, 23], reason: "from the next hour, every two");
      expect(w.days.single.date, DateTime(2026, 11, 7));
      expect(w.days.single.icon, Icons.wb_sunny_outlined);
    });

    test("no temperature, no weather: the tile isn't there", () {
      expect(GlanceWeather.fromHa(state: "unavailable", temperature: null, now: DateTime(2026)), isNull);
      expect(GlanceWeather.fromHearth(null, DateTime(2026)), isNull);
      expect(GlanceWeather.fromHearth(WeatherData.fromJson(const {}), DateTime(2026)), isNull);
      expect([for (final t in glanceTiles(lock: HaLockState.none)) t.id], isNot(contains("weather")));
    });

    test("the house's weather entity: weather.home first, then one named for home, never one without a temperature", () {
      const a = GlanceHaWeatherEntity("weather.forecast_home", "sunny", 60, "°F", 3);
      const b = GlanceHaWeatherEntity("weather.home", "sunny", 61, "°F", 7);
      const c = GlanceHaWeatherEntity("weather.cabin", "sunny", 50, "°F", 3);
      const d = GlanceHaWeatherEntity("weather.home", "unavailable", null, "°F", 7);
      expect(GlanceHaWeatherEntity.pick([a, b, c])!.entity, "weather.home");
      expect(GlanceHaWeatherEntity.pick([c, a, d])!.entity, "weather.forecast_home");
      expect(GlanceHaWeatherEntity.pick([c])!.entity, "weather.cabin");
      expect(GlanceHaWeatherEntity.pick([d]), isNull);
    });

    test("the feed reads weather entities and to-do entities from its template", () {
      final parsed = GlanceHaFeed.parse('{"people": [], "lists": [["Chores", "2", "todo.chores"]],'
          ' "weather": [["weather.home", "rainy", 55.4, "°F", 7]]}');
      expect(parsed.lists.single.entity, "todo.chores");
      expect(parsed.weather.single.hourly, isTrue);
      expect(parsed.weather.single.daily, isTrue);
      expect(GlanceHaFeed.nextOf({
        "items": [
          {"summary": "Dishes", "status": "needs_action"},
          {"summary": "Laundry", "status": "completed"},
          {"summary": "Bins", "status": "needs_action"},
        ],
      }), ["Dishes", "Bins"]);
    });
  });
}
