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
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/home_dock.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/settings_service.dart';
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

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusMoved);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusMoved);
    _firstScreenFocusNode.dispose();
    _belowDockFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Cards centre themselves vertically when focused, which would scroll the dock layout's
  /// first screen partway off the top. While focus is on that screen, keep the page at the top.
  void _onFocusMoved() {
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

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      MoveFocusToSettingsIntent: CallbackAction<MoveFocusToSettingsIntent>(
        onInvoke: (_) => _appBarKey.currentState?.focusSettings(),
      ),
    },
    child: FocusTraversalGroup(
      policy: RowByRowTraversalPolicy(),
      child: Stack(
        children: [
          RepaintBoundary(
            child: Consumer<WallpaperService>(
              builder: (_, wallpaperService, __) => _wallpaper(context, wallpaperService)
            ),
          ),
          // Below the dock, the wallpaper blurs so the rows of apps stand out (from arclauncher).
          Selector2<SettingsService, WallpaperService, bool>(
            selector: (_, settings, wallpaper) => settings.blurWallpaperBelowDock && wallpaper.focusedAppColor == null,
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
              replacement: const Center(
                child: AlternativeLauncherView()
              ),
              visible: state.launcherVisible
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: FocusAwareAppBar(key: _appBarKey),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Consumer<AppsService>(
                  builder: (context, appsService, _) {
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
                                builder: (context, constraints) =>
                                  SingleChildScrollView(
                                    controller: _scrollController,
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _home(
                                            appsService.launcherSections,
                                            viewportHeight: constraints.maxHeight,
                                            dockEnabled: cwSettings.dock,
                                            continueWatchingActive:
                                                cwSettings.show &&
                                                hasContinuingPrograms,
                                            continueWatchingOrder:
                                                cwSettings.order),
                                      ],
                                    ),
                                  ),
                              ),
                            ),
                    );
                    }
                    else {
                      return _emptyState(context);
                    }
                  }
                )
              )
            )
          )
        ]
      )
    ),
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
    if (favorites == null) {
      return _sections(sections,
          continueWatchingActive: continueWatchingActive, continueWatchingOrder: continueWatchingOrder);
    }

    // Empty sections (often "Non-TV Apps") are left out below the dock; they'd only say "This category is empty".
    // With a single section left, its heading is dropped too. Everything below the dock wraps as a grid,
    // so a "row" section doesn't become one long sideways-scrolling strip.
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (continueWatchingActive) const ContinueWatchingRow(isFirstSection: true),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: HomeDock(
                    key: Key(favorites.id.toString()),
                    category: favorites,
                    applications: favorites.applications,
                    isFirstSection: !continueWatchingActive,
                  ),
                ),
              ],
            ),
          ),
        ),
        Focus(
          focusNode: _belowDockFocusNode,
          child: _sections(belowDock, firstCategoryAlreadyFound: true,
              showTitles: belowDock.whereType<Category>().length > 1, allGrids: true),
        ),
      ],
    );
  }

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
              showTitle: showTitles
          );
          break;
        case CategoryType.grid:
          categoryWidget = AppsGrid(
              key: sectionKey,
              category: category,
              applications: category.applications,
              isFirstSection: isFirstSection,
              showTitle: showTitles
          );
          break;
      }

      children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: categoryWidget
      ));
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
        width: physicalSize.width
      );
    }
    else {
      background = _CachedGradientBackground(key: const Key("background"), gradient: wallpaperService.gradient.gradient);
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
