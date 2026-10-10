/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/kids_profiles.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'kids_profiles_page.dart';
import 'message_dialog.dart';
import 'profiles_settings_page.dart';
import 'settings_page.dart';
import 'updates_page.dart';

/// One kid, from Settings > Profiles > Kids' profiles: everything that's that child's own in one place, set by the
/// parent without switching to their profile (Settings is past the parent PIN to get here in a kids' profile). How
/// Hearth stands on the profile (needing a fix: back to the list's Fix), their YouTube time per day, and HearthTube:
/// getting it onto the TV and this profile, its version and updates, and its settings while this profile is on.
class KidProfilePage extends StatefulWidget {
  static const String routeName = "kid_profile";

  /// What [KidProfilePage] pops with when the parent asks to fix the profile.
  static const String fix = "fix";

  /// How long Android's installer may take before Hearth stops watching for HearthTube (the setup flow waits as long).
  static const Duration installWait = Duration(minutes: 3);

  final KidsProfilesState state;
  final KidProfile kid;

  const KidProfilePage({super.key, required this.state, required this.kid});

  @override
  State<KidProfilePage> createState() => _KidProfilePageState();
}

class _KidProfilePageState extends State<KidProfilePage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  late final CompanionUpdater? _updater = context.read<CompanionUpdater?>();
  late KidsProfilesState _state = widget.state;
  late KidProfile _kid = widget.kid;

  /// HearthTube on the TV (one copy serves every profile) and its newest release, once read.
  Map<dynamic, dynamic>? _tubeVersion;
  CompanionRelease? _tubeLatest;

  /// While HearthTube is being put on the TV and this profile: what's happening; and why it couldn't be.
  String? _tubeProgress;
  String? _tubeError;

  CompanionApp get _tube => companionApps.first;

  @override
  void initState() {
    super.initState();
    _readTube();
  }

  Future<void> _readTube() async {
    try {
      final version = await _channel.getPackageVersion(_tube.packageName);
      if (mounted) setState(() => _tubeVersion = version);
      if (version == null) return;
      final latest = await _updater?.latestRelease(_tube);
      if (mounted) setState(() => _tubeLatest = latest);
    } catch (_) {
      // Offline, or no Android side: the version alone says enough
    }
  }

  /// This kid as Android lists them now.
  Future<void> _refresh() async {
    try {
      final state = KidsProfilesState.fromMap(await _channel.getKidsProfilesState(checkProtection: true));
      final kid = state.kids.where((k) => k.userId == _kid.userId).firstOrNull;
      if (mounted && kid != null) {
        setState(() {
          _state = state;
          _kid = kid;
        });
      }
    } catch (_) {}
  }

  /// Puts HearthTube on this profile (over Hearth's own adb, as Fix does, for this kid only).
  Future<void> _addTube() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _tubeProgress = l.updatesInstalling;
      _tubeError = null;
    });
    try {
      await _channel.fixKidsProfiles(userId: _kid.userId).timeout(KidsProfilesPage.selfAdbLimit);
    } catch (_) {
      if (mounted) setState(() => _tubeError = "${l.kidsProfilesFailedBody} ${l.kidsProfilesFailedRetry}");
    }
    await _refresh();
    if (mounted) setState(() => _tubeProgress = null);
  }

  /// HearthTube isn't on the TV: installs it from its latest release with Android's installer (as Updates does, so
  /// Hearth keeps it up to date), then puts it on this profile.
  Future<void> _getTube() async {
    final l = AppLocalizations.of(context)!;
    final updater = _updater;
    if (updater == null) return;
    // Android asks for "Install unknown apps" first; the parent comes back and tries again
    if (!await _channel.checkInstallPermission()) {
      if (!mounted) return;
      await showMessageDialog(context, title: l.updatesInstallPermissionTitle, message: l.updatesInstallPermissionMessage);
      await _channel.requestInstallPermission();
      return;
    }
    setState(() {
      _tubeProgress = l.updatesChecking;
      _tubeError = null;
    });
    try {
      final release = await updater.latestRelease(_tube);
      if (release == null) throw Exception(l.updatesCheckFailed);
      final apk = await updater.download(_tube, release, onProgress: (fraction) {
        if (mounted) setState(() => _tubeProgress = l.updatesDownloadingPercent((fraction * 100).round()));
      });
      if (mounted) setState(() => _tubeProgress = l.updatesInstalling);
      if (!await _channel.installApk(apk.path)) throw Exception(l.updatesInstallerNotStarted);
      // A first install asks on Android's screen; nothing tells Hearth it's done, so watch for the app
      final until = DateTime.now().add(KidProfilePage.installWait);
      Map<dynamic, dynamic>? version;
      while (mounted && version == null && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 3));
        version = await _channel.getPackageVersion(_tube.packageName);
      }
      if (version == null) {
        if (mounted) setState(() => _tubeProgress = null);
        return;
      }
      await updater.setAutoUpdate(true);
      if (!mounted) return;
      setState(() => _tubeVersion = version);
      await _addTube();
    } catch (e) {
      if (mounted) {
        setState(() {
          _tubeProgress = null;
          _tubeError = e.toString().replaceFirst("Exception: ", "");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final small = textTheme.bodySmall?.copyWith(color: Colors.white54);
    final kid = _kid;
    final (:label, :status, :detail, :color) = KidsProfilesPage.describe(l, _state, kid);
    final ready = _state.statusOf(kid) == KidProfileStatus.ready;
    final busy = _tubeProgress != null;
    final tubeOnTv = _state.hearthTubeOnOwner || _tubeVersion != null;
    final version = _tubeVersion?["versionName"] as String?;
    final latest = _tubeLatest;
    final update = latest != null && _tubeVersion != null && latest.isNewerThan(_tubeVersion!);
    Widget? spinner(bool on) =>
        on ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null;

    return SettingsPage(
      title: label,
      children: [
        // How Hearth stands here; needing a fix goes back to the list's Fix
        FocusableSettingsTile(
          autofocus: !ready,
          leading: const Icon(Icons.child_care),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detail, style: textTheme.bodyMedium),
              if (!ready) Text(l.kidsProfilesFixBody, style: small),
            ],
          ),
          trailing: Text(ready ? status : l.kidsProfilesFix, style: textTheme.bodySmall?.copyWith(color: color)),
          onPressed: ready || busy ? null : () => Navigator.of(context).pop(KidProfilePage.fix),
        ),
        if (kid.profileKey != null) YouTubeLimitTile(profileKey: kid.profileKey, autofocus: ready),
        const Divider(),
        // HearthTube: onto the TV and this profile, its version and updates, and its settings for this profile
        if (!tubeOnTv)
          FocusableSettingsTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.kidProfileGetHearthTube, style: textTheme.bodyMedium),
                Text(_tubeProgress ?? _tubeError ?? l.kidProfileGetHearthTubeBody,
                    style: _tubeError != null && !busy ? small?.copyWith(color: Colors.redAccent) : small),
              ],
            ),
            trailing: spinner(busy) ?? const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: busy ? null : _getTube,
          )
        else
          FocusableSettingsTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(version != null ? "HearthTube $version" : "HearthTube", style: textTheme.bodyMedium),
                Text(
                  _tubeProgress ??
                      _tubeError ??
                      (!kid.hearthTube
                          ? l.kidsProfilesHearthTubeMissing
                          : update
                              ? l.updatesUpdateTo(latest.versionName)
                              : latest != null
                                  ? l.updatesUpToDate
                                  : l.kidsProfilesBothOn),
                  style: small,
                ),
              ],
            ),
            trailing: spinner(busy) ??
                (!kid.hearthTube
                    ? Text(l.kidsProfilesFix, style: textTheme.bodySmall?.copyWith(color: Colors.amber))
                    : update
                        ? const Icon(Icons.chevron_right, color: Colors.white54)
                        : null),
            onPressed: busy
                ? null
                : !kid.hearthTube
                    ? _addTube
                    // Updates are the TV's, not one profile's: the Updates page has them
                    : update
                        ? () async {
                            await Navigator.of(context).pushNamed(UpdatesPage.routeName);
                            _readTube();
                          }
                        : null,
          ),
        // Only the profile on now has a running copy to open, in its own user
        if (kid.running && kid.hearthTube)
          FocusableSettingsTile(
            leading: const Icon(Icons.tune),
            title: Text(l.kidProfileHearthTubeSettings, style: textTheme.bodyMedium),
            trailing: const Icon(Icons.open_in_new, color: Colors.white54),
            onPressed: () => _channel.openHearthTubeSettings().catchError((_) => false),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(l.kidProfileHint, style: small),
        ),
      ],
    );
  }
}
