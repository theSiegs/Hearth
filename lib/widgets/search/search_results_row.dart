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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/home_search.dart';
import '../../providers/search_service.dart';
import 'open_title.dart';
import 'search_grid_page.dart';
import 'title_card.dart';

/// Search results in Continue Watching's spot: the titles watchable now in the TV's apps, the focused one's name
/// and details above them (as HearthTube does), and a "More results" card for everything (the grid). Up goes to the
/// top bar; Back (Android's, which the home routes to HomeSearch.backHandler) ends the search.
class SearchResultsRow extends StatefulWidget {
  final VoidCallback onUp;

  const SearchResultsRow({super.key, required this.onUp});

  /// How many titles the row shows before "More results".
  static const int rowLimit = 8;

  @override
  State<SearchResultsRow> createState() => _SearchResultsRowState();
}

class _SearchResultsRowState extends State<SearchResultsRow> {
  TitleMatch? _focused;

  String _watchOn(TitleMatch m) {
    final names = appsFor(m).map((a) => a.name).toList();
    if (names.isEmpty) return "";
    return "Watch on ${names.length == 1 ? names.first : "${names.sublist(0, names.length - 1).join(", ")} or ${names.last}"}";
  }

  Future<void> _open(TitleMatch match) async {
    await openTitle(context, match);
  }

  void _openGrid() {
    SearchGridPage.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<HomeSearch>();
    final textTheme = Theme.of(context).textTheme;
    final shadow = [const Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];
    final row = search.watchNow.take(SearchResultsRow.rowLimit).toList();
    final focused = row.contains(_focused) ? _focused : (row.isNotEmpty ? row.first : null);

    final String heading;
    final String detail;
    if (search.loading) {
      heading = "Searching for “${search.query}”…";
      detail = "";
    } else if (search.error != null) {
      heading = search.error!;
      detail = "";
    } else if (focused != null) {
      heading = focused.result.title;
      detail = [focused.meta, _watchOn(focused)].where((s) => s.isNotEmpty).join(" · ");
    } else if (search.matches.isEmpty) {
      heading = "Nothing found for “${search.query}”";
      detail = "";
    } else {
      heading = "Nothing for “${search.query}” in your apps right now";
      detail = "See where else it's available in More results.";
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handleKey(event, onUp: widget.onUp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, shadows: shadow)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(detail.isEmpty ? " " : detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyLarge?.copyWith(color: Colors.white70, shadows: shadow)),
          ),
          SizedBox(
            height: 135 + 24,
            child: search.loading
                ? ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: 240,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                        ),
                    ],
                  )
                : ListView(
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final (i, match) in row.indexed)
                        Padding(
                          key: ValueKey(match.result.wikidataId),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TitleCard(
                            autofocus: i == 0,
                            title: match.result.title,
                            detail: match.meta,
                            imageUrl: match.imageUrl,
                            packageName: appsFor(match).firstOrNull?.packageName,
                            onFocusChange: (on) {
                              if (on) setState(() => _focused = match);
                            },
                            onPressed: () => _open(match),
                          ),
                        ),
                      if (search.matches.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: MoreCard(
                            autofocus: row.isEmpty,
                            label: "More results",
                            detail: "${search.matches.length} titles",
                            onPressed: _openGrid,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
