import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'focusable_settings_tile.dart';

/// An app made to go with Hearth, installed and updated from its GitHub releases.
class CompanionApp {
  final String name;
  final String packageName;
  final String description;
  final String repo;

  /// Release asset listing versions as {"<versionName>": {"versionCode": n}, ...}; without one, the release
  /// name or tag is compared with the installed version name.
  final String? versionManifest;

  const CompanionApp({
    required this.name,
    required this.packageName,
    required this.description,
    required this.repo,
    this.versionManifest,
  });
}

const List<CompanionApp> companionApps = [
  CompanionApp(
    name: "HearthTube",
    packageName: "com.thesiegs.hearthtube",
    description: "YouTube for Hearth; follows your Hearth profile",
    repo: "theSiegs/HearthTube",
    versionManifest: "hearthtube.json",
  ),
];

/// The newest version in a version manifest: (versionName, versionCode), or null if it lists none.
(String, int)? newestInManifest(Map<String, dynamic> manifest) {
  (String, int)? newest;
  manifest.forEach((name, entry) {
    if (entry is Map && entry['versionCode'] is int) {
      final code = entry['versionCode'] as int;
      if (newest == null || code > newest!.$2) newest = (name, code);
    }
  });
  return newest;
}

class _Release {
  final String versionName;
  final int? versionCode;
  final String apkUrl;
  final int apkSize;

  _Release(this.versionName, this.versionCode, this.apkUrl, this.apkSize);
}

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
  final Map<String, _Release?> _releases = {};
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
    }
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
      _releases[app.packageName] = await _latestRelease(app);
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
      final installedCode = installed['versionCode'] as int? ?? 0;
      final newer = release.versionCode != null
          ? release.versionCode! > installedCode
          : compareVersions(release.versionName, installed['versionName'] as String? ?? "") > 0;
      _set(app, newer ? _State.updateAvailable : _State.upToDate);
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

  Future<_Release?> _latestRelease(CompanionApp app) async {
    final releases = await _getJson("https://api.github.com/repos/${app.repo}/releases?per_page=10") as List<dynamic>;
    final abis = await _channel.getSupportedAbis();
    for (final release in releases.whereType<Map<String, dynamic>>()) {
      if (release['draft'] == true || release['prerelease'] == true) continue;
      final assets = (release['assets'] as List<dynamic>?) ?? [];
      final apk = pickApkAsset(assets, abis);
      if (apk == null) continue;
      String versionName = (release['name'] as String?)?.replaceFirst(RegExp(r"^\D+"), "") ?? "";
      if (versionName.isEmpty) versionName = release['tag_name'] as String? ?? "";
      int? versionCode;
      final manifestAsset = assets
          .whereType<Map<String, dynamic>>()
          .where((a) => a['name'] == app.versionManifest)
          .firstOrNull;
      if (manifestAsset != null) {
        final manifest = await _getJson(manifestAsset['browser_download_url'] as String);
        final newest = manifest is Map<String, dynamic> ? newestInManifest(manifest) : null;
        if (newest != null) (versionName, versionCode) = newest;
      }
      return _Release(versionName, versionCode, apk['browser_download_url'] as String, apk['size'] as int? ?? 0);
    }
    return null;
  }

  Future<dynamic> _getJson(String url) async {
    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
    request.headers.set(HttpHeaders.userAgentHeader, "Hearth-CompanionApps");
    final response = await request.close();
    if (response.statusCode != 200) throw HttpException("HTTP ${response.statusCode}", uri: Uri.parse(url));
    return jsonDecode(await response.transform(utf8.decoder).join());
  }

  Future<void> _install(CompanionApp app) async {
    final release = _releases[app.packageName];
    if (release == null) return;
    if (!await _channel.checkInstallPermission()) {
      await _channel.requestInstallPermission();
      return;
    }
    _set(app, _State.downloading);
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception("No storage for the download");
      final updates = Directory("${dir.path}/updates");
      await updates.create(recursive: true);
      final apk = File("${updates.path}/${app.packageName}.apk");
      final request = await HttpClient().getUrl(Uri.parse(release.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, "Hearth-CompanionApps");
      final response = await request.close();
      if (response.statusCode != 200) throw Exception("Download failed (${response.statusCode})");
      final total = release.apkSize > 0 ? release.apkSize : response.contentLength;
      final sink = apk.openWrite();
      var received = 0;
      await response.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) setState(() => _progress[app.packageName] = received / total);
      }).asFuture();
      await sink.close();

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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Installed from each app's GitHub releases. After Hearth installs an app once, "
                    "its updates usually install without asking.",
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
