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
}
