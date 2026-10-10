import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/setup/setup_chip.dart';
import 'package:flauncher/widgets/setup/setup_flow_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../helpers.dart';
import '../../mocks.mocks.dart';
import 'fake_setup_channel.dart';

/// The profile check, with listeners that hear it change.
class _Profiles extends MockProfileService with LiveListeners {}

void main() {
  late SharedPreferences prefs;
  late FakeSetupChannel channel;
  late DateTime now;
  late _Profiles profiles;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    now = DateTime(2026, 10, 9, 20);
    channel = FakeSetupChannel();
    profiles = _Profiles();
    when(profiles.settledOnce).thenReturn(true);
    when(profiles.isKidsProfile).thenReturn(false);
    when(profiles.activeProfileKey).thenReturn("user:0");
    PackageInfo.setMockInitialValues(
        appName: 'Hearth', packageName: 'com.example.hearth', version: '1', buildNumber: '1', buildSignature: '');
  });

  /// The home as Hearth builds it: the launcher around it, and the top bar's chip on it.
  Future<SetupFlowService> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final flow = SetupFlowService(prefs, now: () => now);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider.value(value: flow),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
        ChangeNotifierProvider<ProfileService>.value(value: profiles),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SetupFlowLauncher(
          startDelay: Duration.zero,
          child: Scaffold(body: Column(children: [SetupChip(), Text("home")])),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return flow;
  }

  testWidgets("a TV Hearth was never set up on: the flow opens by itself", (tester) async {
    await pumpHome(tester);
    expect(find.text("Welcome to Hearth"), findsOneWidget);
  });

  testWidgets("waits for the first profile check, even when the profile can't be told yet", (tester) async {
    when(profiles.settledOnce).thenReturn(false);
    when(profiles.activeProfileKey).thenReturn(null);
    await pumpHome(tester);
    expect(find.text("Welcome to Hearth"), findsNothing);

    when(profiles.settledOnce).thenReturn(true);
    profiles.changed();
    await tester.pumpAndSettle();
    expect(find.text("Welcome to Hearth"), findsOneWidget);
  });

  testWidgets("an existing install: nothing opens, and it counts as set up", (tester) async {
    channel.homeButtonOn = true;
    channel.homeButtonSeen = true;
    final flow = await pumpHome(tester);
    expect(find.text("Welcome to Hearth"), findsNothing);
    expect(flow.flowVersion, SetupFlowService.currentVersion);
  });

  testWidgets("the Home button lost after an update: the lost screen, in a grown-up's profile", (tester) async {
    channel.homeButtonSeen = true;
    await prefs.setInt("device_setup_flow_version", 1);
    await pumpHome(tester);
    expect(find.text("The update turned the Home button off"), findsOneWidget);
  });

  testWidgets("a kids' profile sees no flow, no lost screen and no chip", (tester) async {
    when(profiles.isKidsProfile).thenReturn(true);
    channel.homeButtonSeen = true;
    await prefs.setInt("device_setup_flow_version", 1);
    await pumpHome(tester);
    expect(find.text("Welcome to Hearth"), findsNothing);
    expect(find.text("The update turned the Home button off"), findsNothing);
    expect(find.byKey(const Key("setup_chip")), findsNothing);
  });

  testWidgets("the lost Home button waits for a grown-up's profile", (tester) async {
    when(profiles.isKidsProfile).thenReturn(true);
    when(profiles.activeProfileKey).thenReturn("user:10");
    channel.homeButtonSeen = true;
    await prefs.setInt("device_setup_flow_version", 1);
    await pumpHome(tester);
    expect(find.text("The update turned the Home button off"), findsNothing);

    when(profiles.isKidsProfile).thenReturn(false);
    when(profiles.activeProfileKey).thenReturn("user:0");
    profiles.changed();
    await tester.pumpAndSettle();
    expect(find.text("The update turned the Home button off"), findsOneWidget);
  });

  testWidgets("Hearth restarted right after a trip to Android's settings: back at that step", (tester) async {
    await prefs.setString("device_setup_resume",
        '{"screen":"homeApp","mode":"full","at":${now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch}}');
    channel.homeButtonOn = true;
    await pumpHome(tester);
    expect(find.text("Not chosen yet"), findsOneWidget);
  });

  group("the chip", () {
    testWidgets("says how much is left and carries on where the flow was left", (tester) async {
      await prefs.setInt("device_setup_flow_version", 1);
      await prefs.setString("device_setup_resume",
          '{"screen":"homeApp","mode":"full","at":${now.subtract(const Duration(days: 1)).millisecondsSinceEpoch},"closed":true}');
      channel.homeButtonOn = true;
      // Updates is all on already: only the home app and the two other cards are left
      channel.install = true;
      channel.hearthTube = true;
      await pumpHome(tester);
      expect(find.text("Finish setting up · 3 left"), findsOneWidget);
      await tester.tap(find.text("Finish setting up · 3 left"));
      await tester.pumpAndSettle();
      expect(find.text("Make Hearth your home app"), findsOneWidget);
    });

    testWidgets("asks for the Home button's fix after it was skipped", (tester) async {
      await prefs.setInt("device_setup_flow_version", 1);
      await prefs.setString("device_setup_decisions", '{"homeButton":{"state":"notNow","at":1}}');
      await pumpHome(tester);
      expect(find.text("Home button needs a fix"), findsOneWidget);
      await tester.tap(find.text("Home button needs a fix"));
      await tester.pumpAndSettle();
      expect(find.text("Make the Home button open Hearth"), findsOneWidget);
    });

    testWidgets("gone when nothing is left, or once hidden", (tester) async {
      await prefs.setInt("device_setup_flow_version", 1);
      await prefs.setBool("device_setup_chip_hidden", true);
      await pumpHome(tester);
      expect(find.byKey(const Key("setup_chip")), findsNothing);
    });
  });
}
