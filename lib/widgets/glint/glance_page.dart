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
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_layout.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flauncher/widgets/glint/ha_lock_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The glance page (Peek: Top shelf + glance page), down from the dock: a full page of live tiles in Glint's design
/// language. A kid's time (what's held, the minutes left in each group), the family and where they are, today's
/// events, the to-do lists, what's going on around the house, the weather and the newest notifications, then All apps,
/// Home Assistant's panel and Settings.
///
/// It's only built while it's up: its tiles turn, and Home Assistant is followed, only then. Back, or Up from its top
/// row, closes it ([onClose]); the home puts the selection back on the dock.
class GlancePage extends StatefulWidget {
  final VoidCallback onClose;
  const GlancePage({super.key, required this.onClose});

  @override
  State<GlancePage> createState() => _GlancePageState();
}

class _GlancePageState extends State<GlancePage> {
  final GlintTicker _ticker = GlintTicker();
  final FocusNode _focusNode = FocusNode(debugLabel: "glance_page");
  late final GlintHouseFeed _house;
  late final GlanceHaFeed _family;
  late final HaLockFeed _lock;

  @override
  void initState() {
    super.initState();
    final channel = context.read<FLauncherChannel>();
    _house = GlintHouseFeed(channel.getHaConnection)..addListener(_changed);
    _family = GlanceHaFeed(channel.getHaConnection)..addListener(_changed);
    _lock = HaLockFeed(channel.getHaLockState)..addListener(_changed);
    // The first tile takes the selection as the page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.descendants
          .where((n) => n.canRequestFocus && !n.skipTraversal && n.context != null)
          .firstOrNull
          ?.requestFocus();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final feed in <ChangeNotifier>[_house, _family, _lock]) {
      feed
        ..removeListener(_changed)
        ..dispose();
    }
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static final _backKeys = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape, LogicalKeyboardKey.browserBack};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (_backKeys.contains(event.logicalKey)) {
      if (event is KeyDownEvent) widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Up from the top row leaves the page; elsewhere it moves up as usual
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && !focus.focusInDirection(TraversalDirection.up) && event is KeyDownEvent) widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    _ticker.motion = GlintMotion.fromName(settings.glintMotion);
    final tiles = glanceTiles(
      lock: _lock.state,
      people: _family.people,
      lists: _family.lists,
      house: _house.items,
      weather: context.watch<WeatherService?>()?.weatherData,
      events: context.watch<CalendarService?>()?.today().take(3).toList() ?? const [],
      notifications: () {
        final n = context.watch<NotificationsService?>();
        return n != null && n.hasPermission && settings.showNotificationsWidgetInStatusBar ? n.notifications : null;
      }(),
      haPanel: settings.haPanelEnabled,
    );
    final layout = GlintLayout.pack([for (final t in tiles) t.size]);

    return Material(
      key: const Key("glance_page"),
      color: Colors.black.withValues(alpha: 0.35),
      child: GlintRest(
        rest: const AlwaysStoppedAnimation(0),
        child: GlintTickerScope(
          ticker: _ticker,
          child: LayoutBuilder(builder: (context, box) {
            const top = 48.0, bottom = 48.0, side = 48.0;
            final cell = ((box.maxHeight - top - bottom - 2 * GlintLook.gap) / 3).clamp(60.0, 240.0);
            final step = cell + GlintLook.gap;
            return Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(side, top, side * 2, bottom),
                  child: SizedBox(
                    width: layout.columns * step - GlintLook.gap,
                    height: 3 * step - GlintLook.gap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final (i, tile) in tiles.indexed)
                          Positioned(
                            key: ValueKey(tile.id),
                            left: layout.cells[i].column * step,
                            top: layout.cells[i].row * step,
                            width: tile.size.width * step - GlintLook.gap,
                            height: tile.size.height * step - GlintLook.gap,
                            child: FocusTraversalOrder(
                              order: NumericFocusOrder(layout.cells[i].column * 10.0 + layout.cells[i].row),
                              child: tile.build(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// One tile on the glance page.
class GlanceTile {
  final String id;
  final GlintSize size;
  final Widget Function(BuildContext context) build;
  const GlanceTile(this.id, this.size, this.build);
}

/// The glance page's tiles, in order: what's for a person first (a kid's time, the family), then the day (events,
/// to-do lists, the house, the weather, notifications), then the ways out (All apps, Home Assistant, Settings). Only
/// tiles with something to say are there.
List<GlanceTile> glanceTiles({
  required HaLockState lock,
  List<GlancePerson> people = const [],
  List<GlanceList> lists = const [],
  List<GlintHouseItem> house = const [],
  WeatherData? weather,
  List<CalendarEvent> events = const [],
  List<NotificationItem>? notifications,
  bool haPanel = false,
}) {
  final now = DateTime.now();
  final tiles = <GlanceTile>[GlanceTile("clock", GlintSize.medium, (_) => const ClockFace())];
  if (TimeUpFace.shows(lock, nothingToOpen: false, now: now)) {
    tiles.add(GlanceTile("time", GlintSize.wide, (_) => TimeUpFace(state: lock)));
  }
  if (lock.kids && lock.groups.isNotEmpty) {
    tiles.add(GlanceTile(
      "screen-time",
      GlintSize.wide,
      (_) => PeekFace(id: "glance:screen-time", items: [
        for (final g in lock.groups)
          PeekItem("screen time left", g.name, small: g.minutesLeft <= 0 ? "none left today" : "${g.minutesLeft} min"),
      ]),
    ));
  }
  if (people.isNotEmpty) {
    tiles.add(GlanceTile(
      "family",
      GlintSize.wide,
      (_) => PeekFace(id: "glance:family", items: [
        // Glint's Family rule: first names, lowercase; place names keep their case
        for (final p in people) PeekItem("family", ProfileFace.shownName(p.name), small: p.where),
      ]),
    ));
  }
  if (events.isNotEmpty) tiles.add(GlanceTile("calendar", GlintSize.wide, (_) => CalendarFace(events: events)));
  if (lists.isNotEmpty) {
    tiles.add(GlanceTile(
      "lists",
      GlintSize.wide,
      (_) => PeekFace(id: "glance:lists", items: [
        for (final l in lists) PeekItem("to do", l.name, small: "${l.open} left"),
      ]),
    ));
  }
  if (house.isNotEmpty) tiles.add(GlanceTile("house", GlintSize.wide, (_) => HouseFace(items: house)));
  if (weather != null && weather.currentTemp != null) {
    tiles.add(GlanceTile("weather", GlintSize.medium, (_) => WeatherFace(data: weather)));
  }
  if (notifications != null) {
    tiles.add(GlanceTile("notifications", GlintSize.wide, (_) => NotificationsFace(items: notifications)));
  }
  tiles.add(GlanceTile("all-apps", GlintSize.small, (_) => const AllAppsFace()));
  if (haPanel) tiles.add(GlanceTile("home-assistant", GlintSize.small, (_) => const HomeAssistantFace()));
  tiles.add(GlanceTile("settings", GlintSize.small, (_) => const SettingsFace()));
  return tiles;
}
