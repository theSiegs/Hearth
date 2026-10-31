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

import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_socket.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/foundation.dart';

/// One thing going on around the house, for the Glint home's house tile: another TV playing something, or someone in
/// a car.
class GlintHouseItem {
  /// Small caps over the face: the TV's name, or "In the ID.4".
  final String label;

  /// The face's line: "Sam · Bluey", or who's in the car.
  final String line;

  /// Under it: the app, when there is one.
  final String? detail;

  const GlintHouseItem(this.label, this.line, [this.detail]);

  @override
  bool operator ==(Object other) =>
      other is GlintHouseItem && other.label == label && other.line == line && other.detail == detail;

  @override
  int get hashCode => Object.hash(label, line, detail);

  @override
  String toString() => "$label: $line${detail == null ? "" : " ($detail)"}";
}

/// What's going on around the house, from Home Assistant (only when this TV has a Home Assistant connection; without
/// one the house tile never shows): each Hearth TV that's playing something (the Hearth integration's per-TV sensors)
/// and each car someone is in (a `sensor.<car>_occupants` that names who).
class GlintHouseFeed extends ChangeNotifier {
  final Future<({String url, String token})?> Function() _connection;
  final Future<HaSocket> Function(String url, String token) _connect;
  HaSocket? _socket;
  Timer? _retry;
  Timer? _rediscover;
  bool _disposed = false;
  Map<String, HaEntity> _entities = const {};
  List<GlintHouseItem> _items = const [];

  GlintHouseFeed(this._connection, {Future<HaSocket> Function(String url, String token)? connect})
    : _connect = connect ?? HaSocket.connect {
    unawaited(_start());
  }

  List<GlintHouseItem> get items => _items;

  Future<void> _start() async {
    if (_disposed) return;
    try {
      final connection = await _connection();
      if (connection == null) return _retryIn(const Duration(minutes: 10));
      final socket = await _connect(connection.url, connection.token);
      if (_disposed) return unawaited(socket.close());
      _socket = socket;
      final ids = followed(await _candidates(socket));
      if (ids.isEmpty) {
        await socket.close();
        return _retryIn(const Duration(minutes: 30));
      }
      var first = true;
      await socket.subscribe({"type": "subscribe_entities", "entity_ids": ids.toList()..sort()}, (event) {
        _entities = HaEntityDiff.apply(first ? const {} : _entities, event);
        first = false;
        _update(itemsFrom(_entities));
      });
      // New TVs and cars are found again now and then
      _rediscover = Timer(const Duration(minutes: 30), () => unawaited(socket.close()));
      unawaited(
        socket.done.then((_) {
          _rediscover?.cancel();
          _retryIn(const Duration(seconds: 30));
        }),
      );
    } catch (err) {
      noteFailure('glint_house', err);
      _retryIn(const Duration(minutes: 2));
    }
  }

  /// The entity ids that could be a Hearth TV's or a car's, worked out by Home Assistant (a template), so the stick
  /// doesn't download and parse every entity in the house.
  static const _candidatesTemplate =
      "{{ (states.sensor | selectattr('entity_id', 'search', '_(media_title|profile|state|media_app|occupants)\$')"
      " | map(attribute='entity_id') | list) + (states.binary_sensor | selectattr('entity_id', 'search',"
      " '_connected\$') | map(attribute='entity_id') | list) }}";

  static Future<List<Object?>> _candidates(HaSocket socket) async {
    final first = Completer<Object?>();
    final unsubscribe = await socket.subscribe({"type": "render_template", "template": _candidatesTemplate}, (event) {
      if (!first.isCompleted && event is Map && event.containsKey("result")) first.complete(event["result"]);
    });
    try {
      final result = await first.future.timeout(HaSocket.timeout);
      final ids = result is List
          ? result.whereType<String>()
          : RegExp(r"[a-z_]+\.[a-z0-9_]+").allMatches("$result").map((m) => m.group(0)!);
      return [for (final id in ids) {"entity_id": id}];
    } finally {
      // The template would render again on every sensor's change
      unawaited(unsubscribe());
    }
  }

  void _retryIn(Duration wait) {
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(wait, () => unawaited(_start()));
  }

  void _update(List<GlintHouseItem> items) {
    if (listEquals(items, _items)) return;
    _items = items;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _rediscover?.cancel();
    unawaited(_socket?.close());
    super.dispose();
  }

  /// The entities to follow, from get_states: each Hearth TV's sensors (a TV is a `sensor.<tv>_media_title` with a
  /// `sensor.<tv>_profile` beside it) and the car occupant sensors.
  @visibleForTesting
  static Set<String> followed(List<Object?> states) {
    final ids = <String>{
      for (final s in states)
        if (s is Map && s["entity_id"] is String) s["entity_id"] as String,
    };
    final out = <String>{};
    for (final id in ids) {
      if (id.startsWith("sensor.") && id.endsWith("_occupants")) out.add(id);
      if (id.startsWith("sensor.") && id.endsWith("_media_title")) {
        final tv = id.substring("sensor.".length, id.length - "_media_title".length);
        if (!ids.contains("sensor.${tv}_profile")) continue;
        out.addAll(
          [
            id,
            "sensor.${tv}_profile",
            "sensor.${tv}_state",
            "sensor.${tv}_media_app",
            "binary_sensor.${tv}_connected",
          ].where(ids.contains),
        );
      }
    }
    return out;
  }

  static const _nothing = {"", "unknown", "unavailable", "none", "off", "idle", "standby"};

  /// The faces: TVs playing something first, then cars with someone in them.
  @visibleForTesting
  static List<GlintHouseItem> itemsFrom(Map<String, HaEntity> entities) {
    String? value(String id) {
      final s = entities[id]?.state.trim();
      return s == null || _nothing.contains(s.toLowerCase()) ? null : s;
    }

    final tvs = <GlintHouseItem>[];
    final cars = <GlintHouseItem>[];
    for (final e in entities.values) {
      final id = e.entityId;
      if (id.endsWith("_media_title") && id.startsWith("sensor.")) {
        final tv = id.substring("sensor.".length, id.length - "_media_title".length);
        final title = value(id);
        if (title == null) continue;
        if (entities["binary_sensor.${tv}_connected"]?.state == "off") continue;
        final state = entities["sensor.${tv}_state"]?.state.toLowerCase();
        if (state != null && _nothing.contains(state)) continue;
        final profile = value("sensor.${tv}_profile");
        tvs.add(
          GlintHouseItem(
            _tvName(entities, tv),
            profile == null ? title : "$profile · $title",
            value("sensor.${tv}_media_app"),
          ),
        );
      } else if (id.endsWith("_occupants") && id.startsWith("sensor.")) {
        final who = value(id);
        if (who == null) continue;
        cars.add(GlintHouseItem("In the ${_strip(e.name, " occupants")}", who));
      }
    }
    tvs.sort((a, b) => a.label.compareTo(b.label));
    cars.sort((a, b) => a.label.compareTo(b.label));
    return [...tvs, ...cars];
  }

  /// "Den TV", from its sensors' names ("Den TV Media title"), else its id.
  static String _tvName(Map<String, HaEntity> entities, String tv) {
    final title = entities["sensor.${tv}_media_title"];
    if (title != null && title.name != title.entityId) return _strip(title.name, " Media title");
    return tv.split("_").map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(" ");
  }

  static String _strip(String name, String suffix) =>
      name.toLowerCase().endsWith(suffix.toLowerCase()) ? name.substring(0, name.length - suffix.length).trim() : name;
}
