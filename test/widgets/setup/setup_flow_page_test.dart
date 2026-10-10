import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/setup/setup_flow_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fake_setup_channel.dart';

void main() {
  late SharedPreferences prefs;
  late SetupFlowService flow;
  late FakeSetupChannel channel;
  late DateTime now;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    now = DateTime(2026, 10, 9, 20);
    flow = SetupFlowService(prefs, now: () => now);
    channel = FakeSetupChannel();
    PackageInfo.setMockInitialValues(
        appName: 'Hearth', packageName: 'com.example.hearth', version: '1', buildNumber: '1', buildSignature: '');
  });

  /// Opens the flow over a home page, as Hearth does.
  Future<void> open(WidgetTester tester, {SetupMode mode = SetupMode.full, String? startAt, bool resumed = false}) async {
    // A TV's screen: 1920x1080 at twice the density
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(setupTestApp(
      channel,
      flow,
      prefs,
      Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => SetupFlowPage.open(context, mode: mode, startAt: startAt, resumed: resumed),
              child: const Text("home"),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text("home"));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group("welcome", () {
    testWidgets("Get started goes to the Home button, and OK presses the focused button", (tester) async {
      await open(tester);
      expect(find.text("Welcome to Hearth"), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text("Make the Home button open Hearth"), findsOneWidget);
      expect(flow.resume?.screen, "homeButton");
    });

    testWidgets("each screen starts on its main button, so OK alone goes through", (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(channel.accessibilityOpened, 1);
    });

    testWidgets("Set up later closes the flow and leaves it to the chip", (tester) async {
      await open(tester);
      await press(tester, "Set up later");
      expect(find.text("Welcome to Hearth"), findsNothing);
      expect(flow.flowVersion, SetupFlowService.currentVersion);
      expect(flow.resume?.closed, isTrue);
    });
  });

  group("the Home button", () {
    Future<void> openAtHomeButton(WidgetTester tester) async {
      await open(tester);
      await press(tester, "Get started");
    }

    testWidgets("turned on in Android's settings: says so, then moves on by itself", (tester) async {
      channel.onAccessibilityOpened = () => channel.homeButtonOn = true;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      expect(channel.accessibilityOpened, 1);
      // Home Button Fix brings Hearth back when it starts
      expect(channel.waitingFor, "home_button_fix");
      await comeBack(tester);
      expect(find.text("The Home button now opens Hearth"), findsOneWidget);
      expect(channel.waitingFor, isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text("Make Hearth your home app"), findsOneWidget);
    });

    testWidgets("not turned on: offers to try again", (tester) async {
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      expect(find.text("It's not on yet"), findsOneWidget);
      await press(tester, "Try again");
      expect(channel.accessibilityOpened, 2);
    });

    testWidgets("listed as on but not running: says to turn it off and on", (tester) async {
      channel.onAccessibilityOpened = () => channel.stuck = true;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      expect(find.text("It's on but not running"), findsOneWidget);
    });

    testWidgets("blocked by Android: the computer's commands, and it notices the switch going on", (tester) async {
      channel.restricted = true;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      expect(find.text("Android blocked this switch"), findsOneWidget);
      expect(find.textContaining("ACCESS_RESTRICTED_SETTINGS allow"), findsOneWidget);
      expect(find.text("adb connect 192.0.2.10"), findsOneWidget);
      // Debugging is off: Hearth can't fix it itself
      expect(find.text("Let Hearth fix it"), findsNothing);

      // Run from a computer, then switched on
      channel.homeButtonOn = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text("The Home button now opens Hearth"), findsOneWidget);
    });

    testWidgets("blocked, with debugging on: Hearth shows what it will run, then fixes it", (tester) async {
      channel.restricted = true;
      channel.adb = true;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      await press(tester, "Let Hearth fix it");
      // Nothing runs before the parent has seen the commands and said so
      expect(channel.fixesRun, isEmpty);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining("appops set com.example.hearth ACCESS_RESTRICTED_SETTINGS allow")),
          findsOneWidget);
      await press(tester, "Run it");
      expect(channel.fixesRun, [
        ["restricted_settings", "home_button_fix"]
      ]);
      expect(find.text("The Home button now opens Hearth"), findsOneWidget);
    });

    testWidgets("Hearth's fix without the debugging approval: says what to do", (tester) async {
      channel.restricted = true;
      channel.adb = true;
      channel.fixesWork = false;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      await press(tester, "Let Hearth fix it");
      await press(tester, "Run it");
      expect(find.text("Hearth couldn't do it"), findsOneWidget);
    });

    testWidgets("the screen won't open: the adb command instead", (tester) async {
      channel.accessibilityOpens = false;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      expect(find.textContaining("enabled_accessibility_services"), findsOneWidget);
    });

    testWidgets("skipping asks once, and is remembered", (tester) async {
      await openAtHomeButton(tester);
      await press(tester, "Skip");
      expect(find.text("Skip the Home button?"), findsOneWidget);
      await press(tester, "Skip anyway");
      expect(find.text("Make Hearth your home app"), findsOneWidget);
      expect(flow.choiceFor(SetupFlowService.homeButtonDecision), SetupChoice.notNow);
    });

    testWidgets("already on: not asked for", (tester) async {
      channel.homeButtonOn = true;
      await open(tester);
      await press(tester, "Get started");
      expect(find.text("Make Hearth your home app"), findsOneWidget);
    });
  });

  group("picking up where it was left", () {
    testWidgets("back on the Home button screen with the switch now on: says so", (tester) async {
      channel.homeButtonOn = true;
      await open(tester, startAt: "homeButton", resumed: true);
      expect(find.text("The Home button now opens Hearth"), findsOneWidget);
    });

    testWidgets("back on the Home button screen with the switch still off: not on yet", (tester) async {
      await open(tester, startAt: "homeButton", resumed: true);
      expect(find.text("It's not on yet"), findsOneWidget);
    });
  });

  group("the home app", () {
    testWidgets("chosen in Android's picker: says so", (tester) async {
      channel.homeButtonOn = true;
      await open(tester);
      await press(tester, "Get started");
      channel.homeApp = true;
      await press(tester, "Choose Hearth");
      expect(channel.homeSettingsOpened, 1);
      await comeBack(tester);
      expect(find.text("Hearth is your home app"), findsOneWidget);
    });
  });

  group("finish", () {
    testWidgets("everything on: Finish says so, and nothing is left to resume", (tester) async {
      channel.homeButtonOn = true;
      channel.homeApp = true;
      await open(tester);
      await press(tester, "Get started");
      expect(find.text("Hearth is ready"), findsOneWidget);
      expect(flow.resume, isNull);
      expect(flow.flowVersion, SetupFlowService.currentVersion);
      await press(tester, "Go to my home");
      expect(find.text("Hearth is ready"), findsNothing);
    });

    testWidgets("Finish later keeps the place for the chip", (tester) async {
      await open(tester);
      await press(tester, "Get started");
      await press(tester, "Finish later");
      expect(find.text("Make the Home button open Hearth"), findsNothing);
      expect(flow.resume?.screen, "homeButton");
      expect(flow.resume?.closed, isTrue);
    });
  });

  group("after an update turned the Home button off", () {
    testWidgets("only the Home button screen, worded for the update", (tester) async {
      channel.homeButtonSeen = true;
      await open(tester, mode: SetupMode.lostFix);
      expect(find.text("The update turned the Home button off"), findsOneWidget);
      expect(find.text("Finish later"), findsNothing);
      await press(tester, "Not now");
      expect(flow.choiceFor(SetupFlowService.lostFixDecision), SetupChoice.notNow);
      expect(flow.resume, isNull);
    });
  });
}
