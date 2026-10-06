import 'dart:convert';
import 'dart:io';

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
const _disney = StreamingService("Disney+", "com.disney.disneyplus", ["P7595", "P7596"], _disneyLink);
const _appleTv = StreamingService("Apple TV", "com.apple.atve.androidtv.appletv", ["P9586", "P9751"], _appleTvLink);
const _max = StreamingService("HBO Max", "com.wbd.stream", ["P8298"], _maxLink);
const _paramount = StreamingService("Paramount+", "com.cbs.ott", ["P13147"], _paramountLink);

/// Services in the order results list them.
// Disney+ isn't listed: the app no longer opens titles by the ids Wikidata has (tested October 2026; it showed the Series page),
// so Disney+ titles go through Google TV's page, whose Watch now uses Disney's current links.
const List<StreamingService> streamingServices = [_netflix, _appleTv, _max, _paramount];

String _netflixLink(String property, String id) => "https://www.netflix.com/title/$id";
String _disneyLink(String property, String id) =>
    "https://www.disneyplus.com/${property == "P7595" ? "movies" : "series"}/x/$id";
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

/// A title's poster and the services streaming it in the US, from The Movie Database (TMDB).
class TitleDetails {
  final String? posterUrl;

  /// Subscription services streaming it in the US, as TMDB names them (data from JustWatch).
  final List<String> streamingOn;

  const TitleDetails({this.posterUrl, this.streamingOn = const []});
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
    final us = SearchService._at(json, ["watch/providers", "results", "US", "flatrate"]);
    return TitleDetails(
      posterUrl: poster is String ? "https://image.tmdb.org/t/p/w185$poster" : null,
      streamingOn: us is List ? us.map((p) => p is Map ? p["provider_name"] : null).whereType<String>().toList() : [],
    );
  }
}
