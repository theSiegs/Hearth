import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/profile_pairing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockFLauncherChannel channel;
  late SettingsService settings;
  late MockProfileService profiles;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    settings = SettingsService(await SharedPreferences.getInstance());
    channel = MockFLauncherChannel();
    // Alex's profile is on: only its own PIN shows
    profiles = MockProfileService();
    when(profiles.activeProfileKey).thenReturn("user:0");
    when(channel.getProfilePairingChoices("com.example.tv")).thenAnswer((_) async => [
          {"hearthProfile": "user:0", "displayName": "Alex", "kids": false, "mode": "profile", "chosenProfile": "Alex M"},
          {"hearthProfile": "user:11", "displayName": "Sam", "kids": false, "mode": "auto", "autoMatch": "Sam"},
          {"hearthProfile": "user:12", "displayName": "Jordan", "kids": true, "mode": "profile", "chosenProfile": "Kids"},
        ]);
    when(channel.getProfilePinStatus("com.example.tv", "Alex M"))
        .thenAnswer((_) async => {"status": "rejected", "paused": false});
    when(channel.profilePinEntrySupported("com.example.tv")).thenAnswer((_) async => true);
  });

  Widget buildSubject() => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            Provider<FLauncherChannel>.value(value: channel),
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<ProfileService>.value(value: profiles),
          ],
          child: const Scaffold(
            body: ProfilePairingAppPage(app: {
              "packageName": "com.example.tv",
              "label": "Example TV",
              "seenProfiles": ["Alex M", "Kids"],
            }),
          ),
        ),
      );

  testWidgets("only the profile on now, paired by an explicit choice, gets a PIN row", (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text("Profile PIN: Alex M"), findsOneWidget);
    expect(find.text("Saved — not accepted last time"), findsOneWidget);
    expect(find.textContaining("Profile PIN: Kids"), findsNothing);
    verifyNever(channel.getProfilePinStatus("com.example.tv", "Kids"));
  });

  testWidgets("saving a PIN needs a parent PIN first", (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.text("Profile PIN: Alex M"));
    await tester.pumpAndSettle();

    expect(find.textContaining("Set a parent PIN first"), findsOneWidget);
    verifyNever(channel.saveProfilePin(any, any, any));
  });

  testWidgets("an app Hearth can't type in yet says so", (tester) async {
    when(channel.profilePinEntrySupported("com.example.tv")).thenAnswer((_) async => false);
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text("Saved — not accepted last time · Hearth can’t type PINs in Example TV yet"), findsOneWidget);
  });
}
