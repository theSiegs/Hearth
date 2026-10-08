import 'package:flauncher/providers/home_search.dart';
import 'package:flauncher/widgets/search/search_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  BoxDecoration pill(WidgetTester tester, String label) => tester
      .widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
      .decoration as BoxDecoration;
  bool selected(WidgetTester tester, String label) => pill(tester, label).color == Colors.white;
  double ringWidth(WidgetTester tester, String label) => (pill(tester, label).border as Border).top.width;

  testWidgets("focusing a pill selects it, and so do select and a tap", (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => HomeSearch(installed: (_) => false),
        child: const SearchGridPage(),
      ),
    ));
    await tester.pump();

    // With nothing to show, the first pill has focus
    expect(selected(tester, "Watch now"), isTrue);
    expect(ringWidth(tester, "Watch now"), 3);
    expect(ringWidth(tester, "Rent or buy"), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected(tester, "Watch now"), isFalse);
    expect(selected(tester, "Rent or buy"), isTrue);
    expect(ringWidth(tester, "Watch now"), 1);
    expect(ringWidth(tester, "Rent or buy"), 3);

    await tester.tap(find.text("Other apps"));
    await tester.pump();
    expect(selected(tester, "Other apps"), isTrue);
    expect(selected(tester, "Rent or buy"), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected(tester, "Rent or buy"), isTrue);
  });
}
