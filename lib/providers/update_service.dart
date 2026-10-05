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

/// Checks GitHub Releases for newer builds of this launcher and installs
/// them via the system package installer. Only talks to:
///  - api.github.com (release metadata)
///  - the GitHub-hosted asset download URL returned by that API
/// No analytics, no ads, no third-party endpoints.
class UpdateService extends ChangeNotifier {
  static const String _repoOwner = "theSiegs";
  static const String _repoName = "LtvLauncher";
  static const String _releasesUrl = "https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest";

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
      _currentVersion = info.version;
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
      request.headers.set(HttpHeaders.userAgentHeader, "LTvLauncher-UpdateChecker");
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception("GitHub API returned ${response.statusCode}");
      }

      final body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;

      final String tagName = (json['tag_name'] as String?) ?? "";
      final String normalizedTag = tagName.startsWith("v") ? tagName.substring(1) : tagName;
      final String changelog = (json['body'] as String?) ?? "";
      final List<dynamic> assets = (json['assets'] as List<dynamic>?) ?? [];

      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String? ?? "").toLowerCase().endsWith(".apk"),
            orElse: () => <String, dynamic>{},
          );

      if (apkAsset.isEmpty || normalizedTag.isEmpty) {
        _status = UpdateStatus.error;
        _errorMessage = "No APK asset found on the latest release";
        notifyListeners();
        return;
      }

      if (normalizedTag == _currentVersion) {
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

      final apkFile = File("${updatesDir.path}/ltvlauncher-${info.tagName}.apk");
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(info.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, "LTvLauncher-UpdateChecker");
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
