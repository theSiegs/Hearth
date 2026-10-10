import 'package:flauncher/providers/home_looks.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/setup/setup_frame.dart';
import 'package:flauncher/widgets/setup/setup_flow_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fake_setup_channel.dart';

void main() {
  /// The marks beside a card's items (not the progress strip's)
  Finder itemMarks(IconData icon) =>
      find.descendant(of: find.byType(SetupStatusList), matching: find.byIcon(icon));

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

    testWidgets("Allow debugging? declined: Hearth stops waiting and says what to do", (tester) async {
      channel.restricted = true;
      channel.adb = true;
      channel.fixesHang = true;
      await openAtHomeButton(tester);
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      await press(tester, "Let Hearth fix it");
      // Settling runs the clock on while the spinner turns: past the limit, it gives up and says so
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

  group("your family", () {
    /// Past the essentials (both on) to the family card, on Google TV.
    Future<void> openAtFamily(WidgetTester tester) async {
      channel.homeButtonOn = true;
      channel.homeApp = true;
      channel.googleTv = true;
      await open(tester);
      await press(tester, "Get started");
    }

    Future<void> typePin(WidgetTester tester) async {
      for (final key in [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit8,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pumpAndSettle();
    }

    testWidgets("only on Google TV", (tester) async {
      await openAtFamily(tester);
      expect(find.text("Streaming apps open on the right person, and kids can't change Hearth."), findsOneWidget);
      await press(tester, "Not now");
      expect(flow.cardChoice(SetupCard.family), SetupChoice.notNow);
      expect(find.text("Pick up where you left off, and see what's playing."), findsOneWidget);
    });

    testWidgets("a parent PIN, chosen twice on the row pad", (tester) async {
      await openAtFamily(tester);
      await press(tester, "Turn on");
      expect(find.text("Choose a parent PIN"), findsOneWidget);
      await press(tester, "Choose PIN");
      await typePin(tester);
      await typePin(tester);
      expect(find.text("The parent PIN is set"), findsOneWidget);
      expect(SettingsService(prefs).verifyParentPin("2468"), isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text("Pick the right profile in streaming apps"), findsOneWidget);
    });

    testWidgets("Profile Pairing: Android's switch, then how pairing works; Netflix also needs Hearth voice",
        (tester) async {
      channel.netflix = true;
      await SettingsService(prefs).setParentPin("1357");
      channel.onAccessibilityOpened = () => channel.pairing = true;
      await openAtFamily(tester);
      await press(tester, "Turn on");
      // The PIN is set already: straight to pairing
      expect(find.text("Pick the right profile in streaming apps"), findsOneWidget);
      await press(tester, "Open Accessibility");
      expect(channel.waitingFor, "profile_pairing");
      await comeBack(tester);
      expect(find.text("Profile Pairing is on"), findsOneWidget);
      // It waits for Next: there's something to read
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text("Profile Pairing is on"), findsOneWidget);
      await press(tester, "Next");
      expect(find.text("One more step for Netflix"), findsOneWidget);
      channel.voice = true;
      await press(tester, "Open Settings");
      expect(channel.voiceSettingsOpened, 1);
      await comeBack(tester);
      expect(find.text("Hearth voice is on"), findsOneWidget);
    });

    testWidgets("Profile Pairing blocked by Android, with debugging on: Hearth lifts the block and turns it on",
        (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.restricted = true;
      channel.adb = true;
      await openAtFamily(tester);
      await press(tester, "Turn on");
      await press(tester, "Open Accessibility");
      await comeBack(tester);
      expect(find.text("Android blocked this switch"), findsOneWidget);
      await press(tester, "Let Hearth fix it");
      await press(tester, "Run it");
      expect(channel.fixesRun, [
        ["restricted_settings", "profile_pairing"]
      ]);
      expect(find.text("Profile Pairing is on"), findsOneWidget);
    });

    testWidgets("kids' profiles: turn on debugging, then Hearth goes on them from the screen that says what it does",
        (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.pairing = true;
      channel.kidsProfiles = 2;
      await openAtFamily(tester);
      expect(find.text("Hearth kept on your kids' profiles"), findsOneWidget);
      await press(tester, "Turn on");
      expect(find.text("Turn on debugging first"), findsOneWidget);
      await press(tester, "Open About");
      expect(channel.aboutOpened, 1);
      channel.adb = true;
      await comeBack(tester);
      expect(find.text("Keep Hearth on your kids' profiles"), findsOneWidget);

      // The screen says what it does: one press, no question after it
      expect(channel.profilesAdded, 0);
      await press(tester, "Add to their profiles");
      expect(channel.profilesAdded, 1);
      expect(find.text("Hearth is on your kids' profiles"), findsOneWidget);
      expect(find.text("Ready"), findsNWidgets(2));
      expect(flow.kidsProtected, 2);
    });

    testWidgets("kids' profiles where Hearth didn't stay: says so, with Try again", (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.pairing = true;
      channel.kidsProfiles = 1;
      channel.adb = true;
      channel.profilesKept = false;
      await openAtFamily(tester);
      await press(tester, "Turn on");
      await press(tester, "Add to their profiles");
      expect(find.text("Hearth isn't on every kids' profile yet"), findsOneWidget);
      expect(find.text("Needs a fix"), findsOneWidget);
      expect(find.textContaining("Hearth isn't on it"), findsOneWidget);
      expect(flow.kidsProtected, 0);
      channel.profilesKept = true;
      await press(tester, "Try again");
      expect(find.text("Hearth is on your kids' profiles"), findsOneWidget);
    });

    testWidgets("kids' profiles without the debugging approval: says what to do", (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.pairing = true;
      channel.kidsProfiles = 1;
      channel.adb = true;
      channel.profilesWork = false;
      await openAtFamily(tester);
      await press(tester, "Turn on");
      await press(tester, "Add to their profiles");
      expect(find.text("Hearth is on your kids' profiles"), findsNothing);
      expect(find.text("Couldn't change the kids' profiles"), findsOneWidget);
      expect(flow.kidsProtected, 0);
    });

    testWidgets("on before, with a new kids' profile: Set up what's missing goes on to the kids' step", (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      await flow.decide(SetupCard.family.name, SetupChoice.on);
      channel.pairing = true;
      channel.kidsProfiles = 1;
      channel.adb = true;
      await openAtFamily(tester);
      // The PIN and pairing are checked, the kids' item isn't
      expect(itemMarks(Icons.check_circle), findsNWidgets(2));
      expect(itemMarks(Icons.radio_button_unchecked), findsOneWidget);
      await press(tester, "Set up what's missing");
      expect(find.text("Keep Hearth on your kids' profiles"), findsOneWidget);
    });

    testWidgets("Hearth on the kids' profiles already (put there from Settings) counts as done", (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.pairing = true;
      channel.kidsProfiles = 2;
      channel.kidsReady = 2;
      await openAtFamily(tester);
      expect(itemMarks(Icons.radio_button_unchecked), findsNothing);
      expect(find.text("Next"), findsOneWidget);
    });

    testWidgets("all on already: each item is checked, and Next goes on", (tester) async {
      await SettingsService(prefs).setParentPin("1357");
      channel.pairing = true;
      await openAtFamily(tester);
      expect(find.text("Next"), findsOneWidget);
      expect(find.text("Set up what's missing"), findsNothing);
      expect(find.text("What it needs"), findsNothing);
    });
  });

  group("the cards", () {
    /// Past the essentials (both on) to the first card.
    Future<void> openAtCards(WidgetTester tester) async {
      channel.homeButtonOn = true;
      channel.homeApp = true;
      await open(tester);
      await press(tester, "Get started");
    }

    testWidgets("Not now records the choice and goes to the next card, past the card's steps", (tester) async {
      await openAtCards(tester);
      expect(find.text("Pick up where you left off, and see what's playing."), findsOneWidget);
      await press(tester, "Not now");
      expect(flow.cardChoice(SetupCard.watching), SetupChoice.notNow);
      expect(find.text("Pick a look"), findsOneWidget);
      expect(channel.watchNextAsked, 0);
    });

    testWidgets("Watching: Android's question turns the row on, then notification access", (tester) async {
      await openAtCards(tester);
      await press(tester, "Turn on");
      expect(flow.cardChoice(SetupCard.watching), SetupChoice.on);
      expect(find.text("Continue Watching"), findsWidgets);
      await press(tester, "Turn on");
      expect(channel.watchNextAsked, 1);
      expect(find.text("Continue Watching is on"), findsOneWidget);
      expect(prefs.getBool("show_continue_watching"), isTrue);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text("What's playing and notifications"), findsOneWidget);
      channel.notifications = true;
      await press(tester, "Open Settings");
      expect(channel.notificationSettingsOpened, 1);
      // The notification listener brings Hearth back when it connects
      expect(channel.waitingFor, "notification_access");
      await comeBack(tester);
      expect(find.text("Notifications are on"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text("Pick a look"), findsOneWidget);
    });

    testWidgets("Continue Watching declined: where to find it, and Hearth's own fix with debugging on",
        (tester) async {
      channel.watchNextAnswer = false;
      channel.adb = true;
      await openAtCards(tester);
      await press(tester, "Turn on");
      await press(tester, "Turn on");
      expect(find.text("Android didn't allow it"), findsOneWidget);
      await press(tester, "Let Hearth fix it");
      expect(channel.fixesRun, isEmpty);
      await press(tester, "Run it");
      expect(channel.fixesRun, [
        ["watch_next"]
      ]);
      expect(find.text("Continue Watching is on"), findsOneWidget);
    });

    testWidgets("TV & power: sleep choices need the Home button; Start on boot is on and can be turned off",
        (tester) async {
      channel.homeApp = true;
      await open(tester, startAt: "tv");
      expect(find.text("Turn the TV off when nobody's watching?"), findsOneWidget);
      // Without Home Button Fix, the choices can't be picked
      await tester.tap(find.text("2 hours"), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(channel.idleMinutes, 0);
      expect(find.textContaining("Home button switch"), findsOneWidget);

      final settings = SettingsService(prefs);
      expect(settings.startOnBoot, isTrue);
      await press(tester, "Start Hearth when the TV starts");
      expect(SettingsService(prefs).startOnBoot, isFalse);
      await press(tester, "Next");
      expect(flow.cardChoice(SetupCard.tv), SetupChoice.on);
    });

    testWidgets("TV & power with the Home button on: picks how long", (tester) async {
      channel.homeButtonOn = true;
      await open(tester, startAt: "tv");
      await press(tester, "2 hours");
      expect(channel.idleMinutes, 120);
    });

    testWidgets("Updates: allow installs, then HearthTube can wait", (tester) async {
      channel.homeButtonOn = true;
      await open(tester, startAt: "updates");
      await press(tester, "Turn on");
      expect(find.text("Allow Hearth to install updates"), findsOneWidget);
      channel.install = true;
      await press(tester, "Open Settings");
      expect(channel.installSettingsOpened, 1);
      await comeBack(tester);
      expect(find.text("Hearth can install updates"), findsOneWidget);
      await press(tester, "Next");
      expect(find.text("Install HearthTube?"), findsOneWidget);
      await press(tester, "Not now");
      expect(find.text("Hearth is ready"), findsOneWidget);
    });

    testWidgets("Leave it as it is on a card skipped before goes past it", (tester) async {
      await flow.decide(SetupCard.watching.name, SetupChoice.notNow);
      await openAtCards(tester);
      await press(tester, "Leave it as it is");
      expect(find.text("Pick a look"), findsOneWidget);
      expect(channel.watchNextAsked, 0);
      expect(flow.cardChoice(SetupCard.watching), SetupChoice.notNow);
    });

    testWidgets("a skipped card shows what's off, and Set up what's missing goes through its steps", (tester) async {
      await flow.decide(SetupCard.watching.name, SetupChoice.notNow);
      await openAtCards(tester);
      expect(find.text("Skipped"), findsNothing);
      expect(itemMarks(Icons.radio_button_unchecked), findsNWidgets(2));
      await press(tester, "Set up what's missing");
      expect(flow.cardChoice(SetupCard.watching), SetupChoice.on);
      await press(tester, "Turn on");
      expect(channel.watchNextAsked, 1);
    });

    testWidgets("a rerun starts at the first card when the essentials are on", (tester) async {
      channel.homeButtonOn = true;
      channel.homeApp = true;
      await open(tester, mode: SetupMode.rerun);
      expect(find.text("Pick up where you left off, and see what's playing."), findsOneWidget);
    });
  });

  group("your home", () {
    testWidgets("the focused look shows on the home; Keep current puts the home back", (tester) async {
      await SettingsService(prefs).setThemes("classic");
      await open(tester, startAt: "look");
      expect(find.text("Pick a look"), findsOneWidget);
      // Focus starts on Hearth's own look (the home matches none), shown behind the card
      expect(HomeLook.hearth.matches(SettingsService(prefs)), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(HomeLook.photo.matches(SettingsService(prefs)), isTrue);
      // Focus moves on from the look previewed: what the home had stays the starting point
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(HomeLook.calmDark.matches(SettingsService(prefs)), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(HomeLook.bold.matches(SettingsService(prefs)), isTrue);
      expect(find.text("Now"), findsNothing);

      await press(tester, "Keep current");
      final settings = SettingsService(prefs);
      expect(settings.themes, "classic");
      expect(settings.bingWallpaperEnabled, isFalse);
      expect(flow.cardChoice(SetupCard.home), SetupChoice.on);
      expect(flow.look, isNull);
      // The weather needs nothing here (no weather service): on to Smart home
      expect(find.text("I use Home Assistant"), findsOneWidget);
    });

    testWidgets("a preview cut off by a restart is put back when the look screen shows again", (tester) async {
      final settings = SettingsService(prefs);
      await settings.setThemes("classic");
      final before = HomeLookSnapshot.of(settings);
      // Hearth stopped while Bold was previewed: the home still shows it
      await HomeLook.bold.apply(settings);
      await flow.setLookPreview(HomeLook.bold, before);
      await open(tester, startAt: "look");
      await press(tester, "Keep current");
      expect(SettingsService(prefs).themes, "classic");
      expect(flow.lookPreview, isNull);
    });

    testWidgets("a look picked is kept, and is where new grown-up profiles start", (tester) async {
      await open(tester, startAt: "look");
      await tester.tap(find.text("Bold"));
      await tester.pumpAndSettle();
      expect(HomeLook.bold.matches(SettingsService(prefs)), isTrue);
      expect(flow.look, HomeLook.bold);
      expect(flow.cardChoice(SetupCard.home), SetupChoice.on);
    });

    testWidgets("the look the home has now says so", (tester) async {
      await HomeLook.calmDark.apply(SettingsService(prefs));
      await open(tester, startAt: "look");
      expect(find.text("Now"), findsOneWidget);
      await press(tester, "Use this look");
      expect(flow.look, HomeLook.calmDark);
    });

    testWidgets("another grown-up's first visit: only the look, and their pick is their own", (tester) async {
      await open(tester, mode: SetupMode.look);
      expect(find.text("Pick a look for your home"), findsOneWidget);
      await tester.tap(find.text("Calm dark"));
      await tester.pumpAndSettle();
      expect(find.text("Pick a look for your home"), findsNothing);
      expect(HomeLook.calmDark.matches(SettingsService(prefs)), isTrue);
      expect(flow.look, isNull);
      expect(flow.resume, isNull);
    });

    testWidgets("Back on another grown-up's look card leaves their home as it was", (tester) async {
      await open(tester, mode: SetupMode.look);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("Pick a look for your home"), findsNothing);
      expect(SettingsService(prefs).bingWallpaperEnabled, isFalse);
    });
  });

  group("smart home", () {
    testWidgets("Not now goes on to TV & power", (tester) async {
      await open(tester, startAt: "smartHome");
      expect(find.text("Doorbell and other alerts on the TV, and your Home Assistant dashboard one press away."),
          findsOneWidget);
      await press(tester, "Not now");
      expect(flow.cardChoice(SetupCard.smartHome), SetupChoice.notNow);
      expect(find.text("Turn the TV off when nobody's watching?"), findsOneWidget);
    });

    testWidgets("alerts, the dashboard and TV status, the last two from the phone", (tester) async {
      await open(tester, startAt: "smartHome");
      await press(tester, "I use Home Assistant");
      expect(find.textContaining("192.0.2.10"), findsOneWidget);
      await press(tester, "Turn on");
      expect(channel.haAlerts, isTrue);
      expect(find.text("Alerts are on"), findsOneWidget);
      // Without Home Button Fix the test can't show: that's what's said
      await press(tester, "Send a test notification");
      expect(find.textContaining("Home Button Fix"), findsOneWidget);
      await press(tester, "Next");

      expect(find.text("Your dashboard on the TV"), findsOneWidget);
      await press(tester, "Set up from your phone");
      expect(find.text("http://192.0.2.10:8765/secret"), findsOneWidget);
      channel.haPanelToken = true;
      channel.haSetupReceived = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text("Your dashboard is set up"), findsOneWidget);
      expect(SettingsService(prefs).haPanelEnabled, isTrue);
      await press(tester, "Next");

      expect(find.text("Tell Home Assistant what's on"), findsOneWidget);
      // Sent without a webhook ID: says what's missing
      await press(tester, "Set up from your phone");
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining("didn't send a webhook ID"), findsOneWidget);
      channel.haWebhook = "hearth_tv";
      await press(tester, "Set up from your phone");
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text("The TV tells Home Assistant what's on"), findsOneWidget);
    });
  });

  group("finish", () {
    testWidgets("everything on: Finish says so, and nothing is left to resume", (tester) async {
      channel.homeButtonOn = true;
      channel.homeApp = true;
      channel.watchNext = true;
      channel.notifications = true;
      channel.install = true;
      channel.hearthTube = true;
      await prefs.setBool("show_continue_watching", true);
      await open(tester);
      await press(tester, "Get started");
      // The cards that are all on say so, with Next
      expect(find.text("Watching"), findsWidgets);
      await press(tester, "Next");
      await press(tester, "Keep current");
      await press(tester, "Not now");
      await press(tester, "Next");
      await press(tester, "Next");
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
