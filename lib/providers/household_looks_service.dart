import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/share/household_looks.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/share/share_wallpapers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps each grown-up profile's look, layout and wallpaper pictures in step with the household's (docs/household-sync.md,
/// "Look and layout"). Every so often it asks the Java side what the household has; a profile whose look or layout
/// changed there gets it, fitted to the apps installed here (live when it is the profile on screen, else in its saved
/// layout), and a changed picture is written to the profile's folder. Then the profile on screen goes out: its look,
/// its layout with the household's apps that aren't installed here kept, and any picture it picked that changed.
///
/// What this TV last took or gave for each profile is remembered (by fingerprint), so a change goes out once, an entry
/// is put in place once, and taking the household's doesn't send it straight back.
class HouseholdLooksService {
  static const Duration every = Duration(seconds: 20);

  /// device_: the TV's own, never part of a profile's layout or a backup.
  static const String knownKey = "device_household_looks_known";

  final FLauncherChannel _channel;
  final SharedPreferences _prefs;
  final BackupService _backup;
  final SettingsService _settings;
  final ShareWallpapers _wallpapers;

  /// The home catches up with the live profile's layout (it was replaced).
  final Future<void> Function() _onLiveChanged;

  /// A profile's pictures were written (the wallpaper on screen catches up when it's the live profile's).
  final Future<void> Function(String profileKey) _onPicturesCopied;

  Timer? _timer;
  bool _running = false;
  bool _backedUp = false;
  int _version = 0;
  Map<String, dynamic> _profiles = const {};

  HouseholdLooksService(this._channel, this._prefs, this._backup, this._settings, this._wallpapers,
      {required Future<void> Function() onLiveChanged, required Future<void> Function(String profileKey) onPicturesCopied})
      : _onLiveChanged = onLiveChanged,
        _onPicturesCopied = onPicturesCopied;

  void start() {
    _timer ??= Timer.periodic(every, (_) => unawaited(tick()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// One round: take what changed in the household, then send what changed here. Does nothing outside a household.
  Future<void> tick() async {
    if (_running) return;
    _running = true;
    try {
      final looks = await _channel.getHouseholdLooks(_version);
      if (looks == null) {
        _version = 0;
        return;
      }
      final profiles = looks["profiles"];
      if (profiles is Map) {
        _profiles = Map<String, dynamic>.from(profiles);
        final known = _known();
        for (final entry in _profiles.entries) {
          if (entry.value is Map) await _take(entry.key, Map<String, dynamic>.from(entry.value as Map), known);
        }
        await _saveKnown(known);
      }
      _version = (looks["version"] as num?)?.toInt() ?? 0;
      await _give();
    } catch (err) {
      noteFailure('household_looks', err);
    } finally {
      _running = false;
    }
  }

  Map<String, dynamic> _known() {
    try {
      final decoded = jsonDecode(_prefs.getString(knownKey) ?? "{}");
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _saveKnown(Map<String, dynamic> known) => _prefs.setString(knownKey, jsonEncode(known));

  Map<String, dynamic> _knownFor(Map<String, dynamic> known, String profileKey) {
    final entry = known[profileKey];
    final mine = entry is Map ? Map<String, dynamic>.from(entry) : <String, dynamic>{};
    known[profileKey] = mine;
    return mine;
  }

  Future<SharedLayout?> _localLayout(String profileKey) async {
    final backup = _settings.layoutOwner == profileKey
        ? await _backup.buildBackupData(_settings, true)
        : await _backup.readProfileLayout(profileKey);
    if (backup == null) return null;
    return SharedLayout.fromBackup(backup, settingKeys: _settings.settingKeys, lenient: true);
  }

  // ---- Taking the household's ----

  Future<void> _take(String profileKey, Map<String, dynamic> state, Map<String, dynamic> known) async {
    final mine = _knownFor(known, profileKey);
    final look = state["look"] as String?;
    final layout = state["layout"] as String?;
    final newLook = look != null && HouseholdLooks.fingerprint(look) != mine["look"];
    final newLayout = layout != null && HouseholdLooks.fingerprint(layout) != mine["layout"];
    if (newLook || newLayout) {
      final keys = _settings.settingKeys;
      final composed = HouseholdLooks.compose(
        look == null ? null : HouseholdLooks.parseLook(look, keys),
        layout == null ? null : HouseholdLooks.parseLayout(layout, keys),
        await _localLayout(profileKey),
      );
      if (composed != null) {
        // The first time a profile takes the household's look here, everything is kept first, as a copy does, so it
        // can be undone in Backup & Restore
        if (mine["look"] == null && mine["layout"] == null && !_backedUp) {
          await _backup.backupBeforeCopy(_settings);
          _backedUp = true;
        }
        final live = _settings.layoutOwner == profileKey;
        final fitted = composed.forInstalled(await _backup.installedApps());
        await _backup.applySharedLayout(profileKey, fitted.backup, _settings, live: live);
        if (live) await _onLiveChanged();
        if (look != null) mine["look"] = HouseholdLooks.fingerprint(look);
        if (layout != null) mine["layout"] = HouseholdLooks.fingerprint(layout);
      }
    }
    final wallpapers = state["wallpapers"];
    if (wallpapers is Map) await _takePictures(profileKey, Map<String, dynamic>.from(wallpapers), mine);
  }

  Future<void> _takePictures(String profileKey, Map<String, dynamic> wallpapers, Map<String, dynamic> mine) async {
    final pictures = mine["pictures"] is Map ? Map<String, dynamic>.from(mine["pictures"] as Map) : <String, dynamic>{};
    var changed = false;
    for (final entry in wallpapers.entries) {
      final slot = entry.key;
      if (!ShareWallpapers.fileNames.containsKey(slot)) continue;
      final had = pictures[slot] is Map ? pictures[slot] as Map : null;
      final value = entry.value;
      if (value == null) {
        // Taken away in the household: gone here too, if this TV had it from the household or gave it
        if (had != null) {
          await _wallpapers.delete(profileKey, slot);
          pictures.remove(slot);
          changed = true;
        }
        continue;
      }
      if (value is! Map) continue;
      final hash = value["hash"] as String?;
      final path = value["path"] as String?;
      if (hash == null || path == null || had?["entry"] == hash) continue;
      final bytes = await File(path).readAsBytes();
      if (await _wallpapers.write(profileKey, {slot: bytes}) == 0) continue;
      pictures[slot] = {"entry": hash, "file": sha256.convert(bytes).toString()};
      changed = true;
    }
    mine["pictures"] = pictures;
    if (changed) await _onPicturesCopied(profileKey);
  }

  // ---- Giving the live profile's ----

  Future<void> _give() async {
    final profileKey = _settings.layoutOwner;
    if (profileKey == null) return;
    final state = _profiles[profileKey];
    // Not a profile whose look the household keeps (a kids profile, or one not told apart yet)
    if (state is! Map) return;
    final local = await _localLayout(profileKey);
    if (local == null) return;
    final known = _known();
    final mine = _knownFor(known, profileKey);
    final keys = _settings.settingKeys;
    final householdLayout = state["layout"] is String ? HouseholdLooks.parseLayout(state["layout"] as String, keys) : null;
    final installed = {for (final app in await _backup.installedApps()) app.packageName};

    final look = HouseholdLooks.lookJson(local.settings);
    if (HouseholdLooks.fingerprint(look) != mine["look"] &&
        await _channel.publishHouseholdLook(profileKey, "look", look)) {
      mine["look"] = HouseholdLooks.fingerprint(look);
    }
    final layout = HouseholdLooks.layoutJson(HouseholdLooks.withMissingApps(local, householdLayout, installed));
    if (HouseholdLooks.fingerprint(layout) != mine["layout"] &&
        await _channel.publishHouseholdLook(profileKey, "layout", layout)) {
      mine["layout"] = HouseholdLooks.fingerprint(layout);
    }
    await _givePictures(profileKey, mine);
    await _saveKnown(known);
  }

  Future<void> _givePictures(String profileKey, Map<String, dynamic> mine) async {
    final pictures = mine["pictures"] is Map ? Map<String, dynamic>.from(mine["pictures"] as Map) : <String, dynamic>{};
    for (final slot in ShareWallpapers.fileNames.keys) {
      final file = await _wallpapers.file(profileKey, slot);
      final had = pictures[slot] is Map ? pictures[slot] as Map : null;
      if (!await file.exists()) {
        if (had != null && await _channel.publishHouseholdPicture(profileKey, slot, null) != null) pictures.remove(slot);
        continue;
      }
      final fileHash = sha256.convert(await file.readAsBytes()).toString();
      if (had?["file"] == fileHash) continue;
      // What goes out is the picture as the screen shows it, as a copy sends it
      final jpeg = await _channel.getShareWallpaper(file.path);
      if (jpeg == null || jpeg.isEmpty || jpeg.length > ShareBundle.maxPictureBytes) continue;
      final hash = await _channel.publishHouseholdPicture(profileKey, slot, jpeg);
      if (hash != null && hash.isNotEmpty) pictures[slot] = {"entry": hash, "file": fileHash};
    }
    mine["pictures"] = pictures;
  }
}
