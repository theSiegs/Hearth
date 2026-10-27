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
import 'package:flauncher/share/household_join.dart';
import 'package:flauncher/widgets/settings/family_settings_page.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/household_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool left = false;

  @override
  Future<bool> requestHouseholdJoin() async => true;

  @override
  Future<void> cancelHouseholdJoin() async {}

  @override
  Future<void> leaveHousehold() async => left = true;
}

/// What joining changes, as the looks service would say, and what was decided.
class _Reviewer implements HouseholdJoinReviewer {
  JoinPreview? preview;
  bool finished = false;
  bool restored = false;
  DateTime? backupAt;

  @override
  Future<JoinPreview?> joinPreview() async => preview;

  @override
  Future<bool> finishJoin(JoinPreview preview) async => finished = true;

  @override
  Future<DateTime?> joinBackupAt() async => backupAt;

  @override
  Future<bool> restoreJoinBackup() async => restored = true;
}

void main() {
  late _HouseholdChannel channel;
  late _Reviewer reviewer;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    channel = _HouseholdChannel();
    reviewer = _Reviewer();
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        Provider<HouseholdJoinReviewer>.value(value: reviewer),
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

  group("before joining", () {
    const joinedHolding = {
      "joined": true,
      "join": {"state": "joined"},
      "review": {"ready": true},
      "members": [],
    };

    /// Opens the join dialog from a button, and remembers what it answered.
    Future<List<bool>> openJoin(WidgetTester tester) async {
      final answers = <bool>[];
      await pump(
          tester,
          Builder(
              builder: (context) => TextButton(
                  onPressed: () async => answers.add(await joinNearbyHousehold(context, channel)),
                  child: const Text("open"))));
      await tester.tap(find.text("open"));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      return answers;
    }

    testWidgets("while it waits for Allow, the join code shows large, grouped as the Bell shows it", (tester) async {
      channel.status = {
        "joined": false,
        "join": {"state": "waiting", "code": "626 952", "via": "Office"},
      };
      await openJoin(tester);
      expect(find.text("Allow it on Office"), findsOneWidget);
      expect(find.text("Join code"), findsOneWidget);
      final code = tester.widget<Text>(find.byKey(const ValueKey("householdJoinCode")));
      expect(code.data, "626 952");
      expect(code.style!.fontSize, greaterThanOrEqualTo(40));
      expect(find.textContaining("Choose Allow only when it's this one"), findsOneWidget);
      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      await leave(tester);
    });

    test("the join code is grouped in threes, however it comes", () {
      expect(joinCodeText("626952"), "626 952");
      expect(joinCodeText("626 952"), "626 952");
      expect(joinCodeText("12345"), "12345");
    });

    testWidgets("once allowed, what changes here is listed first; Join and use these goes on", (tester) async {
      channel.status = joinedHolding;
      reviewer.preview = const JoinPreview(profiles: [
        JoinChange(key: "user:0", name: "Alex", look: true, layout: true, pins: 1),
        JoinChange(key: "user:0#sam", name: "Sam"),
      ], parentPin: true);
      final answers = await openJoin(tester);
      expect(find.text("Before this TV joins"), findsOneWidget);
      expect(find.text("These will change on this TV:"), findsOneWidget);
      expect(find.text("Alex: look, home layout, 1 saved PIN"), findsOneWidget);
      // Nothing of Sam's changes, so Sam isn't listed
      expect(find.textContaining("Sam"), findsNothing);
      expect(find.text("The Parent PIN"), findsOneWidget);
      await tester.tap(find.text("Join and use these"));
      await tester.pumpAndSettle();
      expect(reviewer.finished, isTrue);
      expect(answers, [true]);
      await leave(tester);
    });

    testWidgets("what changes holds the remote's focus: Later first, arrows stay in it, Back is Later", (tester) async {
      channel.status = joinedHolding;
      reviewer.preview = const JoinPreview(profiles: [JoinChange(key: "user:0", name: "Alex", look: true)]);
      final answers = <bool>[];
      final keysBehind = <LogicalKeyboardKey>[];
      final steal = ValueNotifier(false);
      // A page behind it that, like the settings panel, acts on the arrows, and builds a tile with autofocus as it
      // refreshes (the Household page does once this TV has joined)
      await pump(
          tester,
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) keysBehind.add(event.logicalKey);
              return KeyEventResult.handled;
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: steal,
              builder: (context, stealing, _) => Column(children: [
                TextButton(
                    onPressed: () async => answers.add(await joinNearbyHousehold(context, channel)),
                    child: const Text("open")),
                if (stealing) TextButton(autofocus: true, onPressed: () {}, child: const Text("Finish joining")),
              ]),
            ),
          ));
      await tester.tap(find.text("open"));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      String focusedLabel() {
        for (final label in ["Don't join", "Later", "Join and use these", "Finish joining"]) {
          if (find.text(label).evaluate().isEmpty) continue;
          final node = Focus.maybeOf(tester.element(find.text(label)));
          if (node != null && node.hasPrimaryFocus) return label;
        }
        return "elsewhere";
      }

      expect(focusedLabel(), "Later");
      // The page refreshes into a tile with autofocus: the focus comes back to the dialog
      steal.value = true;
      await tester.pump();
      await tester.pump();
      expect(focusedLabel(), "Later");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedLabel(), "Don't join");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedLabel(), "Don't join");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusedLabel(), "Join and use these");
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(keysBehind, isEmpty);
      expect(find.text("Before this TV joins"), findsOneWidget);
      // Back is Later: the TV stays held, nothing taken
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("Before this TV joins"), findsNothing);
      expect(reviewer.finished, isFalse);
      expect(channel.left, isFalse);
      expect(answers, [true]);
      await leave(tester);
    });

    testWidgets("Don't join leaves again, and nothing is taken", (tester) async {
      channel.status = joinedHolding;
      reviewer.preview = const JoinPreview(profiles: [JoinChange(key: "user:0", name: "Alex", look: true)]);
      final answers = await openJoin(tester);
      await tester.tap(find.text("Don't join"));
      await tester.pumpAndSettle();
      expect(channel.left, isTrue);
      expect(reviewer.finished, isFalse);
      expect(answers, [false]);
      await leave(tester);
    });

    testWidgets("when nothing here would change, it joins without asking", (tester) async {
      channel.status = joinedHolding;
      reviewer.preview = const JoinPreview(profiles: [JoinChange(key: "user:0", name: "Alex")]);
      final answers = await openJoin(tester);
      await tester.pumpAndSettle();
      expect(find.text("These will change on this TV:"), findsNothing);
      expect(reviewer.finished, isTrue);
      expect(answers, [true]);
      await leave(tester);
    });

    testWidgets("until the household's settings come, it waits, and Later leaves the TV as it is", (tester) async {
      channel.status = {...joinedHolding, "review": {"ready": false}};
      final answers = await openJoin(tester);
      expect(find.text("Getting your other TVs' settings…"), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("haven't arrived yet"), findsOneWidget);
      await tester.tap(find.text("Later"));
      await tester.pumpAndSettle();
      expect(reviewer.finished, isFalse);
      expect(answers, [true]);
      await leave(tester);
    });

    testWidgets("the household page offers Finish joining while holding, and Put back while the copy is kept",
        (tester) async {
      channel.status = {...inHousehold, "review": {"ready": true}};
      await pump(tester, const HouseholdPage());
      expect(find.text("Finish joining"), findsOneWidget);
      expect(find.text("Put back this TV's settings from before it joined"), findsNothing);
      await leave(tester);

      channel.status = {...inHousehold, "joinBackupAt": DateTime(2026, 10, 1).millisecondsSinceEpoch};
      await pump(tester, const HouseholdPage());
      expect(find.text("Finish joining"), findsNothing);
      expect(find.text("Kept until Oct 15, 2026"), findsOneWidget);
      await tester.tap(find.text("Put back this TV's settings from before it joined"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Put back"));
      await tester.pumpAndSettle();
      expect(reviewer.restored, isTrue);
      await leave(tester);
    });
  });
}
