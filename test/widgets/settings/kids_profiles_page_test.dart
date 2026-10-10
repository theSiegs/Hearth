/*
 * Hearth
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
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'dart:io';

import 'package:flauncher/models/kids_profiles.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/widgets/settings/kid_profile_page.dart';
import 'package:flauncher/widgets/settings/kids_profiles_page.dart';
import 'package:flauncher/widgets/settings/profiles_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The TV's kids' profiles as Hearth's native side reports them, and what Fix and Remove do to them.
class _KidsChannel extends FLauncherChannel {
  /// Each kids' profile: its name and whether Hearth and HearthTube are on it, and kept.
  List<Map<String, dynamic>> kids = [];
  bool tubeOnOwner = false;
  bool keep = false;
  bool trusted = false;
  bool adb = true;

  /// Whether Hearth's own adb works (false: "Allow debugging?" wasn't allowed).
  bool works = true;
  int fixes = 0;
  int removes = 0;
  int uninstalls = 0;
  int aboutOpened = 0;
  final List<bool> reads = [];

  @override
  Future<Map<dynamic, dynamic>> getKidsProfilesState({bool checkProtection = false}) async {
    reads.add(checkProtection);
    return {
      "kids": [
        for (final kid in kids)
          {
            ...kid,
            // Whether a copy is kept is read only over Hearth's own adb
            "hearthKept": checkProtection ? kid["hearthKept"] : null,
            "hearthTubeKept": checkProtection ? kid["hearthTubeKept"] : null,
          },
      ],
      "hearthTubeOnOwner": tubeOnOwner,
      "keep": keep,
      "trusted": trusted,
      "adbEnabled": adb,
    };
  }

  @override
  Future<bool> isAdbEnabled() async => adb;

  @override
  Future<bool> openDeviceInfoSettings() async {
    aboutOpened++;
    return true;
  }

  @override
  Future<List<String>> fixKidsProfiles({int? userId}) async {
    if (!works) throw PlatformException(code: "SELF_ADB");
    fixes++;
    fixedOnly.add(userId);
    keep = true;
    trusted = true;
    for (final kid in kids.where((k) => userId == null || k["userId"] == userId)) {
      kid["hearth"] = true;
      kid["hearthKept"] = true;
      if (tubeOnOwner) {
        kid["hearthTube"] = true;
        kid["hearthTubeKept"] = true;
      }
    }
    return ["added"];
  }

  @override
  Future<List<String>> removeHearthFromKidsProfiles() async {
    if (!works) throw PlatformException(code: "SELF_ADB");
    removes++;
    keep = false;
    for (final kid in kids) {
      kid["hearth"] = false;
      kid["hearthTube"] = false;
    }
    return ["removed"];
  }

  @override
  Future<void> uninstallHearth() async => uninstalls++;

  /// Which kids' profiles each Fix was for (null: all of them).
  final List<int?> fixedOnly = [];

  /// HearthTube on the TV (the owner's), and what Android's installer does with it.
  bool tubeInstalled = false;
  bool installPermission = true;
  int installs = 0;
  int tubeSettingsOpened = 0;

  @override
  Future<Map<dynamic, dynamic>?> getPackageVersion(String packageName) async =>
      tubeInstalled ? {"versionName": "1.0", "versionCode": 1} : null;

  @override
  Future<bool> checkInstallPermission() async => installPermission;

  @override
  Future<bool> installApk(String path) async {
    installs++;
    tubeInstalled = true;
    tubeOnOwner = true;
    return true;
  }

  @override
  Future<bool> openHearthTubeSettings({String? section}) async {
    tubeSettingsOpened++;
    return true;
  }

  @override
  Future<int> getLockOnSleepMinutes() async => -1;

  /// Each profile's YouTube limit by its key (null: the profile on now).
  final Map<String?, int> limits = {};

  @override
  Future<int> getYouTubeDailyMinutes({String? profileKey}) async => limits[profileKey] ?? 0;

  @override
  Future<void> setYouTubeDailyMinutes(int minutes, {String? profileKey}) async => limits[profileKey] = minutes;
}

/// HearthTube's newest release, downloaded at once.
class _FakeUpdater extends Fake implements CompanionUpdater {
  bool autoUpdate = false;

  @override
  Future<CompanionRelease?> latestRelease(CompanionApp app) async => CompanionRelease("1.0", 1, "https://example.com/t.apk", 1);

  @override
  Future<File> download(CompanionApp app, CompanionRelease release, {void Function(double)? onProgress}) async {
    onProgress?.call(1);
    return File("hearthtube.apk");
  }

  @override
  Future<void> setAutoUpdate(bool enabled) async => autoUpdate = enabled;
}

void main() {
  late _KidsChannel channel;
  late SharedPreferences prefs;
  late SetupFlowService flow;
  late _FakeUpdater updater;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    flow = SetupFlowService(prefs);
    channel = _KidsChannel();
    updater = _FakeUpdater();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider<SetupFlowService>.value(value: flow),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
        Provider<CompanionUpdater>.value(value: updater),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: page),
        // Settings' panel routes this one (settings_panel.dart)
        onGenerateRoute: (settings) {
          final (state, kid) = settings.arguments as (KidsProfilesState, KidProfile);
          return MaterialPageRoute(builder: (_) => Scaffold(body: KidProfilePage(state: state, kid: kid)));
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets("each kids' profile says how it stands; Fix shows only when one needs it", (tester) async {
    channel.tubeOnOwner = true;
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true, "hearthTube": true},
      {"userId": 11, "name": "Alex", "hearth": true, "hearthTube": false},
      {"userId": 12, "name": null, "hearth": false, "hearthTube": false},
    ];
    await pump(tester, const KidsProfilesPage());
    expect(find.text("Sam"), findsOneWidget);
    expect(find.text("Hearth and HearthTube are on it"), findsOneWidget);
    expect(find.text("HearthTube isn't on it"), findsOneWidget);
    expect(find.text("A kids' profile"), findsOneWidget);
    expect(find.text("Hearth isn't on it"), findsOneWidget);
    expect(find.text("Ready"), findsOneWidget);
    expect(find.text("Needs a fix"), findsNWidgets(2));
    expect(find.text("Fix"), findsOneWidget);
    // Not trusted yet: what the first Fix will ask, and nothing read over adb
    expect(find.textContaining("Allow debugging?"), findsOneWidget);
    expect(channel.reads, [false]);
  });

  testWidgets("all ready: no Fix, and Remove is there", (tester) async {
    channel.tubeOnOwner = true;
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true, "hearthTube": true},
    ];
    await pump(tester, const KidsProfilesPage());
    expect(find.text("Ready"), findsOneWidget);
    expect(find.text("Fix"), findsNothing);
    expect(find.text("Remove Hearth from kids' profiles"), findsOneWidget);
  });

  testWidgets("with a trusted key, whether the copies are kept is read too, and an unkept one needs a fix",
      (tester) async {
    channel.trusted = true;
    channel.keep = true;
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true, "hearthKept": false},
    ];
    await pump(tester, const KidsProfilesPage());
    expect(channel.reads, [false, true]);
    expect(find.textContaining("Not protected"), findsOneWidget);
    expect(find.text("Needs a fix"), findsOneWidget);
    // New kids' profiles get Hearth by themselves from now on
    expect(find.text("Hearth also puts itself on new kids' profiles."), findsOneWidget);
  });

  testWidgets("Fix puts Hearth back, and the setup flow counts the profiles", (tester) async {
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": false},
      {"userId": 11, "name": "Alex", "hearth": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Fix");
    expect(channel.fixes, 1);
    expect(find.text("Ready"), findsNWidgets(2));
    expect(find.text("Fix"), findsNothing);
    expect(flow.kidsProtected, 2);
  });

  testWidgets("Fix with debugging off says how to turn it on, and changes nothing", (tester) async {
    channel.adb = false;
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Fix");
    expect(find.text("Turn on debugging first"), findsOneWidget);
    await press(tester, "Open About");
    expect(channel.aboutOpened, 1);
    expect(channel.fixes, 0);
  });

  testWidgets("Fix without the approval says what to do", (tester) async {
    channel.works = false;
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Fix");
    expect(find.text("Couldn't change the kids' profiles"), findsOneWidget);
    expect(flow.kidsProtected, 0);
  });

  testWidgets("Remove asks first, then takes Hearth off", (tester) async {
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Remove Hearth from kids' profiles");
    expect(channel.removes, 0);
    await press(tester, "Remove");
    expect(channel.removes, 1);
    expect(find.text("Hearth isn't on it"), findsOneWidget);
  });

  testWidgets("Uninstall takes Hearth off the kids' profiles first, and stops when it can't", (tester) async {
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true},
    ];
    channel.works = false;
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Uninstall Hearth");
    await press(tester, "Uninstall");
    expect(find.text("Finish the one-time approval first"), findsOneWidget);
    expect(channel.uninstalls, 0);
    await press(tester, "OK");

    channel.works = true;
    await press(tester, "Uninstall Hearth");
    await press(tester, "Uninstall");
    expect(channel.removes, 1);
    expect(channel.uninstalls, 1);
  });

  testWidgets("a kid's own page sets their YouTube time, without switching to them", (tester) async {
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "hearth": true},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    expect(find.text("YouTube time per day"), findsOneWidget);
    expect(find.text("No limit"), findsOneWidget);
    await press(tester, "YouTube time per day");
    await press(tester, "30 minutes");
    expect(channel.limits, {"user:10": 30});
    expect(find.text("30 minutes"), findsOneWidget);
  });

  testWidgets("a kid's page that needs a fix goes back to Fix", (tester) async {
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "hearth": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    expect(find.text("Hearth isn't on it"), findsOneWidget);
    await press(tester, "Fix");
    expect(channel.fixes, 1);
    expect(find.text("Ready"), findsOneWidget);
  });

  testWidgets("HearthTube on the TV but not on this kid: their page puts it on them only", (tester) async {
    channel.tubeOnOwner = true;
    channel.tubeInstalled = true;
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "hearth": true, "hearthTube": false},
      {"userId": 11, "profileKey": "user:11", "name": "Alex", "hearth": true, "hearthTube": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    await press(tester, "HearthTube 1.0");
    expect(channel.fixedOnly, [10]);
    expect(channel.kids[1]["hearthTube"], isFalse);
    expect(find.text("HearthTube isn't on it"), findsNothing);
  });

  testWidgets("no HearthTube on the TV: a kid's page installs it, then puts it on that kid", (tester) async {
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "hearth": true, "hearthTube": false},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    expect(find.text("Get HearthTube"), findsOneWidget);
    await tester.tap(find.text("Get HearthTube"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(channel.installs, 1);
    expect(updater.autoUpdate, isTrue);
    expect(channel.fixedOnly, [10]);
    expect(find.text("Get HearthTube"), findsNothing);
  });

  testWidgets("Get HearthTube asks for installing apps first when Android doesn't allow it yet", (tester) async {
    channel.installPermission = false;
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "hearth": true},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    await press(tester, "Get HearthTube");
    expect(find.text("Allow Hearth to install apps"), findsOneWidget);
    expect(channel.installs, 0);
  });

  testWidgets("HearthTube's settings only while that kid's profile is on", (tester) async {
    channel.tubeOnOwner = true;
    channel.tubeInstalled = true;
    channel.kids = [
      {"userId": 10, "profileKey": "user:10", "name": "Sam", "running": true, "hearth": true, "hearthTube": true},
      {"userId": 11, "profileKey": "user:11", "name": "Alex", "hearth": true, "hearthTube": true},
    ];
    await pump(tester, const KidsProfilesPage());
    await press(tester, "Sam");
    await press(tester, "HearthTube settings");
    expect(channel.tubeSettingsOpened, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await press(tester, "Alex");
    expect(find.text("HearthTube settings"), findsNothing);
  });

  testWidgets("no kids' profiles: says so, and Uninstall is still there", (tester) async {
    await pump(tester, const KidsProfilesPage());
    expect(find.text("There are no kids' profiles on this TV."), findsOneWidget);
    expect(find.text("Fix"), findsNothing);
    expect(find.text("Uninstall Hearth"), findsOneWidget);
  });

  testWidgets("Profiles shows how many kids' profiles need a fix, and Streaming app PINs", (tester) async {
    channel.kids = [
      {"userId": 10, "name": "Sam", "hearth": true},
      {"userId": 11, "name": "Alex", "hearth": false},
    ];
    await pump(tester, const ProfilesSettingsPage());
    expect(find.text("Kids' profiles"), findsOneWidget);
    expect(find.text("1 needs a fix"), findsOneWidget);
    expect(find.text("Streaming app PINs"), findsOneWidget);
    expect(find.text("Hearth on other profiles"), findsNothing);
  });
}
