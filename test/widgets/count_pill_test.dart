import 'package:flauncher/widgets/count_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Color fill(WidgetTester tester) =>
      (tester.widget<Container>(find.byType(Container).first).decoration as BoxDecoration).color!;

  testWidgets("shows its label and count, and is white only when selected", (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CountPill(label: "Netflix", count: 3, selected: false, onSelected: () {})));
    expect(find.text("Netflix"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
    expect(fill(tester), Colors.white.withValues(alpha: 0.10));

    await tester.pumpWidget(MaterialApp(
        home: CountPill(label: "Netflix", count: 3, selected: true, onSelected: () {})));
    expect(fill(tester), Colors.white);
  });

  testWidgets("focusing it selects it", (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: CountPill(label: "All", count: 5, selected: false, autofocus: true, onSelected: () => selected++)));
    await tester.pump();
    expect(selected, 1);
  });
}
