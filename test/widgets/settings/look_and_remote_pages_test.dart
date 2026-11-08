import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/settings/accent_color_page.dart';
import 'package:flauncher/widgets/settings/animations_sound_page.dart';
import 'package:flauncher/widgets/settings/back_button_action_page.dart';
import 'package:flauncher/widgets/settings/card_style_page.dart';
import 'package:flauncher/widgets/settings/dock_labels_page.dart';
import 'package:flauncher/widgets/settings/look_settings_page.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flauncher/widgets/settings/remote_search_settings_page.dart';
import 'package:flauncher/widgets/settings/settings_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';
import 'settings_test_app.dart';

/// A stand-in page per route, saying which one was opened.
Map<String, WidgetBuilder> _stubRoutes(List<String> names) => {
  for (final name in names) name: (_) => Scaffold(body: Text("opened $name")),
};

void main() {
  group("LookSettingsPage", () {
    final routes = _stubRoutes([
      CardStylePage.routeName,
      AccentColorPage.routeName,
      DockLabelsPage.routeName,
      AnimationsSoundPage.routeName,
    ]);

    testWidgets("lists its four pages and the Glint home switch, starting on Card style with the style chosen now", (
      tester,
    ) async {
      final settings = await freshSettings();
      await settings.setThemes("glow");
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();

      expect(find.text("Look"), findsOneWidget);
      expect(find.text("Accent Color"), findsOneWidget);
      expect(find.text("Dock & labels"), findsOneWidget);
      expect(find.text("Animations & sound"), findsOneWidget);
      expect(find.text("Glow"), findsOneWidget);
      expect(find.text("Glint home"), findsOneWidget);
      expect(hasFocusOn(tester, "Card style"), isTrue);
    });

    testWidgets("the Glint home switch turns the Glint home on and off", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();
      expect(settings.glintHome, isFalse);

      await tester.tap(find.text("Glint home"));
      await tester.pumpAndSettle();
      expect(settings.glintHome, isTrue);
    });

    testWidgets("with the Glint home on, Glint motion shows its level and select steps through them", (tester) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();
      expect(find.text("Glint motion"), findsNothing);

      await settings.setGlintHome(true);
      await tester.pumpAndSettle();
      expect(find.text("Glint motion"), findsOneWidget);
      expect(find.text("Easy"), findsOneWidget);

      await tester.tap(find.text("Glint motion"));
      await tester.pumpAndSettle();
      expect(settings.glintMotion, "calm");
      expect(find.text("Calm"), findsOneWidget);

      await settings.setGlintMotion("still");
      await tester.tap(find.text("Glint motion"));
      await tester.pumpAndSettle();
      expect(settings.glintMotion, "lively");
    });

    testWidgets("Peek tiles show their place, select steps through them, and they go with the Glint home", (
      tester,
    ) async {
      final settings = await freshSettings();
      await tester.pumpWidget(settingsTestApp(settings, const LookSettingsPage(), routes: routes));
      await tester.pumpAndSettle();
      expect(find.text("Peek tiles"), findsOneWidget);

      await tester.tap(find.text("Peek tiles"));
      await tester.pumpAndSettle();
      expect(settings.peek, "row");
      expect(find.text("Above the dock"), findsOneWidget);

      await settings.setPeek("headline");
      await tester.tap(find.text("Peek tiles"));
      await tester.pumpAndSettle();
      expect(settings.peek, "shelf");
      expect(find.text("Top shelf + glance page"), findsOneWidget);

      await tester.tap(find.text("Peek tiles"));
      await tester.pumpAndSettle();
      expect(settings.peek, "off");

      // The Glint home has no dock to sit over
      await settings.setGlintHome(true);
      await tester.pumpAndSettle();
      expect(find.text("Peek tiles"), findsNothing);
    });

    group("Family and house", () {
      MockProfileService profile({required bool kids, String? key = "user:10"}) {
        final p = MockProfileService();
        when(p.isKidsProfile).thenReturn(kids);
        when(p.settledOnce).thenReturn(true);
        when(p.activeProfileKey).thenReturn(key);
        return p;
      }

      /// The Look page in a profile, Settings unlocked by a parent or not; [shown] reports what the glance page would do.
      Widget app(SettingsService settings, ProfileService profiles, {bool unlocked = false, List<bool>? shown}) =>
          ChangeNotifierProvider<ProfileService>.value(
            value: profiles,
            child: settingsTestApp(
              settings,
              SettingsUnlock(
                notifier: ValueNotifier(unlocked),
                child: Column(
                  children: [
                    Builder(builder: (context) {
                      shown?.add(householdTilesShown(context));
                      return const SizedBox.shrink();
                    }),
                    const Expanded(child: LookSettingsPage()),
                  ],
                ),
              ),
              routes: routes,
            ),
          );

      testWidgets("on in an adult's profile, and the adult can turn it off", (tester) async {
        final settings = await freshSettings();
        final shown = <bool>[];
        await tester.pumpWidget(app(settings, profile(kids: false), shown: shown));
        await tester.pumpAndSettle();
        expect(find.text("Family and house"), findsOneWidget);
        expect(settings.householdTiles(kids: false), isTrue);
        expect(shown.last, isTrue);

        await tester.tap(find.text("Family and house"));
        await tester.pumpAndSettle();
        expect(settings.householdTiles(kids: false), isFalse);
        expect(shown.last, isFalse);
      });

      testWidgets("a kids profile doesn't see the switch, and the tiles are off there", (tester) async {
        final settings = await freshSettings();
        final shown = <bool>[];
        await tester.pumpWidget(app(settings, profile(kids: true), shown: shown));
        await tester.pumpAndSettle();
        expect(find.text("Family and house"), findsNothing);
        expect(find.text("Glint home"), findsOneWidget, reason: "the kid's own look is still theirs");
        expect(shown.last, isFalse);
      });

      testWidgets("an adult can turn them on for a kids profile, past the parent PIN", (tester) async {
        final settings = await freshSettings();
        final shown = <bool>[];
        // Settings unlocked by a parent (an unlock holds for the profile it was made in; this one, with no key, for any)
        await tester.pumpWidget(app(settings, profile(kids: true, key: null), unlocked: true, shown: shown));
        await tester.pumpAndSettle();
        expect(shown.last, isFalse);
        expect(find.text("Family and house"), findsOneWidget);
        await tester.tap(find.text("Family and house"));
        await tester.pumpAndSettle();
        expect(settings.householdTiles(kids: true), isTrue);
        expect(shown.last, isTrue);
      });

      test("unset, it follows the profile; once chosen, it's the choice", () async {
        final settings = await freshSettings();
        expect(settings.householdTiles(kids: false), isTrue);
        expect(settings.householdTiles(kids: true), isFalse);
        await settings.setHouseholdTiles(false);
        expect(settings.householdTiles(kids: false), isFalse);
        await settings.setHouseholdTiles(true);
        expect(settings.householdTiles(kids: true), isTrue);
        expect(settings.settingKeys, contains("household_tiles"), reason: "per profile, in its layout and backups");
      });
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
