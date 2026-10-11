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
import 'package:flutter/material.dart';

/// Home Assistant's icons ("mdi:lightbulb") as the nearest Material icons, which Flutter has built in (Material Design
/// Icons, which Home Assistant uses, would be a large font to ship).
class HaIcons {
  static const Map<String, IconData> _mdi = {
    "account": Icons.person,
    "account-circle": Icons.account_circle,
    "account-group": Icons.groups,
    "account-multiple": Icons.group,
    "air-conditioner": Icons.ac_unit,
    "air-filter": Icons.air,
    "alarm": Icons.alarm,
    "alert": Icons.warning_amber,
    "alert-circle": Icons.error_outline,
    "battery": Icons.battery_full,
    "bed": Icons.bed,
    "bell": Icons.notifications,
    "blinds": Icons.blinds,
    "brightness-5": Icons.brightness_5,
    "brightness-6": Icons.brightness_6,
    "brightness-7": Icons.brightness_7,
    "calendar": Icons.calendar_month,
    "calendar-today": Icons.today,
    "car": Icons.directions_car,
    "cast": Icons.cast,
    "cellphone": Icons.smartphone,
    "cellphone-clock": Icons.phonelink_lock,
    "check": Icons.check,
    "clock": Icons.schedule,
    "clock-outline": Icons.schedule,
    "clock-check-outline": Icons.alarm_on,
    "coffee": Icons.coffee,
    "cog": Icons.settings,
    "dishwasher": Icons.kitchen,
    "door": Icons.door_front_door,
    "door-closed": Icons.door_front_door,
    "door-open": Icons.door_front_door_outlined,
    "fan": Icons.mode_fan_off,
    "fire": Icons.local_fire_department,
    "flash": Icons.flash_on,
    "garage": Icons.garage,
    "gauge": Icons.speed,
    "home": Icons.home,
    "home-assistant": Icons.home,
    "home-outline": Icons.home_outlined,
    "lamp": Icons.light,
    "lightbulb": Icons.lightbulb,
    "lightbulb-group": Icons.lightbulb,
    "lightbulb-outline": Icons.lightbulb_outline,
    "lock": Icons.lock,
    "lock-open": Icons.lock_open,
    "map": Icons.map,
    "map-marker": Icons.place,
    "motion-sensor": Icons.sensors,
    "movie": Icons.movie,
    "music": Icons.music_note,
    "music-note": Icons.music_note,
    "palette": Icons.palette,
    "play": Icons.play_arrow,
    "power": Icons.power_settings_new,
    "power-plug": Icons.power,
    "progress-clock": Icons.timelapse,
    "robot-vacuum": Icons.cleaning_services,
    "school": Icons.school,
    "shield": Icons.shield,
    "sofa": Icons.weekend,
    "speaker": Icons.speaker,
    "speaker-multiple": Icons.speaker_group,
    "television": Icons.tv,
    "thermometer": Icons.thermostat,
    "thermostat": Icons.thermostat,
    "timer": Icons.timer,
    "timer-outline": Icons.timer_outlined,
    "tumble-dryer": Icons.local_laundry_service,
    "washing-machine": Icons.local_laundry_service,
    "water": Icons.water_drop,
    "water-percent": Icons.water_drop,
    "weather-cloudy": Icons.cloud,
    "weather-night": Icons.nightlight,
    "weather-partly-cloudy": Icons.wb_cloudy,
    "weather-rainy": Icons.umbrella,
    "weather-snowy": Icons.ac_unit,
    "weather-sunny": Icons.wb_sunny,
    "wifi": Icons.wifi,
    "youtube": Icons.smart_display,
  };

  /// [icon] ("mdi:lightbulb") as a Material icon; without one it knows, the entity's usual icon.
  static IconData of(String? icon, {HaEntity? entity, String? entityId}) {
    if (icon != null) {
      final name = icon.startsWith("mdi:") ? icon.substring(4) : icon;
      final known = _mdi[name] ?? _mdi[name.replaceAll(RegExp(r"-(outline|variant)$"), "")];
      if (known != null) return known;
    }
    return forEntity(entity, entityId: entityId);
  }

  /// An entity's usual icon, by its domain, device class and state.
  static IconData forEntity(HaEntity? entity, {String? entityId}) {
    final id = entity?.entityId ?? entityId ?? "";
    final on = entity?.state == "on";
    switch (HaEntity.domainOf(id)) {
      case "light":
        return on ? Icons.lightbulb : Icons.lightbulb_outline;
      case "switch":
      case "input_boolean":
        return on ? Icons.toggle_on : Icons.toggle_off;
      case "fan":
        return Icons.mode_fan_off;
      case "climate":
        return Icons.thermostat;
      case "media_player":
        return entity?.state == "playing" ? Icons.speaker : Icons.speaker_outlined;
      case "person":
      case "device_tracker":
        return Icons.person;
      case "scene":
        return Icons.palette;
      case "script":
        return Icons.play_arrow;
      case "weather":
        return weather(entity?.state);
      case "calendar":
        return Icons.calendar_month;
      case "lock":
        return entity?.state == "unlocked" ? Icons.lock_open : Icons.lock;
      case "cover":
        return Icons.blinds;
      case "binary_sensor":
        return on ? Icons.radio_button_checked : Icons.radio_button_unchecked;
      case "sensor":
        switch (entity?.deviceClass) {
          case "temperature":
            return Icons.thermostat;
          case "humidity":
            return Icons.water_drop;
          case "battery":
            return Icons.battery_full;
          case "timestamp":
            return Icons.schedule;
          case "duration":
            return Icons.timer_outlined;
          case "power":
          case "energy":
            return Icons.flash_on;
        }
        return Icons.sensors;
      default:
        return Icons.circle_outlined;
    }
  }

  /// A thermostat's mode ("heat_cool").
  static IconData hvacMode(String mode) => switch (mode) {
        "heat" => Icons.local_fire_department,
        "cool" => Icons.ac_unit,
        "heat_cool" => Icons.thermostat_auto,
        "auto" => Icons.autorenew,
        "dry" => Icons.water_drop,
        "fan_only" => Icons.mode_fan_off,
        "off" => Icons.power_settings_new,
        _ => Icons.thermostat,
      };

  /// A weather condition ("partlycloudy").
  static IconData weather(String? condition) => switch (condition) {
        "sunny" => Icons.wb_sunny,
        "clear-night" => Icons.nightlight,
        "cloudy" => Icons.cloud,
        "partlycloudy" => Icons.wb_cloudy,
        "rainy" => Icons.umbrella,
        "pouring" => Icons.water_drop,
        "lightning" => Icons.flash_on,
        "lightning-rainy" => Icons.thunderstorm,
        "snowy" || "snowy-rainy" => Icons.ac_unit,
        "hail" => Icons.grain,
        "fog" => Icons.foggy,
        "windy" || "windy-variant" => Icons.air,
        _ => Icons.cloud_outlined,
      };
}
