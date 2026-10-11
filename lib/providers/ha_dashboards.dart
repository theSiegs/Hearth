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

/// A Home Assistant dashboard, or one of its views: [path] is what goes in the panel's address.
class HaDashboardChoice {
  final String path;
  final String title;

  const HaDashboardChoice(this.path, this.title);

  @override
  bool operator ==(Object other) => other is HaDashboardChoice && other.path == path && other.title == title;

  @override
  int get hashCode => Object.hash(path, title);

  @override
  String toString() => "$title ($path)";
}

/// Home Assistant's dashboards and their views, read over its WebSocket API with the panel's token
/// (lovelace/dashboards/list and lovelace/config: Home Assistant has no REST call for them).
class HaDashboards {
  static const Duration timeout = Duration(seconds: 10);

  /// The default dashboard, which Home Assistant's list leaves out.
  static const HaDashboardChoice overview = HaDashboardChoice("lovelace", "Overview");

  /// The WebSocket address for a Home Assistant base address ("http://192.0.2.10:8123").
  static Uri webSocketUri(String baseUrl) {
    final base = Uri.parse(baseUrl.trim().replaceAll(RegExp(r"/+$"), ""));
    return base.replace(scheme: base.scheme == "https" ? "wss" : "ws", path: "${base.path}/api/websocket");
  }

  /// lovelace/dashboards/list's result: the dashboards to choose from, the default one first.
  static List<HaDashboardChoice> parseDashboards(Object? result) {
    final out = <HaDashboardChoice>[overview];
    if (result is! List) return out;
    for (final d in result) {
      if (d is! Map) continue;
      final path = d["url_path"];
      if (path is! String || path.isEmpty || path == overview.path) continue;
      final title = d["title"];
      out.add(HaDashboardChoice(path, title is String && title.isNotEmpty ? title : path));
    }
    return out;
  }

  /// lovelace/config's result for [dashboard]: its views, as paths the panel can open ("hearth-tv/home"; a view
  /// without a path of its own goes by its place, "hearth-tv/1").
  static List<HaDashboardChoice> parseViews(String dashboard, Object? result) {
    final out = <HaDashboardChoice>[];
    final views = result is Map ? result["views"] : null;
    if (views is! List) return out;
    for (var i = 0; i < views.length; i++) {
      final v = views[i];
      if (v is! Map) continue;
      final path = v["path"];
      final viewPath = path is String && path.isNotEmpty ? path : "$i";
      final title = v["title"];
      out.add(HaDashboardChoice("$dashboard/$viewPath", title is String && title.isNotEmpty ? title : viewPath));
    }
    return out;
  }

  final String baseUrl;
  final String token;
  final Future<WebSocket> Function(Uri uri) _connect;

  HaDashboards(this.baseUrl, this.token, {Future<WebSocket> Function(Uri uri)? connect})
      : _connect = connect ?? ((uri) => WebSocket.connect(uri.toString()));

  Future<List<HaDashboardChoice>> dashboards() async =>
      parseDashboards(await _command({"type": "lovelace/dashboards/list"}));

  /// The views of [dashboard]; empty when it has none to list (a generated dashboard, say).
  Future<List<HaDashboardChoice>> views(String dashboard) async {
    try {
      final result = await _command({
        "type": "lovelace/config",
        if (dashboard != overview.path) "url_path": dashboard,
      });
      return parseViews(dashboard, result);
    } on HaDashboardsException {
      return const [];
    }
  }

  /// Signs in, sends one command and returns its result.
  Future<Object?> _command(Map<String, Object?> command) async {
    final socket = await _connect(webSocketUri(baseUrl)).timeout(timeout);
    try {
      final replies = StreamIterator(socket.map((m) => jsonDecode(m as String) as Map<String, dynamic>));
      Future<Map<String, dynamic>> next() async {
        if (!await replies.moveNext().timeout(timeout)) throw const HaDashboardsException("closed");
        return replies.current;
      }

      if ((await next())["type"] != "auth_required") throw const HaDashboardsException("unexpected greeting");
      socket.add(jsonEncode({"type": "auth", "access_token": token}));
      if ((await next())["type"] != "auth_ok") throw const HaDashboardsException("not signed in");
      socket.add(jsonEncode({"id": 1, ...command}));
      while (true) {
        final reply = await next();
        if (reply["id"] != 1) continue;
        if (reply["success"] != true) throw HaDashboardsException("${command["type"]} failed");
        return reply["result"];
      }
    } finally {
      unawaited(socket.close());
    }
  }
}

class HaDashboardsException implements Exception {
  final String message;

  const HaDashboardsException(this.message);

  @override
  String toString() => "HaDashboardsException: $message";
}
