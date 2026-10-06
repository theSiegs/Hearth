import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _hearthTube = "com.thesiegs.hearthtube";

/// Hearth's search: films and shows from Wikidata, each with buttons for the installed apps that have it (opening
/// the app on that title), plus HearthTube and Google TV's own search.
class SearchPage extends StatefulWidget {
  final SearchService? service;

  const SearchPage({super.key, this.service});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => const SearchPage(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static final SearchService _sharedService = SearchService();

  final FLauncherChannel _channel = FLauncherChannel();
  final TextEditingController _text = TextEditingController();
  // Down leaves the text field for the results (a text field keeps the arrow keys for its cursor otherwise).
  late final FocusNode _field = FocusNode(onKeyEvent: (node, event) {
    if (event is! KeyUpEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      node.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });
  Timer? _debounce;
  String _query = "";
  List<SearchResult> _results = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  SearchService get _service => widget.service ?? _sharedService;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(text));
  }

  Future<void> _search(String text) async {
    final generation = ++_generation;
    setState(() {
      _query = text.trim();
      _loading = _query.length >= 2;
      _error = null;
      if (_query.length < 2) _results = [];
    });
    if (_query.length < 2) return;
    try {
      final results = await _service.search(_query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search right now. Check the internet connection.";
      });
    }
  }

  Future<void> _open(Future<bool> Function() action) async {
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That app couldn't open it.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = context.watch<AppsService>();
    bool installed(String packageName) => apps.getApp(packageName) != null;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              focusNode: _field,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (text) {
                _debounce?.cancel();
                _search(text);
              },
              style: textTheme.headlineSmall,
              decoration: InputDecoration(
                hintText: "Search films and shows",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  if (_loading)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                  if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
                  if (!_loading && _error == null && _query.length >= 2 && _results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text("No films or shows found for \"$_query\".", style: textTheme.bodyLarge),
                    ),
                  for (final result in _results) _ResultRow(result: result, installed: installed, open: _open),
                  if (_query.length >= 2) ...[
                    const Divider(height: 32),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (installed(_hearthTube))
                          SearchChip(
                            icon: Icons.smart_display_outlined,
                            label: "Search HearthTube for \"$_query\"",
                            onPressed: () => _open(() => _channel.searchInApp(_hearthTube, _query)),
                          ),
                        SearchChip(
                          icon: Icons.travel_explore,
                          label: "Ask Google TV",
                          onPressed: () => _open(() => _channel.openGoogleTv(query: _query)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                        _tmdb.enabled
                            ? "Titles from Wikidata; posters and where it's streaming from TMDB (via JustWatch). "
                                "This product uses the TMDB API but is not endorsed or certified by TMDB."
                            : "Titles from Wikidata. Only your search text is sent.",
                        style: textTheme.bodySmall?.copyWith(color: Colors.white38)),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Posters and "streaming on" (TMDB), when a key is built in.
final TmdbClient _tmdb = TmdbClient();

class _ResultRow extends StatelessWidget {
  final SearchResult result;
  final bool Function(String packageName) installed;
  final Future<void> Function(Future<bool> Function() action) open;

  const _ResultRow({required this.result, required this.installed, required this.open});

  @override
  Widget build(BuildContext context) {
    final channel = FLauncherChannel();
    final textTheme = Theme.of(context).textTheme;
    final offers = result.offers.where((offer) => installed(offer.service.packageName)).toList();
    return FutureBuilder<TitleDetails?>(
      future: _tmdb.details(result),
      builder: (context, snapshot) {
        final details = snapshot.data;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tmdb.enabled) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 72,
                    height: 108,
                    color: Colors.white10,
                    child: details?.posterUrl != null
                        ? Image.network(details!.posterUrl!,
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                        : const Icon(Icons.movie_outlined, color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(child: _details(context, textTheme, offers, channel, details)),
            ],
          ),
        );
      },
    );
  }

  Widget _details(BuildContext context, TextTheme textTheme, List<SearchOffer> offers, FLauncherChannel channel,
      TitleDetails? details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.year != null ? "${result.title} (${result.year})" : result.title, style: textTheme.titleLarge),
        if (result.description != null)
          Text(result.description!, style: textTheme.bodyMedium?.copyWith(color: Colors.white60)),
        if (details != null && details.streamingOn.isNotEmpty)
          Text("Streaming on ${details.streamingOn.take(4).join(", ")}",
              style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final offer in offers)
              SearchChip(
                icon: Icons.play_arrow_rounded,
                label: offer.service.name,
                onPressed: () => open(() => channel.openLinkInApp(offer.service.packageName, offer.link)),
              ),
            SearchChip(
              icon: Icons.info_outline,
              label: offers.isEmpty ? "Where to watch (Google TV)" : "More on Google TV",
              onPressed: () => open(() => result.googleTvLink != null
                  ? channel.openGoogleTv(link: result.googleTvLink)
                  : channel.openGoogleTv(query: result.title)),
            ),
          ],
        ),
      ],
    );
  }
}

/// A focusable pill button for the TV remote.
class SearchChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const SearchChip({super.key, required this.icon, required this.label, required this.onPressed});

  @override
  State<SearchChip> createState() => _SearchChipState();
}

class _SearchChipState extends State<SearchChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 100));
        },
        onKeyEvent: (_, event) => KeyEventResult.ignored,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _focused ? accent : Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
