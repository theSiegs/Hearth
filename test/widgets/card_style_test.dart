import 'package:flauncher/widgets/card_style.dart';
import 'package:flauncher/widgets/focus_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardStyle', () {
    test('radius, zoom and shadow per style', () {
      expect(CardStyle.of('classic').radius, 0);
      expect(CardStyle.of('classic').focusScale, 1.0);
      expect(CardStyle.of('classic').focusElevation, 8);
      expect(CardStyle.of('minimal').focusElevation, 6);
      expect(CardStyle.of('premium').focusScale, 1.15);
      expect(CardStyle.of('glow').glow, isTrue);
      expect(CardStyle.of('squircle').innerBorderRadius, BorderRadius.circular(22));
      expect(CardStyle.of('classic').innerBorderRadius, BorderRadius.zero);
      expect(CardStyle.of('unknown'), same(CardStyle.of('modern')));
    });

    test('the zoom spreads at most 14 px each side', () {
      final style = CardStyle.of('premium');
      expect(style.focusScaleFor(100), 1.15);
      expect(style.focusScaleFor(280), closeTo(1.1, 0.0001));
      expect(style.focusScaleFor(1000), closeTo(1.028, 0.0001));
      expect(style.focusScaleFor(0), 1.15);
    });

    test('only the glow style colours the shadow', () {
      const accent = Color(0xFF00FF00);
      expect(CardStyle.of('glow').focusShadowColor(accent), accent.withOpacity(0.85));
      expect(CardStyle.of('modern').focusShadowColor(accent), Colors.black);
    });
  });

  group('FocusHighlight', () {
    Widget highlight(String theme, {bool animate = true, Color accent = Colors.red}) => Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 90,
            child: FocusHighlight(style: CardStyle.of(theme), accentColor: accent, animate: animate),
          ),
        );

    Iterable<Border> borders(WidgetTester tester) => tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration).border as Border);

    testWidgets('draws one accent line for the single-line styles', (tester) async {
      await tester.pumpWidget(highlight('classic'));
      expect(borders(tester).map((b) => (b.top.color, b.top.width)), [(Colors.red, 4.0)]);
    });

    testWidgets('draws nothing for premium', (tester) async {
      await tester.pumpWidget(highlight('premium'));
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('draws a steady accent line over a black one with the animation off', (tester) async {
      await tester.pumpWidget(highlight('modern', animate: false));
      expect(borders(tester).map((b) => b.top.color), [Colors.red, Colors.black]);
      await tester.pump(const Duration(milliseconds: 600));
      expect(borders(tester).map((b) => b.top.color), [Colors.red, Colors.black]);
    });

    testWidgets('keeps pulsing the same way through rebuilds', (tester) async {
      await tester.pumpWidget(highlight('modern'));
      await tester.pump(const Duration(milliseconds: 1500)); // past the top, fading again
      final double fading = borders(tester).first.top.color.opacity;

      await tester.pumpWidget(highlight('modern', accent: Colors.red.shade400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(borders(tester).first.top.color.opacity, lessThan(fading));
    });
  });
}
