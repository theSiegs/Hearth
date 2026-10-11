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

import 'package:flauncher/l10n/app_localizations_en.dart';
import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/widgets/ha_panel/ha_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  final format =
      HaFormat(AppLocalizationsEn(), (key) => key.endsWith(".not_home") ? "Away" : null, now, temperatureUnit: "°F");

  HaEntity sensor(String state, {String? unit, String? deviceClass}) => HaEntity("sensor.a", state, attributes: {
        if (unit != null) "unit_of_measurement": unit,
        if (deviceClass != null) "device_class": deviceClass,
      });

  group("Durations: hours and minutes, no seconds", () {
    test("from each unit", () {
      expect(format.state(sensor("45", unit: "min", deviceClass: "duration")), "45 min");
      expect(format.state(sensor("196", unit: "min", deviceClass: "duration")), "3 h 16 min");
      expect(format.state(sensor("11765", unit: "s", deviceClass: "duration")), "3 h 16 min");
      expect(format.state(sensor("2700", unit: "s", deviceClass: "duration")), "45 min");
      expect(format.state(sensor("3.25", unit: "h", deviceClass: "duration")), "3 h 15 min");
      expect(format.state(sensor("0.5", unit: "d", deviceClass: "duration")), "12 h");
      expect(format.state(sensor("29", unit: "s", deviceClass: "duration")), "0 min");
    });

    test("anything else stays as Home Assistant has it", () {
      expect(format.state(sensor("unknown", unit: "min", deviceClass: "duration")), "—");
      expect(format.state(sensor("45", unit: "fortnights", deviceClass: "duration")), "45 fortnights");
      expect(format.state(sensor("45", unit: "min")), "45 min");
    });
  });

  test("Timestamps: how far off", () {
    expect(
        format.state(sensor(now.add(const Duration(minutes: 40)).toUtc().toIso8601String(), deviceClass: "timestamp")),
        "in 40 min");
    expect(
        format.state(sensor(now.subtract(const Duration(hours: 2, minutes: 5)).toUtc().toIso8601String(),
            deviceClass: "timestamp")),
        "2 h 5 min ago");
    expect(format.state(sensor(now.toUtc().toIso8601String(), deviceClass: "timestamp")), "now");
  });

  test("A scene's state is when it last ran", () {
    expect(format.state(HaEntity("scene.evening", now.subtract(const Duration(minutes: 30)).toUtc().toIso8601String())),
        "30 min ago");
  });

  test("Numbers with their units; long fractions cut short", () {
    expect(format.state(sensor("21.456", unit: "°C")), "21.5 °C");
    expect(format.state(sensor("40", unit: "%")), "40%");
  });

  test("States in Home Assistant's words, else readable", () {
    expect(format.state(const HaEntity("person.alex", "not_home")), "Away");
    expect(format.state(const HaEntity("person.alex", "School")), "School");
    expect(format.state(const HaEntity("media_player.a", "playing")), "Playing");
    expect(format.state(const HaEntity("climate.a", "heat", attributes: {"current_temperature": 66})), "Heat · 66 °F");
    expect(format.state(const HaEntity("light.a", "on", attributes: {"brightness": 128})), "On · 50%");
  });

  test("A tile's state content", () {
    const player = HaEntity("media_player.a", "paused", attributes: {"media_title": "Song", "media_artist": "Band"});
    expect(format.tileState(player, ["media_title", "media_artist", "state"]), "Song · Band · Paused");
    expect(format.tileState(const HaEntity("media_player.a", "idle"), ["media_title", "state"]), "Idle");
    expect(format.tileState(null, const []), "—");
  });
}
