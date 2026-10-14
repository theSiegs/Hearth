/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test("getApplications", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getApplications") {
        return [
          {'packageName': 'me.efesser.flauncher'}
        ];
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final apps = await fLauncherChannel.getApplications();

    expect(apps, [
      {'packageName': 'me.efesser.flauncher'}
    ]);
  });

  test("launchApp", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    String? packageName;
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "launchApp") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    await fLauncherChannel.launchApp("me.efesser.flauncher");

    expect(packageName, "me.efesser.flauncher");
  });

  test("openSettings", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    bool called = false;
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "openSettings") {
        called = true;
        return;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    await fLauncherChannel.openSettings();

    expect(called, isTrue);
  });

  test("openAppInfo", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    String? packageName;
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "openAppInfo") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    await fLauncherChannel.openAppInfo("me.efesser.flauncher");

    expect(packageName, "me.efesser.flauncher");
  });

  test("uninstallApp", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    String? packageName;
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "uninstallApp") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    await fLauncherChannel.uninstallApp("me.efesser.flauncher");

    expect(packageName, "me.efesser.flauncher");
  });

  test("isDefaultLauncher", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "isDefaultLauncher") {
        return true;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final isDefaultLauncher = await fLauncherChannel.isDefaultLauncher();

    expect(isDefaultLauncher, isTrue);
  });

  test("checkForGetContentAvailability", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "checkForGetContentAvailability") {
        return true;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final getContentAvailable = await fLauncherChannel.checkForGetContentAvailability();

    expect(getContentAvailable, isTrue);
  });

  test("startAmbientMode", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    bool called = false;
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "startAmbientMode") {
        called = true;
        return;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    await fLauncherChannel.startAmbientMode();

    expect(called, isTrue);
  });

  test("getDailyDataUsage success", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getDailyDataUsage") {
        return 12345;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getDailyDataUsage();

    expect(usage, 12345);
  });

  test("getDailyDataUsage platform exception", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getDailyDataUsage") {
        throw PlatformException(code: "ERROR");
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getDailyDataUsage();

    expect(usage, -1);
  });

  test("getWeeklyDataUsage success", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getWeeklyDataUsage") {
        return 67890;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getWeeklyDataUsage();

    expect(usage, 67890);
  });

  test("getWeeklyDataUsage platform exception", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getWeeklyDataUsage") {
        throw PlatformException(code: "ERROR");
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getWeeklyDataUsage();

    expect(usage, -1);
  });

  test("getMonthlyDataUsage success", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getMonthlyDataUsage") {
        return 99999;
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getMonthlyDataUsage();

    expect(usage, 99999);
  });

  test("getMonthlyDataUsage platform exception", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getMonthlyDataUsage") {
        throw PlatformException(code: "ERROR");
      }
      fail("Unhandled method name");
    });
    final fLauncherChannel = FLauncherChannel();

    final usage = await fLauncherChannel.getMonthlyDataUsage();

    expect(usage, -1);
  });

  test("openScreensaverSettings", () async {
    const channel = MethodChannel('me.efesser.flauncher/method');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    bool called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "openScreensaverSettings") {
        called = true;
        return true;
      }
      fail("Unhandled method name");
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final opened = await FLauncherChannel().openScreensaverSettings();

    expect(called, isTrue);
    expect(opened, isTrue);
  });

  test("getNetworkStatus reads the connection", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getNetworkStatus") return {"type": "wifi", "vpn": true, "internet": false};
      fail("Unhandled method name");
    });

    final status = await FLauncherChannel().getNetworkStatus();

    expect(status, {"type": "wifi", "vpn": true, "internet": false});
  });

  test("getDataUsageByApp passes the period and reads the apps", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getDataUsageByApp") {
        expect(call.arguments, "weekly");
        return {
          "total": 3000,
          "apps": [
            {"packageName": "com.example.tv", "label": "TV", "kind": "app", "bytes": 2000},
          ],
        };
      }
      fail("Unhandled method name");
    });

    final breakdown = await FLauncherChannel().getDataUsageByApp("weekly");

    expect(breakdown!.total, 3000);
    expect(breakdown.apps.single.label, "TV");
  });

  test("getDataUsageByApp is null without usage access or on an error", () async {
    final channel = MethodChannel('me.efesser.flauncher/method');
    _messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await FLauncherChannel().getDataUsageByApp("daily"), isNull);

    _messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: "ERROR"));
    expect(await FLauncherChannel().getDataUsageByApp("daily"), isNull);
  });
}
