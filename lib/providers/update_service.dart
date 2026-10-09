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
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/github_releases.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, readyToInstall, error }

/// Why the last check or download failed.
enum UpdateError {
  /// No release has an APK built for this device.
  noApkForDevice,

  /// GitHub couldn't be asked (no connection, or it answered with an error).
  checkFailed,

  /// The APK couldn't be downloaded.
  downloadFailed;

  /// What to tell the person, in the app's language.
  String message(AppLocalizations localizations) => switch (this) {
        noApkForDevice => localizations.updateErrorNoApk,
        checkFailed => localizations.updateErrorCheckFailed,
        downloadFailed => localizations.updateErrorDownloadFailed,
      };
}

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

/// Checks Hearth's GitHub releases for a newer APK and hands it to the system installer.
class UpdateService extends ChangeNotifier {
  final FLauncherChannel _channel;
  final GitHubReleases _releases = GitHubReleases("theSiegs/Hearth", userAgent: "Hearth-UpdateChecker");

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _updateInfo;
  double _downloadProgress = 0;
  UpdateError? _error;
  String? _errorMessage;
  String? _downloadedApkPath;
  String _currentVersion = "";

  UpdateService(this._channel) {
    _loadCurrentVersion();
  }

  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  double get downloadProgress => _downloadProgress;

  /// Why the status is [UpdateStatus.error]; [UpdateError.message] says it in the app's language.
  UpdateError? get error => _error;

  /// The failure in English, or the exception's own text.
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
    _error = null;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_currentVersion.isEmpty) {
        await _loadCurrentVersion();
      }

      final release = await _releases.latestWithApk(await _channel.getSupportedAbis());
      if (release == null) {
        _status = UpdateStatus.error;
        _error = UpdateError.noApkForDevice;
        _errorMessage = "No release has an APK for this device";
        notifyListeners();
        return;
      }

      if (compareVersions(release.version, _currentVersion) <= 0) {
        _status = UpdateStatus.upToDate;
        notifyListeners();
        return;
      }

      _updateInfo = UpdateInfo(
        tagName: release.version,
        changelog: release.body,
        downloadUrl: release.apkUrl,
        assetSizeBytes: release.apkSize,
      );
      _status = UpdateStatus.available;
      notifyListeners();
    } catch (e, stack) {
      developer.log("Update check failed", name: "UpdateService", error: e, stackTrace: stack);
      _status = UpdateStatus.error;
      _error = UpdateError.checkFailed;
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
      final apkFile = await downloadedApkFile("hearth-${info.tagName}.apk");
      await _releases.download(info.downloadUrl, apkFile, size: info.assetSizeBytes, onProgress: (fraction) {
        _downloadProgress = fraction;
        notifyListeners();
      });

      _downloadedApkPath = apkFile.path;
      _status = UpdateStatus.readyToInstall;
      notifyListeners();

      await _promptInstall();
    } catch (e, stack) {
      developer.log("Update download failed", name: "UpdateService", error: e, stackTrace: stack);
      _status = UpdateStatus.error;
      _error = UpdateError.downloadFailed;
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
}
