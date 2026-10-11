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

import 'package:flauncher/providers/ha_calls.dart';
import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_socket.dart';
import 'package:flutter/foundation.dart';

enum HaPanelStatus {
  /// Not asked yet.
  idle,

  /// Home Assistant isn't set up on this TV (it's optional).
  notSetUp,
  connecting,
  ready,

  /// It's set up but can't be reached (or turned the token down); it's tried again a little later.
  unreachable,
}

/// The data behind Hearth's own Home Assistant panel: one WebSocket connection while the panel is open (kept a few
/// minutes after it closes, so it opens again at once), the dashboard's layout (lovelace/config), the live states of
/// the entities on it (subscribe_entities) and the service calls its controls make.
class HaPanelService extends ChangeNotifier {
  /// How long the connection stays after the panel closes.
  static const Duration keepWarmFor = Duration(minutes: 5);

  /// Waits before connecting again after a drop or a failure: longer each time, up to the last.
  static const List<Duration> retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final Future<({String url, String token})?> Function() _connection;

  /// The dashboard (and view) to draw: "tv-room/home", "lovelace".
  final Future<String> Function() _dashboard;

  /// The TV's language ("en"), for Home Assistant's names of states.
  final String Function() _language;
  final Future<HaSocket> Function(String url, String token) _connect;

  HaPanelService({
    required Future<({String url, String token})?> Function() connection,
    required Future<String> Function() dashboard,
    String Function()? language,
    Future<HaSocket> Function(String url, String token)? connect,
  })  : _connection = connection,
        _dashboard = dashboard,
        _language = language ?? (() => "en"),
        _connect = connect ?? ((url, token) => HaSocket.connect(url, token));

  HaPanelStatus _status = HaPanelStatus.idle;
  HaPanelLayout _layout = HaPanelLayout.empty;
  Map<String, HaEntity> _entities = const {};
  Map<String, String> _translations = const {};
  String? _userId;
  String? _temperatureUnit;
  bool _layoutLoaded = false;

  HaSocket? _socket;
  ({String url, String token})? _connectedTo;
  String? _loadedPath;
  Future<void> Function()? _unsubscribeEntities;
  final List<Future<void> Function()> _unsubscribeOthers = [];
  final Map<String, Future<void> Function()> _templates = {};
  Map<String, String> _rendered = const {};
  int _attached = 0;
  Timer? _idleTimer;
  Timer? _retryTimer;
  int _failures = 0;
  Future<void>? _starting;
  bool _disposed = false;

  HaPanelStatus get status => _status;

  /// The view being drawn.
  HaPanelLayout get layout => _layout;

  /// The layout has been read (it may be empty).
  bool get layoutLoaded => _layoutLoaded;

  Map<String, HaEntity> get entities => _entities;

  HaEntity? entity(String id) => _entities[id];

  /// Home Assistant's name for a state in the TV's language ("Away" for a person's not_home), when it has one.
  String? translate(String key) => _translations[key];

  /// Home Assistant's temperature unit ("°C"), once known.
  String? get temperatureUnit => _temperatureUnit;

  HaConditionContext get conditionContext => HaConditionContext(entity, userId: _userId);

  /// The panel opened: connects (or reloads the dashboard if the profile's changed) and stays connected until
  /// [detach].
  void attach() {
    _attached++;
    _idleTimer?.cancel();
    _idleTimer = null;
    unawaited(_ensureStarted());
  }

  /// The panel closed: the connection goes after [keepWarmFor] unless it opens again.
  void detach() {
    if (_attached > 0) _attached--;
    if (_attached > 0) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(keepWarmFor, _disconnect);
  }

  /// Connects (or, connected, checks the dashboard and the sign-in are still the ones wanted).
  Future<void> _ensureStarted() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    ({String url, String token})? connection;
    try {
      connection = await _connection();
    } catch (_) {}
    if (_disposed) return;
    if (connection == null || connection.url.trim().isEmpty || connection.token.isEmpty) {
      await _drop();
      _layout = HaPanelLayout.empty;
      _layoutLoaded = false;
      _entities = const {};
      _set(HaPanelStatus.notSetUp);
      return;
    }
    String path;
    try {
      path = await _dashboard();
    } catch (_) {
      path = "lovelace";
    }
    final socket = _socket;
    if (socket != null && !socket.isClosed && _connectedTo == connection) {
      if (path != _loadedPath) {
        try {
          await _loadLayout(socket, path);
        } catch (_) {
          _failed();
        }
      }
      return;
    }
    await _drop();
    if (_status != HaPanelStatus.ready) _set(HaPanelStatus.connecting);
    try {
      final s = await _connect(connection.url, connection.token);
      if (_disposed) {
        unawaited(s.close());
        return;
      }
      _socket = s;
      _connectedTo = connection;
      unawaited(s.done.then((_) => _onDropped(s)));
      await _loadSession(s);
      await _loadLayout(s, path);
      _failures = 0;
    } catch (_) {
      _failed();
    }
  }

  /// Who's signed in, the temperature unit, the names of states, and changes to the dashboard. None of it is
  /// needed: what can't be read is done without.
  Future<void> _loadSession(HaSocket s) async {
    try {
      final user = await s.command({"type": "auth/current_user"});
      if (user is Map && user["id"] is String) _userId = user["id"] as String;
    } catch (_) {}
    try {
      final config = await s.command({"type": "get_config"});
      final units = config is Map ? config["unit_system"] : null;
      if (units is Map && units["temperature"] is String) _temperatureUnit = units["temperature"] as String;
    } catch (_) {}
    try {
      final result = await s
          .command({"type": "frontend/get_translations", "language": _language(), "category": "entity_component"});
      final resources = result is Map ? result["resources"] : null;
      if (resources is Map) {
        _translations = {
          for (final e in resources.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String
        };
      }
    } catch (_) {}
    try {
      _unsubscribeOthers.add(await s.subscribe({"type": "subscribe_events", "event_type": "lovelace_updated"}, (event) {
        final data = event is Map ? event["data"] : null;
        final updated = data is Map ? data["url_path"] : null;
        final (dashboard, _) = HaLovelace.splitPath(_loadedPath ?? "");
        if (updated == dashboard || (updated == null && dashboard == "lovelace")) {
          final path = _loadedPath;
          if (path != null && _socket == s) unawaited(_loadLayout(s, path).catchError((_) {}));
        }
      }));
    } catch (_) {}
  }

  /// The entities to follow for [layout]: those on it, and home's zone when someone on it can be shown on a map.
  static Set<String> followed(HaPanelLayout layout) {
    final ids = layout.entities;
    final locates = ids.any((id) => id.startsWith("person.") || id.startsWith("device_tracker."));
    return locates ? {...ids, "zone.home"} : ids;
  }

  /// Reads the dashboard's layout and subscribes to the entities on it.
  Future<void> _loadLayout(HaSocket s, String path) async {
    final (dashboard, view) = HaLovelace.splitPath(path);
    final config = await s.command({"type": "lovelace/config", if (dashboard != "lovelace") "url_path": dashboard});
    if (_disposed || _socket != s) return;
    final layout = HaLovelace.parse(config, view);
    final oldEntities = followed(_layout);
    _layout = layout;
    _layoutLoaded = true;
    _loadedPath = path;
    if (_unsubscribeEntities == null || !setEquals(oldEntities, followed(layout))) {
      await _subscribeEntities(s, followed(layout));
    }
    await _subscribeTemplates(s, layout);
    _set(HaPanelStatus.ready);
  }

  /// Markdown cards' templates, rendered by Home Assistant and kept up to date (render_template). One that can't be
  /// rendered stays blank.
  Future<void> _subscribeTemplates(HaSocket s, HaPanelLayout layout) async {
    final templates = {
      for (final c in layout.cards)
        if (c is HaMarkdownCard && c.templated) c.content
    };
    if (setEquals(templates, _templates.keys.toSet()) && _templates.isNotEmpty) return;
    final previous = _templates.values.toList();
    _templates.clear();
    for (final p in previous) {
      unawaited(p());
    }
    _rendered = {
      for (final e in _rendered.entries)
        if (templates.contains(e.key)) e.key: e.value
    };
    for (final template in templates) {
      try {
        _templates[template] = await s.subscribe(
            {"type": "render_template", "template": template, "strict": false, "report_errors": false}, (event) {
          final result = event is Map ? event["result"] : null;
          if (result == null || _socket != s || _disposed) return;
          _rendered = {..._rendered, template: "$result"};
          notifyListeners();
        });
      } catch (_) {}
    }
  }

  /// A markdown card's [template] as Home Assistant rendered it; null until it has.
  String? rendered(String template) => _rendered[template];

  Future<void> _subscribeEntities(HaSocket s, Set<String> ids) async {
    final previous = _unsubscribeEntities;
    _unsubscribeEntities = null;
    if (previous != null) unawaited(previous());
    if (ids.isEmpty) {
      _entities = const {};
      return;
    }
    // What was known stays on show until the first event, which has every state
    var first = true;
    _unsubscribeEntities =
        await s.subscribe({"type": "subscribe_entities", "entity_ids": ids.toList()..sort()}, (event) {
      if (_socket != s || _disposed) return;
      _entities = HaEntityDiff.apply(first ? const {} : _entities, event);
      first = false;
      notifyListeners();
    });
  }

  void _onDropped(HaSocket s) {
    if (_socket != s || _disposed) return;
    _socket = null;
    _connectedTo = null;
    _unsubscribeEntities = null;
    _unsubscribeOthers.clear();
    _templates.clear();
    _failed();
  }

  /// Quietly tries again later while the panel is open (what was read stays on show meanwhile).
  void _failed() {
    if (_disposed) return;
    _set(HaPanelStatus.unreachable);
    _retryTimer?.cancel();
    if (_attached == 0) return;
    final delay = retryDelays[_failures.clamp(0, retryDelays.length - 1)];
    _failures++;
    _retryTimer = Timer(delay, () => unawaited(_ensureStarted()));
  }

  /// Runs a service ("light", "toggle"); false when it couldn't (Home Assistant unreachable, or it said no).
  Future<bool> callService(String domain, String service,
      {Map<String, Object?>? target, Map<String, Object?>? data}) async {
    final s = _socket;
    if (s == null || s.isClosed) return false;
    try {
      await s.callService(domain, service, target: target, data: data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Like [callService], with "light.toggle" as one string.
  Future<bool> perform(String action, {Map<String, Object?>? target, Map<String, Object?>? data}) {
    final dot = action.indexOf(".");
    if (dot <= 0) return Future.value(false);
    return callService(action.substring(0, dot), action.substring(dot + 1), target: target, data: data);
  }

  /// Home Assistant's address and token while connected.
  ({String url, String token})? get connection => _connectedTo;

  /// Where to get an entity's picture (its entity_picture) and how: one of Home Assistant's own ("/api/...", or an
  /// address under its own) with the token, another https one as it is; null for any other (or not connected, for
  /// Home Assistant's own).
  static ({Uri uri, Map<String, String> headers})? pictureRequest(
      String picture, ({String url, String token})? connection) {
    final p = picture.trim();
    if (p.isEmpty) return null;
    final base = connection?.url.trim().replaceAll(RegExp(r"/+$"), "");
    final auth = connection == null ? const <String, String>{} : {"Authorization": "Bearer ${connection.token}"};
    if (p.startsWith("/") && !p.startsWith("//")) {
      if (base == null || base.isEmpty) return null;
      final uri = Uri.tryParse("$base$p");
      return uri == null ? null : (uri: uri, headers: auth);
    }
    final uri = Uri.tryParse(p);
    if (uri == null || !uri.hasScheme) return null;
    if (base != null && base.isNotEmpty && p.startsWith("$base/")) return (uri: uri, headers: auth);
    if (uri.scheme == "https") return (uri: uri, headers: const <String, String>{});
    return null;
  }

  /// Makes a control's service call.
  Future<bool> run(HaCall call) => perform(call.action, target: call.target, data: call.data);

  /// A connected socket for the panel's parts that subscribe on their own (templates, forecasts).
  HaSocket? get socket => _socket != null && !_socket!.isClosed ? _socket : null;

  Future<void> _drop() async {
    final s = _socket;
    _socket = null;
    _connectedTo = null;
    _unsubscribeEntities = null;
    _unsubscribeOthers.clear();
    _templates.clear();
    if (s != null) await s.close();
  }

  void _disconnect() {
    _idleTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_drop());
    _failures = 0;
    // What was read stays for next time, until it's read again
    if (_status == HaPanelStatus.ready || _status == HaPanelStatus.connecting) _status = HaPanelStatus.idle;
    _loadedPath = null;
  }

  void _set(HaPanelStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_drop());
    super.dispose();
  }
}
