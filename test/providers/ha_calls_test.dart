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

import 'package:flauncher/providers/ha_calls.dart';
import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/providers/ha_lovelace.dart';
import 'package:flutter_test/flutter_test.dart';

HaTileCard tile(String entity, [Map<String, Object?>? tapAction]) =>
    HaTileCard(entity, tapAction: HaAction.parse(tapAction));

void main() {
  group("OK on a tile", () {
    test("toggle, perform-action (and its older name), none", () {
      expect(HaCalls.tap(tile("light.living_room", {"action": "toggle"}), null),
          HaCall.on("light.living_room", "light.toggle"));
      expect(HaCalls.tap(tile("sensor.a", {"action": "toggle"}), null), HaCall.on("sensor.a", "homeassistant.toggle"));
      expect(
          HaCalls.tap(
              tile("scene.evening", {
                "action": "perform-action",
                "perform_action": "scene.turn_on",
                "target": {"entity_id": "scene.evening"},
                "data": {"transition": 2},
              }),
              null),
          const HaCall("scene.turn_on", target: {"entity_id": "scene.evening"}, data: {"transition": 2}));
      expect(
          HaCalls.tap(
              tile("script.x", {
                "action": "call-service",
                "service": "script.turn_on",
                "service_data": {"entity_id": "script.x"}
              }),
              null),
          const HaCall("script.turn_on", data: {"entity_id": "script.x"}));
      expect(HaCalls.tap(tile("light.a", {"action": "none"}), null), isNull);
    });

    test("without a tap action: what the entity does by default", () {
      expect(HaCalls.tap(tile("switch.fan"), null), HaCall.on("switch.fan", "switch.toggle"));
      expect(HaCalls.tap(tile("scene.day"), null), HaCall.on("scene.day", "scene.turn_on"));
      expect(HaCalls.tap(tile("input_button.go"), null), HaCall.on("input_button.go", "input_button.press"));
      expect(
          HaCalls.tap(tile("lock.door"), const HaEntity("lock.door", "locked")), HaCall.on("lock.door", "lock.unlock"));
      expect(HaCalls.tap(tile("sensor.outside"), null), isNull);
      expect(HaCalls.tap(tile("person.alex", {"action": "more-info"}), null), isNull);
    });
  });

  group("Thermostat", () {
    const climate = HaEntity("climate.hall", "heat", attributes: {
      "temperature": 70,
      "min_temp": 50,
      "max_temp": 80,
      "hvac_modes": ["heat", "off"]
    });

    test("steps by its own step, else by the unit's", () {
      expect(HaCalls.temperatureStep(climate, "°F"), 1);
      expect(HaCalls.temperatureStep(climate, "°C"), 0.5);
      expect(HaCalls.temperatureStep(const HaEntity("climate.a", "heat", attributes: {"target_temp_step": 0.1}), "°C"),
          0.1);
    });

    test("stays within its range and on its steps", () {
      expect(HaCalls.clampTemperature(climate, 81, 1), 80);
      expect(HaCalls.clampTemperature(climate, 20, 1), 50);
      expect(HaCalls.clampTemperature(climate, 71.26, 0.5), 71.5);
    });

    test("calls", () {
      expect(HaCalls.setTemperature("climate.hall", 71),
          HaCall.on("climate.hall", "climate.set_temperature", {"temperature": 71.0}));
      expect(HaCalls.setTemperatureRange("climate.hall", 66, 74),
          HaCall.on("climate.hall", "climate.set_temperature", {"target_temp_low": 66.0, "target_temp_high": 74.0}));
      expect(HaCalls.setHvacMode("climate.hall", "off"),
          HaCall.on("climate.hall", "climate.set_hvac_mode", {"hvac_mode": "off"}));
    });
  });

  group("Player", () {
    const all = HaMediaFeatures.pause |
        HaMediaFeatures.play |
        HaMediaFeatures.previousTrack |
        HaMediaFeatures.nextTrack |
        HaMediaFeatures.turnOn |
        HaMediaFeatures.stop;

    test("buttons by its state and supported features", () {
      expect(HaCalls.playback(const HaEntity("media_player.a", "playing", attributes: {"supported_features": all})),
          [HaPlayback.previous, HaPlayback.pause, HaPlayback.next]);
      expect(HaCalls.playback(const HaEntity("media_player.a", "paused", attributes: {"supported_features": all})),
          [HaPlayback.previous, HaPlayback.play, HaPlayback.next]);
      expect(
          HaCalls.playback(
              const HaEntity("media_player.a", "playing", attributes: {"supported_features": HaMediaFeatures.stop})),
          [HaPlayback.stop]);
      expect(HaCalls.playback(const HaEntity("media_player.a", "off", attributes: {"supported_features": all})),
          [HaPlayback.turnOn]);
      expect(HaCalls.playback(const HaEntity("media_player.a", "off")), isEmpty);
    });

    test("calls", () {
      expect(HaCalls.playbackCall("media_player.a", HaPlayback.pause),
          HaCall.on("media_player.a", "media_player.media_pause"));
      expect(HaCalls.playbackCall("media_player.a", HaPlayback.next),
          HaCall.on("media_player.a", "media_player.media_next_track"));
      expect(HaCalls.volume("media_player.a", 0.456),
          HaCall.on("media_player.a", "media_player.volume_set", {"volume_level": 0.46}));
      expect(HaCalls.volume("media_player.a", 1.3),
          HaCall.on("media_player.a", "media_player.volume_set", {"volume_level": 1.0}));
    });
  });

  group("Light", () {
    test("brightness as a percentage; 0 turns it off", () {
      expect(HaCalls.brightnessPercent(const HaEntity("light.a", "on", attributes: {"brightness": 128})), 50);
      expect(HaCalls.brightnessPercent(const HaEntity("light.a", "on")), 100);
      expect(HaCalls.brightnessPercent(const HaEntity("light.a", "off", attributes: {"brightness": 128})), 0);
      expect(HaCalls.brightness("light.a", 40), HaCall.on("light.a", "light.turn_on", {"brightness_pct": 40}));
      expect(HaCalls.brightness("light.a", 0), HaCall.on("light.a", "light.turn_off"));
    });
  });
}
