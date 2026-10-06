import 'package:flauncher/providers/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map _id(String value) => {"mainsnak": {"datavalue": {"value": value}}};
Map _time(String value) => {"mainsnak": {"datavalue": {"value": {"time": value}}}};

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
    expect(bluey.offers.single.link, "https://www.disneyplus.com/series/x/1xy9TAOQ0M3r");
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
}
