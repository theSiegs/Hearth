import 'package:flauncher/l10n/app_localizations_de.dart';
import 'package:flauncher/l10n/app_localizations_en.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/providers/github_releases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

/// HearthTube's releases as GitHub lists them: its one release is a pre-release on the tag "latest".
class _FakeHearthTubeReleases extends GitHubReleases {
  _FakeHearthTubeReleases() : super("theSiegs/HearthTube", userAgent: "Hearth-Test");

  @override
  Future<dynamic> getJson(Uri uri) async {
    if (uri.path.endsWith("hearthtube.json")) {
      return {
        "32.63": {"versionCode": 3263}
      };
    }
    return [
      {
        "tag_name": "latest",
        "name": "HearthTube 32.63",
        "prerelease": true,
        "assets": [
          {"name": "HearthTube_arm64-v8a.apk", "browser_download_url": "https://example/ht.apk", "size": 1},
          {"name": "hearthtube.json", "browser_download_url": "https://example/hearthtube.json", "size": 1},
        ],
      },
    ];
  }
}

void main() {
  group("newestInManifest", () {
    test("picks the highest versionCode, skipping the download list", () {
      final manifest = {
        "package": {
          "downloadUrlList": ["https://example.invalid/app.apk"]
        },
        "32.60+1": {"versionCode": 2450001, "changelog": []},
        "32.60+2": {"versionCode": 2450002, "changelog": ["First"]},
      };
      expect(newestInManifest(manifest), ("32.60+2", 2450002));
    });

    test("is null when no entry has a versionCode", () {
      expect(newestInManifest({"package": {}}), isNull);
    });

    test("takes HearthTube's date versions over its SmartTube-style ones", () {
      final manifest = {
        "32.63+7": {"versionCode": 2453007},
        "2026.10.10": {"versionCode": 26101001},
        "2026.10.10.2": {"versionCode": 26101002},
      };
      expect(newestInManifest(manifest), ("2026.10.10.2", 26101002));
    });
  });

  group("a HearthTube update is newer", () {
    test("by versionCode when the manifest gives one", () {
      final release = CompanionRelease("2026.10.10", 26101001, "https://example/ht.apk", 1);
      expect(release.isNewerThan({"versionName": "32.63+7", "versionCode": 2453007}), isTrue);
      expect(release.isNewerThan({"versionName": "2026.10.10.2", "versionCode": 26101002}), isFalse);
    });

    test("by version name without one", () {
      expect(CompanionRelease("2026.10.10", null, "", 1).isNewerThan({"versionName": "32.63+7"}), isTrue);
      expect(CompanionRelease("2026.10.10.2", null, "", 1).isNewerThan({"versionName": "2026.10.10"}), isTrue);
      expect(CompanionRelease("2026.10.10", null, "", 1).isNewerThan({"versionName": "2026.10.10.2"}), isFalse);
    });
  });

  test("HearthTube is listed with its release manifest", () {
    final hearthTube = companionApps.singleWhere((app) => app.packageName == "com.thesiegs.hearthtube");
    expect(hearthTube.repo, "theSiegs/HearthTube");
    expect(hearthTube.versionManifest, "hearthtube.json");
  });

  test("HearthTube's description is translated", () {
    final hearthTube = companionApps.singleWhere((app) => app.packageName == "com.thesiegs.hearthtube");
    expect(hearthTube.localizedDescription(AppLocalizationsEn()), hearthTube.description);
    expect(hearthTube.localizedDescription(AppLocalizationsDe()), "YouTube für Hearth; folgt Ihrem Hearth-Profil");
  });

  group("latestRelease follows Include pre-releases", () {
    late MockFLauncherChannel channel;
    late SharedPreferences sharedPreferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
      channel = MockFLauncherChannel();
      when(channel.getSupportedAbis()).thenAnswer((_) async => ["arm64-v8a"]);
    });

    CompanionUpdater updater(bool includePrereleases) => CompanionUpdater(channel, sharedPreferences,
        includePrereleases: () => includePrereleases, releasesFor: (_) => _FakeHearthTubeReleases());

    test("offers HearthTube's pre-release when the switch is on", () async {
      final release = await updater(true).latestRelease(companionApps.first);

      expect(release!.versionName, "32.63");
      expect(release.versionCode, 3263);
      expect(release.isNewerThan({"versionName": "32.50", "versionCode": 3250}), isTrue);
    });

    test("offers nothing from a pre-release when the switch is off", () async {
      expect(await updater(false).latestRelease(companionApps.first), isNull);
    });
  });
}
