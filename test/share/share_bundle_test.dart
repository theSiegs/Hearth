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

  ShareBundle bundle({Map<String, dynamic>? layout}) => ShareBundle.build(
        hearth: "2026.10.62",
        tv: "Den",
        profiles: const [ShareProfile(id: "p1", name: "Alex", kids: false), ShareProfile(id: "p2", name: "Sam", kids: true)],
        layouts: {"p1": layout ?? backup()},
        pairings: {
          "p1": const [
            SharedPairing(packageName: "com.example.video", picker: false, appProfile: "Alex"),
            SharedPairing(packageName: "com.example.music", picker: true),
          ],
        },
        settingKeys: keys,
      );

  group("a bundle", () {
    test("goes out and comes back the same", () {
      final sent = bundle();
      final got = ShareBundle.parse(sent.encode(), settingKeys: keys);
      expect(got.hearth, "2026.10.62");
      expect(got.tv, "Den");
      expect(got.profiles.map((p) => p.name), ["Alex", "Sam"]);
      expect(got.profiles.map((p) => p.kids), [false, true]);
      final layout = got.layouts["p1"]!;
      expect(layout.settings["accent_color"], "#ff7a1a");
      expect(layout.settings["show_continue_watching"], false);
      expect(layout.settings["continue_watching_max_items"], 8);
      expect(layout.settings["hidden_watch_next_packages"], ["com.example.video"]);
      expect(layout.apps.map((a) => a.packageName), ["com.example.video", "com.example.music", "com.example.game"]);
      expect(layout.apps[1].hidden, isTrue);
      expect(layout.categories.map((c) => c["name"]), ["Favorites", "Kids"]);
      expect(layout.appsCategories, hasLength(3));
      expect(layout.spacers, hasLength(1));
      expect(got.layouts.containsKey("p2"), isFalse);
      expect(got.pairings["p1"]!.map((p) => p.picker), [false, true]);
      expect(got.pairings["p1"]![0].appProfile, "Alex");
    });

    test("never carries what belongs to a TV or is a secret, however the settings are named", () {
      final sent = bundle(layout: backup(settings: {
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
      for (final text in [sent.encode(), jsonEncode(ShareBundle.parse(sent.encode(), settingKeys: keys).layouts["p1"]!.toJson())]) {
        final settings = (jsonDecode(text) is Map && (jsonDecode(text) as Map).containsKey("sections"))
            ? (((jsonDecode(text) as Map)["sections"] as List).first as Map)["data"]["settings"] as Map
            : (jsonDecode(text) as Map)["settings"] as Map;
        expect(settings.keys.toSet(), {"accent_color"});
      }
      expect(sent.encode(), isNot(contains("c0ffee")));
      expect(sent.encode(), isNot(contains("secret")));
    });

    test("is checked again on the receiving end, whatever the sender did", () {
      final hand = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      final data = ((hand["sections"] as List).first as Map)["data"] as Map;
      (data["settings"] as Map<String, dynamic>).addAll({
        "device_parent_pin_hash": "c0ffee",
        "start_on_boot": true,
        "custom_banner_x": "/etc/passwd",
        "accent_color": "#abcdef",
        "continue_watching_max_items": {"nested": 1},
        "app_language": "x" * 5000,
      });
      final got = ShareBundle.parse(jsonEncode(hand), settingKeys: keys).layouts["p1"]!;
      expect(got.settings["accent_color"], "#abcdef");
      expect(got.settings.keys, isNot(contains("device_parent_pin_hash")));
      expect(got.settings.keys, isNot(contains("start_on_boot")));
      expect(got.settings.keys, isNot(contains("custom_banner_x")));
      expect(got.settings.keys, isNot(contains("continue_watching_max_items")));
      expect(got.settings.keys, isNot(contains("app_language")));
    });

    test("drops what doesn't fit a layout instead of trusting it", () {
      final hand = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      final data = ((hand["sections"] as List).first as Map)["data"] as Map;
      (data["apps"] as List).addAll([
        {"packageName": "../../etc/passwd", "name": "x"},
        {"packageName": "com.example.video", "name": "again"},
        {"packageName": "nodots", "name": "y"},
        "not a map",
      ]);
      (data["categories"] as List).addAll([
        {"id": 4, "name": "Duplicate id"},
        {"id": -1, "name": "Negative"},
        {"id": 12, "name": "Wild", "sort": 99, "type": -3, "rowHeight": 99999, "columnsCount": 0, "order": "x"},
      ]);
      (data["appsCategories"] as List).addAll([
        {"categoryId": 77, "appPackageName": "com.example.video", "order": 0},
        {"categoryId": 4, "appPackageName": "com.example.unknown", "order": 0},
        {"categoryId": 4, "appPackageName": "com.example.video", "order": 3},
      ]);
      final got = ShareBundle.parse(jsonEncode(hand), settingKeys: keys).layouts["p1"]!;
      expect(got.apps.map((a) => a.packageName), ["com.example.video", "com.example.music", "com.example.game"]);
      expect(got.categories.map((c) => c["id"]), [4, 9, 12]);
      final wild = got.categories.last;
      expect([wild["sort"], wild["type"], wild["rowHeight"], wild["columnsCount"], wild["order"]], [0, 0, 110, 6, 0]);
      expect(got.appsCategories, hasLength(3));
    });
  });

  group("the layout on a TV with other apps", () {
    final here = [
      const InstalledApp(packageName: "com.example.video", name: "Video HD", version: "9", lastLaunchedAt: 77),
      const InstalledApp(packageName: "com.example.news", name: "News", version: "1"),
    ];

    test("keeps this TV's own name and version, leaves out the apps it doesn't have, and says which", () {
      final layout = ShareBundle.parse(bundle().encode(), settingKeys: keys).layouts["p1"]!;
      final result = layout.forInstalled(here);
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
      final layout = ShareBundle.parse(bundle().encode(), settingKeys: keys).layouts["p1"]!;
      final result = layout.forInstalled([
        const InstalledApp(packageName: "com.example.music", name: "Music", version: "2"),
      ]);
      expect(((result.backup["apps"] as List).single as Map)["hidden"], true);
      expect(result.missing, ["Video", "Game"]);
    });
  });

  group("a bundle that isn't ours to take", () {
    String of(Map<String, dynamic> change) {
      final hand = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      hand.addAll(change);
      return jsonEncode(hand);
    }

    void refused(String text, [String? part]) {
      expect(
        () => ShareBundle.parse(text, settingKeys: keys),
        throwsA(isA<ShareFormatException>().having((e) => e.message, "message", part == null ? anything : contains(part))),
      );
    }

    test("refuses what isn't one", () {
      refused("not json at all");
      refused("[]", "bundle");
      refused(jsonEncode({"format": "something-else", "v": 1}), "not a Hearth");
      refused(of({"v": "1"}), "version");
      refused(of({"profiles": "none"}), "profiles");
      refused("x" * (ShareBundle.maxJsonBytes + 1), "too big");
    });

    test("says when it is from a newer Hearth", () {
      expect(
        () => ShareBundle.parse(of({"v": 2}), settingKeys: keys),
        throwsA(isA<ShareFormatException>().having((e) => e.newer, "newer", isTrue)),
      );
    });

    test("refuses profiles it can't tell apart or name", () {
      final profile = {"id": "p1", "name": "Alex", "kind": "adult"};
      refused(of({"profiles": [profile, profile]}), "duplicate");
      refused(of({"profiles": [{"id": "../x", "name": "Alex"}]}), "id");
      refused(of({"profiles": [{"id": "p1", "name": "  "}]}), "name");
      refused(of({"profiles": List.generate(ShareBundle.maxProfiles + 1, (i) => {"id": "p$i", "name": "N$i"})}), "too many");
    });

    test("refuses two layouts for one profile and layouts with too many apps", () {
      final hand = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      final sections = hand["sections"] as List;
      sections.add(sections.first);
      refused(jsonEncode(hand), "duplicate");

      final big = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      final data = ((big["sections"] as List).first as Map)["data"] as Map;
      data["apps"] = List.generate(ShareBundle.maxApps + 1, (i) => {"packageName": "com.example.a$i", "name": "A"});
      refused(jsonEncode(big), "too many");
    });

    test("ignores sections it doesn't know and sections for profiles that aren't in it", () {
      final hand = jsonDecode(bundle().encode()) as Map<String, dynamic>;
      (hand["sections"] as List).addAll([
        {"type": "wallpaper-from-the-future", "profile": "p1", "data": {}},
        {"type": "layout", "profile": "nobody", "data": backup()},
        {"type": "secrets", "profile": "p1", "data": [{"pin": "1234"}]},
      ]);
      final got = ShareBundle.parse(jsonEncode(hand), settingKeys: keys);
      expect(got.layouts.keys, ["p1"]);
      expect(got.pairings.keys, ["p1"]);
    });

    test("tidies text that will be shown or logged", () {
      final text = of({
        "profiles": [
          {"id": "p1", "name": "Alex\n\u0000\u001b[31mRed", "kind": "adult"},
        ],
        "from": {"hearth": "2026.10.62\r\n", "tv": "T" * 500},
      });
      final got = ShareBundle.parse(text, settingKeys: keys);
      expect(got.profiles.single.name, isNot(contains("\n")));
      expect(got.profiles.single.name, isNot(contains("\u0000")));
      expect(got.hearth, "2026.10.62");
      expect(got.tv.length, ShareBundle.maxText);
    });
  });

  group("pairings", () {
    Map<String, dynamic> pairing(Map<String, dynamic> change) {
      return {"pkg": "com.example.video", "mode": "profile", "appProfile": "Alex", ...change};
    }

    test("are an app profile's name or always ask, for a streaming app", () {
      expect(SharedPairing.parse(pairing({})).appProfile, "Alex");
      expect(SharedPairing.parse(pairing({"mode": "picker"})).picker, isTrue);
    });

    test("refuse what isn't one", () {
      for (final bad in [
        pairing({"pkg": "../x"}),
        pairing({"pkg": 5}),
        pairing({"mode": "auto"}),
        pairing({"appProfile": ""}),
        pairing({"appProfile": 7}),
      ]) {
        expect(() => SharedPairing.parse(bad), throwsA(isA<ShareFormatException>()), reason: "$bad");
      }
    });

    test("with a name sent for a picker aren't carried", () {
      final got = SharedPairing.parse(pairing({"mode": "picker", "appProfile": "Alex"}));
      expect(got.appProfile, "");
    });
  });
}
