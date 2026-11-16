import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/keyboard/hearth_keyboard.dart';
import 'package:flauncher/widgets/search/search_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const channel = MethodChannel('me.efesser.flauncher/method');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<List<String>> pump(WidgetTester tester, List<String> calls,
      {required bool voice, String keyboard = "onscreen", bool phone = false}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        "voiceSearch" => "dune",
        "getKeyboardStatus" => {"kind": keyboard, "phone": phone, "canSwitch": false, "onScreen": null},
        _ => null,
      };
    });
    final submitted = <String>[];
    await tester.pumpWidget(Provider<FLauncherChannel>.value(
      value: FLauncherChannel(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SearchEntry(onSubmit: submitted.add, onCancel: () {}, voice: voice)),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return submitted;
  }

  testWidgets("the remote's voice search listens right away and searches what was said", (tester) async {
    final calls = <String>[];
    final submitted = await pump(tester, calls, voice: true);
    expect(calls, contains("voiceSearch"));
    expect(submitted, ["dune"]);
  });

  testWidgets("the mic sits next to the box, and listens when pressed", (tester) async {
    final calls = <String>[];
    final submitted = await pump(tester, calls, voice: false);
    expect(calls, isNot(contains("voiceSearch")));
    await tester.tap(find.byKey(const ValueKey("searchMic")));
    await tester.pumpAndSettle();
    expect(calls, contains("voiceSearch"));
    expect(submitted, ["dune"]);
  });

  testWidgets("with the TV's on-screen keyboard, no keys of Hearth's own", (tester) async {
    final calls = <String>[];
    await pump(tester, calls, voice: false);
    await tester.pumpAndSettle();
    expect(calls, contains("getKeyboardStatus"));
    expect(find.byType(HearthKeyboard), findsNothing);
  });

  testWidgets("a phone's keyboard stuck with no phone there: Hearth's keys, no phone offered", (tester) async {
    final calls = <String>[];
    final submitted = await pump(tester, calls, voice: false, keyboard: "phone");
    await tester.pumpAndSettle();
    expect(find.byType(HearthKeyboard), findsOneWidget);
    expect(find.text("Type on your phone"), findsNothing);
    expect(find.textContaining("you can type there too"), findsNothing);
    for (final c in ["u", "p"]) {
      await tester.tap(find.text(c));
      await tester.pump();
    }
    await tester.tap(find.text("Search"));
    await tester.pump();
    expect(submitted, ["up"]);
  });

  testWidgets("a phone remote there: Hearth's keys first, the phone offered too", (tester) async {
    final calls = <String>[];
    await pump(tester, calls, voice: false, keyboard: "phone", phone: true);
    await tester.pumpAndSettle();
    expect(find.byType(HearthKeyboard), findsOneWidget);
    expect(find.text("Type on your phone"), findsOneWidget);
    expect(find.textContaining("you can type there too"), findsOneWidget);
  });
}
