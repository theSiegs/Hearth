import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:path_provider/path_provider.dart';
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

/// Finds, downloads and installs companion app releases, for the Companion apps page and on its own: Hearth is the
/// TV's one updater for its companions. In the background it checks at start and then daily, and installs only where
/// Android lets Hearth update without asking (it's the app's installer of record) and while the app isn't in front.
class CompanionUpdater {
  /// SharedPreferences key: automatic updates on/off; unset = on exactly when Hearth installed HearthTube.
  static const String autoUpdateKey = "companion_auto_update";
  static const String _lastCheckKey = "companion_last_auto_check";
  static const Duration _checkEvery = Duration(hours: 24);

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
      final manifestAsset =
          assets.whereType<Map<String, dynamic>>().where((a) => a['name'] == app.versionManifest).firstOrNull;
      if (manifestAsset != null) {
        final manifest = await _getJson(manifestAsset['browser_download_url'] as String);
        final newest = manifest is Map<String, dynamic> ? newestInManifest(manifest) : null;
        if (newest != null) (versionName, versionCode) = newest;
      }
      return CompanionRelease(versionName, versionCode, apk['browser_download_url'] as String, apk['size'] as int? ?? 0);
    }
    return null;
  }

  /// Downloads the release's APK, reporting progress (0–1) when the size is known.
  Future<File> download(CompanionApp app, CompanionRelease release, {void Function(double)? onProgress}) async {
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
      if (total > 0) onProgress?.call(received / total);
    }).asFuture();
    await sink.close();
    return apk;
  }

  Future<dynamic> _getJson(String url) async {
    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
    request.headers.set(HttpHeaders.userAgentHeader, "Hearth-CompanionApps");
    final response = await request.close();
    if (response.statusCode != 200) throw HttpException("HTTP ${response.statusCode}", uri: Uri.parse(url));
    return jsonDecode(await response.transform(utf8.decoder).join());
  }
}
