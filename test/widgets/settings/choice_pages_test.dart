import 'package:flauncher/l10n/app_localizations_en.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/animations_sound_page.dart';
import 'package:flauncher/widgets/settings/back_button_action_page.dart';
import 'package:flauncher/widgets/settings/continue_watching_max_items_page.dart';
import 'package:flauncher/widgets/settings/data_usage_period_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_test_app.dart';

/// The switch on the row titled [title].
Finder _switchOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(RoundedSwitchListTile)), matching: find.byType(Switch));

void main() {
  group("BackButtonActionPage", () {
    testWidgets("starts on the action chosen now", (tester) async {
      final settings = await freshSettings();
      await settings.setBackButtonAction(backButtonActionScreensaver);
      await tester.pumpWidget(settingsTestApp(settings, const BackButtonActionPage()));
      await tester.pumpAndSettle();

      expect(find.text("Do nothing"), findsOneWidget);
      expect(find.text("Show clock"), findsOneWidget);
      expect(hasFocusOn(tester, "Show screensaver"), isTrue);
    });

    testWidgets("by default Back does nothing; picking the clock saves it", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const BackButtonActionPage()));
      await tester.pumpAndSettle();
      expect(hasFocusOn(tester, "Do nothing"), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(settings.backButtonAction, backButtonActionClock);
    });
  });

  group("DataUsagePeriodPage", () {
    testWidgets("starts on daily, the default, and saves the period picked", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const DataUsagePeriodPage()));
      await tester.pumpAndSettle();

      expect(find.text("Data Usage Period"), findsOneWidget);
      expect(hasFocusOn(tester, "Daily"), isTrue);

      await tester.tap(find.text("Monthly"));
      await tester.pumpAndSettle();
      expect(settings.dataUsagePeriod, dataUsageMonthly);

      await tester.tap(find.text("Weekly"));
      await tester.pumpAndSettle();
      expect(settings.dataUsagePeriod, dataUsageWeekly);
    });
  });

  group("ContinueWatchingMaxItemsPage", () {
    test("offers 5, 10, 15 (the default), 20 and no limit", () {
      final presets = ContinueWatchingMaxItemsPage.maxItemsPresets(AppLocalizationsEn());
      expect(presets.map((p) => p.$1), [5, 10, 15, 20, 0]);
      expect(presets[2].$3, contains("Default"));
      expect(presets.where((p) => p.$3.contains("Default")), hasLength(1));
      expect(presets[0].$2, "5 Items");
      expect(presets[4].$2, "Unlimited");
    });

    testWidgets("starts on the maximum set now and saves a new one", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const ContinueWatchingMaxItemsPage()));
      await tester.pumpAndSettle();
      expect(hasFocusOn(tester, "15 Items"), isTrue);

      await tester.tap(find.text("Unlimited"));
      await tester.pumpAndSettle();
      expect(settings.continueWatchingMaxItems, 0);
      expect(hasFocusOn(tester, "15 Items"), isTrue, reason: "a tap doesn't move the focus");

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(settings.continueWatchingMaxItems, 10);
    });
  });

  group("AnimationsSoundPage", () {
    testWidgets("all on by default; OK on the first switch turns the highlight animation off", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const AnimationsSoundPage()));
      await tester.pumpAndSettle();

      for (final title in [
        "App card highlight animation",
        "Click sound on key press",
        "App selector transition animation",
      ]) {
        expect(tester.widget<Switch>(_switchOf(title)).value, isTrue, reason: title);
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(settings.appHighlightAnimationEnabled, isFalse);
      expect(settings.appKeyClickEnabled, isTrue);
      expect(tester.widget<Switch>(_switchOf("App card highlight animation")).value, isFalse);
    });

    testWidgets("each switch sets its own setting", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const AnimationsSoundPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Click sound on key press"));
      await tester.pumpAndSettle();
      expect(settings.appKeyClickEnabled, isFalse);
      expect(settings.appSelectorTransitionAnimationEnabled, isTrue);

      await tester.tap(find.text("App selector transition animation"));
      await tester.pumpAndSettle();
      expect(settings.appSelectorTransitionAnimationEnabled, isFalse);
      expect(settings.appHighlightAnimationEnabled, isTrue);
    });
  });
}
