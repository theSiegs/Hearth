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
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/streaming_pins_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../mocks.mocks.dart';

const _pkg = "com.example.tv";

/// Profile Pairing's apps, pairings and saved PINs as Hearth's native side has them.
class _PinsChannel extends FLauncherChannel {
  bool parentPresent = false;

  @override
  Future<bool> isParentPresent() async => parentPresent;

  @override
  Future<void> parentConfirmed() async {}

  final List<Map<dynamic, dynamic>> choices = [
    {"hearthProfile": "user:0", "displayName": "Alex", "kids": false, "mode": "profile", "chosenProfile": "Alex M"},
    {"hearthProfile": "user:0:sam", "displayName": "Sam", "kids": false, "mode": "auto", "autoMatch": "Sam M"},
    {"hearthProfile": "user:0:jordan", "displayName": "Jordan", "kids": false, "mode": "auto"},
    {"hearthProfile": "user:10", "displayName": "Riley", "kids": true, "mode": "profile", "chosenProfile": "Kids"},
  ];

  /// App profile -> saved PIN.
  final Map<String, String> pins = {"Alex M": "1111"};

  /// What was changed, in order: pairings ("pair <Google TV profile> <app profile>"), saves and removals.
  final List<String> events = [];

  @override
  Future<Map<dynamic, dynamic>> getProfilePairingStatus() async => {"enabled": true, "voiceDefault": true};

  @override
  Future<List<Map<dynamic, dynamic>>> getProfilePairingApps() async => [
        {
          "packageName": _pkg,
          "label": "Example TV",
          "installed": true,
          "enabled": true,
          "seenProfiles": ["Alex M", "Sam M", "Jo M", "Kids"],
        },
        {"packageName": "com.example.other", "label": "Other TV", "installed": true, "enabled": true},
        {"packageName": "com.example.gone", "label": "Gone TV", "installed": false},
        if (contentAppInstalled)
          {
            "packageName": StreamingPinsPage.contentPinPackage,
            "label": "Mountain+",
            "installed": true,
            "enabled": true,
          },
      ];

  bool contentAppInstalled = false;

  /// The saved content PIN, if any.
  String? contentPin;

  @override
  Future<Map<dynamic, dynamic>> getContentPinStatus(String packageName) async =>
      {"status": contentPin != null ? "saved" : "none", "paused": false};

  @override
  Future<bool> saveContentPin(String packageName, String pin) async {
    events.add("save content $pin");
    contentPin = pin;
    return true;
  }

  @override
  Future<void> removeContentPin(String packageName) async {
    events.add("remove content");
    contentPin = null;
  }

  @override
  Future<bool> profilePinEntrySupported(String packageName) async =>
      packageName != "com.example.other" && packageName != StreamingPinsPage.contentPinPackage;

  @override
  Future<List<Map<dynamic, dynamic>>> getProfilePairingChoices(String packageName) async =>
      packageName == _pkg ? choices : [];

  bool typingOn = true;
  List<Map<dynamic, dynamic>> log = [];

  int phoneSaved = -1;

  @override
  Future<String?> startPinSetup() async => "http://192.0.2.10:8765/secret#key";

  @override
  Future<void> stopPinSetup() async => events.add("phone page closed");

  @override
  Future<int> getPinSetupSaved() async => phoneSaved;

  @override
  Future<bool> isPinTypingOn() async => typingOn;

  @override
  Future<void> setPinTypingOn(bool on) async {
    events.add("typing $on");
    typingOn = on;
  }

  @override
  Future<List<Map<dynamic, dynamic>>> getPinEntryLog() async => log;

  @override
  Future<Map<dynamic, dynamic>> getProfilePinStatus(String packageName, String appProfile,
          {String? profileKey}) async =>
      {"status": pins.containsKey(appProfile) ? "saved" : "none", "paused": false};

  @override
  Future<bool> saveProfilePin(String packageName, String appProfile, String pin) async {
    events.add("save $appProfile $pin");
    pins[appProfile] = pin;
    return true;
  }

  @override
  Future<void> removeProfilePin(String packageName, String appProfile, {String? profileKey}) async {
    events.add("remove $appProfile");
    pins.remove(appProfile);
  }

  @override
  Future<void> setProfilePairingChoice(String packageName, String hearthProfile, String mode, String? appProfile) async {
    events.add("pair $hearthProfile $mode $appProfile");
    final choice = choices.firstWhere((c) => c["hearthProfile"] == hearthProfile);
    choice["mode"] = mode;
    choice["chosenProfile"] = appProfile;
  }
}

void main() {
  late _PinsChannel channel;
  late SharedPreferences prefs;
  late MockProfileService profiles;

  /// The Google TV profile on now: its key and name.
  void on(String key, String name) {
    when(profiles.activeProfileKey).thenReturn(key);
    when(profiles.activeProfileName).thenReturn(name);
    when(profiles.isKidsProfile).thenReturn(!key.startsWith("user:0"));
  }

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // What typing PINs involves was read before (see the consent test)
    await prefs.setBool("pin_consent_given", true);
    channel = _PinsChannel();
    profiles = MockProfileService();
    on("user:0:sam", "Sam");
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
        ChangeNotifierProvider<ProfileService>.value(value: profiles),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StreamingPinsPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final digit in digits.split("")) {
      await tester.sendKeyEvent(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(digit)));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets("only the profile on now, in each app Hearth can type PINs in, with its app profile and PIN",
      (tester) async {
    await pump(tester);
    expect(find.text("Example TV"), findsOneWidget);
    // Matched by name: its PIN can be set too
    expect(find.text("Sam M · Profile PIN: None"), findsOneWidget);
    // Another profile's PIN isn't this one's to see or change
    expect(find.textContaining("Alex M"), findsNothing);
    // Never an app Hearth can't type in, or one that isn't installed
    expect(find.text("Other TV"), findsNothing);
    expect(find.text("Gone TV"), findsNothing);
  });

  testWidgets("one switch turns PIN typing off; recent entries are listed without names", (tester) async {
    channel.log = [
      {"package": _pkg, "versionCode": 7, "content": false, "result": "REJECTED", "at": 0},
    ];
    await pump(tester);
    expect(find.textContaining("Not accepted"), findsOneWidget);
    await tap(tester, "Type saved PINs");
    expect(channel.events, ["typing false"]);
    expect(find.text("Off: the apps ask for their PINs as usual"), findsOneWidget);
  });

  testWidgets("PINs can be set on a phone, past the parent PIN, from a QR code without its key shown", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Set up PINs on your phone");
    await type(tester, "2468");
    expect(find.text("http://192.0.2.10:8765/secret"), findsOneWidget);
    expect(find.textContaining("#key"), findsNothing);
    channel.phoneSaved = 1;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(channel.events, contains("phone page closed"));
  });

  testWidgets("the first PIN saved shows what typing PINs involves, once", (tester) async {
    await prefs.remove("pin_consent_given");
    on("user:10", "Riley");
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Example TV");
    await type(tester, "2468");
    expect(find.text("Before Hearth types PINs for you"), findsOneWidget);
    await tap(tester, "Continue");
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["save Kids 1357"]);
    expect(SettingsService(prefs).pinConsentGiven, isTrue);
  });

  testWidgets("a kids profile has its own PINs, set past the parent PIN", (tester) async {
    on("user:10", "Riley");
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    expect(find.text("Kids · Profile PIN: None"), findsOneWidget);
    await tap(tester, "Example TV");
    expect(find.text("Parent PIN"), findsOneWidget);
    await type(tester, "2468");
    await type(tester, "1357");
    await type(tester, "1357");
    // Paired by an explicit choice already: just the PIN
    expect(channel.events, ["save Kids 1357"]);
  });

  testWidgets("a PIN for a name match pairs it for good, just before the PIN is saved", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Example TV");
    await type(tester, "2468");
    expect(find.text("Sam M’s PIN in Example TV"), findsOneWidget);
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["pair user:0:sam profile Sam M", "save Sam M 1357"]);
    expect(find.text("Sam M · Profile PIN: Saved"), findsOneWidget);
  });

  testWidgets("an adult still at the remote isn't asked for the parent PIN again", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    channel.parentPresent = true;
    await pump(tester);
    await tap(tester, "Example TV");
    // Straight to the app profile's PIN
    expect(find.text("Parent PIN"), findsNothing);
    expect(find.text("Sam M’s PIN in Example TV"), findsOneWidget);
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["pair user:0:sam profile Sam M", "save Sam M 1357"]);
  });

  testWidgets("a kids profile asks for the parent PIN even with an adult around", (tester) async {
    on("user:10", "Riley");
    await SettingsService(prefs).setParentPin("2468");
    channel.parentPresent = true;
    await pump(tester);
    await tap(tester, "Example TV");
    expect(find.text("Parent PIN"), findsOneWidget);
  });

  testWidgets("backing out of the PIN changes no pairing", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Example TV");
    await type(tester, "2468");
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(channel.events, isEmpty);
  });

  testWidgets("without a parent PIN, says to set one first", (tester) async {
    await pump(tester);
    await tap(tester, "Example TV");
    expect(find.textContaining("Set a parent PIN first"), findsOneWidget);
    expect(channel.events, isEmpty);
  });

  testWidgets("no match yet: the app profile is picked first", (tester) async {
    on("user:0:jordan", "Jordan");
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    expect(find.text("No match yet: shows the picker"), findsOneWidget);
    await tap(tester, "Example TV");
    expect(find.text("Jordan in Example TV"), findsOneWidget);
    await tap(tester, "Jo M");
    await type(tester, "2468");
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["pair user:0:jordan profile Jo M", "save Jo M 1357"]);
  });

  testWidgets("a saved PIN can be removed, and the pairing stays", (tester) async {
    on("user:0", "Alex");
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Example TV");
    await type(tester, "2468");
    await tap(tester, "Remove PIN");
    expect(channel.events, ["remove Alex M"]);
    expect(find.text("Alex M · Profile PIN: None"), findsOneWidget);
  });

  group("content PIN", () {
    const hint = "Typed only in adults’ profiles that have a Google TV PIN lock";

    testWidgets("an adult's profile has the row, once the app is installed", (tester) async {
      channel.contentAppInstalled = true;
      await pump(tester);
      expect(find.text("Mountain+ content PIN"), findsOneWidget);
      expect(find.text("None · $hint"), findsOneWidget);
      // Not a profile PIN row of its own
      expect(find.text("Mountain+"), findsNothing);
    });

    testWidgets("no row without the app", (tester) async {
      await pump(tester);
      expect(find.textContaining("content PIN"), findsNothing);
    });

    testWidgets("never in a kids profile", (tester) async {
      on("user:10", "Riley");
      channel.contentAppInstalled = true;
      channel.contentPin = "4321";
      await pump(tester);
      expect(find.textContaining("content PIN"), findsNothing);
    });

    testWidgets("set past the parent PIN, typed twice", (tester) async {
      channel.contentAppInstalled = true;
      await SettingsService(prefs).setParentPin("2468");
      await pump(tester);
      await tap(tester, "Mountain+ content PIN");
      expect(find.text("Parent PIN"), findsOneWidget);
      await type(tester, "2468");
      expect(find.text("Mountain+ content PIN"), findsWidgets);
      expect(find.textContaining("when a title starts"), findsOneWidget);
      await type(tester, "1357");
      await type(tester, "1357");
      // Nothing paired: the content PIN is the whole TV's
      expect(channel.events, ["save content 1357"]);
      expect(find.text("Saved · $hint"), findsOneWidget);
    });

    testWidgets("an adult still at the remote goes straight to the PIN", (tester) async {
      channel.contentAppInstalled = true;
      channel.parentPresent = true;
      await SettingsService(prefs).setParentPin("2468");
      await pump(tester);
      await tap(tester, "Mountain+ content PIN");
      expect(find.text("Parent PIN"), findsNothing);
      await type(tester, "1357");
      await type(tester, "1357");
      expect(channel.events, ["save content 1357"]);
    });

    testWidgets("a saved one can be changed or removed", (tester) async {
      channel.contentAppInstalled = true;
      channel.contentPin = "1111";
      await SettingsService(prefs).setParentPin("2468");
      await pump(tester);
      expect(find.text("Saved · $hint"), findsOneWidget);
      await tap(tester, "Mountain+ content PIN");
      await type(tester, "2468");
      await tap(tester, "Change PIN");
      await type(tester, "2222");
      await type(tester, "2222");
      expect(channel.events, ["save content 2222"]);
      await tap(tester, "Mountain+ content PIN");
      await type(tester, "2468");
      await tap(tester, "Remove PIN");
      expect(channel.events, ["save content 2222", "remove content"]);
      expect(find.text("None · $hint"), findsOneWidget);
    });

    testWidgets("without a parent PIN, says to set one first", (tester) async {
      channel.contentAppInstalled = true;
      await pump(tester);
      await tap(tester, "Mountain+ content PIN");
      expect(find.textContaining("Set a parent PIN first"), findsOneWidget);
      expect(channel.events, isEmpty);
    });
  });
}
