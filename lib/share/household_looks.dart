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

  /// Where a look entry keeps when each setting last changed (a key no setting has: a TV before stamps ignores it).
  static const String lookStampsKey = "~at";

  /// Where a layout entry keeps when each of its items last changed (see [layoutItems]).
  static const String layoutStampsKey = "at";

  /// The look entry for [settings], with when each setting changed ([stamps], by setting key) when given.
  static String lookJson(Map<String, Object> settings, [Map<String, int>? stamps]) {
    final keys = settings.keys.toList()..sort();
    return jsonEncode({
      for (final key in keys) key: settings[key],
      if (stamps != null && stamps.isNotEmpty) lookStampsKey: _sorted(stamps),
    });
  }

  /// The layout entry for [layout] (apps by package, rows by id, placements by row, order and app, spacers by id), with
  /// when each item changed ([stamps], by [layoutItems] id) when given.
  static String layoutJson(SharedLayout layout, [Map<String, int>? stamps]) {
    final text = _layoutText(layout);
    if (stamps == null || stamps.isEmpty) return text;
    return "${text.substring(0, text.length - 1)},${jsonEncode(layoutStampsKey)}:${jsonEncode(_sorted(stamps))}}";
  }

  static Map<String, int> _sorted(Map<String, int> stamps) {
    final keys = stamps.keys.toList()..sort();
    return {for (final key in keys) key: stamps[key]!};
  }

  static String _layoutText(SharedLayout layout) {
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

  /// When each setting of a look entry last changed, by setting key; empty for an entry without stamps (a TV before
  /// them, which counts as long ago).
  static Map<String, int> lookStamps(String text) => _stamps(text, lookStampsKey);

  /// When each item of a layout entry last changed, by [layoutItems] id; empty for an entry without stamps.
  static Map<String, int> layoutStamps(String text) => _stamps(text, layoutStampsKey);

  static Map<String, int> _stamps(String text, String key) {
    try {
      final decoded = jsonDecode(text);
      final raw = decoded is Map ? decoded[key] : null;
      if (raw is! Map) return {};
      return {
        for (final entry in raw.entries)
          if (entry.key is String && (entry.key as String).length <= 300 && entry.value is int && entry.value >= 0)
            entry.key as String: entry.value as int,
      };
    } on FormatException {
      return {};
    }
  }

  // ---- Items: what "the newest change wins" is counted by ----

  /// A look's items: each setting by its key, its value as text (a setting at its default isn't there).
  static Map<String, String> lookItems(Map<String, Object> settings) =>
      {for (final entry in settings.entries) entry.key: jsonEncode(entry.value)};

  /// A layout's items, each one thing a person changes on its own: "rows" (the rows and spacers, their order and how
  /// each looks), "row:<id>" (the apps in that row and their order; the dock is a row) and "app:<package>" (whether it
  /// is hidden). With [installed], only those apps count (a TV can't tell what another TV did with an app it lacks).
  static Map<String, String> layoutItems(SharedLayout layout, [Set<String>? installed]) {
    final decoded = jsonDecode(_layoutText(layout)) as Map;
    bool counts(String pkg) => installed == null || installed.contains(pkg);
    final items = <String, String>{
      "rows": jsonEncode({"categories": decoded["categories"], "spacers": decoded["spacers"]}),
    };
    for (final category in decoded["categories"] as List) {
      final id = (category as Map)["id"];
      items["row:$id"] = jsonEncode([
        for (final p in decoded["appsCategories"] as List)
          if ((p as Map)["categoryId"] == id && counts(p["appPackageName"] as String)) [p["appPackageName"], p["order"]],
      ]);
    }
    for (final app in decoded["apps"] as List) {
      final pkg = (app as Map)["packageName"] as String;
      if (counts(pkg)) items["app:$pkg"] = app["hidden"] == true ? "hidden" : "shown";
    }
    return items;
  }

  /// An item's value as this TV remembers it: short ones as they are, long ones by a fingerprint.
  static String remembered(String value) => value.length <= 24 ? value : "#${fingerprint(value).substring(0, 20)}";

  /// What this TV remembers of a profile's items ([seen]: item to [remembered] value, [stamps]: item to when it last
  /// changed here or was taken) after looking at what it has now ([items]). An item that changed since is stamped [now],
  /// except on the first look ([seen] empty), when everything counts as long ago, so a TV that joins takes the
  /// household's. A setting or a row that is gone counts as a change; an app that is gone doesn't (it was uninstalled).
  static void observe(Map<String, String> seen, Map<String, int> stamps, Map<String, String> items, int now) {
    final first = seen.isEmpty;
    for (final entry in items.entries) {
      final value = remembered(entry.value);
      if (seen[entry.key] == value) continue;
      seen[entry.key] = value;
      stamps[entry.key] = first ? (stamps[entry.key] ?? 0) : now;
    }
    for (final item in seen.keys.toList()) {
      if (items.containsKey(item) || item.startsWith("app:") || seen[item] == _gone) continue;
      seen[item] = _gone;
      stamps[item] = now;
    }
  }

  static const String _gone = "-";

  /// Which side an item comes from: this TV's when it changed here later than the household's did, else the
  /// household's (a tie, and an item neither has stamped, go to the household, as on joining).
  static bool _localWins(String item, Map<String, int> local, Map<String, int> household) =>
      (local[item] ?? 0) > (household[item] ?? 0);

  /// The look when the household's ([household], stamped [householdStamps]) arrives on a TV whose own is [local]
  /// ([localStamps]): setting by setting, the newer change wins. Returns the settings and their stamps.
  static ({Map<String, Object> settings, Map<String, int> stamps}) mergeLook(Map<String, Object> household,
      Map<String, int> householdStamps, Map<String, Object> local, Map<String, int> localStamps) {
    final settings = <String, Object>{};
    final stamps = <String, int>{};
    final keys = {...household.keys, ...local.keys, ...householdStamps.keys, ...localStamps.keys};
    for (final key in keys) {
      final h = household[key];
      final l = local[key];
      final Object? value;
      if (jsonEncode(h) == jsonEncode(l)) {
        value = h;
        stamps[key] = _max(householdStamps[key], localStamps[key]);
      } else if (_localWins(key, localStamps, householdStamps)) {
        value = l;
        stamps[key] = localStamps[key]!;
      } else {
        value = h;
        stamps[key] = householdStamps[key] ?? 0;
      }
      if (value != null) settings[key] = value;
    }
    stamps.removeWhere((_, at) => at == 0);
    return (settings: settings, stamps: stamps);
  }

  /// The layout when the household's arrives on a TV whose own is [local], with [installed] the apps this TV has:
  /// item by item ([layoutItems]), the newer change wins. A row this TV's change wins keeps the household's places
  /// for apps it lacks. Returns the layout (its settings are [local]'s) and the items' stamps.
  static ({SharedLayout layout, Map<String, int> stamps}) mergeLayout(SharedLayout household,
      Map<String, int> householdStamps, SharedLayout local, Map<String, int> localStamps, Set<String> installed) {
    final hItems = layoutItems(household, installed);
    final lItems = layoutItems(local, installed);
    final stamps = <String, int>{};
    bool fromLocal(String item) {
      if (hItems[item] == lItems[item]) {
        stamps[item] = _max(householdStamps[item], localStamps[item]);
        return false;
      }
      final mine = _localWins(item, localStamps, householdStamps);
      stamps[item] = (mine ? localStamps[item] : householdStamps[item]) ?? 0;
      return mine;
    }

    final rowsFrom = fromLocal("rows") ? local : household;
    final placements = <Map<String, dynamic>>[];
    for (final category in rowsFrom.categories) {
      final id = category["id"] as int;
      final item = "row:$id";
      if (!fromLocal(item)) {
        placements.addAll(household.appsCategories.where((p) => p["categoryId"] == id));
        continue;
      }
      placements.addAll(local.appsCategories.where((p) => p["categoryId"] == id));
      placements.addAll(household.appsCategories
          .where((p) => p["categoryId"] == id && !installed.contains(p["appPackageName"] as String)));
    }
    final localApps = {for (final app in local.apps) app.packageName: app};
    final apps = <SharedApp>[];
    final seen = <String>{};
    for (final app in household.apps) {
      seen.add(app.packageName);
      final mine = localApps[app.packageName];
      final item = "app:${app.packageName}";
      if (mine != null && installed.contains(app.packageName)) {
        apps.add(fromLocal(item) ? mine : app);
      } else {
        apps.add(app);
        if (householdStamps[item] != null) stamps[item] = householdStamps[item]!;
      }
    }
    for (final app in local.apps) {
      if (!seen.add(app.packageName)) continue;
      apps.add(app);
      final item = "app:${app.packageName}";
      if (localStamps[item] != null) stamps[item] = localStamps[item]!;
    }
    stamps.removeWhere((_, at) => at == 0);
    return (
      layout: SharedLayout(
        settings: local.settings,
        apps: apps,
        categories: rowsFrom.categories,
        appsCategories: placements,
        spacers: rowsFrom.spacers,
      ),
      stamps: stamps,
    );
  }

  static int _max(int? a, int? b) => (a ?? 0) > (b ?? 0) ? a! : (b ?? 0);

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
