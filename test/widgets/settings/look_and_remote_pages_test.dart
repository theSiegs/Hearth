import 'package:flauncher/widgets/settings/accent_color_page.dart';
import 'package:flauncher/widgets/settings/animations_sound_page.dart';
import 'package:flauncher/widgets/settings/back_button_action_page.dart';
import 'package:flauncher/widgets/settings/card_style_page.dart';
import 'package:flauncher/widgets/settings/dock_labels_page.dart';
import 'package:flauncher/widgets/settings/look_settings_page.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flauncher/widgets/settings/remote_search_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_test_app.dart';

/// A stand-in page per route, saying which one was opened.
Map<String, WidgetBuilder> _stubRoutes(List<String> names) =>
    {for (final name in names) name: (_) => Scaffold(body: Text("opened $name"))};

void main() {
  group("LookSettingsPage", () {
    final routes = _stubRoutes([
      CardStylePage.routeName,
      AccentColorPage.routeName,
      DockLabelsPage.routeName,
      AnimationsSoundPage.routeName,
    ]);

    testWidgets("lists its four pages, starting on Card style with the style chosen now", (tester) async {
      final settings = await freshSettings();
      await settings.setThemes("glow");
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();

      expect(find.text("Look"), findsOneWidget);
      expect(find.text("Accent Color"), findsOneWidget);
      expect(find.text("Dock & labels"), findsOneWidget);
      expect(find.text("Animations & sound"), findsOneWidget);
      expect(find.text("Glow"), findsOneWidget);
      expect(hasFocusOn(tester, "Card style"), isTrue);
    });

    testWidgets("the trailing style name follows the setting", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();
      expect(find.text("Default"), findsOneWidget);

      await settings.setThemes("capsule");
      await tester.pumpAndSettle();
      expect(find.text("Capsule"), findsOneWidget);
      expect(find.text("Default"), findsNothing);
    });

    testWidgets("an unknown saved style shows no name rather than failing", (tester) async {
      final settings = await freshSettings();
      await settings.setThemes("retired-style");
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();
      expect(find.text("Card style"), findsOneWidget);
      expect(find.text("retired-style"), findsNothing);
    });

    testWidgets("each tile opens its own page", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text("opened ${CardStylePage.routeName}"), findsOneWidget);

      for (final (label, route) in [
        ("Accent Color", AccentColorPage.routeName),
        ("Dock & labels", DockLabelsPage.routeName),
        ("Animations & sound", AnimationsSoundPage.routeName),
      ]) {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text("opened $route"), findsOneWidget, reason: label);
      }
    });
  });

  group("RemoteSearchSettingsPage", () {
    final routes = _stubRoutes([RemoteButtonsPage.routeName, BackButtonActionPage.routeName]);

    testWidgets("starts on Remote buttons and opens it", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const RemoteSearchSettingsPage(), routes: routes));
      await tester.pumpAndSettle();

      expect(find.text("Remote"), findsOneWidget);
      expect(hasFocusOn(tester, "Remote buttons"), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text("opened ${RemoteButtonsPage.routeName}"), findsOneWidget);
    });

    testWidgets("Down then OK opens the Back button page", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const RemoteSearchSettingsPage(), routes: routes));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(hasFocusOn(tester, "Back button action"), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text("opened ${BackButtonActionPage.routeName}"), findsOneWidget);
    });
  });
}
