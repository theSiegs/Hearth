import 'dart:convert';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/share/share_bundle.dart';

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

  const ShareApplyReport(this.profiles, this.backupName);

  int get copied => profiles.where((p) => p.layout || p.pairingsApplied > 0).length;
  int get missingApps => profiles.fold(0, (sum, p) => sum + p.missingApps.length);
  int get pairingsApplied => profiles.fold(0, (sum, p) => sum + p.pairingsApplied);
  int get pairingsKept => profiles.fold(0, (sum, p) => sum + p.pairingsKept);

  /// What goes back to the sending TV: counts only, no names.
  String toReportJson() => jsonEncode({
        "copied": copied,
        "missingApps": missingApps,
        "pairingsApplied": pairingsApplied,
        "pairingsKept": pairingsKept,
      });
}

class ShareProfileReport {
  final String name;
  final bool layout;
  final List<String> missingApps;
  final int pairingsApplied;
  final int pairingsKept;

  const ShareProfileReport({
    required this.name,
    required this.layout,
    required this.missingApps,
    required this.pairingsApplied,
    required this.pairingsKept,
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

  ShareApplier(this._backup, this._settings, this._channel, this._onLiveChanged);

  /// Applies each profile of [bundle] that has a target in [targets] (source profile id to this TV's profile key).
  /// [layouts] and [pairings] choose what is taken. A backup is made first, to undo it in Backup & Restore.
  Future<ShareApplyReport> apply(
    ShareBundle bundle,
    Map<String, LocalProfile> targets, {
    bool layouts = true,
    bool pairings = true,
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
      reports.add(ShareProfileReport(
        name: target.name,
        layout: layoutDone,
        missingApps: missing,
        pairingsApplied: applied,
        pairingsKept: kept,
      ));
    }
    if (liveChanged) await _onLiveChanged();
    return ShareApplyReport(reports, backupName);
  }
}
