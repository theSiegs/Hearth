import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/continue_watching_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

WatchNextProgram _program(int id, String packageName) => WatchNextProgram(
      id: id,
      packageName: packageName,
      title: "Show $id",
      description: "",
      watchNextType: 0,
      lastEngagementTime: 0,
      playbackPosition: 100,
      duration: 200,
      intentUri: "intent://$packageName",
      posterArtUri: "",
    );

void main() {
  testWidgets("focusing an app's pill shows only that app's programs", (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settingsService = SettingsService(await SharedPreferences.getInstance());
    final appsService = MockAppsService();
    when(appsService.applications).thenReturn([]);
    final watchNextService = MockWatchNextService();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<WatchNextService>.value(value: watchNextService),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContinueWatchingGridPage(programs: [_program(1, "app.a"), _program(2, "app.b"), _program(3, "app.b")]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Show 1"), findsOneWidget);

    Focus.of(tester.element(find.text("app.b"))).requestFocus();
    await tester.pumpAndSettle();

    expect(find.text("Show 1"), findsNothing);
    expect(find.text("Show 2"), findsOneWidget);
    expect(find.text("Show 3"), findsOneWidget);

    await tester.tap(find.text("All"));
    await tester.pumpAndSettle();
    expect(find.text("Show 1"), findsOneWidget);
  });
}
