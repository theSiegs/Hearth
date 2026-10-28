import 'package:flauncher/widgets/settings/date_time_format_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'settings_test_app.dart';

/// 3:45 PM, the time the time presets' examples are written for.
final _afternoon = DateTime(2026, 1, 17, 15, 45);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group("presets", () {
    test("each date example is what its format shows (17 January 2026)", () {
      for (final (format, example) in dateFormatPresets) {
        if (format.contains("E")) continue; // weekday examples: see below
        expect(DateFormat(format, "en").format(_afternoon), example, reason: format);
      }
    });

    test("each weekday example is what its format shows for the same date", () {
      // The examples say Friday, 17 January; in 2026 (the year the other examples show) that is a Saturday
      final day = DateTime(2025, 1, 17);
      for (final (format, example) in dateFormatPresets.where((p) => p.$1.contains("E"))) {
        expect(DateFormat(format, "en").format(day), example, reason: format);
      }
      expect(DateFormat("EEE", "en").format(DateTime(2026, 1, 17)), "Sat");
    });

    test("12-hour time examples are what their formats show at 3:45 PM", () {
      expect(DateFormat("hh:mm", "en").format(_afternoon), "03:45");
      expect(DateFormat("h:mm a", "en").format(_afternoon), "3:45 PM");
      expect(DateFormat("hh:mm a", "en").format(_afternoon), "03:45 PM");
      expect(DateFormat("HH:mm", "en").format(_afternoon), "15:45");
      for (final (format, example) in timeFormatPresets) {
        expect(DateFormat(format, "en").format(_afternoon), example, reason: format);
      }
    });

    test("the 12-hour preset without AM/PM shows 3:45 at 3:45 PM", () {
      expect(timeFormatPresets.map((p) => p.$1), contains("h:mm"));
      expect(DateFormat("h:mm", "en").format(_afternoon), "3:45");
    });

    test("formats are not offered twice", () {
      expect(dateFormatPresets.map((p) => p.$1).toSet(), hasLength(dateFormatPresets.length));
      expect(timeFormatPresets.map((p) => p.$1).toSet(), hasLength(timeFormatPresets.length));
    });
  });

  group("DateTimeFormatPage", () {
    testWidgets("starts on the date format chosen now and shows both sections", (tester) async {
      final settings = await freshSettings();
      await settings.setDateTimeFormat("d MMMM", "HH:mm");
      await tester.pumpWidget(settingsTestApp(settings, const DateTimeFormatPage()));
      await tester.pumpAndSettle();

      expect(find.text("Date and time format"), findsOneWidget);
      expect(find.text("Date"), findsOneWidget);
      expect(find.text("Time"), findsOneWidget);
      expect(hasFocusOn(tester, "17 January"), isTrue);
    });

    testWidgets("a saved format that isn't a preset starts on the first one", (tester) async {
      final settings = await freshSettings();
      await settings.setDateTimeFormat("yyyy-MM-dd", "HH:mm");
      await tester.pumpWidget(settingsTestApp(settings, const DateTimeFormatPage()));
      await tester.pumpAndSettle();

      expect(hasFocusOn(tester, dateFormatPresets.first.$2), isTrue);
    });

    testWidgets("picking a date keeps the time format, and picking a time keeps the date format", (tester) async {
      final settings = await freshSettings();
      await settings.setDateTimeFormat("EEE, MMM d", "h:mm a");
      await tester.pumpWidget(settingsTestApp(settings, const DateTimeFormatPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text("17/01/2026"));
      await tester.pumpAndSettle();
      expect(settings.dateFormat, "dd/MM/y");
      expect(settings.timeFormat, "h:mm a");

      await tester.scrollUntilVisible(find.text("15:45"), 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text("15:45"));
      await tester.pumpAndSettle();
      expect(settings.dateFormat, "dd/MM/y");
      expect(settings.timeFormat, "HH:mm");
    });

    testWidgets("the preview shows the date and time in the formats chosen", (tester) async {
      final settings = await freshSettings();
      await settings.setDateTimeFormat("M/d/y", "HH:mm");
      await tester.pumpWidget(settingsTestApp(settings, const DateTimeFormatPage()));
      await tester.pumpAndSettle();

      final preview = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .firstWhere((d) => d != null && d.contains(" — "))!
          .split(" — ");
      expect(preview[0], DateFormat("M/d/y", "en").format(DateTime.now()));
      expect(preview[1], matches(RegExp(r"^\d\d:\d\d$")));
    });

    testWidgets("without formats the preview asks for them", (tester) async {
      final settings = await freshSettings();
      await settings.setDateTimeFormat("", "");
      await tester.pumpWidget(settingsTestApp(settings, const DateTimeFormatPage()));
      await tester.pumpAndSettle();

      expect(find.text("Select formats below"), findsOneWidget);
    });
  });
}
