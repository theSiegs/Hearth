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
import 'package:flutter/foundation.dart';

/// A person in the family and where they are, as Home Assistant's person entity says ("home", "away" or a zone).
class GlancePerson {
  final String name;
  final String where;
  const GlancePerson(this.name, this.where);

  @override
  bool operator ==(Object other) => other is GlancePerson && other.name == name && other.where == where;

  @override
  int get hashCode => Object.hash(name, where);
}

/// A to-do list with something left on it ("Chores", 3).
class GlanceList {
  final String name;
  final int open;
  const GlanceList(this.name, this.open);

  @override
  bool operator ==(Object other) => other is GlanceList && other.name == name && other.open == open;

  @override
  int get hashCode => Object.hash(name, open);
}

/// The family and the to-do lists, from Home Assistant, for the glance page: one template Home Assistant renders
/// again whenever a person or a list changes. Made when the page opens and disposed when it closes, so nothing is
/// followed while the page isn't up. Without a Home Assistant connection it stays empty and its tiles don't show.
class GlanceHaFeed extends ChangeNotifier {
  final Future<({String url, String token})?> Function() _connection;
  final Future<HaSocket> Function(String url, String token) _connect;
  HaSocket? _socket;
  bool _disposed = false;
  List<GlancePerson> _people = const [];
  List<GlanceList> _lists = const [];

  GlanceHaFeed(this._connection, {Future<HaSocket> Function(String url, String token)? connect})
      : _connect = connect ?? HaSocket.connect {
    unawaited(_start());
  }

  List<GlancePerson> get people => _people;
  List<GlanceList> get lists => _lists;

  /// People ([name, state]) and to-do lists ([name, open items]).
  static const template = "{%- set ns = namespace(people=[], lists=[]) -%}"
      "{%- for p in states.person -%}{%- set ns.people = ns.people + [[p.name, p.state]] -%}{%- endfor -%}"
      "{%- for t in states.todo -%}{%- set ns.lists = ns.lists + [[t.name, t.state]] -%}{%- endfor -%}"
      "{{ {'people': ns.people, 'lists': ns.lists} | tojson }}";

  Future<void> _start() async {
    try {
      final connection = await _connection();
      if (connection == null || _disposed) return;
      final socket = await _connect(connection.url, connection.token);
      if (_disposed) return unawaited(socket.close());
      _socket = socket;
      await socket.subscribe({"type": "render_template", "template": template}, (event) {
        if (event is Map && event.containsKey("result")) _take(event["result"]);
      });
    } catch (err) {
      noteFailure('glance_feed', err);
    }
  }

  void _take(Object? result) {
    final parsed = parse(result);
    if (listEquals(parsed.people, _people) && listEquals(parsed.lists, _lists)) return;
    _people = parsed.people;
    _lists = parsed.lists;
    if (!_disposed) notifyListeners();
  }

  /// The template's result (Home Assistant may hand it back as JSON text or already parsed): people by name, and the
  /// lists with something left on them, most first.
  @visibleForTesting
  static ({List<GlancePerson> people, List<GlanceList> lists}) parse(Object? result) {
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
    if (data is Map) {
      for (final p in (data["people"] is List ? data["people"] as List : const [])) {
        if (p is List && p.length == 2 && p[0] is String && p[1] is String) {
          final state = (p[1] as String).trim();
          if (state.isEmpty || state == "unknown" || state == "unavailable") continue;
          people.add(GlancePerson(p[0] as String, state == "not_home" ? "away" : state.replaceAll("_", " ")));
        }
      }
      for (final t in (data["lists"] is List ? data["lists"] as List : const [])) {
        if (t is List && t.length == 2 && t[0] is String) {
          final open = int.tryParse("${t[1]}");
          if (open != null && open > 0) lists.add(GlanceList(t[0] as String, open));
        }
      }
    }
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    lists.sort((a, b) => b.open.compareTo(a.open));
    return (people: people, lists: lists);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_socket?.close());
    super.dispose();
  }
}
