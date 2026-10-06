import 'package:flauncher/widgets/settings/companion_apps_page.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });

  test("HearthTube is listed with its release manifest", () {
    final hearthTube = companionApps.singleWhere((app) => app.packageName == "com.thesiegs.hearthtube");
    expect(hearthTube.repo, "theSiegs/HearthTube");
    expect(hearthTube.versionManifest, "hearthtube.json");
  });
}
