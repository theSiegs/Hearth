import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/share/share_applier.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/share/share_wallpapers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the pairing choices a copy hands to the Java side.
class _Channel extends FLauncherChannel {
  final List<(String, List<Map<String, dynamic>>)> pairings = [];
  int kept = 0;

  @override
  Future<Map<dynamic, dynamic>> applySharePairings(String profileKey, List<Map<String, dynamic>> choices) async {
    pairings.add((profileKey, choices));
    return {"applied": choices.length - kept, "kept": kept, "skipped": 0};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FLauncherDatabase database;
  late SharedPreferences prefs;
  late BackupService backup;
  late SettingsService settings;
  late Directory tempDir;
  late _Channel channel;
  late int liveChanges;
  late ShareApplier applier;
  late List<String> picturesCopied;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    database = FLauncherDatabase.inMemory();
    backup = BackupService(database, prefs);
    settings = SettingsService(prefs);
    channel = _Channel();
    liveChanges = 0;
    picturesCopied = [];
    applier = ShareApplier(backup, settings, channel, () async => liveChanges++,
        pictures: ShareWallpapers(channel), onPicturesCopied: (key) async => picturesCopied.add(key));
    tempDir = await Directory.systemTemp.createTemp('ltv_share_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );
    await database.persistApps([
      AppsCompanion.insert(packageName: "com.example.video", name: "Video HD", version: "9", hidden: const Value(false)),
      AppsCompanion.insert(packageName: "com.example.news", name: "News", version: "1", hidden: const Value(false)),
    ]);
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  ShareBundle bundle() => ShareBundle.build(
        hearth: "2026.10.62",
        tv: "Den",
        profiles: const [
          ShareProfile(id: "p1", name: "Alex", kids: false),
          ShareProfile(id: "p2", name: "Sam", kids: true),
        ],
        layouts: {
          "p1": {
            "settings": {"accent_color": "#ff00aa"},
            "apps": [
              {"packageName": "com.example.video", "name": "Video", "hidden": true},
              {"packageName": "com.example.gone", "name": "Gone", "hidden": false},
            ],
            "categories": [
              {"id": 1, "name": "Favorites", "sort": 0, "type": 0, "rowHeight": 110, "columnsCount": 6, "order": 0},
            ],
            "appsCategories": [
              {"categoryId": 1, "appPackageName": "com.example.video", "order": 0},
              {"categoryId": 1, "appPackageName": "com.example.gone", "order": 1},
            ],
            "spacers": [],
          },
          "p2": {
            "settings": {"accent_color": "#0000ff"},
            "apps": [],
            "categories": [],
            "appsCategories": [],
            "spacers": [],
          },
        },
        pairings: {
          "p1": const [
            SharedPairing(packageName: "com.netflix.ninja", picker: false, appProfile: "Alex"),
            SharedPairing(packageName: "com.disney.disneyplus", picker: true),
          ],
        },
        settingKeys: settings.settingKeys,
      );

  ShareBundle received() => ShareBundle.parse(bundle().encode(), settingKeys: settings.settingKeys);

  group("the profile a copy lands on by default", () {
    const locals = [
      LocalProfile(key: "user:0:alex", name: "alex", kids: false),
      LocalProfile(key: "user:11", name: "Sam", kids: true),
      LocalProfile(key: "user:12", name: "Alex", kids: true),
    ];

    test("has the same name and the same kind, whatever the case", () {
      expect(defaultTarget(const ShareProfile(id: "p1", name: "Alex", kids: false), locals)!.key, "user:0:alex");
      expect(defaultTarget(const ShareProfile(id: "p2", name: "sam", kids: true), locals)!.key, "user:11");
    });

    test("is none when the kind differs or the name isn't here", () {
      expect(defaultTarget(const ShareProfile(id: "p1", name: "Sam", kids: false), locals), isNull);
      expect(defaultTarget(const ShareProfile(id: "p1", name: "Riley", kids: true), locals), isNull);
    });
  });

  group("where the copies go on a new TV", () {
    const alex = ShareProfile(id: "p1", name: "Alex", kids: false);
    const sam = ShareProfile(id: "p2", name: "Sam", kids: true);

    test("a household of one grown-up goes to this TV's one grown-up, whatever the names", () {
      const locals = [LocalProfile(key: "user:0:kev", name: "Kev", kids: false)];
      expect(defaultTargets(const [alex], locals)["p1"]!.key, "user:0:kev");
    });

    test("the same name still wins, and nothing is guessed when there is more than one to pick from", () {
      const two = [
        LocalProfile(key: "user:0:kev", name: "Kev", kids: false),
        LocalProfile(key: "user:0:alex", name: "Alex", kids: false),
      ];
      expect(defaultTargets(const [alex], two)["p1"]!.key, "user:0:alex");
      const other = [
        LocalProfile(key: "user:0:kev", name: "Kev", kids: false),
        LocalProfile(key: "user:0:jo", name: "Jo", kids: false),
      ];
      expect(defaultTargets(const [alex], other)["p1"], isNull);
      const manySources = [alex, ShareProfile(id: "p3", name: "Pat", kids: false)];
      expect(defaultTargets(manySources, const [LocalProfile(key: "user:0:kev", name: "Kev", kids: false)])["p1"], isNull);
    });

    test("a profile here that already took another's place isn't offered twice", () {
      const locals = [LocalProfile(key: "user:0:alex", name: "Alex", kids: false)];
      const sources = [alex, ShareProfile(id: "p3", name: "Pat", kids: false)];
      final targets = defaultTargets(sources, locals);
      expect(targets["p1"]!.key, "user:0:alex");
      expect(targets["p3"], isNull);
    });

    test("a kids profile is only ever matched by name", () {
      const locals = [LocalProfile(key: "user:11", name: "Riley", kids: true)];
      expect(defaultTargets(const [sam], locals)["p2"], isNull);
      expect(defaultTargets(const [ShareProfile(id: "p2", name: "riley", kids: true)], locals)["p2"]!.key, "user:11");
    });
  });

  group("applying a copy", () {
    const alex = LocalProfile(key: "user:0:alex", name: "Alex", kids: false);
    const sam = LocalProfile(key: "user:11", name: "Sam", kids: true);

    test("to the live profile changes it now, fitted to the apps installed here", () async {
      await prefs.setString(SettingsService.layoutOwnerKey, alex.key);
      final report = await applier.apply(received(), {"p1": alex});

      expect(settings.accentColorHex, "#ff00aa");
      expect((await database.getApplications()).firstWhere((a) => a.packageName == "com.example.video").hidden, isTrue);
      expect((await database.getApplications()).firstWhere((a) => a.packageName == "com.example.video").name, "Video HD");
      expect((await database.getAppsCategories()).map((ac) => ac.appPackageName), ["com.example.video"]);
      expect(liveChanges, 1);
      expect(report.profiles.single.name, "Alex");
      expect(report.profiles.single.layout, isTrue);
      expect(report.profiles.single.missingApps, ["Gone"]);
      expect(report.missingApps, 1);
      expect(report.backupName, startsWith("ltv_backup_before_copy_"));
    });

    test("to another profile waits in its saved layout, and changes nothing live", () async {
      await prefs.setString(SettingsService.layoutOwnerKey, alex.key);
      await settings.setAccentColor("#123456");
      await applier.apply(received(), {"p2": sam});

      expect(settings.accentColorHex, "#123456");
      expect(liveChanges, 0);
      expect(await backup.loadProfileLayout(sam.key, settings), isTrue);
      expect(settings.accentColorHex, "#0000ff");
    });

    test("keeps a backup first that holds what was there before", () async {
      await prefs.setString(SettingsService.layoutOwnerKey, alex.key);
      await settings.setAccentColor("#123456");
      final report = await applier.apply(received(), {"p1": alex});
      final file = File("${tempDir.path}/${report.backupName}");
      expect(await file.exists(), isTrue);
      expect(((json.decode(await file.readAsString()) as Map)["settings"] as Map)["accent_color"], "#123456");
    });

    test("hands the pairing choices to this TV for the profile they go to, and counts what it kept", () async {
      channel.kept = 1;
      final report = await applier.apply(received(), {"p1": alex}, layouts: false);
      expect(channel.pairings.single.$1, alex.key);
      expect(channel.pairings.single.$2, [
        {"pkg": "com.netflix.ninja", "mode": "profile", "appProfile": "Alex"},
        {"pkg": "com.disney.disneyplus", "mode": "picker"},
      ]);
      expect(report.pairingsApplied, 1);
      expect(report.pairingsKept, 1);
      // Only the pairings were asked for: the layout is as it was
      expect(settings.accentColorHex, isNot("#ff00aa"));
      expect(report.profiles.single.layout, isFalse);
    });

    test("never puts a kids profile on a grown-up's or the other way round", () async {
      final report = await applier.apply(received(), {
        "p1": sam, // a grown-up's copy, aimed at a kid
        "p2": alex, // a kid's copy, aimed at a grown-up
      });
      expect(report.profiles, isEmpty);
      expect(channel.pairings, isEmpty);
    });

    test("skips the profiles with no target", () async {
      final report = await applier.apply(received(), {"p2": sam});
      expect(report.profiles.map((p) => p.name), ["Sam"]);
    });

    ShareBundle withExtras({String? hash}) => ShareBundle.build(
          hearth: "2026.10.63",
          tv: "Den",
          profiles: const [ShareProfile(id: "p1", name: "Alex", kids: false)],
          layouts: const {},
          pairings: const {},
          settingKeys: settings.settingKeys,
          wallpapers: {
            "p1": {
              "any": Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]),
              "night": Uint8List.fromList([0xFF, 0xD8, 0xFF, 3, 4]),
            },
          },
          parentPinHash: hash,
        );

    test("puts the pictures in the profile's own folder, under the fixed names, and says so", () async {
      final report = await applier.apply(
          ShareBundle.parse(withExtras().encode(), settingKeys: settings.settingKeys), {"p1": alex});
      final folder = "${tempDir.path}/${WallpaperService.profileFolder(alex.key)}";
      expect(await File("$folder/wallpaper").readAsBytes(), [0xFF, 0xD8, 0xFF, 1, 2]);
      expect(await File("$folder/wallpaper_night").readAsBytes(), [0xFF, 0xD8, 0xFF, 3, 4]);
      expect(await File("$folder/wallpaper_day").exists(), isFalse);
      expect(picturesCopied, [alex.key]);
      expect(report.pictures, 2);
      expect(report.copied, 1);
    });

    test("takes no pictures when told not to", () async {
      await applier.apply(ShareBundle.parse(withExtras().encode(), settingKeys: settings.settingKeys), {"p1": alex},
          pictures: false);
      expect(Directory("${tempDir.path}/wallpapers").existsSync(), isFalse);
      expect(picturesCopied, isEmpty);
    });

    test("takes the parent PIN only when told to, and says so", () async {
      final bundle = ShareBundle.parse(withExtras(hash: "d" * 64).encode(), settingKeys: settings.settingKeys);
      await applier.apply(bundle, {"p1": alex});
      expect(settings.hasParentPin, isFalse);

      final report = await applier.apply(bundle, {"p1": alex}, parentPin: true);
      expect(settings.parentPinHash, "d" * 64);
      expect(report.parentPin, isTrue);
      expect((json.decode(report.toReportJson()) as Map)["parentPin"], isTrue);
    });

    test("counts what saving the PINs and Home Assistant did, nothing of them", () async {
      final report = (await applier.apply(
              ShareBundle.parse(withExtras().encode(), settingKeys: settings.settingKeys), {"p1": alex}))
          .withSecrets(ShareSecretsReport.fromChannel({
        "pins": {"added": 3, "kept": 1, "skipped": 2},
        "ha": true,
      }));
      final sent = json.decode(report.toReportJson()) as Map<String, dynamic>;
      expect(sent["pinsAdded"], 3);
      expect(sent["pinsKept"], 1);
      expect(sent["pinsSkipped"], 2);
      expect(sent["haSet"], true);
    });

    test("tells the sender counts only", () async {
      await prefs.setString(SettingsService.layoutOwnerKey, alex.key);
      final report = await applier.apply(received(), {"p1": alex});
      final sent = json.decode(report.toReportJson()) as Map<String, dynamic>;
      expect(sent, {
        "copied": 1,
        "missingApps": 1,
        "pairingsApplied": 2,
        "pairingsKept": 0,
        "pictures": 0,
        "parentPin": false,
      });
    });
  });
}
