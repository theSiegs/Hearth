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
import 'dart:math' as math;

import 'package:flauncher/actions.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_rotation.dart';
import 'package:flauncher/widgets/glint/glance_weather.dart';
import 'package:flauncher/widgets/glint/glint_apps_page.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flauncher/widgets/glint/ha_lock_feed.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

/// The glance page (Peek: Top shelf + glance page), down from the dock: its own page over a dark backdrop that hides
/// the home (the top bar stays, without its weather and date and time: the page's own tiles have them). Live tiles on a
/// clean two-column grid inside the TV's safe area: a kid's time (what's held, the minutes left in each group), today
/// (the date, what's on next), the weather, the family and where they are, the to-do lists and what's going on around
/// the house; then a small row of ways out (All apps, Home Assistant's panel, notifications, Settings). The family and
/// the house show only where the profile shows them ([householdTilesShown]).
///
/// The tiles are live: while one isn't selected, its face turns slowly through what it has (one page-wide
/// [GlanceRotation], one tile at a time). The selected tile holds still. Pressing a tile always opens that tile's own
/// view ([GlanceView]), whatever its face shows.
///
/// It slides up and fades in, its tiles following one after another, and plays that backwards as it goes ([leave]).
/// It's only built while it's up: Home Assistant is followed only then. Back, or Up from its top row, asks to close
/// ([onClose]); [onGone] is called once it has gone.
class GlancePage extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback? onGone;
  const GlancePage({super.key, required this.onClose, this.onGone});

  /// The page coming in, and going.
  static const Duration openTime = Duration(milliseconds: 280), closeTime = Duration(milliseconds: 200);

  /// Each tile's own fade and rise, and how far apart they start.
  static const Duration tileTime = Duration(milliseconds: 200), tileStagger = Duration(milliseconds: 30);

  /// The latest a tile starts coming in after the page, so the whole arrival stays about 300 ms.
  static const Duration staggerCap = Duration(milliseconds: 120);

  @override
  State<GlancePage> createState() => GlancePageState();
}

class GlancePageState extends State<GlancePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode(debugLabel: "glance_page");
  late final GlintHouseFeed _house;
  late final GlanceHaFeed _family;
  late final HaLockFeed _lock;
  late final AnimationController _show;
  late final bool _moves;
  final GlanceRotation _rotation = GlanceRotation();
  final Set<String> _turning = {};
  bool _leaving = false;
  bool _viewOpen = false;
  bool _resumed = true;

  /// Each person's Google TV profile photo, looked up once per page (null: none). The family tile waits until everyone
  /// on it has been looked up, so a face never swaps on its own.
  final Map<String, Uint8List?> _photos = {};
  final Set<String> _lookingUp = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final channel = context.read<FLauncherChannel>();
    _moves = GlintMotion.fromName(context.read<SettingsService>().glintMotion).pace.moves;
    _show = AnimationController(
      vsync: this,
      duration: _moves ? GlancePage.openTime : Duration.zero,
      reverseDuration: _moves ? GlancePage.closeTime : Duration.zero,
    )..forward();
    _house = GlintHouseFeed(channel.getHaConnection)..addListener(_changed);
    _family = GlanceHaFeed(channel.getHaConnection)..addListener(_changed);
    _lock = HaLockFeed(channel.getHaLockState)..addListener(_changed);
    _turn();
    // The first tile takes the selection as the page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.descendants
          .where((n) => n.canRequestFocus && !n.skipTraversal && n.context != null)
          .firstOrNull
          ?.requestFocus();
    });
  }

  /// The tiles turn only while they can be seen and may move: not at Motion: Still, not while Hearth is behind
  /// something else, not under a tile's view, not as the page goes.
  void _turn() => _rotation.running = _moves && _resumed && !_viewOpen && !_leaving;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _turn();
  }

  /// Plays the page out, then [GlancePage.onGone]. It takes no keys meanwhile.
  void leave() {
    if (_leaving) return;
    setState(() => _leaving = true);
    _turn();
    _show.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onGone?.call();
    });
  }

  void _changed() {
    if (!mounted) return;
    for (final p in _family.people) {
      if (_photos.containsKey(p.name) || !_lookingUp.add(p.name)) continue;
      unawaited(_lookUp(p.name));
    }
    setState(() {});
  }

  /// A person's Google TV profile photo, which Hearth saves from the profile chooser under the profile's name: by
  /// their whole name, else their first name (as a TV profile is usually named).
  Future<void> _lookUp(String name) async {
    Uint8List? found;
    final channel = context.read<FLauncherChannel>();
    for (final candidate in profileNamesFor(name)) {
      try {
        final avatar = await channel.getProfileAvatar(candidate);
        if (avatar.png != null && avatar.png!.isNotEmpty) {
          found = avatar.png;
          break;
        }
      } catch (err) {
        noteFailure('glance_page', err);
      }
    }
    if (!mounted) return;
    _lookingUp.remove(name);
    setState(() => _photos[name] = found);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    for (final feed in <ChangeNotifier>[_house, _family, _lock]) {
      feed
        ..removeListener(_changed)
        ..dispose();
    }
    _show.dispose();
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

  /// What the page shows now; [GlanceView]s read it too, so a view shows what's current.
  GlanceInputs _inputs(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final now = DateTime.now();
    final notifications = () {
      final n = context.watch<NotificationsService?>();
      return n != null && n.hasPermission && settings.showNotificationsWidgetInStatusBar ? n.notifications : null;
    }();
    // The family and the house only where this profile shows them (Look > Family and house)
    final household = householdTilesShown(context);
    return GlanceInputs(
      lock: _lock.state,
      // Shown once everyone on it has been looked up
      people: household && _family.people.every((p) => _photos.containsKey(p.name)) ? _family.people : const [],
      photos: _photos,
      connection: _family.connection,
      lists: _family.lists,
      house: household ? _house.items : const [],
      // The TV's own weather (Settings), else Home Assistant's
      weather: GlanceWeather.fromHearth(context.watch<WeatherService?>()?.weatherData, now) ?? _family.weatherAt(now),
      events: context.watch<CalendarService?>()?.today().take(GlanceInputs.eventCount).toList() ?? const [],
      notifications: notifications,
      haPanel: settings.haPanelEnabled,
      now: now,
    );
  }

  /// Opens a tile's view over the page; the tiles hold still under it.
  Future<void> _open(GlanceView view) async {
    if (_viewOpen || _leaving) return;
    setState(() => _viewOpen = true);
    _turn();
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => ListenableBuilder(
          listenable: Listenable.merge([_family, _house, _lock]),
          builder: (context, _) => GlanceViewPanel(view: view, inputs: _inputs(context), onDone: _family.markDone),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _viewOpen = false);
        _turn();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final all = glanceTilesFor(_inputs(context));
    final tiles = [for (final t in all) if (!t.action) t];
    final actions = [for (final t in all) if (t.action) t];
    // Tell the rotation how many faces each tile has, and forget tiles that went
    final ids = {for (final t in tiles) t.id};
    for (final gone in _turning.difference(ids)) {
      _rotation.remove(gone);
    }
    _turning
      ..clear()
      ..addAll(ids);
    for (final t in tiles) {
      _rotation.setFaces(t.id, t.faces);
    }
    final opening = !_show.isCompleted;

    return Material(
      key: const Key("glance_page"),
      type: MaterialType.transparency,
      child: ExcludeFocus(
        excluding: _leaving,
        child: IgnorePointer(
          ignoring: _leaving,
          child: GlintTileStyle(
            glow: settings.accentColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(
                  opacity: CurvedAnimation(parent: _show, curve: Curves.easeOut),
                  child: const _Backdrop(),
                ),
                FadeTransition(
                  // Comes in tile by tile (below); goes as one
                  opacity: _leaving ? _show : kAlwaysCompleteAnimation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                        .animate(CurvedAnimation(parent: _show, curve: Curves.easeOutCubic)),
                    child: Focus(
                      focusNode: _focusNode,
                      onKeyEvent: _onKey,
                      child: FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: LayoutBuilder(
                          builder: (context, box) => _layout(context, box, tiles, actions, opening: opening),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The grid inside the TV's safe area, under the top bar, with the ways out in a row along the bottom.
  Widget _layout(BuildContext context, BoxConstraints box, List<GlanceTile> tiles, List<GlanceTile> actions,
      {required bool opening}) {
    final g = GlanceGrid.fit(box.biggest, tiles.length);
    Duration delay(int i) {
      if (!opening || !_moves) return Duration.zero;
      final d = GlancePage.tileStagger * i;
      return d > GlancePage.staggerCap ? GlancePage.staggerCap : d;
    }

    final grid = SizedBox(
      width: g.width,
      height: g.contentHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (i, tile) in tiles.indexed)
            AnimatedPositioned(
              key: ValueKey(tile.id),
              duration: _moves ? const Duration(milliseconds: 240) : Duration.zero,
              curve: Curves.easeOutCubic,
              left: g.left(i),
              top: g.top(i),
              width: g.tileWidth,
              height: g.tileHeight,
              child: _TileIn(
                delay: delay(i),
                moves: _moves,
                child: GlanceLiveTile(tile: tile, rotation: _rotation, onOpen: _open),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(g.side, g.topInset, g.side, g.bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: g.gridHeight,
            // Scrolls only when there's more than fits; otherwise nothing clips a selected tile's glow
            child: g.scrolls
                ? SingleChildScrollView(
                    clipBehavior: Clip.hardEdge,
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: grid),
                  )
                : Align(alignment: Alignment.topLeft, child: grid),
          ),
          const SizedBox(height: GlanceGrid.actionsGap),
          SizedBox(
            height: GlanceGrid.actionsHeight,
            child: Row(
              children: [
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: GlanceGrid.gap),
                  _TileIn(
                    key: ValueKey(action.id),
                    delay: delay(tiles.length + i),
                    moves: _moves,
                    child: Builder(builder: (context) => action.build(context, 0, null)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the glance page's tiles go on a screen: inside the TV's safe area (5% at the sides and bottom), below the top
/// bar, two columns of equal tiles, three rows in view; more scroll.
class GlanceGrid {
  static const double gap = 16;
  static const double actionsHeight = 48, actionsGap = 20;
  static const int columns = 2, rowsInView = 3;

  final double side, topInset, bottomInset;
  final double width, gridHeight, tileWidth, tileHeight;
  final int count;

  GlanceGrid._(this.side, this.topInset, this.bottomInset, this.width, this.gridHeight, this.tileWidth,
      this.tileHeight, this.count);

  factory GlanceGrid.fit(Size screen, int count) {
    final side = (screen.width * 0.05).clamp(24.0, 96.0);
    const topInset = kToolbarHeight + 16;
    final bottomInset = (screen.height * 0.05).clamp(16.0, 64.0);
    final width = math.max(0.0, screen.width - 2 * side);
    final gridHeight = math.max(0.0, screen.height - topInset - bottomInset - actionsHeight - actionsGap);
    final tileWidth = math.max(0.0, (width - gap * (columns - 1)) / columns);
    final tileHeight = ((gridHeight - gap * (rowsInView - 1)) / rowsInView).clamp(72.0, 160.0);
    return GlanceGrid._(side, topInset, bottomInset, width, gridHeight, tileWidth, tileHeight, count);
  }

  int get rows => (count / columns).ceil();
  double get contentHeight => rows == 0 ? 0 : rows * tileHeight + (rows - 1) * gap;
  bool get scrolls => contentHeight > gridHeight;
  double left(int i) => (i % columns) * (tileWidth + gap);
  double top(int i) => (i ~/ columns) * (tileHeight + gap);
}

/// The page's own backdrop: the wallpaper dimmed well down, a little less under the top bar so it still reads.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.1, 0.22, 1],
          colors: [Color(0x80000000), Color(0x99000000), Color(0xD1000000), Color(0xE0000000)],
        ),
      ),
    ),
  );
}

/// A tile coming in: a short fade and rise, [delay] after the page starts (a tile that arrives later, as Home
/// Assistant answers, comes in the same way).
class _TileIn extends StatefulWidget {
  final Duration delay;
  final bool moves;
  final Widget child;
  const _TileIn({super.key, required this.delay, required this.moves, required this.child});

  @override
  State<_TileIn> createState() => _TileInState();
}

class _TileInState extends State<_TileIn> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: GlancePage.tileTime);
  late final Animation<double> _curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (!widget.moves) {
      _in.value = 1;
    } else if (widget.delay == Duration.zero) {
      _in.forward();
    } else {
      _wait = Timer(widget.delay, () {
        if (mounted) _in.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_curve),
      child: widget.child,
    ),
  );
}

/// The Google TV profile names a person could have: their whole name, then their first name.
List<String> profileNamesFor(String name) {
  final whole = name.trim();
  final first = whole.split(RegExp(r"\s+")).first;
  return [if (whole.isNotEmpty) whole, if (first.isNotEmpty && first != whole) first];
}

/// A person's name as the glance page shows it: the first name, capitalised ("alex rivera" is "Alex").
String glanceName(String name) {
  final first = name.trim().split(RegExp(r"\s+")).first;
  if (first.isEmpty) return name.trim();
  return first.characters.first.toUpperCase() + first.characters.skip(1).string;
}

/// A place as the glance page shows it: capitalised ("school" is "School"); a quiet dash for someone Home Assistant
/// can't place.
String glancePlace(String where) {
  final w = where.trim();
  if (w.isEmpty) return "—";
  return w.characters.first.toUpperCase() + w.characters.skip(1).string;
}

/// What pressing a tile opens: one per tile, whatever its face shows.
enum GlanceView { screenTime, today, weather, family, lists, house }

/// One tile on the glance page; an [action] is a small one in the row of ways out.
///
/// [build] makes the tile's face for face number [face] (of [faces]) with [onPressed] as what pressing it does. The
/// page hands every face of a tile the same [onPressed], opening the tile's [view]: what a tile shows never changes
/// what pressing it does. Tiles without a [view] (the ways out, a kid's time) do their own one thing.
class GlanceTile {
  final String id;
  final bool action;
  final int faces;
  final GlanceView? view;
  final Widget Function(BuildContext context, int face, VoidCallback? onPressed) build;
  const GlanceTile(this.id, this.build, {this.action = false, this.faces = 1, this.view});
}

/// Everything the glance page shows, at one moment.
class GlanceInputs {
  final HaLockState lock;
  final List<GlancePerson> people;
  final Map<String, Uint8List?> photos;
  final ({String url, String token})? connection;
  final List<GlanceList> lists;
  final List<GlintHouseItem> house;
  final GlanceWeather? weather;
  final List<CalendarEvent> events;
  final List<NotificationItem>? notifications;
  final bool haPanel;
  final DateTime now;

  /// How many of today's events the page takes.
  static const int eventCount = 6;

  GlanceInputs({
    required this.lock,
    this.people = const [],
    this.photos = const {},
    this.connection,
    this.lists = const [],
    this.house = const [],
    this.weather,
    this.events = const [],
    this.notifications,
    this.haPanel = false,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  /// Today's events still to come (or on now, or all day).
  List<CalendarEvent> get upcoming => [for (final e in events) if (e.allDay || e.end.isAfter(now)) e];

  /// Everyone on the family tile, each with their face.
  List<GlanceMember> get members => [
    for (final p in people)
      GlanceMember(
        glanceName(p.name),
        p.where,
        // Keyed by whose it is: one person's face never carries over to the next
        PersonFace(
          key: ValueKey("face:${p.name}"),
          name: glanceName(p.name),
          photo: photos[p.name],
          picture: p.picture == null ? null : HaPanelService.pictureRequest(p.picture!, connection),
          size: GlanceFamilyFace.faceSize,
        ),
      ),
  ];
}

/// The glance page's tiles, in order: a kid's time first, then today, the weather, the family, the to-do lists and
/// the house, then the ways out (All apps, Home Assistant, notifications, Settings). Only tiles with something to say
/// are there; today always is.
List<GlanceTile> glanceTiles({
  required HaLockState lock,
  List<GlancePerson> people = const [],
  Map<String, Uint8List?> photos = const {},
  ({String url, String token})? connection,
  List<GlanceList> lists = const [],
  List<GlintHouseItem> house = const [],
  GlanceWeather? weather,
  List<CalendarEvent> events = const [],
  List<NotificationItem>? notifications,
  bool haPanel = false,
  DateTime? now,
}) => glanceTilesFor(GlanceInputs(
  lock: lock,
  people: people,
  photos: photos,
  connection: connection,
  lists: lists,
  house: house,
  weather: weather,
  events: events,
  notifications: notifications,
  haPanel: haPanel,
  now: now,
));

List<GlanceTile> glanceTilesFor(GlanceInputs d) {
  final tiles = <GlanceTile>[];
  final lock = d.lock;
  if (TimeUpFace.shows(lock, nothingToOpen: false, now: d.now)) {
    tiles.add(GlanceTile("time", (_, _, _) => TimeUpFace(state: lock)));
  }
  if (lock.kids && lock.groups.isNotEmpty) {
    final rows = [for (final g in lock.groups) (g.name, g.minutesLeft <= 0 ? "none today" : "${g.minutesLeft} min")];
    tiles.add(GlanceTile(
      "screen-time",
      view: GlanceView.screenTime,
      faces: GlanceTableFace.pagesOf(rows.length),
      (_, face, onPressed) => GlanceTableFace(label: "Screen time left", rows: rows, face: face, onPressed: onPressed),
    ));
  }
  // Today is always there: ahead of what Home Assistant brings a moment later, so the page doesn't shift under the
  // selection as it arrives. It shows the next few events at once and doesn't turn.
  final upcoming = d.upcoming;
  tiles.add(GlanceTile(
    "today",
    view: GlanceView.today,
    (_, _, onPressed) => GlanceTodayFace(events: upcoming, onPressed: onPressed, clock: () => d.now),
  ));
  final weather = d.weather;
  if (weather != null) {
    tiles.add(GlanceTile(
      "weather",
      view: GlanceView.weather,
      faces: GlanceWeatherFace.facesOf(weather),
      (_, face, onPressed) => GlanceWeatherFace(weather: weather, face: face, onPressed: onPressed, clock: () => d.now),
    ));
  }
  if (d.people.isNotEmpty) {
    final members = d.members;
    tiles.add(GlanceTile(
      "family",
      view: GlanceView.family,
      faces: GlanceFamilyFace.facesOf(members),
      (_, face, onPressed) => GlanceFamilyFace(members: members, face: face, onPressed: onPressed),
    ));
  }
  if (d.lists.isNotEmpty) {
    final lists = d.lists;
    tiles.add(GlanceTile(
      "lists",
      view: GlanceView.lists,
      faces: GlanceListsFace.facesOf(lists),
      (_, face, onPressed) => GlanceListsFace(lists: lists, face: face, onPressed: onPressed),
    ));
  }
  if (d.house.isNotEmpty) {
    final house = d.house;
    tiles.add(GlanceTile(
      "house",
      view: GlanceView.house,
      faces: house.length,
      (_, face, onPressed) => GlanceHouseFace(items: house, face: face, onPressed: onPressed),
    ));
  }

  tiles.add(GlanceTile(
    "all-apps",
    action: true,
    (context, _, _) =>
        GlanceAction(icon: Icons.apps_rounded, name: "All apps", onPressed: () => GlintAppsPage.open(context)),
  ));
  if (d.haPanel) {
    tiles.add(GlanceTile(
      "home-assistant",
      action: true,
      (context, _, _) => GlanceAction(
        icon: Icons.home_outlined,
        name: "Home",
        onPressed: () => Actions.maybeInvoke(context, const OpenHaPanelIntent()),
      ),
    ));
  }
  final notifications = d.notifications;
  if (notifications != null) {
    tiles.add(GlanceTile(
      "notifications",
      action: true,
      (context, _, _) => GlanceAction(
        icon: notifications.isEmpty ? Icons.notifications_none_rounded : Icons.notifications_rounded,
        name: "Notifications",
        count: notifications.length,
        onPressed: () =>
            showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const NotificationsPanel()),
      ),
    ));
  }
  tiles.add(GlanceTile(
    "settings",
    action: true,
    (context, _, _) => GlanceAction(
      icon: Icons.settings_outlined,
      name: "Settings",
      onPressed: () =>
          showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const SettingsPanel()),
    ),
  ));
  return tiles;
}

/// A tile on the page, live: its face follows the [rotation]'s index for it (only this tile rebuilds when it turns),
/// it tells the rotation when it has the selection (so it holds still), and pressing it opens its own view through
/// [onOpen] (the same, whatever face is up).
class GlanceLiveTile extends StatelessWidget {
  final GlanceTile tile;
  final GlanceRotation rotation;
  final ValueChanged<GlanceView> onOpen;
  const GlanceLiveTile({super.key, required this.tile, required this.rotation, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final view = tile.view;
    // One action per tile, made from the tile alone, never from the face
    final VoidCallback? onPressed = view == null ? null : () => onOpen(view);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => rotation.focus(tile.id, focused),
      child: ValueListenableBuilder<int>(
        valueListenable: rotation.indexOf(tile.id),
        builder: (context, index, _) => tile.build(context, tile.faces <= 1 ? 0 : index % tile.faces, onPressed),
      ),
    );
  }
}

/// Small tracked caps over a face.
Widget _label(String text) =>
    Text(text.toUpperCase(), style: GlintLook.label, maxLines: 1, overflow: TextOverflow.ellipsis);

/// A value that cross-fades when it changes (someone's place, minutes left).
class _Fading extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign align;
  const _Fading(this.text, this.style, {this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 280),
    layoutBuilder: (current, previous) => Stack(
      alignment: switch (align) {
        TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      children: [...previous, ?current],
    ),
    child: Text(
      text,
      key: ValueKey(text),
      style: style,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// A tile's face turning: the old face fades out as the new one fades in, slowly (no cut, no slide). Instant at
/// Motion: Still.
class GlanceFaceSwitch extends StatelessWidget {
  final int face;
  final Widget child;
  final AlignmentGeometry alignment;
  const GlanceFaceSwitch({super.key, required this.face, required this.child, this.alignment = Alignment.topLeft});

  static const Duration time = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService?>(context, listen: false);
    final moves = settings == null || GlintMotion.fromName(settings.glintMotion).pace.moves;
    return AnimatedSwitcher(
      duration: moves ? time : Duration.zero,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(face), child: child),
    );
  }
}

/// Today: the date, and the next few of today's events at once, one to a line (as many as fit, at most [shown]), with
/// how many more there are. It doesn't turn: the whole list is the tile's view.
class GlanceTodayFace extends StatelessWidget {
  final List<CalendarEvent> events;
  final VoidCallback? onPressed;
  final DateTime Function() clock;
  const GlanceTodayFace({super.key, this.events = const [], this.onPressed, this.clock = DateTime.now});

  /// At most this many events on the tile.
  static const int shown = 3;

  /// Each event's line.
  static const double lineHeight = 21;

  /// How many events fit in [height], from one up to [shown].
  static int fitting(double height) => (height / lineHeight).floor().clamp(1, shown);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = clock();
    String date;
    try {
      date = DateFormat("EEEE, MMMM d").format(now);
    } catch (_) {
      date = DateFormat("EEE, MMM d").format(now);
    }
    return GlintTile(
      key: const Key("glance_today"),
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: LayoutBuilder(builder: (context, box) {
        // The date takes about 26 of the height; the events what's left
        final count = math.min(events.length, fitting(box.maxHeight - 30));
        final more = events.length - count;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(date,
                      style: GlintLook.primary.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (more > 0) Text(l10n.glanceMoreEvents(more), style: GlintLook.label),
              ],
            ),
            const SizedBox(height: 4),
            if (events.isEmpty)
              Text(l10n.glanceNothingElseToday, style: GlintLook.secondaryText, maxLines: 1)
            else
              for (final e in events.take(count)) GlanceEventRow(event: e, now: now),
          ],
        );
      }),
    );
  }
}

/// One of today's events on one line: a dot in its calendar's color, when (in the accent: all day, now, or when it
/// starts), what.
class GlanceEventRow extends StatelessWidget {
  final CalendarEvent event;
  final DateTime now;
  const GlanceEventRow({super.key, required this.event, required this.now});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService?>(context, listen: false);
    final e = event;
    String when;
    if (e.allDay) {
      when = l10n.glanceAllDay;
    } else if (e.isOn(now)) {
      when = l10n.glanceNow;
    } else {
      try {
        when = DateFormat(settings?.timeFormat ?? "h:mm a").format(e.start);
      } catch (_) {
        when = DateFormat("h:mm").format(e.start);
      }
    }
    return SizedBox(
      height: GlanceTodayFace.lineHeight,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: e.color == null ? GlintLook.secondary : Color(e.color!).withValues(alpha: 1),
              shape: BoxShape.circle,
            ),
          ),
          Text(when, style: GlintLook.secondaryText.copyWith(color: GlintLook.accentText()), maxLines: 1),
          const SizedBox(width: 10),
          Expanded(
            child: Text(e.summary,
                style: GlintLook.primary.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// One event: when (in the accent) over what.
class GlanceEventLine extends StatelessWidget {
  final CalendarEvent event;
  final DateTime now;
  const GlanceEventLine({super.key, required this.event, required this.now});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService?>(context, listen: false);
    String time(DateTime t) {
      try {
        return DateFormat(settings?.timeFormat ?? "h:mm a").format(t);
      } catch (_) {
        return DateFormat("h:mm").format(t);
      }
    }

    final e = event;
    final when = e.allDay ? "All day" : (e.isOn(now) ? "Now, until ${time(e.end)}" : time(e.start));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (e.color != null)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: Color(e.color!).withValues(alpha: 1), shape: BoxShape.circle),
              ),
            Text(when, style: GlintLook.secondaryText.copyWith(color: GlintLook.accentText())),
          ],
        ),
        Text(e.summary,
            style: GlintLook.primary.copyWith(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// The weather: now (the sky, the temperature, today's high and low), then the next hours, then the coming days, a
/// face each.
class GlanceWeatherFace extends StatelessWidget {
  final GlanceWeather weather;
  final int face;
  final VoidCallback? onPressed;
  final DateTime Function() clock;
  const GlanceWeatherFace(
      {super.key, required this.weather, this.face = 0, this.onPressed, this.clock = DateTime.now});

  /// Now, and the hours and the days when there are some.
  static int facesOf(GlanceWeather w) => 1 + (w.hours.isNotEmpty ? 1 : 0) + (w.days.isNotEmpty ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final fahrenheit = Provider.of<SettingsService?>(context, listen: false)?.useFahrenheit ?? false;
    final faces = <(String, Widget Function())>[
      ("Weather", () => GlanceWeatherNow(weather: weather, fahrenheit: fahrenheit)),
      if (weather.hours.isNotEmpty)
        ("Next hours", () => GlanceWeatherHours(weather: weather, fahrenheit: fahrenheit)),
      if (weather.days.isNotEmpty) ("Coming days", () => GlanceWeatherDays(weather: weather, fahrenheit: fahrenheit)),
    ];
    final i = face % faces.length;
    return GlintTile(
      key: const Key("glance_weather"),
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: GlanceFaceSwitch(
        face: i,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(faces[i].$1),
            const SizedBox(height: 4),
            Expanded(child: faces[i].$2()),
          ],
        ),
      ),
    );
  }
}

/// The weather now: the sky, the temperature, and today's high and low.
class GlanceWeatherNow extends StatelessWidget {
  final GlanceWeather weather;
  final bool fahrenheit;
  const GlanceWeatherNow({super.key, required this.weather, required this.fahrenheit});

  @override
  Widget build(BuildContext context) {
    final w = weather;
    String deg(double? c) => GlanceWeather.degrees(c, fahrenheit: fahrenheit);
    final hiLo = [if (w.high != null) "H ${deg(w.high)}", if (w.low != null) "L ${deg(w.low)}"].join("  ");
    return Row(
      children: [
        Icon(w.icon, color: const Color(0xFFFFE0B8), size: 34, shadows: GlintLook.textShadow),
        const SizedBox(width: 12),
        Text(deg(w.temp), style: GlintLook.display(40)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (w.condition != null)
                Text(w.condition!,
                    style: GlintLook.primary.copyWith(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (hiLo.isNotEmpty) Text(hiLo, style: GlintLook.secondaryText, maxLines: 1),
            ],
          ),
        ),
      ],
    );
  }
}

/// A few hours or days side by side: a label over an icon over a temperature.
class _ForecastRow extends StatelessWidget {
  final List<(String, IconData, String)> items;
  const _ForecastRow(this.items);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (label, icon, value) in items)
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Icon(icon, color: const Color(0xFFFFE0B8), size: 20, shadows: GlintLook.textShadow),
              const SizedBox(height: 2),
              Text(value, style: GlintLook.primary.copyWith(fontSize: 16), maxLines: 1),
            ],
          ),
        ),
    ],
  );
}

String _hour(DateTime t) {
  try {
    return DateFormat.j().format(t);
  } catch (_) {
    return DateFormat("h a").format(t);
  }
}

/// The next hours.
class GlanceWeatherHours extends StatelessWidget {
  final GlanceWeather weather;
  final bool fahrenheit;
  const GlanceWeatherHours({super.key, required this.weather, required this.fahrenheit});

  @override
  Widget build(BuildContext context) => _ForecastRow([
    for (final h in weather.hours) (_hour(h.time), h.icon, GlanceWeather.degrees(h.temp, fahrenheit: fahrenheit)),
  ]);
}

/// The coming days: high and low.
class GlanceWeatherDays extends StatelessWidget {
  final GlanceWeather weather;
  final bool fahrenheit;
  const GlanceWeatherDays({super.key, required this.weather, required this.fahrenheit});

  @override
  Widget build(BuildContext context) => _ForecastRow([
    for (final day in weather.days)
      (
        DateFormat.E().format(day.date),
        day.icon,
        [
          GlanceWeather.degrees(day.high, fahrenheit: fahrenheit),
          if (day.low != null) GlanceWeather.degrees(day.low, fahrenheit: fahrenheit),
        ].join(" / "),
      ),
  ]);
}

/// One person on the family tile: their name as shown, where they are ("" when Home Assistant can't place them), their
/// face.
class GlanceMember {
  final String name;
  final String where;
  final Widget face;
  const GlanceMember(this.name, this.where, this.face);
}

/// The family: everyone at once, each a face with their name and where they are under it (a quiet dash for someone
/// Home Assistant can't place); more people than fit in a row take more than one face. Then, a face each, one person
/// at a time, larger: each of those Home Assistant can place.
class GlanceFamilyFace extends StatelessWidget {
  final List<GlanceMember> members;
  final int face;
  final VoidCallback? onPressed;
  const GlanceFamilyFace({super.key, required this.members, this.face = 0, this.onPressed});

  static const double faceSize = 40;

  /// At most this many side by side.
  static const int perPage = 6;

  /// Everyone, in rows of at most [perPage], split evenly ("6 + 1" is "4 + 3").
  static List<List<T>> pagesOf<T>(List<T> all) {
    if (all.isEmpty) return const [];
    final count = (all.length / perPage).ceil();
    final per = (all.length / count).ceil();
    return [for (var i = 0; i < all.length; i += per) all.sublist(i, math.min(i + per, all.length))];
  }

  /// The ones with a place, one at a time.
  static List<T> placed<T extends Object>(List<T> all, String Function(T) where) =>
      [for (final m in all) if (where(m).isNotEmpty) m];

  /// Everyone (a face or more), then each person with a place; one person alone has just the one face.
  static int facesOf(List<GlanceMember> members) {
    if (members.length < 2) return 1;
    return pagesOf(members).length + placed(members, (m) => m.where).length;
  }

  @override
  Widget build(BuildContext context) {
    final pages = pagesOf(members);
    final one = members.length < 2 ? const <GlanceMember>[] : placed(members, (m) => m.where);
    final count = pages.length + one.length;
    final i = count == 0 ? 0 : face % count;
    final small = members.length > 4;

    Widget person(GlanceMember m) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        m.face,
        const SizedBox(height: 6),
        Text(m.name,
            style: GlintLook.primary.copyWith(fontSize: small ? 14 : 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
        _Fading(m.where.isEmpty ? "—" : m.where, GlintLook.secondaryText, align: TextAlign.center),
      ],
    );
    Widget page(List<GlanceMember> some) => Row(
      key: ValueKey(some.map((m) => m.name).join("|")),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (final m in some) Expanded(child: Center(child: person(m)))],
    );
    Widget spotlight(GlanceMember m) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: 60, height: 60, child: FittedBox(child: m.face)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label("Family"),
                const SizedBox(height: 2),
                Text(m.name,
                    style: GlintLook.primary.copyWith(fontSize: 20), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(glancePlace(m.where), style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );

    return GlintTile(
      key: const Key("glance_family"),
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: GlanceFaceSwitch(
        face: i,
        alignment: Alignment.center,
        child: Center(child: i < pages.length ? page(pages[i]) : spotlight(one[i - pages.length])),
      ),
    );
  }
}

/// A few names and values, one to a line (the screen time left in each group); more than fit take more than one face.
/// Each value cross-fades when it changes.
class GlanceTableFace extends StatelessWidget {
  final String label;
  final List<(String, String)> rows;
  final int face;
  final VoidCallback? onPressed;
  const GlanceTableFace(
      {super.key, required this.label, required this.rows, this.face = 0, this.onPressed});

  static const int perPage = 3;

  static int pagesOf(int rows) => math.max(1, (rows / perPage).ceil());

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var i = 0; i < rows.length; i += perPage) rows.sublist(i, math.min(i + perPage, rows.length)),
    ];
    final i = pages.isEmpty ? 0 : face % pages.length;
    return GlintTile(
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 2),
          if (pages.isNotEmpty) GlanceFaceSwitch(face: i, child: _table(pages[i])),
        ],
      ),
    );
  }
}

/// Names and values, one to a line.
Widget _table(List<(String, String)> rows) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (final (name, value) in rows)
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: GlintLook.primary.copyWith(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            _Fading(value, GlintLook.secondaryText, align: TextAlign.end),
          ],
        ),
      ),
  ],
);

/// The to-do lists, a face each: the list's name, how much is left on it, and the first few things on it (as many as
/// fit, at most [shown]). Pressing opens the lists' view, where OK marks a thing done.
class GlanceListsFace extends StatelessWidget {
  final List<GlanceList> lists;
  final int face;
  final VoidCallback? onPressed;
  const GlanceListsFace({super.key, required this.lists, this.face = 0, this.onPressed});

  /// One face per list.
  static int facesOf(List<GlanceList> lists) => math.max(1, lists.length);

  /// At most this many of a list's things on the tile.
  static const int shown = 3;

  /// Each thing's line.
  static const double lineHeight = 21;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final i = lists.isEmpty ? 0 : face % lists.length;
    final Widget body;
    if (lists.isEmpty) {
      body = const SizedBox.shrink();
    } else {
      final l = lists[i];
      body = LayoutBuilder(
        builder: (context, box) {
          // The name takes about 22 of the height; the things what's left
          final fit = ((box.maxHeight - 24) / lineHeight).floor().clamp(1, shown);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.name,
                        style: GlintLook.primary.copyWith(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 12),
                  _Fading(l10n.glanceTodoLeft(l.open), GlintLook.label, align: TextAlign.end),
                ],
              ),
              const SizedBox(height: 2),
              for (final item in l.next.take(fit))
                SizedBox(
                  height: lineHeight,
                  child: Row(
                    children: [
                      Icon(Icons.radio_button_unchecked, size: 14, color: GlintLook.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.summary,
                            style: GlintLook.primary.copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }
    return GlintTile(
      key: const Key("glance_lists"),
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: GlanceFaceSwitch(face: i, child: body),
    );
  }
}

/// Around the house, one thing to a face: another TV playing something, someone in a car.
class GlanceHouseFace extends StatelessWidget {
  final List<GlintHouseItem> items;
  final int face;
  final VoidCallback? onPressed;
  const GlanceHouseFace({super.key, required this.items, this.face = 0, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final i = items.isEmpty ? 0 : face % items.length;
    return GlintTile(
      key: const Key("glance_house"),
      onPressed: onPressed,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: items.isEmpty
          ? const SizedBox.shrink()
          : GlanceFaceSwitch(face: i, child: _houseItem(items[i])),
    );
  }
}

Widget _houseItem(GlintHouseItem item, {int lines = 2}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    _label(item.label),
    const SizedBox(height: 4),
    Text(item.line, style: GlintLook.primary.copyWith(fontSize: 18), maxLines: lines, overflow: TextOverflow.ellipsis),
    if (item.detail != null)
      Text(item.detail!, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
  ],
);

/// A tile's view, over the glance page: everything the tile has, at once and still. Back closes it. In the lists' view
/// OK on a thing marks it done ([onDone]: false when Home Assistant didn't); without [onDone] the lists are only read.
class GlanceViewPanel extends StatelessWidget {
  final GlanceView view;
  final GlanceInputs inputs;
  final Future<bool> Function(String entity, GlanceTodoItem item)? onDone;
  const GlanceViewPanel({super.key, required this.view, required this.inputs, this.onDone});

  static String titleOf(GlanceView view) => switch (view) {
    GlanceView.screenTime => "Screen time left",
    GlanceView.today => "Today",
    GlanceView.weather => "Weather",
    GlanceView.family => "Family",
    GlanceView.lists => "To do",
    GlanceView.house => "Around the house",
  };

  @override
  Widget build(BuildContext context) {
    final d = inputs;
    final fahrenheit = Provider.of<SettingsService?>(context, listen: false)?.useFahrenheit ?? false;
    const gap = SizedBox(height: 14);
    final List<Widget> body = switch (view) {
      GlanceView.screenTime => [
        _table([for (final g in d.lock.groups) (g.name, g.minutesLeft <= 0 ? "none today" : "${g.minutesLeft} min")]),
      ],
      GlanceView.today => [
        Text(DateFormat("EEEE, MMMM d").format(d.now), style: GlintLook.primary.copyWith(fontSize: 19)),
        if (d.upcoming.isEmpty) ...[gap, Text("Nothing else on today", style: GlintLook.secondaryText)],
        for (final e in d.upcoming) ...[gap, GlanceEventLine(event: e, now: d.now)],
      ],
      GlanceView.weather => [
        if (d.weather != null) ...[
          SizedBox(height: 56, child: GlanceWeatherNow(weather: d.weather!, fahrenheit: fahrenheit)),
          if (d.weather!.hours.isNotEmpty) ...[
            gap,
            _label("Next hours"),
            SizedBox(height: 72, child: GlanceWeatherHours(weather: d.weather!, fahrenheit: fahrenheit)),
          ],
          if (d.weather!.days.isNotEmpty) ...[
            gap,
            _label("Coming days"),
            SizedBox(height: 72, child: GlanceWeatherDays(weather: d.weather!, fahrenheit: fahrenheit)),
          ],
        ],
      ],
      GlanceView.family => [
        for (final m in d.members)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                m.face,
                const SizedBox(width: 14),
                Expanded(child: Text(m.name, style: GlintLook.primary.copyWith(fontSize: 17))),
                Text(m.where.isEmpty ? "No location" : glancePlace(m.where), style: GlintLook.secondaryText),
              ],
            ),
          ),
      ],
      GlanceView.lists => [GlanceTodoView(lists: d.lists, onDone: onDone)],
      GlanceView.house => [
        for (final item in d.house) ...[_houseItem(item, lines: 3), gap],
      ],
    };
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape, LogicalKeyboardKey.browserBack}
                .contains(event.logicalKey)) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            key: Key("glance_view_${view.name}"),
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            decoration: BoxDecoration(
              color: const Color(0xF01A1714),
              borderRadius: BorderRadius.circular(GlintLook.corner + 4),
              border: Border.all(color: GlintLook.line),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [_label(titleOf(view)), const SizedBox(height: 12), ...body],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lists' view: each list's name and how much is left, and the things on it. With [onDone] each thing can be
/// selected and OK marks it done (it stays where it is, ticked, so nothing moves under the selection); without it
/// (no Home Assistant to tell) the lists are only read. The lists are taken as the view opens and hold still.
class GlanceTodoView extends StatefulWidget {
  final List<GlanceList> lists;
  final Future<bool> Function(String entity, GlanceTodoItem item)? onDone;
  const GlanceTodoView({super.key, required this.lists, this.onDone});

  @override
  State<GlanceTodoView> createState() => _GlanceTodoViewState();
}

class _GlanceTodoViewState extends State<GlanceTodoView> {
  late List<GlanceList> _lists = widget.lists;
  final Set<GlanceTodoItem> _done = {};
  final Set<GlanceTodoItem> _busy = {};
  final FocusNode _first = FocusNode(debugLabel: "glance_todo_first");
  bool _failed = false;

  bool get _marks => widget.onDone != null;

  @override
  void initState() {
    super.initState();
    _focusFirst();
  }

  void _focusFirst() {
    if (!_marks || !_lists.any((l) => l.entity != null && l.next.isNotEmpty)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _first.context != null && !_first.hasFocus) _first.requestFocus();
    });
  }

  /// A list whose things hadn't come yet when the view opened takes them when they come; the others hold still.
  @override
  void didUpdateWidget(GlanceTodoView old) {
    super.didUpdateWidget(old);
    final fresh = {for (final l in widget.lists) if (l.entity != null) l.entity!: l};
    final next = [
      for (final l in _lists)
        if (l.next.isEmpty && fresh[l.entity]?.next.isNotEmpty == true) fresh[l.entity]! else l,
    ];
    if (listEquals(next, _lists)) return;
    _lists = next;
    _focusFirst();
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Future<void> _mark(String entity, GlanceTodoItem item) async {
    final onDone = widget.onDone;
    if (onDone == null || _done.contains(item) || !_busy.add(item)) return;
    setState(() => _failed = false);
    final ok = await onDone(entity, item);
    if (!mounted) return;
    setState(() {
      _busy.remove(item);
      if (ok) {
        _done.add(item);
      } else {
        _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    var firstGiven = false;
    final children = <Widget>[];
    for (final l in _lists) {
      final left = l.open - l.next.where(_done.contains).length;
      children.add(Row(
        children: [
          Expanded(child: Text(l.name, style: GlintLook.primary.copyWith(fontSize: 17))),
          Text(l10n.glanceTodoLeft(math.max(0, left)), style: GlintLook.secondaryText),
        ],
      ));
      for (final item in l.next) {
        final entity = l.entity;
        final canMark = _marks && entity != null;
        final focusNode = canMark && !firstGiven ? _first : null;
        if (canMark) firstGiven = true;
        children.add(_GlanceTodoRow(
          key: ValueKey("${l.entity}:${item.uid ?? item.summary}"),
          item: item,
          done: _done.contains(item),
          focusNode: focusNode,
          onPressed: canMark ? () => _mark(entity, item) : null,
        ));
      }
      children.add(const SizedBox(height: 14));
    }
    children.add(Text(
      _failed ? l10n.glanceTodoFailed : (_marks ? l10n.glanceTodoHint : ""),
      key: const Key("glance_todo_note"),
      style: GlintLook.secondaryText,
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// One thing on a list in the lists' view: selectable when it can be marked done, ticked once it is.
class _GlanceTodoRow extends StatefulWidget {
  final GlanceTodoItem item;
  final bool done;
  final FocusNode? focusNode;
  final VoidCallback? onPressed;
  const _GlanceTodoRow({super.key, required this.item, required this.done, this.focusNode, this.onPressed});

  @override
  State<_GlanceTodoRow> createState() => _GlanceTodoRowState();
}

class _GlanceTodoRowState extends State<_GlanceTodoRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final glow = GlintTileStyle.of(context)?.glow ?? Colors.white;
    final row = Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlintLook.corner),
        color: _focused ? GlintTileStyle.selectedFill : Colors.transparent,
        border: Border.all(color: _focused ? glow.withValues(alpha: 0.9) : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          Icon(widget.done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: widget.done ? GlintLook.accentText() : GlintLook.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.item.summary,
              style: widget.done
                  ? GlintLook.secondaryText.copyWith(decoration: TextDecoration.lineThrough)
                  : GlintLook.primary.copyWith(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (widget.onPressed == null) return row;
    return GlintPress(
      focusNode: widget.focusNode,
      onPressed: widget.onPressed,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: row,
    );
  }
}

/// A way out, small, in the row along the bottom: an icon and a name (and, for notifications, how many).
class GlanceAction extends StatefulWidget {
  final IconData icon;
  final String name;
  final int? count;
  final VoidCallback onPressed;
  const GlanceAction({super.key, required this.icon, required this.name, required this.onPressed, this.count});

  @override
  State<GlanceAction> createState() => _GlanceActionState();
}

class _GlanceActionState extends State<GlanceAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final glow = GlintTileStyle.of(context)?.glow ?? Colors.white;
    final radius = BorderRadius.circular(GlintLook.corner);
    final ink = glow.computeLuminance() > 0.45 ? const Color(0xFF1A1208) : Colors.white;
    return GlintPress(
      onPressed: widget.onPressed,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: GlanceGrid.actionsHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: _focused ? GlintTileStyle.selectedFill : GlintTileStyle.fill,
            border: Border.all(
              color: _focused ? glow.withValues(alpha: 0.9) : GlintLook.line,
              width: _focused ? 2 : GlintLook.hairlineWidth,
            ),
            boxShadow: _focused ? GlintTileStyle.glowOf(glow) : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: GlintLook.content, size: 20, shadows: GlintLook.textShadow),
              const SizedBox(width: 10),
              Text(widget.name, style: GlintLook.primary.copyWith(fontSize: 15)),
              if (widget.count != null && widget.count! > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: glow, borderRadius: BorderRadius.circular(10)),
                  child: _Fading("${widget.count}", TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
