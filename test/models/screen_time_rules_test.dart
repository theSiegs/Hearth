import 'dart:convert';

import 'package:flauncher/models/screen_time_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("no rules is no limit and nothing to send", () {
    final rules = ScreenTimeRules.parse(null);
    expect(rules.minutes(ScreenTimeRules.all, weekend: false), isNull);
    expect(rules.bedtime, isNull);
    expect(rules.toJson(), isNull);
  });

  test("minutes per group and kind of day", () {
    final rules = ScreenTimeRules.parse(null)
        .withMinutes(ScreenTimeRules.all, 120, weekend: false, name: "All screen time")
        .withMinutes(ScreenTimeRules.games, 30, weekend: true, name: "Games");
    final json = jsonDecode(rules.toJson()!) as Map<String, dynamic>;
    expect(json["all"], {"weekday": 120});
    final games = (json["groups"] as List).single as Map;
    expect(games["id"], "games");
    expect(games["category"], "game");
    expect(games["weekend"], 30);
    expect(ScreenTimeRules.parse(rules.toJson()).minutes(ScreenTimeRules.games, weekend: true), 30);
    expect(ScreenTimeRules.parse(rules.toJson()).minutes(ScreenTimeRules.games, weekend: false), isNull);
  });

  test("a group with no limit left is taken out, and others are kept", () {
    final had = jsonEncode({
      "groups": [
        {"id": "music", "name": "Music", "weekday": 60, "apps": ["com.example.music"]},
        {"id": "youtube", "name": "YouTube", "weekday": 45, "apps": ScreenTimeRules.youtubeApps},
      ],
      "notCounted": ["com.example.school"],
    });
    final rules = ScreenTimeRules.parse(had).withMinutes(ScreenTimeRules.youtube, null, weekend: false, name: "YouTube");
    final json = jsonDecode(rules.toJson()!) as Map<String, dynamic>;
    expect((json["groups"] as List).map((g) => g["id"]), ["music"]);
    expect(json["notCounted"], ["com.example.school"]);
  });

  test("bedtime", () {
    final rules = ScreenTimeRules.parse(null)
        .withBedtime((from: "20:30", to: "07:00", nights: BedtimeNights.weekdays));
    expect(jsonDecode(rules.toJson()!)["bedtime"], {"from": "20:30", "to": "07:00", "days": "weekdays"});
    expect(ScreenTimeRules.parse(rules.toJson()).bedtime?.nights, BedtimeNights.weekdays);
    expect(rules.withBedtime(null).toJson(), isNull);
  });
}
