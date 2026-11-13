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

/// Which nights a bedtime holds, named by the morning it ends on (as the TV reads it, LocalRules.java).
enum BedtimeNights { all, weekdays, weekends }

/// A kid's own screen-time rules, for a TV without Home Assistant (docs/tv-remote-api.md, Version 2, `rules`): All
/// screen time, Games and YouTube, each with minutes on weekdays and weekends (null: no limit), and a bedtime. What the
/// editor doesn't show (other groups, apps not counted) is kept as it was.
class ScreenTimeRules {
  static const String all = "all";
  static const String games = "games";
  static const String youtube = "youtube";

  /// The apps the YouTube group holds: YouTube and HearthTube, on the TV and on phones.
  static const List<String> youtubeApps = [
    "com.thesiegs.hearthtube",
    "com.thesiegs.hearthtube.mobile",
    "com.google.android.youtube.tv",
    "com.google.android.youtube",
  ];

  final Map<String, dynamic> _json;

  ScreenTimeRules._(this._json);

  factory ScreenTimeRules.parse(String? json) {
    if (json == null || json.isEmpty) return ScreenTimeRules._({});
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return ScreenTimeRules._(decoded);
    } catch (_) {}
    return ScreenTimeRules._({});
  }

  /// Minutes a day for [group] ([all], [games] or [youtube]); null: no limit.
  int? minutes(String group, {required bool weekend}) {
    final rule = _rule(group);
    final value = rule?[weekend ? "weekend" : "weekday"];
    return value is num ? value.toInt() : null;
  }

  /// Sets [group]'s minutes ([name] is what the kid is told when its time is up). A group with no limit on either
  /// kind of day is taken out.
  ScreenTimeRules withMinutes(String group, int? minutes, {required bool weekend, required String name}) {
    final json = _copy();
    final key = weekend ? "weekend" : "weekday";
    if (group == all) {
      final rule = Map<String, dynamic>.from((json["all"] as Map?) ?? {});
      rule[key] = minutes;
      json["all"] = rule;
      if (rule["weekday"] == null && rule["weekend"] == null) json.remove("all");
      return ScreenTimeRules._(json);
    }
    final groups = [
      for (final g in (json["groups"] as List?) ?? [])
        if (g is Map) Map<String, dynamic>.from(g)
    ];
    var rule = groups.where((g) => g["id"] == group).firstOrNull;
    if (rule == null) {
      rule = {"id": group, "name": name, "apps": group == youtube ? youtubeApps : <String>[]};
      if (group == games) rule["category"] = "game";
      groups.add(rule);
    }
    rule["name"] = name;
    rule[key] = minutes;
    if (rule["weekday"] == null && rule["weekend"] == null) groups.remove(rule);
    json["groups"] = groups;
    if (groups.isEmpty) json.remove("groups");
    return ScreenTimeRules._(json);
  }

  /// Bedtime's start and end ("20:30", "07:00"), and its nights; null when there is none.
  ({String from, String to, BedtimeNights nights})? get bedtime {
    final b = _json["bedtime"];
    if (b is! Map || b["from"] is! String || b["to"] is! String) return null;
    final nights = BedtimeNights.values.where((n) => n.name == b["days"]).firstOrNull ?? BedtimeNights.all;
    return (from: b["from"] as String, to: b["to"] as String, nights: nights);
  }

  ScreenTimeRules withBedtime(({String from, String to, BedtimeNights nights})? bedtime) {
    final json = _copy();
    if (bedtime == null) {
      json.remove("bedtime");
    } else {
      json["bedtime"] = {"from": bedtime.from, "to": bedtime.to, "days": bedtime.nights.name};
    }
    return ScreenTimeRules._(json);
  }

  /// No limits and no bedtime: nothing for the TV to hold.
  bool get isEmpty =>
      _json["all"] == null && ((_json["groups"] as List?) ?? []).isEmpty && _json["bedtime"] == null;

  /// The rules for the TV; null when there are none.
  String? toJson() => isEmpty ? null : jsonEncode(_json);

  Map<String, dynamic>? _rule(String group) {
    if (group == all) return (_json["all"] as Map?)?.cast<String, dynamic>();
    for (final g in (_json["groups"] as List?) ?? []) {
      if (g is Map && g["id"] == group) return g.cast<String, dynamic>();
    }
    return null;
  }

  Map<String, dynamic> _copy() => jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
}
