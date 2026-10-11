import 'dart:io';

import 'package:flauncher/providers/ha_calendars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const family = HaCalendar("calendar.family", "Family");
const school = HaCalendar("calendar.school", "School");

CalendarEvent event(String summary, DateTime start, DateTime end,
        {bool allDay = false, HaCalendar calendar = family}) =>
    CalendarEvent(
        calendarId: calendar.entityId,
        calendarName: calendar.name,
        summary: summary,
        start: start,
        end: end,
        allDay: allDay);

/// A Home Assistant that answers from a map of paths, counting requests.
class FakeHa {
  final Map<String, Object?> replies;
  final List<Uri> asked = [];
  final List<String> tokens = [];
  bool down = false;

  FakeHa(this.replies);

  Future<Object?> getJson(Uri uri, String token) async {
    asked.add(uri);
    tokens.add(token);
    if (down) throw const SocketException("unreachable");
    if (!replies.containsKey(uri.path)) throw const HttpException("HTTP 404");
    return replies[uri.path];
  }
}

void main() {
  group("parsing", () {
    test("reads the calendar list, by name, leaving out what it can't read", () {
      final calendars = HaCalendarParser.parseCalendars([
        {"entity_id": "calendar.school", "name": "School"},
        {"entity_id": "calendar.family", "name": "Family"},
        {"entity_id": "calendar.nameless"},
        {"name": "No id"},
        "junk",
      ]);
      expect(calendars, [const HaCalendar("calendar.nameless", "calendar.nameless"), family, school]);
      expect(HaCalendarParser.parseCalendars({"message": "401"}), isEmpty);
    });

    test("reads timed and all-day events", () {
      final events = HaCalendarParser.parseEvents([
        {
          "summary": " Soccer practice ",
          "start": {"dateTime": "2026-10-10T17:00:00"},
          "end": {"dateTime": "2026-10-10T18:30:00"},
          "location": "Park",
        },
        {
          "summary": "Holiday",
          "start": {"date": "2026-10-12"},
          "end": {"date": "2026-10-13"},
        },
        {"summary": "No start"},
      ], family);
      expect(events, hasLength(2));
      expect(events[0].summary, "Soccer practice");
      expect(events[0].allDay, isFalse);
      expect(events[0].start, DateTime(2026, 10, 10, 17));
      expect(events[0].end, DateTime(2026, 10, 10, 18, 30));
      expect(events[0].location, "Park");
      expect(events[0].calendarName, "Family");
      expect(events[1].allDay, isTrue);
      expect(events[1].start, DateTime(2026, 10, 12));
      expect(events[1].end, DateTime(2026, 10, 13));
    });

    test("puts times with an offset in the TV's time", () {
      final events = HaCalendarParser.parseEvents([
        {"summary": "Call", "start": {"dateTime": "2026-10-10T15:00:00Z"}, "end": {"dateTime": "2026-10-10T16:00:00+00:00"}},
      ], family);
      expect(events.single.start, DateTime.utc(2026, 10, 10, 15).toLocal());
      expect(events.single.start.isUtc, isFalse);
      expect(events.single.end, DateTime.utc(2026, 10, 10, 16).toLocal());
    });

    test("gives an event without an end an hour, or its day; a missing title stays empty", () {
      final events = HaCalendarParser.parseEvents([
        {"start": {"dateTime": "2026-10-10T09:00:00"}},
        {"summary": "Trip", "start": "2026-10-11"},
      ], family);
      expect(events[0].summary, "");
      expect(events[0].end, DateTime(2026, 10, 10, 10));
      expect(events[1].allDay, isTrue);
      expect(events[1].end, DateTime(2026, 10, 12));
    });
  });

  group("what's on", () {
    final now = DateTime(2026, 10, 10, 14, 0);
    final events = [
      event("Breakfast", DateTime(2026, 10, 10, 8), DateTime(2026, 10, 10, 9)),
      event("Movie", DateTime(2026, 10, 10, 19), DateTime(2026, 10, 10, 21)),
      event("Nap", DateTime(2026, 10, 10, 13, 30), DateTime(2026, 10, 10, 15), calendar: school),
      event("Birthday", DateTime(2026, 10, 10), DateTime(2026, 10, 11), allDay: true),
      event("Vacation", DateTime(2026, 10, 9), DateTime(2026, 10, 13), allDay: true),
      event("Yesterday", DateTime(2026, 10, 9), DateTime(2026, 10, 10), allDay: true),
      event("Late show", DateTime(2026, 10, 10, 23), DateTime(2026, 10, 11, 1)),
      event("Dentist", DateTime(2026, 10, 12, 10), DateTime(2026, 10, 12, 11)),
      event("Too far", DateTime(2026, 10, 17, 10), DateTime(2026, 10, 17, 11)),
    ];

    test("today leaves out what's over and lists all-day events first, then by start", () {
      expect(HaCalendarParser.eventsOn(events, now, now).map((e) => e.summary),
          ["Birthday", "Vacation", "Nap", "Movie", "Late show"]);
    });

    test("an event that runs past midnight and a multi-day event show on each day", () {
      final tomorrow = DateTime(2026, 10, 11);
      expect(HaCalendarParser.eventsOn(events, tomorrow, now).map((e) => e.summary), ["Vacation", "Late show"]);
    });

    test("the week lists the days with something on, starting today", () {
      final week = HaCalendarParser.agenda(events, now, days: 7);
      expect(week.map((d) => d.$1), [DateTime(2026, 10, 10), DateTime(2026, 10, 11), DateTime(2026, 10, 12)]);
      expect(week[2].$2.map((e) => e.summary), ["Vacation", "Dentist"]);
    });

    test("an event without length shows until its time", () {
      final reminder = event("Reminder", DateTime(2026, 10, 10, 15), DateTime(2026, 10, 10, 15));
      expect(HaCalendarParser.eventsOn([reminder], now, now), [reminder]);
      expect(HaCalendarParser.eventsOn([reminder], now, DateTime(2026, 10, 10, 15, 1)), isEmpty);
    });

    test("an event is on between its start and end", () {
      expect(events[2].isOn(now), isTrue);
      expect(events[1].isOn(now), isFalse);
      expect(events[3].isOn(now), isFalse); // all day
    });
  });

  group("client", () {
    test("asks with the token, for the calendar's events between two times", () async {
      final ha = FakeHa({
        "/ha/api/calendars": [
          {"entity_id": "calendar.family", "name": "Family"}
        ],
        "/ha/api/calendars/calendar.family": [
          {"summary": "Dinner", "start": {"dateTime": "2026-10-10T18:00:00"}, "end": {"dateTime": "2026-10-10T19:00:00"}}
        ],
      });
      final client = HaCalendarClient("http://192.0.2.10:8123/ha/", "secret", getJson: ha.getJson);
      expect(await client.calendars(), [family]);
      final from = DateTime(2026, 10, 10), to = DateTime(2026, 10, 17);
      final events = await client.events(family, from, to);
      expect(events.single.summary, "Dinner");
      final uri = ha.asked.last;
      expect(uri.host, "192.0.2.10");
      expect(uri.port, 8123);
      expect(uri.queryParameters["start"], from.toUtc().toIso8601String());
      expect(uri.queryParameters["end"], to.toUtc().toIso8601String());
      expect(ha.tokens, everyElement("secret"));
    });
  });

  group("service", () {
    late FakeHa ha;
    late DateTime now;
    late List<String> hidden;
    ({String url, String token})? connection;

    HaCalendarService service({Listenable? settings}) => HaCalendarService(
          connection: () async => connection,
          hiddenCalendars: () => hidden,
          client: (url, token) => HaCalendarClient(url, token, getJson: ha.getJson),
          now: () => now,
          settings: settings,
        );

    setUp(() {
      now = DateTime(2026, 10, 10, 12);
      hidden = [];
      connection = (url: "http://192.0.2.10:8123", token: "secret");
      ha = FakeHa({
        "/api/calendars": [
          {"entity_id": "calendar.family", "name": "Family"},
          {"entity_id": "calendar.school", "name": "School"},
        ],
        "/api/calendars/calendar.family": [
          {"summary": "Dinner", "start": {"dateTime": "2026-10-10T18:00:00"}, "end": {"dateTime": "2026-10-10T19:00:00"}}
        ],
        "/api/calendars/calendar.school": [
          {"summary": "Field trip", "start": {"date": "2026-10-12"}, "end": {"date": "2026-10-13"}}
        ],
      });
    });

    test("without Home Assistant there's nothing, and it asks nobody", () async {
      connection = null;
      final s = service();
      await s.refresh();
      expect(s.status, HaCalendarStatus.notSetUp);
      expect(s.available, isFalse);
      expect(s.today(), isEmpty);
      expect(ha.asked, isEmpty);
    });

    test("reads every calendar's coming week", () async {
      final s = service();
      await s.refresh();
      expect(s.status, HaCalendarStatus.ok);
      expect(s.available, isTrue);
      expect(s.today().map((e) => e.summary), ["Dinner"]);
      expect(s.week().map((d) => d.$1), [DateTime(2026, 10, 10), DateTime(2026, 10, 12)]);
    });

    test("keeps what it read for a few minutes", () async {
      final s = service();
      await s.refresh();
      final asked = ha.asked.length;
      now = now.add(const Duration(minutes: 4));
      await s.refresh();
      expect(ha.asked.length, asked);
      now = now.add(const Duration(minutes: 2));
      await s.refresh();
      expect(ha.asked.length, greaterThan(asked));
    });

    test("an unreachable Home Assistant fails quietly, keeps the last events and tries again a minute later", () async {
      final s = service();
      await s.refresh();
      ha.down = true;
      now = now.add(const Duration(minutes: 6));
      await s.refresh();
      expect(s.status, HaCalendarStatus.unreachable);
      expect(s.today().map((e) => e.summary), ["Dinner"]);
      expect(s.available, isTrue);
      final asked = ha.asked.length;
      now = now.add(const Duration(seconds: 30));
      await s.refresh();
      expect(ha.asked.length, asked);
      now = now.add(const Duration(seconds: 31));
      await s.refresh();
      expect(ha.asked.length, greaterThan(asked));
    });

    test("never reached, it isn't available", () async {
      ha.down = true;
      final s = service();
      await s.refresh();
      expect(s.status, HaCalendarStatus.unreachable);
      expect(s.available, isFalse);
    });

    test("leaves out the calendars this profile turned off, and says so when they change", () async {
      final settings = ValueNotifier(0);
      final s = service(settings: settings);
      await s.refresh();
      var notified = 0;
      s.addListener(() => notified++);
      hidden = ["calendar.school"];
      settings.value++;
      expect(notified, 1);
      expect(s.shownCalendars, [family]);
      expect(s.week().map((d) => d.$1), [DateTime(2026, 10, 10)]);
      // Another settings change that isn't about calendars
      settings.value++;
      expect(notified, 1);
      hidden = ["calendar.school", "calendar.family"];
      settings.value++;
      expect(s.available, isFalse);
      s.dispose();
    });
  });
}
