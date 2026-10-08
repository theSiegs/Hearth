import 'dart:async';

import 'package:collection/collection.dart';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/search_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _hearthTube = "com.thesiegs.hearthtube";

/// Hearth's search: films and shows from Wikidata, each with buttons for the installed apps that have it (opening
/// the app on that title), plus HearthTube and Google TV's own search.
class SearchPage extends StatefulWidget {
  final SearchService? service;

  /// Start listening for a spoken search as soon as the page opens (the remote's mic/search button).
  final bool voice;

  const SearchPage({super.key, this.service, this.voice = false});

  static Future<void> open(BuildContext context, {bool voice = false}) => Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => SearchPage(voice: voice),
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
  // OK on the field brings up the on-screen keyboard (a TV remote has no other way to ask for it).
  late final FocusNode _field = FocusNode(onKeyEvent: (node, event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
      _showKeyboard();
      return KeyEventResult.handled;
    }
    if (event is! KeyUpEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_firstResult.context != null) {
        _firstResult.requestFocus();
      } else {
        node.focusInDirection(TraversalDirection.down);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });

  /// The first result's first button, where Down from the text field goes.
  final FocusNode _firstResult = FocusNode();
  Timer? _debounce;
  String _query = "";
  List<SearchResult> _results = [];

  /// TMDB's details for each result (null: none), fetched before results show so they can be grouped.
  Map<SearchResult, TitleDetails?> _details = {};

  /// The quiet group (rent or buy, other apps) is open.
  bool _showMore = false;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  SearchService get _service => widget.service ?? _sharedService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.voice) {
        _listen();
      } else {
        _showKeyboard();
      }
    });
  }

  void _showKeyboard() {
    _field.requestFocus();
    SystemChannels.textInput.invokeMethod("TextInput.show");
  }

  bool _listening = false;

  /// Asks the TV's speech recognizer for the search text, then searches it.
  Future<void> _listen() async {
    if (_listening) return;
    setState(() => _listening = true);
    String? said;
    try {
      said = await _channel.voiceSearch();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _listening = false);
    if (said == null || said.trim().isEmpty) {
      _field.requestFocus();
      return;
    }
    _text.text = said.trim();
    _debounce?.cancel();
    await _search(said);
    if (mounted && _firstResult.context != null) _firstResult.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _field.dispose();
    _firstResult.dispose();
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
      // Where each title is watchable decides where it shows, so the details come first (TMDB's answers are cached)
      final tmdb = _tmdbFor(context);
      final details = tmdb.enabled ? await Future.wait(results.map(tmdb.details)) : <TitleDetails?>[];
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _details = {for (final (i, r) in results.indexed) r: i < details.length ? details[i] : null};
        _showMore = false;
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

  /// Titles included with an installed app first (at no extra cost); the rest (rent or buy, or only on apps that
  /// aren't installed) behind one quiet line, closed until asked for.
  List<Widget> _resultRows(bool Function(String packageName) installed) {
    final watchable = <(SearchResult, Availability)>[];
    final more = <(SearchResult, Availability)>[];
    for (final result in _results) {
      final availability = Availability.of(result, _details[result], installed);
      (availability.watchable ? watchable : more).add((result, availability));
    }
    final textTheme = Theme.of(context).textTheme;
    return [
      for (final (index, (result, availability)) in watchable.indexed)
        _ResultRow(
            result: result,
            details: _details[result],
            availability: availability,
            open: _open,
            firstFocus: index == 0 ? _firstResult : null),
      if (!_loading && _results.isNotEmpty && watchable.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Text("Nothing for \"$_query\" in your apps right now.", style: textTheme.bodyLarge),
        ),
      if (more.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SearchChip(
              focusNode: watchable.isEmpty ? _firstResult : null,
              icon: _showMore ? Icons.expand_less : Icons.expand_more,
              label: _showMore ? "Fewer" : "${more.length} more to rent, buy, or in other apps",
              quiet: true,
              onPressed: () => setState(() => _showMore = !_showMore),
            ),
          ),
        ),
      if (_showMore)
        for (final (result, availability) in more)
          _ResultRow(
              result: result, details: _details[result], availability: availability, open: _open, quiet: true),
    ];
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
            Row(
              children: [
                Image.asset("assets/logo.png", height: 40, filterQuality: FilterQuality.medium),
                const SizedBox(width: 16),
                Text("Search", style: textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _MicButton(listening: _listening, onPressed: _listen),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _field,
                    autofocus: !widget.voice,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (text) {
                      _debounce?.cancel();
                      _search(text);
                    },
                    style: textTheme.headlineSmall,
                    decoration: InputDecoration(
                      hintText: _listening ? "Listening\u2026" : "Search films and shows",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(color: Colors.transparent, width: 2)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
                    ),
                  ),
                ),
              ],
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
                  ..._resultRows(installed),
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
                            onPressed: () => _open(() => _channel.openLinkInApp(_hearthTube,
                                "https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(_query)}")),
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
                        _tmdbFor(context).enabled
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
final Map<String, TmdbClient> _tmdbClients = {};

/// The user's own TMDB key (Settings → Search) when set, otherwise the one built into this release.
TmdbClient _tmdbFor(BuildContext context) {
  final userKey = context.read<SettingsService>().tmdbApiKey;
  return _tmdbClients[userKey] ??= userKey.isEmpty ? TmdbClient() : TmdbClient(apiKey: userKey);
}

class _ResultRow extends StatelessWidget {
  final SearchResult result;
  final TitleDetails? details;
  final Availability availability;
  final Future<void> Function(Future<bool> Function() action) open;
  final FocusNode? firstFocus;

  /// In the "more" group: smaller and dimmer.
  final bool quiet;

  const _ResultRow(
      {required this.result,
      required this.details,
      required this.availability,
      required this.open,
      this.firstFocus,
      this.quiet = false});

  /// Opens the title in [app]: its own page when Wikidata links one, else the app's search for the title, else
  /// Google TV's page for it.
  Future<bool> _openIn(FLauncherChannel channel, ProviderApp app) async {
    final offer = result.offers.firstWhereOrNull((o) => o.service.packageName == app.packageName);
    if (offer != null && await channel.openLinkInApp(app.packageName, offer.link)) return true;
    if (await channel.searchInApp(app.packageName, result.title)) return true;
    return _openGoogleTv(channel);
  }

  Future<bool> _openGoogleTv(FLauncherChannel channel) => result.googleTvLink != null
      ? channel.openGoogleTv(link: result.googleTvLink)
      : channel.openGoogleTv(query: result.title);

  @override
  Widget build(BuildContext context) {
    final channel = FLauncherChannel();
    final textTheme = Theme.of(context).textTheme;
    // The quiet line: everything that isn't "watch it now"
    final notes = [
      if (availability.rentOrBuy.isNotEmpty) "Rent or buy on ${availability.rentOrBuy.map((a) => a.name).join(", ")}",
      if (availability.elsewhere.isNotEmpty && !availability.watchable) "Also on ${availability.elsewhere.take(3).join(", ")} (not on this TV)",
    ];
    final buttons = quiet ? availability.rentOrBuy : availability.included;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: quiet ? 6 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tmdbFor(context).enabled) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: quiet ? 48 : 72,
                height: quiet ? 72 : 108,
                color: Colors.white10,
                child: details?.posterUrl != null
                    ? Opacity(
                        opacity: quiet ? 0.6 : 1,
                        child: Image.network(details!.posterUrl!,
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))
                    : const Icon(Icons.movie_outlined, color: Colors.white24),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.year != null ? "${result.title} (${result.year})" : result.title,
                    style: (quiet ? textTheme.titleMedium : textTheme.titleLarge)
                        ?.copyWith(color: quiet ? Colors.white70 : null)),
                if (result.description != null && !quiet)
                  Text(result.description!, style: textTheme.bodyMedium?.copyWith(color: Colors.white60)),
                if (notes.isNotEmpty)
                  Text(notes.join(" \u00b7 "), style: textTheme.bodySmall?.copyWith(color: Colors.white38)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final (index, app) in buttons.indexed)
                      SearchChip(
                        focusNode: index == 0 ? firstFocus : null,
                        icon: quiet ? Icons.shopping_bag_outlined : Icons.play_arrow_rounded,
                        label: quiet ? "Rent or buy on ${app.name}" : app.name,
                        quiet: quiet,
                        onPressed: () => open(() => _openIn(channel, app)),
                      ),
                    SearchChip(
                      focusNode: buttons.isEmpty ? firstFocus : null,
                      icon: Icons.info_outline,
                      label: "More on Google TV",
                      quiet: true,
                      onPressed: () => open(() => _openGoogleTv(channel)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A focusable pill button for the TV remote.
class SearchChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  /// Secondary: smaller, no background and dimmer until it's focused.
  final bool quiet;

  const SearchChip(
      {super.key, required this.icon, required this.label, required this.onPressed, this.focusNode, this.quiet = false});

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
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 100));
        },
        onKeyEvent: (_, event) => KeyEventResult.ignored,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding: widget.quiet
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _focused ? accent : (widget.quiet ? Colors.transparent : Colors.white.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon,
                    size: widget.quiet ? 16 : 20, color: _focused || !widget.quiet ? Colors.white : Colors.white54),
                const SizedBox(width: 8),
                Text(widget.label,
                    style: TextStyle(
                        color: _focused || !widget.quiet ? Colors.white : Colors.white54,
                        fontSize: widget.quiet ? 14 : 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The microphone circle next to the search box, in the top bar's style.
class _MicButton extends StatefulWidget {
  final bool listening;
  final VoidCallback onPressed;

  const _MicButton({required this.listening, required this.onPressed});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
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
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _focused || widget.listening ? accent : const Color(0xE6202024),
            ),
            child: Icon(widget.listening ? Icons.graphic_eq : Icons.mic, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
