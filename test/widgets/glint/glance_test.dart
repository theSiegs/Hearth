import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/widgets/glint/glance.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("places by name, off when unknown", () {
    expect(GlancePlace.fromName("row"), GlancePlace.row);
    expect(GlancePlace.fromName(" Column "), GlancePlace.column);
    expect(GlancePlace.fromName("headline"), GlancePlace.headline);
    expect(GlancePlace.fromName("sideways"), GlancePlace.off);
    expect(GlancePlace.fromName(null), GlancePlace.off);
  });

  test("only what has something to say, weather first", () {
    expect(glanceTiles(const GlanceData()), isEmpty);
    expect(
      glanceTiles(const GlanceData(weather: WeatherData(location: "Springfield"))),
      isEmpty,
      reason: "no temperature yet",
    );

    final now = DateTime.now();
    final tiles = glanceTiles(
      GlanceData(
        house: const [GlintHouseItem("Den TV", "Sam · Bluey")],
        notifications: [
          NotificationItem(
            key: "k",
            packageName: "p",
            appLabel: "Doorbell",
            title: "At the door",
            text: "",
            isClearable: true,
          ),
        ],
        events: [
          CalendarEvent(
            calendarId: "1",
            calendarName: "Family",
            summary: "Piano",
            start: now,
            end: now.add(const Duration(hours: 1)),
            allDay: false,
          ),
        ],
        weather: const WeatherData(currentTemp: 61),
      ),
    );
    expect(
      [for (final t in tiles) t.kind],
      [GlanceKind.weather, GlanceKind.calendar, GlanceKind.notifications, GlanceKind.house],
    );
  });

  test("a normal build never makes things up", () {
    expect(const GlanceData().orDemo().weather, isNull);
    expect(const GlanceData().orDemo().house, isEmpty);
  });
}
