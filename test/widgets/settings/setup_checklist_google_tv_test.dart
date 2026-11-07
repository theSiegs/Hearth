import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../setup/fake_setup_channel.dart';

/// Set up Hearth's Google TV group: what's set in Google TV itself, and Google's own limits when Home Assistant runs
/// screen time.
void main() {
  late SharedPreferences prefs;
  late FakeSetupChannel channel;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    channel = FakeSetupChannel()..googleTv = true;
    PackageInfo.setMockInitialValues(
        appName: 'Hearth', packageName: 'com.example.hearth', version: '1', buildNumber: '1', buildSignature: '');
  });

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    // A fresh page each time: it reads the TV as it starts
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(setupTestApp(
        channel, SetupFlowService(prefs), prefs, const Scaffold(body: SetupChecklistPage())));
    await tester.pumpAndSettle();
  }

  testWidgets("profiles and kids' apps are explained, and Open Settings opens Google TV's", (tester) async {
    await open(tester);
    expect(find.text("Google TV's own settings"), findsOneWidget);
    // Not paired: nothing about Google's limits
    expect(find.text("Leave Google's time limits off"), findsNothing);
    await tap(tester, "Profiles and kids' apps");
    expect(find.text("Add everyone in Google TV"), findsOneWidget);
    expect(find.textContaining("For each kid, pick their apps in Google TV"), findsOneWidget);
    await tap(tester, "Open Settings");
    expect(channel.settingsOpened, 1);
  });

  testWidgets("paired: leave Google's limits off; once Hearth saw one lately, it says one is on", (tester) async {
    channel.haPaired = true;
    await open(tester);
    expect(find.text("Leave Google's time limits off"), findsOneWidget);
    expect(find.text("Google TV's own limit is on"), findsNothing);

    channel.googleLimitSeenAt = DateTime.now().subtract(const Duration(days: 1));
    await open(tester);
    expect(find.text("Google TV's own limit is on"), findsOneWidget);
    await tap(tester, "Google TV's own limit is on");
    expect(find.textContaining("Hearth saw Google TV's own time's up screen on this TV lately"), findsOneWidget);
    expect(find.textContaining("Google's own limit wins over Hearth"), findsOneWidget);
  });

  testWidgets("a sighting long ago doesn't count", (tester) async {
    channel.haPaired = true;
    channel.googleLimitSeenAt = DateTime.now().subtract(const Duration(days: 30));
    await open(tester);
    expect(find.text("Google TV's own limit is on"), findsNothing);
    expect(find.text("Leave Google's time limits off"), findsOneWidget);
  });

  testWidgets("not Google TV: no Google TV group", (tester) async {
    channel.googleTv = false;
    await open(tester);
    expect(find.text("Google TV's own settings"), findsNothing);
  });
}
