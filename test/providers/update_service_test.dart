import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/github_releases.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../mocks.mocks.dart';

/// Answers the releases list with [releases], newest first as GitHub lists them.
class _FakeReleases extends GitHubReleases {
  final List<Map<String, dynamic>> releases;

  _FakeReleases(this.releases) : super("owner/app", userAgent: "Hearth-Test");

  @override
  Future<dynamic> getJson(Uri uri) async => releases;
}

Map<String, dynamic> _release(String tag, {bool prerelease = false}) => {
      "tag_name": tag,
      "prerelease": prerelease,
      "assets": [
        {"name": "Hearth-universal-release.apk", "browser_download_url": "https://example/$tag.apk", "size": 1}
      ],
    };

void main() {
  test("each update error has its own message in the app's language", () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final french = await AppLocalizations.delegate.load(const Locale('fr'));

    expect(UpdateError.noApkForDevice.message(english), "No release has an APK for this device");
    expect(UpdateError.checkFailed.message(english), "Couldn't check for updates");
    expect(UpdateError.downloadFailed.message(english), "Couldn't download the update");
    expect(UpdateError.values.map((e) => e.message(french)).toSet(), hasLength(UpdateError.values.length));
    expect(UpdateError.downloadFailed.message(french), "Impossible de télécharger la mise à jour");
  });

  group("pre-releases", () {
    late MockFLauncherChannel channel;
    final releases = _FakeReleases([
      _release("v2026.10.20", prerelease: true),
      _release("v2026.10.01"),
    ]);

    setUp(() {
      PackageInfo.setMockInitialValues(
          appName: "Hearth", packageName: "x", version: "2026.10.05", buildNumber: "8113", buildSignature: "");
      channel = MockFLauncherChannel();
      when(channel.getSupportedAbis()).thenAnswer((_) async => ["arm64-v8a"]);
    });

    test("offers a newer pre-release when they're included", () async {
      final service = UpdateService(channel, includePrereleases: () => true, releases: releases);
      await service.checkForUpdate();

      expect(service.status, UpdateStatus.available);
      expect(service.updateInfo!.tagName, "2026.10.20");
    });

    test("without pre-releases, an older stable release is no update: never a downgrade", () async {
      var include = true;
      final service = UpdateService(channel, includePrereleases: () => include, releases: releases);
      await service.checkForUpdate();
      expect(service.status, UpdateStatus.available);

      include = false;
      await service.checkForUpdate();

      expect(service.status, UpdateStatus.upToDate);
    });
  });
}
