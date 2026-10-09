import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks.dart';

void main() {
  test("a new dock starts with the installed streaming apps, in the usual order", () {
    final apps = [
      fakeApp(packageName: "com.android.vending", name: "Play Store"),
      fakeApp(packageName: "com.disney.disneyplus", name: "Disney+"),
      fakeApp(packageName: "com.netflix.ninja", name: "Netflix"),
      fakeApp(packageName: "org.example.game", name: "A game"),
    ];
    expect(AppsService.defaultDockApps(apps).map((a) => a.name), ["Netflix", "Disney+"]);
  });

  test("with fewer than two streaming apps it tops up with TV apps, never the Play Store or sideloaded ones", () {
    final apps = [
      fakeApp(packageName: "com.android.vending", name: "Play Store"),
      fakeApp(packageName: "org.example.side", name: "Sideloaded", sideloaded: true),
      fakeApp(packageName: "org.example.tv", name: "TV app"),
      fakeApp(packageName: "com.netflix.ninja", name: "Netflix"),
    ];
    expect(AppsService.defaultDockApps(apps).map((a) => a.name), ["Netflix", "TV app"]);
  });

  test("at most five", () {
    final apps = [for (final p in AppsService.defaultDockPackages) fakeApp(packageName: p, name: p)];
    expect(AppsService.defaultDockApps(apps).length, AppsService.defaultDockSize);
  });
}
