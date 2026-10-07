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

import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flauncher/actions.dart';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/home_dock.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/l10n/app_localizations.dart';

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

  /// On the dock layout's first screen, the dock and Continue Watching take turns: Up from the dock
  /// slides the dock away and shows Continue Watching; Down from there brings the dock back.
  bool _showingRecents = false;
  final FocusNode _dockFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  final FocusNode _recentsFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  FocusNode? _lastDockFocus;

  /// Wraps the single apps grid shown when there's no dock.
  final FocusNode _appsGridFocusNode = FocusNode(canRequestFocus: false, skipTraversal: true);

  ProfileService? _profileService;
  String? _lastProfile;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusMoved);
    // The remote's mapped search button: open search, by voice or keyboard.
    FLauncherChannel.listenForSearch(_openSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await FLauncherChannel().takePendingSearch();
        if (pending != null) _openSearch(pending);
      } catch (_) {}
    });
    _profileService = context.read<ProfileService?>();
    _lastProfile = _profileService?.activeProfileName;
    _profileService?.addListener(_onProfileChanged);
  }

  /// Arriving in a profile, the selection starts on the first dock app, or the first app when there's no dock.
  void _onProfileChanged() {
    final name = _profileService?.activeProfileName;
    if (name == null || name == _lastProfile) return;
    _lastProfile = name;
    if (_showingRecents) setState(() => _showingRecents = false);
    // Keep trying for a few seconds: the profile's layout (its own dock) and app list load after the name changes,
    // and focus comes back to the top bar (where the profile switch started), which would hide the dock.
    var landed = false;
    for (final ms in const [300, 1200, 2500, 4000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || landed) return;
        final target = _firstFocusable(_dockFocusNode) ?? _firstFocusable(_appsGridFocusNode) ??
            _firstFocusable(_belowDockFocusNode);
        if (target != null) {
          target.requestFocus();
          landed = _dockFocusNode.hasFocus || _appsGridFocusNode.hasFocus || _belowDockFocusNode.hasFocus;
        }
      });
    }
  }

  bool _searchOpen = false;

  /// Focus is in the top bar: the dock and Continue Watching are hidden.
  bool _topBarFocused = false;

  Future<void> _openSearch(String mode) async {
    if (!mounted || _searchOpen) return;
    _searchOpen = true;
    await SearchPage.open(context, voice: mode == "voice");
    _searchOpen = false;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusMoved);
    _profileService?.removeListener(_onProfileChanged);
    _appsGridFocusNode.dispose();
    _firstScreenFocusNode.dispose();
    _belowDockFocusNode.dispose();
    _dockFocusNode.dispose();
    _recentsFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Cards centre themselves vertically when focused, which would scroll the dock layout's
  /// first screen partway off the top. While focus is on that screen, keep the page at the top.
  void _onFocusMoved() {
    if (_dockFocusNode.hasFocus) {
      _lastDockFocus = FocusManager.instance.primaryFocus;
    }
    // With the top bar focused, the first screen is just the wallpaper: dock and Continue Watching slide away and
    // come back when focus comes down again.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final bool inTopBar = focusContext != null &&
        focusContext.mounted &&
        focusContext.findAncestorWidgetOfExactType<FocusAwareAppBar>() != null;
    if (inTopBar != _topBarFocused) {
      setState(() {
        _topBarFocused = inTopBar;
        if (inTopBar) _showingRecents = false;
      });
    }
    // Focus moving into a settings panel or the app bar leaves the blur as it was,
    // unless the dock layout itself has gone (dock switched off, or Favorites emptied).
    final bool dockLayoutGone = _belowDockFocusNode.context == null;
    if (_belowDockFocusNode.hasFocus != _browsingBelowDock &&
        (_belowDockFocusNode.hasFocus || _firstScreenFocusNode.hasFocus || dockLayoutGone)) {
      setState(() => _browsingBelowDock = _belowDockFocusNode.hasFocus);
    }
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
          // Nothing to show after all (e.g. every program is hidden): stay on the dock.
          setState(() => _showingRecents = false);
          return;
        }
      } else {
        final last = _lastDockFocus;
        target = last != null && last.context != null && _dockFocusNode.descendants.contains(last)
            ? last
            : _firstFocusable(_dockFocusNode);
      }
      target?.requestFocus();
    });
  }

  static FocusNode? _firstFocusable(FocusNode parent) =>
      parent.descendants.firstWhereOrNull((n) => n.canRequestFocus && !n.skipTraversal && n.context != null);

  /// Up (or Down) swaps the dock and Continue Watching; any other key is left for normal navigation.
  KeyEventResult Function(FocusNode, KeyEvent) _swapOn(LogicalKeyboardKey key, bool showRecents) => (node, event) {
        if (event.logicalKey != key || event is KeyUpEvent) return KeyEventResult.ignored;
        if (event is KeyDownEvent) _setShowingRecents(showRecents);
        return KeyEventResult.handled;
      };

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
        _appBarKey.currentState?.focusSettings();
        setState(() => _showingRecents = false);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Actions(
        actions: <Type, Action<Intent>>{
          MoveFocusToSettingsIntent: CallbackAction<MoveFocusToSettingsIntent>(
            onInvoke: (_) {
              _appBarKey.currentState?.focusSettings();
              // Continue Watching only shows while it's being browsed; the dock comes back behind the top bar.
              if (_showingRecents) setState(() => _showingRecents = false);
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) => _appBarKey.currentState?.openSettings(),
          ),
          OpenHaPanelIntent: CallbackAction<OpenHaPanelIntent>(
            onInvoke: (_) => FLauncherChannel().openHaPanel(),
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
                      child: child!,
                      replacement: const Center(child: AlternativeLauncherView()),
                      visible: state.launcherVisible),
                  child: Scaffold(
                      backgroundColor: Colors.transparent,
                      appBar: FocusAwareAppBar(key: _appBarKey),
                      body: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Consumer<AppsService>(builder: (context, appsService, _) {
                            if (appsService.initialized) {
                              return Selector<WatchNextService, bool>(
                                selector: (_, watchNext) => watchNext.programs.isNotEmpty,
                                builder: (context, hasContinuingPrograms, _) =>
                                    Selector<SettingsService, ({bool show, int order, bool dock})>(
                                  selector: (_, settings) => (
                                    show: settings.showContinueWatching,
                                    order: settings.continueWatchingOrder,
                                    dock: settings.dockEnabled,
                                  ),
                                  builder: (context, cwSettings, _) => LayoutBuilder(
                                    builder: (context, constraints) => SingleChildScrollView(
                                      controller: _scrollController,
                                      physics: const ClampingScrollPhysics(),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _home(appsService.launcherSections,
                                              viewportHeight: constraints.maxHeight,
                                              dockEnabled: cwSettings.dock,
                                              continueWatchingActive: cwSettings.show && hasContinuingPrograms,
                                              continueWatchingOrder: cwSettings.order),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return _emptyState(context);
                            }
                          }))))
            ])),
      );

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
        ? sections.whereType<Category>().firstWhereOrNull((c) => c.name == 'Favorites' && c.applications.isNotEmpty)
        : null;
    if (favorites == null && !dockEnabled) {
      return _sections(sections,
          continueWatchingActive: continueWatchingActive, continueWatchingOrder: continueWatchingOrder);
    }
    if (favorites == null) {
      // No dock (nothing in Favorites this profile can open): one untitled grid of the apps it can open, never the
      // TV Apps / Non-TV Apps / Favorites split, or a friendly card when there's nothing at all.
      final usable = sections.where((s) => !(s is Category && (s.applications.isEmpty || s.name == 'Favorites'))).toList();
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
    final bool showRecents = continueWatchingActive && _showingRecents;
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
                ExcludeFocus(
                  excluding: showRecents,
                  child: Focus(
                    focusNode: _dockFocusNode,
                    onKeyEvent: continueWatchingActive ? _swapOn(LogicalKeyboardKey.arrowUp, true) : null,
                    child: _swapAnimation(
                      visible: !showRecents && !_topBarFocused,
                      // Far enough to slide the dock off the bottom of the screen, so it needn't fade too.
                      // (A fade would paint the dock once, off-screen, and its frosted backdrop would stay
                      // sampled from there.)
                      hiddenOffset: const Offset(0, 1.6),
                      fade: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        child: HomeDock(
                          key: Key(favorites.id.toString()),
                          category: favorites,
                          applications: favorites.applications,
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
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.nightlight_round, color: Colors.white70, size: 40),
              SizedBox(height: 12),
              Text("Nothing to watch right now", style: TextStyle(color: Colors.white, fontSize: 24)),
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

      // Pass isFirstSection only to the first category found
      bool isFirstSection = !firstCategoryFound;
      if (isFirstSection) firstCategoryFound = true;

      switch (allGrids ? CategoryType.grid : category.type) {
        case CategoryType.row:
          categoryWidget = CategoryRow(
              key: sectionKey,
              category: category,
              applications: category.applications,
              isFirstSection: isFirstSection,
              showTitle: showTitles);
          break;
        case CategoryType.grid:
          categoryWidget = AppsGrid(
              key: sectionKey,
              category: category,
              applications: category.applications,
              isFirstSection: isFirstSection,
              showTitle: showTitles);
          break;
      }

      children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: categoryWidget));
      sectionIdx++;
    }

    if (continueWatchingActive && !cwInserted) {
      final bool isFirstSection = !firstCategoryFound;
      children.add(ContinueWatchingRow(isFirstSection: isFirstSection));
      cwInserted = true;
      firstCategoryFound = true;
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

  Widget _emptyState(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(localizations.loading, style: Theme.of(context).textTheme.titleLarge),
        ],
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
