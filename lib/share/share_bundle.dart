import 'dart:convert';
import 'dart:typed_data';

import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/parent_pin_hash.dart';

/// The data of a copy of a profile from one TV to another: what the sending TV puts together, and what the receiving
/// TV takes of it. The bytes come from another TV and are not trusted: everything is checked here, a setting only
/// goes in if it is one a profile has, and nothing in it names a path. The only secret in it is the parent PIN's hash.
///
/// A profile is a look (settings), a layout (apps, rows, the dock), its Profile Pairing choices and its wallpaper
/// pictures; the TV's parent PIN may come along too. (The streaming PINs and the Home Assistant settings travel as a
/// message of their own that only the Java side reads.) Keys like
/// "user:11" differ from TV to TV, so profiles travel by a made-up id and a name; the receiving TV says which of its
/// own profiles each one goes to.
class ShareBundle {
  static const String formatName = "hearth-share";
  static const int version = 1;

  /// What the whole bundle may weigh (as JSON): a layout with hundreds of apps is some 100 KB; the pictures are the rest.
  static const int maxJsonBytes = 40 * 1024 * 1024;

  /// A wallpaper picture (a JPEG of at most 1920x1080) and how many a copy may carry (three a profile, three profiles).
  static const int maxPictureBytes = 3 * 1024 * 1024;
  static const int maxPictures = 9;

  /// What a wallpaper picture is called by where it shows: always, by day, by night.
  static const List<String> wallpaperSlots = ["any", "day", "night"];

  /// The parent PIN's hash as the TV keeps it: SHA-256, in hex.
  static final RegExp parentPinHashPattern = ParentPinHash.pattern;
  static const int maxProfiles = 16;
  static const int maxApps = 2000;
  static const int maxCategories = 200;
  static const int maxAppsCategories = 20000;
  static const int maxSpacers = 200;
  static const int maxPairings = 64;
  static const int maxText = 200;

  /// Settings that belong to the TV (or to the sender's Home Assistant) even when a profile has them.
  static const Set<String> notShared = {
    "hidden_calendars", // calendar ids are this TV's own accounts
    "hidden_watch_next_program_ids", // program ids are this TV's own
    "start_on_boot",
  };

  /// Letters, digits, dots and underscores: what an Android package name holds.
  static final RegExp packagePattern = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');

  final String hearth;
  final String tv;
  final List<ShareProfile> profiles;
  final Map<String, SharedLayout> layouts;
  final Map<String, List<SharedPairing>> pairings;

  /// Each profile's wallpaper pictures by slot ([wallpaperSlots]), as JPEG bytes.
  final Map<String, Map<String, Uint8List>> wallpapers;

  /// The sender's parent PIN as its hash, when the sending parent chose to send it.
  final String? parentPinHash;

  const ShareBundle({
    required this.hearth,
    required this.tv,
    required this.profiles,
    required this.layouts,
    required this.pairings,
    this.wallpapers = const {},
    this.parentPinHash,
  });

  int get pictureCount => wallpapers.values.fold(0, (sum, slots) => sum + slots.length);

  /// The bundle as the sender puts it together. [layouts] are profile-only backups (BackupService.buildBackupData),
  /// by profile id: only what a profile may share is kept.
  static ShareBundle build({
    required String hearth,
    required String tv,
    required List<ShareProfile> profiles,
    required Map<String, Map<String, dynamic>> layouts,
    required Map<String, List<SharedPairing>> pairings,
    required Set<String> settingKeys,
    Map<String, Map<String, Uint8List>> wallpapers = const {},
    String? parentPinHash,
  }) {
    return ShareBundle(
      hearth: hearth,
      tv: tv,
      profiles: profiles,
      layouts: {
        for (final entry in layouts.entries)
          entry.key: SharedLayout.fromBackup(entry.value, settingKeys: settingKeys, lenient: true),
      },
      pairings: pairings,
      wallpapers: wallpapers,
      parentPinHash: parentPinHash,
    );
  }

  String encode() {
    final sections = <Map<String, dynamic>>[
      for (final profile in profiles) ...[
        if (layouts[profile.id] != null) {"type": "layout", "profile": profile.id, "data": layouts[profile.id]!.toJson()},
        if ((pairings[profile.id] ?? const []).isNotEmpty)
          {"type": "pairings", "profile": profile.id, "data": [for (final p in pairings[profile.id]!) p.toJson()]},
        for (final picture in (wallpapers[profile.id] ?? const <String, Uint8List>{}).entries)
          {"type": "wallpaper", "profile": profile.id, "slot": picture.key, "data": base64Encode(picture.value)},
      ],
    ];
    return jsonEncode({
      "format": formatName,
      "v": version,
      "from": {"hearth": hearth, "tv": tv},
      "profiles": [for (final p in profiles) p.toJson()],
      "sections": sections,
      if (parentPinHash != null) "parentPin": parentPinHash,
    });
  }

  /// A bundle from another TV. Throws a [ShareFormatException], whose message is for the log, if it isn't one this
  /// Hearth takes. Sections of a type this version doesn't know are ignored, so a newer Hearth can send more.
  static ShareBundle parse(String source, {required Set<String> settingKeys}) {
    if (source.length > maxJsonBytes) throw const ShareFormatException("too big");
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const ShareFormatException("not JSON");
    }
    final root = _map(decoded, "bundle");
    if (root["format"] != formatName) throw const ShareFormatException("not a Hearth copy");
    final v = root["v"];
    if (v is! int) throw const ShareFormatException("no version");
    if (v > version) throw const ShareFormatException("newer", newer: true);
    final from = root["from"] is Map ? _map(root["from"], "from") : const <String, dynamic>{};
    final profileList = _list(root["profiles"], "profiles", maxProfiles);
    final profiles = <ShareProfile>[];
    final ids = <String>{};
    for (final raw in profileList) {
      final profile = ShareProfile.parse(_map(raw, "profile"));
      if (!ids.add(profile.id)) throw const ShareFormatException("duplicate profile");
      profiles.add(profile);
    }
    final layouts = <String, SharedLayout>{};
    final pairings = <String, List<SharedPairing>>{};
    final wallpapers = <String, Map<String, Uint8List>>{};
    var pictures = 0;
    for (final raw in _list(root["sections"], "sections", maxProfiles * 8)) {
      final section = _map(raw, "section");
      final type = section["type"];
      final profile = section["profile"];
      if (type is! String || profile is! String || !ids.contains(profile)) continue;
      switch (type) {
        case "layout":
          if (layouts.containsKey(profile)) throw const ShareFormatException("duplicate layout");
          layouts[profile] = SharedLayout.fromBackup(_map(section["data"], "layout"), settingKeys: settingKeys);
        case "pairings":
          if (pairings.containsKey(profile)) throw const ShareFormatException("duplicate pairings");
          pairings[profile] = [
            for (final p in _list(section["data"], "pairings", maxPairings)) SharedPairing.parse(_map(p, "pairing")),
          ];
        case "wallpaper":
          final slot = section["slot"];
          if (slot is! String || !wallpaperSlots.contains(slot)) throw const ShareFormatException("bad picture slot");
          if (++pictures > maxPictures) throw const ShareFormatException("too many pictures");
          final slots = wallpapers.putIfAbsent(profile, () => {});
          if (slots.containsKey(slot)) throw const ShareFormatException("duplicate picture");
          slots[slot] = _picture(section["data"]);
      }
    }
    final pin = root["parentPin"];
    if (pin != null && (pin is! String || !parentPinHashPattern.hasMatch(pin))) {
      throw const ShareFormatException("bad parent PIN");
    }
    return ShareBundle(
      hearth: _text(from["hearth"], 40),
      tv: _text(from["tv"], maxText),
      profiles: profiles,
      layouts: layouts,
      pairings: pairings,
      wallpapers: wallpapers,
      parentPinHash: pin as String?,
    );
  }

  /// A picture's bytes if they are a JPEG of a size a wallpaper has; nothing else is ever written to a file.
  static Uint8List _picture(Object? data) {
    if (data is! String || data.length > (maxPictureBytes + 2) ~/ 3 * 4) throw const ShareFormatException("bad picture");
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const ShareFormatException("bad picture");
    }
    if (bytes.length < 4 || bytes.length > maxPictureBytes || bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) {
      throw const ShareFormatException("not a JPEG");
    }
    return bytes;
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is! Map) throw ShareFormatException("$what isn't an object");
    return Map<String, dynamic>.from(value);
  }

  static List<dynamic> _list(Object? value, String what, int max) {
    if (value is! List) throw ShareFormatException("$what isn't a list");
    if (value.length > max) throw ShareFormatException("$what has too many");
    return value;
  }

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

  /// The bundle is from a newer Hearth than this one.
  final bool newer;

  const ShareFormatException(this.message, {this.newer = false});

  @override
  String toString() => "ShareFormatException: $message";
}

/// One profile in a bundle: an id only the bundle knows, its name, and whether it is a kids profile.
class ShareProfile {
  final String id;
  final String name;
  final bool kids;

  const ShareProfile({required this.id, required this.name, required this.kids});

  static ShareProfile parse(Map<String, dynamic> map) {
    final id = map["id"];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,16}$').hasMatch(id)) throw const ShareFormatException("bad profile id");
    final name = ShareBundle._text(map["name"], ShareBundle.maxText);
    if (name.isEmpty) throw const ShareFormatException("a profile without a name");
    return ShareProfile(id: id, name: name, kids: map["kind"] == "kids");
  }

  Map<String, dynamic> toJson() => {"id": id, "name": name, "kind": kids ? "kids" : "adult"};
}

/// A profile's Profile Pairing choice for one streaming app: an app profile by name, or "always ask".
class SharedPairing {
  final String packageName;
  final bool picker;

  /// The app profile's name; empty for [picker].
  final String appProfile;

  const SharedPairing({required this.packageName, required this.picker, this.appProfile = ""});

  static SharedPairing parse(Map<String, dynamic> map) {
    final pkg = map["pkg"];
    if (pkg is! String || !ShareBundle.packagePattern.hasMatch(pkg) || pkg.length > 200) {
      throw const ShareFormatException("bad pairing app");
    }
    if (map["mode"] == "picker") return SharedPairing(packageName: pkg, picker: true);
    final name = ShareBundle._text(map["appProfile"], ShareBundle.maxText);
    if (map["mode"] != "profile" || name.isEmpty) throw const ShareFormatException("bad pairing");
    return SharedPairing(packageName: pkg, picker: false, appProfile: name);
  }

  Map<String, dynamic> toJson() =>
      picker ? {"pkg": packageName, "mode": "picker"} : {"pkg": packageName, "mode": "profile", "appProfile": appProfile};
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

  Map<String, dynamic> toJson() => {
        "settings": settings,
        "apps": [for (final app in apps) app.toJson()],
        "categories": categories,
        "appsCategories": appsCategories,
        "spacers": spacers,
      };
}

class SharedApp {
  final String packageName;
  final String name;
  final bool hidden;

  const SharedApp(this.packageName, this.name, this.hidden);

  Map<String, dynamic> toJson() => {"packageName": packageName, "name": name, "hidden": hidden};
}
