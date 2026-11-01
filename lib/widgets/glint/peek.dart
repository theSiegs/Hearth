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

/// Where the peek tiles sit on the dock home. Saved by name.
enum PeekPlace {
  off,

  /// Tiles in a row just above the dock.
  row,

  /// Tiles in a short column at the top right, under the top bar's clock.
  column,

  /// No tiles: Metro lines of text on the picture itself, at the top left, one thing per line.
  headline;

  static PeekPlace fromName(String? name) =>
      values.where((p) => p.name == name?.trim().toLowerCase()).firstOrNull ?? off;
}

/// What's going on, in Glint's peek tiles over the dock home: the weather, today's next event, the newest
/// notification and what's on around the house. They're for looking at (Glint's Still tiles): none of them takes the
/// selection, which stays on the dock's apps, because a TV's home is mostly for opening a streaming app; the top bar
/// still opens the forecast, today's agenda and the notifications. Only things with something to say are shown, at
/// most three, the ones that want a person first.
class Peek extends StatefulWidget {
  final PeekPlace place;
  const Peek({super.key, required this.place});

  @override
  State<Peek> createState() => _PeekState();
}

class _PeekState extends State<Peek> with WidgetsBindingObserver {
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
    final data = PeekData(
      weather: context.watch<WeatherService?>()?.weatherData,
      events: context.watch<CalendarService?>()?.today().take(3).toList() ?? const [],
      notifications: notifications != null && notifications.hasPermission && settings.showNotificationsWidgetInStatusBar
          ? notifications.notifications
          : const [],
      house: _house.items,
    ).orDemo();
    String time(DateTime t) {
      try {
        return DateFormat(settings.timeFormat).format(t);
      } catch (_) {
        return DateFormat("h:mm").format(t);
      }
    }

    final things = peekThings(data, time: time);
    if (things.isEmpty) return const SizedBox.shrink();
    return GlintPeek(
      child: widget.place == PeekPlace.headline
          ? PeekHeadline(things: things)
          : GlintTickerScope(
              ticker: _ticker,
              child: Material(
                type: MaterialType.transparency,
                child: widget.place == PeekPlace.column ? _column(things) : _row(things),
              ),
            ),
    );
  }

  /// One row, centred, narrowed to fit if need be.
  Widget _row(List<PeekThing> things) => LayoutBuilder(
    builder: (context, box) {
      final gaps = GlintLook.gap * (things.length - 1);
      final width = ((box.maxWidth - gaps) / things.length).clamp(0.0, GlintLook.peekHeight * 3.4);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, t) in things.indexed) ...[
            if (i > 0) const SizedBox(width: GlintLook.gap),
            SizedBox(key: ValueKey(t.kind), width: width, height: GlintLook.peekHeight, child: t.tile()),
          ],
        ],
      );
    },
  );

  /// A short column down the right, under the clock.
  Widget _column(List<PeekThing> things) => SizedBox(
    width: 300,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, t) in things.indexed) ...[
          if (i > 0) const SizedBox(height: GlintLook.gap),
          SizedBox(key: ValueKey(t.kind), height: GlintLook.peekHeight, child: t.tile()),
        ],
      ],
    ),
  );
}

enum PeekKind { weather, calendar, notifications, house }

/// One peek tile's worth: what it is, its faces, and what's new on it (only for things that want a person).
class PeekThing {
  final PeekKind kind;
  final List<PeekItem> items;
  final Object? fresh;
  const PeekThing(this.kind, this.items, {this.fresh});

  Widget tile() => PeekFace(id: "peek:${kind.name}", items: items, fresh: fresh);
}

/// What the peek tiles show, from the TV's services.
class PeekData {
  final WeatherData? weather;
  final List<CalendarEvent> events;
  final List<NotificationItem> notifications;
  final List<GlintHouseItem> house;

  const PeekData({this.weather, this.events = const [], this.notifications = const [], this.house = const []});

  /// A demo build (`--dart-define=PEEK_DEMO=true`, for looking at the design on a TV with little going on) fills
  /// what's missing with made-up things.
  PeekData orDemo() {
    if (!const bool.fromEnvironment("PEEK_DEMO")) return this;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return PeekData(
      weather: weather?.currentTemp != null
          ? weather
          : const WeatherData(
              location: "Springfield",
              currentTemp: 61,
              currentConditionCode: 1,
              currentCondition: "Partly cloudy",
              todayMaxTemp: 66,
              todayMinTemp: 48,
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

/// The peek tiles there's something for, at most [max]: chosen by what wants a person (a notification, the house)
/// before what's ambient (the next event, the weather), then shown in a fixed order (weather, event, notification,
/// house) so the tiles don't trade places.
///
/// A notification shows its app, how many there are and its title, never its text: the TV's screen is shared. A
/// message from a person shows only who it's from and how many they sent.
List<PeekThing> peekThings(PeekData data, {required String Function(DateTime) time, int max = 3}) {
  final now = DateTime.now();
  final byKind = <PeekKind, PeekThing>{};
  final w = data.weather;
  if (w != null && w.currentTemp != null) {
    final hiLo = [
      if (w.todayMaxTemp != null) "H ${w.todayMaxTemp}°",
      if (w.todayMinTemp != null) "L ${w.todayMinTemp}°",
    ];
    byKind[PeekKind.weather] = PeekThing(PeekKind.weather, [
      PeekItem(
        w.location ?? "Weather",
        ["${w.currentTemp}°", if (w.currentCondition?.isNotEmpty ?? false) w.currentCondition!].join("  "),
        small: hiLo.isEmpty ? null : hiLo.join(" · "),
      ),
    ]);
  }
  final events = data.events.where((e) => e.allDay || e.end.isAfter(now)).toList();
  if (events.isNotEmpty) {
    byKind[PeekKind.calendar] = PeekThing(PeekKind.calendar, [
      for (final e in events)
        PeekItem(
          e.allDay ? "Today" : (e.isOn(now) ? "Now · until ${time(e.end)}" : "Today · ${time(e.start)}"),
          e.summary,
          colourEdge: e.color == null ? null : Color(e.color!).withValues(alpha: 1),
        ),
    ]);
  }
  final shown = data.notifications.take(3).toList();
  if (shown.isNotEmpty) {
    final count = data.notifications.length;
    PeekItem item(NotificationItem n) {
      // A message from a person shows only who and how many: its title is often the message itself
      if (n.sender.isNotEmpty) {
        final fromThem = data.notifications.where((o) => o.sender == n.sender).length;
        return PeekItem(n.appLabel, fromThem > 1 ? "${n.sender} · $fromThem" : n.sender);
      }
      return PeekItem(count > 1 ? "${n.appLabel} · $count" : n.appLabel, n.title.isNotEmpty ? n.title : n.appLabel);
    }

    byKind[PeekKind.notifications] = PeekThing(PeekKind.notifications, [
      for (final n in shown) item(n),
    ], fresh: shown.first.key);
  }
  if (data.house.isNotEmpty) {
    byKind[PeekKind.house] = PeekThing(PeekKind.house, [
      for (final h in data.house) PeekItem(h.label, h.line, small: h.detail),
    ], fresh: Object.hashAll(data.house));
  }
  const wantsPerson = [PeekKind.notifications, PeekKind.house, PeekKind.calendar, PeekKind.weather];
  final chosen = wantsPerson.where(byKind.containsKey).take(max).toSet();
  return [
    for (final k in PeekKind.values)
      if (chosen.contains(k)) byKind[k]!,
  ];
}

/// The peek as Metro text on the picture: one line per thing, a small ember label over big light type, no glass,
/// shaded so it reads over a busy picture. Each line is one thing only, the first of each tile's faces.
class PeekHeadline extends StatelessWidget {
  final List<PeekThing> things;
  const PeekHeadline({super.key, required this.things});

  /// A close dark edge round each letter and a wide soft one under the line: no box, so nothing to see but the words,
  /// and they read over a busy picture.
  static const _shade = [
    Shadow(color: Color(0xB3000000), blurRadius: 4),
    Shadow(color: Color(0x99000000), blurRadius: 24),
  ];

  @override
  Widget build(BuildContext context) {
    final lines = things.take(GlintLook.headlineLines).map((t) => t.items.first).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Column(
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
                    style: GlintLook.label.copyWith(color: GlintLook.ember, letterSpacing: 0.6, shadows: _shade),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l.line),
                        if (l.small != null)
                          TextSpan(
                            text: "  ${l.small}",
                            style: GlintLook.secondaryText.copyWith(fontSize: 18, shadows: _shade),
                          ),
                      ],
                    ),
                    style: GlintLook.display(GlintLook.headlineSize).copyWith(shadows: _shade),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
