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

import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flutter/material.dart';

/// Decides when the Glint home's live tiles turn to their next face: one tile at a time, [GlintLook.flipSpacing]
/// apart, each no sooner than its own pace, never the selected one (what select opens doesn't change under it) and
/// never while the home rests. Glint's Calm motion, at ten feet.
class GlintTicker {
  final Duration spacing;
  final Map<Object, _Turning> _tiles = {};
  Timer? _timer;
  bool _paused = false;
  final DateTime Function() _now;

  GlintTicker({this.spacing = GlintLook.flipSpacing, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// A tile with [faces] faces that turns no more often than every [pace]; [index] is the face it shows.
  ValueNotifier<int> join(Object id, {required int faces, required Duration pace}) {
    final tile = _tiles.putIfAbsent(id, () => _Turning(ValueNotifier(0), _now()));
    tile
      ..faces = faces
      ..pace = pace;
    if (tile.index.value >= faces) tile.index.value = 0;
    _timer ??= Timer.periodic(spacing, (_) => step());
    return tile.index;
  }

  void leave(Object id) {
    _tiles.remove(id)?.index.dispose();
    if (_tiles.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Held still while [id] is selected.
  void hold(Object id, bool held) => _tiles[id]?.held = held;

  set paused(bool value) => _paused = value;

  /// Turns the tile that has waited longest past its pace, if any.
  void step() {
    if (_paused) return;
    final now = _now();
    _Turning? next;
    for (final tile in _tiles.values) {
      if (tile.faces < 2 || tile.held) continue;
      if (now.difference(tile.turnedAt) < tile.pace) continue;
      if (next == null || tile.turnedAt.isBefore(next.turnedAt)) next = tile;
    }
    if (next == null) return;
    next.turnedAt = now;
    next.index.value = (next.index.value + 1) % next.faces;
  }

  void dispose() {
    _timer?.cancel();
    for (final tile in _tiles.values) {
      tile.index.dispose();
    }
    _tiles.clear();
  }
}

class _Turning {
  final ValueNotifier<int> index;
  int faces = 1;
  Duration pace = const Duration(seconds: 20);
  bool held = false;

  /// When it last turned, or joined: a tile shows its first face a full pace before it turns.
  DateTime turnedAt;
  _Turning(this.index, this.turnedAt);
}

/// Where the home's [GlintTicker] is found.
class GlintTickerScope extends InheritedWidget {
  final GlintTicker ticker;
  const GlintTickerScope({super.key, required this.ticker, required super.child});

  static GlintTicker? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlintTickerScope>()?.ticker;

  @override
  bool updateShouldNotify(GlintTickerScope old) => old.ticker != ticker;
}

/// Flips a face over its top edge to [index]'s: the old face turns away, the new one turns in, [GlintLook.flip] in all.
class GlintFlip extends StatefulWidget {
  final int index;
  final Widget Function(BuildContext context, int index) builder;

  const GlintFlip({super.key, required this.index, required this.builder});

  @override
  State<GlintFlip> createState() => _GlintFlipState();
}

class _GlintFlipState extends State<GlintFlip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: GlintLook.flip);
  late int _shown = widget.index;

  @override
  void didUpdateWidget(GlintFlip old) {
    super.didUpdateWidget(old);
    if (widget.index != _shown && !_controller.isAnimating) _turn();
  }

  Future<void> _turn() async {
    final target = widget.index;
    _controller.value = 0;
    await _controller.animateTo(0.5, curve: Curves.easeIn);
    if (!mounted) return;
    setState(() => _shown = target);
    await _controller.animateTo(1, curve: Curves.easeOut);
    if (!mounted) return;
    _controller.value = 0;
    // Another turn asked for while this one ran
    if (widget.index != _shown) _turn();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = _controller.value;
      // 0 → 0.5: the old face turns away over the top; 0.5 → 1: the new one turns in from below
      final angle = t <= 0.5 ? t * math.pi : (t - 1) * math.pi;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX(angle),
        child: child,
      );
    },
    child: KeyedSubtree(key: ValueKey(_shown), child: widget.builder(context, _shown)),
  );
}
