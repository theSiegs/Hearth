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

import 'package:flutter/foundation.dart';

import 'search_service.dart';

/// The home's search: what was asked, and the titles found, grouped by how they can be watched on this TV. The top
/// bar, the results row (in Continue Watching's spot) and the "more results" grid all show it.
class HomeSearch extends ChangeNotifier {
  final SearchService _service;

  /// TMDB, for where titles are watchable; null without a key (titles then group by the apps Wikidata links).
  final TmdbClient? Function() _tmdb;

  /// Whether an app is on this TV.
  final bool Function(String packageName) _installed;

  HomeSearch({SearchService? service, TmdbClient? Function()? tmdb, required bool Function(String packageName) installed})
      : _service = service ?? SearchService(),
        _tmdb = tmdb ?? (() => null),
        _installed = installed;

  /// Set by the home: handles Android's Back (a system "go back", not a key) while there's a search to close.
  /// True when it did.
  bool Function()? backHandler;

  String _query = "";
  List<TitleMatch> _matches = const [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  /// What was searched ("" when there's no search).
  String get query => _query;
  bool get active => _query.isNotEmpty;
  bool get loading => _loading;
  String? get error => _error;

  /// Every title found, in search order.
  List<TitleMatch> get matches => _matches;

  /// Watchable now at no extra cost in an installed app: the results row, and the grid's first pill.
  List<TitleMatch> get watchNow => _matches.where((m) => m.availability.watchable).toList();

  /// Not watchable now, but rentable or for sale in an installed store.
  List<TitleMatch> get rentOrBuy =>
      _matches.where((m) => !m.availability.watchable && m.availability.rentOrBuy.isNotEmpty).toList();

  /// The rest: only on apps that aren't on this TV, or nowhere known.
  List<TitleMatch> get otherApps =>
      _matches.where((m) => !m.availability.watchable && m.availability.rentOrBuy.isEmpty).toList();

  /// Searches [text]. Each search replaces the last one's results outright, and an older search that answers late
  /// is dropped, so one search's titles never show up in another's.
  Future<void> search(String text) async {
    final query = text.trim();
    final generation = ++_generation;
    _query = query;
    _matches = const [];
    _error = null;
    _loading = query.length >= 2;
    notifyListeners();
    if (!_loading) return;
    try {
      final results = await _service.search(query);
      if (generation != _generation) return;
      final tmdb = _tmdb();
      final details = tmdb != null && tmdb.enabled
          ? await Future.wait(results.map(tmdb.details))
          : List<TitleDetails?>.filled(results.length, null);
      if (generation != _generation) return;
      _matches = [
        for (final (i, result) in results.indexed)
          TitleMatch(result, details[i], Availability.of(result, details[i], _installed)),
      ];
    } catch (_) {
      if (generation != _generation) return;
      _error = "Couldn't search right now. Check the internet connection.";
    }
    _loading = false;
    notifyListeners();
  }

  /// Ends the search: the home goes back to Continue Watching and the dock.
  void clear() {
    _generation++;
    _query = "";
    _matches = const [];
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
