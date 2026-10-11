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

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/ha_dashboards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("The WebSocket address follows the base address's scheme and path", () {
    expect(HaDashboards.webSocketUri("http://192.0.2.10:8123").toString(), "ws://192.0.2.10:8123/api/websocket");
    expect(HaDashboards.webSocketUri("https://ha.example.com/").toString(), "wss://ha.example.com/api/websocket");
  });

  test("Dashboards: the default one first, then Home Assistant's, by title", () {
    final list = HaDashboards.parseDashboards([
      {"url_path": "tv-room", "title": "TV room", "mode": "storage"},
      {"url_path": "map", "title": ""},
      {"title": "No path"},
    ]);
    expect(list, [
      HaDashboards.overview,
      const HaDashboardChoice("tv-room", "TV room"),
      const HaDashboardChoice("map", "map"),
    ]);
    expect(HaDashboards.parseDashboards(null), [HaDashboards.overview]);
  });

  test("Views: by their own path, else by their place", () {
    final views = HaDashboards.parseViews("tv-room", {
      "views": [
        {"path": "home", "title": "Home"},
        {"title": "Lights"},
      ]
    });
    expect(views, [
      const HaDashboardChoice("tv-room/home", "Home"),
      const HaDashboardChoice("tv-room/1", "Lights"),
    ]);
    expect(HaDashboards.parseViews("tv-room", {"strategy": {}}), isEmpty);
  });

  test("Signs in with the token and asks for the dashboards", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sent = <Map<String, dynamic>>[];
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.add(jsonEncode({"type": "auth_required"}));
      socket.listen((message) {
        final msg = jsonDecode(message as String) as Map<String, dynamic>;
        sent.add(msg);
        if (msg["type"] == "auth") {
          socket.add(jsonEncode({"type": msg["access_token"] == "t0ken" ? "auth_ok" : "auth_invalid"}));
        } else {
          socket.add(jsonEncode({
            "id": msg["id"],
            "type": "result",
            "success": true,
            "result": [
              {"url_path": "tv-room", "title": "TV room"}
            ],
          }));
        }
      });
    });
    addTearDown(() => server.close(force: true));

    final dashboards = await HaDashboards("http://127.0.0.1:${server.port}", "t0ken").dashboards();

    expect(dashboards, [HaDashboards.overview, const HaDashboardChoice("tv-room", "TV room")]);
    expect(sent.last["type"], "lovelace/dashboards/list");

    await expectLater(
        HaDashboards("http://127.0.0.1:${server.port}", "wrong").dashboards(), throwsA(isA<HaDashboardsException>()));
  });
}
