import 'package:flauncher/hearth_ids.dart';
import 'package:flauncher/providers/github_releases.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> asset(String name) => {"name": name, "browser_download_url": "https://example/$name", "size": 1};

void main() {
  test("components are named by the Java package in every build", () {
    expect(hearthComponent("com.thesiegs.hearth", "LauncherAccessibilityService"),
        "com.thesiegs.hearth/com.thesiegs.hearth.LauncherAccessibilityService");
    expect(hearthComponent("com.thesiegs.hearth.debug", "LauncherNotificationListenerService"),
        "com.thesiegs.hearth.debug/com.thesiegs.hearth.LauncherNotificationListenerService");
    expect(hearthComponent("com.leanbitlab.ltvL", "LauncherAccessibilityService"),
        "com.leanbitlab.ltvL/com.thesiegs.hearth.LauncherAccessibilityService");
  });

  test("knows Hearth under both ids", () {
    expect(isHearthPackage("com.thesiegs.hearth"), isTrue);
    expect(isHearthPackage("com.thesiegs.hearth.debug"), isTrue);
    expect(isHearthPackage("com.leanbitlab.ltvL"), isTrue);
    expect(isHearthPackage("com.thesiegs.hearthtube"), isFalse);
    expect(isHearthPackage(null), isFalse);
    expect(isBridgePackage("com.leanbitlab.ltvL"), isTrue);
    expect(isBridgePackage("com.leanbitlab.ltvL.debug"), isTrue);
    expect(isBridgePackage("com.thesiegs.hearth"), isFalse);
  });

  test("an update installs the new Hearth, from the new Hearth and from the bridge", () {
    expect(expectedUpdatePackage("com.thesiegs.hearth"), "com.thesiegs.hearth");
    expect(expectedUpdatePackage("com.thesiegs.hearth.debug"), "com.thesiegs.hearth");
    expect(expectedUpdatePackage("com.leanbitlab.ltvL"), "com.thesiegs.hearth");
  });

  test("the bridge build's APKs are never offered as an update", () {
    final release = [
      asset("Hearth-bridge-armeabi-v7a-release.apk"),
      asset("Hearth-bridge-universal-release.apk"),
      asset("Hearth-armeabi-v7a-release.apk"),
      asset("Hearth-universal-release.apk"),
    ];
    expect(pickApkAsset(release, ["armeabi-v7a"], accept: isHearthUpdateAsset)!["name"],
        "Hearth-armeabi-v7a-release.apk");
    expect(pickApkAsset(release, ["x86"], accept: isHearthUpdateAsset)!["name"], "Hearth-universal-release.apk");
    expect(pickApkAsset(release.take(2).toList(), ["armeabi-v7a"], accept: isHearthUpdateAsset), isNull);
  });
}
