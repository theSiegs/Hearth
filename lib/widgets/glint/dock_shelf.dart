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
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/widgets/glint/ha_lock_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

/// The top shelf, in the open space above the dock (Peek: Top shelf + glance page). With the selection on a dock app,
/// that app's Continue Watching and next up as a few cards (Hearth's own Watch Next data: the profile's own programs);
/// before any selection, or on a tile that isn't an app, every app's ("Pick up where you left off"). With nothing to
/// show, one quiet line: the time, the weather, the next event. In a kids profile with Home Assistant it also says the
/// minutes left today in the app's group.
///
/// It changes only when the selection moves on the dock ([generation]) or the home is seen afresh, with a quick fade;
/// never while the selection is in it. Up from the dock goes into the cards, select resumes, Down goes back.
class DockShelf extends StatefulWidget {
  /// The dock app the selection is on; null before any selection, or on a tile that isn't an app.
  final String? package;

  /// Bumped by the home on every move of the selection on the dock: the shelf takes a new look only then.
  final int generation;

  /// Wraps the cards (a container node: it takes no selection itself).
  final FocusNode focusNode;

  /// Down from the cards: back to the dock.
  final VoidCallback onDown;

  /// At most this many cards.
  static const int maxCards = 4;

  /// The cards' corners: rounded rectangles at the thumbnails' own 16:9, never the dock's capsule (it would cut the
  /// title art, the progress bar and the words off).
  static const double cardRadius = 14;

  const DockShelf({
    super.key,
    required this.package,
    required this.generation,
    required this.focusNode,
    required this.onDown,
  });

  @override
  State<DockShelf> createState() => DockShelfState();
}

/// What the shelf shows, taken when the selection moves.
@immutable
class ShelfLook {
  final String? package;
  final List<WatchNextProgram> programs;
  final String? appName;
  final int? minutesLeft;

  /// Which look this is, for the fade between two.
  final int serial;

  const ShelfLook(this.package, this.programs, {this.appName, this.minutesLeft, required this.serial});
}

class DockShelfState extends State<DockShelf> with WidgetsBindingObserver {
  late final HaLockFeed _lock;
  WatchNextService? _watchNext;
  ShelfLook? _look;
  Timer? _minute;
  int _serial = 0;

  @visibleForTesting
  ShelfLook? get look => _look;

  @override
  void initState() {
    super.initState();
    _lock = HaLockFeed(context.read<FLauncherChannel>().getHaLockState)..addListener(_quietFill);
    WidgetsBinding.instance.addObserver(this);
    // The quiet line's clock
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && (_look?.programs.isEmpty ?? false)) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchNext = Provider.of<WatchNextService?>(context, listen: false);
    if (!identical(watchNext, _watchNext)) {
      _watchNext?.removeListener(_quietFill);
      _watchNext = watchNext?..addListener(_quietFill);
    }
  }

  @override
  void didUpdateWidget(DockShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation || oldWidget.package != widget.package) _take();
  }

  /// Back from an app, the home is seen afresh: what was just watched moves along (unless the selection is here).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _take();
  }

  /// Data arriving while the shelf shows only the quiet line (the first start, Home Assistant's first answer) fills
  /// it; cards already shown stay until the selection moves.
  void _quietFill() {
    if (!mounted || widget.focusNode.hasFocus) return;
    final look = _look;
    if (look == null || look.programs.isNotEmpty) return;
    final next = _compute();
    if (next.programs.isNotEmpty || next.minutesLeft != look.minutesLeft) setState(() => _look = next);
  }

  void _take() {
    if (!mounted || widget.focusNode.hasFocus) return;
    setState(() => _look = _compute());
  }

  ShelfLook _compute() {
    final settings = context.read<SettingsService>();
    final apps = context.read<AppsService>();
    final watchNext = _watchNext;
    final package = widget.package;
    final all = watchNext != null && settings.showContinueWatching && watchNext.hasPermission
        ? watchNext.visiblePrograms(settings, apps)
        : const <WatchNextProgram>[];
    final programs = (package == null ? all : all.where((p) => p.packageName == package))
        .take(DockShelf.maxCards)
        .toList(growable: false);
    final lock = _lock.state;
    return ShelfLook(
      package,
      programs,
      appName: package == null ? null : apps.applications.firstWhereOrNull((a) => a.packageName == package)?.name,
      minutesLeft: package != null && lock.kids ? lock.minutesLeftFor(package) : null,
      serial: ++_serial,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchNext?.removeListener(_quietFill);
    _lock
      ..removeListener(_quietFill)
      ..dispose();
    _minute?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowDown || event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyDownEvent) widget.onDown();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final look = _look ??= _compute();
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(look.serial),
          child: look.programs.isNotEmpty ? _cards(context, look) : _quietLine(context, look),
        ),
      ),
    );
  }

  static const List<Shadow> _shade = [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];

  static String _minutes(AppLocalizations l10n, int minutes) =>
      minutes <= 0 ? l10n.shelfNoTimeLeft : l10n.shelfMinutesLeft(minutes);

  /// The app's name (or "Pick up where you left off") and, for a kid, the minutes left today.
  String _heading(AppLocalizations l10n, ShelfLook look) => [
        look.package == null ? l10n.shelfPickUp : (look.appName ?? l10n.continueWatching),
        if (look.minutesLeft != null) _minutes(l10n, look.minutesLeft!),
      ].join("  ·  ");

  Widget _cards(BuildContext context, ShelfLook look) {
    final l10n = AppLocalizations.of(context)!;
    final apps = context.read<AppsService>();
    return Padding(
      key: const Key("shelf_cards"),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_heading(l10n, look),
              key: const Key("shelf_heading"),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, shadows: _shade)),
          FocusTraversalGroup(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, p) in look.programs.indexed)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: WatchNextCard(
                      key: ValueKey("shelf:${p.id}"),
                      program: p,
                      appsService: apps,
                      watchNextService: _watchNext!,
                      isFirstInRow: i == 0,
                      isLastInRow: i == look.programs.length - 1,
                      maxRadius: DockShelf.cardRadius,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quietLine(BuildContext context, ShelfLook look) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    String time(DateTime t) {
      try {
        return DateFormat(settings.timeFormat).format(t);
      } catch (_) {
        return DateFormat("h:mm").format(t);
      }
    }

    final now = DateTime.now();
    final weather = Provider.of<WeatherService?>(context, listen: false)?.weatherData;
    final next = Provider.of<CalendarService?>(context, listen: false)
        ?.today()
        .where((e) => !e.allDay && e.start.isAfter(now))
        .firstOrNull;
    final parts = [
      if (look.minutesLeft != null) [?look.appName, _minutes(l10n, look.minutesLeft!)].join(" "),
      time(now),
      if (weather?.currentTemp != null)
        ["${weather!.currentTemp}°", if (weather.currentCondition?.isNotEmpty ?? false) weather.currentCondition!]
            .join(" "),
      if (next != null) "${next.summary} ${time(next.start)}",
    ];
    return Padding(
      key: const Key("shelf_quiet"),
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(parts.join("   ·   "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 20, shadows: _shade)),
    );
  }
}
