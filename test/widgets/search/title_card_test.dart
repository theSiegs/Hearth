import 'package:flauncher/widgets/search/title_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double scaleOf(WidgetTester tester, String text) =>
      tester.widget<AnimatedScale>(find.ancestor(of: find.text(text), matching: find.byType(AnimatedScale))).scale;

  testWidgets("a TitleCard lifts when focused, and select or a tap presses it", (tester) async {
    final pressed = <String>[];
    final focusChanges = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          TitleCard(
            title: "Dune",
            detail: "2021",
            autofocus: true,
            onPressed: () => pressed.add("Dune"),
            onFocusChange: focusChanges.add,
          ),
          TitleCard(title: "Arrival", detail: "", onPressed: () => pressed.add("Arrival")),
        ]),
      ),
    ));
    await tester.pump();
    expect(scaleOf(tester, "Dune"), 1.06);
    expect(scaleOf(tester, "Arrival"), 1.0);
    expect(focusChanges, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(pressed, ["Dune"]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(scaleOf(tester, "Dune"), 1.0);
    expect(scaleOf(tester, "Arrival"), 1.06);
    expect(focusChanges, [true, false]);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.tap(find.text("Dune"));
    expect(pressed, ["Dune", "Arrival", "Dune"]);
  });

  testWidgets("a MoreCard lifts when focused, and select or a tap presses it", (tester) async {
    int presses = 0;
    final focusChanges = <bool>[];
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoreCard(
          label: "See all",
          detail: "12 titles",
          focusNode: focusNode,
          onPressed: () => presses++,
          onFocusChange: focusChanges.add,
        ),
      ),
    ));
    expect(scaleOf(tester, "See all"), 1.0);

    focusNode.requestFocus();
    await tester.pump();
    expect(scaleOf(tester, "See all"), 1.06);
    expect(focusChanges, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text("See all"));
    expect(presses, 2);
  });
}
