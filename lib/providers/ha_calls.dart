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

/// A service call a panel control makes: "light.turn_on", its target and its data.
class HaCall {
  final String action;
  final Map<String, Object?> target;
  final Map<String, Object?> data;

  const HaCall(this.action, {this.target = const {}, this.data = const {}});

  HaCall.on(String entityId, this.action, [this.data = const {}]) : target = {"entity_id": entityId};

  @override
  bool operator ==(Object other) =>
      other is HaCall && other.action == action && _same(other.target, target) && _same(other.data, data);

  static bool _same(Map a, Map b) =>
      a.length == b.length && a.keys.every((k) => b.containsKey(k) && "${a[k]}" == "${b[k]}");

  @override
  int get hashCode => action.hashCode;

  @override
  String toString() => "$action $target $data";
}

/// media_player's supported_features bits.
class HaMediaFeatures {
  static const int pause = 1;
  static const int volumeSet = 4;
  static const int previousTrack = 16;
  static const int nextTrack = 32;
  static const int turnOn = 128;
  static const int turnOff = 256;
  static const int stop = 4096;
  static const int play = 16384;
}

/// A playback button and what it does.
enum HaPlayback { turnOn, previous, play, pause, stop, next }

/// What the panel's controls ask Home Assistant to do.
class HaCalls {
  /// Domains whose tiles toggle on OK (as their icon does in Home Assistant).
  static const Set<String> _toggles = {"light", "switch", "fan", "input_boolean", "siren", "humidifier"};

  /// OK on a tile: its tap_action, else what the tile's entity does by default; null for nothing.
  static HaCall? tap(HaTileCard card, HaEntity? entity) {
    final action = card.tapAction;
    final domain = HaEntity.domainOf(card.entity);
    switch (action?.action) {
      case "none":
      case "navigate":
      case "url":
      case "assist":
        return null;
      case "toggle":
        return toggle(card.entity);
      case "perform-action":
        final perform = action!.performAction;
        if (perform == null || !perform.contains(".")) return null;
        return HaCall(perform, target: action.target, data: action.data);
    }
    // more-info, or none given
    if (_toggles.contains(domain)) return toggle(card.entity);
    return switch (domain) {
      "scene" || "script" => HaCall.on(card.entity, "$domain.turn_on"),
      "button" || "input_button" => HaCall.on(card.entity, "$domain.press"),
      "lock" => HaCall.on(card.entity, entity?.state == "locked" ? "lock.unlock" : "lock.lock"),
      _ => null,
    };
  }

  /// OK does something on [card].
  static bool actionable(HaTileCard card) => tap(card, null) != null;

  static HaCall toggle(String entityId) {
    final domain = HaEntity.domainOf(entityId);
    return HaCall.on(
        entityId,
        (_toggles.contains(domain) || domain == "media_player" || domain == "cover")
            ? "$domain.toggle"
            : "homeassistant.toggle");
  }

  /// One press of − or + on a thermostat: [unit] is Home Assistant's temperature unit ("°F" steps by 1, else 0.5).
  static double temperatureStep(HaEntity entity, String? unit) {
    final step = entity.number("target_temp_step");
    if (step != null && step > 0) return step.toDouble();
    return unit == "°F" ? 1 : 0.5;
  }

  /// [value] kept within the thermostat's range and on its steps.
  static double clampTemperature(HaEntity entity, double value, double step) {
    final min = entity.number("min_temp")?.toDouble() ?? -100;
    final max = entity.number("max_temp")?.toDouble() ?? 1000;
    final stepped = (value / step).round() * step;
    return double.parse(stepped.clamp(min, max).toStringAsFixed(2));
  }

  static HaCall setTemperature(String entityId, double temperature) =>
      HaCall.on(entityId, "climate.set_temperature", {"temperature": temperature});

  static HaCall setTemperatureRange(String entityId, double low, double high) =>
      HaCall.on(entityId, "climate.set_temperature", {"target_temp_low": low, "target_temp_high": high});

  static HaCall setHvacMode(String entityId, String mode) =>
      HaCall.on(entityId, "climate.set_hvac_mode", {"hvac_mode": mode});

  /// The playback buttons a player has now, as Home Assistant's tile shows them.
  static List<HaPlayback> playback(HaEntity entity) {
    final off = entity.state == "off" || entity.state == "standby";
    if (off) return entity.supports(HaMediaFeatures.turnOn) ? const [HaPlayback.turnOn] : const [];
    final playing = entity.state == "playing";
    return [
      if (entity.supports(HaMediaFeatures.previousTrack)) HaPlayback.previous,
      if (playing && entity.supports(HaMediaFeatures.pause))
        HaPlayback.pause
      else if (playing && entity.supports(HaMediaFeatures.stop))
        HaPlayback.stop
      else if (!playing && entity.supports(HaMediaFeatures.play))
        HaPlayback.play,
      if (entity.supports(HaMediaFeatures.nextTrack)) HaPlayback.next,
    ];
  }

  static HaCall playbackCall(String entityId, HaPlayback button) => HaCall.on(
      entityId,
      switch (button) {
        HaPlayback.turnOn => "media_player.turn_on",
        HaPlayback.previous => "media_player.media_previous_track",
        HaPlayback.play => "media_player.media_play",
        HaPlayback.pause => "media_player.media_pause",
        HaPlayback.stop => "media_player.media_stop",
        HaPlayback.next => "media_player.media_next_track",
      });

  /// [level] 0 to 1.
  static HaCall volume(String entityId, double level) => HaCall.on(
      entityId, "media_player.volume_set", {"volume_level": double.parse(level.clamp(0, 1).toStringAsFixed(2))});

  /// [percent] 0 to 100; 0 turns the light off.
  static HaCall brightness(String entityId, int percent) => percent <= 0
      ? HaCall.on(entityId, "light.turn_off")
      : HaCall.on(entityId, "light.turn_on", {"brightness_pct": percent.clamp(1, 100)});

  /// A light's brightness now, 0 to 100 (0 when it's off).
  static int brightnessPercent(HaEntity? entity) {
    if (entity == null || entity.state != "on") return 0;
    final b = entity.number("brightness");
    return b == null ? 100 : (b / 2.55).round().clamp(0, 100);
  }
}
