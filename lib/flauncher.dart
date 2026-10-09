/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/widgets/profile_transition_overlay.dart';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flauncher/actions.dart';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/home_dock.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/providers/home_search.dart';
import 'package:flauncher/widgets/search/search_entry.dart';
import 'package:flauncher/widgets/search/search_grid_page.dart';
import 'package:flauncher/widgets/search/search_results_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/profile_service.dart';

import 'models/category.dart';

class FLauncher extends StatefulWidget {
  const FLauncher({super.key});

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> {
  final GlobalKey<FocusAwareAppBarState> _appBarKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  /// Wraps the dock layout's first screen (Continue Watching + dock).
  final FocusNode _firstScreenFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Wraps the sections below the dock.
  final FocusNode _belowDockFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Focus is in the sections below the dock, so the wallpaper is blurred behind them.
  bool _browsingBelowDock = false;

  /// Focus is in the top bar: the dock and Continue Watching are hidden.
  bool _topBarFocused = false;

  /// On the dock layout's first screen, the dock and Continue Watching take turns: Up from the dock
  /// slides the dock away and shows Continue Watching; Down from there brings the dock back.
  bool _showingRecents = false;
  final FocusNode _dockFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  final FocusNode _recentsFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  FocusNode? _lastDockFocus;

  /// Continue Watching has something to show (set as the home builds).
  bool _recentsAvailable = false;

  /// A search's results are in the dock's spot (Continue Watching's place), as Continue Watching takes it.
  bool _showingSearch = false;
  final FocusNode _searchRowFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// The search box is open over the home (typing, or listening when [_searchVoice]).
  bool _searchTyping = false;
  bool _searchVoice = false;
  HomeSearch? _homeSearch;
  bool _awaitingResults = false;

  /// Wraps the single apps grid shown when there's no dock.
  final FocusNode _appsGridFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  ProfileService? _profileService;
  String? _lastProfile;

  /// A profile just switched to, until the selection has landed on its home.
  String? _landingProfile;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusMoved);
    // The remote's mapped search button: open search, by voice or keyboard.
    FLauncherChannel.listenForSearch(_openSearch);
    final channel = context.read<FLauncherChannel>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await channel.takePendingSearch();
        if (pending != null) _openSearch(pending);
      } catch (_) {}
    });
    _homeSearch = context.read<HomeSearch?>();
    _homeSearch?.addListener(_onSearchChanged);
    _homeSearch?.backHandler = _searchBack;
    _profileService = context.read<ProfileService?>();
    _lastProfile = _profileService?.activeProfileKey;
    _profileService?.addListener(_onProfileChanged);
    _appsService = context.read<AppsService?>();
    _appsService?.addListener(_onAppsChanged);
  }

  AppsService? _appsService;
  DateTime? _landedAt;

  /// After a profile switch the profile's apps can arrive well after the welcome card (a kids profile's user is
  /// still unlocking), and the card that had focus can be rebuilt away: while nothing on the home has focus, the
  /// selection lands on the dock again as the apps come in. Only for a few minutes after a switch.
  void _onAppsChanged() {
    final at = _landedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(minutes: 3)) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus.context == null || focus is FocusScopeNode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _landOnHome());
    }
  }

  /// Arriving in a profile, the selection starts on the first dock app, or the first app when there's no dock.
  void _onProfileChanged() {
    final profiles = _profileService;
    if (profiles == null) return;
    final key = profiles.activeProfileKey;
    if (key != null && key != _lastProfile) {
      _lastProfile = key;
      _landingProfile = key;
      if (_showingRecents) setState(() => _showingRecents = false);
      // Another profile, another person: their search isn't this one's
      if (_homeSearch?.active ?? false) _endSearch(focusDock: false);
    }
    // Once, when the welcome card is gone and the profile's layout (its own dock) is in; the card holds focus till then.
    final landing = _landingProfile;
    if (landing == null || profiles.transition != null || !profiles.layoutReadyFor(landing)) return;
    _landingProfile = null;
    _landedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _landOnHome());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _landOnHome() {
    // Not while another page is open over the home (search, settings): it keeps its focus
    if (!mounted || _searchTyping || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    (_firstFocusable(_dockFocusNode) ?? _firstFocusable(_appsGridFocusNode) ?? _firstFocusable(_belowDockFocusNode))
        ?.requestFocus();
  }

  /// Opens the search box over the home: the keyboard, or listening right away for [mode] "voice" (the remote's
  /// voice search). It starts from the current search, to edit it.
  void _openSearch(String mode) {
    if (!mounted) return;
    setState(() {
      _searchTyping = true;
      _searchVoice = mode == "voice";
    });
  }

  void _submitSearch(String text) {
    setState(() {
      _searchTyping = false;
      // The row shows right away (its "Searching…" heading and placeholder cards) where there's a row to show
      if (_showingSearch || _firstFocusable(_dockFocusNode) != null) {
        _showingSearch = true;
        _showingRecents = false;
      }
    });
    _awaitingResults = true;
    // Focus waits on the search button until the results are in, then moves to them (_onSearchChanged)
    _appBarKey.currentState?.focusSearch();
    _homeSearch?.search(text);
  }

  void _cancelSearchEntry() {
    setState(() => _searchTyping = false);
    _appBarKey.currentState?.focusSearch();
    // A search that finished while the box was open shows now
    _onSearchChanged();
  }

  void _onSearchChanged() {
    final search = _homeSearch;
    if (!mounted || search == null || !_awaitingResults || search.loading || !search.active) return;
    // The box is open again for a new search: the old one's results mustn't take focus (or the keys) from it
    if (_searchTyping) return;
    _awaitingResults = false;
    // No dock on this layout: no row to show them in, so the grid. (While the row or Continue Watching shows, the
    // dock is out of the focus tree, so it only counts when neither is up.)
    if (!_showingSearch && !_showingRecents && _firstFocusable(_dockFocusNode) == null) {
      SearchGridPage.open(context);
      return;
    }
    _setShowingSearch(true);
  }

  /// Results in the dock's spot (true), or the dock back (false); focus goes with them.
  void _setShowingSearch(bool show) {
    setState(() {
      _showingSearch = show;
      if (show) _showingRecents = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchTyping) return;
      if (show) {
        (_firstFocusable(_searchRowFocusNode) ?? _firstFocusable(_dockFocusNode))?.requestFocus();
      } else {
        _focusDock();
      }
    });
  }

  /// Android's Back while searching: closes the search box, else ends the search. False when there's no search.
  bool _searchBack() {
    if (_searchTyping) {
      _cancelSearchEntry();
      return true;
    }
    if (_homeSearch?.active ?? false) {
      _endSearch();
      return true;
    }
    return false;
  }

  /// Back from the results: the search ends and the home is as it was.
  void _endSearch({bool focusDock = true}) {
    _awaitingResults = false;
    _homeSearch?.clear();
    setState(() => _showingSearch = false);
    if (focusDock) WidgetsBinding.instance.addPostFrameCallback((_) => _focusDock());
  }

  /// Keys on the results row besides Back and Up: Down brings the dock back (the search stays, a press of Up away).
  KeyEventResult _searchRowKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowDown || event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _setShowingSearch(false);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusMoved);
    _profileService?.removeListener(_onProfileChanged);
    _appsService?.removeListener(_onAppsChanged);
    _homeSearch?.removeListener(_onSearchChanged);
    if (_homeSearch?.backHandler == _searchBack) _homeSearch?.backHandler = null;
    _searchRowFocusNode.dispose();
    _appsGridFocusNode.dispose();
    _firstScreenFocusNode.dispose();
    _belowDockFocusNode.dispose();
    _dockFocusNode.dispose();
    _recentsFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusMoved() {
    if (_dockFocusNode.hasFocus) {
      _lastDockFocus = FocusManager.instance.primaryFocus;
    }
    _followTopBarFocus();
    _followBelowDockFocus();
    _keepFirstScreenAtTop();
  }

  /// With the top bar focused, the first screen is just the wallpaper: dock and Continue Watching slide away and
  /// come back when focus comes down again. Focus leaving the home screen (Settings, a dialog, the Home Assistant
  /// panel) leaves it as it was.
  void _followTopBarFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final bool inHome = focusContext != null &&
        focusContext.mounted &&
        focusContext.findAncestorStateOfType<_FLauncherState>() == this;
    final bool inTopBar = inHome && focusContext.findAncestorWidgetOfExactType<FocusAwareAppBar>() != null;
    if (inHome && inTopBar != _topBarFocused) {
      setState(() {
        _topBarFocused = inTopBar;
        if (inTopBar) _showingRecents = false;
      });
    }
  }

  /// The wallpaper blurs while focus is below the dock. Focus moving into a settings panel or the app bar leaves
  /// the blur as it was, unless the dock layout itself has gone (dock switched off, or Favorites emptied).
  void _followBelowDockFocus() {
    final bool dockLayoutGone = _belowDockFocusNode.context == null;
    if (_belowDockFocusNode.hasFocus != _browsingBelowDock &&
        (_belowDockFocusNode.hasFocus || _firstScreenFocusNode.hasFocus || dockLayoutGone)) {
      setState(() => _browsingBelowDock = _belowDockFocusNode.hasFocus);
    }
  }

  /// Cards centre themselves vertically when focused, which would scroll the dock layout's
  /// first screen partway off the top. While focus is on that screen, keep the page at the top.
  void _keepFirstScreenAtTop() {
    if (!_firstScreenFocusNode.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Unconditional: the card's own scroll animation has only just started, and this replaces it.
      if (mounted && _firstScreenFocusNode.hasFocus && _scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 150), curve: Curves.easeInOut);
      }
    });
  }

  void _setShowingRecents(bool show) {
    if (show == _showingRecents) return;
    setState(() => _showingRecents = show);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusNode? target;
      if (show) {
        target = _firstFocusable(_recentsFocusNode);
        if (target == null) {
          // The row emptied in the meantime: the dock instead.
          setState(() => _showingRecents = false);
          _focusDock();
          return;
        }
        target.requestFocus();
      } else {
        _focusDock();
      }
    });
  }

  /// Down from the top bar lands on Continue Watching when it has something, else on the dock where it was last.
  /// The dock is slid away (not unfocusable) while the top bar has focus, so plain Down would pick whatever is
  /// nearest on screen: the grid below, scrolling the page down. True when it handled the key.
  bool _leaveTopBar() {
    if (_firstFocusable(_dockFocusNode) == null) return false; // no dock: normal navigation
    if (_homeSearch?.active ?? false) {
      _setShowingSearch(true);
    } else if (_recentsAvailable) {
      _setShowingRecents(true);
    } else {
      _focusDock();
    }
    return true;
  }

  void _focusDock() {
    final last = _lastDockFocus;
    final target = last != null && last.context != null && _dockFocusNode.descendants.contains(last)
        ? last
        : _firstFocusable(_dockFocusNode);
    target?.requestFocus();
  }

  KeyEventResult _searchUpFromDock(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowUp || event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _setShowingSearch(true);
    return KeyEventResult.handled;
  }

  static FocusNode? _firstFocusable(FocusNode parent) =>
      parent.descendants.firstWhereOrNull((n) => n.canRequestFocus && !n.skipTraversal && n.context != null);

  /// Up from the dock swaps in Continue Watching; any other key is left for normal navigation.
  KeyEventResult _recentsUpFromDock(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowUp || event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _setShowingRecents(true);
    return KeyEventResult.handled;
  }

  /// From Continue Watching: Down swaps the dock back in; Up goes to the top bar and puts the dock back in place
  /// behind it, so Continue Watching only shows while it's being browsed.
  KeyEventResult _recentsKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) _setShowingRecents(false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent) {
        _appBarKey.currentState?.focusTopBar();
        setState(() => _showingRecents = false);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Actions(
        actions: <Type, Action<Intent>>{
          MoveFocusToTopBarIntent: CallbackAction<MoveFocusToTopBarIntent>(
            onInvoke: (_) {
              _appBarKey.currentState?.focusTopBar();
              // Continue Watching only shows while it's being browsed; the dock comes back behind the top bar.
              if (_showingRecents) setState(() => _showingRecents = false);
              return null;
            },
          ),
          StartSearchIntent: CallbackAction<StartSearchIntent>(onInvoke: (_) => _openSearch("text")),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) => _appBarKey.currentState?.openSettings(),
          ),
          LeaveTopBarIntent: CallbackAction<LeaveTopBarIntent>(onInvoke: (_) => _leaveTopBar()),
          OpenHaPanelIntent: CallbackAction<OpenHaPanelIntent>(
            onInvoke: (_) => context.read<FLauncherChannel>().openHaPanel(),
          ),
        },
        child: FocusTraversalGroup(
            policy: RowByRowTraversalPolicy(),
            child: Stack(children: [
              RepaintBoundary(
                child: Consumer<WallpaperService>(
                    builder: (_, wallpaperService, __) => _wallpaper(context, wallpaperService)),
              ),
              // Below the dock, the wallpaper blurs so the rows of apps stand out (from arclauncher).
              Selector2<SettingsService, WallpaperService, bool>(
                selector: (_, settings, wallpaper) =>
                    settings.blurWallpaperBelowDock && wallpaper.focusedAppColor == null,
                builder: (_, blurEnabled, __) => Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      key: const Key("below_dock_blur"),
                      opacity: blurEnabled && _browsingBelowDock ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: const CachedBlurBackdrop(sigma: 10, child: SizedBox.expand()),
                    ),
                  ),
                ),
              ),
              Consumer<LauncherState>(
                  builder: (_, state, child) => Visibility(
                      visible: state.launcherVisible,
                      replacement: const Center(child: AlternativeLauncherView()),
                      child: child!),
                  child: Scaffold(
                      backgroundColor: Colors.transparent,
                      appBar: FocusAwareAppBar(key: _appBarKey),
                      body: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Consumer<AppsService>(
                              builder: (context, appsService, _) => _homeBody(context, appsService))))),
              // Typing or saying a search, over the home
              if (_searchTyping)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.55),
                    child: SearchEntry(
                      key: ValueKey(_searchVoice),
                      initialText: _homeSearch?.query ?? "",
                      voice: _searchVoice,
                      onSubmit: _submitSearch,
                      onCancel: _cancelSearchEntry,
                    ),
                  ),
                ),
              // A profile switch: the welcome card until this profile's home is complete
              Positioned.fill(child: ProfileTransitionOverlay(channel: context.read<FLauncherChannel>())),
            ])),
      );

  /// The scrolling home, once the apps and the profile are in.
  Widget _homeBody(BuildContext context, AppsService appsService) {
    // Starting up: placeholders until both the apps and the profile (its layout) are in,
    // so the home doesn't reshuffle in front of anyone
    final bool profileSettled = context.select<ProfileService?, bool>((p) => p?.settledOnce ?? true);
    if (!appsService.initialized || !profileSettled) {
      return _emptyState(context);
    }
    return Selector3<SettingsService, WatchNextService, AppsService, ({bool continueWatching, int order, bool dock})>(
      selector: (_, settings, watchNext, apps) => (
        // The row's own list, so the home never keeps a spot (or Up) for a row with nothing in it
        continueWatching: settings.showContinueWatching &&
            watchNext.hasPermission &&
            watchNext.visiblePrograms(settings, apps).isNotEmpty,
        order: settings.continueWatchingOrder,
        dock: settings.dockEnabled,
      ),
      builder: (context, home, _) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          child: _home(appsService.launcherSections,
              viewportHeight: constraints.maxHeight,
              dockEnabled: home.dock,
              continueWatchingActive: home.continueWatching,
              continueWatchingOrder: home.order),
        ),
      ),
    );
  }

  /// With the dock on and something in Favorites, the first screen shows the wallpaper with
  /// Continue Watching and the Favorites dock along the bottom; the other sections follow below.
  /// Otherwise it's the classic list of sections.
  Widget _home(
    List<LauncherSection> sections, {
    required double viewportHeight,
    required bool dockEnabled,
    required bool continueWatchingActive,
    required int continueWatchingOrder,
  }) {
    final Category? favorites = dockEnabled
        ? sections
            .whereType<Category>()
            .firstWhereOrNull((c) => c.name == AppsService.favoritesName && c.applications.isNotEmpty)
        : null;
    if (favorites == null && !dockEnabled) {
      return _sections(sections,
          continueWatchingActive: continueWatchingActive, continueWatchingOrder: continueWatchingOrder);
    }
    if (favorites == null) {
      // No dock (nothing in Favorites this profile can open): one untitled grid of the apps it can open, never the
      // TV Apps / Non-TV Apps / Favorites split, or a friendly card when there's nothing at all.
      final usable = sections
          .where((s) => !(s is Category && (s.applications.isEmpty || s.name == AppsService.favoritesName)))
          .toList();
      if (usable.isEmpty && !continueWatchingActive) return _nothingToWatch(viewportHeight);
      return Focus(
        focusNode: _appsGridFocusNode,
        child: _sections(usable,
            continueWatchingActive: continueWatchingActive,
            continueWatchingOrder: continueWatchingOrder,
            showTitles: false,
            allGrids: true),
      );
    }

    // Empty sections (often "Non-TV Apps") are left out below the dock; they'd only say "This category is empty".
    // With a single section left, its heading is dropped too. Everything below the dock wraps as a grid,
    // so a "row" section doesn't become one long sideways-scrolling strip.
    final search = context.watch<HomeSearch?>();
    final bool showSearch = (search?.active ?? false) && _showingSearch;
    final bool showRecents = continueWatchingActive && _showingRecents && !showSearch;
    _recentsAvailable = continueWatchingActive;
    final List<LauncherSection> belowDock =
        sections.where((s) => s != favorites && !(s is Category && s.applications.isEmpty)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(minHeight: viewportHeight),
          alignment: Alignment.bottomCenter,
          child: Focus(
            focusNode: _firstScreenFocusNode,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (continueWatchingActive)
                  ExcludeFocus(
                    excluding: !showRecents,
                    child: Focus(
                      focusNode: _recentsFocusNode,
                      onKeyEvent: _recentsKey,
                      child: _swapAnimation(
                        visible: showRecents,
                        hiddenOffset: const Offset(0, 0.25),
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: ContinueWatchingRow(key: Key("home_recents"), isFirstSection: true),
                        ),
                      ),
                    ),
                  ),
                // A search's results, in Continue Watching's place (they stay up while the top bar has focus)
                if (search?.active ?? false)
                  ExcludeFocus(
                    excluding: !showSearch,
                    child: Focus(
                      focusNode: _searchRowFocusNode,
                      onKeyEvent: _searchRowKey,
                      child: _swapAnimation(
                        visible: showSearch,
                        hiddenOffset: const Offset(0, 0.25),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: SearchResultsRow(
                            onUp: () => _appBarKey.currentState?.focusSearch(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ExcludeFocus(
                  excluding: showRecents || showSearch,
                  child: Focus(
                    focusNode: _dockFocusNode,
                    // Up from the dock: the search's results while there's a search, else Continue Watching
                    onKeyEvent: (search?.active ?? false)
                        ? _searchUpFromDock
                        : (continueWatchingActive ? _recentsUpFromDock : null),
                    child: _swapAnimation(
                      visible: !showRecents && !showSearch && !_topBarFocused,
                      // Slide fully off-screen without fading: a fade would freeze the frosted backdrop's
                      // off-screen sample.
                      hiddenOffset: const Offset(0, 1.6),
                      fade: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        child: HomeDock(
                          key: Key(favorites.id.toString()),
                          category: favorites,
                          isFirstSection: !continueWatchingActive,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Focus(
          focusNode: _belowDockFocusNode,
          child: _sections(belowDock,
              firstCategoryAlreadyFound: true, showTitles: false, allGrids: true),
        ),
      ],
    );
  }

  /// Shown when the profile can open nothing at all (a kids profile at bedtime, or before apps are approved).
  Widget _nothingToWatch(double viewportHeight) => Container(
        key: const Key("nothing_to_watch"),
        height: viewportHeight,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.nightlight_round, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.homeNothingToWatch,
                  style: const TextStyle(color: Colors.white, fontSize: 24)),
            ],
          ),
        ),
      );

  Widget _swapAnimation(
          {required bool visible, required Offset hiddenOffset, required Widget child, bool fade = true}) =>
      AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: fade
            ? AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: child,
              )
            : child,
      );

  Widget _sections(
    List<LauncherSection> sections, {
    bool continueWatchingActive = false,
    int continueWatchingOrder = 0,
    bool firstCategoryAlreadyFound = false,
    bool showTitles = true,
    bool allGrids = false,
  }) {
    List<Widget> children = [];
    bool firstCategoryFound = firstCategoryAlreadyFound;
    bool cwInserted = false;

    int sectionIdx = 0;
    for (var section in sections) {
      if (continueWatchingActive && !cwInserted && sectionIdx == continueWatchingOrder) {
        final bool isFirstSection = !firstCategoryFound;
        children.add(ContinueWatchingRow(isFirstSection: isFirstSection));
        cwInserted = true;
        firstCategoryFound = true;
      }

      final Key sectionKey = Key(section.id.toString());

      if (section is LauncherSpacer) {
        children.add(SizedBox(key: sectionKey, height: section.height.toDouble()));
        sectionIdx++;
        continue;
      }

      Category category = section as Category;
      Widget categoryWidget;

      bool isFirstSection = !firstCategoryFound;
      if (isFirstSection) firstCategoryFound = true;

      switch (allGrids ? CategoryType.grid : category.type) {
        case CategoryType.row:
          categoryWidget = CategoryRow(
              key: sectionKey,
              category: category,
              isFirstSection: isFirstSection,
              showTitle: showTitles);
          break;
        case CategoryType.grid:
          categoryWidget = AppsGrid(
              key: sectionKey,
              category: category,
              isFirstSection: isFirstSection,
              showTitle: showTitles);
          break;
      }

      children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: categoryWidget));
      sectionIdx++;
    }

    if (continueWatchingActive && !cwInserted) {
      children.add(ContinueWatchingRow(isFirstSection: !firstCategoryFound));
    }

    return Column(children: children);
  }

  Widget _wallpaper(BuildContext context, WallpaperService wallpaperService) {
    Widget background;
    if (wallpaperService.wallpaper != null) {
      final physicalSize = MediaQuery.sizeOf(context);
      background = Image(
          image: wallpaperService.wallpaper!,
          key: Key("background_${wallpaperService.version}"),
          fit: BoxFit.cover,
          height: physicalSize.height,
          width: physicalSize.width);
    } else {
      background =
          _CachedGradientBackground(key: const Key("background"), gradient: wallpaperService.gradient.gradient);
    }

    final Color? appColor = wallpaperService.focusedAppColor;
    if (appColor != null) {
      background = AnimatedContainer(
        key: const Key("background_app_color"),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [appColor, Color.lerp(appColor, Colors.black, 0.7)!],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: kWallpaperShadeColors,
            ),
          ),
        ),
      ],
    );
  }

  /// Starting up: empty dock-shaped tiles where the dock will appear.
  Widget _emptyState(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Container(
          key: const Key("home_placeholder"),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              4,
              (i) => Container(
                width: 160,
                height: 90,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 12),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a [Gradient] once into an image and shows that, instead of evaluating the gradient
/// shader on every frame; on TV sticks a full-screen live gradient costs noticeably more.
/// Adapted from arclauncher.
class _CachedGradientBackground extends StatefulWidget {
  final Gradient gradient;

  const _CachedGradientBackground({super.key, required this.gradient});

  @override
  State<_CachedGradientBackground> createState() => _CachedGradientBackgroundState();
}

class _CachedGradientBackgroundState extends State<_CachedGradientBackground> {
  ui.Image? _image;
  Size _renderedSize = Size.zero;
  Gradient? _renderedGradient;
  bool _rendering = false;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(Size size) async {
    if (_rendering) {
      return;
    }
    _rendering = true;
    final recorder = ui.PictureRecorder();
    final rect = Offset.zero & size;
    Canvas(recorder).drawRect(rect, Paint()..shader = widget.gradient.createShader(rect));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    picture.dispose();
    _rendering = false;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _renderedSize = size;
      _renderedGradient = widget.gradient;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final needsRender = size != _renderedSize || widget.gradient != _renderedGradient;
        if (needsRender && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (size != _renderedSize || widget.gradient != _renderedGradient)) {
              _render(size);
            }
          });
        }
        final image = _image;
        if (image != null && !needsRender) {
          return RawImage(image: image, width: size.width, height: size.height, fit: BoxFit.fill);
        }
        // First frame, and while re-rendering: paint the gradient live so nothing flashes.
        return DecoratedBox(decoration: BoxDecoration(gradient: widget.gradient));
      },
    );
  }
}
