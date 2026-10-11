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

/// One Home Assistant entity's state, as subscribe_entities sends it.
class HaEntity {
  final String entityId;
  final String state;
  final Map<String, Object?> attributes;
  final DateTime? lastChanged;
  final DateTime? lastUpdated;

  const HaEntity(this.entityId, this.state, {this.attributes = const {}, this.lastChanged, this.lastUpdated});

  /// "light" for "light.living_room".
  String get domain => domainOf(entityId);

  static String domainOf(String entityId) {
    final dot = entityId.indexOf(".");
    return dot < 0 ? entityId : entityId.substring(0, dot);
  }

  /// Its friendly name, else its id.
  String get name {
    final n = attributes["friendly_name"];
    return n is String && n.trim().isNotEmpty ? n.trim() : entityId;
  }

  String? get deviceClass => _string("device_class");

  String? get unit => _string("unit_of_measurement");

  String? _string(String key) {
    final v = attributes[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// A number attribute ("temperature"), or null.
  num? number(String key) {
    final v = attributes[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  int get supportedFeatures => number("supported_features")?.toInt() ?? 0;

  bool supports(int feature) => supportedFeatures & feature != 0;

  bool get unavailable => state == "unavailable" || state == "unknown";

  @override
  String toString() => "$entityId=$state";
}

/// Keeping entities up to date from subscribe_entities' messages: {"a": adds (the whole state), "c": changes ("+" what
/// is new, "-" attributes that went), "r": removes}. States are compressed: "s" state, "a" attributes, "lc" last
/// changed and "lu" last updated (seconds since 1970; "lu" left out when it's the same as "lc").
class HaEntityDiff {
  /// [entities] with [event] applied; the map given isn't changed.
  static Map<String, HaEntity> apply(Map<String, HaEntity> entities, Object? event) {
    if (event is! Map) return entities;
    final out = Map<String, HaEntity>.of(entities);
    final adds = event["a"];
    if (adds is Map) {
      adds.forEach((id, compressed) {
        if (id is! String || compressed is! Map) return;
        final lc = _time(compressed["lc"]);
        out[id] = HaEntity(
          id,
          _state(compressed["s"]),
          attributes: compressed["a"] is Map ? Map<String, Object?>.unmodifiable(compressed["a"] as Map) : const {},
          lastChanged: lc,
          lastUpdated: _time(compressed["lu"]) ?? lc,
        );
      });
    }
    final changes = event["c"];
    if (changes is Map) {
      changes.forEach((id, change) {
        if (id is! String || change is! Map) return;
        final old = out[id];
        if (old == null) return;
        final plus = change["+"] is Map ? change["+"] as Map : const {};
        final minus = change["-"] is Map ? change["-"] as Map : const {};
        final attributes = Map<String, Object?>.of(old.attributes);
        final removed = minus["a"];
        if (removed is List) {
          for (final key in removed) {
            attributes.remove(key);
          }
        }
        final added = plus["a"];
        if (added is Map) {
          added.forEach((key, value) {
            if (key is String) attributes[key] = value;
          });
        }
        final lc = _time(plus["lc"]);
        out[id] = HaEntity(
          id,
          plus.containsKey("s") ? _state(plus["s"]) : old.state,
          attributes: Map.unmodifiable(attributes),
          lastChanged: lc ?? old.lastChanged,
          lastUpdated: _time(plus["lu"]) ?? lc ?? old.lastUpdated,
        );
      });
    }
    final removes = event["r"];
    if (removes is List) {
      for (final id in removes) {
        out.remove(id);
      }
    }
    return out;
  }

  static String _state(Object? s) => s == null ? "unknown" : "$s";

  static DateTime? _time(Object? seconds) =>
      seconds is num ? DateTime.fromMicrosecondsSinceEpoch((seconds * 1000000).round(), isUtc: true).toLocal() : null;
}
