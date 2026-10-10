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
import 'package:flauncher/widgets/settings/streaming_pins_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _pkg = "com.example.tv";

/// Profile Pairing's apps, pairings and saved PINs as Hearth's native side has them.
class _PinsChannel extends FLauncherChannel {
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
      ];

  @override
  Future<bool> profilePinEntrySupported(String packageName) async => packageName != "com.example.other";

  @override
  Future<List<Map<dynamic, dynamic>>> getProfilePairingChoices(String packageName) async =>
      packageName == _pkg ? choices : [];

  @override
  Future<Map<dynamic, dynamic>> getProfilePinStatus(String packageName, String appProfile) async =>
      {"status": pins.containsKey(appProfile) ? "saved" : "none", "paused": false};

  @override
  Future<bool> saveProfilePin(String packageName, String appProfile, String pin) async {
    events.add("save $appProfile $pin");
    pins[appProfile] = pin;
    return true;
  }

  @override
  Future<void> removeProfilePin(String packageName, String appProfile) async {
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

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    channel = _PinsChannel();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
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

  testWidgets("each grown-up's profile in the apps Hearth can type PINs in, with its app profile and PIN",
      (tester) async {
    await pump(tester);
    expect(find.text("Example TV"), findsOneWidget);
    expect(find.text("Alex M · Profile PIN: Saved"), findsOneWidget);
    // Matched by name: its PIN can be set too
    expect(find.text("Sam M · Profile PIN: None"), findsOneWidget);
    expect(find.text("No match yet: shows the picker"), findsOneWidget);
    // Never a kids' profile; never an app Hearth can't type in, or one that isn't installed
    expect(find.text("Riley"), findsNothing);
    expect(find.text("Other TV"), findsNothing);
    expect(find.text("Gone TV"), findsNothing);
  });

  testWidgets("a PIN for a name match pairs it for good, just before the PIN is saved", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Sam");
    await type(tester, "2468");
    expect(find.text("Sam M’s PIN in Example TV"), findsOneWidget);
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["pair user:0:sam profile Sam M", "save Sam M 1357"]);
    expect(find.text("Sam M · Profile PIN: Saved"), findsOneWidget);
  });

  testWidgets("backing out of the PIN changes no pairing", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Sam");
    await type(tester, "2468");
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(channel.events, isEmpty);
  });

  testWidgets("without a parent PIN, says to set one first", (tester) async {
    await pump(tester);
    await tap(tester, "Sam");
    expect(find.textContaining("Set a parent PIN first"), findsOneWidget);
    expect(channel.events, isEmpty);
  });

  testWidgets("no match yet: the app profile is picked first", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Jordan");
    expect(find.text("Jordan in Example TV"), findsOneWidget);
    await tap(tester, "Jo M");
    await type(tester, "2468");
    await type(tester, "1357");
    await type(tester, "1357");
    expect(channel.events, ["pair user:0:jordan profile Jo M", "save Jo M 1357"]);
  });

  testWidgets("a saved PIN can be removed, and the pairing stays", (tester) async {
    await SettingsService(prefs).setParentPin("2468");
    await pump(tester);
    await tap(tester, "Alex");
    await type(tester, "2468");
    await tap(tester, "Remove PIN");
    expect(channel.events, ["remove Alex M"]);
    expect(find.text("Alex M · Profile PIN: None"), findsOneWidget);
  });
}
