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
import 'dart:convert';

import 'package:flauncher/providers/ha_socket.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/glint/glance_weather.dart';
import 'package:flutter/foundation.dart';

/// A person in the family and where they are, as Home Assistant's person entity says ("home", "away" or a zone);
/// [where] is empty for someone Home Assistant can't place (no tracker yet).
class GlancePerson {
  final String name;
  final String where;

  /// Home Assistant's picture of them (the person's entity_picture), when it has one.
  final String? picture;
  const GlancePerson(this.name, this.where, [this.picture]);

  @override
  bool operator ==(Object other) =>
      other is GlancePerson && other.name == name && other.where == where && other.picture == picture;

  @override
  int get hashCode => Object.hash(name, where, picture);
}

/// A to-do list with something left on it ("Chores", 3), its entity and, once fetched, the next things on it.
class GlanceList {
  final String name;
  final int open;
  final String? entity;
  final List<String> next;
  const GlanceList(this.name, this.open, {this.entity, this.next = const []});

  GlanceList withNext(List<String> next) => GlanceList(name, open, entity: entity, next: next);

  @override
  bool operator ==(Object other) =>
      other is GlanceList &&
      other.name == name &&
      other.open == open &&
      other.entity == entity &&
      listEquals(other.next, next);

  @override
  int get hashCode => Object.hash(name, open, entity, Object.hashAll(next));
}

/// A Home Assistant weather entity, as the feed's template has it.
class GlanceHaWeatherEntity {
  final String entity;
  final String state;
  final Object? temperature;
  final String? unit;
  final int features;
  const GlanceHaWeatherEntity(this.entity, this.state, this.temperature, this.unit, this.features);

  /// It sends hourly forecasts (WeatherEntityFeature.FORECAST_HOURLY); daily ones (FORECAST_DAILY).
  bool get hourly => features & 2 != 0;
  bool get daily => features & 1 != 0;

  @override
  bool operator ==(Object other) =>
      other is GlanceHaWeatherEntity &&
      other.entity == entity &&
      other.state == state &&
      "${other.temperature}" == "$temperature" &&
      other.unit == unit &&
      other.features == features;

  @override
  int get hashCode => Object.hash(entity, state, "$temperature", unit, features);

  /// The house's weather when there are several: weather.home, else one named for home, else the first; none that
  /// is unavailable or has no temperature.
  static GlanceHaWeatherEntity? pick(List<GlanceHaWeatherEntity> all) {
    final usable = [
      for (final w in all)
        if (w.state != "unavailable" && w.state != "unknown" && GlanceWeather.haCelsius(w.temperature, w.unit) != null)
          w,
    ]..sort((a, b) => a.entity.compareTo(b.entity));
    return usable.where((w) => w.entity == "weather.home").firstOrNull ??
        usable.where((w) => w.entity.contains("home")).firstOrNull ??
        usable.firstOrNull;
  }
}

/// The family, the to-do lists (and the next things on them) and the weather, from Home Assistant, for the glance
/// page: one template Home Assistant renders again whenever a person, a list or the weather changes, plus the weather
/// entity's forecasts. Made when the page opens and disposed when it closes, so nothing is followed while the page
/// isn't up. Without a Home Assistant connection it stays empty and its tiles don't show.
class GlanceHaFeed extends ChangeNotifier {
  final Future<({String url, String token})?> Function() _connection;
  final Future<HaSocket> Function(String url, String token) _connect;
  HaSocket? _socket;
  bool _disposed = false;
  List<GlancePerson> _people = const [];
  List<GlanceList> _lists = const [];
  List<GlanceList> _merged = const [];
  final Map<String, List<String>> _items = {};
  GlanceHaWeatherEntity? _weather;
  final Map<String, List<Object?>> _forecasts = {};
  final List<Future<void> Function()> _forecastSubs = [];

  GlanceHaFeed(this._connection, {Future<HaSocket> Function(String url, String token)? connect})
      : _connect = connect ?? HaSocket.connect {
    unawaited(_start());
  }

  List<GlancePerson> get people => _people;

  /// Home Assistant's address and token, once connected (for its pictures).
  ({String url, String token})? get connection => _connected;
  ({String url, String token})? _connected;

  /// The lists, with the next things on each once they've been fetched.
  List<GlanceList> get lists => _merged;

  /// Home Assistant's weather (the house's weather entity and its forecasts); null when it has none.
  GlanceWeather? weatherAt(DateTime now) {
    final w = _weather;
    if (w == null) return null;
    return GlanceWeather.fromHa(
      state: w.state,
      temperature: w.temperature,
      unit: w.unit,
      hourly: _forecasts["hourly"] ?? const [],
      daily: _forecasts["daily"] ?? const [],
      now: now,
    );
  }

  /// People ([name, state, picture]), to-do lists ([name, open items, entity]) and weather entities ([entity, state,
  /// temperature, unit, features]).
  static const template = "{%- set ns = namespace(people=[], lists=[], weather=[]) -%}"
      "{%- for p in states.person -%}{%- set ns.people = ns.people + [[p.name, p.state, p.attributes.entity_picture | default('', true)]] -%}{%- endfor -%}"
      "{%- for t in states.todo -%}{%- set ns.lists = ns.lists + [[t.name, t.state, t.entity_id]] -%}{%- endfor -%}"
      "{%- for w in states.weather -%}{%- set ns.weather = ns.weather + [[w.entity_id, w.state, w.attributes.temperature, w.attributes.temperature_unit | default('', true), w.attributes.supported_features | default(0, true)]] -%}{%- endfor -%}"
      "{{ {'people': ns.people, 'lists': ns.lists, 'weather': ns.weather} | tojson }}";

  /// How many of a list's next things it keeps.
  static const int nextItems = 3;

  Future<void> _start() async {
    try {
      final connection = await _connection();
      if (connection == null || _disposed) return;
      final socket = await _connect(connection.url, connection.token);
      if (_disposed) return unawaited(socket.close());
      _socket = socket;
      _connected = connection;
      await socket.subscribe({"type": "render_template", "template": template}, (event) {
        if (event is Map && event.containsKey("result")) _take(event["result"]);
      });
    } catch (err) {
      noteFailure('glance_feed', err);
    }
  }

  void _take(Object? result) {
    final parsed = parse(result);
    final weather = GlanceHaWeatherEntity.pick(parsed.weather);
    final listsChanged = !listEquals(parsed.lists, _lists);
    if (listEquals(parsed.people, _people) && !listsChanged && weather == _weather) return;
    if (weather?.entity != _weather?.entity) unawaited(_followForecasts(weather));
    _people = parsed.people;
    _lists = parsed.lists;
    _weather = weather;
    _merge();
    if (listsChanged) unawaited(_fetchItems());
    if (!_disposed) notifyListeners();
  }

  void _merge() => _merged = [
    for (final l in _lists)
      if (l.entity != null && _items[l.entity] != null) l.withNext(_items[l.entity]!) else l,
  ];

  /// The next things on each list (todo/item/list), whenever the lists change.
  Future<void> _fetchItems() async {
    final socket = _socket;
    if (socket == null) return;
    for (final l in _lists) {
      final entity = l.entity;
      if (entity == null) continue;
      try {
        final reply = await socket.command({"type": "todo/item/list", "entity_id": entity});
        if (_disposed) return;
        _items[entity] = nextOf(reply);
      } catch (err) {
        noteFailure('glance_feed', err);
      }
    }
    if (_disposed) return;
    _merge();
    notifyListeners();
  }

  /// The things still to do in a todo/item/list reply, in the list's order.
  @visibleForTesting
  static List<String> nextOf(Object? reply) {
    final items = reply is Map && reply["items"] is List ? reply["items"] as List : const [];
    return [
      for (final i in items)
        if (i is Map && i["status"] == "needs_action" && i["summary"] is String && (i["summary"] as String).trim().isNotEmpty)
          (i["summary"] as String).trim(),
    ].take(nextItems).toList();
  }

  /// Follows [weather]'s forecasts (the hours and the days), dropping the last entity's.
  Future<void> _followForecasts(GlanceHaWeatherEntity? weather) async {
    for (final stop in _forecastSubs) {
      unawaited(stop());
    }
    _forecastSubs.clear();
    _forecasts.clear();
    final socket = _socket;
    if (weather == null || socket == null) return;
    for (final type in [if (weather.hourly) "hourly", if (weather.daily) "daily"]) {
      try {
        final stop = await socket.subscribe(
          {"type": "weather/subscribe_forecast", "entity_id": weather.entity, "forecast_type": type},
          (event) {
            if (_disposed || event is! Map || event["forecast"] is! List) return;
            _forecasts[type] = event["forecast"] as List;
            notifyListeners();
          },
        );
        if (_disposed) return unawaited(stop());
        _forecastSubs.add(stop);
      } catch (err) {
        noteFailure('glance_feed', err);
      }
    }
  }

  /// The template's result (Home Assistant may hand it back as JSON text or already parsed): everyone by name (with
  /// no place for someone Home Assistant can't place), the lists with something left on them, most first, and the
  /// weather entities.
  @visibleForTesting
  static ({List<GlancePerson> people, List<GlanceList> lists, List<GlanceHaWeatherEntity> weather}) parse(
      Object? result) {
    Object? data = result;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = null;
      }
    }
    final people = <GlancePerson>[];
    final lists = <GlanceList>[];
    final weather = <GlanceHaWeatherEntity>[];
    if (data is Map) {
      for (final p in (data["people"] is List ? data["people"] as List : const [])) {
        if (p is List && p.length >= 2 && p[0] is String && p[1] is String) {
          final state = (p[1] as String).trim();
          final where = switch (state) {
            "" || "unknown" || "unavailable" => "",
            "not_home" => "away",
            _ => state.replaceAll("_", " "),
          };
          final picture = p.length > 2 && p[2] is String && (p[2] as String).trim().isNotEmpty ? p[2] as String : null;
          people.add(GlancePerson(p[0] as String, where, picture));
        }
      }
      for (final t in (data["lists"] is List ? data["lists"] as List : const [])) {
        if (t is List && t.length >= 2 && t[0] is String) {
          final open = int.tryParse("${t[1]}");
          final entity = t.length > 2 && t[2] is String ? t[2] as String : null;
          if (open != null && open > 0) lists.add(GlanceList(t[0] as String, open, entity: entity));
        }
      }
      for (final w in (data["weather"] is List ? data["weather"] as List : const [])) {
        if (w is List && w.length >= 3 && w[0] is String && w[1] is String) {
          final unit = w.length > 3 && w[3] is String && (w[3] as String).isNotEmpty ? w[3] as String : null;
          final features = w.length > 4 ? int.tryParse("${w[4]}") ?? 0 : 0;
          weather.add(GlanceHaWeatherEntity(w[0] as String, w[1] as String, w[2], unit, features));
        }
      }
    }
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    lists.sort((a, b) => b.open.compareTo(a.open));
    return (people: people, lists: lists, weather: weather);
  }

  @override
  void dispose() {
    _disposed = true;
    _forecastSubs.clear();
    unawaited(_socket?.close());
    super.dispose();
  }
}
