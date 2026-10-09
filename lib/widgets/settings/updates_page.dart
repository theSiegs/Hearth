import 'package:flauncher/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_page.dart';
import 'update_dialog.dart';

enum _State { checking, notInstalled, upToDate, updateAvailable, downloading, installing, error }

/// Updates: Hearth's own, and installing and updating the companion apps from their GitHub releases.
class UpdatesPage extends StatefulWidget {
  static const String routeName = "companion_apps";

  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> with WidgetsBindingObserver {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  final Map<String, _State> _states = {};
  final Map<String, Map<dynamic, dynamic>?> _installed = {};
  final Map<String, CompanionRelease?> _releases = {};
  late final CompanionUpdater _updater = context.read<CompanionUpdater>();
  bool? _autoUpdate;
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};
  Timer? _installWatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final app in companionApps) {
      _check(app);
    }
    _updater.autoUpdateEnabled().then((on) {
      if (mounted) setState(() => _autoUpdate = on);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _installWatch?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final app in companionApps) {
        _refreshInstalled(app);
      }
      _resumeAfterPermission();
    }
  }

  /// The app whose install waits for "Install unknown apps" to be allowed.
  CompanionApp? _waitingForPermission;

  Future<void> _resumeAfterPermission() async {
    final app = _waitingForPermission;
    if (app == null) return;
    _waitingForPermission = null;
    if (await _channel.checkInstallPermission()) _install(app);
  }

  /// Explains the "Install unknown apps" screen before opening it; true when the user goes ahead.
  Future<bool> _askForInstallPermission() async {
    final localizations = AppLocalizations.of(context)!;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.updatesInstallPermissionTitle),
        content: SizedBox(
          width: 420,
          child: Text(localizations.updatesInstallPermissionMessage),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(localizations.notNow)),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(localizations.updatesOpenSettings),
          ),
        ],
      ),
    );
    return go == true;
  }

  void _set(CompanionApp app, _State state, {String? error}) {
    if (!mounted) return;
    setState(() {
      _states[app.packageName] = state;
      if (error != null) _errors[app.packageName] = error;
    });
  }

  Future<void> _check(CompanionApp app) async {
    _set(app, _State.checking);
    try {
      _installed[app.packageName] = await _channel.getPackageVersion(app.packageName);
      _releases[app.packageName] = await _updater.latestRelease(app);
      _settle(app);
    } catch (e) {
      if (!mounted) return;
      _set(app, _State.error, error: AppLocalizations.of(context)!.updatesCheckFailed);
    }
  }

  /// Picks the state from the installed version and the latest release.
  void _settle(CompanionApp app) {
    final installed = _installed[app.packageName];
    final release = _releases[app.packageName];
    if (installed == null) {
      _set(app, _State.notInstalled);
    } else if (release == null) {
      _set(app, _State.upToDate);
    } else {
      _set(app, release.isNewerThan(installed) ? _State.updateAvailable : _State.upToDate);
    }
  }

  Future<void> _refreshInstalled(CompanionApp app) async {
    final before = _installed[app.packageName]?['versionCode'];
    final now = await _channel.getPackageVersion(app.packageName);
    _installed[app.packageName] = now;
    final state = _states[app.packageName];
    if (state == _State.installing && now?['versionCode'] == before) return;
    if (state != _State.downloading && state != _State.checking) _settle(app);
  }

  Future<void> _install(CompanionApp app) async {
    final release = _releases[app.packageName];
    if (release == null) return;
    if (!await _channel.checkInstallPermission()) {
      if (!mounted || !await _askForInstallPermission()) return;
      _waitingForPermission = app;
      await _channel.requestInstallPermission();
      return;
    }
    _set(app, _State.downloading);
    try {
      final apk = await _updater.download(app, release, onProgress: (fraction) {
        if (mounted) setState(() => _progress[app.packageName] = fraction);
      });

      _set(app, _State.installing);
      if (!await _channel.installApk(apk.path)) {
        if (!mounted) return;
        throw Exception(AppLocalizations.of(context)!.updatesInstallerNotStarted);
      }
      // Updates may install without a prompt, so nothing brings Hearth back to the front: watch for the new version.
      _installWatch?.cancel();
      var ticks = 0;
      _installWatch = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (++ticks > 60 || _states[app.packageName] != _State.installing) {
          timer.cancel();
          if (_states[app.packageName] == _State.installing) _settle(app);
          return;
        }
        await _refreshInstalled(app);
      });
    } catch (e) {
      _set(app, _State.error, error: e.toString().replaceFirst("Exception: ", ""));
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return SettingsPage(
      title: localizations.updatesTitle,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.local_fire_department_outlined),
          title: Text("Hearth", style: textTheme.bodyMedium),
          trailing:
              Text(localizations.updatesCheckForUpdates, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
          onPressed: () => showDialog(context: context, builder: (_) => const UpdateDialog()),
        ),
        // Hearth's and the companion apps' updates. Each check reads it (Hearth's dialog checks every time it
        // opens); the companions are checked again now. Turning it off never offers an older version.
        RoundedSwitchListTile(
          value: context.select<SettingsService, bool>((s) => s.updatesIncludePrereleases),
          onChanged: (on) async {
            await context.read<SettingsService>().setUpdatesIncludePrereleases(on);
            for (final app in companionApps) {
              _check(app);
            }
          },
          title: Text(localizations.updatesIncludePrereleases, style: textTheme.bodyMedium),
          subtitle: Text(localizations.updatesIncludePrereleasesDescription),
          secondary: const Icon(Icons.science_outlined),
        ),
        for (final app in companionApps) _tile(context, app),
        RoundedSwitchListTile(
          value: _autoUpdate ?? false,
          onChanged: _autoUpdate == null
              ? null
              : (on) async {
                  setState(() => _autoUpdate = on);
                  await _updater.setAutoUpdate(on);
                },
          title: Text(localizations.updatesAutoUpdate, style: textTheme.bodyMedium),
          subtitle: Text(localizations.updatesAutoUpdateDescription),
          secondary: const Icon(Icons.system_update_outlined),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            localizations.updatesFooter,
            style: textTheme.bodySmall?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, CompanionApp app) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final state = _states[app.packageName] ?? _State.checking;
    final installed = _installed[app.packageName];
    final release = _releases[app.packageName];
    final (String status, Color color, VoidCallback? action) = switch (state) {
      _State.checking => (localizations.updatesChecking, Colors.white54, null),
      _State.notInstalled => (localizations.updatesInstall, Colors.orange, () => _install(app)),
      _State.updateAvailable => (
          localizations.updatesUpdateTo(release?.versionName ?? ''),
          Colors.orange,
          () => _install(app)
        ),
      _State.upToDate => (localizations.updatesUpToDate, Colors.green, () => _check(app)),
      _State.downloading => (
          localizations.updatesDownloadingPercent(((_progress[app.packageName] ?? 0) * 100).round()),
          Colors.white54,
          null
        ),
      _State.installing => (localizations.updatesInstalling, Colors.white54, null),
      _State.error => (_errors[app.packageName] ?? localizations.updatesError, Colors.redAccent, () => _check(app)),
    };
    final description = app.localizedDescription(localizations);
    return FocusableSettingsTile(
      leading: const Icon(Icons.extension_outlined),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.name, style: textTheme.bodyMedium),
          Text(
            installed != null
                ? localizations.updatesDescriptionWithVersion(description, '${installed['versionName']}')
                : description,
            style: textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
        ],
      ),
      trailing: Text(status, style: textTheme.bodySmall?.copyWith(color: color)),
      onPressed: action,
    );
  }
}
