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

import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/providers/ha_panel_service.dart';
import 'package:flauncher/providers/ha_socket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ha_fake_server.dart';

/// Waits (for real) until [condition] holds.
Future<void> until(bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail("timed out waiting${reason == null ? "" : " for $reason"}");
}

final Map<String, Object?> _dashboard = {
  "views": [
    {
      "path": "home",
      "title": "Home",
      "sections": [
        {
          "cards": [
            {"type": "heading", "heading": "Lights"},
            {
              "type": "tile",
              "entity": "light.living_room",
              "tap_action": {"action": "toggle"},
              "visibility": [
                {"condition": "state", "entity": "binary_sensor.evening", "state": "on"}
              ]
            },
          ]
        }
      ]
    },
    {
      "path": "other",
      "cards": [
        {"type": "tile", "entity": "sensor.outside"}
      ]
    }
  ]
};

void main() {
  late HaFakeServer server;

  setUp(() async {
    server = await HaFakeServer.start(dashboards: {
      "tv-room": _dashboard
    }, states: {
      "light.living_room": {
        "s": "off",
        "a": {"friendly_name": "Living room"}
      },
      "binary_sensor.evening": {"s": "on"},
      "sensor.outside": {
        "s": "21",
        "a": {"unit_of_measurement": "°C"}
      },
      "sensor.not_on_the_dashboard": {"s": "1"},
    });
  });

  tearDown(() => server.close());

  HaPanelService service({String path = "tv-room/home", String? token}) => HaPanelService(
        connection: () async => (url: server.url, token: token ?? server.token),
        dashboard: () async => path,
      );

  test("Reads the view and subscribes to the entities on it, and only those", () async {
    final s = service();
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.ready && s.entities.isNotEmpty);
    expect(s.layout.title, "Home");
    expect(server.commands("lovelace/config").single["url_path"], "tv-room");
    expect((server.commands("subscribe_entities").single["entity_ids"] as List).toSet(),
        {"light.living_room", "binary_sensor.evening"});
    expect(s.entity("light.living_room")!.state, "off");
    expect(s.entity("sensor.not_on_the_dashboard"), isNull);
    expect(s.temperatureUnit, "°F");
    expect(s.translate("component.person.entity_component._.state.not_home"), "Away");
    expect(s.conditionContext.userId, "user-1");
  });

  test("Live states: changes come in and visibility follows them", () async {
    final s = service();
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.entities.length == 2);
    final tile = s.layout.cards.whereType<HaTileCard>().single;
    expect(HaCondition.all(tile.visibility, s.conditionContext), isTrue);
    server.change("binary_sensor.evening", "off");
    await until(() => s.entity("binary_sensor.evening")!.state == "off");
    expect(HaCondition.all(tile.visibility, s.conditionContext), isFalse);
  });

  test("Service calls go as call_service with their target and data", () async {
    final s = service();
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.ready);
    expect(await s.perform("light.turn_on", target: {"entity_id": "light.living_room"}, data: {"brightness_pct": 40}),
        isTrue);
    final call = server.commands("call_service").single;
    expect(call["domain"], "light");
    expect(call["service"], "turn_on");
    expect(call["target"], {"entity_id": "light.living_room"});
    expect(call["service_data"], {"brightness_pct": 40});
    server.failServices = true;
    expect(await s.callService("light", "toggle"), isFalse);
  });

  test("Entity pictures: Home Assistant's own with the token, other https ones as they are", () {
    const ha = (url: "http://192.0.2.10:8123/", token: "t0ken");
    final own = HaPanelService.pictureRequest("/api/image/serve/abc/512x512", ha)!;
    expect(own.uri.toString(), "http://192.0.2.10:8123/api/image/serve/abc/512x512");
    expect(own.headers, {"Authorization": "Bearer t0ken"});
    final full = HaPanelService.pictureRequest("http://192.0.2.10:8123/api/media_player_proxy/media_player.a", ha)!;
    expect(full.headers, {"Authorization": "Bearer t0ken"});
    final other = HaPanelService.pictureRequest("https://images.example.com/cover.jpg", ha)!;
    expect(other.uri.toString(), "https://images.example.com/cover.jpg");
    expect(other.headers, isEmpty);
    expect(HaPanelService.pictureRequest("http://images.example.com/cover.jpg", ha), isNull);
    expect(HaPanelService.pictureRequest("/api/image/serve/abc", null), isNull);
    expect(HaPanelService.pictureRequest("", ha), isNull);
  });

  test("The service call payload leaves out what isn't given", () {
    expect(HaSocket.serviceCall("scene", "turn_on"), {"type": "call_service", "domain": "scene", "service": "turn_on"});
    expect(
        HaSocket.serviceCall("weather", "get_forecasts",
            target: {"entity_id": "weather.home"}, data: {"type": "hourly"}, returnResponse: true),
        {
          "type": "call_service",
          "domain": "weather",
          "service": "get_forecasts",
          "service_data": {"type": "hourly"},
          "target": {"entity_id": "weather.home"},
          "return_response": true,
        });
  });

  test("Connects again after a drop, and the states come back", () async {
    final s = service();
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.ready && s.entities.isNotEmpty);
    await server.dropAll();
    await until(() => s.status == HaPanelStatus.unreachable, reason: "the drop");
    // What was read stays on show meanwhile
    expect(s.layoutLoaded, isTrue);
    server.states["light.living_room"] = {"s": "on"};
    await until(() => s.status == HaPanelStatus.ready && s.entity("light.living_room")?.state == "on",
        reason: "the reconnect");
    expect(server.commands("subscribe_entities"), hasLength(2));
  });

  test("A token Home Assistant turns down: unreachable", () async {
    final s = service(token: "wrong");
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.unreachable);
    expect(s.layoutLoaded, isFalse);
  });

  test("Markdown templates: Home Assistant renders them, and they're read again on a new layout", () async {
    server.dashboards["md"] = {
      "views": [
        {
          "cards": [
            {"type": "markdown", "content": "{{ 1 + 1 }} playing"},
            {"type": "markdown", "content": "Plain"},
          ]
        }
      ]
    };
    server.renderTemplate = (t) => t == "{{ 1 + 1 }} playing" ? "2 playing" : "?";
    final s = service(path: "md");
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.rendered("{{ 1 + 1 }} playing") != null);
    expect(s.rendered("{{ 1 + 1 }} playing"), "2 playing");
    final asked = server.commands("render_template").single;
    expect(asked["template"], "{{ 1 + 1 }} playing");
    expect(asked["report_errors"], isFalse);
  });

  test("Not set up: says so, without connecting", () async {
    final s = HaPanelService(connection: () async => null, dashboard: () async => "lovelace");
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.notSetUp);
    expect(server.received, isEmpty);
  });

  test("Opening again with another dashboard reads it on the same connection", () async {
    var path = "tv-room/home";
    final s =
        HaPanelService(connection: () async => (url: server.url, token: server.token), dashboard: () async => path);
    addTearDown(s.dispose);
    s.attach();
    await until(() => s.status == HaPanelStatus.ready);
    s.detach();
    path = "tv-room/other";
    s.attach();
    await until(() => s.entity("sensor.outside") != null);
    expect(server.commands("lovelace/config"), hasLength(2));
    expect(server.commands("auth/current_user"), hasLength(1));
  });
}
