import 'package:flauncher/providers/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map _id(String value) => {"mainsnak": {"datavalue": {"value": value}}};
Map _time(String value) => {"mainsnak": {"datavalue": {"value": {"time": value}}}};
Map _item(String id) => {"mainsnak": {"datavalue": {"value": {"id": id}}}};

void main() {
  final hits = [
    {"id": "Q19798734", "label": "Stranger Things", "description": "American science fiction horror television series"},
    {"id": "Q39071378", "label": "Bluey", "description": "Australian animated preschool television series"},
    {"id": "Q19896225", "label": "Stranger Things", "description": "album by Marc Almond"},
  ];
  final entities = {
    "Q19798734": {
      "labels": {"en": {"value": "Stranger Things"}},
      "claims": {
        "P1874": [_id("80057281")],
        "P9751": [_id("umc.cmc.6a4s868u4ocy2a9zg6ochi2nd")],
        "P580": [_time("+2016-07-15T00:00:00Z")],
      },
    },
    "Q39071378": {
      "labels": {"en": {"value": "Bluey"}},
      "claims": {
        "P7596": [_id("1xy9TAOQ0M3r")],
        "P2671": [_id("/g/11g9dfjk4n")],
        "P4983": [_id("82728")],
        "P580": [_time("+2018-10-01T00:00:00Z")],
      },
    },
    "Q19896225": {"labels": {"en": {"value": "Stranger Things"}}, "claims": {}},
  };

  test("keeps films and shows, drops everything else", () {
    final results = SearchService.parseResults(hits, entities);
    expect(results.map((r) => r.wikidataId), ["Q19798734", "Q39071378"]);
  });

  test("never keeps an adult title (Wikidata's genre or class pornographic film)", () {
    final adultHits = [
      {"id": "Q1", "label": "A Parody"},
      {"id": "Q2", "label": "Another"},
      {"id": "Q3", "label": "A Comedy"},
    ];
    final adultEntities = {
      "Q1": {"labels": {"en": {"value": "A Parody"}}, "claims": {"P4947": [_id("1")], "P136": [_item("Q185529")]}},
      "Q2": {"labels": {"en": {"value": "Another"}}, "claims": {"P4947": [_id("2")], "P31": [_item("Q185529")]}},
      "Q3": {"labels": {"en": {"value": "A Comedy"}}, "claims": {"P4947": [_id("3")], "P136": [_item("Q157443")]}},
    };
    expect(SearchService.parseResults(adultHits, adultEntities).map((r) => r.wikidataId), ["Q3"]);
  });

  test("reads TMDB's adult mark", () {
    expect(TmdbClient.parseDetails({"adult": true}).adult, isTrue);
    expect(TmdbClient.parseDetails({"adult": false}).adult, isFalse);
    expect(TmdbClient.parseDetails({}).adult, isFalse);
  });

  test("builds each app's link and the year", () {
    final results = SearchService.parseResults(hits, entities);
    final stranger = results.first;
    expect(stranger.year, 2016);
    expect(stranger.offers.map((o) => o.service.name), ["Netflix", "Apple TV"]);
    expect(stranger.offers.first.link, "https://www.netflix.com/title/80057281");
    expect(stranger.offers.last.link, "https://tv.apple.com/show/umc.cmc.6a4s868u4ocy2a9zg6ochi2nd");
    expect(stranger.googleTvLink, isNull);
  });

  test("links Google TV's page by Knowledge Graph id", () {
    final bluey = SearchService.parseResults(hits, entities).last;
    expect(bluey.offers, isEmpty, reason: "Disney+ titles go through Google TV's page");
    expect(bluey.googleTvLink, "https://tv.google.com/asset/%2Fg%2F11g9dfjk4n");
  });

  test("searches once per query and caches it", () async {
    var calls = 0;
    final service = SearchService(getJson: (uri) async {
      calls++;
      return uri.queryParameters["action"] == "wbsearchentities" ? {"search": hits} : {"entities": entities};
    });
    expect((await service.search("stranger")).length, 2);
    expect((await service.search("Stranger ")).length, 2);
    expect(calls, 2);
    expect(await service.search("s"), isEmpty);
  });

  test("matches TMDB provider names to apps", () {
    final netflix = streamingServices.first;
    expect(netflix.matches("Netflix Standard with Ads"), isTrue);
    expect(netflix.matches("Hulu"), isFalse);
    final max = streamingServices.firstWhere((s) => s.name == "HBO Max");
    expect(max.matches("Max"), isTrue);
    expect(max.matches("Max Amazon Channel"), isTrue);
    expect(max.matches("MGM Plus"), isFalse);
  });

  group("TMDB", () {
    test("reads the poster and US streaming services", () {
      final details = TmdbClient.parseDetails({
        "poster_path": "/abc.jpg",
        "watch/providers": {
          "results": {
            "US": {
              "flatrate": [
                {"provider_name": "Disney Plus"},
                {"provider_name": "Hulu"}
              ]
            },
            "GB": {
              "flatrate": [
                {"provider_name": "BBC iPlayer"}
              ]
            }
          }
        }
      });
      expect(details.posterUrl, "https://image.tmdb.org/t/p/w185/abc.jpg");
      expect(details.streamingOn, ["Disney Plus", "Hulu"]);
    });

    test("splits what comes with a service from what's to rent or buy", () {
      final details = TmdbClient.parseDetails({
        "watch/providers": {
          "results": {
            "US": {
              "flatrate": [
                {"provider_name": "Netflix"}
              ],
              "ads": [
                {"provider_name": "Tubi TV"}
              ],
              "rent": [
                {"provider_name": "Google Play Movies"},
                {"provider_name": "Amazon Video"}
              ],
              "buy": [
                {"provider_name": "Google Play Movies"},
                {"provider_name": "Netflix"}
              ]
            }
          }
        }
      });
      expect(details.included, ["Netflix", "Tubi TV"]);
      // Netflix includes it, so it isn't also "to buy" there
      expect(details.rentOrBuy, ["Google Play Movies", "Amazon Video"]);
    });

    test("names TMDB's providers by their TV apps", () {
      expect(providerApp("Netflix Standard with Ads")?.packageName, "com.netflix.ninja");
      expect(providerApp("Max")?.name, "HBO Max");
      expect(providerApp("Maxdome"), isNull);
      expect(providerApp("Amazon Prime Video")?.name, "Prime Video");
      expect(providerApp("Google Play Movies")?.name, "Google TV");
      expect(providerApp("Crunchyroll"), isNull);
      // Not the YouTube app, and not the HBO Max app
      expect(providerApp("YouTube TV"), isNull);
      expect(providerApp("YouTube Free")?.name, "YouTube");
      expect(providerApp("HBO Max Amazon Channel"), isNull);
      expect(providerApp("Apple TV Store")?.name, "Apple TV");
    });

    test("puts what an installed app includes first, and keeps the rest quiet", () {
      const result = SearchResult(wikidataId: "Q1", title: "A Show");
      const details = TitleDetails(
        included: ["Netflix", "Hulu", "Crunchyroll"],
        rentOrBuy: ["Google Play Movies", "Amazon Video"],
      );
      bool installed(String pkg) => pkg == "com.netflix.ninja" || pkg == "com.google.android.videos";
      final availability = Availability.of(result, details, installed);
      expect(availability.watchable, isTrue);
      expect(availability.included.map((a) => a.name), ["Netflix"]);
      expect(availability.rentOrBuy.map((a) => a.name), ["Google TV"]); // Prime Video isn't installed
      expect(availability.elsewhere, ["Hulu", "Crunchyroll"]);

      final notHere = Availability.of(result, details, (_) => false);
      expect(notHere.watchable, isFalse);
      expect(notHere.elsewhere, ["Netflix", "Hulu", "Crunchyroll"]);
    });

    test("without TMDB, the installed apps Wikidata links count as included", () {
      final bluey = SearchService.parseResults(hits, entities).last;
      final linked = bluey.offers.map((o) => o.service.packageName).toSet();
      final availability = Availability.of(bluey, null, linked.contains);
      expect(availability.watchable, linked.any((pkg) => providerApps.any((a) => a.packageName == pkg)));
      expect(Availability.of(bluey, null, (_) => false).watchable, isFalse);
    });

    test("sends nothing without a key", () async {
      var calls = 0;
      final client = TmdbClient(apiKey: "", getJson: (_) async => calls++);
      final bluey = SearchService.parseResults(hits, entities).last;
      expect(bluey.tmdbId, "82728");
      expect(await client.details(bluey), isNull);
      expect(calls, 0);
    });

    test("asks for a show's details once", () async {
      final asked = <Uri>[];
      final client = TmdbClient(apiKey: "k", getJson: (uri) async {
        asked.add(uri);
        return {"poster_path": "/p.jpg"};
      });
      final bluey = SearchService.parseResults(hits, entities).last;
      await client.details(bluey);
      await client.details(bluey);
      expect(asked.single.path, "/3/tv/82728");
    });
  });
}