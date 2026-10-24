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
import 'package:flauncher/widgets/settings/family_settings_page.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/household_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The household as Hearth's native side reports it, and what removing a TV does.
class _HouseholdChannel extends FLauncherChannel {
  Map<dynamic, dynamic> status = const {};
  final List<String> removed = [];

  @override
  Future<Map<dynamic, dynamic>> getHouseholdStatus() async => status;

  @override
  Future<void> lookForHouseholds() async {}

  @override
  Future<void> stopLookingForHouseholds() async {}

  @override
  Future<bool> removeHouseholdTv(String tvId) async {
    removed.add(tvId);
    return true;
  }

  @override
  Future<Map<dynamic, dynamic>> getKidsProfilesState({bool checkProtection = false}) async => {"kids": []};
}

void main() {
  late _HouseholdChannel channel;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    channel = _HouseholdChannel();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: page),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// Past the page's first look around, and its timers.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  const inHousehold = {
    "joined": true,
    "enabled": true,
    "lastResult": "2 changes",
    "asking": "Office",
    "members": [
      {"tvId": "a", "name": "Kitchen", "self": true, "online": true, "lastSeen": 0},
      {"tvId": "b", "name": "Den", "self": false, "online": true, "lastSeen": 0},
      {"tvId": "c", "name": "Attic", "self": false, "online": false, "lastSeen": 0},
    ],
  };

  testWidgets("in a household its TVs come first, before the switch; a TV asking to join is answered in the Bell",
      (tester) async {
    channel.status = inHousehold;
    await pump(tester, const HouseholdPage());
    final list = tester.getTopLeft(find.text("TVs in this household")).dy;
    expect(tester.getTopLeft(find.text("Kitchen")).dy, greaterThan(list));
    expect(tester.getTopLeft(find.text("Sync with my other TVs")).dy, greaterThan(tester.getTopLeft(find.text("Attic")).dy));
    expect(find.text("This TV"), findsOneWidget);
    expect(find.text("On now"), findsOneWidget);
    expect(find.text("Not seen yet"), findsOneWidget);
    expect(find.text("Office"), findsOneWidget);
    expect(find.text("Asking to join"), findsOneWidget);
    expect(find.text("Last sync: 2 changes"), findsOneWidget);
    await leave(tester);
  });

  testWidgets("another TV opens its card; Close keeps it, Remove takes it out", (tester) async {
    channel.status = inHousehold;
    await pump(tester, const HouseholdPage());
    await tester.tap(find.text("Den"));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text("Remove from household"), findsOneWidget);
    await tester.tap(find.text("Close"));
    await tester.pumpAndSettle();
    expect(channel.removed, isEmpty);
    expect(find.text("Den"), findsOneWidget);
    await tester.tap(find.text("Den"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Remove from household"));
    await tester.pumpAndSettle();
    expect(channel.removed, ["b"]);
    await leave(tester);
  });

  testWidgets("in no household, a household found lists its TVs above Join", (tester) async {
    channel.status = {
      "joined": false,
      "nearby": [
        ["Kitchen", "Den"],
      ],
    };
    await pump(tester, const HouseholdPage());
    expect(find.text("Household on your network"), findsOneWidget);
    expect(tester.getTopLeft(find.text("Den")).dy, lessThan(tester.getTopLeft(find.text("Join the household")).dy));
    await leave(tester);
  });

  /// What the Family page says beside Household sync.
  Finder householdSays(String text) => find.descendant(
      of: find.ancestor(of: find.text("Household sync"), matching: find.byType(FocusableSettingsTile)),
      matching: find.text(text));

  testWidgets("Family says how the household stands", (tester) async {
    channel.status = inHousehold;
    await pump(tester, const FamilySettingsPage());
    expect(householdSays("3 TVs"), findsOneWidget);
    channel.status = {"joined": true, "enabled": false, "members": []};
    await pump(tester, const SizedBox());
    await pump(tester, const FamilySettingsPage());
    expect(householdSays("Off"), findsOneWidget);
    channel.status = {"joined": false, "nearby": []};
    await pump(tester, const SizedBox());
    await pump(tester, const FamilySettingsPage());
    expect(householdSays("Not set up"), findsOneWidget);
  });
}
