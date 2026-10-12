import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/home_agenda.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/calendar_agenda.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../mocks.mocks.dart';

final DateTime now = DateTime(2026, 10, 10, 14, 0); // a Saturday afternoon

/// A timed event as Hearth's Android side reads it from the TV's calendar store.
Map<String, Object?> timed(String title, DateTime start, DateTime end) => {
      "calendarId": 1,
      "calendarName": "Family",
      "title": title,
      "start": start.millisecondsSinceEpoch,
      "end": end.millisecondsSinceEpoch,
      "allDay": false,
    };

/// An all-day event: the store keeps its days as midnights in UTC.
Map<String, Object?> allDay(String title, DateTime day) => {
      "calendarId": 1,
      "calendarName": "Family",
      "title": title,
      "start": DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch,
      "end": DateTime.utc(day.year, day.month, day.day + 1).millisecondsSinceEpoch,
      "allDay": true,
    };

/// A service that has read [events] from one "Family" calendar on the TV (or may not read the calendars).
Future<CalendarService> calendarService(List<Map<String, Object?>> events, {bool allowed = true}) async {
  final service = CalendarService(
    read: (from, to) async => allowed
        ? (
            access: TvCalendarAccess.granted,
            calendars: CalendarParser.parseCalendars([
              {"id": 1, "name": "Family", "account": "alex@example.com"}
            ]),
            events: CalendarParser.parseEvents(events),
          )
        : (access: TvCalendarAccess.denied, calendars: const <TvCalendar>[], events: const <CalendarEvent>[]),
    hiddenCalendars: () => const [],
    now: () => now,
  );
  await service.refresh();
  return service;
}

void main() {
  late MockSettingsService settings;

  setUp(() {
    settings = MockSettingsService();
    when(settings.timeFormat).thenReturn("h:mm a");
  });

  Widget app(Widget child, {CalendarService? service, HomeAgenda? agenda, List<SingleChildWidget> more = const []}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          if (service != null) ChangeNotifierProvider<CalendarService>.value(value: service),
          if (agenda != null) ChangeNotifierProvider<HomeAgenda>.value(value: agenda),
          ...more,
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  group("today over the home", () {
    testWidgets("shows what's left of today, all-day events first, in the clock's time format", (tester) async {
      final service = await calendarService([
        timed("Breakfast", DateTime(2026, 10, 10, 8), DateTime(2026, 10, 10, 9)),
        timed("Movie night", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21)),
        timed("Soccer", DateTime(2026, 10, 10, 13, 30), DateTime(2026, 10, 10, 15)),
        allDay("Birthday", DateTime(2026, 10, 10)),
        timed("Dentist", DateTime(2026, 10, 12, 10), DateTime(2026, 10, 12, 11)),
      ]);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now), service: service));

      expect(find.text("CALENDAR"), findsOneWidget);
      expect(find.text("Rest of today"), findsOneWidget);
      expect(find.text("OK: next 7 days"), findsOneWidget);
      expect(find.text("Breakfast"), findsNothing); // over
      expect(find.text("Dentist"), findsNothing); // not today
      expect(find.text("All day"), findsOneWidget);
      expect(find.text("Now · until 3:00 PM"), findsOneWidget);
      expect(find.text("7:00 PM – 9:00 PM"), findsOneWidget);
      final x = [for (final t in ["Birthday", "Soccer", "Movie night"]) tester.getTopLeft(find.text(t)).dx];
      expect(x, orderedEquals([...x]..sort()));
      expect(find.text("Family"), findsNWidgets(3));
    });

    testWidgets("follows a 24-hour clock", (tester) async {
      when(settings.timeFormat).thenReturn("HH:mm");
      final service =
          await calendarService([timed("Movie night", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21))]);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now), service: service));
      expect(find.text("19:00 – 21:00"), findsOneWidget);
    });

    testWidgets("says when nothing else is on today", (tester) async {
      final service =
          await calendarService([timed("Breakfast", DateTime(2026, 10, 10, 8), DateTime(2026, 10, 10, 9))]);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now), service: service));
      expect(find.text("Nothing else today"), findsOneWidget);
    });

    testWidgets("is nothing without calendar access", (tester) async {
      final service = await calendarService(const [], allowed: false);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now), service: service));
      expect(find.text("CALENDAR"), findsNothing);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now)));
      expect(find.text("CALENDAR"), findsNothing);
    });

    testWidgets("counts the events past the ones it shows", (tester) async {
      final service = await calendarService([
        for (var h = 15; h < 21; h++) timed("Event $h", DateTime(2026, 10, 10, h), DateTime(2026, 10, 10, h, 30)),
      ]);
      await tester.pumpWidget(app(CalendarTodayRow(now: () => now), service: service));
      expect(find.text("+2 more"), findsOneWidget);
    });
  });

  group("the week", () {
    testWidgets("lists the coming days with events, Down moves through them", (tester) async {
      final service = await calendarService([
        timed("Movie night", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21)),
        timed("Brunch", DateTime(2026, 10, 11, 10), DateTime(2026, 10, 11, 11)),
        {...allDay("Field trip", DateTime(2026, 10, 13)), "location": "Museum"},
        timed("Too far", DateTime(2026, 10, 20, 10), DateTime(2026, 10, 20, 11)),
      ]);
      await tester.pumpWidget(app(CalendarAgendaPage(now: () => now), service: service));
      await tester.pumpAndSettle();

      expect(find.text("Next 7 days"), findsOneWidget);
      expect(find.text("Today"), findsOneWidget);
      expect(find.text("Tomorrow"), findsOneWidget);
      expect(find.text("Tuesday, October 13"), findsOneWidget);
      expect(find.text("Family · Museum"), findsOneWidget);
      expect(find.text("Too far"), findsNothing);
      expect(find.text("10:00 AM – 11:00 AM"), findsOneWidget);

      // The first event has focus; Down goes to the next
      bool focused(String title) => Focus.of(tester.element(find.text(title))).hasFocus;
      expect(focused("Movie night"), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focused("Brunch"), isTrue);
    });

    testWidgets("says when there's nothing in the coming days", (tester) async {
      final service = await calendarService(const []);
      await tester.pumpWidget(app(CalendarAgendaPage(now: () => now), service: service));
      await tester.pumpAndSettle();
      expect(find.text("Nothing on in the next 7 days"), findsOneWidget);
    });
  });

  group("the top bar's date and time", () {
    late MockTvInputsService inputs;
    late MockNotificationsService notifications;
    late MockWeatherService weather;

    setUp(() {
      when(settings.autoHideAppBarEnabled).thenReturn(false);
      when(settings.showDataWidgetInStatusBar).thenReturn(false);
      when(settings.showDateInStatusBar).thenReturn(true);
      when(settings.showTimeInStatusBar).thenReturn(true);
      when(settings.showInputsWidgetInStatusBar).thenReturn(false);
      when(settings.showNotificationsWidgetInStatusBar).thenReturn(false);
      when(settings.autoHideNotificationsWidget).thenReturn(false);
      when(settings.dateFormat).thenReturn(SettingsService.defaultDateFormat);
      when(settings.showWeatherInStatusBar).thenReturn(false);
      when(settings.haPanelEnabled).thenReturn(false);
      inputs = MockTvInputsService();
      notifications = MockNotificationsService();
      weather = MockWeatherService();
      when(inputs.hasInputs).thenReturn(false);
      when(notifications.hasPermission).thenReturn(false);
      when(weather.hasWeather).thenReturn(false);
    });

    Widget topBar({CalendarService? service, HomeAgenda? agenda}) => app(
          const Column(children: [SizedBox(height: kToolbarHeight, child: FocusAwareAppBar())]),
          service: service,
          agenda: agenda,
          more: [
            ChangeNotifierProvider<TvInputsService>.value(value: inputs),
            ChangeNotifierProvider<NotificationsService>.value(value: notifications),
            ChangeNotifierProvider<WeatherService>.value(value: weather),
          ],
        );

    testWidgets("take no focus without calendars to show", (tester) async {
      await tester.pumpWidget(topBar());
      expect(find.byKey(const Key("statusbar_date")), findsOneWidget);
      expect(find.byKey(const Key("statusbar_calendar")), findsNothing);
      expect(find.byKey(const Key("statusbar_calendar_allow")), findsNothing);
    });

    testWidgets("without calendar access, the date is a stop whose OK asks for it", (tester) async {
      var allowed = false;
      var asked = 0;
      final service = CalendarService(
        read: (from, to) async => allowed
            ? (
                access: TvCalendarAccess.granted,
                calendars: CalendarParser.parseCalendars([
                  {"id": 1, "name": "Family", "account": "alex@example.com"}
                ]),
                events: CalendarParser.parseEvents(
                    [timed("Movie night", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21))]),
              )
            : (access: TvCalendarAccess.denied, calendars: const <TvCalendar>[], events: const <CalendarEvent>[]),
        hiddenCalendars: () => const [],
        requestAccess: () async {
          asked++;
          allowed = true;
          return true;
        },
        now: () => now,
      );
      await service.refresh();
      await tester.pumpWidget(topBar(service: service, agenda: HomeAgenda()));
      final allow = find.byKey(const Key("statusbar_calendar_allow"));
      expect(allow, findsOneWidget);
      expect(find.byKey(const Key("statusbar_calendar")), findsNothing);

      tester.widget<Focus>(find.descendant(of: allow, matching: find.byType(Focus)).first).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(asked, 1);
      // Allowed: the date is the calendar now
      expect(find.byKey(const Key("statusbar_calendar")), findsOneWidget);
    });

    testWidgets("focused, show today's events; OK opens the week and Back closes it", (tester) async {
      final service =
          await calendarService([timed("Movie night", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21))]);
      final agenda = HomeAgenda();
      await tester.pumpWidget(topBar(service: service, agenda: agenda));
      final pill = find.byKey(const Key("statusbar_calendar"));
      expect(pill, findsOneWidget);

      final node = tester.widget<Focus>(find.descendant(of: pill, matching: find.byType(Focus)).first).focusNode!;
      node.requestFocus();
      await tester.pump();
      expect(agenda.showing, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarAgendaPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CalendarAgendaPage), findsNothing);

      expect(node.hasFocus, isTrue); // back on the date and time
      node.unfocus();
      await tester.pump();
      expect(agenda.showing, isFalse);
    });
  });
}
