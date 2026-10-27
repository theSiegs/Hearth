import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/household_looks_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/share/household_looks.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/share/share_wallpapers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The household's side as the Java side reports it: each profile's look and layout entries, and what this TV gave.
class _FakeChannel extends FLauncherChannel {
  final Map<String, Map<String, dynamic>> profiles = {};
  int version = 1;
  final List<String> given = [];

  /// Just joined, holding the household's settings; what the Java side says they change in pairings and PINs.
  bool review = false;
  Map<dynamic, dynamic>? javaPreview;
  bool finished = false;
  bool restored = false;
  String? parentPinHash;

  @override
  Future<Map<dynamic, dynamic>?> getHouseholdLooks(int since) async {
    if (since == version) return {"version": version, if (review) "review": true};
    return {
      "version": version,
      if (review) "review": true,
      "profiles": {for (final e in profiles.entries) e.key: {...e.value, "wallpapers": {}}},
    };
  }

  @override
  Future<bool> publishHouseholdLook(String profileKey, String kind, String value) async {
    given.add("$profileKey $kind");
    profiles.putIfAbsent(profileKey, () => {})[kind] = value;
    version++;
    return true;
  }

  @override
  Future<String?> publishHouseholdPicture(String profileKey, String slot, Uint8List? jpeg) async => "";

  @override
  Future<Map<dynamic, dynamic>?> getHouseholdJoinPreview() async => review ? javaPreview : null;

  @override
  Future<bool> finishHouseholdJoin() async {
    finished = true;
    review = false;
    version++;
    return true;
  }

  @override
  Future<bool> restoreHouseholdJoinBackup() async => restored = true;

  @override
  Future<Map<dynamic, dynamic>?> getHouseholdParentPin() async =>
      parentPinHash == null ? {"state": "none"} : {"state": "live", "hash": parentPinHash};
}

/// This TV's profiles: the live one's backup and the others' saved layouts, and what was put in place.
class _FakeBackup extends BackupService {
  final Map<String, Map<String, dynamic>> layouts = {};
  final List<String> installed;
  final List<String> applied = [];
  final SettingsService settings;

  _FakeBackup(super.db, super.prefs, this.settings, this.installed);

  @override
  Future<Map<String, dynamic>> buildBackupData(SettingsService settingsService, [bool profileOnly = false]) async =>
      layouts[settings.layoutOwner]!;

  @override
  Future<Map<String, dynamic>?> readProfileLayout(String profileKey) async => layouts[profileKey];

  @override
  Future<List<InstalledApp>> installedApps() async =>
      [for (final pkg in installed) InstalledApp(packageName: pkg, name: pkg, version: "1")];

  @override
  Future<File> backupBeforeCopy(SettingsService settingsService, {DateTime? now}) async => File("unused");

  @override
  Future<void> applySharedLayout(String profileKey, Map<String, dynamic> backup, SettingsService settingsService,
      {required bool live}) async {
    applied.add(profileKey);
    layouts[profileKey] = backup;
  }
}

class _NoPictures extends ShareWallpapers {
  _NoPictures(super.channel);

  @override
  Future<File> file(String profileKey, String slot) async => File("${Directory.systemTemp.path}/none-$slot-$profileKey");
}

Map<String, dynamic> _backup(Map<String, Object> settings, {List<String> apps = const ["com.a.app"]}) => {
      "settings": settings,
      "apps": [for (final pkg in apps) {"packageName": pkg, "name": pkg, "hidden": false}],
      "categories": [
        {"id": 1, "name": "Favorites", "sort": 0, "type": 0, "rowHeight": 110, "columnsCount": 6, "order": 0},
      ],
      "appsCategories": [
        for (var i = 0; i < apps.length; i++) {"categoryId": 1, "appPackageName": apps[i], "order": i},
      ],
      "spacers": const [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FLauncherDatabase database;
  late SettingsService settings;
  late _FakeChannel channel;
  late _FakeBackup backup;
  late HouseholdLooksService service;
  late Directory copies;
  var now = 1000;

  setUp(() async {
    SharedPreferences.setMockInitialValues({SettingsService.layoutOwnerKey: "user:0"});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    channel = _FakeChannel();
    database = FLauncherDatabase.inMemory();
    backup = _FakeBackup(database, prefs, settings, ["com.a.app"]);
    now = 1000;
    copies = await Directory.systemTemp.createTemp("join_backup");
    service = HouseholdLooksService(channel, prefs, backup, settings, _NoPictures(channel),
        onLiveChanged: () async {},
        onPicturesCopied: (_) async {},
        now: () => now,
        joinBackupFolder: () async => Directory("${copies.path}/copy"));
  });

  tearDown(() async {
    await database.close();
    await copies.delete(recursive: true);
  });

  Map<String, dynamic> settingsOf(String key) => Map<String, dynamic>.from(backup.layouts[key]!["settings"] as Map);

  test("taking the household's look keeps the settings that are this TV's own (its calendars)", () async {
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5", "hidden_calendars": ["tv:3"]});
    channel.profiles["user:0"] = {"look": HouseholdLooks.lookJson({"accent_color": "FF6D00"})};
    await service.tick();
    expect(settingsOf("user:0"), {"accent_color": "FF6D00", "hidden_calendars": ["tv:3"]});
  });

  test("a setting changed here and another changed on another TV meanwhile both stay, and both go out", () async {
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5"});
    channel.profiles["user:0"] = {"look": HouseholdLooks.lookJson({"accent_color": "00BFA5"})};
    await service.tick();
    expect(channel.given.where((g) => g.endsWith("look")), isEmpty);

    // Here: the dock goes off at 2000. Elsewhere: the accent changes at 1500, and this TV hears of it after
    now = 2000;
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5", "dock_enabled": false});
    channel.profiles["user:0"]!["look"] = HouseholdLooks.lookJson({"accent_color": "FF6D00"}, {"accent_color": 1500});
    channel.version++;
    await service.tick();
    expect(settingsOf("user:0"), {"accent_color": "FF6D00", "dock_enabled": false});
    final look = channel.profiles["user:0"]!["look"] as String;
    expect(HouseholdLooks.parseLook(look, settings.settingKeys), {"accent_color": "FF6D00", "dock_enabled": false});
    expect(HouseholdLooks.lookStamps(look), {"accent_color": 1500, "dock_enabled": 2000});
  });

  test("on joining, the household's look wins over this TV's own", () async {
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5", "dock_enabled": false});
    channel.profiles["user:0"] = {"look": HouseholdLooks.lookJson({"accent_color": "FF6D00"})};
    await service.tick();
    expect(settingsOf("user:0"), {"accent_color": "FF6D00"});
    expect(channel.given.where((g) => g.endsWith("look")), isEmpty);
  });

  test("a TV from before stamps and this one don't trade the same look back and forth", () async {
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5"});
    channel.profiles["user:0"] = {"look": HouseholdLooks.lookJson({"accent_color": "00BFA5"})};
    await service.tick();
    now = 2000;
    backup.layouts["user:0"] = _backup({"accent_color": "FF6D00"});
    await service.tick();
    expect(channel.given.where((g) => g.endsWith("look")), hasLength(1));
    // The older TV took it and gives it back without stamps
    channel.profiles["user:0"]!["look"] = HouseholdLooks.lookJson({"accent_color": "FF6D00"});
    channel.version++;
    await service.tick();
    await service.tick();
    expect(channel.given.where((g) => g.endsWith("look")), hasLength(1));
  });

  test("a profile the household has nothing for goes out even when it isn't on screen", () async {
    backup.layouts["user:0"] = _backup({"accent_color": "00BFA5"});
    backup.layouts["user:0#sam"] = _backup({"accent_color": "FF6D00"});
    channel.profiles["user:0"] = {
      "look": HouseholdLooks.lookJson({"accent_color": "00BFA5"}),
      "layout": HouseholdLooks.layoutJson(
          SharedLayout.fromBackup(_backup({}), settingKeys: settings.settingKeys, lenient: true)),
    };
    channel.profiles["user:0#sam"] = {};
    await service.tick();
    expect(channel.given, containsAll(["user:0#sam look", "user:0#sam layout"]));
    expect(jsonDecode(channel.profiles["user:0#sam"]!["look"] as String)["accent_color"], "FF6D00");
  });

  group("before joining", () {
    setUp(() {
      channel.review = true;
      channel.javaPreview = {
        "profiles": [
          {"key": "user:0", "name": "Alex", "kids": false, "pairings": 2, "pins": 1},
        ],
        "tvPins": 0,
      };
      backup.layouts["user:0"] = _backup({"accent_color": "00BFA5"});
      channel.profiles["user:0"] = {
        "look": HouseholdLooks.lookJson({"accent_color": "FF6D00"}),
        "layout": HouseholdLooks.layoutJson(
            SharedLayout.fromBackup(_backup({}), settingKeys: settings.settingKeys, lenient: true)),
      };
    });

    test("nothing is taken or given while someone hasn't seen what joining changes", () async {
      await service.tick();
      expect(backup.applied, isEmpty);
      expect(channel.given, isEmpty);
    });

    test("the preview lists what differs here: the look, not the same layout, and the Java side's counts", () async {
      final preview = (await service.joinPreview())!;
      final alex = preview.profiles.single;
      expect(alex.name, "Alex");
      expect(alex.look, isTrue);
      expect(alex.layout, isFalse);
      expect(alex.pairings, 2);
      expect(alex.pins, 1);
      expect(preview.parentPin, isFalse);
      expect(preview.isEmpty, isFalse);
      // The household has a Parent PIN and this TV none: it changes
      channel.parentPinHash = "a" * 64;
      expect((await service.joinPreview())!.parentPin, isTrue);
    });

    test("joining keeps a copy; putting it back restores the look, which then goes out as the newest", () async {
      final preview = (await service.joinPreview())!;
      expect(await service.finishJoin(preview), isTrue);
      expect(channel.finished, isTrue);
      expect(await service.joinBackupAt(), DateTime.fromMillisecondsSinceEpoch(1000));
      await service.tick();
      expect(settingsOf("user:0")["accent_color"], "FF6D00");

      now = 5000;
      expect(await service.restoreJoinBackup(), isTrue);
      expect(channel.restored, isTrue);
      expect(settingsOf("user:0")["accent_color"], "00BFA5");
      final look = channel.profiles["user:0"]!["look"] as String;
      expect(jsonDecode(look)["accent_color"], "00BFA5");
      expect(HouseholdLooks.lookStamps(look)["accent_color"], 5000);
      expect(await service.joinBackupAt(), isNull);
    });

    test("the copy is gone after 14 days", () async {
      await service.finishJoin((await service.joinPreview())!);
      now += const Duration(days: 15).inMilliseconds;
      expect(await service.joinBackupAt(), isNull);
      expect(await Directory("${copies.path}/copy").exists(), isFalse);
    });
  });
}
