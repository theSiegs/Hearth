import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';

/// A streaming service a search result can open in.
class StreamingService {
  final String name;
  final String packageName;

  /// The Wikidata property holding this service's id for a film or show.
  final List<String> properties;

  /// Builds the link that opens the title in the app, from the property that had the id.
  final String Function(String property, String id) link;

  const StreamingService(this.name, this.packageName, this.properties, this.link);

  /// Whether a TMDB provider name ("Netflix Standard with Ads", "Apple TV+", "Max", "Paramount Plus") is this service.
  bool matches(String providerName) {
    final p = providerName.toLowerCase();
    return switch (packageName) {
      "com.netflix.ninja" => p.startsWith("netflix"),
      "com.apple.atve.androidtv.appletv" => p.startsWith("apple tv"),
      "com.wbd.stream" => p == "max" || p.startsWith("hbo max") || p.startsWith("max "),
      "com.cbs.ott" => p.startsWith("paramount"),
      "com.disney.disneyplus" => p.startsWith("disney"),
      _ => false,
    };
  }
}

const _netflix = StreamingService("Netflix", "com.netflix.ninja", ["P1874"], _netflixLink);
const _appleTv = StreamingService("Apple TV", "com.apple.atve.androidtv.appletv", ["P9586", "P9751"], _appleTvLink);
const _max = StreamingService("HBO Max", "com.wbd.stream", ["P8298"], _maxLink);
const _paramount = StreamingService("Paramount+", "com.cbs.ott", ["P13147"], _paramountLink);

/// Services in the order results list them.
// Disney+ isn't listed: the app no longer opens titles by the ids Wikidata has (tested October 2026; it showed the Series page),
// so Disney+ titles go through Google TV's page, whose Watch now uses Disney's current links.
const List<StreamingService> streamingServices = [_netflix, _appleTv, _max, _paramount];

String _netflixLink(String property, String id) => "https://www.netflix.com/title/$id";
String _appleTvLink(String property, String id) => "https://tv.apple.com/${property == "P9586" ? "movie" : "show"}/$id";
String _maxLink(String property, String id) => "https://play.max.com/$id";
String _paramountLink(String property, String id) => "https://www.paramountplus.com/shows/$id/";

const _googleKnowledgeGraph = "P2671";
const _tmdbMovie = "P4947";
const _tmdbShow = "P4983";

/// Where one result can be watched: a service and the link that opens the title in its app.
class SearchOffer {
  final StreamingService service;
  final String link;

  const SearchOffer(this.service, this.link);
}

/// A film or show found in Wikidata.
class SearchResult {
  final String wikidataId;
  final String title;
  final String? description;
  final int? year;

  /// Google's Knowledge Graph id ("/g/11g9dfjk4n"), which opens Google TV's page for the title.
  final String? googleId;
  final List<SearchOffer> offers;

  /// The Movie Database id, for the poster and where it's streaming; [tmdbIsMovie] says which kind of id.
  final String? tmdbId;
  final bool tmdbIsMovie;

  const SearchResult({
    required this.wikidataId,
    required this.title,
    this.description,
    this.year,
    this.googleId,
    this.offers = const [],
    this.tmdbId,
    this.tmdbIsMovie = false,
  });

  /// Google TV's page for this title, when Wikidata knows its Google id.
  String? get googleTvLink => googleId == null ? null : "https://tv.google.com/asset/${Uri.encodeComponent(googleId!)}";
}

/// Searches films and shows in Wikidata (open data, no account or key) and says which streaming apps have them.
/// Only the search text goes to Wikidata; results are cached for the session.
class SearchService {
  static const _api = "https://www.wikidata.org/w/api.php";
  static const _userAgent = "Hearth/1.0 (https://github.com/theSiegs/Hearth)";

  final Future<dynamic> Function(Uri uri) _getJson;
  final Map<String, List<SearchResult>> _cache = {};

  SearchService({Future<dynamic> Function(Uri uri)? getJson}) : _getJson = getJson ?? _httpGetJson;

  Future<List<SearchResult>> search(String query) async {
    final text = query.trim();
    if (text.length < 2) return [];
    final cached = _cache[text.toLowerCase()];
    if (cached != null) return cached;

    final found = await _getJson(Uri.parse(_api).replace(queryParameters: {
      "action": "wbsearchentities",
      "search": text,
      "type": "item",
      "language": "en",
      "uselang": "en",
      "limit": "20",
      "format": "json",
    }));
    final hits = ((found as Map)["search"] as List? ?? []).cast<Map>();
    if (hits.isEmpty) return _cache[text.toLowerCase()] = [];

    final details = await _getJson(Uri.parse(_api).replace(queryParameters: {
      "action": "wbgetentities",
      "ids": hits.map((h) => h["id"]).join("|"),
      "props": "claims|labels|descriptions",
      "languages": "en",
      "format": "json",
    }));
    final results = parseResults(hits, (details as Map)["entities"] as Map? ?? {});
    return _cache[text.toLowerCase()] = results;
  }

  /// Keeps the hits that are films or shows (they have a streaming or TMDB id), in search order.
  static List<SearchResult> parseResults(List<Map> hits, Map entities) {
    final results = <SearchResult>[];
    for (final hit in hits) {
      final entity = entities[hit["id"]];
      if (entity is! Map) continue;
      final claims = (entity["claims"] as Map?) ?? {};
      final offers = <SearchOffer>[];
      for (final service in streamingServices) {
        for (final property in service.properties) {
          final id = _firstString(claims, property);
          if (id != null) {
            offers.add(SearchOffer(service, service.link(property, id)));
            break;
          }
        }
      }
      final isTitle = offers.isNotEmpty || claims.containsKey(_tmdbMovie) || claims.containsKey(_tmdbShow);
      if (!isTitle) continue;
      results.add(SearchResult(
        wikidataId: hit["id"] as String,
        title: (_at(entity, ["labels", "en", "value"]) ?? hit["label"] ?? "") as String,
        description: (_at(entity, ["descriptions", "en", "value"]) ?? hit["description"]) as String?,
        year: _year(claims, "P577") ?? _year(claims, "P580"),
        googleId: _firstString(claims, _googleKnowledgeGraph),
        offers: offers,
        tmdbId: _firstString(claims, _tmdbMovie) ?? _firstString(claims, _tmdbShow),
        tmdbIsMovie: _firstString(claims, _tmdbMovie) != null,
      ));
    }
    return results;
  }

  /// Follows map keys, or null when any step is missing.
  static dynamic _at(dynamic value, List<String> keys) {
    for (final key in keys) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value;
  }

  static String? _firstString(Map claims, String property) {
    final list = claims[property];
    if (list is! List) return null;
    for (final claim in list) {
      final value = _at(claim, ["mainsnak", "datavalue", "value"]);
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  static int? _year(Map claims, String property) {
    final list = claims[property];
    if (list is! List) return null;
    int? earliest;
    for (final claim in list) {
      final time = _at(claim, ["mainsnak", "datavalue", "value", "time"]);
      if (time is String) {
        final year = int.tryParse(RegExp(r"^[+-]?(\d{4})").firstMatch(time)?.group(1) ?? "");
        if (year != null && (earliest == null || year < earliest)) earliest = year;
      }
    }
    return earliest;
  }

  static Future<dynamic> _httpGetJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw HttpException("HTTP ${response.statusCode}", uri: uri);
      return jsonDecode(await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }
}

/// A title's poster and where it can be watched in the US, from The Movie Database (TMDB; the data is JustWatch's).
class TitleDetails {
  final String? posterUrl;

  /// A wide still (16:9), for cards shaped like Continue Watching's.
  final String? backdropUrl;

  /// Services where it comes with the service: by subscription, free, or free with ads, as TMDB names them.
  final List<String> included;

  /// Stores where it can be rented or bought (and isn't also included there).
  final List<String> rentOrBuy;

  const TitleDetails({this.posterUrl, this.backdropUrl, this.included = const [], this.rentOrBuy = const []});

  /// Included services (the name older code used: "streaming on").
  List<String> get streamingOn => included;
}

/// A TV app that TMDB lists titles for, by its TMDB provider names.
class ProviderApp {
  final String name;
  final String packageName;

  /// Lower-case TMDB provider names, or their beginnings ("netflix" covers "Netflix Standard with Ads").
  final List<String> prefixes;

  /// Lower-case names that begin like this app's but are something else ("youtube tv" is the cable service).
  final List<String> except;

  const ProviderApp(this.name, this.packageName, this.prefixes, {this.except = const []});

  bool matches(String providerName) {
    final p = providerName.toLowerCase();
    if (except.any((e) => p == e || p.startsWith("$e "))) return false;
    return prefixes.any((prefix) => p == prefix || p.startsWith("$prefix "));
  }
}

/// The apps Hearth can tell are on the TV, for TMDB's providers. Providers not here count as apps that aren't.
const List<ProviderApp> providerApps = [
  ProviderApp("Netflix", "com.netflix.ninja", ["netflix"]),
  ProviderApp("Disney+", "com.disney.disneyplus", ["disney plus", "disney+"]),
  ProviderApp("Apple TV", "com.apple.atve.androidtv.appletv", ["apple tv", "apple tv+", "apple tv plus"]),
  ProviderApp("HBO Max", "com.wbd.stream", ["max", "hbo max"]),
  ProviderApp("Paramount+", "com.cbs.ott", ["paramount plus", "paramount+"]),
  ProviderApp("Hulu", "com.hulu.livingroomplus", ["hulu"]),
  ProviderApp("Prime Video", "com.amazon.amazonvideo.livingroom", ["amazon prime video", "amazon video", "prime video"]),
  ProviderApp("Peacock", "com.peacocktv.peacockandroid", ["peacock", "peacock premium", "peacock premium plus"]),
  ProviderApp("Tubi", "com.tubitv", ["tubi tv", "tubi"]),
  ProviderApp("Pluto TV", "tv.pluto.android", ["pluto tv"]),
  ProviderApp("YouTube", "com.google.android.youtube.tv", ["youtube"], except: ["youtube tv"]),
  ProviderApp("Google TV", "com.google.android.videos", ["google play movies", "google tv"]),
];

/// Add-on channels sold through another service ("HBO Max Amazon Channel" is bought in Prime Video, not the
/// HBO Max app): their own subscription, so never the app they're named after.
final RegExp _addOnChannel = RegExp(r" (amazon|apple tv|roku premium) channel$", caseSensitive: false);

/// The app for a TMDB provider name, or null when Hearth doesn't know one.
ProviderApp? providerApp(String providerName) => _addOnChannel.hasMatch(providerName)
    ? null
    : providerApps.firstWhereOrNull((app) => app.matches(providerName));

/// How a title can be watched on this TV: what search shows up front (included with an installed app), and what it
/// keeps quiet (rent or buy, or only on apps that aren't installed).
class Availability {
  /// Installed apps it comes with (subscription, free or with ads), best first.
  final List<ProviderApp> included;

  /// Installed stores that rent or sell it.
  final List<ProviderApp> rentOrBuy;

  /// Services it comes with that aren't on this TV, by name.
  final List<String> elsewhere;

  /// Whether TMDB knew where it's watchable at all.
  final bool known;

  const Availability({this.included = const [], this.rentOrBuy = const [], this.elsewhere = const [], this.known = false});

  /// Up front in the results: it can be watched now at no extra cost.
  bool get watchable => included.isNotEmpty;

  /// Sorts out where [result] can be watched, with TMDB's [details] when there are any. Without them, the installed
  /// apps Wikidata links the title to count as included (so search still works without a TMDB key).
  static Availability of(SearchResult result, TitleDetails? details, bool Function(String packageName) installed) {
    List<ProviderApp> installedApps(Iterable<String> names) {
      final apps = <ProviderApp>[];
      for (final name in names) {
        final app = providerApp(name);
        if (app != null && installed(app.packageName) && !apps.contains(app)) apps.add(app);
      }
      return apps;
    }

    if (details == null || (details.included.isEmpty && details.rentOrBuy.isEmpty)) {
      final linked = <ProviderApp>[];
      for (final offer in result.offers) {
        final app = providerApps.firstWhereOrNull((a) => a.packageName == offer.service.packageName);
        if (app != null && installed(app.packageName) && !linked.contains(app)) linked.add(app);
      }
      return Availability(included: linked);
    }
    final included = installedApps(details.included);
    final elsewhere = <String>[];
    for (final name in details.included) {
      final app = providerApp(name);
      final label = app?.name ?? name;
      if ((app == null || !installed(app.packageName)) && !elsewhere.contains(label)) elsewhere.add(label);
    }
    return Availability(
      included: included,
      rentOrBuy: installedApps(details.rentOrBuy).where((app) => !included.contains(app)).toList(),
      elsewhere: elsewhere,
      known: true,
    );
  }
}

/// Looks titles up in TMDB by the id Wikidata gives. Needs an API key built in with
/// `--dart-define=TMDB_API_KEY=...`; without one, [enabled] is false and nothing is sent.
class TmdbClient {
  static const String _key = String.fromEnvironment("TMDB_API_KEY");

  final String _apiKey;
  final Future<dynamic> Function(Uri uri) _getJson;
  final Map<String, Future<TitleDetails?>> _cache = {};

  TmdbClient({String? apiKey, Future<dynamic> Function(Uri uri)? getJson})
      : _apiKey = apiKey ?? _key,
        _getJson = getJson ?? SearchService._httpGetJson;

  bool get enabled => _apiKey.isNotEmpty;

  Future<TitleDetails?> details(SearchResult result) {
    final id = result.tmdbId;
    if (!enabled || id == null) return Future.value(null);
    final kind = result.tmdbIsMovie ? "movie" : "tv";
    return _cache["$kind/$id"] ??= _fetch(kind, id);
  }

  Future<TitleDetails?> _fetch(String kind, String id) async {
    try {
      final json = await _getJson(Uri.https("api.themoviedb.org", "/3/$kind/$id", {
        "api_key": _apiKey,
        "append_to_response": "watch/providers",
      }));
      return parseDetails(json as Map);
    } catch (_) {
      return null;
    }
  }

  static TitleDetails parseDetails(Map json) {
    final poster = json["poster_path"];
    final backdrop = json["backdrop_path"];
    List<String> names(String kind) {
      final list = SearchService._at(json, ["watch/providers", "results", "US", kind]);
      return list is List ? list.map((p) => p is Map ? p["provider_name"] : null).whereType<String>().toList() : [];
    }

    final included = <String>{...names("flatrate"), ...names("free"), ...names("ads")}.toList();
    final rentOrBuy = <String>{...names("rent"), ...names("buy")}.where((n) => !included.contains(n)).toList();
    return TitleDetails(
      posterUrl: poster is String ? "https://image.tmdb.org/t/p/w185$poster" : null,
      backdropUrl: backdrop is String ? "https://image.tmdb.org/t/p/w500$backdrop" : null,
      included: included,
      rentOrBuy: rentOrBuy,
    );
  }
}

/// One search result as Hearth shows it: the title, TMDB's details (null without a key or an answer), and where it
/// can be watched on this TV.
class TitleMatch {
  final SearchResult result;
  final TitleDetails? details;
  final Availability availability;

  const TitleMatch(this.result, this.details, this.availability);

  /// The best picture for a wide card: TMDB's still, else its poster.
  String? get imageUrl => details?.backdropUrl ?? details?.posterUrl;
}
