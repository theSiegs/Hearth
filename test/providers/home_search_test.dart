import 'dart:async';

import 'package:flauncher/providers/home_search.dart';
import 'package:flauncher/providers/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers each search only when the test says so, so searches can finish out of order.
class _ManualSearch extends SearchService {
  final Map<String, Completer<List<SearchResult>>> pending = {};

  @override
  Future<List<SearchResult>> search(String query) => (pending[query] = Completer()).future;
}

SearchResult _title(String id, String title, {String? netflixId}) => SearchResult(
      wikidataId: id,
      title: title,
      offers: [
        if (netflixId != null) SearchOffer(streamingServices.first, "https://www.netflix.com/title/$netflixId"),
      ],
    );

void main() {
  late _ManualSearch service;
  late HomeSearch search;

  setUp(() {
    service = _ManualSearch();
    search = HomeSearch(service: service, installed: (pkg) => pkg == "com.netflix.ninja");
  });

  test("a new search's results replace the last one's entirely", () async {
    final first = search.search("bluey");
    service.pending["bluey"]!.complete([_title("Q1", "Bluey", netflixId: "1")]);
    await first;
    expect(search.matches.map((m) => m.result.title), ["Bluey"]);

    final second = search.search("the bear");
    // While the new search runs, nothing from the last one shows
    expect(search.matches, isEmpty);
    expect(search.query, "the bear");
    service.pending["the bear"]!.complete([_title("Q2", "The Bear", netflixId: "2")]);
    await second;
    expect(search.matches.map((m) => m.result.title), ["The Bear"]);
  });

  test("an older search that answers late is dropped", () async {
    final slow = search.search("bluey");
    final fast = search.search("the bear");
    service.pending["the bear"]!.complete([_title("Q2", "The Bear", netflixId: "2")]);
    await fast;
    service.pending["bluey"]!.complete([_title("Q1", "Bluey", netflixId: "1")]);
    await slow;
    expect(search.query, "the bear");
    expect(search.matches.map((m) => m.result.title), ["The Bear"]);
  });

  test("clearing ends the search, and a late answer doesn't bring it back", () async {
    final running = search.search("bluey");
    search.clear();
    service.pending["bluey"]!.complete([_title("Q1", "Bluey", netflixId: "1")]);
    await running;
    expect(search.active, isFalse);
    expect(search.matches, isEmpty);
  });

  test("groups titles by how they can be watched here", () async {
    final running = search.search("bears");
    service.pending["bears"]!.complete([
      _title("Q1", "On Netflix", netflixId: "1"),
      _title("Q2", "Nowhere here"),
    ]);
    await running;
    expect(search.watchNow.map((m) => m.result.title), ["On Netflix"]);
    expect(search.rentOrBuy, isEmpty);
    expect(search.otherApps.map((m) => m.result.title), ["Nowhere here"]);
  });
}
