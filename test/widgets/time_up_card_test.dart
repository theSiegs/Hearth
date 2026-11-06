import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/time_up_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

void main() {
  final now = DateTime(2026, 10, 26, 18, 30);
  int ms(DateTime t) => t.millisecondsSinceEpoch;

  late Map<String, Object?> state;
  late Map<String, Object?> askAnswer;
  late List<Map<dynamic, dynamic>> asks;
  late int refreshes;

  setUp(() {
    state = {
      "paired": true,
      "kids": true,
      "timeUp": [
        {"id": "games", "name": "Games"}
      ],
    };
    askAnswer = {
      "ok": true,
      "request": {"id": "r1", "status": "pending", "minutes": 30, "askedMinutes": 30, "expires": ms(now.add(const Duration(minutes: 30)))},
    };
    asks = [];
    refreshes = 0;
  });

  Future<void> pump(WidgetTester tester, {String? heldGroup, String? fallback}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case "getHaLockState":
          return state;
        case "askForMoreTime":
          asks.add(call.arguments as Map);
          return askAnswer;
        case "refreshHaStatus":
          refreshes++;
          return null;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    final settings = MockSettingsService();
    when(settings.accentColor).thenReturn(Colors.orange);
    await tester.pumpWidget(ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: TimeUpCard(channel: FLauncherChannel(), heldGroup: heldGroup, fallback: fallback, clock: () => now),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("time up: asks for the held group's minutes and says it's waiting for an adult", (tester) async {
    await pump(tester, heldGroup: "Games");
    expect(find.text("Time's up for Games today"), findsOneWidget);
    expect(find.text("Ask an adult for more time"), findsOneWidget);
    for (final minutes in [15, 30, 45, 60]) {
      expect(find.text("$minutes min"), findsOneWidget);
    }
    await tester.tap(find.text("30 min"));
    await tester.pumpAndSettle();
    expect(asks, [
      {"minutes": 30, "group": "games"}
    ]);
    expect(find.text("Asked for 30 min; waiting for an adult"), findsOneWidget);
    // Waiting: the buttons don't ask again
    await tester.tap(find.text("15 min"));
    await tester.pumpAndSettle();
    expect(asks, hasLength(1));
    // And it asks Home Assistant for a fresh answer meanwhile
    await tester.pump(const Duration(seconds: 20));
    expect(refreshes, 1);
  });

  testWidgets("the answer shows once Home Assistant's state carries it", (tester) async {
    state["request"] = {"id": "r1", "status": "approved", "minutes": 45, "askedMinutes": 30, "answered": ms(now)};
    await pump(tester);
    expect(find.text("An adult added 45 min"), findsOneWidget);
    state["request"] = {"id": "r1", "status": "expired", "minutes": 30, "askedMinutes": 30, "answered": ms(now)};
    FLauncherChannel.haStateVersion.value++;
    await tester.pumpAndSettle();
    expect(find.text("No adult answered in time. You can ask again."), findsOneWidget);
  });

  testWidgets("not now: the kid waits out the cooldown", (tester) async {
    state["request"] = {
      "id": "r1",
      "status": "denied",
      "minutes": 30,
      "answered": ms(now.subtract(const Duration(minutes: 3))),
    };
    await pump(tester);
    expect(find.text("You can ask again in 7 min"), findsOneWidget);
    await tester.tap(find.text("15 min"));
    await tester.pumpAndSettle();
    expect(asks, isEmpty);
  });

  testWidgets("the server's cooldown and errors are said", (tester) async {
    askAnswer = {"ok": false, "error": "cooldown", "retryIn": 300};
    await pump(tester, heldGroup: "Games");
    await tester.tap(find.text("15 min"));
    await tester.pumpAndSettle();
    expect(find.text("You can ask again in 5 min"), findsOneWidget);
  });

  testWidgets("a profile Home Assistant doesn't know can't ask", (tester) async {
    askAnswer = {"ok": false, "error": "no_person"};
    await pump(tester, heldGroup: "Games");
    await tester.tap(find.text("15 min"));
    await tester.pumpAndSettle();
    expect(find.textContaining("isn't set up in Home Assistant"), findsOneWidget);
  });

  testWidgets("not paired: no button, and the home's own words", (tester) async {
    state = {"paired": false, "kids": true, "timeUp": []};
    await pump(tester, fallback: "Nothing to watch right now");
    expect(find.text("Nothing to watch right now"), findsOneWidget);
    expect(find.text("Ask an adult for more time"), findsNothing);
  });

  testWidgets("a pause says why and until when, with no asking", (tester) async {
    state["pause"] = {"reason": "Dinner", "until": ms(DateTime(2026, 10, 26, 19))};
    await pump(tester, heldGroup: "Games");
    expect(find.text("Paused: Dinner"), findsOneWidget);
    expect(find.text("Until 7:00 PM"), findsOneWidget);
    expect(find.text("Ask an adult for more time"), findsNothing);
  });

  testWidgets("bedtime says so, with no asking", (tester) async {
    state["lock"] = {"kind": "bedtime", "until": ms(DateTime(2026, 10, 27, 7))};
    await pump(tester);
    expect(find.text("It's bedtime"), findsOneWidget);
    expect(find.text("Until 7:00 AM"), findsOneWidget);
    expect(find.text("Ask an adult for more time"), findsNothing);
  });
}
