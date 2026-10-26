import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/ha_pair_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

void main() {
  late bool paired;
  late Map<String, Object?> started;
  late List<String> answers;
  late List<String?> urls;
  late int unpaired;

  setUp(() {
    paired = false;
    started = {"pairing_id": "pairing-123", "code": "042137", "expires_in": 600, "nonce": "n" * 40};
    answers = ["pending", "paired"];
    urls = [];
    unpaired = 0;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case "getHaIntegration":
          return {"paired": paired, "url": "http://192.0.2.10:8123"};
        case "startHaPairing":
          urls.add((call.arguments as Map)["url"] as String?);
          return started;
        case "pollHaPairing":
          final answer = answers.length > 1 ? answers.removeAt(0) : answers.first;
          if (answer == "paired") paired = true;
          return answer;
        case "unpairHaIntegration":
          unpaired++;
          paired = false;
          return null;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    await tester.pumpWidget(Provider<FLauncherChannel>.value(
      value: FLauncherChannel(),
      child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: HaPairPage())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("pairs: shows the code, then says it's paired once Home Assistant confirms", (tester) async {
    await pumpPage(tester);
    expect(find.text("Pair"), findsOneWidget);
    await tester.tap(find.text("Pair"));
    await tester.pump();
    await tester.pump();
    expect(urls, ["http://192.0.2.10:8123"]);
    expect(find.text("042137"), findsOneWidget);
    await tester.pump(HaPairPage.pollEvery);
    await tester.pump();
    expect(find.text("042137"), findsOneWidget);
    await tester.pump(HaPairPage.pollEvery);
    await tester.pumpAndSettle();
    expect(find.text("042137"), findsNothing);
    expect(find.textContaining("Paired. This TV reports"), findsOneWidget);
    expect(find.text("Unpair"), findsOneWidget);
  });

  testWidgets("Home Assistant without the household set up says so", (tester) async {
    started = {"error": "not_set_up", "nonce": "n" * 40};
    await pumpPage(tester);
    await tester.tap(find.text("Pair"));
    await tester.pumpAndSettle();
    expect(find.textContaining("no household yet"), findsOneWidget);
    expect(find.text("Pair"), findsOneWidget);
  });

  testWidgets("a request that runs out says to try again", (tester) async {
    answers = ["ended"];
    await pumpPage(tester);
    await tester.tap(find.text("Pair"));
    await tester.pump();
    await tester.pump();
    await tester.pump(HaPairPage.pollEvery);
    await tester.pumpAndSettle();
    expect(find.textContaining("ended before it was confirmed"), findsOneWidget);
    expect(find.text("Pair"), findsOneWidget);
  });

  testWidgets("paired: unpair forgets it on this TV", (tester) async {
    paired = true;
    await pumpPage(tester);
    expect(find.textContaining("paired with Home Assistant at http://192.0.2.10:8123"), findsOneWidget);
    await tester.tap(find.text("Unpair"));
    await tester.pumpAndSettle();
    expect(unpaired, 1);
    expect(find.textContaining("Unpaired."), findsOneWidget);
    expect(find.text("Pair"), findsOneWidget);
  });
}
