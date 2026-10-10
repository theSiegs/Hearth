import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FLauncherDatabase database;
  late SharedPreferences sharedPreferences;
  late BackupService backupService;
  late Directory tempDir;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    sharedPreferences = await SharedPreferences.getInstance();
    database = FLauncherDatabase.inMemory();
    backupService = BackupService(database, sharedPreferences);

    tempDir = await Directory.systemTemp.createTemp('ltv_backup_test');

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test("Export and Import Backup preserves database and SharedPreferences settings", () async {
    // 1. Populate database and SharedPreferences
    await sharedPreferences.setBool("app_highlight_animation_enabled", false);
    await sharedPreferences.setString("themes", "modern");
    await sharedPreferences.setInt("test_int_key", 42);

    await database.persistApps([
      AppsCompanion.insert(
        packageName: "com.test.app1",
        name: "Test App 1",
        version: "1.0.0",
        hidden: const Value(false),
      ),
      AppsCompanion.insert(
        packageName: "com.test.app2",
        name: "Test App 2",
        version: "2.0.0",
        hidden: const Value(true),
      ),
    ]);

    final categoryId = await database.insertCategory(CategoriesCompanion.insert(
      name: "Custom Category",
      order: 1,
    ));

    await database.into(database.appsCategories).insert(AppsCategoriesCompanion.insert(
      categoryId: categoryId,
      appPackageName: "com.test.app1",
      order: 0,
    ));

    await database.into(database.launcherSpacers).insert(LauncherSpacersCompanion.insert(
      height: 100,
      order: 2,
    ));

    // 2. Export Backup
    final settingsService = SettingsService(sharedPreferences);
    final backupPath = await backupService.exportBackup(settingsService);
    final backupFile = File(backupPath);
    expect(await backupFile.exists(), isTrue);

    // Verify backup JSON content
    final jsonContent = await backupFile.readAsString();
    final Map<String, dynamic> decoded = json.decode(jsonContent);
    expect(decoded["version"], 1);
    expect(decoded["settings"]["app_highlight_animation_enabled"], false);
    expect(decoded["settings"]["themes"], "modern");
    expect(decoded["settings"]["test_int_key"], 42);
    expect((decoded["apps"] as List).length, 2);
    expect((decoded["categories"] as List).length, 1);
    expect((decoded["appsCategories"] as List).length, 1);
    expect((decoded["spacers"] as List).length, 1);

    // 3. Clear database and SharedPreferences
    await sharedPreferences.clear();
    await database.transaction(() async {
      await database.customStatement('DELETE FROM apps_categories;');
      await database.customStatement('DELETE FROM launcher_spacers;');
      await database.customStatement('DELETE FROM categories;');
      await database.customStatement('DELETE FROM apps;');
    });

    expect(sharedPreferences.getKeys(), isEmpty);
    expect(await database.getApplications(), isEmpty);
    expect(await database.getCategories(), isEmpty);

    // 4. Import Backup
    await backupService.importBackup(backupFile, settingsService);

    // 5. Verify SharedPreferences and database restored
    expect(sharedPreferences.getBool("app_highlight_animation_enabled"), false);
    expect(sharedPreferences.getString("themes"), "modern");
    expect(sharedPreferences.getInt("test_int_key"), 42);

    final apps = await database.getApplications();
    expect(apps.length, 2);
    final app1 = apps.firstWhere((a) => a.packageName == "com.test.app1");
    expect(app1.name, "Test App 1");
    expect(app1.hidden, false);
    final app2 = apps.firstWhere((a) => a.packageName == "com.test.app2");
    expect(app2.name, "Test App 2");
    expect(app2.hidden, true);

    final categories = await database.getCategories();
    expect(categories.length, 1);
    expect(categories[0].name, "Custom Category");

    final appsCategories = await database.getAppsCategories();
    expect(appsCategories.length, 1);
    expect(appsCategories[0].appPackageName, "com.test.app1");
    expect(appsCategories[0].categoryId, categoryId);

    final spacers = await database.getLauncherSpacers();
    expect(spacers.length, 1);
    expect(spacers[0].height, 100);
  });

  test("Import Backup handles out-of-bounds CategorySort and CategoryType values gracefully", () async {
    final file = File('${tempDir.path}/ltv_backup_corrupted.json');
    await file.writeAsString(json.encode({
      "version": 1,
      "settings": {},
      "apps": [],
      "categories": [
        {
          "id": 100,
          "name": "Corrupted Enum Category",
          "sort": 999, // out of bounds
          "type": 999, // out of bounds
          "rowHeight": 110,
          "columnsCount": 6,
          "order": 0,
        }
      ],
      "appsCategories": [],
      "spacers": [],
    }));

    await backupService.importBackup(file, SettingsService(sharedPreferences));
    final categories = await database.getCategories();
    expect(categories.length, 1);
    expect(categories[0].sort, CategorySort.manual);
    expect(categories[0].type, CategoryType.grid);
  });

  group("automatic backup", () {
    setUp(() => sharedPreferences.clear());

    test("writes once per interval and keeps only the newest copies", () async {
      final settingsService = SettingsService(sharedPreferences);
      final start = DateTime(2026, 10, 1, 9);

      for (int day = 0; day < 9; day++) {
        expect(await backupService.autoBackupIfDue(settingsService, keep: 7, now: start.add(Duration(days: day))),
            isNotNull);
      }
      // Same day again: not due
      expect(await backupService.autoBackupIfDue(settingsService, now: start.add(const Duration(days: 8, hours: 2))),
          isNull);

      final autoFiles = tempDir.listSync().where((f) => f.path.contains("ltv_backup_auto_")).toList();
      expect(autoFiles.length, 7);
      expect(autoFiles.any((f) => f.path.contains("20261001")), isFalse);
      expect(autoFiles.any((f) => f.path.contains("20261009")), isTrue);

      // Listed alongside manual backups so they can be restored
      final listed = await backupService.getBackupFiles();
      expect(listed.where((e) => e.name.startsWith("ltv_backup_auto_")).length, 7);
    });

    test("start backs up at once when one is due", () async {
      backupService.start(SettingsService(sharedPreferences));
      addTearDown(backupService.dispose);
      for (int i = 0; i < 100 && sharedPreferences.getInt("device_last_auto_backup") == null; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(tempDir.listSync().where((f) => f.path.contains("ltv_backup_auto_")), hasLength(1));
    });
  });

  group("profile layouts", () {
    test("restore a profile's layout but keep device-wide settings", () async {
      final settingsService = SettingsService(sharedPreferences);
      await sharedPreferences.setString("themes", "kids_theme");
      await sharedPreferences.setString("device_parent_pin", "parent");
      await database.persistApps([
        AppsCompanion.insert(packageName: "com.kid.app", name: "Kid App", version: "1", hidden: const Value(false)),
      ]);

      await backupService.saveProfileLayout("Riley", settingsService);

      // Another profile changes the layout and the device-wide PIN
      await sharedPreferences.setString("themes", "adult_theme");
      await sharedPreferences.setString("device_parent_pin", "changed");
      await database.customStatement('DELETE FROM apps;');

      expect(await backupService.loadProfileLayout("Riley", settingsService), isTrue);
      expect(sharedPreferences.getString("themes"), "kids_theme");
      expect(sharedPreferences.getString("device_parent_pin"), "changed");
      expect((await database.getApplications()).map((a) => a.packageName), ["com.kid.app"]);
    });

    test("leave the setup flow's progress out of a backup, and keep this TV's on restore", () async {
      final settingsService = SettingsService(sharedPreferences);
      await sharedPreferences.setInt("device_setup_flow_version", 1);
      await sharedPreferences.setString("device_setup_decisions", '{"watching":{"state":"on","at":1}}');
      final data = await backupService.buildBackupData(settingsService);
      expect((data["settings"] as Map).keys.where((k) => k.startsWith("device_setup_")), isEmpty);

      // A backup made before they were left out still carries them: this TV's own stay
      data["settings"] = {...data["settings"] as Map<String, dynamic>, "device_setup_flow_version": 7};
      await sharedPreferences.remove("device_setup_flow_version");
      await backupService.restoreBackupData(data, settingsService);
      expect(sharedPreferences.getInt("device_setup_flow_version"), isNull);
      expect(sharedPreferences.getString("device_setup_decisions"), isNotNull);
    });

    test("a profile without a saved layout reports none", () async {
      final settingsService = SettingsService(sharedPreferences);
      expect(await backupService.loadProfileLayout("New Person", settingsService), isFalse);
    });
  });

  group("settings at their defaults", () {
    setUp(() => sharedPreferences.clear());

    test("aren't exported, and the export says so", () async {
      final settingsService = SettingsService(sharedPreferences);
      await settingsService.setAppLanguage("fr");
      final data = await backupService.buildBackupData(settingsService);
      expect(data["onlyChosenSettings"], isTrue);
      expect(data["settings"]["app_language"], "fr");
      expect((data["settings"] as Map).containsKey("date_format"), isFalse);
    });

    test("go back to their defaults on restore", () async {
      final settingsService = SettingsService(sharedPreferences);
      final data = await backupService.buildBackupData(settingsService);
      await settingsService.setAppLanguage("fr");
      await backupService.restoreBackupData(data, settingsService);
      expect(settingsService.appLanguage, "");
    });

    test("include the dock and Home Assistant panel, so a profile's layout doesn't keep another's", () async {
      final settingsService = SettingsService(sharedPreferences);
      final layout = await backupService.buildBackupData(settingsService, true);
      await settingsService.setDockEnabled(false);
      await settingsService.setHaPanelEnabled(true);
      await backupService.restoreBackupData(layout, settingsService, true);
      expect(settingsService.dockEnabled, isTrue);
      expect(settingsService.haPanelEnabled, isFalse);
    });

    test("an older export's old default date and time count as never chosen", () async {
      final settingsService = SettingsService(sharedPreferences);
      final data = await backupService.buildBackupData(settingsService);
      data.remove("onlyChosenSettings");
      data["settings"] = {...data["settings"] as Map<String, dynamic>, "date_format": "EEEE d", "time_format": "H:mm"};
      await backupService.restoreBackupData(data, settingsService);
      expect(settingsService.dateFormat, SettingsService.defaultDateFormat);
      expect(settingsService.timeFormat, SettingsService.defaultTimeFormat);
    });

    test("a newer export keeps that date and time when they were chosen", () async {
      final settingsService = SettingsService(sharedPreferences);
      await settingsService.setDateTimeFormat("EEEE d", "H:mm");
      final data = await backupService.buildBackupData(settingsService);
      await backupService.restoreBackupData(data, settingsService);
      expect(settingsService.dateFormat, "EEEE d");
      expect(settingsService.timeFormat, "H:mm");
    });
  });
}
