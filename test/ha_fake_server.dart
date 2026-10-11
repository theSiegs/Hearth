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

// A pretend Home Assistant for the panel's tests: its WebSocket API with a dashboard config and entity states.
// Plain Dart (dart:io only), so a script can run it for the emulator too.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HaFakeServer {
  final HttpServer _server;
  final String token;

  /// lovelace/config's answer, by url_path (null for the default dashboard).
  final Map<String?, Object?> dashboards;

  /// entity_id → {"s": state, "a": attributes}.
  final Map<String, Map<String, Object?>> states;

  /// render_template's answer for a template.
  String Function(String template) renderTemplate = (t) => t;

  /// weather/subscribe_forecast's forecast for an entity.
  List<Map<String, Object?>> Function(String entityId, String type) forecast = (_, __) => const [];

  /// Every command received (after sign-in).
  final List<Map<String, dynamic>> received = [];
  final List<WebSocket> _sockets = [];

  /// The subscribe_entities subscriptions: socket and id.
  final List<(WebSocket, int, List<String>?)> _entitySubs = [];

  /// Service calls answer with an error while this is set.
  bool failServices = false;

  HaFakeServer._(this._server, this.token, this.dashboards, this.states) {
    _server.transform(WebSocketTransformer()).listen(_onSocket);
  }

  static Future<HaFakeServer> start({
    String token = "t0ken",
    Map<String?, Object?>? dashboards,
    Map<String, Map<String, Object?>>? states,
    int port = 0,
    Object? address,
  }) async {
    final server = await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, port);
    return HaFakeServer._(server, token, dashboards ?? {}, states ?? {});
  }

  String get url => "http://${_server.address.address}:${_server.port}";

  int get port => _server.port;

  /// The commands of [type] received.
  List<Map<String, dynamic>> commands(String type) => received.where((m) => m["type"] == type).toList();

  void _onSocket(WebSocket socket) {
    _sockets.add(socket);
    socket.add(jsonEncode({"type": "auth_required", "ha_version": "2026.10.0"}));
    var signedIn = false;
    socket.listen((message) {
      final msg = jsonDecode(message as String) as Map<String, dynamic>;
      if (!signedIn) {
        if (msg["type"] == "auth" && msg["access_token"] == token) {
          signedIn = true;
          socket.add(jsonEncode({"type": "auth_ok"}));
        } else {
          socket.add(jsonEncode({"type": "auth_invalid", "message": "Invalid access token"}));
          socket.close();
        }
        return;
      }
      received.add(msg);
      _answer(socket, msg);
    }, onDone: () {
      _sockets.remove(socket);
      _entitySubs.removeWhere((s) => s.$1 == socket);
    });
  }

  void _result(WebSocket socket, int id, Object? result) =>
      socket.add(jsonEncode({"id": id, "type": "result", "success": true, "result": result}));

  void _error(WebSocket socket, int id, String code) => socket.add(jsonEncode({
        "id": id,
        "type": "result",
        "success": false,
        "error": {"code": code, "message": code}
      }));

  void _event(WebSocket socket, int id, Object? event) =>
      socket.add(jsonEncode({"id": id, "type": "event", "event": event}));

  void _answer(WebSocket socket, Map<String, dynamic> msg) {
    final id = msg["id"] as int;
    switch (msg["type"]) {
      case "auth/current_user":
        _result(socket, id, {"id": "user-1", "name": "TV", "is_admin": false});
      case "get_config":
        _result(socket, id, {
          "unit_system": {"temperature": "°F"}
        });
      case "frontend/get_translations":
        _result(socket, id, {
          "resources": {
            "component.person.entity_component._.state.home": "Home",
            "component.person.entity_component._.state.not_home": "Away",
            "component.media_player.entity_component._.state.playing": "Playing",
            "component.media_player.entity_component._.state.paused": "Paused",
            "component.light.entity_component._.state.on": "On",
            "component.light.entity_component._.state.off": "Off",
            "component.climate.entity_component._.state.heat": "Heat",
            "component.climate.entity_component._.state.off": "Off",
            "component.weather.entity_component._.state.sunny": "Sunny",
          }
        });
      case "lovelace/config":
        final path = msg["url_path"] as String?;
        if (!dashboards.containsKey(path)) {
          _error(socket, id, "config_not_found");
        } else {
          _result(socket, id, dashboards[path]);
        }
      case "subscribe_events":
      case "unsubscribe_events":
        _result(socket, id, null);
      case "subscribe_entities":
        final ids = (msg["entity_ids"] as List?)?.cast<String>();
        _entitySubs.add((socket, id, ids));
        _result(socket, id, null);
        _event(socket, id, {
          "a": {
            for (final e in states.entries)
              if (ids == null || ids.contains(e.key)) e.key: {...e.value, "lc": 1760000000.0}
          }
        });
      case "call_service":
        if (failServices) {
          _error(socket, id, "home_assistant_error");
        } else {
          _result(socket, id, {
            "context": {"id": "c"}
          });
        }
      case "render_template":
        _result(socket, id, null);
        _event(socket, id, {"result": renderTemplate(msg["template"] as String), "listeners": {}});
      case "weather/subscribe_forecast":
        _result(socket, id, null);
        _event(socket, id, {
          "type": msg["forecast_type"],
          "forecast": forecast(msg["entity_id"] as String, msg["forecast_type"] as String),
        });
      default:
        _error(socket, id, "unknown_command");
    }
  }

  /// [entityId]'s state becomes [state] (attributes [attributes] added), as a subscribe_entities change.
  void change(String entityId, String state, [Map<String, Object?> attributes = const {}]) {
    final old = states[entityId];
    final added = old == null;
    states[entityId] = {
      "s": state,
      "a": {...?(old?["a"] as Map<String, Object?>?), ...attributes}
    };
    for (final (socket, id, ids) in _entitySubs) {
      if (ids != null && !ids.contains(entityId)) continue;
      _event(
          socket,
          id,
          added
              ? {
                  "a": {entityId: states[entityId]}
                }
              : {
                  "c": {
                    entityId: {
                      "+": {"s": state, if (attributes.isNotEmpty) "a": attributes, "lc": 1760000100.0}
                    }
                  }
                });
    }
  }

  /// Drops every connection, as a restarting Home Assistant does.
  Future<void> dropAll() async {
    for (final s in List.of(_sockets)) {
      await s.close();
    }
  }

  Future<void> close() async {
    await dropAll();
    await _server.close(force: true);
  }
}
