import 'package:flauncher/providers/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> asset(String name) => {"name": name, "browser_download_url": "https://example/$name", "size": 1};

void main() {
  group("compareVersions", () {
    test("orders date-style versions and ignores a leading v", () {
      expect(compareVersions("v2026.10.05", "2026.10.03+8112"), greaterThan(0));
      expect(compareVersions("2026.10.03", "2026.10.03+8112"), lessThan(0));
      expect(compareVersions("2026.10.03+8112", "v2026.10.03+8112"), 0);
      expect(compareVersions("2026.9.30", "2026.10.1"), lessThan(0));
    });
  });

  group("pickApkAsset", () {
    final splitRelease = [
      asset("ltvlauncher-2026.10.05-arm64-v8a.apk"),
      asset("ltvlauncher-2026.10.05-armeabi-v7a.apk"),
      asset("checksums.txt"),
    ];

    test("picks the APK built for the device's ABI", () {
      expect(pickApkAsset(splitRelease, ["armeabi-v7a", "armeabi"])!["name"], "ltvlauncher-2026.10.05-armeabi-v7a.apk");
      expect(pickApkAsset(splitRelease, ["arm64-v8a", "armeabi-v7a"])!["name"], "ltvlauncher-2026.10.05-arm64-v8a.apk");
    });

    test("falls back to a universal APK, never to another ABI", () {
      expect(pickApkAsset([asset("ltvlauncher-2026.10.05.apk"), ...splitRelease], ["x86"])!["name"],
          "ltvlauncher-2026.10.05.apk");
      expect(pickApkAsset(splitRelease, ["x86"]), isNull);
    });

    test("understands this repo's release workflow names", () {
      final workflowRelease = [
        asset("Hearth-universal-release.apk"),
        asset("Hearth-armeabi-v7a-release.apk"),
        asset("Hearth-arm64-v8a-release.apk"),
      ];
      expect(pickApkAsset(workflowRelease, ["armeabi-v7a", "armeabi"])!["name"], "Hearth-armeabi-v7a-release.apk");
      expect(pickApkAsset(workflowRelease, ["arm64-v8a"])!["name"], "Hearth-arm64-v8a-release.apk");
      expect(pickApkAsset(workflowRelease, ["x86_64"])!["name"], "Hearth-universal-release.apk");
    });
  });
}
