/*
 * LTvLauncher
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
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flauncher/flauncher_channel.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, readyToInstall, error }

class UpdateInfo {
  final String tagName;
  final String changelog;
  final String downloadUrl;
  final int assetSizeBytes;

  UpdateInfo({
    required this.tagName,
    required this.changelog,
    required this.downloadUrl,
    required this.assetSizeBytes,
  });
}

const _abiPattern = r"(arm64-v8a|armeabi-v7a|armeabi|x86_64|x86)";

/// Compares dotted versions numerically ("2026.10.05" > "2026.10.03+8112"); a leading "v" and any
/// non-digits in a part are ignored, and missing parts count as 0.
int compareVersions(String left, String right) {
  List<int> parts(String version) {
    var v = version.trim();
    if (v.startsWith("v") || v.startsWith("V")) v = v.substring(1);
    return v.split(RegExp(r"[.+]")).map((p) => int.tryParse(p.replaceAll(RegExp(r"[^0-9]"), "")) ?? 0).toList();
  }

  final l = parts(left), r = parts(right);
  for (var i = 0; i < (l.length > r.length ? l.length : r.length); i++) {
    final a = i < l.length ? l[i] : 0, b = i < r.length ? r[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

/// The ABI token may sit anywhere between separators: "LTvLauncher-armeabi-v7a-release.apk", "app-arm64-v8a.apk".
/// Picks the release APK for this device: one built for its ABIs (in preference order), else a universal APK.
/// Never returns an APK built for another ABI — it would fail to install (e.g. arm64 on a 32-bit stick).
Map<String, dynamic>? pickApkAsset(List<dynamic> assets, List<String> deviceAbis) {
  final apks = assets
      .whereType<Map<String, dynamic>>()
      .where((a) => (a['name'] as String? ?? "").toLowerCase().endsWith(".apk") && a['browser_download_url'] is String)
      .toList();
  String? abiOf(Map<String, dynamic> asset) =>
      RegExp(r"(?:^|[-_.])" "$_abiPattern" r"(?=[-_.])", caseSensitive: false).firstMatch(asset['name'] as String)?.group(1)?.toLowerCase();

  for (final abi in deviceAbis) {
    for (final apk in apks) {
      if (abiOf(apk) == abi.toLowerCase()) return apk;
    }
  }
  for (final apk in apks) {
    if (abiOf(apk) == null) return apk;
  }
  return null;
}

/// Checks GitHub Releases for newer builds of this launcher and installs
/// them via the system package installer. Only talks to:
///  - api.github.com (release metadata)
///  - the GitHub-hosted asset download URL returned by that API
/// No analytics, no ads, no third-party endpoints.
class UpdateService extends ChangeNotifier {
  static const String _repoOwner = "theSiegs";
  static const String _repoName = "Hearth";
  // The full list, not /latest: drafts and pre-releases are skipped here, and the newest stable release with an
  // APK for this device wins.
  static const String _releasesUrl = "https://api.github.com/repos/$_repoOwner/$_repoName/releases?per_page=20";

  final FLauncherChannel _channel;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _updateInfo;
  double _downloadProgress = 0;
  String? _errorMessage;
  String? _downloadedApkPath;
  String _currentVersion = "";

  UpdateService(this._channel) {
    _loadCurrentVersion();
  }

  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  String get currentVersion => _currentVersion;

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.buildNumber.isEmpty ? info.version : "${info.version}+${info.buildNumber}";
    } catch (e) {
      developer.log("Failed to read current version", name: "UpdateService", error: e);
    }
  }

  Future<void> checkForUpdate() async {
    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_currentVersion.isEmpty) {
        await _loadCurrentVersion();
      }

      final request = await HttpClient().getUrl(Uri.parse(_releasesUrl));
      request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
      request.headers.set(HttpHeaders.userAgentHeader, "Hearth-UpdateChecker");
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception("GitHub API returned ${response.statusCode}");
      }

      final body = await response.transform(utf8.decoder).join();
      final List<dynamic> releases = jsonDecode(body) as List<dynamic>;
      final List<String> abis = await _channel.getSupportedAbis();

      Map<String, dynamic>? release;
      Map<String, dynamic>? apkAsset;
      for (final candidate in releases.whereType<Map<String, dynamic>>()) {
        if (candidate['draft'] == true || candidate['prerelease'] == true) continue;
        final asset = pickApkAsset((candidate['assets'] as List<dynamic>?) ?? [], abis);
        if (asset != null) {
          release = candidate;
          apkAsset = asset;
          break;
        }
      }

      if (release == null || apkAsset == null) {
        _status = UpdateStatus.error;
        _errorMessage = "No release has an APK for this device";
        notifyListeners();
        return;
      }

      final String tagName = (release['tag_name'] as String?) ?? "";
      final String normalizedTag = tagName.startsWith("v") ? tagName.substring(1) : tagName;
      final String changelog = (release['body'] as String?) ?? "";

      if (compareVersions(normalizedTag, _currentVersion) <= 0) {
        _status = UpdateStatus.upToDate;
        notifyListeners();
        return;
      }

      _updateInfo = UpdateInfo(
        tagName: normalizedTag,
        changelog: changelog,
        downloadUrl: apkAsset['browser_download_url'] as String,
        assetSizeBytes: apkAsset['size'] as int? ?? 0,
      );
      _status = UpdateStatus.available;
      notifyListeners();
    } catch (e, stack) {
      developer.log("Update check failed", name: "UpdateService", error: e, stackTrace: stack);
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> downloadAndInstall() async {
    final info = _updateInfo;
    if (info == null) return;

    _status = UpdateStatus.downloading;
    _downloadProgress = 0;
    notifyListeners();

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception("No external storage directory available");

      final updatesDir = Directory("${dir.path}/updates");
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final apkFile = File("${updatesDir.path}/hearth-${info.tagName}.apk");
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(info.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, "Hearth-UpdateChecker");
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception("Download failed with status ${response.statusCode}");
      }

      final sink = apkFile.openWrite();
      int received = 0;
      final total = info.assetSizeBytes > 0 ? info.assetSizeBytes : response.contentLength;

      await response.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          _downloadProgress = received / total;
          notifyListeners();
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      _downloadedApkPath = apkFile.path;
      _status = UpdateStatus.readyToInstall;
      notifyListeners();

      await _promptInstall();
    } catch (e, stack) {
      developer.log("Update download failed", name: "UpdateService", error: e, stackTrace: stack);
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _promptInstall() async {
    final path = _downloadedApkPath;
    if (path == null) return;

    final hasPermission = await _channel.checkInstallPermission();
    if (!hasPermission) {
      await _channel.requestInstallPermission();
      // The user needs to grant "install unknown apps" for this app, then
      // retry; we don't poll for the grant since it happens in Settings.
      return;
    }

    await _channel.installApk(path);
  }

  /// Call after the user returns from granting the install-unknown-apps
  /// permission, to retry launching the installer with the already-downloaded APK.
  Future<void> retryInstall() async {
    if (_downloadedApkPath != null) {
      await _promptInstall();
    }
  }

  void reset() {
    _status = UpdateStatus.idle;
    _updateInfo = null;
    _downloadProgress = 0;
    _errorMessage = null;
    notifyListeners();
  }
}
