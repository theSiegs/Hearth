import 'package:flauncher/providers/poster_lookup.dart';
import 'package:flauncher/providers/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late List<Uri> asked;
  late Map<String, Map<String, Object>> entities;
  late Map<String, Map<String, Object>> tmdb;
  var offline = false;
  var now = DateTime(2026, 10, 1);

  Map<String, Object> claim(String value) => {
        "mainsnak": {
          "datavalue": {"value": value}
        }
      };

  Future<dynamic> getJson(Uri uri) async {
    asked.add(uri);
    if (offline) throw Exception("offline");
    if (uri.host == "api.themoviedb.org") return tmdb[uri.path] ?? (throw Exception("404"));
    if (uri.queryParameters["action"] == "wbsearchentities") {
      return {
        "search": [
          for (final id in entities.keys) {"id": id, "label": entities[id]!["label"]}
        ]
      };
    }
    return {
      "entities": {
        for (final id in entities.keys)
          id: {
            "labels": {
              "en": {"value": entities[id]!["label"]}
            },
            "claims": {
              "P4983": [claim(entities[id]!["tmdb"] as String)]
            },
          }
      }
    };
  }

  PosterLookup lookup() => PosterLookup(SearchService(getJson: getJson), TmdbClient(apiKey: "k", getJson: getJson), prefs,
      clock: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    asked = [];
    offline = false;
    now = DateTime(2026, 10, 1);
    entities = {
      "Q1": {"label": "Bluey Movie Night", "tmdb": "9"},
      "Q2": {"label": "Bluey", "tmdb": "82728"},
    };
    tmdb = {
      "/3/tv/82728": {"backdrop_path": "/still.jpg", "poster_path": "/poster.jpg"},
      "/3/tv/9": {"backdrop_path": "/other.jpg"},
    };
  });

  test("finds the still of the title that matches exactly", () async {
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey!"), "https://image.tmdb.org/t/p/w500/still.jpg");
  });

  test("no exact match, no picture", () async {
    entities.remove("Q2");
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNull);
  });

  test("never a title TMDB marks adult", () async {
    tmdb["/3/tv/82728"] = {"backdrop_path": "/still.jpg", "adult": true};
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNull);
  });

  test("videos from YouTube and HearthTube aren't looked up", () async {
    expect(await lookup().imageFor("com.thesiegs.hearthtube", "Bluey"), isNull);
    expect(await lookup().imageFor("com.google.android.youtube.tv", "Bluey"), isNull);
    expect(asked, isEmpty);
  });

  test("without a TMDB key nothing is sent", () async {
    final off = PosterLookup(SearchService(getJson: getJson), TmdbClient(apiKey: "", getJson: getJson), prefs);
    expect(await off.imageFor("com.disney.disneyplus", "Bluey"), isNull);
    expect(asked, isEmpty);
  });

  test("an answer is kept, so the title isn't sent again", () async {
    await lookup().imageFor("com.disney.disneyplus", "Bluey");
    asked.clear();
    expect(await lookup().imageFor("com.netflix.ninja", "bluey"), "https://image.tmdb.org/t/p/w500/still.jpg");
    expect(asked, isEmpty);
  });

  test("a miss is kept for a week, then tried again", () async {
    entities.remove("Q2");
    await lookup().imageFor("com.disney.disneyplus", "Bluey");
    entities["Q2"] = {"label": "Bluey", "tmdb": "82728"};
    asked.clear();
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNull);
    expect(asked, isEmpty);
    now = now.add(const Duration(days: 8));
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNotNull);
  });

  test("offline isn't kept as a miss", () async {
    offline = true;
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNull);
    offline = false;
    expect(await lookup().imageFor("com.disney.disneyplus", "Bluey"), isNotNull);
  });
}
