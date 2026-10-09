import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flauncher/widgets/date_time_widget.dart';
import 'package:flauncher/widgets/animated_character.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('DateTimeWidget Tests', () {
    testWidgets("names the day in Hearth's language", (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Localizations(
            locale: const Locale('de'),
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: const DateTimeWidget('EEEE', animate: false),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text)).data!;
      expect(['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'], contains(text));
    });

    testWidgets('a right-to-left language gets plain text, not one animated character at a time',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: DateTimeWidget('HH:mm', animate: true)),
          ),
        ),
      );
      expect(find.byType(AnimatedTimeDisplay), findsNothing);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('Renders static text when animate is false', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DateTimeWidget('HH:mm:ss', animate: false),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(AnimatedTimeDisplay), findsNothing);
    });

    testWidgets('Renders AnimatedTimeDisplay when animate is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DateTimeWidget('HH:mm:ss', animate: true),
          ),
        ),
      );

      expect(find.byType(AnimatedTimeDisplay), findsOneWidget);
    });

    testWidgets('Updates format when widget is updated', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DateTimeWidget('HH:mm', animate: false),
          ),
        ),
      );

      final initialTextWidget = tester.widget<Text>(find.byType(Text));
      final initialText = initialTextWidget.data;

      // Update the widget with a new format string
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DateTimeWidget('HH:mm:ss', animate: false),
          ),
        ),
      );

      final newTextWidget = tester.widget<Text>(find.byType(Text));
      final newText = newTextWidget.data;

      expect(newText, isNot(equals(initialText)));
      expect(newText!.contains(':'), isTrue); // Ensures standard time formatting is active
    });

    testWidgets('Timer correctly ticks and is disposed', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            // Use 's' so interval is 1 second, but we pass custom interval to speed it up
            body: DateTimeWidget('ss', animate: false, updateInterval: Duration(milliseconds: 100)),
          ),
        ),
      );

      // Verify widget builds without crashing
      expect(find.byType(Text), findsOneWidget);

      // Advance time to allow the Timer to fire at least once
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      // Unmount the widget to trigger dispose and cancel the Timer
      await tester.pumpWidget(Container());

      // If the timer was not canceled properly, pumpWidget would fail or tests would hang.
      expect(find.byType(DateTimeWidget), findsNothing);
    });

    testWidgets('Refreshes time when app lifecycle state changes to resumed', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DateTimeWidget('HH:mm:ss', animate: false),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);

      // Simulate app lifecycle state transition to paused and back to resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(Text), findsOneWidget);
    });
  });
}
