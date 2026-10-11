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

import 'package:flauncher/actions.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/ha_panel/ha_format.dart';
import 'package:flauncher/widgets/ha_panel/ha_markdown.dart';
import 'package:flauncher/widgets/ha_panel/ha_icons.dart';
import 'package:flauncher/widgets/ha_panel/ha_tile.dart';
import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Hearth's own Home Assistant panel, along the right edge over the home (as Settings is along the left): the
/// dashboard's cards drawn as TV controls. Home Assistant's dashboard config says what's on it; the panel draws the
/// kinds of cards it knows and leaves out the rest.
///
/// One list for the D-pad: Up and Down go from row to row (two half-width tiles share a row), Left and Right only
/// within a row (a slider uses them itself), and Left with nothing further left, or Back, closes the panel.
class HaPanel extends StatefulWidget {
  static const double width = 350;

  final HaPanelService service;
  final DateTime Function() now;

  /// Opens Home Assistant's own dashboard (the web page) in the panel's place; null when there's none to open.
  final VoidCallback? onOpenFullDashboard;

  const HaPanel({super.key, required this.service, this.now = DateTime.now, this.onOpenFullDashboard});

  /// Slides the panel in over [context]'s home.
  static Future<void> open(BuildContext context, HaPanelService service, {VoidCallback? onOpenFullDashboard}) =>
      showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => HaPanel(service: service, onOpenFullDashboard: onOpenFullDashboard),
      );

  @override
  State<HaPanel> createState() => _HaPanelState();
}

class _HaPanelState extends State<HaPanel> {
  final FocusNode _root = FocusNode(debugLabel: "HaPanel");
  final ScrollController _scroll = ScrollController();

  /// The stop that last had the focus, and the stops as they were then, in order: when it goes (a card hidden by its
  /// visibility), the focus moves to the next one that's still there (or the one before, if it was the last).
  FocusNode? _lastFocused;
  List<FocusNode> _lastStops = const [];

  @override
  void initState() {
    super.initState();
    widget.service.attach();
    widget.service.addListener(_onChanged);
    FocusManager.instance.addListener(_onFocusMoved);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusMoved);
    widget.service.removeListener(_onChanged);
    widget.service.detach();
    _root.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    // After the rebuild: the focused stop may have gone (or the first stops come)
    WidgetsBinding.instance.addPostFrameCallback((_) => _landFocus());
  }

  void _onFocusMoved() {
    final focused = FocusManager.instance.primaryFocus;
    if (!mounted) return;
    if (focused == null || focused == _root || !focused.ancestors.contains(_root)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _landFocus());
      return;
    }
    final previous = _lastFocused, before = _lastStops;
    _lastFocused = focused;
    _lastStops = _stops();
    if (previous != null && previous != focused) {
      // The stop that had the focus went and Flutter handed the focus to one it had before (the top, often): the
      // next one down takes it instead
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || FocusManager.instance.primaryFocus != focused) return;
        final stops = _stops();
        if (stops.contains(previous)) return;
        final next = HaPanelNavigation.successor(previous, before, stops);
        if (next != null && next != focused) {
          _lastFocused = previous;
          _lastStops = before;
          next.requestFocus();
        }
      });
    }
    final context = focused.context;
    if (context != null && context.mounted) {
      Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 150));
    }
  }

  /// With no stop in the panel focused (none had the focus yet, or the one that had it went), a stop takes it: the one
  /// after the stop that went, else the one before it, else the first. Not while something is open over the panel,
  /// or it's closing.
  void _landFocus() {
    if (!mounted) return;
    final stops = _stops();
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && stops.contains(primary)) {
      // Stops came or went elsewhere: the order to go by is the new one
      _lastStops = stops;
      return;
    }
    final route = ModalRoute.of(context);
    if (stops.isEmpty || (route != null && !route.isCurrent)) return;
    final target = HaPanelNavigation.successor(_lastFocused, _lastStops, stops) ?? stops.first;
    target.requestFocus();
  }

  List<FocusNode> _stops() => _root.traversalDescendants
      .where((n) => n.canRequestFocus && !n.skipTraversal && n.context != null && n.context!.mounted)
      .toList();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final arrows = [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown
    ];
    // Back closes the panel, whatever has the focus in it
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.browserBack) {
      // On its release, as the system closes things: the press it ends started here
      if (event is KeyUpEvent) Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (!arrows.contains(key)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final focused = FocusManager.instance.primaryFocus;
    final from = focused == null || focused == _root ? null : focused.rect;
    if (from == null) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        Navigator.of(context).pop();
      } else {
        _landFocus();
      }
      return KeyEventResult.handled;
    }
    final stops = _stops()..remove(focused);
    FocusNode? target;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      target = HaPanelNavigation.sideways(from, {for (final s in stops) s: s.rect},
          left: key == LogicalKeyboardKey.arrowLeft);
      if (target == null && key == LogicalKeyboardKey.arrowLeft) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    } else {
      final up = key == LogicalKeyboardKey.arrowUp;
      target = HaPanelNavigation.vertical(from, {for (final s in stops) s: s.rect}, up: up);
      if (target == null && _scroll.hasClients) {
        // At the top or the bottom: show what's beyond the last stop (a heading, the end of a card)
        _scroll.animateTo(up ? 0 : _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    }
    if (target != null) {
      target.requestFocus();
      _click();
    }
    return KeyEventResult.handled;
  }

  void _click() {
    try {
      final settings = context.read<SettingsService?>();
      if (settings?.appKeyClickEnabled ?? false) context.read<FLauncherChannel>().playClickSound();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(28);
    void close() => Navigator.of(context).maybePop();
    return Actions(
      actions: {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => close()),
        DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => close()),
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: const Color(0xFF111111),
                elevation: 24,
                shadowColor: Colors.black,
                borderRadius: const BorderRadius.horizontal(left: radius),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: HaPanel.width,
                  height: double.infinity,
                  child: Focus(
                    focusNode: _root,
                    autofocus: true,
                    onKeyEvent: _onKey,
                    child: ListenableBuilder(
                      listenable: widget.service,
                      builder: (context, _) => _content(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = widget.service;
    final text = Theme.of(context).textTheme;
    switch (service.status) {
      case HaPanelStatus.notSetUp:
        return _message(context, l.haNativeNotSetUp, l.haNativeNotSetUpDetail(HaPanelPage.breadcrumb(l)));
      case HaPanelStatus.idle:
      case HaPanelStatus.connecting:
        if (!service.layoutLoaded) return _message(context, l.haNativeLoading, null);
      case HaPanelStatus.unreachable:
        if (!service.layoutLoaded) return _message(context, l.haNativeUnreachable, null, icon: Icons.cloud_off);
      case HaPanelStatus.ready:
        break;
    }
    final format = HaFormat(l, service.translate, widget.now(), temperatureUnit: service.temperatureUnit);
    final rows = HaPanelRows.build(service.layout, service.conditionContext);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (service.layout.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text(service.layout.title!,
                  style: text.titleLarge!.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          if (service.status == HaPanelStatus.unreachable) _quietRow(context, Icons.cloud_off, l.haNativeUnreachable),
          if (rows.isEmpty) _quietRow(context, Icons.dashboard_outlined, l.haNativeEmpty),
          for (final row in rows) _row(context, row, format),
          if (widget.onOpenFullDashboard != null) _fullDashboardRow(context, l),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, HaPanelRow row, HaFormat format) {
    if (row.cards.length == 2) {
      return Padding(
        key: ValueKey(row.key),
        padding: const EdgeInsets.only(bottom: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _card(context, row.cards[0], format)),
              const SizedBox(width: 8),
              Expanded(child: _card(context, row.cards[1], format)),
            ],
          ),
        ),
      );
    }
    final card = row.cards.single;
    final child = _card(context, card, format);
    return Padding(
      key: ValueKey(row.key),
      padding: EdgeInsets.only(bottom: card is HaHeadingCard ? 0 : 8),
      child: card.half ? Row(children: [Expanded(child: child), const SizedBox(width: 8), const Spacer()]) : child,
    );
  }

  Widget _card(BuildContext context, HaCard card, HaFormat format) => switch (card) {
        HaHeadingCard() => _heading(context, card),
        HaTileCard() => HaTile(card: card, service: widget.service, format: format),
        HaMarkdownCard() => _markdown(context, card),
        HaMapCard() => _map(context, card, format),
        HaUnsupportedCard() => const SizedBox.shrink(),
      };

  /// A markdown card: one stop, so the list scrolls through it.
  Widget _markdown(BuildContext context, HaMarkdownCard card) {
    final text = card.templated ? widget.service.rendered(card.content) : card.content;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return FocusableTap(
      onPressed: () {},
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: haFocusDecoration(context, focused),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (card.title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(card.title!,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w700)),
              ),
            HaMarkdownView(text),
          ],
        ),
      ),
    );
  }

  /// A map card as a list: who (or what) is where.
  Widget _map(BuildContext context, HaMapCard card, HaFormat format) {
    final text = Theme.of(context).textTheme;
    return FocusableTap(
      onPressed: () {},
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: haFocusDecoration(context, focused),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (card.title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(card.title!, style: text.titleSmall!.copyWith(fontWeight: FontWeight.w700)),
              ),
            for (final id in card.mapEntities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 18, color: HaTileColors.active(widget.service.entity(id)) ?? Colors.white60),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.service.entity(id)?.name ?? id,
                          style: text.bodyMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(format.tileState(widget.service.entity(id), const []),
                          style: text.bodyMedium!.copyWith(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The last row: Home Assistant's own dashboard, for what the panel doesn't draw.
  Widget _fullDashboardRow(BuildContext context, AppLocalizations l) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FocusableTap(
          onPressed: () {
            final open = widget.onOpenFullDashboard!;
            Navigator.of(context).maybePop();
            open();
          },
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: haFocusDecoration(context, focused, filled: false),
            child: Row(
              children: [
                const Icon(Icons.open_in_new, size: 18, color: Colors.white60),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l.haNativeOpenFullDashboard,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _heading(BuildContext context, HaHeadingCard card) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          if (card.icon != null) ...[
            Icon(HaIcons.of(card.icon), size: 18, color: Colors.white60),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(card.heading,
                style: text.titleSmall!.copyWith(color: Colors.white70, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _quietRow(BuildContext context, IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white60))),
          ],
        ),
      );

  Widget _message(BuildContext context, String title, String? detail, {IconData? icon}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) Icon(icon, color: Colors.white54),
          if (icon != null) const SizedBox(height: 8),
          Text(title, style: text.titleMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail, style: text.bodyMedium!.copyWith(color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

/// A row of the panel: a heading, a card, or two half-width cards side by side.
class HaPanelRow {
  /// Stays the same while cards come and go around it, so the focus stays on its card.
  final String key;
  final List<HaCard> cards;

  const HaPanelRow(this.key, this.cards);
}

class HaPanelRows {
  /// The visible cards of [layout] in rows: sections and cards whose visibility doesn't hold now are left out, and
  /// so are the cards the panel can't draw; half-width cards pair up.
  static List<HaPanelRow> build(HaPanelLayout layout, HaConditionContext context) {
    final rows = <HaPanelRow>[];
    for (final (si, section) in layout.sections.indexed) {
      if (!HaCondition.all(section.visibility, context)) continue;
      HaPanelRow? open;
      for (final (ci, card) in section.cards.indexed) {
        if (card is HaUnsupportedCard || !HaCondition.all(card.visibility, context)) continue;
        if (card.half && card is! HaHeadingCard) {
          if (open != null) {
            rows[rows.length - 1] = HaPanelRow(open.key, [open.cards.single, card]);
            open = null;
          } else {
            open = HaPanelRow("$si/$ci", [card]);
            rows.add(open);
          }
        } else {
          open = null;
          rows.add(HaPanelRow("$si/$ci", [card]));
        }
      }
    }
    return rows;
  }
}

/// Where the D-pad goes from a focused rect, among the panel's stops and their rects.
class HaPanelNavigation {
  /// [gone] was one of [before] (in order) and isn't in [now]: the first stop after it that's still there, else the
  /// last one before it; null when [gone] isn't known.
  static T? successor<T>(T? gone, List<T> before, List<T> now) {
    final i = gone == null ? -1 : before.indexOf(gone);
    if (i < 0) return null;
    for (var j = i + 1; j < before.length; j++) {
      if (now.contains(before[j])) return before[j];
    }
    for (var j = i - 1; j >= 0; j--) {
      if (now.contains(before[j])) return before[j];
    }
    return null;
  }

  /// Left or right within the same row (stops that overlap it top to bottom); null when there's none.
  static T? sideways<T>(Rect from, Map<T, Rect> stops, {required bool left}) {
    T? best;
    var bestDistance = double.infinity;
    stops.forEach((stop, r) {
      final overlap = (r.bottom < from.bottom ? r.bottom : from.bottom) - (r.top > from.top ? r.top : from.top);
      if (overlap <= 4) return;
      final distance = left ? from.left - r.right : r.left - from.right;
      if (distance < -1 || distance >= bestDistance) return;
      best = stop;
      bestDistance = distance;
    });
    return best;
  }

  /// The nearest row above or below, and in it the stop nearest across; null when there's none.
  static T? vertical<T>(Rect from, Map<T, Rect> stops, {required bool up}) {
    final candidates = <T, Rect>{};
    stops.forEach((stop, r) {
      if (up ? r.bottom <= from.top + 1 : r.top >= from.bottom - 1) candidates[stop] = r;
    });
    if (candidates.isEmpty) return null;
    // The nearest row: the stop whose edge is closest, and those level with it
    final nearest = candidates.values.reduce((a, b) => up ? (a.bottom >= b.bottom ? a : b) : (a.top <= b.top ? a : b));
    T? best;
    var bestDistance = double.infinity;
    candidates.forEach((stop, r) {
      final inRow = r.top < nearest.bottom - 1 && r.bottom > nearest.top + 1;
      if (!inRow) return;
      final distance = (r.center.dx - from.center.dx).abs();
      if (distance < bestDistance - 0.5) {
        best = stop;
        bestDistance = distance;
      }
    });
    return best;
  }
}
