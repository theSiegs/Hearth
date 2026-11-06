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

import 'package:flutter/foundation.dart';

/// What turns the glance page's live tiles: one timer for the whole page, turning one tile at a time in turn, so
/// the tiles change apart from each other and the page stays calm.
///
/// Each tile tells it how many faces it has ([setFaces]); only tiles with two or more turn. A tile that has the
/// selection never turns ([focus]), and waits [resumeAfter] once the selection leaves it. Nothing turns while
/// [running] is off (Motion: Still, the page hidden, a view open over it).
///
/// The face index is only what a tile shows: what pressing a tile does never depends on it.
class GlanceRotation {
  /// About how often each tile changes; with many tiles turning they're never closer together than [minGap].
  final Duration period, minGap, resumeAfter;

  /// Nothing turns this soon after the page starts.
  final Duration settle;
  final DateTime Function() _clock;

  GlanceRotation({
    this.period = const Duration(seconds: 8),
    this.minGap = const Duration(milliseconds: 1500),
    this.resumeAfter = const Duration(seconds: 4),
    this.settle = const Duration(seconds: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Map<String, ValueNotifier<int>> _index = {};
  final Map<String, int> _faces = {};
  final Map<String, DateTime> _holdUntil = {};
  final List<String> _order = [];
  String? _focused;
  int _next = 0;
  Timer? _timer;
  Duration? _timerEvery;
  bool _running = false;
  DateTime? _startedAt;

  /// The face [id] shows (a count up; the tile takes it modulo its faces).
  ValueListenable<int> indexOf(String id) => _index.putIfAbsent(id, () => ValueNotifier(0));

  /// The tile that has the selection, if any.
  String? get focused => _focused;

  /// How many faces [id] has now (fewer than two: it doesn't turn). Tiles turn in the order they're first told.
  void setFaces(String id, int faces) {
    if (_faces[id] == faces) return;
    _faces[id] = faces;
    if (!_order.contains(id)) _order.add(id);
    _replan();
  }

  /// A tile left the page.
  void remove(String id) {
    _faces.remove(id);
    _order.remove(id);
    _holdUntil.remove(id);
    if (_focused == id) _focused = null;
    _replan();
  }

  /// The selection came to [id], or left it.
  void focus(String id, bool focused) {
    if (focused) {
      _focused = id;
      _holdUntil.remove(id);
    } else if (_focused == id) {
      _focused = null;
      _holdUntil[id] = _clock().add(resumeAfter);
    }
  }

  /// The tiles that turn, in turn.
  List<String> get turning => [for (final id in _order) if ((_faces[id] ?? 0) >= 2) id];

  /// How long between one change and the next: [period] shared among the turning tiles, at least [minGap].
  Duration get every {
    final n = turning.length;
    if (n == 0) return period;
    final share = Duration(microseconds: period.inMicroseconds ~/ n);
    return share < minGap ? minGap : share;
  }

  bool get running => _running;

  /// Turns tiles while on.
  set running(bool on) {
    if (on == _running) return;
    _running = on;
    if (on) _startedAt ??= _clock();
    _replan();
  }

  void _replan() {
    final want = _running && turning.isNotEmpty ? every : null;
    if (want == _timerEvery && (_timer != null) == (want != null)) return;
    _timer?.cancel();
    _timer = null;
    _timerEvery = want;
    if (want != null) _timer = Timer.periodic(want, (_) => tick());
  }

  /// One step: the next tile in turn that may change does (not the selected one, nor one the selection just left).
  /// Returns which, or null.
  String? tick() {
    if (!_running) return null;
    final now = _clock();
    if (_startedAt != null && now.difference(_startedAt!) < settle) return null;
    final ids = turning;
    if (ids.isEmpty) return null;
    for (var tries = 0; tries < ids.length; tries++) {
      final id = ids[_next % ids.length];
      _next = (_next + 1) % ids.length;
      if (id == _focused) continue;
      final hold = _holdUntil[id];
      if (hold != null && now.isBefore(hold)) continue;
      _holdUntil.remove(id);
      final index = _index.putIfAbsent(id, () => ValueNotifier(0));
      index.value = index.value + 1;
      return id;
    }
    return null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    for (final n in _index.values) {
      n.dispose();
    }
    _index.clear();
  }
}
