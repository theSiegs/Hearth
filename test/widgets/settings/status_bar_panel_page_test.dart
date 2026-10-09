import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/status_bar_panel_page.dart';
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
          child: const Scaffold(body: StatusBarPanelPage()),
        ),
      );

  testWidgets('shows the status bar switches', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
  });

  testWidgets('has no network indicator switch, since the top bar has no network icon', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('Network Indicator'), findsNothing);
    expect(find.byIcon(Icons.signal_wifi_4_bar), findsNothing);
  });
}
