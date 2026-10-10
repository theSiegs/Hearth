import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late SetupFlowService flow;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    now = DateTime(2026, 10, 9, 20);
    flow = SetupFlowService(prefs, now: () => now);
  });

  test("keeps everything under device_setup_, so no layout or backup carries it", () async {
    await flow.saveResume("homeButton", SetupMode.full);
    await flow.decide("watching", SetupChoice.on);
    await flow.close();
    expect(prefs.getKeys(), isNotEmpty);
    expect(prefs.getKeys().every(SetupFlowService.isSetupKey), isTrue);
  });

  test("remembers where the flow was, in which mode and when", () async {
    expect(flow.resume, isNull);
    await flow.saveResume("homeApp", SetupMode.rerun);
    final resume = flow.resume!;
    expect(resume.screen, "homeApp");
    expect(resume.mode, SetupMode.rerun);
    expect(resume.at, now);
    expect(resume.closed, isFalse);
  });

  test("Finish later keeps the place but won't reopen by itself; Finish forgets it", () async {
    await flow.saveResume("homeButton", SetupMode.full);
    await flow.close();
    expect(flow.resume?.screen, "homeButton");
    expect(flow.resume?.closed, isTrue);
    expect(flow.flowVersion, SetupFlowService.currentVersion);

    await flow.finish();
    expect(flow.resume, isNull);
    expect(flow.seenVersion, SetupFlowService.currentVersion);
  });

  test("stores choices, and forgets one when told to", () async {
    await flow.decide(SetupFlowService.homeButtonDecision, SetupChoice.notNow);
    await flow.decide("watching", SetupChoice.on);
    expect(flow.choiceFor(SetupFlowService.homeButtonDecision), SetupChoice.notNow);
    expect(flow.decisions["watching"]?.at, now);
    await flow.decide(SetupFlowService.homeButtonDecision, null);
    expect(flow.choiceFor(SetupFlowService.homeButtonDecision), isNull);
    expect(flow.choiceFor("watching"), SetupChoice.on);
  });

  test("a damaged value reads as nothing rather than failing", () async {
    await prefs.setString("device_setup_resume", "{not json");
    await prefs.setString("device_setup_decisions", "[]");
    expect(flow.resume, isNull);
    expect(flow.decisions, isEmpty);
  });

  group("what the home opens", () {
    SetupLaunch launch(SetupFlowService flow,
            {bool kids = false, bool on = false, bool seen = false, bool pin = false}) =>
        flow.launch(kids: kids, homeButtonOn: on, homeButtonSeenBefore: seen, hasParentPin: pin);

    test("a TV Hearth was never set up on: the whole flow", () {
      expect(launch(flow), isA<SetupLaunchFirstRun>());
    });

    test("never in a kids' profile, whatever is pending", () async {
      expect(launch(flow, kids: true), isA<SetupLaunchNothing>());
      expect(launch(flow, kids: true, seen: true), isA<SetupLaunchNothing>());
    });

    test("Hearth in use before the flow existed: marked as through it, nothing shown", () async {
      expect(launch(flow, seen: true, on: true), isA<SetupLaunchExistingInstall>());
      expect(launch(flow, pin: true), isA<SetupLaunchExistingInstall>());
      await prefs.setString("device_layout_owner", "user:0");
      expect(launch(SetupFlowService(prefs, now: () => now)), isA<SetupLaunchExistingInstall>());

      await flow.markExistingInstall({SetupCard.watching: true});
      expect(flow.flowVersion, SetupFlowService.currentVersion);
      // Each card from the TV's state: on when all on already, otherwise Not now
      expect(flow.cardChoice(SetupCard.watching), SetupChoice.on);
      expect(flow.cardChoice(SetupCard.tv), SetupChoice.notNow);
      expect(flow.cardChoice(SetupCard.updates), SetupChoice.notNow);
      expect(launch(flow, seen: true, on: true), isA<SetupLaunchNothing>());
    });

    test("a layout saved by this start's own profile check isn't a sign of an earlier setup", () async {
      final fresh = SetupFlowService(prefs, now: () => now);
      await prefs.setString("device_layout_owner", "user:0");
      expect(launch(fresh), isA<SetupLaunchFirstRun>());
    });

    test("picks up a step left for Android's settings within 30 minutes, not later", () async {
      await flow.saveResume("homeButton", SetupMode.full);
      now = now.add(const Duration(minutes: 29));
      final resumed = launch(flow);
      expect(resumed, isA<SetupLaunchResume>());
      expect((resumed as SetupLaunchResume).resume.screen, "homeButton");

      now = now.add(const Duration(minutes: 2));
      expect(launch(flow), isA<SetupLaunchNothing>());
    });

    test("a first run interrupted long ago leaves it to the chip, not to a new first run", () async {
      await flow.saveResume("homeApp", SetupMode.full);
      now = now.add(const Duration(hours: 5));
      expect(launch(flow), isA<SetupLaunchNothing>());
    });

    test("Finish later isn't picked up by itself", () async {
      await flow.saveResume("homeButton", SetupMode.full);
      await flow.close();
      expect(launch(flow), isA<SetupLaunchNothing>());
    });

    test("an update switched the Home button off: takes over until Not now, and again after the next loss", () async {
      await flow.finish();
      expect(launch(flow, seen: true), isA<SetupLaunchLostFix>());
      await flow.decide(SetupFlowService.lostFixDecision, SetupChoice.notNow);
      expect(launch(flow, seen: true), isA<SetupLaunchNothing>());

      // Turned back on, then lost again
      expect(launch(flow, seen: true, on: true), isA<SetupLaunchNothing>());
      await Future<void>.delayed(Duration.zero);
      expect(launch(flow, seen: true), isA<SetupLaunchLostFix>());
    });
  });

  group("the chip", () {
    test("counts the essentials neither on nor skipped", () async {
      const allOn = {SetupCard.watching: true, SetupCard.tv: true, SetupCard.updates: true};
      expect(flow.remaining(homeButtonOn: false, homeAppOn: false, cardOn: allOn), 2);
      await flow.decide(SetupFlowService.homeAppDecision, SetupChoice.notNow);
      expect(flow.remaining(homeButtonOn: false, homeAppOn: false, cardOn: allOn), 1);
      expect(flow.remaining(homeButtonOn: true, homeAppOn: false, cardOn: allOn), 0);
    });

    test("counts the cards nobody decided on that aren't all on anyway", () async {
      expect(flow.remaining(homeButtonOn: true, homeAppOn: true), SetupCard.values.length);
      expect(flow.remaining(homeButtonOn: true, homeAppOn: true, cardOn: {SetupCard.updates: true}),
          SetupCard.values.length - 1);
      await flow.decide(SetupCard.watching.name, SetupChoice.notNow);
      await flow.decide(SetupCard.tv.name, SetupChoice.on);
      expect(flow.remaining(homeButtonOn: true, homeAppOn: true, cardOn: {SetupCard.updates: true}), 0);
    });

    test("asks for a fix when the Home button was skipped or lost", () async {
      expect(flow.homeButtonNeedsFix(homeButtonOn: false, homeButtonSeenBefore: false), isFalse);
      expect(flow.homeButtonNeedsFix(homeButtonOn: false, homeButtonSeenBefore: true), isTrue);
      await flow.decide(SetupFlowService.homeButtonDecision, SetupChoice.notNow);
      expect(flow.homeButtonNeedsFix(homeButtonOn: false, homeButtonSeenBefore: false), isTrue);
      expect(flow.homeButtonNeedsFix(homeButtonOn: true, homeButtonSeenBefore: true), isFalse);
    });

    test("shows only once the flow has run, never for kids, and not once hidden", () async {
      expect(flow.chipAllowed(kids: false), isFalse);
      await flow.close();
      expect(flow.chipAllowed(kids: false), isTrue);
      expect(flow.chipAllowed(kids: true), isFalse);
      await flow.hideChip();
      expect(flow.chipAllowed(kids: false), isFalse);
    });
  });
}
