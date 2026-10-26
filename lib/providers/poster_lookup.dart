import 'dart:convert';

import 'package:flauncher/quiet_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_service.dart';

/// Finds a picture for a Continue Watching card that has none Hearth can read (the app gave none, it's inside a kids
/// profile Hearth can't open, or it came from another TV without its poster): the title's still from TMDB, found
/// through Wikidata the way search finds titles. Only an exact title match counts, and never one TMDB marks adult,
/// so a card gets no picture rather than another title's. Answers are kept on the TV (misses retried after a week),
/// so each title goes to Wikidata and TMDB at most once.
class PosterLookup {
  static const _prefsKey = "watch_next_poster_lookup";
  static const _keep = 300;
  static const Duration retryMiss = Duration(days: 7);

  /// Apps whose cards are videos, not films or shows: a title match there would be by chance.
  static const Set<String> _skipApps = {"com.google.android.youtube.tv", "com.thesiegs.hearthtube"};

  final SearchService _search;
  final TmdbClient _tmdb;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final Map<String, Future<String?>> _running = {};

  PosterLookup(this._search, this._tmdb, this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  bool get enabled => _tmdb.enabled;

  /// Whether a card from [packageName] titled [title] can be looked up at all.
  bool canLookUp(String packageName, String title) =>
      enabled && !_skipApps.contains(packageName) && _normalize(title).length >= 2;

  /// The picture's web address for [title], or null when there's no sure match.
  Future<String?> imageFor(String packageName, String title) {
    if (!canLookUp(packageName, title)) return Future.value(null);
    final key = _normalize(title);
    // A block, not an arrow: remove() returns this future, and whenComplete would then wait on itself
    return _running[key] ??= _lookUp(key, title).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<String?> _lookUp(String key, String title) async {
    final known = _known();
    final kept = known[key];
    if (kept is Map) {
      final url = kept["u"];
      final at = (kept["t"] as num?)?.toInt() ?? 0;
      if (url is String && url.isNotEmpty) return url;
      if (_clock().millisecondsSinceEpoch - at < retryMiss.inMilliseconds) return null;
    }
    String? url;
    // TMDB didn't answer for a match (offline, or busy): not kept as a miss, so it's tried again next time
    var unanswered = false;
    try {
      for (final result in await _search.search(title)) {
        if (_normalize(result.title) != key || result.tmdbId == null) continue;
        final details = await _tmdb.details(result);
        if (details == null) unanswered = true;
        if (details == null || details.adult) continue;
        url = details.backdropUrl ?? details.posterUrl;
        if (url != null) break;
      }
    } catch (err) {
      noteFailure('poster_lookup', err);
      return null;
    }
    if (url == null && unanswered) return null;
    _remember(key, url);
    return url;
  }

  Map<String, dynamic> _known() {
    try {
      final raw = _prefs.getString(_prefsKey);
      return raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  void _remember(String key, String? url) {
    final known = _known()..[key] = {"u": url ?? "", "t": _clock().millisecondsSinceEpoch};
    if (known.length > _keep) {
      final oldest = known.entries.toList()
        ..sort((a, b) => (((a.value as Map?)?["t"] as num?) ?? 0).compareTo(((b.value as Map?)?["t"] as num?) ?? 0));
      for (final e in oldest.take(known.length - _keep)) {
        known.remove(e.key);
      }
    }
    _prefs.setString(_prefsKey, jsonEncode(known));
  }

  /// Lower case, letters and digits only, single spaces: "Bluey!" and "bluey" are the same title.
  static String _normalize(String title) =>
      title.toLowerCase().replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), " ").trim();
}
