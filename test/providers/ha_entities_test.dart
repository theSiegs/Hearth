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
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("Adds: the whole state, compressed", () {
    final entities = HaEntityDiff.apply(const {}, {
      "a": {
        "light.living_room": {
          "s": "on",
          "a": {"friendly_name": "Living room", "brightness": 128},
          "c": "01H",
          "lc": 1760000000.5,
        },
        "sensor.outside": {
          "s": 21.5,
          "a": {"unit_of_measurement": "°C"},
          "lc": 1760000000,
          "lu": 1760000060,
        },
      }
    });
    final light = entities["light.living_room"]!;
    expect(light.state, "on");
    expect(light.name, "Living room");
    expect(light.number("brightness"), 128);
    expect(light.lastChanged, DateTime.fromMillisecondsSinceEpoch(1760000000500, isUtc: true).toLocal());
    expect(light.lastUpdated, light.lastChanged);
    final sensor = entities["sensor.outside"]!;
    expect(sensor.state, "21.5");
    expect(sensor.unit, "°C");
    expect(sensor.lastUpdated!.difference(sensor.lastChanged!), const Duration(minutes: 1));
  });

  test("Changes: what's new is added, attributes that went are removed, the rest stays", () {
    final before = HaEntityDiff.apply(const {}, {
      "a": {
        "media_player.kitchen": {
          "s": "playing",
          "a": {"friendly_name": "Kitchen", "media_title": "Song", "volume_level": 0.4},
          "lc": 1760000000,
        }
      }
    });
    final after = HaEntityDiff.apply(before, {
      "c": {
        "media_player.kitchen": {
          "+": {
            "s": "paused",
            "a": {"volume_level": 0.5},
            "lc": 1760000100,
          },
          "-": {
            "a": ["media_title"]
          },
        },
        "media_player.not_known": {
          "+": {"s": "on"}
        },
      }
    });
    final player = after["media_player.kitchen"]!;
    expect(player.state, "paused");
    expect(player.attributes, {"friendly_name": "Kitchen", "volume_level": 0.5});
    expect(player.lastChanged, DateTime.fromMillisecondsSinceEpoch(1760000100000, isUtc: true).toLocal());
    expect(after.containsKey("media_player.not_known"), isFalse);
    // The map given is left as it was
    expect(before["media_player.kitchen"]!.state, "playing");

    // An attribute-only change keeps the state and when it changed
    final again = HaEntityDiff.apply(after, {
      "c": {
        "media_player.kitchen": {
          "+": {
            "a": {"volume_level": 0.6},
            "lu": 1760000200,
          }
        }
      }
    });
    expect(again["media_player.kitchen"]!.state, "paused");
    expect(again["media_player.kitchen"]!.lastChanged, player.lastChanged);
    expect(again["media_player.kitchen"]!.number("volume_level"), 0.6);
  });

  test("Removes", () {
    final before = HaEntityDiff.apply(const {}, {
      "a": {
        "light.a": {"s": "on"},
        "light.b": {"s": "off"}
      }
    });
    final after = HaEntityDiff.apply(before, {
      "r": ["light.a"]
    });
    expect(after.keys, ["light.b"]);
    expect(HaEntityDiff.apply(after, "nonsense"), same(after));
  });

  test("Supported features are bits", () {
    const player = HaEntity("media_player.a", "playing", attributes: {"supported_features": 16 | 32});
    expect(player.supports(16), isTrue);
    expect(player.supports(1), isFalse);
  });
}
