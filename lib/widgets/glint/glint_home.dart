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

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_layout.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The Glint home: Hearth's home in the design language of Glint (the household's phone launcher). Live tiles of
/// frosted glass over the picture, in three rows that run on to the right: the clock, what you were watching, the
/// weather, today's next event, who's watching, the Favorites apps, then all the apps and Settings.
///
/// Live tiles turn to their next face slowly, one at a time. Left alone a while, the home rests: the glass goes clear
/// and the picture shows through, until the next press of a key.
///
/// [focusNode] wraps the tiles, so the home's landing (a profile arriving, the Home button) finds the first one.
class GlintHome extends StatefulWidget {
  final FocusNode focusNode;
  const GlintHome({super.key, required this.focusNode});

  @override
  State<GlintHome> createState() => _GlintHomeState();
}

class _GlintHomeState extends State<GlintHome> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rest = AnimationController(vsync: this, duration: GlintLook.restFade);
  final GlintTicker _ticker = GlintTicker();
  final ScrollController _scroll = ScrollController();
  late final GlintHouseFeed _house;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _house = GlintHouseFeed(context.read<FLauncherChannel>().getHaConnection)..addListener(_houseChanged);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    WidgetsBinding.instance.addObserver(this);
    _rest.addListener(() => _ticker.paused = _rest.value > 0);
    _awake();
    // Arriving with nothing selected (the first start, the classic home switched off): the first tile
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectFirstIfNothing());
  }

  void _houseChanged() {
    if (mounted) setState(() {});
  }

  void _selectFirstIfNothing() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null && focus is! FocusScopeNode) return;
    widget.focusNode.descendants
        .firstWhereOrNull((n) => n.canRequestFocus && !n.skipTraversal && n.context != null)
        ?.requestFocus();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    WidgetsBinding.instance.removeObserver(this);
    _house
      ..removeListener(_houseChanged)
      ..dispose();
    _idle?.cancel();
    _rest.dispose();
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Away (an app in front, the TV asleep), the home neither rests nor counts down to it; back, it's awake at once,
  /// so the first key moves the selection instead of only waking it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rest.value = 0;
      _awake();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _idle?.cancel();
    }
  }

  /// Any key wakes the home. The first press out of a deep rest only wakes it, so nothing moves or opens unseen.
  bool _onAnyKey(KeyEvent event) {
    final wasResting = _rest.value > 0.5;
    _awake();
    return wasResting && event is KeyDownEvent && mounted && (ModalRoute.of(context)?.isCurrent ?? true);
  }

  void _awake() {
    if (_rest.value > 0) _rest.animateBack(0, duration: const Duration(milliseconds: 220));
    _idle?.cancel();
    _idle = Timer(GlintLook.restAfter, () {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _rest.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = context.watch<AppsService>();
    final settings = context.watch<SettingsService>();
    final watchNext = context.watch<WatchNextService?>();
    final weather = context.watch<WeatherService?>()?.weatherData;
    final calendar = context.watch<CalendarService?>();
    final profiles = context.watch<ProfileService?>();

    final tiles = <_Tile>[_Tile("clock", GlintSize.medium, (_) => const ClockFace())];

    final programs = (watchNext != null && settings.showContinueWatching && watchNext.hasPermission)
        ? watchNext.visiblePrograms(settings, apps).take(3).toList()
        : const <WatchNextProgram>[];
    if (programs.isNotEmpty) {
      tiles.add(_Tile("continue", GlintSize.large, (_) => ContinueWatchingFace(programs: List.of(programs))));
    }
    if (weather != null && weather.currentTemp != null) {
      tiles.add(_Tile("weather", GlintSize.medium, (_) => WeatherFace(data: weather)));
    }
    final events = calendar?.today().take(3).toList() ?? const <CalendarEvent>[];
    if (events.isNotEmpty) tiles.add(_Tile("calendar", GlintSize.wide, (_) => CalendarFace(events: events)));

    if (_house.items.isNotEmpty) {
      tiles.add(_Tile("house", GlintSize.wide, (_) => HouseFace(items: _house.items)));
    }

    final notifications = context.watch<NotificationsService?>();
    if (notifications != null && notifications.hasPermission && settings.showNotificationsWidgetInStatusBar) {
      tiles.add(_Tile("notifications", GlintSize.wide, (_) => NotificationsFace(items: notifications.notifications)));
    }

    final name = profiles?.activeProfileName;
    if (name != null && name.isNotEmpty) {
      tiles.add(
        _Tile("profile", GlintSize.small, (_) => ProfileFace(name: name, avatar: profiles?.activeProfileAvatar)),
      );
    }

    final sections = apps.launcherSections.whereType<Category>().toList();
    final favorites = sections.firstWhereOrNull(
      (c) => c.name == AppsService.favoritesName && c.applications.isNotEmpty,
    );
    // No Favorites: the first section with apps in it stands in, so Start isn't empty
    final Category? shown = favorites ?? sections.firstWhereOrNull((c) => c.applications.isNotEmpty);
    final List<App> startApps = shown?.applications.take(10).toList() ?? const [];
    for (final (i, app) in startApps.indexed) {
      tiles.add(
        _Tile(
          "app:${app.packageName}",
          i < 2 ? GlintSize.wide : GlintSize.small,
          (_) => AppFace(app: app, category: shown, wide: i < 2),
        ),
      );
    }
    tiles.add(_Tile("all-apps", GlintSize.small, (_) => const AllAppsFace()));
    tiles.add(_Tile("search", GlintSize.small, (_) => const SearchFace()));
    if (settings.haPanelEnabled) tiles.add(_Tile("home-assistant", GlintSize.small, (_) => const HomeAssistantFace()));
    tiles.add(_Tile("settings", GlintSize.small, (_) => const SettingsFace()));

    final layout = GlintLayout.pack([for (final t in tiles) t.size]);

    return Material(
      type: MaterialType.transparency,
      child: GlintRest(
        rest: _rest,
        child: GlintTickerScope(
          ticker: _ticker,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The top stays open, so the picture shows over the tiles (Glint's "open top")
              final top = constraints.maxHeight * 0.28, bottom = 40.0, side = 48.0;
              final cell = ((constraints.maxHeight - top - bottom - 2 * GlintLook.gap) / 3).clamp(60.0, 200.0);
              final step = cell + GlintLook.gap;
              final width = layout.columns * step - GlintLook.gap;
              return FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Focus(
                  focusNode: widget.focusNode,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.fromLTRB(side, top, side * 2, bottom),
                    child: SizedBox(
                      width: width,
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
                              // Left to right, top to bottom within a column: the order the D-pad walks when it has to choose
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
            },
          ),
        ),
      ),
    );
  }
}

class _Tile {
  final String id;
  final GlintSize size;
  final Widget Function(BuildContext context) build;
  const _Tile(this.id, this.size, this.build);
}
