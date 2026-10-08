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
import 'title_card.dart';

enum _Tab { watchNow, rentOrBuy, otherApps }

/// Every result of the home's search, as a grid of the same cards, sorted by pills: Watch now (included in an
/// installed app), Rent or buy, Other apps. The pills follow HearthTube's: white when selected.
class SearchGridPage extends StatefulWidget {
  const SearchGridPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => const SearchGridPage(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  State<SearchGridPage> createState() => _SearchGridPageState();
}

class _SearchGridPageState extends State<SearchGridPage> {
  _Tab? _tab;

  List<TitleMatch> _items(HomeSearch search, _Tab tab) => switch (tab) {
        _Tab.watchNow => search.watchNow,
        _Tab.rentOrBuy => search.rentOrBuy,
        _Tab.otherApps => search.otherApps,
      };

  String _detail(TitleMatch m, _Tab tab) {
    final where = switch (tab) {
      _Tab.watchNow => appsFor(m).map((a) => a.name).join(", "),
      _Tab.rentOrBuy => "Rent or buy · ${appsFor(m, rentOrBuy: true).map((a) => a.name).join(", ")}",
      _Tab.otherApps => m.availability.elsewhere.isEmpty
          ? "Where to watch: Google TV"
          : "On ${m.availability.elsewhere.take(2).join(", ")} (not on this TV)",
    };
    return [m.meta, where].where((s) => s.isNotEmpty).join(" · ");
  }

  Future<void> _press(TitleMatch m, _Tab tab) async {
    final opened = switch (tab) {
      _Tab.watchNow => await openTitle(context, m),
      _Tab.rentOrBuy => await openTitle(context, m, rentOrBuy: true),
      _Tab.otherApps => await openOnGoogleTv(m),
    };
    if (opened && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<HomeSearch>();
    final textTheme = Theme.of(context).textTheme;
    final counts = {for (final t in _Tab.values) t: _items(search, t).length};
    // Opens on the first pill that has anything
    final tab = _tab ?? _Tab.values.firstWhere((t) => counts[t]! > 0, orElse: () => _Tab.watchNow);
    final items = _items(search, tab);
    const labels = {_Tab.watchNow: "Watch now", _Tab.rentOrBuy: "Rent or buy", _Tab.otherApps: "Other apps"};

    return Scaffold(
      backgroundColor: const Color(0xFF121612),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(26)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.search, size: 22),
                  const SizedBox(width: 10),
                  Text(search.query, style: textTheme.titleMedium),
                ]),
              ),
              const SizedBox(width: 16),
              Text("${search.matches.length} results", style: textTheme.titleMedium?.copyWith(color: Colors.white70)),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              for (final t in _Tab.values) ...[
                _Pill(
                  label: labels[t]!,
                  count: counts[t]!,
                  selected: t == tab,
                  autofocus: t == tab && items.isEmpty,
                  onSelected: () => setState(() => _tab = t),
                ),
                const SizedBox(width: 12),
              ],
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: items.isEmpty
                  ? Text("Nothing here for “${search.query}”.", style: textTheme.bodyLarge)
                  : LayoutBuilder(builder: (context, constraints) {
                      const columns = 4;
                      const gap = 22.0;
                      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                      return GridView.builder(
                        key: ValueKey(tab),
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: gap,
                            childAspectRatio: 16 / 9),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final m = items[i];
                          return TitleCard(
                            autofocus: i == 0,
                            width: width,
                            height: width * 9 / 16,
                            title: m.result.title,
                            detail: _detail(m, tab),
                            imageUrl: m.imageUrl,
                            packageName: switch (tab) {
                              _Tab.watchNow => appsFor(m).firstOrNull?.packageName,
                              _Tab.rentOrBuy => appsFor(m, rentOrBuy: true).firstOrNull?.packageName,
                              _Tab.otherApps => null,
                            },
                            onPressed: () => _press(m, tab),
                          );
                        },
                      );
                    }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  "Where to watch from TMDB (via JustWatch). This product uses the TMDB API but is not endorsed or "
                  "certified by TMDB.",
                  style: textTheme.bodySmall?.copyWith(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A HearthTube-style pill: white when selected, see-through otherwise; focusing it selects it.
class _Pill extends StatefulWidget {
  final String label;
  final int count;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelected;

  const _Pill(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onSelected,
      this.autofocus = false});

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = widget.selected ? Colors.black : Colors.white;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onSelected()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) widget.onSelected();
        },
        onKeyEvent: (_, __) => KeyEventResult.ignored,
        child: GestureDetector(
          onTap: widget.onSelected,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected ? Colors.white : Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _focused ? accent : Colors.white.withOpacity(0.15), width: _focused ? 3 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.label, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Text("${widget.count}", style: TextStyle(color: fg.withOpacity(0.6), fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
