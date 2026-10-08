import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/dock_labels_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  late SettingsService settingsService;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.clear();
    settingsService = SettingsService(sharedPreferences);
  });

  Widget buildSubject() => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<SettingsService>.value(
          value: settingsService,
          child: const Scaffold(body: DockLabelsPage()),
        ),
      );

  testWidgets('dock is on by default, frosted, light, with a shadow', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(settingsService.dockEnabled, isTrue);
    expect(settingsService.dockBlurEnabled, isTrue);
    expect(settingsService.dockDarkBackground, isFalse);
    expect(settingsService.dockShadowEnabled, isTrue);
    expect(find.text('Frosted dock'), findsOneWidget);
  });

  testWidgets('toggles change the dock settings', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Dark dock'));
    await tester.pumpAndSettle();
    expect(settingsService.dockDarkBackground, isTrue);

    await tester.tap(find.text('Frosted dock'));
    await tester.pumpAndSettle();
    expect(settingsService.dockBlurEnabled, isFalse);
  });

  testWidgets('turning the dock off hides its style options', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Favorites dock'));
    await tester.pumpAndSettle();

    expect(settingsService.dockEnabled, isFalse);
    expect(find.text('Frosted dock'), findsNothing);
    expect(find.text('Dock shadow'), findsNothing);
  });
}
