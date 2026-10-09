import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  final FLauncherDatabase _database;
  final SharedPreferences _sharedPreferences;

  Timer? _autoBackupTimer;

  BackupService(this._database, this._sharedPreferences);

  /// Daily automatic backups: checked now and then hourly until [dispose].
  void start(SettingsService settingsService) {
    _autoBackupTimer?.cancel();
    void check() => autoBackupIfDue(settingsService).catchError((Object e) {
          developer.log("Automatic backup failed", name: "BackupService", error: e);
          return null;
        });
    check();
    _autoBackupTimer = Timer.periodic(const Duration(hours: 1), (_) => check());
  }

  void dispose() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  /// Hearth's own folders that can hold backups, best first: Downloads, external files, documents.
  Future<List<Directory>> _appDirectories() async {
    final List<Directory> dirs = [];
    for (final lookup in [getDownloadsDirectory, getExternalStorageDirectory, getApplicationDocumentsDirectory]) {
      try {
        final dir = await lookup();
        if (dir != null) dirs.add(dir);
      } catch (e) {
        developer.log("Backup folder lookup failed", name: "BackupService", error: e);
      }
    }
    return dirs;
  }

  /// Where a new backup is written.
  Future<Directory> getBackupDirectory() async {
    final dirs = await _appDirectories();
    if (dirs.isEmpty) {
      throw const FileSystemException("Could not find any suitable directory for backup");
    }
    return dirs.first;
  }

  /// Discovers all possible directories where backup files may reside:
  /// - App private and external storage
  /// - Standard Android /sdcard/Download directories
  /// - Mounted USB drives (/storage/*)
  Future<List<Directory>> getSearchDirectories() async {
    final Set<String> paths = {};
    final List<Directory> dirs = [];

    void addDir(Directory? dir) {
      if (dir != null && paths.add(dir.path)) {
        dirs.add(dir);
      }
    }

    (await _appDirectories()).forEach(addDir);

    final standardPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/sdcard/Download',
      '/sdcard/Downloads',
      '/storage/emulated/0',
      '/sdcard',
    ];

    for (final p in standardPaths) {
      final d = Directory(p);
      if (d.existsSync()) {
        addDir(d);
      }
    }

    // Scan mounted USB drives and external volumes in /storage
    try {
      final storageDir = Directory('/storage');
      if (storageDir.existsSync()) {
        for (final entity in storageDir.listSync()) {
          if (entity is Directory) {
            final name = path.basename(entity.path);
            if (name != 'self' && name != 'emulated' && name != 'knox-emulated') {
              addDir(entity);
              final usbDownload = Directory(path.join(entity.path, 'Download'));
              if (usbDownload.existsSync()) {
                addDir(usbDownload);
              }
            }
          }
        }
      }
    } catch (e) {
      developer.log("Couldn't list /storage", name: "BackupService", error: e);
    }

    return dirs;
  }

  static Future<String> _realPath(File file) async {
    try {
      return await file.resolveSymbolicLinks();
    } catch (_) {
      return file.path;
    }
  }

  /// Gets the list of available backup files across all search locations.
  Future<List<BackupFileEntry>> getBackupFiles() async {
    final List<Directory> searchDirs = await getSearchDirectories();
    final List<BackupFileEntry> entries = [];
    final Set<String> seenPaths = {};

    for (final dir in searchDirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list()) {
          // One file is reachable through several paths (/sdcard, /storage/emulated/0, /storage/self/primary)
          if (entity is File && seenPaths.add(await _realPath(entity))) {
            final name = path.basename(entity.path);
            if ((name.startsWith('ltv_backup') || name.startsWith('flauncher_backup')) && name.endsWith('.json')) {
              try {
                final lastModified = await entity.lastModified();
                final size = await entity.length();
                entries.add(BackupFileEntry(
                  file: entity,
                  name: name,
                  lastModified: lastModified,
                  size: size,
                ));
              } catch (e) {
                developer.log("Couldn't read ${entity.path}", name: "BackupService", error: e);
              }
            }
          }
        }
      } catch (e) {
        // Folders Hearth may not read (shared storage without the permission) are skipped
        developer.log("Couldn't list ${dir.path}", name: "BackupService", error: e);
      }
    }

    // Sort by modification date (newest first)
    entries.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return entries;
  }

  /// Exports categories, apps, spacers, and settings to a JSON file.
  Future<String> exportBackup(SettingsService settingsService) async {
    final Directory dir = await getBackupDirectory();
    final filename = 'ltv_backup_${_timestamp(DateTime.now())}.json';
    final File file = File(path.join(dir.path, filename));
    final Map<String, dynamic> backupData = await buildBackupData(settingsService);
    final String jsonStr = const JsonEncoder.withIndent('  ').convert(backupData);
    await file.writeAsString(jsonStr);

    // Also attempt writing a copy to public Download folder if accessible
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync() && downloadDir.path != dir.path) {
        final publicFile = File(path.join(downloadDir.path, filename));
        await publicFile.writeAsString(jsonStr);
      }
    } catch (e) {
      developer.log("Couldn't copy the backup to Download", name: "BackupService", error: e);
    }

    return file.path;
  }

  /// Snapshot of categories, apps, spacers, and settings. With [profileOnly], device-wide settings are left out
  /// so a per-profile layout never carries them between profiles.
  Future<Map<String, dynamic>> buildBackupData(SettingsService settingsService, [bool profileOnly = false]) async {
    // Only what's stored: a setting at its default isn't saved, so a later default change still applies
    final Map<String, dynamic> settingsMap = {};
    final Set<String> keys = _sharedPreferences.getKeys();
    for (final key in keys) {
      final value = _sharedPreferences.get(key);
      if (value != null) {
        settingsMap[key] = value;
      }
    }
    if (profileOnly) {
      settingsMap.removeWhere((key, _) => isDeviceLevelKey(key));
    }

    final List<Category> categories = await _database.getCategories();
    final List<App> apps = await _database.getApplications();
    final List<AppCategory> appsCategories = await _database.getAppsCategories();
    final List<LauncherSpacer> spacers = await _database.getLauncherSpacers();

    return {
      "version": 1,
      "onlyChosenSettings": true,
      "settings": settingsMap,
      "apps": apps.map((a) => {
        "packageName": a.packageName,
        "name": a.name,
        "version": a.version,
        "hidden": a.hidden,
        "lastLaunchedAt": a.lastLaunchedAt?.millisecondsSinceEpoch,
      }).toList(),
      "categories": categories.map((c) => {
        "id": c.id,
        "name": c.name,
        "sort": c.sort.index,
        "type": c.type.index,
        "rowHeight": c.rowHeight,
        "columnsCount": c.columnsCount,
        "order": c.order,
      }).toList(),
      "appsCategories": appsCategories.map((ac) => {
        "categoryId": ac.categoryId,
        "appPackageName": ac.appPackageName,
        "order": ac.order,
      }).toList(),
      "spacers": spacers.map((s) => {
        "id": s.id,
        "height": s.height,
        "order": s.order,
      }).toList(),
    };
  }

  /// Imports categories, apps, spacers, and settings from the JSON file.
  Future<void> importBackup(File backupFile, SettingsService settingsService) async {
    if (!await backupFile.exists()) {
      throw FileNotFoundException("Backup file not found at ${backupFile.path}");
    }

    final String jsonStr = await backupFile.readAsString();
    final Map<String, dynamic> backupData = json.decode(jsonStr) as Map<String, dynamic>;
    await restoreBackupData(backupData, settingsService);
  }

  /// Replaces the launcher layout and settings with [backupData]. With [profileOnly], device-wide settings are kept.
  Future<void> restoreBackupData(Map<String, dynamic> backupData, SettingsService settingsService,
      [bool profileOnly = false]) async {
    if (backupData["version"] != 1) {
      throw FormatException("Invalid backup file version");
    }

    final Map<String, dynamic> settingsMap = Map<String, dynamic>.from(backupData["settings"] as Map);
    if (profileOnly) {
      settingsMap.removeWhere((key, _) => isDeviceLevelKey(key));
    }
    if (backupData["onlyChosenSettings"] != true) SettingsService.forgetOldDefaults(settingsMap);
    // A setting the backup doesn't carry was at its default
    for (final key in settingsService.settingKeys) {
      if (!settingsMap.containsKey(key) && !isDeviceLevelKey(key)) await _sharedPreferences.remove(key);
    }
    await settingsService.importSettingsMap(settingsMap);

    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM apps_categories;');
      await _database.customStatement('DELETE FROM launcher_spacers;');
      await _database.customStatement('DELETE FROM categories;');
      await _database.customStatement('DELETE FROM apps;');

      final List<dynamic> appsJson = backupData["apps"] as List;
      final List<AppsCompanion> appsCompanions = appsJson.map((a) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(a as Map);
        final int? lla = map["lastLaunchedAt"] as int?;
        return AppsCompanion(
          packageName: Value(map["packageName"] as String),
          name: Value(map["name"] as String),
          version: Value(map["version"] as String),
          hidden: Value(map["hidden"] as bool),
          lastLaunchedAt: Value(lla != null ? DateTime.fromMillisecondsSinceEpoch(lla) : null),
        );
      }).toList();
      await _database.batch((batch) {
        batch.insertAll(_database.apps, appsCompanions);
      });

      final List<dynamic> categoriesJson = backupData["categories"] as List;
      final List<CategoriesCompanion> categoriesCompanions = categoriesJson.map((c) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(c as Map);
        final int sortIndex = (map["sort"] as num?)?.toInt() ?? 0;
        final CategorySort sort = (sortIndex >= 0 && sortIndex < CategorySort.values.length)
            ? CategorySort.values[sortIndex]
            : CategorySort.manual;

        final int typeIndex = (map["type"] as num?)?.toInt() ?? 0;
        final CategoryType type = (typeIndex >= 0 && typeIndex < CategoryType.values.length)
            ? CategoryType.values[typeIndex]
            : CategoryType.grid;

        return CategoriesCompanion(
          id: Value(map["id"] as int),
          name: Value(map["name"] as String),
          sort: Value(sort),
          type: Value(type),
          rowHeight: Value(map["rowHeight"] as int),
          columnsCount: Value(map["columnsCount"] as int),
          order: Value(map["order"] as int),
        );
      }).toList();
      await _database.batch((batch) {
        batch.insertAll(_database.categories, categoriesCompanions);
      });

      final List<dynamic> appsCategoriesJson = backupData["appsCategories"] as List;
      final List<AppsCategoriesCompanion> appsCategoriesCompanions = appsCategoriesJson.map((ac) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(ac as Map);
        return AppsCategoriesCompanion(
          categoryId: Value(map["categoryId"] as int),
          appPackageName: Value(map["appPackageName"] as String),
          order: Value(map["order"] as int),
        );
      }).toList();
      await _database.batch((batch) {
        batch.insertAll(_database.appsCategories, appsCategoriesCompanions);
      });

      final List<dynamic> spacersJson = backupData["spacers"] as List;
      final List<LauncherSpacersCompanion> spacersCompanions = spacersJson.map((s) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(s as Map);
        return LauncherSpacersCompanion(
          id: Value(map["id"] as int),
          height: Value(map["height"] as int),
          order: Value(map["order"] as int),
        );
      }).toList();
      await _database.batch((batch) {
        batch.insertAll(_database.launcherSpacers, spacersCompanions);
      });
    });
  }

  /// Settings that belong to the device, not to a profile's layout.
  static bool isDeviceLevelKey(String key) => key.startsWith("device_") || key == "start_on_boot";

  static String _timestamp(DateTime now) =>
      "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_"
      "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";

  static const String _lastAutoBackupKey = "device_last_auto_backup";
  static const String _autoBackupPrefix = "ltv_backup_auto_";

  /// Writes a backup to the app's own storage once a day, keeping the newest [keep]. They show up in the
  /// restore list next to manual backups.
  Future<File?> autoBackupIfDue(SettingsService settingsService,
      {Duration interval = const Duration(days: 1), int keep = 7, DateTime? now}) async {
    final DateTime time = now ?? DateTime.now();
    final int? last = _sharedPreferences.getInt(_lastAutoBackupKey);
    if (last != null && time.difference(DateTime.fromMillisecondsSinceEpoch(last)) < interval) {
      return null;
    }

    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(path.join(dir.path, '$_autoBackupPrefix${_timestamp(time)}.json'));
    await file.writeAsString(jsonEncode(await buildBackupData(settingsService)));
    await _sharedPreferences.setInt(_lastAutoBackupKey, time.millisecondsSinceEpoch);

    final List<File> autoBackups = dir
        .listSync()
        .whereType<File>()
        .where((f) => path.basename(f.path).startsWith(_autoBackupPrefix))
        .toList()
      ..sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));
    for (final old in autoBackups.skip(keep)) {
      try {
        await old.delete();
      } catch (e) {
        developer.log("Couldn't delete an old automatic backup", name: "BackupService", error: e);
      }
    }
    return file;
  }

  Future<File> _profileLayoutFile(String profileName) async {
    final Directory dir = Directory(path.join((await getApplicationDocumentsDirectory()).path, "profile_layouts"));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String safeName = profileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(path.join(dir.path, "$safeName.json"));
  }

  Future<void> saveProfileLayout(String profileName, SettingsService settingsService) async {
    final File file = await _profileLayoutFile(profileName);
    await file.writeAsString(jsonEncode(await buildBackupData(settingsService, true)));
  }

  /// A profile's settings back to their defaults (device-level settings, like the TV's own, stay).
  Future<void> resetProfileSettings(SettingsService settingsService) async {
    for (final key in settingsService.settingKeys) {
      if (!isDeviceLevelKey(key)) await _sharedPreferences.remove(key);
    }
    settingsService.reload();
  }

  /// Returns false when this profile has no saved layout yet.
  Future<bool> loadProfileLayout(String profileName, SettingsService settingsService) async {
    final File file = await _profileLayoutFile(profileName);
    if (!await file.exists()) {
      return false;
    }
    final Map<String, dynamic> data = json.decode(await file.readAsString()) as Map<String, dynamic>;
    await restoreBackupData(data, settingsService, true);
    return true;
  }
}

class BackupFileEntry {
  final File file;
  final String name;
  final DateTime lastModified;
  final int size;

  BackupFileEntry({
    required this.file,
    required this.name,
    required this.lastModified,
    required this.size,
  });
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
