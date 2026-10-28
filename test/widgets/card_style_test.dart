import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/card_style.dart';
import 'package:flauncher/widgets/focus_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

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

  group('FocusCardFrame', () {
    Future<void> frame(WidgetTester tester, {required bool highlighted, bool hideOutline = false}) {
      final settings = MockSettingsService();
      when(settings.themes).thenReturn('classic');
      when(settings.accentColor).thenReturn(Colors.red);
      when(settings.hideHighlightOutlineOnHomescreen).thenReturn(hideOutline);
      when(settings.appHighlightAnimationEnabled).thenReturn(false);
      when(settings.appSelectorTransitionAnimationEnabled).thenReturn(false);
      return tester.pumpWidget(ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: FocusCardFrame(
                highlighted: highlighted, scale: highlighted ? 1.1 : 1.0, width: 160, height: 90, children: const []),
          ),
        ),
      ));
    }

    double dim(WidgetTester tester) => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    testWidgets('a focused card grows, lifts, drops its dimming and gets the outline', (tester) async {
      await frame(tester, highlighted: true);
      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(container.transform!.getMaxScaleOnAxis(), closeTo(1.1, 0.0001));
      expect(tester.widget<Material>(find.byType(Material)).elevation, CardStyle.of('classic').focusElevation);
      expect(dim(tester), 0);
      expect(find.byType(FocusHighlight), findsOneWidget);
    });

    testWidgets('an unfocused card is dimmed, flat and has no outline', (tester) async {
      await frame(tester, highlighted: false);
      expect(tester.widget<Material>(find.byType(Material)).elevation, 0);
      expect(dim(tester), 0.10);
      expect(find.byType(FocusHighlight), findsNothing);
    });

    testWidgets('the outline stays off when the setting hides it', (tester) async {
      await frame(tester, highlighted: true, hideOutline: true);
      expect(find.byType(FocusHighlight), findsNothing);
    });
  });
}
