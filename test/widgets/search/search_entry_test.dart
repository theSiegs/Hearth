import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/search/search_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const channel = MethodChannel('me.efesser.flauncher/method');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<List<String>> pump(WidgetTester tester, List<String> calls, {required bool voice}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == "voiceSearch" ? "dune" : null;
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

  testWidgets("the box has no mic button of its own (the keyboard has one)", (tester) async {
    final calls = <String>[];
    await pump(tester, calls, voice: false);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(calls, isNot(contains("voiceSearch")));
  });
}
