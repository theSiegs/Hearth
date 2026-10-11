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
import 'package:flauncher/widgets/ha_panel/ha_format.dart';
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

  const HaPanel({super.key, required this.service, this.now = DateTime.now});

  /// Slides the panel in over [context]'s home.
  static Future<void> open(BuildContext context, HaPanelService service) => showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => HaPanel(service: service),
      );

  @override
  State<HaPanel> createState() => _HaPanelState();
}

class _HaPanelState extends State<HaPanel> {
  final FocusNode _root = FocusNode(debugLabel: "HaPanel");
  final ScrollController _scroll = ScrollController();

  /// Where the focus last was, to land near it again when what had it goes (a card hidden by its visibility).
  Rect? _lastRect;

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
    // After the rebuild: a focus stop that went (or the first ones that came) leave the focus on the panel itself
    WidgetsBinding.instance.addPostFrameCallback((_) => _landFocus());
  }

  void _onFocusMoved() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || !mounted) return;
    if (focused == _root) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _landFocus());
      return;
    }
    if (!focused.ancestors.contains(_root)) return;
    _lastRect = focused.rect;
    final context = focused.context;
    if (context != null && context.mounted) {
      Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 150));
    }
  }

  /// With the panel itself focused (nothing in it had focus yet, or what had it went), the nearest stop takes it.
  void _landFocus() {
    if (!mounted || !_root.hasPrimaryFocus) return;
    final stops = _stops();
    if (stops.isEmpty) return;
    var target = stops.first;
    final last = _lastRect;
    if (last != null) {
      var best = double.infinity;
      for (final s in stops) {
        final d = (s.rect.center.dy - last.center.dy).abs() + (s.rect.center.dx - last.center.dx).abs() / 4;
        if (d < best) {
          best = d;
          target = s;
        }
      }
    }
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
      if (event is KeyDownEvent) Navigator.of(context).maybePop();
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
    final format = HaFormat(l, service.translate, widget.now());
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
        HaUnsupportedCard() => const SizedBox.shrink(),
      };

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
