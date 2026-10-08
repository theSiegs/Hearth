import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester, {ShapeBorder? splashShape}) async {
    int presses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusableTap(
          autofocus: true,
          onPressed: () => presses++,
          splashShape: splashShape,
          builder: (context, focused) => Text(focused ? "focused" : "not focused"),
        ),
      ),
    ));
    await tester.pump();
    return () => presses;
  }

  testWidgets("select and a tap both press it, and the builder sees focus", (tester) async {
    final presses = await pump(tester);
    expect(find.text("focused"), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(presses(), 1);

    await tester.tap(find.text("focused"));
    expect(presses(), 2);
  });

  testWidgets("with a splash it is still a single focus stop", (tester) async {
    final presses = await pump(tester, splashShape: const StadiumBorder());
    expect(find.byType(InkWell), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).canRequestFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text("focused"));
    expect(presses(), 2);
  });
}
