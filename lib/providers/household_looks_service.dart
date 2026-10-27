import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/household_parent_pin.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/share/household_join.dart';
import 'package:flauncher/share/household_looks.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/share/share_wallpapers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps each profile's look (kids' included), layout and wallpaper pictures in step with the household's (docs/household-sync.md,
/// "Look and layout"). Every so often it asks the Java side what the household has; a profile whose look or layout
/// changed there gets it, fitted to the apps installed here (live when it is the profile on screen, else in its saved
/// layout), and a changed picture is written to the profile's folder. Then the profile on screen goes out: its look,
/// its layout with the household's apps that aren't installed here kept, and any picture it picked that changed.
///
/// What this TV last took or gave for each profile is remembered (by fingerprint), so a change goes out once, an entry
/// is put in place once, and taking the household's doesn't send it straight back. So is each item of the look and
/// layout (a setting, the rows, a row's apps, an app hidden or not) as this TV last had it, and when it changed here:
/// when the household's arrives, the newer change of each item wins (HouseholdLooks.mergeLook, mergeLayout), so two
/// TVs changing different things at once both keep theirs.
class HouseholdLooksService implements HouseholdJoinReviewer {
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

  /// The household's Parent PIN, kept in step on the same rounds.
  final HouseholdParentPin? _parentPin;

  /// The time in milliseconds, for when a change was made here.
  final int Function() _now;

  HouseholdLooksService(this._channel, this._prefs, this._backup, this._settings, this._wallpapers,
      {required Future<void> Function() onLiveChanged,
      required Future<void> Function(String profileKey) onPicturesCopied,
      HouseholdParentPin? parentPin,
      int Function()? now,
      Future<Directory> Function()? joinBackupFolder})
      : _onLiveChanged = onLiveChanged,
        _onPicturesCopied = onPicturesCopied,
        _parentPin = parentPin,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _joinBackupFolder = joinBackupFolder ??
            (() async => Directory("${(await getApplicationDocumentsDirectory()).path}/household_join_backup"));

  /// Where the copy of this TV's looks, layouts and pictures from before it joined is kept.
  final Future<Directory> Function() _joinBackupFolder;

  void start() {
    _timer ??= Timer.periodic(every, (_) => unawaited(tick()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// How often the copy from before joining is checked for its days, whether or not the Household page reads it.
  static const Duration joinBackupCheckEvery = Duration(days: 1);

  /// When the copy from before joining was last checked (null: not since Hearth started).
  int? _joinBackupCheckedAt;

  /// One round: take what changed in the household, then send what changed here. Does nothing outside a household.
  Future<void> tick() async {
    if (_running) return;
    _running = true;
    try {
      final looks = await _channel.getHouseholdLooks(_version);
      // Just joined: nothing is taken or given until someone has seen what it changes (joinPreview, finishJoin)
      if (looks != null && looks["review"] == true) {
        _version = 0;
        return;
      }
      await _parentPin?.tick();
      if (looks == null) {
        _version = 0;
        return;
      }
      final known = _known();
      final installed = {for (final app in await _backup.installedApps()) app.packageName};
      final profiles = looks["profiles"];
      if (profiles is Map) {
        _profiles = Map<String, dynamic>.from(profiles);
        for (final entry in _profiles.entries) {
          if (entry.value is Map) {
            await _take(entry.key, Map<String, dynamic>.from(entry.value as Map), known, installed);
          }
        }
        await _saveKnown(known);
      }
      _version = (looks["version"] as num?)?.toInt() ?? 0;
      await _giveAll(known, installed);
      await _saveKnown(known);
    } catch (err) {
      noteFailure('household_looks', err);
    } finally {
      _running = false;
      // Also after a round that ended early (outside a household, or while joining)
      await _expireJoinBackup();
    }
  }

  /// The copy from before joining goes after its days, whether or not the Household page reads it: at the first round,
  /// then daily (in a household or not). After the round, so it never holds one up.
  Future<void> _expireJoinBackup() async {
    final checkedAt = _joinBackupCheckedAt;
    if (checkedAt != null && _now() - checkedAt < joinBackupCheckEvery.inMilliseconds) return;
    _joinBackupCheckedAt = _now();
    try {
      await _joinBackupMeta();
    } catch (err) {
      noteFailure('household_looks', err);
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

  Future<void> _saveKnown(Map<String, dynamic> known) async {
    final text = jsonEncode(known);
    if (_prefs.getString(knownKey) != text) await _prefs.setString(knownKey, text);
  }

  Map<String, dynamic> _knownFor(Map<String, dynamic> known, String profileKey) {
    final entry = known[profileKey];
    final mine = entry is Map ? Map<String, dynamic>.from(entry) : <String, dynamic>{};
    known[profileKey] = mine;
    return mine;
  }

  /// A profile's look and layout as this TV has them, and the settings of it that stay this TV's own
  /// ([ShareBundle.notShared], and the calendars it hides by their id here: putting the household's in place would
  /// otherwise clear them).
  Future<({SharedLayout layout, Map<String, Object> own, List<String> ownCalendars})?> _local(String profileKey) async {
    final backup = _settings.layoutOwner == profileKey
        ? await _backup.buildBackupData(_settings, true)
        : await _backup.readProfileLayout(profileKey);
    if (backup == null) return null;
    final raw = backup["settings"] is Map ? backup["settings"] as Map : const {};
    return (
      layout: SharedLayout.fromBackup(backup, settingKeys: _settings.settingKeys, lenient: true),
      own: <String, Object>{
        for (final key in ShareBundle.notShared)
          if (raw[key] != null && !BackupService.isDeviceLevelKey(key)) key: raw[key] as Object,
      },
      ownCalendars: ShareBundle.thisTvsCalendars(raw[ShareBundle.hiddenCalendarsKey]),
    );
  }

  static Map<String, String> _strings(Object? value) =>
      value is Map ? {for (final e in value.entries) if (e.value is String) "${e.key}": e.value as String} : {};

  static Map<String, int> _ints(Object? value) =>
      value is Map ? {for (final e in value.entries) if (e.value is int) "${e.key}": e.value as int} : {};

  /// Notes what changed in the profile's look and layout here since last time, and when (HouseholdLooks.observe).
  void _observe(Map<String, dynamic> mine, SharedLayout local, Set<String> installed) {
    final now = _now();
    final lookSeen = _strings(mine["lookSeen"]);
    final lookAt = _ints(mine["lookAt"]);
    HouseholdLooks.observe(lookSeen, lookAt, HouseholdLooks.lookItems(local.settings), now);
    final layoutSeen = _strings(mine["layoutSeen"]);
    final layoutAt = _ints(mine["layoutAt"]);
    HouseholdLooks.observe(layoutSeen, layoutAt, HouseholdLooks.layoutItems(local, installed), now);
    mine["lookSeen"] = lookSeen;
    mine["lookAt"] = lookAt;
    mine["layoutSeen"] = layoutSeen;
    mine["layoutAt"] = layoutAt;
  }

  // ---- Taking the household's ----

  Future<void> _take(String profileKey, Map<String, dynamic> state, Map<String, dynamic> known,
      Set<String> installed) async {
    final mine = _knownFor(known, profileKey);
    final look = state["look"] as String?;
    final layout = state["layout"] as String?;
    final newLook = look != null && HouseholdLooks.fingerprint(look) != mine["look"];
    final newLayout = layout != null && HouseholdLooks.fingerprint(layout) != mine["layout"];
    if (newLook || newLayout) {
      final keys = _settings.settingKeys;
      final local = await _local(profileKey);
      // What changed here and hasn't gone out yet counts too, with when: item by item, the newer change wins
      if (local != null) _observe(mine, local.layout, installed);
      var settings = look == null ? null : HouseholdLooks.parseLook(look, keys);
      if (settings != null && local != null) {
        final merged = HouseholdLooks.mergeLook(
            settings, HouseholdLooks.lookStamps(look!), local.layout.settings, _ints(mine["lookAt"]));
        settings = merged.settings;
        mine["lookAt"] = merged.stamps;
      }
      var parts = layout == null ? null : HouseholdLooks.parseLayout(layout, keys);
      if (parts != null && local != null) {
        final merged = HouseholdLooks.mergeLayout(
            parts, HouseholdLooks.layoutStamps(layout!), local.layout, _ints(mine["layoutAt"]), installed);
        parts = merged.layout;
        mine["layoutAt"] = merged.stamps;
      }
      final composed = HouseholdLooks.compose(settings, parts, local?.layout);
      if (composed != null) {
        // The first time a profile takes the household's look here, everything is kept first, so it can be undone in
        // Backup & Restore
        if (mine["look"] == null && mine["layout"] == null && !_backedUp) {
          await _backup.backupBeforeCopy(_settings);
          _backedUp = true;
        }
        final live = _settings.layoutOwner == profileKey;
        final fitted = composed.forInstalled(await _backup.installedApps());
        // The profile's settings that are this TV's own stay as they are, the calendars it hides by their id here too
        final settings = <String, Object>{...composed.settings, ...?local?.own};
        final ownCalendars = local?.ownCalendars ?? const <String>[];
        if (ownCalendars.isNotEmpty) {
          settings[ShareBundle.hiddenCalendarsKey] = [
            ...ShareBundle.sharedCalendars(settings[ShareBundle.hiddenCalendarsKey]),
            ...ownCalendars,
          ];
        }
        fitted.backup["settings"] = settings;
        await _backup.applySharedLayout(profileKey, fitted.backup, _settings, live: live);
        if (live) await _onLiveChanged();
        if (look != null) mine["look"] = HouseholdLooks.fingerprint(look);
        if (layout != null) mine["layout"] = HouseholdLooks.fingerprint(layout);
        // What this TV has now, so the next look tells a change made here from what was just taken
        mine["lookSeen"] = {
          for (final e in HouseholdLooks.lookItems(composed.settings).entries) e.key: HouseholdLooks.remembered(e.value),
        };
        mine["layoutSeen"] = {
          for (final e in HouseholdLooks.layoutItems(composed, installed).entries)
            e.key: HouseholdLooks.remembered(e.value),
        };
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

  // ---- Giving this TV's ----

  /// The profile on screen goes out where it differs from the household's; so does any other profile of this TV that
  /// the household has no look or layout for yet (one set up only here, or on a TV that just joined). A profile the
  /// household doesn't know (one whose Google account Hearth hasn't seen yet) doesn't.
  Future<void> _giveAll(Map<String, dynamic> known, Set<String> installed) async {
    final live = _settings.layoutOwner;
    for (final entry in _profiles.entries) {
      final state = entry.value;
      if (state is! Map) continue;
      if (entry.key == live || (state["look"] == null && state["layout"] == null)) {
        await _give(entry.key, Map<String, dynamic>.from(state), known, installed);
      }
    }
  }

  Future<void> _give(String profileKey, Map<String, dynamic> state, Map<String, dynamic> known,
      Set<String> installed) async {
    final local = await _local(profileKey);
    if (local == null) return;
    final mine = _knownFor(known, profileKey);
    _observe(mine, local.layout, installed);
    final keys = _settings.settingKeys;
    final householdLookText = state["look"] as String?;
    final householdLayoutText = state["layout"] as String?;
    final householdLook = householdLookText == null ? null : HouseholdLooks.parseLook(householdLookText, keys);
    final householdLayout = householdLayoutText == null ? null : HouseholdLooks.parseLayout(householdLayoutText, keys);

    // Only a difference in the look or layout itself goes out, not one in the stamps alone: a TV from before stamps
    // gives its entries without them, and the two would otherwise trade them forever
    if (householdLook == null ||
        HouseholdLooks.lookJson(householdLook) != HouseholdLooks.lookJson(local.layout.settings)) {
      final look = HouseholdLooks.lookJson(local.layout.settings, _ints(mine["lookAt"])..removeWhere((_, at) => at == 0));
      if (await _channel.publishHouseholdLook(profileKey, "look", look)) mine["look"] = HouseholdLooks.fingerprint(look);
    }
    final given = HouseholdLooks.withMissingApps(local.layout, householdLayout, installed);
    if (householdLayout == null || HouseholdLooks.layoutJson(householdLayout) != HouseholdLooks.layoutJson(given)) {
      // The household's stamps for what this TV can't judge (the apps it lacks), this TV's for the rest
      final stamps = <String, int>{
        if (householdLayoutText != null) ...HouseholdLooks.layoutStamps(householdLayoutText),
        ..._ints(mine["layoutAt"]),
      }..removeWhere((_, at) => at == 0);
      final layout = HouseholdLooks.layoutJson(given, stamps);
      if (await _channel.publishHouseholdLook(profileKey, "layout", layout)) {
        mine["layout"] = HouseholdLooks.fingerprint(layout);
      }
    }
    await _givePictures(profileKey, mine);
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
      // What goes out is the picture as the screen shows it
      final jpeg = await _channel.getShareWallpaper(file.path);
      if (jpeg == null || jpeg.isEmpty || jpeg.length > ShareBundle.maxPictureBytes) continue;
      final hash = await _channel.publishHouseholdPicture(profileKey, slot, jpeg);
      if (hash != null && hash.isNotEmpty) pictures[slot] = {"entry": hash, "file": fileHash};
    }
    mine["pictures"] = pictures;
  }

  // ---- Before joining: what changes, and the copy to put back (docs/household-sync.md, "Before joining") ----

  @override
  Future<JoinPreview?> joinPreview() async {
    final java = await _channel.getHouseholdJoinPreview();
    final looks = await _channel.getHouseholdLooks(0);
    if (java == null || looks == null) return null;
    final states = looks["profiles"] is Map ? looks["profiles"] as Map : const {};
    final keys = _settings.settingKeys;
    final installed = {for (final app in await _backup.installedApps()) app.packageName};
    final profiles = <JoinChange>[];
    for (final raw in (java["profiles"] as List?) ?? const []) {
      if (raw is! Map || raw["key"] is! String) continue;
      final key = raw["key"] as String;
      final state = states[key] is Map ? states[key] as Map : const {};
      final local = await _local(key);
      final look = state["look"] is String ? HouseholdLooks.parseLook(state["look"] as String, keys) : null;
      final layout = state["layout"] is String ? HouseholdLooks.parseLayout(state["layout"] as String, keys) : null;
      profiles.add(JoinChange(
        key: key,
        name: (raw["name"] as String?) ?? "",
        kids: raw["kids"] == true,
        look: look != null && HouseholdLooks.lookDiffers(look, local?.layout.settings),
        layout: layout != null && HouseholdLooks.layoutDiffers(layout, local?.layout, installed),
        pictures: state["wallpapers"] is Map ? await _picturesChanged(key, state["wallpapers"] as Map) : 0,
        pairings: (raw["pairings"] as num?)?.toInt() ?? 0,
        pins: (raw["pins"] as num?)?.toInt() ?? 0,
      ));
    }
    // A Parent PIN differing from this TV's own is kept until it's entered here; only one where there was none changes
    final pin = await _channel.getHouseholdParentPin();
    return JoinPreview(
      profiles: profiles,
      parentPin: pin?["state"] == "live" && _settings.parentPinHash == null,
      tvPins: (java["tvPins"] as num?)?.toInt() ?? 0,
    );
  }

  /// How many of a profile's pictures the household's would replace or take away.
  Future<int> _picturesChanged(String profileKey, Map wallpapers) async {
    var changed = 0;
    for (final entry in wallpapers.entries) {
      if (!ShareWallpapers.fileNames.containsKey(entry.key)) continue;
      final here = await _wallpapers.file(profileKey, entry.key as String);
      final value = entry.value;
      if (value == null) {
        if (await here.exists()) changed++;
        continue;
      }
      final path = value is Map ? value["path"] as String? : null;
      if (path == null) continue;
      if (!await here.exists() ||
          sha256.convert(await here.readAsBytes()) != sha256.convert(await File(path).readAsBytes())) {
        changed++;
      }
    }
    return changed;
  }

  @override
  Future<bool> finishJoin(JoinPreview preview) async {
    try {
      await _saveJoinBackup([for (final p in preview.profiles) p.key]);
    } catch (err) {
      // Without the copy nothing is replaced: the TV stays as it is, still holding the household's settings
      noteFailure('household_looks', err);
      return false;
    }
    if (!await _channel.finishHouseholdJoin()) return false;
    _version = 0;
    unawaited(tick());
    return true;
  }

  Future<void> _saveJoinBackup(List<String> profileKeys) async {
    final folder = await _joinBackupFolder();
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final kept = <String, int>{};
    for (var i = 0; i < profileKeys.length; i++) {
      final key = profileKeys[i];
      final layout = _settings.layoutOwner == key
          ? await _backup.buildBackupData(_settings, true)
          : await _backup.readProfileLayout(key);
      if (layout != null) await File("${folder.path}/layout_$i.json").writeAsString(jsonEncode(layout), flush: true);
      for (final slot in ShareWallpapers.fileNames.keys) {
        final picture = await _wallpapers.file(key, slot);
        if (await picture.exists()) await picture.copy("${folder.path}/picture_${i}_$slot");
      }
      kept[key] = i;
    }
    // Written last: a copy without it is one that didn't finish, and isn't offered
    await File("${folder.path}/meta.json")
        .writeAsString(jsonEncode({"at": _now(), "profiles": kept}), flush: true);
  }

  Future<Map<String, dynamic>?> _joinBackupMeta() async {
    final folder = await _joinBackupFolder();
    final meta = File("${folder.path}/meta.json");
    if (!await meta.exists()) return null;
    try {
      final decoded = jsonDecode(await meta.readAsString());
      if (decoded is! Map || decoded["at"] is! int || decoded["profiles"] is! Map) return null;
      final at = decoded["at"] as int;
      if (_now() - at > HouseholdJoinReviewer.keptFor.inMilliseconds) {
        await folder.delete(recursive: true);
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<DateTime?> joinBackupAt() async {
    final meta = await _joinBackupMeta();
    return meta == null ? null : DateTime.fromMillisecondsSinceEpoch(meta["at"] as int);
  }

  @override
  Future<bool> restoreJoinBackup() async {
    // Not while a round is putting the household's in place
    while (_running) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _running = true;
    try {
      return await _restoreJoinBackup();
    } finally {
      _running = false;
    }
  }

  Future<bool> _restoreJoinBackup() async {
    final meta = await _joinBackupMeta();
    // No copy of the looks here (it didn't finish): the pairings and PINs can still come back
    if (meta == null) return _channel.restoreHouseholdJoinBackup();
    final folder = await _joinBackupFolder();
    final profiles = Map<String, dynamic>.from(meta["profiles"] as Map);
    for (final entry in profiles.entries) {
      final key = entry.key;
      final i = entry.value;
      final layout = File("${folder.path}/layout_$i.json");
      if (await layout.exists()) {
        final data = jsonDecode(await layout.readAsString());
        if (data is Map) {
          final live = _settings.layoutOwner == key;
          await _backup.applySharedLayout(key, Map<String, dynamic>.from(data), _settings, live: live);
          if (live) await _onLiveChanged();
        }
      }
      for (final slot in ShareWallpapers.fileNames.keys) {
        final picture = File("${folder.path}/picture_${i}_$slot");
        if (await picture.exists()) {
          await _wallpapers.write(key, {slot: await picture.readAsBytes()});
        } else {
          await _wallpapers.delete(key, slot);
        }
      }
      await _onPicturesCopied(key);
    }
    // The pairings and PINs (a copy whose days are over on the Java side is just gone: the rest still came back)
    await _channel.restoreHouseholdJoinBackup();
    await folder.delete(recursive: true);
    // What came back is the newest change of each item now, and goes out at once, the profiles not on screen too
    final known = _known();
    final installed = {for (final app in await _backup.installedApps()) app.packageName};
    for (final key in profiles.keys) {
      final state = _profiles[key];
      if (state is Map) await _give(key, Map<String, dynamic>.from(state), known, installed);
    }
    await _saveKnown(known);
    return true;
  }
}
