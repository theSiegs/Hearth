import 'dart:convert';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Set<String> keys;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keys = SettingsService(await SharedPreferences.getInstance()).settingKeys;
  });

  Map<String, dynamic> backup({Map<String, dynamic>? settings}) => {
        "version": 1,
        "settings": settings ??
            {
              "accent_color": "#ff7a1a",
              "show_continue_watching": false,
              "continue_watching_max_items": 8,
              "hidden_watch_next_packages": ["com.example.video"],
            },
        "apps": [
          {"packageName": "com.example.video", "name": "Video", "version": "1", "hidden": false, "lastLaunchedAt": 5},
          {"packageName": "com.example.music", "name": "Music", "version": "2", "hidden": true, "lastLaunchedAt": null},
          {"packageName": "com.example.game", "name": "Game", "version": "3", "hidden": false},
        ],
        "categories": [
          {"id": 4, "name": "Favorites", "sort": 0, "type": 0, "rowHeight": 110, "columnsCount": 6, "order": 0},
          {"id": 9, "name": "Kids", "sort": 1, "type": 1, "rowHeight": 90, "columnsCount": 5, "order": 1},
        ],
        "appsCategories": [
          {"categoryId": 4, "appPackageName": "com.example.video", "order": 0},
          {"categoryId": 9, "appPackageName": "com.example.music", "order": 0},
          {"categoryId": 9, "appPackageName": "com.example.game", "order": 1},
        ],
        "spacers": [
          {"id": 1, "height": 40, "order": 2},
        ],
      };

  SharedLayout layoutOf(Map<String, dynamic> backup) => SharedLayout.fromBackup(backup, settingKeys: keys);

  group("a layout from another TV", () {
    test("keeps the look's settings, the apps, rows, places and spacers", () {
      final layout = layoutOf(backup());
      expect(layout.settings["accent_color"], "#ff7a1a");
      expect(layout.settings["show_continue_watching"], false);
      expect(layout.settings["continue_watching_max_items"], 8);
      expect(layout.settings["hidden_watch_next_packages"], ["com.example.video"]);
      expect(layout.apps.map((a) => a.packageName), ["com.example.video", "com.example.music", "com.example.game"]);
      expect(layout.apps[1].hidden, isTrue);
      expect(layout.categories.map((c) => c["name"]), ["Favorites", "Kids"]);
      expect(layout.appsCategories, hasLength(3));
      expect(layout.spacers, hasLength(1));
    });

    test("never takes what belongs to a TV or is a secret, however the settings are named", () {
      final layout = layoutOf(backup(settings: {
        "accent_color": "#00ff00",
        "device_parent_pin_hash": "c0ffee",
        "device_weather_location": "Somewhere",
        "device_layout_owner": "user:11",
        "start_on_boot": true,
        "hidden_calendars": ["a"],
        "hidden_watch_next_program_ids": ["1"],
        "setup_flow_step": 3,
        "custom_banner_com.example.video": "/data/user/0/x/banner.png",
        "ha_panel_token": "secret",
        "something_new_and_unknown": "x",
      }));
      expect(layout.settings.keys.toSet(), {"accent_color"});
    });

    test("takes only settings of a kind the settings use", () {
      final layout = layoutOf(backup(settings: {
        "accent_color": "#abcdef",
        "continue_watching_max_items": {"nested": 1},
        "date_format": "x" * 5000,
      }));
      expect(layout.settings, {"accent_color": "#abcdef"});
    });

    test("drops what doesn't fit a layout instead of trusting it", () {
      // As it comes from another TV: JSON, so anything can be in its lists
      final hand = jsonDecode(jsonEncode(backup())) as Map<String, dynamic>;
      (hand["apps"] as List).addAll([
        {"packageName": "../../etc/passwd", "name": "x"},
        {"packageName": "com.example.video", "name": "again"},
        {"packageName": "nodots", "name": "y"},
        "not a map",
      ]);
      (hand["categories"] as List).addAll([
        {"id": 4, "name": "Duplicate id"},
        {"id": -1, "name": "Negative"},
        {"id": 12, "name": "Wild", "sort": 99, "type": -3, "rowHeight": 99999, "columnsCount": 0, "order": "x"},
      ]);
      (hand["appsCategories"] as List).addAll([
        {"categoryId": 77, "appPackageName": "com.example.video", "order": 0},
        {"categoryId": 4, "appPackageName": "com.example.unknown", "order": 0},
        {"categoryId": 4, "appPackageName": "com.example.video", "order": 3},
      ]);
      final got = layoutOf(hand);
      expect(got.apps.map((a) => a.packageName), ["com.example.video", "com.example.music", "com.example.game"]);
      expect(got.categories.map((c) => c["id"]), [4, 9, 12]);
      final wild = got.categories.last;
      expect([wild["sort"], wild["type"], wild["rowHeight"], wild["columnsCount"], wild["order"]], [0, 0, 110, 6, 0]);
      expect(got.appsCategories, hasLength(3));
    });

    test("tidies a row's name, which will be shown", () {
      final hand = backup();
      (hand["categories"] as List).add({"id": 20, "name": "Alex\n\u0000\u001b[31mRed${"x" * 500}"});
      final row = layoutOf(hand).categories.last;
      expect(row["name"], isNot(contains("\n")));
      expect(row["name"], isNot(contains("\u0000")));
      expect((row["name"] as String).length, ShareBundle.maxText);
    });

    test("with too many apps, or a list that isn't one, is refused; this TV's own is cut to fit instead", () {
      final big = backup();
      big["apps"] = List.generate(ShareBundle.maxApps + 1, (i) => {"packageName": "com.example.a$i", "name": "A"});
      expect(() => layoutOf(big), throwsA(isA<ShareFormatException>()));
      expect(SharedLayout.fromBackup(big, settingKeys: keys, lenient: true).apps, hasLength(ShareBundle.maxApps));
      expect(() => layoutOf({...backup(), "spacers": "none"}), throwsA(isA<ShareFormatException>()));
    });
  });

  group("the layout on a TV with other apps", () {
    final here = [
      const InstalledApp(packageName: "com.example.video", name: "Video HD", version: "9", lastLaunchedAt: 77),
      const InstalledApp(packageName: "com.example.news", name: "News", version: "1"),
    ];

    test("keeps this TV's own name and version, leaves out the apps it doesn't have, and says which", () {
      final result = layoutOf(backup()).forInstalled(here);
      expect(result.missing, ["Music", "Game"]);
      final apps = result.backup["apps"] as List;
      expect(apps.map((a) => (a as Map)["packageName"]), ["com.example.video", "com.example.news"]);
      final video = apps.first as Map;
      expect(video["name"], "Video HD");
      expect(video["version"], "9");
      expect(video["lastLaunchedAt"], 77);
      expect(video["hidden"], false);
      // An app the layout doesn't know isn't hidden
      expect((apps.last as Map)["hidden"], false);
      // Placements for apps this TV doesn't have are gone, so nothing dangles
      expect(result.backup["appsCategories"], [
        {"categoryId": 4, "appPackageName": "com.example.video", "order": 0},
      ]);
      expect((result.backup["categories"] as List).map((c) => (c as Map)["name"]), ["Favorites", "Kids"]);
      expect(result.backup["version"], 1);
      expect(result.backup["onlyChosenSettings"], true);
    });

    test("keeps a hidden app hidden", () {
      final result = layoutOf(backup()).forInstalled([
        const InstalledApp(packageName: "com.example.music", name: "Music", version: "2"),
      ]);
      expect(((result.backup["apps"] as List).single as Map)["hidden"], true);
      expect(result.missing, ["Video", "Game"]);
    });
  });
}
