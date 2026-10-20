import 'dart:convert';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/share/share_wallpapers.dart';

/// A profile this TV has, as a copy can land on it.
class LocalProfile {
  final String key;
  final String name;
  final bool kids;

  const LocalProfile({required this.key, required this.name, required this.kids});

  static LocalProfile fromChannel(Map<dynamic, dynamic> map) => LocalProfile(
        key: map["key"] as String,
        name: (map["name"] as String?) ?? "",
        kids: map["kids"] == true,
      );
}

/// The profile of this TV a copied profile goes to by default: the one with the same name and the same kind (a kids
/// profile never lands on a grown-up's or the other way round), or none. A parent can pick another before copying.
LocalProfile? defaultTarget(ShareProfile source, List<LocalProfile> locals) {
  String norm(String name) => name.trim().toLowerCase();
  for (final local in locals) {
    if (local.kids == source.kids && norm(local.name) == norm(source.name)) return local;
  }
  return null;
}

/// What a copy did on this TV, for the screen and for the sender's.
class ShareApplyReport {
  /// Per profile: its name here, whether its layout and look went in, the apps this TV doesn't have, and how many of
  /// its pairing choices went in or were kept as they were.
  final List<ShareProfileReport> profiles;

  /// The backup taken first (its name, to find it in Backup & Restore).
  final String backupName;

  /// Whether the sender's parent PIN became this TV's.
  final bool parentPin;

  /// The streaming PINs and Home Assistant settings, once they were saved (they are the Java side's): null before.
  final ShareSecretsReport? secrets;

  const ShareApplyReport(this.profiles, this.backupName, {this.parentPin = false, this.secrets});

  ShareApplyReport withSecrets(ShareSecretsReport report) =>
      ShareApplyReport(profiles, backupName, parentPin: parentPin, secrets: report);

  int get copied =>
      profiles.where((p) => p.layout || p.pairingsApplied > 0 || p.pictures > 0).length;
  int get pictures => profiles.fold(0, (sum, p) => sum + p.pictures);
  int get missingApps => profiles.fold(0, (sum, p) => sum + p.missingApps.length);
  int get pairingsApplied => profiles.fold(0, (sum, p) => sum + p.pairingsApplied);
  int get pairingsKept => profiles.fold(0, (sum, p) => sum + p.pairingsKept);

  /// What goes back to the sending TV: counts only, no names.
  String toReportJson() => jsonEncode({
        "copied": copied,
        "missingApps": missingApps,
        "pairingsApplied": pairingsApplied,
        "pairingsKept": pairingsKept,
        "pictures": pictures,
        "parentPin": parentPin,
        if (secrets != null) ...secrets!.toJson(),
      });
}

/// What saving the PINs and the Home Assistant settings that came did (counts, and whether Home Assistant went in).
class ShareSecretsReport {
  final int pinsAdded;
  final int pinsKept;
  final int pinsSkipped;

  /// Whether Home Assistant's address and a token made for this TV were saved; null when they weren't asked for.
  final bool? haSet;

  const ShareSecretsReport({this.pinsAdded = 0, this.pinsKept = 0, this.pinsSkipped = 0, this.haSet});

  static ShareSecretsReport fromChannel(Map<dynamic, dynamic> result) {
    final pins = result["pins"] is Map ? result["pins"] as Map : const {};
    int count(String key) => (pins[key] as num?)?.toInt() ?? 0;
    return ShareSecretsReport(
      pinsAdded: count("added"),
      pinsKept: count("kept"),
      pinsSkipped: count("skipped"),
      haSet: result["ha"] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        "pinsAdded": pinsAdded,
        "pinsKept": pinsKept,
        "pinsSkipped": pinsSkipped,
        if (haSet != null) "haSet": haSet,
      };
}

class ShareProfileReport {
  final String name;
  final bool layout;
  final List<String> missingApps;
  final int pairingsApplied;
  final int pairingsKept;

  /// How many wallpaper pictures were put in.
  final int pictures;

  const ShareProfileReport({
    required this.name,
    required this.layout,
    required this.missingApps,
    required this.pairingsApplied,
    required this.pairingsKept,
    this.pictures = 0,
  });
}

/// Puts a bundle from another TV in place on this one. Everything the bundle holds was checked when it was read
/// ([ShareBundle.parse]); what is done here is fitting it to this TV: only the apps installed here, this TV's own names
/// and versions, and a profile's pairing where it has none of its own.
class ShareApplier {
  final BackupService _backup;
  final SettingsService _settings;
  final FLauncherChannel _channel;

  /// Called after the live profile's layout was replaced, so the home catches up with it.
  final Future<void> Function() _onLiveChanged;

  /// Where wallpaper pictures are written, and what's told when a profile's were (null: pictures aren't taken).
  final ShareWallpapers? _pictures;
  final Future<void> Function(String profileKey)? _onPicturesCopied;

  ShareApplier(this._backup, this._settings, this._channel, this._onLiveChanged,
      {ShareWallpapers? pictures, Future<void> Function(String profileKey)? onPicturesCopied})
      : _pictures = pictures,
        _onPicturesCopied = onPicturesCopied;

  /// Applies each profile of [bundle] that has a target in [targets] (source profile id to this TV's profile key).
  /// [layouts] and [pairings] choose what is taken. A backup is made first, to undo it in Backup & Restore.
  Future<ShareApplyReport> apply(
    ShareBundle bundle,
    Map<String, LocalProfile> targets, {
    bool layouts = true,
    bool pairings = true,
    bool pictures = true,
    bool parentPin = false,
  }) async {
    // A copy that can't keep a backup first doesn't go ahead: the layout it replaces would be gone for good
    final backupName = (await _backup.backupBeforeCopy(_settings)).uri.pathSegments.last;
    final installed = await _backup.installedApps();
    final live = _settings.layoutOwner;
    final reports = <ShareProfileReport>[];
    var liveChanged = false;
    for (final source in bundle.profiles) {
      final target = targets[source.id];
      if (target == null || target.kids != source.kids) continue;
      var layoutDone = false;
      var missing = const <String>[];
      final layout = bundle.layouts[source.id];
      if (layouts && layout != null) {
        final fitted = layout.forInstalled(installed);
        missing = fitted.missing;
        final isLive = live == target.key;
        await _backup.applySharedLayout(target.key, fitted.backup, _settings, live: isLive);
        layoutDone = true;
        liveChanged = liveChanged || isLive;
      }
      var applied = 0;
      var kept = 0;
      final choices = bundle.pairings[source.id];
      if (pairings && choices != null && choices.isNotEmpty) {
        final result = await _channel.applySharePairings(target.key, [for (final c in choices) c.toJson()]);
        applied = (result["applied"] as num?)?.toInt() ?? 0;
        kept = (result["kept"] as num?)?.toInt() ?? 0;
      }
      var written = 0;
      final copiedPictures = bundle.wallpapers[source.id];
      if (pictures && _pictures != null && copiedPictures != null && copiedPictures.isNotEmpty) {
        written = await _pictures.write(target.key, copiedPictures);
        if (written > 0) await _onPicturesCopied?.call(target.key);
      }
      reports.add(ShareProfileReport(
        name: target.name,
        layout: layoutDone,
        missingApps: missing,
        pairingsApplied: applied,
        pairingsKept: kept,
        pictures: written,
      ));
    }
    if (liveChanged) await _onLiveChanged();
    var pinTaken = false;
    final hash = bundle.parentPinHash;
    if (parentPin && hash != null) {
      await _settings.setParentPinHash(hash);
      pinTaken = true;
    }
    return ShareApplyReport(reports, backupName, parentPin: pinTaken);
  }
}
