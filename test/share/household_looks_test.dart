import 'dart:convert';

import 'package:flauncher/share/household_looks.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

const settingKeys = {"accent_color", "dock_enabled", "date_format", "hidden_calendars", "device_parent_pin_hash"};

/// A profile-only backup as BackupService builds it, with the apps installed on that TV.
Map<String, dynamic> backup({
  required List<String> installed,
  Map<String, Object> settings = const {"accent_color": "00BFA5"},
  List<List<Object>> placements = const [],
  List<int> rows = const [1],
}) =>
    {
      "settings": settings,
      "apps": [for (final pkg in installed) {"packageName": pkg, "name": "Name of $pkg", "hidden": pkg.endsWith("x")}],
      "categories": [
        for (final id in rows) {"id": id, "name": "Row $id", "sort": 0, "type": 0, "rowHeight": 110, "columnsCount": 6, "order": id},
      ],
      "appsCategories": [
        for (final p in placements) {"categoryId": p[0], "appPackageName": p[1], "order": p[2]},
      ],
      "spacers": const [],
    };

SharedLayout layoutOf(Map<String, dynamic> b) => SharedLayout.fromBackup(b, settingKeys: settingKeys, lenient: true);

List<InstalledApp> installedApps(List<String> packages) =>
    [for (final pkg in packages) InstalledApp(packageName: pkg, name: "Here $pkg", version: "1")];

void main() {
  test("a look is written the same way whatever order its settings came in", () {
    final a = HouseholdLooks.lookJson({"dock_enabled": true, "accent_color": "00BFA5"});
    final b = HouseholdLooks.lookJson({"accent_color": "00BFA5", "dock_enabled": true});
    expect(a, b);
    expect(HouseholdLooks.fingerprint(a), HouseholdLooks.fingerprint(b));
  });

  test("a layout is written the same way whatever order, and without the apps' names, which are each TV's own", () {
    final one = layoutOf(backup(installed: ["com.b.app", "com.a.app"], placements: [
      [1, "com.b.app", 1],
      [1, "com.a.app", 0],
    ]));
    final two = layoutOf(backup(installed: ["com.a.app", "com.b.app"], placements: [
      [1, "com.a.app", 0],
      [1, "com.b.app", 1],
    ]));
    expect(HouseholdLooks.layoutJson(one), HouseholdLooks.layoutJson(two));
    expect(HouseholdLooks.layoutJson(one), isNot(contains("Name of")));
  });

  test("a TV without an app keeps the household's place for it", () {
    final household = layoutOf(backup(installed: ["com.a.app", "com.only.there"], placements: [
      [1, "com.a.app", 0],
      [1, "com.only.there", 1],
    ]));
    final here = layoutOf(backup(installed: ["com.a.app", "com.only.here"], placements: [
      [1, "com.a.app", 0],
      [1, "com.only.here", 2],
    ]));
    final merged = HouseholdLooks.withMissingApps(here, household, {"com.a.app", "com.only.here"});
    final json = jsonDecode(HouseholdLooks.layoutJson(merged)) as Map;
    expect([for (final a in json["apps"]) a["packageName"]], ["com.a.app", "com.only.here", "com.only.there"]);
    expect([for (final p in json["appsCategories"]) p["appPackageName"]], ["com.a.app", "com.only.there", "com.only.here"]);
  });

  test("a place in a row this TV took away goes with the row", () {
    final household = layoutOf(backup(installed: ["com.only.there"], rows: [1, 2], placements: [
      [2, "com.only.there", 0],
    ]));
    final here = layoutOf(backup(installed: ["com.a.app"], rows: [1]));
    final merged = HouseholdLooks.withMissingApps(here, household, {"com.a.app"});
    expect(merged.appsCategories, isEmpty);
  });

  test("taking the household's layout and giving it back gives the same entry, so two TVs don't trade it forever", () {
    final sent = layoutOf(backup(installed: ["com.a.app", "com.only.there", "com.hidden.x"], placements: [
      [1, "com.a.app", 0],
      [1, "com.only.there", 1],
    ]));
    final entry = HouseholdLooks.layoutJson(sent);
    final household = HouseholdLooks.parseLayout(entry, settingKeys)!;
    // put in place on a TV that has com.a.app and com.hidden.x but not com.only.there
    final composed = HouseholdLooks.compose({"accent_color": "00BFA5"}, household, null)!;
    final fitted = composed.forInstalled(installedApps(["com.a.app", "com.hidden.x"]));
    expect(fitted.missing, ["com.only.there"]);
    // what that TV then has, read back as it would give it
    final local = layoutOf(fitted.backup);
    final given = HouseholdLooks.layoutJson(
        HouseholdLooks.withMissingApps(local, household, {"com.a.app", "com.hidden.x"}));
    expect(given, entry);
  });

  test("a look from another TV keeps only what a profile may have", () {
    final look = HouseholdLooks.parseLook(
        jsonEncode({"accent_color": "FF6D00", "device_parent_pin_hash": "x", "hidden_calendars": ["a"], "nope": 1}),
        settingKeys)!;
    expect(look, {"accent_color": "FF6D00"});
    expect(HouseholdLooks.parseLook("not json", settingKeys), isNull);
    expect(HouseholdLooks.parseLook("[1]", settingKeys), isNull);
    expect(HouseholdLooks.parseLayout("not json", settingKeys), isNull);
    expect(HouseholdLooks.parseLayout(jsonEncode({"apps": "x"}), settingKeys), isNull);
  });

  group("the newer change of each item wins", () {
    test("stamps ride along in the entries, and a TV that reads entries without them still reads the rest", () {
      final look = HouseholdLooks.lookJson({"accent_color": "FF6D00"}, {"accent_color": 5, "dock_enabled": 7});
      expect(HouseholdLooks.parseLook(look, settingKeys), {"accent_color": "FF6D00"});
      expect(HouseholdLooks.lookStamps(look), {"accent_color": 5, "dock_enabled": 7});
      expect(HouseholdLooks.lookStamps(HouseholdLooks.lookJson({"accent_color": "FF6D00"})), isEmpty);

      final layout = layoutOf(backup(installed: ["com.a.app"], placements: [
        [1, "com.a.app", 0],
      ]));
      final text = HouseholdLooks.layoutJson(layout, {"row:1": 9, "rows": 3});
      expect(HouseholdLooks.layoutStamps(text), {"row:1": 9, "rows": 3});
      expect(HouseholdLooks.layoutJson(HouseholdLooks.parseLayout(text, settingKeys)!), HouseholdLooks.layoutJson(layout));
      expect(HouseholdLooks.layoutStamps("not json"), isEmpty);
    });

    test("two TVs changing different settings both keep theirs", () {
      final merged = HouseholdLooks.mergeLook(
        {"accent_color": "FF6D00", "dock_enabled": true},
        {"accent_color": 200},
        {"accent_color": "00BFA5", "dock_enabled": false},
        {"dock_enabled": 300},
      );
      expect(merged.settings, {"accent_color": "FF6D00", "dock_enabled": false});
      expect(merged.stamps, {"accent_color": 200, "dock_enabled": 300});
    });

    test("the same setting changed on both: the later change wins, and a tie or no stamps goes to the household", () {
      expect(HouseholdLooks.mergeLook({"accent_color": "FF6D00"}, {"accent_color": 200}, {"accent_color": "00BFA5"},
              {"accent_color": 100}).settings,
          {"accent_color": "FF6D00"});
      expect(HouseholdLooks.mergeLook({"accent_color": "FF6D00"}, {"accent_color": 200}, {"accent_color": "00BFA5"},
              {"accent_color": 300}).settings,
          {"accent_color": "00BFA5"});
      // Joining: nothing here was changed since this TV started counting, so the household's wins
      expect(HouseholdLooks.mergeLook({"accent_color": "FF6D00"}, {}, {"accent_color": "00BFA5", "dock_enabled": true},
              {}).settings,
          {"accent_color": "FF6D00"});
    });

    test("a setting put back to its default here, later, stays at its default", () {
      final merged =
          HouseholdLooks.mergeLook({"accent_color": "FF6D00"}, {"accent_color": 200}, {}, {"accent_color": 300});
      expect(merged.settings, isEmpty);
      expect(merged.stamps, {"accent_color": 300});
    });

    test("what changed here is stamped when it changed; the first look and an uninstalled app aren't changes", () {
      final seen = <String, String>{};
      final stamps = <String, int>{};
      HouseholdLooks.observe(seen, stamps, {"accent_color": '"00BFA5"', "app:com.a.app": "shown"}, 100);
      expect(stamps, {"accent_color": 0, "app:com.a.app": 0});
      HouseholdLooks.observe(seen, stamps, {"accent_color": '"FF6D00"', "app:com.a.app": "shown"}, 200);
      expect(stamps["accent_color"], 200);
      expect(stamps["app:com.a.app"], 0);
      // The setting back at its default, the app uninstalled
      HouseholdLooks.observe(seen, stamps, {}, 300);
      expect(stamps["accent_color"], 300);
      expect(stamps["app:com.a.app"], 0);
      // Nothing more changed: nothing is stamped again
      HouseholdLooks.observe(seen, stamps, {}, 400);
      expect(stamps["accent_color"], 300);
      // A long value is remembered by a fingerprint, so the TV doesn't keep a copy of every row
      final long = "x" * 100;
      expect(HouseholdLooks.remembered(long), hasLength(lessThan(30)));
      expect(HouseholdLooks.remembered(long), HouseholdLooks.remembered(long));
    });

    test("an app hidden here and a row reordered on another TV both stay", () {
      final installed = {"com.a.app", "com.b.app"};
      final household = layoutOf(backup(installed: ["com.a.app", "com.b.app"], placements: [
        [1, "com.b.app", 0],
        [1, "com.a.app", 1],
      ]));
      final here = layoutOf({
        ...backup(installed: ["com.a.app", "com.b.app"], placements: [
          [1, "com.a.app", 0],
          [1, "com.b.app", 1],
        ]),
        "apps": [
          {"packageName": "com.a.app", "hidden": true},
          {"packageName": "com.b.app", "hidden": false},
        ],
      });
      final merged = HouseholdLooks.mergeLayout(
          household, {"row:1": 200}, here, {"app:com.a.app": 300, "row:1": 100}, installed);
      expect({for (final a in merged.layout.apps) a.packageName: a.hidden}, {"com.a.app": true, "com.b.app": false});
      expect([for (final p in merged.layout.appsCategories) p["appPackageName"]], ["com.b.app", "com.a.app"]);
      expect(merged.stamps, {"row:1": 200, "app:com.a.app": 300});
    });

    test("a row changed here later keeps this TV's order and the household's places for apps it lacks", () {
      final installed = {"com.a.app", "com.b.app"};
      final household = layoutOf(backup(installed: ["com.a.app", "com.b.app", "com.only.there"], placements: [
        [1, "com.a.app", 0],
        [1, "com.b.app", 1],
        [1, "com.only.there", 2],
      ]));
      final here = layoutOf(backup(installed: ["com.a.app", "com.b.app"], placements: [
        [1, "com.b.app", 0],
        [1, "com.a.app", 1],
      ]));
      final merged = HouseholdLooks.mergeLayout(household, {"row:1": 100}, here, {"row:1": 200}, installed);
      expect([for (final p in merged.layout.appsCategories) p["appPackageName"]],
          ["com.b.app", "com.a.app", "com.only.there"]);
      expect(merged.layout.apps.map((a) => a.packageName), containsAll(["com.only.there"]));
      // And with no stamps here (a TV that just joined) the household's row wins
      final joined = HouseholdLooks.mergeLayout(household, {}, here, {}, installed);
      expect([for (final p in joined.layout.appsCategories) p["appPackageName"]],
          ["com.a.app", "com.b.app", "com.only.there"]);
    });

    group("hidden calendars, calendar by calendar", () {
      final family = "cal:${"1" * 32}";
      final school = "cal:${"2" * 32}";
      final chores = "cal:${"3" * 32}";
      Map<String, Object> hiding(List<String> calendars) => {"hidden_calendars": calendars};

      test("only their keys go between TVs, each once and in order, each its own item", () {
        final look = HouseholdLooks.parseLook(
            jsonEncode({
              "hidden_calendars": [school, "tv:3", family, school, "alex@example.com"]
            }),
            settingKeys)!;
        expect(look, {
          "hidden_calendars": [family, school]
        });
        expect(HouseholdLooks.lookItems({"accent_color": "FF6D00", ...look}),
            {"accent_color": '"FF6D00"', "calendar:$family": "hidden", "calendar:$school": "hidden"});
        // Kept by their ids here only (from before keys): nothing goes out
        expect(layoutOf(backup(installed: [], settings: {"hidden_calendars": ["tv:3"]})).settings, isEmpty);
      });

      test("two TVs hiding different calendars both keep theirs", () {
        final merged = HouseholdLooks.mergeLook(
            hiding([family]), {"calendar:$family": 200}, hiding([school]), {"calendar:$school": 300});
        expect(merged.settings, hiding([family, school]));
        expect(merged.stamps, {"calendar:$family": 200, "calendar:$school": 300});
      });

      test("shown again later on one TV, it's shown on the other; hidden again later here, it stays hidden", () {
        // Shown on another TV (its item gone there, stamped) after it was hidden here
        expect(
            HouseholdLooks.mergeLook({}, {"calendar:$family": 300}, hiding([family]), {"calendar:$family": 200})
                .settings,
            isEmpty);
        expect(
            HouseholdLooks.mergeLook({}, {"calendar:$family": 200}, hiding([family]), {"calendar:$family": 300})
                .settings,
            hiding([family]));
        // Shown here after it was hidden on another TV
        expect(
            HouseholdLooks.mergeLook(hiding([family]), {"calendar:$family": 200}, {}, {"calendar:$family": 300})
                .settings,
            isEmpty);
        expect(
            HouseholdLooks.mergeLook(hiding([family]), {"calendar:$family": 300}, {}, {"calendar:$family": 200})
                .settings,
            hiding([family]));
      });

      test("one the household has no say about stays hidden here, and one only another TV has is kept", () {
        // A TV that just joined (nothing stamped here), the household's entry from a TV before keys or one without
        // the calendar, and the household's giving back this TV's own stamp
        expect(HouseholdLooks.mergeLook({"accent_color": "FF6D00"}, {}, hiding([chores]), {}).settings,
            {"accent_color": "FF6D00", ...hiding([chores])});
        expect(HouseholdLooks.mergeLook({}, {"calendar:$chores": 200}, hiding([chores]), {"calendar:$chores": 200})
                .settings,
            hiding([chores]));
        // Hidden on a TV this one's account isn't on: kept, so it applies when the calendar comes here
        final kept = HouseholdLooks.mergeLook(hiding([school]), {"calendar:$school": 200}, {}, {});
        expect(kept.settings, hiding([school]));
        expect(kept.stamps, {"calendar:$school": 200});
      });

      test("observed one by one: hiding one and showing another are separate changes", () {
        final seen = <String, String>{};
        final stamps = <String, int>{};
        HouseholdLooks.observe(seen, stamps, HouseholdLooks.lookItems({"accent_color": "FF6D00"}), 100);
        HouseholdLooks.observe(
            seen, stamps, HouseholdLooks.lookItems({"accent_color": "FF6D00", ...hiding([family, school])}), 200);
        HouseholdLooks.observe(
            seen, stamps, HouseholdLooks.lookItems({"accent_color": "FF6D00", ...hiding([school])}), 300);
        expect(stamps, {"accent_color": 0, "calendar:$family": 300, "calendar:$school": 200});
      });
    });

    test("rows added on the household's side come with their apps; a row added here later stays", () {
      final installed = {"com.a.app"};
      final household = layoutOf(backup(installed: ["com.a.app"], rows: [1, 2], placements: [
        [2, "com.a.app", 0],
      ]));
      final here = layoutOf(backup(installed: ["com.a.app"], rows: [1]));
      final taken = HouseholdLooks.mergeLayout(household, {"rows": 200, "row:2": 200}, here, {}, installed);
      expect(taken.layout.categories.map((c) => c["id"]), [1, 2]);
      expect(taken.layout.appsCategories.single["categoryId"], 2);
      final kept = HouseholdLooks.mergeLayout(here, {"rows": 100}, household, {"rows": 200, "row:2": 200}, installed);
      expect(kept.layout.categories.map((c) => c["id"]), [1, 2]);
      expect(kept.layout.appsCategories.single["categoryId"], 2);
    });
  });

  test("a part the household doesn't have comes from this TV, and with neither there is nothing to put in place", () {
    final local = layoutOf(backup(installed: ["com.a.app"], settings: {"accent_color": "00BFA5"}));
    final withLook = HouseholdLooks.compose({"accent_color": "FF6D00"}, null, local)!;
    expect(withLook.settings, {"accent_color": "FF6D00"});
    expect(withLook.apps.map((a) => a.packageName), ["com.a.app"]);
    expect(HouseholdLooks.compose({"accent_color": "FF6D00"}, null, null), isNull);
    expect(HouseholdLooks.compose(null, local, null), isNull);
  });
}
