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
    final backupPath = await backupService.exportBackup();
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
    await backupService.importBackup();

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

    await backupService.importBackup(file);
    final categories = await database.getCategories();
    expect(categories.length, 1);
    expect(categories[0].sort, CategorySort.manual);
    expect(categories[0].type, CategoryType.grid);
  });

  group("automatic backup", () {
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

    test("a profile without a saved layout reports none", () async {
      final settingsService = SettingsService(sharedPreferences);
      expect(await backupService.loadProfileLayout("New Person", settingsService), isFalse);
    });
  });
}
