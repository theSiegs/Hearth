import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The TV as the setup flow sees it: each switch's state, which a test changes as if the owner had flipped it in
/// Android's settings.
class FakeSetupChannel extends FLauncherChannel {
  bool homeButtonOn = false;
  bool homeButtonSeen = false;
  bool restricted = false;
  bool stuck = false;
  bool homeApp = false;
  bool notifications = false;
  bool install = false;
  bool adb = false;

  /// What opening Android's Accessibility screen returns: false when the TV wouldn't open it.
  bool accessibilityOpens = true;

  /// Runs when the owner is sent to Android's Accessibility screen, as if they did something there.
  void Function()? onAccessibilityOpened;

  /// The self-adb fixes run, and whether they work (false: "Allow debugging?" wasn't approved).
  final List<List<String>> fixesRun = [];
  bool fixesWork = true;

  /// The switch Hearth waits for to bring it back from Android's settings.
  String? waitingFor;

  int accessibilityOpened = 0;
  int homeSettingsOpened = 0;

  @override
  Future<bool> isDefaultLauncher() async => homeApp;

  @override
  Future<Map<dynamic, dynamic>> getHomeButtonFixStatus() async => {
        "enabled": homeButtonOn,
        "listedButStopped": stuck,
        "seenBefore": homeButtonSeen,
        "restricted": restricted,
      };

  @override
  Future<bool> checkNotificationListenerPermission() async => notifications;

  @override
  Future<bool> checkInstallPermission() async => install;

  @override
  Future<Map<dynamic, dynamic>> getProfilePairingStatus() async => {"enabled": false, "voiceDefault": false};

  @override
  Future<bool> isAdbEnabled() async => adb;

  @override
  Future<void> setSetupWaitingFor(String? what) async => waitingFor = what;

  @override
  Future<bool> requestAccessibilityPermission() async {
    accessibilityOpened++;
    onAccessibilityOpened?.call();
    return accessibilityOpens;
  }

  @override
  Future<void> openDefaultLauncherSettings() async => homeSettingsOpened++;

  @override
  Future<String?> getLocalIpAddress() async => "192.0.2.10";

  @override
  Future<List<String>?> getSetupFixCommands(String fix) async => switch (fix) {
        "restricted_settings" => ["appops set com.example.hearth ACCESS_RESTRICTED_SETTINGS allow"],
        "home_button_fix" => ["settings put secure enabled_accessibility_services 'x'"],
        _ => null,
      };

  @override
  Future<List<String>> runSetupFixes(List<String> fixes) async {
    fixesRun.add(fixes);
    if (!fixesWork) throw PlatformException(code: "SELF_ADB");
    if (fixes.contains("restricted_settings")) restricted = false;
    if (fixes.contains("home_button_fix")) homeButtonOn = true;
    return [];
  }
}

/// Hearth's providers for the flow, around [child].
Widget setupTestApp(FakeSetupChannel channel, SetupFlowService flow, SharedPreferences prefs, Widget child) =>
    MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider.value(value: flow),
        ChangeNotifierProvider(create: (_) => SettingsService(prefs)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

/// Back from Android's settings: Hearth comes to the front again.
Future<void> comeBack(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}
