/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/providers/calendars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const family = TvCalendar("tv:1", "Family", account: "alex@example.com");
const school = TvCalendar("tv:2", "School", account: "alex@example.com");

CalendarEvent event(String summary, DateTime start, DateTime end, {bool allDay = false, TvCalendar calendar = family}) =>
    CalendarEvent(
        calendarId: calendar.id,
        calendarName: calendar.name,
        summary: summary,
        start: start,
        end: end,
        allDay: allDay);

/// The TV's calendar store for a profile, counting reads.
class FakeTv {
  TvCalendarAccess access = TvCalendarAccess.granted;
  List<TvCalendar> calendars = const [family, school];
  List<CalendarEvent> events = [];
  bool failing = false;
  int reads = 0;
  final List<(DateTime, DateTime)> ranges = [];

  Future<CalendarReading> read(DateTime from, DateTime to) async {
    reads++;
    ranges.add((from, to));
    if (failing) throw Exception("provider gone");
    if (access != TvCalendarAccess.granted) {
      return (access: access, calendars: const <TvCalendar>[], events: const <CalendarEvent>[]);
    }
    return (access: access, calendars: calendars, events: events);
  }
}

void main() {
  group("reading the TV's answers", () {
    test("reads the calendars, by name, with their colors", () {
      final calendars = CalendarParser.parseCalendars([
        {"id": 7, "name": "School", "account": "alex@example.com", "color": -12396910},
        {"id": 3, "name": " Family ", "account": "alex@example.com"},
        {"name": "No id"},
        "junk",
      ]);
      expect(calendars.map((c) => c.id), ["tv:3", "tv:7"]);
      expect(calendars[0].name, "Family");
      expect(calendars[0].color, isNull);
      // Android's signed ARGB as an opaque color
      expect(calendars[1].color, -12396910 + 0x100000000);
      expect(calendars[1].color! >> 24, 0xFF);
      expect(CalendarParser.parseCalendars(null), isEmpty);
    });

    test("reads the access", () {
      expect(CalendarParser.parseAccess("granted"), TvCalendarAccess.granted);
      expect(CalendarParser.parseAccess("waiting"), TvCalendarAccess.waiting);
      expect(CalendarParser.parseAccess("denied"), TvCalendarAccess.denied);
      expect(CalendarParser.parseAccess(null), TvCalendarAccess.denied);
    });

    test("reads timed events in the TV's time", () {
      final start = DateTime(2026, 10, 10, 17), end = DateTime(2026, 10, 10, 18, 30);
      final events = CalendarParser.parseEvents([
        {
          "calendarId": 1,
          "calendarName": "Family",
          "title": " Soccer practice ",
          "location": "Park",
          "start": start.millisecondsSinceEpoch,
          "end": end.millisecondsSinceEpoch,
          "allDay": false,
          "color": 0x00FF8800,
        },
        {"calendarId": 1, "title": "No start"},
      ]);
      expect(events, hasLength(1));
      expect(events[0].summary, "Soccer practice");
      expect(events[0].calendarId, "tv:1");
      expect(events[0].calendarName, "Family");
      expect(events[0].start, start);
      expect(events[0].end, end);
      expect(events[0].allDay, isFalse);
      expect(events[0].location, "Park");
      expect(events[0].color, 0xFFFF8800);
    });

    test("reads an all-day event's UTC midnights as its days here", () {
      final events = CalendarParser.parseEvents([
        {
          "calendarId": 1,
          "title": "Holiday",
          "start": DateTime.utc(2026, 10, 12).millisecondsSinceEpoch,
          "end": DateTime.utc(2026, 10, 14).millisecondsSinceEpoch,
          "allDay": true,
        },
        // No end, no title
        {"calendarId": 1, "start": DateTime.utc(2026, 10, 15).millisecondsSinceEpoch, "allDay": true},
      ]);
      expect(events[0].start, DateTime(2026, 10, 12));
      expect(events[0].end, DateTime(2026, 10, 14));
      expect(events[0].allDay, isTrue);
      expect(events[0].occursOn(DateTime(2026, 10, 13)), isTrue);
      expect(events[0].occursOn(DateTime(2026, 10, 14)), isFalse);
      expect(events[1].summary, "");
      expect(events[1].end, DateTime(2026, 10, 16));
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
      expect(CalendarParser.eventsOn(events, now, now).map((e) => e.summary),
          ["Birthday", "Vacation", "Nap", "Movie", "Late show"]);
    });

    test("an event that runs past midnight and a multi-day event show on each day", () {
      final tomorrow = DateTime(2026, 10, 11);
      expect(CalendarParser.eventsOn(events, tomorrow, now).map((e) => e.summary), ["Vacation", "Late show"]);
    });

    test("the week lists the days with something on, starting today", () {
      final week = CalendarParser.agenda(events, now, days: 7);
      expect(week.map((d) => d.$1), [DateTime(2026, 10, 10), DateTime(2026, 10, 11), DateTime(2026, 10, 12)]);
      expect(week[2].$2.map((e) => e.summary), ["Vacation", "Dentist"]);
    });

    test("an event without length shows until its time", () {
      final reminder = event("Reminder", DateTime(2026, 10, 10, 15), DateTime(2026, 10, 10, 15));
      expect(CalendarParser.eventsOn([reminder], now, now), [reminder]);
      expect(CalendarParser.eventsOn([reminder], now, DateTime(2026, 10, 10, 15, 1)), isEmpty);
    });

    test("an event is on between its start and end", () {
      expect(events[2].isOn(now), isTrue);
      expect(events[1].isOn(now), isFalse);
      expect(events[3].isOn(now), isFalse); // all day
    });
  });

  group("service", () {
    late FakeTv tv;
    late DateTime now;
    late List<String> hidden;
    late String? profile;
    late bool granting;

    CalendarService service({Listenable? settings}) => CalendarService(
          read: tv.read,
          requestAccess: () async {
            if (granting) tv.access = TvCalendarAccess.granted;
            return granting;
          },
          hiddenCalendars: () => hidden,
          profileKey: () => profile,
          now: () => now,
          settings: settings,
        );

    setUp(() {
      now = DateTime(2026, 10, 10, 12);
      hidden = [];
      profile = "user:0";
      granting = true;
      tv = FakeTv()
        ..events = [
          event("Dinner", DateTime(2026, 10, 10, 18), DateTime(2026, 10, 10, 19)),
          event("Field trip", DateTime(2026, 10, 12), DateTime(2026, 10, 13), allDay: true, calendar: school),
        ];
    });

    test("without calendar access there's nothing", () async {
      tv.access = TvCalendarAccess.denied;
      final s = service();
      await s.refresh();
      expect(s.access, TvCalendarAccess.denied);
      expect(s.available, isFalse);
      expect(s.today(), isEmpty);
    });

    test("asking for access reads them", () async {
      tv.access = TvCalendarAccess.denied;
      final s = service();
      await s.refresh();
      expect(await s.requestAccess(), isTrue);
      expect(s.available, isTrue);
      expect(s.today().map((e) => e.summary), ["Dinner"]);
    });

    test("access turned down stays without calendars", () async {
      tv.access = TvCalendarAccess.denied;
      granting = false;
      final s = service();
      await s.refresh();
      expect(await s.requestAccess(), isFalse);
      expect(s.available, isFalse);
    });

    test("reads the coming week, from the day before (all-day events are by UTC day)", () async {
      final s = service();
      await s.refresh();
      expect(s.access, TvCalendarAccess.granted);
      expect(s.available, isTrue);
      expect(s.today().map((e) => e.summary), ["Dinner"]);
      expect(s.week().map((d) => d.$1), [DateTime(2026, 10, 10), DateTime(2026, 10, 12)]);
      expect(tv.ranges.single, (DateTime(2026, 10, 9), DateTime(2026, 10, 18)));
    });

    test("with no calendar, the date and time take no focus", () async {
      tv.calendars = const [];
      final s = service();
      await s.refresh();
      expect(s.available, isFalse);
    });

    test("keeps what it read for a few minutes", () async {
      final s = service();
      await s.refresh();
      now = now.add(const Duration(minutes: 4));
      await s.refresh();
      expect(tv.reads, 1);
      now = now.add(const Duration(minutes: 2));
      await s.refresh();
      expect(tv.reads, 2);
    });

    test("a kids' profile whose Hearth hasn't reported is asked again a minute later", () async {
      tv.access = TvCalendarAccess.waiting;
      final s = service();
      await s.refresh();
      expect(s.access, TvCalendarAccess.waiting);
      expect(s.available, isFalse);
      now = now.add(const Duration(seconds: 61));
      tv.access = TvCalendarAccess.granted;
      await s.refresh();
      expect(s.available, isTrue);
    });

    test("a failed read keeps the last events and tries again a minute later", () async {
      final s = service();
      await s.refresh();
      tv.failing = true;
      now = now.add(const Duration(minutes: 6));
      await s.refresh();
      expect(s.today().map((e) => e.summary), ["Dinner"]);
      final reads = tv.reads;
      now = now.add(const Duration(seconds: 30));
      await s.refresh();
      expect(tv.reads, reads);
      now = now.add(const Duration(seconds: 31));
      await s.refresh();
      expect(tv.reads, reads + 1);
    });

    test("leaves out the calendars this profile turned off, and says so when they change", () async {
      final settings = ValueNotifier(0);
      final s = service(settings: settings);
      await s.refresh();
      var notified = 0;
      s.addListener(() => notified++);
      hidden = ["tv:2"];
      settings.value++;
      expect(notified, 1);
      expect(s.shownCalendars, [family]);
      expect(s.week().map((d) => d.$1), [DateTime(2026, 10, 10)]);
      // Another settings change that isn't about calendars
      settings.value++;
      expect(notified, 1);
      hidden = ["tv:2", "tv:1"];
      settings.value++;
      expect(s.available, isFalse);
      s.dispose();
    });

    test("another profile reads its own calendars at once, and the last one's are gone meanwhile", () async {
      final settings = ValueNotifier(0);
      final s = service(settings: settings);
      await s.refresh();
      expect(s.today(), isNotEmpty);
      profile = "user:0:sam";
      tv.events = [event("Gym", DateTime(2026, 10, 10, 17), DateTime(2026, 10, 10, 18))];
      settings.value++;
      expect(s.today(), isEmpty);
      await Future<void>.delayed(Duration.zero);
      await s.refresh(); // the read under way
      expect(s.today().map((e) => e.summary), ["Gym"]);
      expect(tv.reads, 2);
      s.dispose();
    });
  });
}
