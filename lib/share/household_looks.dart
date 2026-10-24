import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flauncher/share/share_bundle.dart';

/// A profile's look and layout as household entries (docs/household-sync.md, "Look and layout"). The look is the
/// profile's chosen settings; the layout is its apps, rows and spacers. Both are written the same way every time for the
/// same content (keys and lists in a fixed order, no app names, which are each TV's own), so a TV can tell its layout
/// from the household's by comparing text. What comes from the household came from another TV: it is read through
/// [SharedLayout.fromBackup], which keeps only what a profile may have.
class HouseholdLooks {
  HouseholdLooks._();

  /// A short fingerprint of an entry's text, to remember which one this TV has.
  static String fingerprint(String text) => sha256.convert(utf8.encode(text)).toString();

  /// The look entry for [settings].
  static String lookJson(Map<String, Object> settings) {
    final keys = settings.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: settings[key]});
  }

  /// The layout entry for [layout]: apps by package, rows by id, placements by row, order and app, spacers by id.
  static String layoutJson(SharedLayout layout) {
    final apps = [...layout.apps]..sort((a, b) => a.packageName.compareTo(b.packageName));
    final categories = [...layout.categories]..sort((a, b) => (a["id"] as int).compareTo(b["id"] as int));
    final placements = [...layout.appsCategories]..sort((a, b) {
        final byRow = (a["categoryId"] as int).compareTo(b["categoryId"] as int);
        if (byRow != 0) return byRow;
        final byOrder = (a["order"] as int).compareTo(b["order"] as int);
        if (byOrder != 0) return byOrder;
        return (a["appPackageName"] as String).compareTo(b["appPackageName"] as String);
      });
    final spacers = [...layout.spacers]..sort((a, b) => (a["id"] as int).compareTo(b["id"] as int));
    return jsonEncode({
      "apps": [for (final app in apps) {"packageName": app.packageName, "hidden": app.hidden}],
      "categories": [
        for (final c in categories)
          {
            "id": c["id"],
            "name": c["name"],
            "sort": c["sort"],
            "type": c["type"],
            "rowHeight": c["rowHeight"],
            "columnsCount": c["columnsCount"],
            "order": c["order"],
          },
      ],
      "appsCategories": [
        for (final p in placements) {"categoryId": p["categoryId"], "appPackageName": p["appPackageName"], "order": p["order"]},
      ],
      "spacers": [for (final s in spacers) {"id": s["id"], "height": s["height"], "order": s["order"]}],
    });
  }

  /// This TV's layout ([local]) as it goes to the household: the household's apps that aren't installed here, and their
  /// places in rows this TV still has, are kept ([household], [installed]), so a TV without an app doesn't take it away
  /// from the others.
  static SharedLayout withMissingApps(SharedLayout local, SharedLayout? household, Set<String> installed) {
    if (household == null) return local;
    final rows = {for (final c in local.categories) c["id"] as int};
    final apps = [...local.apps];
    final inLocal = {for (final app in local.apps) app.packageName};
    for (final app in household.apps) {
      if (!installed.contains(app.packageName) && inLocal.add(app.packageName)) apps.add(app);
    }
    final placements = [...local.appsCategories];
    for (final p in household.appsCategories) {
      final pkg = p["appPackageName"] as String;
      if (!installed.contains(pkg) && rows.contains(p["categoryId"])) placements.add(p);
    }
    return SharedLayout(
      settings: local.settings,
      apps: apps,
      categories: local.categories,
      appsCategories: placements,
      spacers: local.spacers,
    );
  }

  /// A look entry's settings, kept to those a profile may have; null when it isn't one.
  static Map<String, Object>? parseLook(String text, Set<String> settingKeys) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return SharedLayout.fromBackup({"settings": decoded}, settingKeys: settingKeys).settings;
    } on FormatException {
      return null;
    } on ShareFormatException {
      return null;
    }
  }

  /// A layout entry, checked; null when it isn't one.
  static SharedLayout? parseLayout(String text, Set<String> settingKeys) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return SharedLayout.fromBackup(Map<String, dynamic>.from(decoded), settingKeys: settingKeys);
    } on FormatException {
      return null;
    } on ShareFormatException {
      return null;
    }
  }

  /// The profile's look and layout put back together from its entries, each taken from [local] when the household has
  /// none; null when a part is in neither (a profile this TV has no layout for yet).
  static SharedLayout? compose(Map<String, Object>? look, SharedLayout? layout, SharedLayout? local) {
    final settings = look ?? local?.settings;
    final parts = layout ?? local;
    if (settings == null || parts == null) return null;
    return SharedLayout(
      settings: settings,
      apps: parts.apps,
      categories: parts.categories,
      appsCategories: parts.appsCategories,
      spacers: parts.spacers,
    );
  }
}
