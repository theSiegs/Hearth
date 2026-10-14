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
import 'dart:io';

import 'package:flauncher/providers/ha_dashboards.dart';
import 'package:flauncher/quiet_failure.dart';

/// One signed-in connection to Home Assistant's WebSocket API that stays open: commands with their replies, and
/// subscriptions whose events keep coming. [done] completes when it closes (Home Assistant went away, or [close]).
class HaSocket {
  static const Duration timeout = Duration(seconds: 10);

  final WebSocket _socket;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = {};
  final Map<int, void Function(Object? event)> _subscriptions = {};
  final Completer<void> _done = Completer();

  HaSocket._(this._socket);

  /// Connects to [baseUrl] ("http://192.0.2.10:8123") and signs in with [token]; throws [HaSocketException] when it
  /// can't.
  static Future<HaSocket> connect(String baseUrl, String token, {Future<WebSocket> Function(Uri uri)? connect}) async {
    final uri = HaDashboards.webSocketUri(baseUrl);
    final WebSocket socket;
    try {
      socket = await (connect ?? (u) => WebSocket.connect(u.toString()))(uri).timeout(timeout);
    } catch (e) {
      throw HaSocketException("can't connect: $e");
    }
    final greeting = StreamController<Map<String, dynamic>>();
    final ha = HaSocket._(socket);
    var signedIn = false;
    socket.listen(
      (message) {
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(message as String) as Map<String, dynamic>;
        } catch (err) {
            noteFailure('ha_socket', err);
          return;
        }
        if (!signedIn) {
          greeting.add(msg);
        } else {
          ha._onMessage(msg);
        }
      },
      onDone: () {
        if (!greeting.isClosed) greeting.close();
        ha._closed();
      },
      onError: (_) {},
      cancelOnError: false,
    );
    final replies = StreamIterator(greeting.stream);
    try {
      Future<Map<String, dynamic>> next() async {
        if (!await replies.moveNext().timeout(timeout)) throw const HaSocketException("closed");
        return replies.current;
      }

      if ((await next())["type"] != "auth_required") throw const HaSocketException("unexpected greeting");
      socket.add(jsonEncode({"type": "auth", "access_token": token}));
      final auth = await next();
      if (auth["type"] != "auth_ok") throw const HaSocketException("not signed in");
      signedIn = true;
      unawaited(greeting.close());
      return ha;
    } catch (e) {
      unawaited(socket.close());
      if (e is HaSocketException) rethrow;
      throw HaSocketException("$e");
    }
  }

  /// Completes when the connection has closed.
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// Sends [command] and returns its result; throws [HaSocketException] when it fails or no reply comes.
  Future<Object?> command(Map<String, Object?> command) {
    if (isClosed) return Future.error(const HaSocketException("closed"));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _socket.add(jsonEncode({...command, "id": id}));
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw HaSocketException("${command["type"]}: no reply");
    });
  }

  /// Sends a subscribing [command] ("subscribe_entities", "render_template", ...); [onEvent] then has each event.
  /// Returns a function that ends the subscription.
  Future<Future<void> Function()> subscribe(Map<String, Object?> command, void Function(Object? event) onEvent) async {
    if (isClosed) throw const HaSocketException("closed");
    final id = _nextId;
    // Events can come right after the reply, so the subscription is in place before it's sent
    _subscriptions[id] = onEvent;
    try {
      await this.command(command);
    } catch (err) {
        noteFailure('ha_socket', err);
      _subscriptions.remove(id);
      rethrow;
    }
    return () async {
      if (_subscriptions.remove(id) == null || isClosed) return;
      try {
        await this.command({"type": "unsubscribe_events", "subscription": id});
      } catch (err) { noteFailure('ha_socket', err); }
    };
  }

  /// A service call ("light", "toggle"), with [target] ({"entity_id": ...}) and [data].
  Future<Object?> callService(String domain, String service,
          {Map<String, Object?>? target, Map<String, Object?>? data, bool returnResponse = false}) =>
      command(serviceCall(domain, service, target: target, data: data, returnResponse: returnResponse));

  /// The call_service command [callService] sends.
  static Map<String, Object?> serviceCall(String domain, String service,
          {Map<String, Object?>? target, Map<String, Object?>? data, bool returnResponse = false}) =>
      {
        "type": "call_service",
        "domain": domain,
        "service": service,
        if (data != null && data.isNotEmpty) "service_data": data,
        if (target != null && target.isNotEmpty) "target": target,
        if (returnResponse) "return_response": true,
      };

  void _onMessage(Map<String, dynamic> msg) {
    final id = msg["id"];
    if (id is! int) return;
    switch (msg["type"]) {
      case "result":
        final completer = _pending.remove(id);
        if (completer == null) return;
        if (msg["success"] == true) {
          completer.complete(msg["result"]);
        } else {
          final error = msg["error"];
          completer.completeError(HaSocketException(error is Map ? "${error["code"]}: ${error["message"]}" : "failed"));
        }
      case "event":
        _subscriptions[id]?.call(msg["event"]);
    }
  }

  void _closed() {
    for (final c in _pending.values) {
      c.completeError(const HaSocketException("closed"));
    }
    _pending.clear();
    _subscriptions.clear();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (err) { noteFailure('ha_socket', err); }
    _closed();
  }
}

class HaSocketException implements Exception {
  final String message;

  const HaSocketException(this.message);

  @override
  String toString() => "HaSocketException: $message";
}
