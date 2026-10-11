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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/ha_entities.dart';

/// How a tile shows an entity's state: the way Home Assistant's own tiles do, in the TV's language where Home
/// Assistant has the words.
class HaFormat {
  final AppLocalizations l;

  /// Home Assistant's names of states ("component.person.entity_component._.state.not_home" → "Away").
  final String? Function(String key) translate;
  final DateTime now;

  /// Home Assistant's temperature unit ("°F"), for thermostats, which don't say theirs.
  final String? temperatureUnit;

  const HaFormat(this.l, this.translate, this.now, {this.temperatureUnit});

  /// The tile's state line: [stateContent]'s parts ("media_title", "state", ...) joined, or the state alone.
  String tileState(HaEntity? entity, List<String> stateContent) {
    if (entity == null) return "—";
    if (stateContent.isEmpty) return state(entity);
    final parts = <String>[];
    for (final part in stateContent) {
      final text = switch (part) {
        "state" => state(entity),
        "last_changed" => entity.lastChanged == null ? null : relative(entity.lastChanged!),
        "last_updated" => entity.lastUpdated == null ? null : relative(entity.lastUpdated!),
        _ => _attribute(entity.attributes[part]),
      };
      if (text != null && text.isNotEmpty) parts.add(text);
    }
    return parts.isEmpty ? state(entity) : parts.join(" · ");
  }

  /// The entity's state, as its tile shows it alone.
  String state(HaEntity entity) {
    if (entity.unavailable) return stateName(entity) ?? "—";
    switch (entity.domain) {
      case "sensor":
        if (entity.deviceClass == "timestamp") {
          final at = DateTime.tryParse(entity.state);
          if (at != null) return relative(at.toLocal());
        }
        return number(entity.state, entity.unit);
      case "input_number":
      case "number":
        return number(entity.state, entity.unit);
      case "climate":
        final current = entity.number("current_temperature");
        final mode = stateName(entity) ?? entity.state;
        return current == null ? mode : "$mode · ${number("$current", _temperatureUnit(entity))}";
      case "light":
        final brightness = entity.number("brightness");
        final name = stateName(entity) ?? entity.state;
        return entity.state == "on" && brightness != null ? "$name · ${(brightness / 2.55).round()}%" : name;
      case "weather":
        final temperature = entity.number("temperature");
        final condition = stateName(entity) ?? _humanize(entity.state);
        return temperature == null
            ? condition
            : "$condition · ${number("$temperature", entity.attributes["temperature_unit"] as String?)}";
    }
    return stateName(entity) ?? _humanize(entity.state);
  }

  /// Home Assistant's name for the entity's state ("Away", "Playing"), else null (a zone's name, a number).
  String? stateName(HaEntity entity) {
    final domain = entity.domain;
    final deviceClass = entity.deviceClass;
    final s = entity.state;
    if (deviceClass != null) {
      final own = translate("component.$domain.entity_component.$deviceClass.state.$s");
      if (own != null) return own;
    }
    final known = translate("component.$domain.entity_component._.state.$s");
    if (known != null) return known;
    if (s == "unavailable" || s == "unknown") return "—";
    // Without Home Assistant's words, the usual ones read well enough
    switch (s) {
      case "not_home":
        return "Away";
      case "home":
        return "Home";
    }
    if (domain == "person" || domain == "device_tracker") return s;
    return null;
  }

  /// A number with its unit ("21.5 °C", "40%"); long fractions are cut short.
  static String number(String value, String? unit) {
    final n = num.tryParse(value);
    var text = value;
    if (n != null) {
      final fraction = value.contains(".") ? value.split(".").last.length : 0;
      text = fraction > 2 ? n.toStringAsFixed(1) : value;
    }
    if (unit == null || unit.isEmpty) return text;
    return unit == "%" ? "$text%" : "$text $unit";
  }

  String? _temperatureUnit(HaEntity entity) {
    final unit = entity.attributes["temperature_unit"];
    return unit is String ? unit : temperatureUnit;
  }

  /// How far [at] is from now: "in 40 min", "2 h 5 min ago", "now".
  String relative(DateTime at) {
    final diff = at.difference(now);
    final minutes = (diff.inSeconds.abs() / 60).round();
    if (minutes < 1) return l.haTimeNow;
    final span = this.span(Duration(minutes: minutes));
    return diff.isNegative ? l.haTimeAgo(span) : l.haTimeIn(span);
  }

  /// "40 min", "2 h 5 min", "3 d".
  String span(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 60) return l.haSpanMinutes(minutes);
    if (minutes < 24 * 60) {
      final rest = minutes % 60;
      return rest == 0 ? l.haSpanHours(minutes ~/ 60) : "${l.haSpanHours(minutes ~/ 60)} ${l.haSpanMinutes(rest)}";
    }
    return l.haSpanDays((minutes / (24 * 60)).round());
  }

  static String? _attribute(Object? value) {
    if (value == null) return null;
    if (value is List) return value.join(", ");
    return "$value";
  }

  /// "heat_cool" → "Heat cool".
  static String _humanize(String s) {
    final words = s.replaceAll("_", " ").trim();
    if (words.isEmpty) return s;
    return words[0].toUpperCase() + words.substring(1);
  }
}
