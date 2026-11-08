import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart' show PeekItem;
import 'package:flauncher/widgets/glint/peek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String time(DateTime t) => "${t.hour}:${t.minute.toString().padLeft(2, "0")}";
  final now = DateTime.now();
  NotificationItem note(String key, {String title = "At the door", String text = "A parcel"}) =>
      NotificationItem(key: key, packageName: "p", appLabel: "Doorbell", title: title, text: text, isClearable: true);
  final event = CalendarEvent(
    calendarId: "1",
    calendarName: "Family",
    summary: "Piano",
    start: now.add(const Duration(hours: 1)),
    end: now.add(const Duration(hours: 2)),
    allDay: false,
  );
  const house = [GlintHouseItem("Den TV", "Sam · Bluey", "HearthTube")];
  const weather = WeatherData(location: "Springfield", currentTemp: 61, currentCondition: "Sunny");

  test("places by name, off when unknown", () {
    expect(PeekPlace.fromName("row"), PeekPlace.row);
    expect(PeekPlace.fromName(" Column "), PeekPlace.column);
    expect(PeekPlace.fromName("headline"), PeekPlace.headline);
    expect(PeekPlace.fromName("sideways"), PeekPlace.off);
    expect(PeekPlace.fromName(null), PeekPlace.off);
  });

  test("only what has something to say", () {
    expect(peekThings(const PeekData(), time: time), isEmpty);
    expect(
      peekThings(
        const PeekData(weather: WeatherData(location: "Springfield")),
        time: time,
      ),
      isEmpty,
      reason: "no temperature yet",
    );
    final past = CalendarEvent(
      calendarId: "1",
      calendarName: "Family",
      summary: "Done",
      start: now.subtract(const Duration(hours: 3)),
      end: now.subtract(const Duration(hours: 2)),
      allDay: false,
    );
    expect(
      peekThings(PeekData(events: [past]), time: time),
      isEmpty,
      reason: "over already",
    );
  });

  test("three at most, what wants a person first, shown in a fixed order", () {
    final things = peekThings(
      PeekData(weather: weather, events: [event], notifications: [note("k")], house: house),
      time: time,
    );
    expect(
      [for (final t in things) t.kind],
      [PeekKind.calendar, PeekKind.notifications, PeekKind.house],
      reason: "the weather gives way, the rest keep their order",
    );
    expect(
      [
        for (final t in peekThings(
          PeekData(weather: weather, events: [event]),
          time: time,
        ))
          t.kind,
      ],
      [PeekKind.weather, PeekKind.calendar],
    );
  });

  test("a kid's time comes first, and glows when it changes", () {
    const t = PeekItem("Time", "It's bedtime", small: "Until 7:00 AM");
    final things = peekThings(
      PeekData(weather: weather, events: [event], notifications: [note("k")], house: house, time: t),
      time: time,
    );
    expect([for (final t in things) t.kind], [PeekKind.time, PeekKind.notifications, PeekKind.house]);
    expect(things.first.items.single.line, "It's bedtime");
    expect(things.first.fresh, isNotNull);
  });

  test("only things that want a person can glow", () {
    final things = peekThings(
      PeekData(weather: weather, events: [event], notifications: [note("k")]),
      time: time,
    );
    expect(
      {for (final t in things) t.kind: t.fresh != null},
      {PeekKind.weather: false, PeekKind.calendar: false, PeekKind.notifications: true},
    );
  });

  test("a notification shows its app, the count and its title, never its text", () {
    final item = peekThings(PeekData(notifications: [note("a"), note("b")]), time: time).single.items.first;
    expect(item.label, "Doorbell · 2");
    expect(item.line, "At the door");
    expect(item.small, isNull);
    final untitled = peekThings(
      PeekData(
        notifications: [note("a", title: "", text: "Private words")],
      ),
      time: time,
    );
    expect(untitled.single.items.first.line, "Doorbell");
  });

  test("a message from a person shows only who and how many", () {
    NotificationItem message(String key, String sender) => NotificationItem(
      key: key,
      packageName: "m",
      appLabel: "Messages",
      title: "See you at 6?",
      text: "Bring the thing",
      isClearable: true,
      sender: sender,
    );
    final items = peekThings(
      PeekData(notifications: [message("a", "Sam"), message("b", "Sam"), message("c", "Alex")]),
      time: time,
    ).single.items;
    expect(
      [for (final i in items) "${i.label}: ${i.line}"],
      ["Messages: Sam · 2", "Messages: Sam · 2", "Messages: Alex"],
    );
    expect(items.every((i) => i.small == null), isTrue);
  });

  test("a normal build never makes things up", () {
    expect(const PeekData().orDemo().weather, isNull);
    expect(const PeekData().orDemo().house, isEmpty);
  });
}
