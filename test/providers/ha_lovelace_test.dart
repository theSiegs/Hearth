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

import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flauncher/widgets/ha_panel/ha_panel.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

HaConditionContext _ctx(Map<String, String> states, {String? userId}) =>
    HaConditionContext((id) => states.containsKey(id) ? HaEntity(id, states[id]!) : null, userId: userId);

void main() {
  group("Dashboard paths", () {
    test("split into dashboard and view", () {
      expect(HaLovelace.splitPath("tv-room/home"), ("tv-room", "home"));
      expect(HaLovelace.splitPath("/tv-room/"), ("tv-room", null));
      expect(HaLovelace.splitPath(""), ("lovelace", null));
    });

    test("pick a view by path, by place, else the first", () {
      final config = {
        "views": [
          {"path": "home", "title": "Home"},
          {"title": "Lights"},
        ]
      };
      expect(HaLovelace.pickView(config, "home")!["title"], "Home");
      expect(HaLovelace.pickView(config, "1")!["title"], "Lights");
      expect(HaLovelace.pickView(config, "nope")!["title"], "Home");
      expect(HaLovelace.pickView(config, null)!["title"], "Home");
      expect(HaLovelace.pickView({"strategy": {}}, null), isNull);
    });
  });

  group("Config", () {
    final config = {
      "views": [
        {
          "title": "Home",
          "path": "home",
          "type": "sections",
          "sections": [
            {
              "type": "grid",
              "cards": [
                {"type": "heading", "heading": "Lights", "icon": "mdi:lightbulb-group"},
                {
                  "type": "tile",
                  "entity": "light.living_room",
                  "name": "Living room",
                  "tap_action": {"action": "toggle"},
                  "features": [
                    {"type": "light-brightness"}
                  ],
                  "grid_options": {"columns": 12},
                },
                {
                  "type": "tile",
                  "entity": "sensor.outside",
                  "grid_options": {"columns": 6}
                },
                {"type": "tile", "entity": "person.alex"},
                {"type": "picture-glance", "entity": "camera.door"},
              ]
            },
            {
              "type": "grid",
              "visibility": [
                {"condition": "state", "entity": "binary_sensor.washer", "state": "on"}
              ],
              "cards": [
                {
                  "type": "tile",
                  "entity": "media_player.kitchen",
                  "state_content": ["media_title", "state"],
                  "features": [
                    {"type": "media-player-playback"},
                    {"type": "media-player-volume-slider"},
                    {"type": "something-new"},
                  ],
                  "visibility": [
                    {
                      "condition": "state",
                      "entity": "media_player.kitchen",
                      "state": ["playing", "paused"]
                    }
                  ],
                },
                {
                  "type": "vertical-stack",
                  "cards": [
                    {
                      "type": "tile",
                      "entity": "climate.hall",
                      "features": [
                        {"type": "target-temperature"},
                        {
                          "type": "climate-hvac-modes",
                          "hvac_modes": ["heat", "off"]
                        }
                      ]
                    },
                    {
                      "type": "conditional",
                      "conditions": [
                        {"entity": "sun.sun", "state_not": "below_horizon"}
                      ],
                      "card": {
                        "type": "tile",
                        "entity": "scene.day",
                        "tap_action": {
                          "action": "perform-action",
                          "perform_action": "scene.turn_on",
                          "target": {"entity_id": "scene.day"}
                        }
                      },
                    },
                  ]
                },
              ]
            },
          ]
        },
        {
          "title": "Other",
          "cards": [
            {"type": "tile", "entity": "light.porch"}
          ]
        },
      ]
    };

    test("reads headings, tiles and their features, and keeps what it can't draw as unsupported", () {
      final layout = HaLovelace.parse(config, "home");
      expect(layout.title, "Home");
      expect(layout.sections, hasLength(2));
      final cards = layout.sections[0].cards;
      expect((cards[0] as HaHeadingCard).heading, "Lights");
      expect((cards[0] as HaHeadingCard).icon, "mdi:lightbulb-group");
      final light = cards[1] as HaTileCard;
      expect(light.entity, "light.living_room");
      expect(light.name, "Living room");
      expect(light.tapAction!.action, "toggle");
      expect(light.features.single, isA<HaLightBrightnessFeature>());
      expect(light.half, isFalse);
      expect((cards[2] as HaTileCard).half, isTrue);
      // No grid options and no controls: half, as Home Assistant's own tiles
      expect((cards[3] as HaTileCard).half, isTrue);
      expect(cards[4], isA<HaUnsupportedCard>());
      expect(layout.hasUnsupported, isTrue);
    });

    test("flattens stacks and conditional cards, passing their conditions on", () {
      final layout = HaLovelace.parse(config, "home");
      final cards = layout.sections[1].cards;
      final media = cards[0] as HaTileCard;
      expect(media.stateContent, ["media_title", "state"]);
      expect(media.features[0], isA<HaMediaPlaybackFeature>());
      expect(media.features[1], isA<HaVolumeSliderFeature>());
      expect(media.features[2], isA<HaUnsupportedFeature>());
      expect(media.half, isFalse);
      final climate = cards[1] as HaTileCard;
      expect((climate.features[1] as HaHvacModesFeature).modes, ["heat", "off"]);
      final scene = cards[2] as HaTileCard;
      expect(scene.tapAction!.performAction, "scene.turn_on");
      expect(scene.tapAction!.target, {"entity_id": "scene.day"});
      expect(scene.visibility.single, isA<HaStateCondition>());
      expect(layout.sections[1].visibility.single, isA<HaStateCondition>());
    });

    test("an older view's cards are one section, full width", () {
      final layout = HaLovelace.parse(config, "1");
      expect(layout.sections.single.cards.single.half, isFalse);
    });

    test("knows every entity it looks at", () {
      final layout = HaLovelace.parse(config, "home");
      expect(layout.entities, containsAll(["light.living_room", "binary_sensor.washer", "sun.sun", "scene.day"]));
    });
  });

  group("Visibility", () {
    HaCondition parse(Object json) => HaCondition.parse(json)!;

    test("state: one state or a list, and state_not", () {
      final playing = parse({
        "condition": "state",
        "entity": "media_player.kitchen",
        "state": ["playing", "paused"]
      });
      expect(playing.test(_ctx({"media_player.kitchen": "paused"})), isTrue);
      expect(playing.test(_ctx({"media_player.kitchen": "idle"})), isFalse);
      expect(parse({"condition": "state", "entity": "light.a", "state": "on"}).test(_ctx({"light.a": "on"})), isTrue);
      final notOff = parse({"condition": "state", "entity": "light.a", "state_not": "off"});
      expect(notOff.test(_ctx({"light.a": "on"})), isTrue);
      expect(notOff.test(_ctx({"light.a": "off"})), isFalse);
    });

    test("a missing entity is unavailable", () {
      expect(parse({"condition": "state", "entity": "light.gone", "state": "on"}).test(_ctx({})), isFalse);
      expect(parse({"condition": "state", "entity": "light.gone", "state": "unavailable"}).test(_ctx({})), isTrue);
      expect(parse({"condition": "state", "entity": "light.gone", "state_not": "on"}).test(_ctx({})), isTrue);
    });

    test("or, and, not", () {
      final either = parse({
        "condition": "or",
        "conditions": [
          {"condition": "state", "entity": "binary_sensor.washer", "state": "on"},
          {"condition": "state", "entity": "binary_sensor.dryer", "state": "on"},
        ]
      });
      expect(either.test(_ctx({"binary_sensor.washer": "off", "binary_sensor.dryer": "on"})), isTrue);
      expect(either.test(_ctx({"binary_sensor.washer": "off", "binary_sensor.dryer": "off"})), isFalse);
      final both = parse({
        "condition": "and",
        "conditions": [
          {"condition": "state", "entity": "binary_sensor.washer", "state": "on"},
          {"condition": "state", "entity": "binary_sensor.dryer", "state": "on"},
        ]
      });
      expect(both.test(_ctx({"binary_sensor.washer": "on", "binary_sensor.dryer": "off"})), isFalse);
      expect(both.test(_ctx({"binary_sensor.washer": "on", "binary_sensor.dryer": "on"})), isTrue);
      final neither = parse({
        "condition": "not",
        "conditions": [
          {"condition": "state", "entity": "binary_sensor.washer", "state": "on"},
        ]
      });
      expect(neither.test(_ctx({"binary_sensor.washer": "off"})), isTrue);
    });

    test("numeric_state, user, and kinds it doesn't know (they show)", () {
      final warm = parse({"condition": "numeric_state", "entity": "sensor.t", "above": 20, "below": "30"});
      expect(warm.test(_ctx({"sensor.t": "25"})), isTrue);
      expect(warm.test(_ctx({"sensor.t": "31"})), isFalse);
      expect(warm.test(_ctx({"sensor.t": "unknown"})), isFalse);
      final user = parse({
        "condition": "user",
        "users": ["user-1"]
      });
      expect(user.test(_ctx({}, userId: "user-1")), isTrue);
      expect(user.test(_ctx({}, userId: "user-2")), isFalse);
      expect(parse({"condition": "screen", "media_query": "(min-width: 1024px)"}).test(_ctx({})), isTrue);
    });
  });

  group("Rows", () {
    final layout = HaLovelace.parse({
      "views": [
        {
          "sections": [
            {
              "cards": [
                {"type": "heading", "heading": "People"},
                {
                  "type": "tile",
                  "entity": "person.alex",
                  "grid_options": {"columns": 6}
                },
                {
                  "type": "tile",
                  "entity": "person.sam",
                  "grid_options": {"columns": 6}
                },
                {
                  "type": "tile",
                  "entity": "person.robin",
                  "grid_options": {"columns": 6},
                  "visibility": [
                    {"condition": "state", "entity": "person.robin", "state": "home"}
                  ]
                },
                {
                  "type": "tile",
                  "entity": "person.kim",
                  "grid_options": {"columns": 6}
                },
                {
                  "type": "tile",
                  "entity": "light.a",
                  "grid_options": {"columns": 12}
                },
                {
                  "type": "tile",
                  "entity": "person.lee",
                  "grid_options": {"columns": 6}
                },
              ]
            },
            {
              "visibility": [
                {"condition": "state", "entity": "binary_sensor.washer", "state": "on"}
              ],
              "cards": [
                {"type": "heading", "heading": "Laundry"},
              ]
            },
          ]
        }
      ]
    }, null);

    List<List<String>> names(List<HaPanelRow> rows) => [
          for (final r in rows) [for (final c in r.cards) c is HaTileCard ? c.entity : (c as HaHeadingCard).heading]
        ];

    test("half-width tiles pair up; hidden cards and sections are left out", () {
      expect(names(HaPanelRows.build(layout, _ctx({"person.robin": "not_home", "binary_sensor.washer": "off"}))), [
        ["People"],
        ["person.alex", "person.sam"],
        ["person.kim"],
        ["light.a"],
        ["person.lee"],
      ]);
    });

    test("live: a card that shows again pairs up, and a section comes in", () {
      expect(names(HaPanelRows.build(layout, _ctx({"person.robin": "home", "binary_sensor.washer": "on"}))), [
        ["People"],
        ["person.alex", "person.sam"],
        ["person.robin", "person.kim"],
        ["light.a"],
        ["person.lee"],
        ["Laundry"],
      ]);
    });
  });

  group("D-pad", () {
    // Two tiles side by side, then a full-width one, then a − / + pair
    const left = Rect.fromLTWH(0, 0, 100, 50);
    const right = Rect.fromLTWH(110, 0, 100, 50);
    const full = Rect.fromLTWH(0, 60, 210, 50);
    const minus = Rect.fromLTWH(0, 120, 50, 40);
    const plus = Rect.fromLTWH(160, 120, 50, 40);
    final stops = {"left": left, "right": right, "full": full, "minus": minus, "plus": plus};
    Map<String, Rect> without(String s) => Map.of(stops)..remove(s);

    test("Left and Right stay in the row", () {
      expect(HaPanelNavigation.sideways(right, without("right"), left: true), "left");
      expect(HaPanelNavigation.sideways(left, without("left"), left: true), isNull);
      expect(HaPanelNavigation.sideways(minus, without("minus"), left: false), "plus");
      // Nothing to the left on its row: null (the panel closes), not a stop on another row
      expect(HaPanelNavigation.sideways(minus, without("minus"), left: true), isNull);
      expect(HaPanelNavigation.sideways(full, without("full"), left: false), isNull);
    });

    test("Up and Down go row by row, to the nearest stop across", () {
      expect(HaPanelNavigation.vertical(right, without("right"), up: false), "full");
      expect(HaPanelNavigation.vertical(full, without("full"), up: true), "left");
      expect(HaPanelNavigation.vertical(plus, without("plus"), up: true), "full");
      expect(HaPanelNavigation.vertical(full, without("full"), up: false), "minus");
      expect(HaPanelNavigation.vertical(left, without("left"), up: true), isNull);
      expect(HaPanelNavigation.vertical(plus, without("plus"), up: false), isNull);
    });
  });
}
