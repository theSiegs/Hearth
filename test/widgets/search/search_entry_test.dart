import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/search/search_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const channel = MethodChannel('me.efesser.flauncher/method');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets("the mic rings in the accent when focused, and select listens", (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == "voiceSearch" ? "dune" : null;
    });
    final submitted = <String>[];
    await tester.pumpWidget(Provider<FLauncherChannel>.value(
      value: FLauncherChannel(),
      child: MaterialApp(home: Scaffold(body: SearchEntry(onSubmit: submitted.add, onCancel: () {}))),
    ));
    await tester.pump();

    final mic = find.byIcon(Icons.mic_none);
    final micFocus = Focus.of(tester.element(mic));
    Color ring() => ((tester.widget<Container>(find.ancestor(of: mic, matching: find.byType(Container)).first).decoration
                as BoxDecoration)
            .border as Border)
        .top
        .color;
    final accent = Theme.of(tester.element(mic)).colorScheme.primary;

    // The box has focus to start with, not the mic
    expect(micFocus.hasFocus, isFalse);
    expect(ring(), Colors.transparent);

    micFocus.requestFocus();
    await tester.pump();
    expect(ring(), accent);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(calls, ["voiceSearch"]);
    expect(submitted, ["dune"]);
  });
}
