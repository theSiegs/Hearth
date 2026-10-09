import 'package:flauncher/hearth_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("components are named by the Java package in every build", () {
    expect(hearthComponent("com.thesiegs.hearth", "LauncherAccessibilityService"),
        "com.thesiegs.hearth/com.thesiegs.hearth.LauncherAccessibilityService");
    expect(hearthComponent("com.thesiegs.hearth.debug", "LauncherNotificationListenerService"),
        "com.thesiegs.hearth.debug/com.thesiegs.hearth.LauncherNotificationListenerService");
  });

  test("knows Hearth, release or debug, and nothing else", () {
    expect(isHearthPackage("com.thesiegs.hearth"), isTrue);
    expect(isHearthPackage("com.thesiegs.hearth.debug"), isTrue);
    expect(isHearthPackage("com.leanbitlab.ltvL"), isFalse);
    expect(isHearthPackage("com.thesiegs.hearthtube"), isFalse);
    expect(isHearthPackage(null), isFalse);
  });

  test("an update installs Hearth itself", () {
    expect(expectedUpdatePackage("com.thesiegs.hearth"), "com.thesiegs.hearth");
    expect(expectedUpdatePackage("com.thesiegs.hearth.debug"), "com.thesiegs.hearth");
  });
}
