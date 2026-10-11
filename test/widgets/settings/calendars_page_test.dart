import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/calendars_page.dart';
import 'package:flauncher/widgets/settings/status_bar_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  late SettingsService settings;
  late TvCalendarAccess access;
  late bool granting;
  late int asked;

  CalendarService service() => CalendarService(
        read: (from, to) async => access == TvCalendarAccess.granted
            ? (
                access: access,
                calendars: const [
                  TvCalendar("tv:1", "Family", account: "alex@example.com", color: 0xFF3366CC),
                  TvCalendar("tv:2", "alex@example.com", account: "alex@example.com"),
                ],
                events: const <CalendarEvent>[],
              )
            : (access: access, calendars: const <TvCalendar>[], events: const <CalendarEvent>[]),
        requestAccess: () async {
          asked++;
          if (granting) access = TvCalendarAccess.granted;
          return granting;
        },
        hiddenCalendars: () => settings.hiddenCalendars,
        settings: settings,
      );

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    settings = SettingsService(await SharedPreferences.getInstance());
    access = TvCalendarAccess.granted;
    granting = true;
    asked = 0;
  });

  Widget app(CalendarService calendars, Widget page) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<CalendarService>.value(value: calendars),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routes: {CalendarsPage.routeName: (_) => const Scaffold(body: CalendarsPage())},
          home: Scaffold(body: page),
        ),
      );

  testWidgets("the status bar settings open the calendars", (tester) async {
    await tester.pumpWidget(app(service(), const StatusBarPanelPage()));
    await tester.tap(find.byKey(const Key("settings_calendars")));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarsPage), findsOneWidget);
  });

  testWidgets("lists this profile's calendars with a switch each, per profile", (tester) async {
    await tester.pumpWidget(app(service(), const CalendarsPage()));
    await tester.pumpAndSettle();
    expect(find.text("Family"), findsOneWidget);
    // The account under a calendar named otherwise; not repeated under one named after it
    expect(find.text("alex@example.com"), findsNWidgets(2));
    expect(find.byKey(const Key("calendars_allow")), findsNothing);

    await tester.tap(find.text("Family"));
    await tester.pumpAndSettle();
    expect(settings.hiddenCalendars, ["tv:1"]);
  });

  testWidgets("without access, offers to allow it", (tester) async {
    access = TvCalendarAccess.denied;
    final calendars = service();
    await tester.pumpWidget(app(calendars, const CalendarsPage()));
    await tester.pumpAndSettle();
    expect(find.text("Allow calendar access"), findsOneWidget);
    expect(find.textContaining("only reads them"), findsOneWidget);

    await tester.tap(find.byKey(const Key("calendars_allow")));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(calendars.available, isTrue);
    expect(find.text("Family"), findsOneWidget);
    expect(find.byKey(const Key("calendars_allow")), findsNothing);
  });

  testWidgets("says so when access is turned down", (tester) async {
    access = TvCalendarAccess.denied;
    granting = false;
    await tester.pumpWidget(app(service(), const CalendarsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key("calendars_allow")));
    await tester.pumpAndSettle();
    expect(find.textContaining("Calendar access is turned off"), findsOneWidget);
  });
}
