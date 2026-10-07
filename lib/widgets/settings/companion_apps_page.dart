import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flutter/material.dart';

import 'focusable_settings_tile.dart';

export 'package:flauncher/providers/companion_updater.dart' show CompanionApp, companionApps, newestInManifest;

enum _State { checking, notInstalled, upToDate, updateAvailable, downloading, installing, error }

class CompanionAppsPage extends StatefulWidget {
  static const String routeName = "companion_apps";

  const CompanionAppsPage({super.key});

  @override
  State<CompanionAppsPage> createState() => _CompanionAppsPageState();
}

class _CompanionAppsPageState extends State<CompanionAppsPage> with WidgetsBindingObserver {
  final FLauncherChannel _channel = FLauncherChannel();
  final Map<String, _State> _states = {};
  final Map<String, Map<dynamic, dynamic>?> _installed = {};
  final Map<String, CompanionRelease?> _releases = {};
  late final CompanionUpdater _updater = CompanionUpdater(_channel);
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
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Allow Hearth to install apps"),
        content: const SizedBox(
          width: 420,
          child: Text("On the next screen, find Hearth and turn it on, then press Back. "
              "The install continues when you're back here."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Not now")),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Open Settings"),
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
      _set(app, _State.error, error: "Couldn't check for updates");
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
      if (!await _channel.installApk(apk.path)) throw Exception("The installer didn't start");
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
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text("Companion apps", style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final (index, app) in companionApps.indexed) _tile(context, app, index == 0),
                FocusableSettingsTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Update automatically", style: textTheme.bodyMedium),
                      Text(
                        "Hearth checks daily and installs updates to apps it installed, when they're not in use",
                        style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                    ],
                  ),
                  trailing: Switch(value: _autoUpdate ?? false, onChanged: null),
                  onPressed: _autoUpdate == null
                      ? null
                      : () async {
                          final on = !_autoUpdate!;
                          setState(() => _autoUpdate = on);
                          await _updater.setAutoUpdate(on);
                        },
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Installed from each app's GitHub releases. After Hearth installs or updates an app once, "
                    "its updates install without asking, and the app leaves updating to Hearth.",
                    style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, CompanionApp app, bool autofocus) {
    final textTheme = Theme.of(context).textTheme;
    final state = _states[app.packageName] ?? _State.checking;
    final installed = _installed[app.packageName];
    final release = _releases[app.packageName];
    final (String status, Color color, VoidCallback? action) = switch (state) {
      _State.checking => ("Checking…", Colors.white54, null),
      _State.notInstalled => ("Install", Colors.orange, () => _install(app)),
      _State.updateAvailable => ("Update to ${release?.versionName ?? ''}", Colors.orange, () => _install(app)),
      _State.upToDate => ("Up to date", Colors.green, () => _check(app)),
      _State.downloading => ("Downloading ${((_progress[app.packageName] ?? 0) * 100).round()}%", Colors.white54, null),
      _State.installing => ("Installing…", Colors.white54, null),
      _State.error => (_errors[app.packageName] ?? "Error", Colors.redAccent, () => _check(app)),
    };
    return FocusableSettingsTile(
      autofocus: autofocus,
      leading: const Icon(Icons.extension_outlined),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.name, style: textTheme.bodyMedium),
          Text(
            installed != null ? "${app.description} · ${installed['versionName']}" : app.description,
            style: textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
        ],
      ),
      trailing: Text(status, style: textTheme.bodySmall?.copyWith(color: color)),
      onPressed: action,
    );
  }
}
