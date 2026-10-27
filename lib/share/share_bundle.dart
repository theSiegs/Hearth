import 'package:flauncher/models/category.dart';

/// A profile's look and layout as they move between TVs (household sync: HouseholdLooks), and the limits what comes
/// from another TV is checked against. What comes from another TV is not trusted: everything is checked here, a setting
/// only goes in if it is one a profile has, and nothing in it names a path. (It began as the copy of profiles between
/// TVs, which household sync replaced.)
class ShareBundle {
  ShareBundle._();

  /// A wallpaper picture as it goes to another TV: a JPEG of at most 1920x1080.
  static const int maxPictureBytes = 3 * 1024 * 1024;
  static const int maxApps = 2000;
  static const int maxCategories = 200;
  static const int maxAppsCategories = 20000;
  static const int maxSpacers = 200;
  static const int maxText = 200;

  /// Settings that belong to the TV even when a profile has them.
  static const Set<String> notShared = {
    "hidden_watch_next_program_ids", // program ids are this TV's own
    "start_on_boot",
  };

  /// The setting of a profile's hidden calendars. Only their keys (the same calendar on every TV, "cal:…") go between
  /// TVs; one hidden by its id on this TV ("tv:12", from before keys) stays here ([sharedCalendars], [thisTvsCalendars]).
  static const String hiddenCalendarsKey = "hidden_calendars";
  static const int maxHiddenCalendars = 500;

  static final RegExp _calendarKey = RegExp(r'^cal:[0-9a-f]{32}$');

  /// The calendar keys in a hidden calendars setting, each once and in order: what goes between TVs.
  static List<String> sharedCalendars(Object? value) =>
      value is List ? ({for (final c in value) if (c is String && _calendarKey.hasMatch(c)) c}.toList()..sort()) : [];

  /// The calendars in a hidden calendars setting that are this TV's own (hidden by their id here).
  static List<String> thisTvsCalendars(Object? value) =>
      value is List ? [for (final c in value) if (c is String && !_calendarKey.hasMatch(c)) c] : [];

  /// Letters, digits, dots and underscores: what an Android package name holds.
  static final RegExp packagePattern = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');

  static String _text(Object? value, int max) {
    if (value is! String) return "";
    return _clean(value, max);
  }

  /// Text from another TV for a screen or a log: no control characters, cut to [max].
  static String _clean(String value, int max) {
    final cleaned = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), " ").replaceAll(RegExp(r'\s+'), " ").trim();
    return cleaned.length > max ? cleaned.substring(0, max) : cleaned;
  }
}

class ShareFormatException implements Exception {
  final String message;

  const ShareFormatException(this.message);

  @override
  String toString() => "ShareFormatException: $message";
}

/// An app of the receiving TV, as the layout needs it: the name and version are this TV's own.
class InstalledApp {
  final String packageName;
  final String name;
  final String version;
  final int? lastLaunchedAt;

  const InstalledApp({required this.packageName, required this.name, required this.version, this.lastLaunchedAt});
}

/// A profile's layout and look, checked: the settings it may carry, and the apps, rows and spacers, with nothing that
/// isn't ours to take (names and versions of apps, when each was last opened: those are the receiving TV's own).
class SharedLayout {
  final Map<String, Object> settings;

  /// Packages in the layout and whether each is hidden, with the name the sender gave it (for "wasn't installed here").
  final List<SharedApp> apps;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> appsCategories;
  final List<Map<String, dynamic>> spacers;

  const SharedLayout({
    required this.settings,
    required this.apps,
    required this.categories,
    required this.appsCategories,
    required this.spacers,
  });

  /// From a profile-only backup map. [lenient] (the sender's own data) drops what doesn't fit instead of refusing.
  static SharedLayout fromBackup(Map<String, dynamic> backup, {required Set<String> settingKeys, bool lenient = false}) {
    final allowed = {for (final key in settingKeys) if (!_isOurs(key)) key};
    final settings = <String, Object>{};
    final rawSettings = backup["settings"];
    if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        final key = entry.key;
        if (key is! String || !allowed.contains(key)) continue;
        if (key == ShareBundle.hiddenCalendarsKey) {
          final calendars = entry.value is List && (entry.value as List).length <= 2000
              ? ShareBundle.sharedCalendars(entry.value).take(ShareBundle.maxHiddenCalendars).toList()
              : const <String>[];
          if (calendars.isNotEmpty) settings[key] = calendars;
          continue;
        }
        final value = _setting(entry.value);
        if (value != null) settings[key] = value;
      }
    }

    final apps = <SharedApp>[];
    final seenApps = <String>{};
    for (final raw in _items(backup["apps"], ShareBundle.maxApps, lenient)) {
      if (raw is! Map) continue;
      final pkg = raw["packageName"];
      if (pkg is! String || !ShareBundle.packagePattern.hasMatch(pkg) || pkg.length > 200 || !seenApps.add(pkg)) continue;
      apps.add(SharedApp(pkg, ShareBundle._text(raw["name"], ShareBundle.maxText), raw["hidden"] == true));
    }

    final categories = <Map<String, dynamic>>[];
    final categoryIds = <int>{};
    for (final raw in _items(backup["categories"], ShareBundle.maxCategories, lenient)) {
      if (raw is! Map) continue;
      final id = raw["id"];
      final name = raw["name"];
      if (id is! int || id < 0 || name is! String || !categoryIds.add(id)) continue;
      categories.add({
        "id": id,
        "name": ShareBundle._clean(name, ShareBundle.maxText),
        "sort": _within(raw["sort"], 0, CategorySort.values.length - 1, 0),
        "type": _within(raw["type"], 0, CategoryType.values.length - 1, 0),
        "rowHeight": _within(raw["rowHeight"], 1, 2000, 110),
        "columnsCount": _within(raw["columnsCount"], 1, 50, 6),
        "order": _within(raw["order"], 0, 100000, 0),
      });
    }

    final appsCategories = <Map<String, dynamic>>[];
    final placed = <String>{};
    for (final raw in _items(backup["appsCategories"], ShareBundle.maxAppsCategories, lenient)) {
      if (raw is! Map) continue;
      final categoryId = raw["categoryId"];
      final pkg = raw["appPackageName"];
      if (categoryId is! int || !categoryIds.contains(categoryId) || pkg is! String || !seenApps.contains(pkg)) continue;
      if (!placed.add("$categoryId|$pkg")) continue;
      appsCategories.add({"categoryId": categoryId, "appPackageName": pkg, "order": _within(raw["order"], 0, 100000, 0)});
    }

    final spacers = <Map<String, dynamic>>[];
    final spacerIds = <int>{};
    for (final raw in _items(backup["spacers"], ShareBundle.maxSpacers, lenient)) {
      if (raw is! Map) continue;
      final id = raw["id"];
      if (id is! int || id < 0 || !spacerIds.add(id)) continue;
      spacers.add({
        "id": id,
        "height": _within(raw["height"], 1, 2000, 50),
        "order": _within(raw["order"], 0, 100000, 0),
      });
    }

    return SharedLayout(
      settings: settings,
      apps: apps,
      categories: categories,
      appsCategories: appsCategories,
      spacers: spacers,
    );
  }

  /// Settings a profile has but another TV must not take (see [ShareBundle.notShared]) or that belong to this TV.
  static bool _isOurs(String key) => key.startsWith("device_") || ShareBundle.notShared.contains(key);

  /// A setting's value if it is a kind the settings use (and not absurdly long), else null.
  static Object? _setting(Object? value) {
    if (value is bool || value is int) return value as Object;
    if (value is double) return value.isFinite ? value : null;
    if (value is String) return value.length <= 2000 ? value : null;
    if (value is List) {
      if (value.length > 500) return null;
      final items = <String>[];
      for (final item in value) {
        if (item is! String || item.length > 200) return null;
        items.add(item);
      }
      return items;
    }
    return null;
  }

  static List<dynamic> _items(Object? value, int max, bool lenient) {
    if (value == null) return const [];
    if (value is! List) {
      if (lenient) return const [];
      throw const ShareFormatException("a layout list isn't a list");
    }
    if (value.length > max) {
      if (lenient) return value.take(max).toList();
      throw const ShareFormatException("a layout list has too many");
    }
    return value;
  }

  static int _within(Object? value, int min, int max, int fallback) {
    if (value is! num) return fallback;
    final n = value.toInt();
    return n < min || n > max ? fallback : n;
  }

  /// The layout as the receiving TV has it in an ordinary profile-only backup (BackupService.restoreBackupData):
  /// only the apps installed here, each with this TV's own name and version. Returns it with the names the sender
  /// gave to the apps this TV doesn't have (placements for those are left out, so nothing dangles).
  ({Map<String, dynamic> backup, List<String> missing}) forInstalled(List<InstalledApp> installed) {
    final here = {for (final app in installed) app.packageName: app};
    final inLayout = {for (final app in apps) app.packageName: app};
    final missing = [
      for (final app in apps)
        if (!here.containsKey(app.packageName)) app.name.isEmpty ? app.packageName : app.name,
    ];
    return (
      backup: {
        "version": 1,
        "onlyChosenSettings": true,
        "settings": settings,
        "apps": [
          for (final app in installed)
            {
              "packageName": app.packageName,
              "name": app.name,
              "version": app.version,
              "hidden": inLayout[app.packageName]?.hidden ?? false,
              "lastLaunchedAt": app.lastLaunchedAt,
            },
        ],
        "categories": categories,
        "appsCategories": [
          for (final placement in appsCategories)
            if (here.containsKey(placement["appPackageName"])) placement,
        ],
        "spacers": spacers,
      },
      missing: missing,
    );
  }
}

class SharedApp {
  final String packageName;
  final String name;
  final bool hidden;

  const SharedApp(this.packageName, this.name, this.hidden);
}
