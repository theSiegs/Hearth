import 'package:flauncher/providers/github_releases.dart';
import 'package:flauncher/providers/update_deferral.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group("updating quietly", () {
    late MockFLauncherChannel channel;
    final releases = _FakeReleases([_release("v2026.10.01")]);

    setUp(() {
      PackageInfo.setMockInitialValues(
          appName: "Hearth", packageName: "x", version: "2026.10.05", buildNumber: "8113", buildSignature: "");
      channel = MockFLauncherChannel();
      when(channel.getSupportedAbis()).thenAnswer((_) async => ["arm64-v8a"]);
      when(channel.isOwnerUser()).thenAnswer((_) async => true);
      when(channel.isScreenOn()).thenAnswer((_) async => false);
      when(channel.checkInstallPermission()).thenAnswer((_) async => true);
    });

    test("waits while the screen is on", () async {
      when(channel.isScreenOn()).thenAnswer((_) async => true);
      final service = UpdateService(channel, releases: releases);
      expect(await service.updateQuietly(), isFalse);
      verifyNever(channel.getSupportedAbis());
    });

    test("a kids profile's Hearth leaves it to the owner's", () async {
      when(channel.isOwnerUser()).thenAnswer((_) async => false);
      final service = UpdateService(channel, releases: releases);
      expect(await service.updateQuietly(), isTrue);
      verifyNever(channel.getSupportedAbis());
    });

    test("with the screen off and nothing newer: looked, nothing installed", () async {
      final service = UpdateService(channel, releases: releases);
      expect(await service.updateQuietly(), isTrue);
      expect(service.status, UpdateStatus.upToDate);
      verifyNever(channel.installApk(any));
    });
  });

  group("updating quietly while a kids profile runs", () {
    late MockFLauncherChannel channel;
    late SharedPreferences prefs;
    late bool kids;
    late DateTime now;
    final newer = _FakeReleases([_release("v2026.12.01")]);

    setUp(() async {
      PackageInfo.setMockInitialValues(
          appName: "Hearth", packageName: "x", version: "2026.10.05", buildNumber: "8113", buildSignature: "");
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      kids = true;
      now = DateTime(2026, 11, 16, 2);
      channel = MockFLauncherChannel();
      when(channel.getSupportedAbis()).thenAnswer((_) async => ["arm64-v8a"]);
      when(channel.isOwnerUser()).thenAnswer((_) async => true);
      when(channel.isScreenOn()).thenAnswer((_) async => false);
      when(channel.checkInstallPermission()).thenAnswer((_) async => true);
    });

    UpdateService service() => UpdateService(channel,
        releases: newer, deferral: UpdateDeferral(prefs, () async => kids, now: () => now));

    test("waits, and is tried again later", () async {
      final s = service();
      expect(await s.updateQuietly(), isFalse);
      expect(s.status, UpdateStatus.available);
      verifyNever(channel.getApkPackageName(any));
      verifyNever(channel.installApk(any));
    });

    test("goes ahead once no kids profile is running", () async {
      expect(await service().updateQuietly(), isFalse);
      kids = false;
      final s = service();
      await s.updateQuietly();
      // It went on to download (no download in a test: that's the failure it stops at)
      expect(s.error, UpdateError.downloadFailed);
    });

    test("goes ahead after a week of waiting", () async {
      expect(await service().updateQuietly(), isFalse);
      now = now.add(updateDeferralCap);
      final s = service();
      await s.updateQuietly();
      expect(s.error, UpdateError.downloadFailed);
    });

    test("an adult's own Install doesn't wait", () async {
      final s = service();
      await s.checkForUpdate();
      await s.downloadAndInstall();
      expect(s.error, UpdateError.downloadFailed);
    });
  });
}
