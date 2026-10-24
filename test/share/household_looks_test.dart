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

  test("a part the household doesn't have comes from this TV, and with neither there is nothing to put in place", () {
    final local = layoutOf(backup(installed: ["com.a.app"], settings: {"accent_color": "00BFA5"}));
    final withLook = HouseholdLooks.compose({"accent_color": "FF6D00"}, null, local)!;
    expect(withLook.settings, {"accent_color": "FF6D00"});
    expect(withLook.apps.map((a) => a.packageName), ["com.a.app"]);
    expect(HouseholdLooks.compose({"accent_color": "FF6D00"}, null, null), isNull);
    expect(HouseholdLooks.compose(null, local, null), isNull);
  });
}
