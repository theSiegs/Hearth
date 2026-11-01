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

import 'package:collection/collection.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

/// Where the glance sits on the dock home. Saved by name.
enum GlancePlace {
  off,

  /// Tiles in a row just above the dock.
  row,

  /// Tiles in a column at the top right, under the top bar's clock.
  column,

  /// No tiles: Metro lines of text on the picture itself, at the top left, one thing per line.
  headline;

  static GlancePlace fromName(String? name) =>
      values.where((p) => p.name == name?.trim().toLowerCase()).firstOrNull ?? off;
}

/// What's going on, at a glance, over the dock home: the weather, today's next event, the newest notifications and
/// what's on around the house, as Glint's live glass tiles or as lines of text. They're for looking at: none of them
/// takes the selection, which stays on the dock's apps (a TV's home is mostly for opening a streaming app); the top
/// bar still opens the forecast, today's agenda and the notifications. Only things with something to say are shown.
class Glance extends StatefulWidget {
  final GlancePlace place;
  const Glance({super.key, required this.place});

  @override
  State<Glance> createState() => _GlanceState();
}

class _GlanceState extends State<Glance> with WidgetsBindingObserver {
  final GlintTicker _ticker = GlintTicker();
  late final GlintHouseFeed _house;

  @override
  void initState() {
    super.initState();
    _house = GlintHouseFeed(context.read<FLauncherChannel>().getHaConnection)..addListener(_houseChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _houseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ticker.freshView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _house
      ..removeListener(_houseChanged)
      ..dispose();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    _ticker.motion = GlintMotion.fromName(settings.glintMotion);
    final notifications = context.watch<NotificationsService?>();
    final data = GlanceData(
      weather: context.watch<WeatherService?>()?.weatherData,
      events: context.watch<CalendarService?>()?.today().take(3).toList() ?? const [],
      notifications: notifications != null && notifications.hasPermission && settings.showNotificationsWidgetInStatusBar
          ? notifications.notifications
          : const [],
      house: _house.items,
    ).orDemo();
    if (widget.place == GlancePlace.headline) return GlintGlance(child: GlanceHeadline(data: data));
    final tiles = glanceTiles(data);
    if (tiles.isEmpty) return const SizedBox.shrink();
    return GlintGlance(
      child: GlintTickerScope(
        ticker: _ticker,
        child: Material(
          type: MaterialType.transparency,
          child: widget.place == GlancePlace.column ? _column(tiles) : _row(tiles),
        ),
      ),
    );
  }

  /// One row, centred, every tile as tall: the weather squarer, the others wide; narrowed to fit if need be.
  Widget _row(List<GlanceTile> tiles) => LayoutBuilder(
    builder: (context, box) {
      const height = 116.0;
      final gaps = GlintLook.gap * (tiles.length - 1);
      final widths = [for (final t in tiles) t.kind == GlanceKind.weather ? height * 1.5 : height * 2.4];
      final want = widths.sum;
      final scale = want + gaps > box.maxWidth ? (box.maxWidth - gaps) / want : 1.0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: GlintLook.gap),
            SizedBox(key: ValueKey(t.kind), width: widths[i] * scale, height: height, child: t.face),
          ],
        ],
      );
    },
  );

  /// A column down the right: as many tiles as fit above the dock, most important first.
  Widget _column(List<GlanceTile> tiles) {
    final shown = tiles.take(3).toList();
    return SizedBox(
      width: 290,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, t) in shown.indexed) ...[
            if (i > 0) const SizedBox(height: GlintLook.gap),
            SizedBox(key: ValueKey(t.kind), height: t.kind == GlanceKind.weather ? 112 : 92, child: t.face),
          ],
        ],
      ),
    );
  }
}

enum GlanceKind { weather, calendar, notifications, house }

class GlanceTile {
  final GlanceKind kind;
  final Widget face;
  const GlanceTile(this.kind, this.face);
}

/// What the glance shows, from the TV's services.
class GlanceData {
  final WeatherData? weather;
  final List<CalendarEvent> events;
  final List<NotificationItem> notifications;
  final List<GlintHouseItem> house;

  const GlanceData({this.weather, this.events = const [], this.notifications = const [], this.house = const []});

  /// A demo build (`--dart-define=GLANCE_DEMO=true`, for looking at the design on a TV with little going on) fills
  /// what's missing with made-up things.
  GlanceData orDemo() {
    if (!const bool.fromEnvironment("GLANCE_DEMO")) return this;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return GlanceData(
      weather: weather?.currentTemp != null
          ? weather
          : const WeatherData(
              location: "Springfield",
              currentTemp: 61,
              currentConditionCode: 1,
              currentCondition: "Partly cloudy",
              todayMaxTemp: 66,
              todayMinTemp: 48,
              forecasts: [
                WeatherForecastItem(maxTemp: 66, minTemp: 48, conditionCode: 1),
                WeatherForecastItem(maxTemp: 58, minTemp: 44, conditionCode: 61, precipProbability: 70),
              ],
            ),
      events: events.isNotEmpty
          ? events
          : [
              CalendarEvent(
                calendarId: "demo",
                calendarName: "Family",
                summary: "Piano lesson",
                start: today.add(const Duration(hours: 16)),
                end: today.add(const Duration(hours: 17)),
                allDay: false,
                color: 0xFF4F8EF7,
              ),
              CalendarEvent(
                calendarId: "demo",
                calendarName: "Family",
                summary: "Pizza night",
                start: today.add(const Duration(hours: 18, minutes: 30)),
                end: today.add(const Duration(hours: 20)),
                allDay: false,
                color: 0xFFE8A33D,
              ),
            ],
      notifications: notifications.isNotEmpty
          ? notifications
          : [
              NotificationItem(
                key: "demo",
                packageName: "com.example.door",
                appLabel: "Doorbell",
                title: "Package at the front door",
                text: "Delivered 12 minutes ago",
                isClearable: true,
              ),
            ],
      house: house.isNotEmpty
          ? house
          : const [GlintHouseItem("Playroom TV", "Sam · Bluey", "HearthTube"), GlintHouseItem("In the car", "Alex")],
    );
  }
}

/// The glance tiles there's something for, in order: weather, the next event, notifications, the house.
List<GlanceTile> glanceTiles(GlanceData data) => [
  if (data.weather?.currentTemp != null) GlanceTile(GlanceKind.weather, WeatherFace(data: data.weather!)),
  if (data.events.isNotEmpty) GlanceTile(GlanceKind.calendar, CalendarFace(events: data.events)),
  if (data.notifications.isNotEmpty) GlanceTile(GlanceKind.notifications, NotificationsFace(items: data.notifications)),
  if (data.house.isNotEmpty) GlanceTile(GlanceKind.house, HouseFace(items: data.house)),
];

/// The glance as Metro text on the picture: one line per thing, a small ember label over big light type, no glass.
/// Each line is one thing only (the next event, the newest notification, one thing around the house), so it reads
/// from across the room.
class GlanceHeadline extends StatelessWidget {
  final GlanceData data;
  const GlanceHeadline({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    String time(DateTime t) {
      try {
        return DateFormat(settings.timeFormat).format(t);
      } catch (_) {
        return DateFormat("h:mm").format(t);
      }
    }

    final now = DateTime.now();
    final lines = <({String label, String line, String? detail})>[];
    final w = data.weather;
    if (w != null && w.currentTemp != null) {
      final hiLo = [
        if (w.todayMaxTemp != null) "H ${w.todayMaxTemp}°",
        if (w.todayMinTemp != null) "L ${w.todayMinTemp}°",
      ];
      lines.add((
        label: [w.location ?? "Outside", ...hiLo].join(" · "),
        line: "${w.currentTemp}°",
        detail: w.currentCondition,
      ));
    }
    final next = data.events.firstWhereOrNull((e) => e.allDay || e.end.isAfter(now));
    if (next != null) {
      final when = next.allDay
          ? "Today"
          : (next.isOn(now) ? "Now · until ${time(next.end)}" : "Today · ${time(next.start)}");
      lines.add((label: when, line: next.summary, detail: null));
    }
    final n = data.notifications.firstOrNull;
    if (n != null) lines.add((label: n.appLabel, line: n.title.isNotEmpty ? n.title : n.text, detail: null));
    final h = data.house.firstOrNull;
    if (h != null) {
      final more = data.house.length - 1;
      lines.add((label: more > 0 ? "${h.label} · $more more" : h.label, line: h.line, detail: h.detail));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.label.toLowerCase(),
                  style: GlintLook.label.copyWith(color: GlintLook.ember, letterSpacing: 0.6),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: l.line),
                      if (l.detail != null)
                        TextSpan(text: "  ${l.detail}", style: GlintLook.secondaryText.copyWith(fontSize: 18)),
                    ],
                  ),
                  style: GlintLook.display(30),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
