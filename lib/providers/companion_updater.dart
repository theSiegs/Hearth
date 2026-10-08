import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/github_releases.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CompanionRelease {
  final String versionName;
  final int? versionCode;
  final String apkUrl;
  final int apkSize;

  CompanionRelease(this.versionName, this.versionCode, this.apkUrl, this.apkSize);

  /// Newer than the installed version ({versionName, versionCode} from getPackageVersion).
  bool isNewerThan(Map<dynamic, dynamic> installed) {
    final installedCode = installed['versionCode'] as int? ?? 0;
    return versionCode != null
        ? versionCode! > installedCode
        : compareVersions(versionName, installed['versionName'] as String? ?? "") > 0;
  }
}

/// Finds, downloads and installs companion app releases, for the Updates page and on its own: Hearth is the
/// TV's one updater for its companions. In the background it checks at start and then daily, and installs only where
/// Android lets Hearth update without asking (it's the app's installer of record) and while the app isn't in front.
class CompanionUpdater {
  /// SharedPreferences key: automatic updates on/off; unset = on exactly when Hearth installed HearthTube.
  static const String autoUpdateKey = "companion_auto_update";
  static const String _lastCheckKey = "companion_last_auto_check";
  static const Duration _checkEvery = Duration(hours: 24);
  static const String _userAgent = "Hearth-CompanionApps";

  final FLauncherChannel _channel;
  Timer? _timer;

  CompanionUpdater(this._channel);

  /// Starts the background checks (first a couple of minutes after Hearth starts, so it never slows the start).
  void start() {
    _timer?.cancel();
    _timer = Timer(const Duration(minutes: 2), () {
      _maybeCheck();
      _timer = Timer.periodic(const Duration(hours: 1), (_) => _maybeCheck());
    });
  }

  void dispose() => _timer?.cancel();

  /// Whether automatic updates are on: the saved choice, or by default whether Hearth installed HearthTube.
  Future<bool> autoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(autoUpdateKey);
    return saved ?? await _channel.isInstalledByHearth(companionApps.first.packageName);
  }

  Future<void> setAutoUpdate(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoUpdateKey, enabled);
    await _channel.companionSettingsChanged();
  }

  Future<void> _maybeCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < _checkEvery.inMilliseconds) return;
      if (!await autoUpdateEnabled()) return;
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      for (final app in companionApps) {
        await _autoUpdate(app);
      }
    } catch (e) {
      log("Companion update check failed", name: "CompanionUpdater", error: e);
    }
  }

  Future<void> _autoUpdate(CompanionApp app) async {
    final installed = await _channel.getPackageVersion(app.packageName);
    // Not installed (installing is the user's choice), or installed some other way, where Android would ask
    if (installed == null || !await _channel.isInstalledByHearth(app.packageName)) return;
    final release = await latestRelease(app);
    if (release == null || !release.isNewerThan(installed)) return;
    if (await _channel.getForegroundPackage() == app.packageName) return; // next time, not mid-video
    if (!await _channel.checkInstallPermission()) return;
    log("Updating ${app.name} to ${release.versionName}", name: "CompanionUpdater");
    final apk = await download(app, release);
    await _channel.installApk(apk.path);
  }

  /// The newest non-draft, non-prerelease release with an APK for this TV, or null.
  Future<CompanionRelease?> latestRelease(CompanionApp app) async {
    final releases = GitHubReleases(app.repo, userAgent: _userAgent);
    final release = await releases.latestWithApk(await _channel.getSupportedAbis(), perPage: 10);
    if (release == null) return null;
    String versionName = release.name.replaceFirst(RegExp(r"^\D+"), "");
    if (versionName.isEmpty) versionName = release.tagName;
    int? versionCode;
    final manifestAsset = release.assets.where((a) => a['name'] == app.versionManifest).firstOrNull;
    if (manifestAsset != null) {
      final manifest = await releases.getJson(Uri.parse(manifestAsset['browser_download_url'] as String));
      final newest = manifest is Map<String, dynamic> ? newestInManifest(manifest) : null;
      if (newest != null) (versionName, versionCode) = newest;
    }
    return CompanionRelease(versionName, versionCode, release.apkUrl, release.apkSize);
  }

  /// Downloads the release's APK, reporting progress (0–1) when the size is known.
  Future<File> download(CompanionApp app, CompanionRelease release, {void Function(double)? onProgress}) async {
    final apk = await downloadedApkFile("${app.packageName}.apk");
    await GitHubReleases(app.repo, userAgent: _userAgent)
        .download(release.apkUrl, apk, size: release.apkSize, onProgress: onProgress);
    return apk;
  }
}
