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
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glint_apps_page.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_house_feed.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flauncher/widgets/glint/glint_tile.dart';
import 'package:flauncher/widgets/glint/ha_lock_feed.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

/// The glance page (Peek: Top shelf + glance page), down from the dock: its own page over a dark backdrop that hides
/// the home (the top bar stays). Live tiles on a clean two-column grid inside the TV's safe area: a kid's time (what's
/// held, the minutes left in each group), the family and where they are, today (the date, the weather, what's on),
/// the to-do lists and what's going on around the house; then a small row of ways out (All apps, Home Assistant's
/// panel, notifications, Settings).
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

class GlancePageState extends State<GlancePage> with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode(debugLabel: "glance_page");
  late final GlintHouseFeed _house;
  late final GlanceHaFeed _family;
  late final HaLockFeed _lock;
  late final AnimationController _show;
  late final bool _moves;
  bool _leaving = false;

  /// Each person's Google TV profile photo, looked up once per page (null: none). The family tile waits until everyone
  /// on it has been looked up, so a face never swaps on its own.
  final Map<String, Uint8List?> _photos = {};
  final Set<String> _lookingUp = {};

  @override
  void initState() {
    super.initState();
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
    // The first tile takes the selection as the page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.descendants
          .where((n) => n.canRequestFocus && !n.skipTraversal && n.context != null)
          .firstOrNull
          ?.requestFocus();
    });
  }

  /// Plays the page out, then [GlancePage.onGone]. It takes no keys meanwhile.
  void leave() {
    if (_leaving) return;
    setState(() => _leaving = true);
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notifications = () {
      final n = context.watch<NotificationsService?>();
      return n != null && n.hasPermission && settings.showNotificationsWidgetInStatusBar ? n.notifications : null;
    }();
    final all = glanceTiles(
      lock: _lock.state,
      // Shown once everyone on it has been looked up
      people: _family.people.every((p) => _photos.containsKey(p.name)) ? _family.people : const [],
      photos: _photos,
      connection: _family.connection,
      lists: _family.lists,
      house: _house.items,
      weather: context.watch<WeatherService?>()?.weatherData,
      events: context.watch<CalendarService?>()?.today().take(4).toList() ?? const [],
      notifications: notifications,
      haPanel: settings.haPanelEnabled,
    );
    final tiles = [for (final t in all) if (!t.action) t];
    final actions = [for (final t in all) if (t.action) t];
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
              child: _TileIn(delay: delay(i), moves: _moves, child: Builder(builder: tile.build)),
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
                    child: Builder(builder: action.build),
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

/// One tile on the glance page; an [action] is a small one in the row of ways out.
class GlanceTile {
  final String id;
  final bool action;
  final Widget Function(BuildContext context) build;
  const GlanceTile(this.id, this.build, {this.action = false});
}

/// The glance page's tiles, in order: a kid's time first, then today, the family, the to-do lists and the house, then the ways out (All apps, Home Assistant, notifications, Settings). Only tiles with
/// something to say are there; today always is.
List<GlanceTile> glanceTiles({
  required HaLockState lock,
  List<GlancePerson> people = const [],
  Map<String, Uint8List?> photos = const {},
  ({String url, String token})? connection,
  List<GlanceList> lists = const [],
  List<GlintHouseItem> house = const [],
  WeatherData? weather,
  List<CalendarEvent> events = const [],
  List<NotificationItem>? notifications,
  bool haPanel = false,
}) {
  final now = DateTime.now();
  final tiles = <GlanceTile>[];
  if (TimeUpFace.shows(lock, nothingToOpen: false, now: now)) {
    tiles.add(GlanceTile("time", (_) => TimeUpFace(state: lock)));
  }
  if (lock.kids && lock.groups.isNotEmpty) {
    tiles.add(GlanceTile(
      "screen-time",
      (_) => GlanceTableFace(
        label: "Screen time left",
        rows: [for (final g in lock.groups) (g.name, g.minutesLeft <= 0 ? "none today" : "${g.minutesLeft} min")],
      ),
    ));
  }
  // Today is always there: ahead of what Home Assistant brings a moment later, so the page doesn't shift under the
  // selection as it arrives
  tiles.add(GlanceTile("today", (_) => GlanceTodayFace(weather: weather, events: events)));
  if (people.isNotEmpty) {
    tiles.add(GlanceTile(
      "family",
      (_) => GlanceFamilyFace(members: [
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
      ]),
    ));
  }
  if (lists.isNotEmpty) {
    tiles.add(GlanceTile(
      "lists",
      (_) => GlanceTableFace(label: "To do", rows: [for (final l in lists) (l.name, "${l.open} left")]),
    ));
  }
  if (house.isNotEmpty) tiles.add(GlanceTile("house", (_) => GlanceHouseFace(items: house)));

  tiles.add(GlanceTile(
    "all-apps",
    action: true,
    (context) => GlanceAction(icon: Icons.apps_rounded, name: "All apps", onPressed: () => GlintAppsPage.open(context)),
  ));
  if (haPanel) {
    tiles.add(GlanceTile(
      "home-assistant",
      action: true,
      (context) => GlanceAction(
        icon: Icons.home_outlined,
        name: "Home",
        onPressed: () => Actions.maybeInvoke(context, const OpenHaPanelIntent()),
      ),
    ));
  }
  if (notifications != null) {
    tiles.add(GlanceTile(
      "notifications",
      action: true,
      (context) => GlanceAction(
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
    (context) => GlanceAction(
      icon: Icons.settings_outlined,
      name: "Settings",
      onPressed: () =>
          showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const SettingsPanel()),
    ),
  ));
  return tiles;
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
      alignment: align == TextAlign.end ? Alignment.centerRight : Alignment.centerLeft,
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

/// Turns through [children] one at a time, every [pace], with a soft cross-fade and a small rise. Holds the first
/// when nothing may move (Motion: Still) or there's only one.
class GlanceCycle extends StatefulWidget {
  final List<Widget> children;
  final Duration pace;
  const GlanceCycle({super.key, required this.children, this.pace = const Duration(seconds: 6)});

  @override
  State<GlanceCycle> createState() => _GlanceCycleState();
}

class _GlanceCycleState extends State<GlanceCycle> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(GlanceCycle old) {
    super.didUpdateWidget(old);
    if (_index >= widget.children.length) _index = 0;
    if (old.children.length != widget.children.length || old.pace != widget.pace) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = null;
    final moves = GlintMotion.fromName(context.read<SettingsService>().glintMotion).pace.moves;
    if (!moves || widget.children.length < 2) return;
    _timer = Timer.periodic(widget.pace, (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.children.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final i = _index < widget.children.length ? _index : 0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(i), child: widget.children[i]),
    );
  }
}

/// Today: the date, the weather now, and what's on today, turning through the events. The time itself is the top
/// bar's.
class GlanceTodayFace extends StatelessWidget {
  final WeatherData? weather;
  final List<CalendarEvent> events;
  final DateTime Function() clock;
  const GlanceTodayFace({super.key, this.weather, this.events = const [], this.clock = DateTime.now});

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

    final now = clock();
    String date;
    try {
      date = DateFormat("EEEE, MMMM d").format(now);
    } catch (_) {
      date = DateFormat("EEE, MMM d").format(now);
    }
    final w = weather;
    final hiLo = w == null
        ? ""
        : [
            if (w.todayMaxTemp != null) "H ${w.todayMaxTemp}°",
            if (w.todayMinTemp != null) "L ${w.todayMinTemp}°",
          ].join("  ");
    final upcoming = [for (final e in events) if (e.allDay || e.end.isAfter(now)) e];
    String when(CalendarEvent e) =>
        e.allDay ? "All day" : (e.isOn(now) ? "Now, until ${time(e.end)}" : time(e.start));

    return GlintTile(
      key: const Key("glance_today"),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label("Today"),
          const SizedBox(height: 2),
          Text(date, style: GlintLook.primary.copyWith(fontSize: 19), maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          if (w != null && w.currentTemp != null)
            Row(
              children: [
                Icon(WeatherData.iconFor(w.currentConditionCode),
                    color: const Color(0xFFFFE0B8), size: 18, shadows: GlintLook.textShadow),
                const SizedBox(width: 6),
                Expanded(
                  child: _Fading(
                    [
                      "${w.currentTemp}°",
                      if (w.currentCondition?.isNotEmpty ?? false) w.currentCondition!,
                      if (hiLo.isNotEmpty) hiLo,
                    ].join("   "),
                    GlintLook.secondaryText,
                  ),
                ),
              ],
            ),
          SizedBox(
            height: 20,
            child: upcoming.isEmpty
                ? Text("Nothing else on today", style: GlintLook.secondaryText, maxLines: 1)
                : GlanceCycle(
                    pace: const Duration(seconds: 5),
                    children: [
                      for (final e in upcoming)
                        Row(
                          children: [
                            if (e.color != null)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                    color: Color(e.color!).withValues(alpha: 1), shape: BoxShape.circle),
                              ),
                            Text(when(e), style: GlintLook.secondaryText.copyWith(color: GlintLook.accentText())),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.summary,
                                  style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One person on the family tile: their name as shown, where they are, their face.
class GlanceMember {
  final String name;
  final String where;
  final Widget face;
  const GlanceMember(this.name, this.where, this.face);
}

/// The family: everyone at once, each a face with their name and where they are under it. Where someone is
/// cross-fades when it changes; more people than fit turn through in pages.
class GlanceFamilyFace extends StatelessWidget {
  final List<GlanceMember> members;
  const GlanceFamilyFace({super.key, required this.members});

  static const double faceSize = 40;

  /// At most this many side by side.
  static const int perPage = 6;

  @override
  Widget build(BuildContext context) {
    Widget person(GlanceMember m) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        m.face,
        const SizedBox(height: 6),
        Text(m.name,
            style: GlintLook.primary.copyWith(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
        _Fading(m.where, GlintLook.secondaryText),
      ],
    );
    Widget page(List<GlanceMember> some) => Row(
      key: ValueKey(some.map((m) => m.name).join("|")),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (final m in some) Expanded(child: Center(child: person(m)))],
    );
    final pages = [
      for (var i = 0; i < members.length; i += perPage) members.sublist(i, math.min(i + perPage, members.length)),
    ];
    return GlintTile(
      key: const Key("glance_family"),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Center(
        child: pages.length == 1
            ? page(pages.single)
            : GlanceCycle(pace: const Duration(seconds: 8), children: [for (final p in pages) page(p)]),
      ),
    );
  }
}

/// A few names and values, one to a line (the screen time left in each group, the to-do lists); more than fit turn
/// through in pages. Each value cross-fades when it changes.
class GlanceTableFace extends StatelessWidget {
  final String label;
  final List<(String, String)> rows;
  const GlanceTableFace({super.key, required this.label, required this.rows});

  static const int perPage = 3;

  @override
  Widget build(BuildContext context) {
    Widget page(List<(String, String)> some) => Column(
      key: ValueKey(some.map((r) => r.$1).join("|")),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (name, value) in some)
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
    final pages = [
      for (var i = 0; i < rows.length; i += perPage) rows.sublist(i, math.min(i + perPage, rows.length)),
    ];
    return GlintTile(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 2),
          if (pages.length == 1)
            page(pages.single)
          else
            GlanceCycle(pace: const Duration(seconds: 7), children: [for (final p in pages) page(p)]),
        ],
      ),
    );
  }
}

/// Around the house, one thing at a time: another TV playing something, someone in a car.
class GlanceHouseFace extends StatelessWidget {
  final List<GlintHouseItem> items;
  const GlanceHouseFace({super.key, required this.items});

  @override
  Widget build(BuildContext context) => GlintTile(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: GlanceCycle(
      pace: const Duration(seconds: 6),
      children: [
        for (final item in items)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _label(item.label),
              const SizedBox(height: 4),
              Text(item.line,
                  style: GlintLook.primary.copyWith(fontSize: 18), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (item.detail != null)
                Text(item.detail!, style: GlintLook.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
      ],
    ),
  );
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
