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

import 'package:flauncher/providers/wallpaper_service.dart';
import 'dart:async';

import 'package:flauncher/app_image_type.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/card_style.dart';
import 'package:flauncher/widgets/focus_highlight.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/home_dock.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/launcher_card_behavior.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../models/category.dart';

class AppCard extends StatefulWidget
{
  final App application;
  final Category category;
  final bool autofocus;
  final void Function(AxisDirection) onMove;
  final VoidCallback onMoveEnd;
  final VoidCallback? onMoveCancel;
  final bool upGoesToTopBar;
  final bool isFirstInRow;
  final bool isLastInRow;

  const AppCard({
    super.key,
    required this.application,
    required this.category,
    required this.autofocus,
    required this.onMove,
    required this.onMoveEnd,
    this.onMoveCancel,
    this.upGoesToTopBar = false,
    this.isFirstInRow = false,
    this.isLastInRow = false,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin, LauncherCardBehavior {
  bool _moving = false;
  final FocusNode _focusNode = FocusNode();

  late Future<(AppImageType, ImageProvider)> _appImageLoadFuture;
  /// The loaded banner or icon, for the info panel.
  ImageProvider? _image;

  late final AppsService _appsService;
  late int _imageRevision;

  @override
  void initState() {
    super.initState();
    _appsService = context.read<AppsService>();
    _imageRevision = _appsService.imageRevision(widget.application.packageName);

    FocusManager.instance.addHighlightModeListener(_focusHighlightModeChanged);
    _appImageLoadFuture = _loadAppBannerOrIcon(_appsService);
    _restorePendingReorderFocus();
  }

  @override
  void didUpdateWidget(AppCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restorePendingReorderFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_focusHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  // A move rebuilds the row; the moved card then takes focus back and stays in move mode.
  void _restorePendingReorderFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appsService = context.read<AppsService>();
      if (appsService.pendingReorderFocusPackage != widget.application.packageName ||
          appsService.pendingReorderFocusCategoryId != widget.category.id) {
        return;
      }
      appsService.clearPendingReorderFocusPackage();
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
      if (!_moving) {
        setState(() => _moving = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only this app's banner or icon changing reloads the image (a custom banner, an app update)
    final int imageRevision =
        context.select<AppsService, int>((s) => s.imageRevision(widget.application.packageName));
    if (imageRevision != _imageRevision) {
      _imageRevision = imageRevision;
      _appImageLoadFuture = _loadAppBannerOrIcon(_appsService);
    }
    final bool showAppNames = context.select<SettingsService, bool>((s) => s.showAppNamesBelowIcons);
    final CardStyle style = CardStyle.of(context.select<SettingsService, String>((s) => s.themes));
    final Color accentColor = context.select<SettingsService, Color>((s) => s.accentColor);
    final bool hideHighlightOutlineOnHomescreen = context.select<SettingsService, bool>((s) => s.hideHighlightOutlineOnHomescreen);
    final bool appHighlightAnimationEnabled = context.select<SettingsService, bool>((s) => s.appHighlightAnimationEnabled);
    final bool appSelectorTransitionAnimationEnabled = context.select<SettingsService, bool>((s) => s.appSelectorTransitionAnimationEnabled);
    final Duration focusDuration = appSelectorTransitionAnimationEnabled ? const Duration(milliseconds: 200) : Duration.zero;

    return FocusKeyboardListener(
      onPressed: (key) => _onPressed(context, key),
      onLongPress: (key) => _onLongPress(context, key),
      builder: (context) {
        final bool shouldHighlight = _shouldHighlight(context);

        return bumpable(pressable(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: RepaintBoundary(
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedContainer(
                      duration: focusDuration,
                      curve: Curves.easeOutBack,
                      transformAlignment: Alignment.center,
                      transform: _scaleTransform(style, shouldHighlight, constraints.maxWidth),
                      child: Material(
                        borderRadius: style.borderRadius,
                        clipBehavior: Clip.antiAlias,
                        elevation: shouldHighlight ? style.focusElevation : 0,
                        shadowColor: shouldHighlight ? style.focusShadowColor(accentColor) : Colors.black,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _notificationBadge(),
                            _tapTarget(context),
                            if (_moving) ..._arrows(),
                            IgnorePointer(
                              child: AnimatedOpacity(
                                duration: focusDuration,
                                curve: Curves.easeInOut,
                                opacity: shouldHighlight ? 0 : 0.10,
                                child: Container(color: Colors.black),
                              ),
                            ),
                            if (shouldHighlight && !hideHighlightOutlineOnHomescreen)
                              FocusHighlight(
                                style: style,
                                accentColor: accentColor,
                                animate: appHighlightAnimationEnabled,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showAppNames)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  widget.application.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        )));
      },
    );
  }

  Widget _notificationBadge() => Selector<NotificationsService, int>(
        selector: (_, service) => service.getNotificationCount(widget.application.packageName),
        builder: (context, count, _) {
          if (count <= 0) return const SizedBox.shrink();
          return Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _tapTarget(BuildContext context) => Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _onPressed(context, LogicalKeyboardKey.enter),
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => _onPressed(context, LogicalKeyboardKey.enter),
          ),
        },
        child: InkWell(
          focusNode: _focusNode,
          // Not while Settings or a panel is open over the home: a card built then (the home's layout changed under
          // it) would take the selection from it. The home lands on its own once it's back on top.
          autofocus: widget.autofocus && (ModalRoute.isCurrentOf(context) ?? true),
          focusColor: Colors.transparent,
          onTap: () => _onPressed(context, LogicalKeyboardKey.enter),
          onLongPress: () => _onLongPress(context, LogicalKeyboardKey.enter),
          onFocusChange: (focused) {
            // Scroll only on gaining focus, so a panel opening over the home doesn't move the page.
            if (!focused) return;
            context.read<WallpaperService?>()?.onAppFocused(widget.application.packageName);
            Scrollable.ensureVisible(
              context,
              // Centred; this also keeps the first section's title clear of the app bar.
              alignment: 0.5,
              curve: Curves.easeInOut,
              duration: const Duration(milliseconds: 100)
            );
          },
          child: _appImage(),
        ),
      );

  Future<(AppImageType, ImageProvider)> _loadAppBannerOrIcon(AppsService service) async {
    Uint8List bytes = Uint8List(0);

    bytes = await service.getAppBanner(widget.application.packageName);
    AppImageType type = AppImageType.banner;

    if (bytes.isEmpty) {
      type = AppImageType.icon;
      bytes = await service.getAppIcon(widget.application.packageName);
    }

    final image = MemoryImage(bytes);
    _image = image;
    return (type, image);
  }

  Widget _appImage()
  {
    App app = widget.application;

    return FutureBuilder(
      future: _appImageLoadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final record = snapshot.data;
          if (record == null) return const SizedBox();

          if (record.$1 == AppImageType.banner) {
            return Ink.image(
              image: record.$2,
              fit: BoxFit.cover,
              onImageError: (e, s) => debugPrint('AppCard banner image error: $e'),
            );
          }
          else {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Ink.image(
                      image: record.$2,
                      height: double.maxFinite,
                      onImageError: (e, s) => debugPrint('AppCard icon image error: $e'),
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        app.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        }
        else if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                app.name,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              )
            ),
          );
        }
        else {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 0, width: 16),
                  Text(AppLocalizations.of(context)!.loading)
                ],
              ),
            ),
          );
        }
      }
    );
  }

  void _focusHighlightModeChanged(FocusHighlightMode mode)
  {
    setState(() { });
  }

  bool _shouldHighlight(BuildContext context)
  {
    return FocusManager.instance.highlightMode == FocusHighlightMode.traditional && Focus.of(context).hasFocus;
  }

  Matrix4 _scaleTransform(CardStyle style, bool highlighted, double maxWidth) {
    final double scale = highlighted && !_moving ? style.focusScaleFor(maxWidth) : 1.0;
    return Matrix4.diagonal3Values(scale, scale, 1.0);
  }

  List<Widget> _arrows() {
    final arrows = <Widget>[
      _arrow(Alignment.centerLeft, Icons.keyboard_arrow_left, () {
        widget.onMove(AxisDirection.left);
      }),
      _arrow(Alignment.centerRight, Icons.keyboard_arrow_right, () {
        widget.onMove(AxisDirection.right);
      }),
    ];
    
    // Only show Up/Down arrows for grid layouts
    if (widget.category.type == CategoryType.grid) {
      arrows.add(_arrow(Alignment.topCenter, Icons.keyboard_arrow_up, () {
        widget.onMove(AxisDirection.up);
      }));
      arrows.add(_arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down, () {
        widget.onMove(AxisDirection.down);
      }));
    }

    return arrows;
  }

  Widget _arrow(Alignment alignment, IconData icon, VoidCallback onTap) =>
      ExcludeFocus(
        child: Align(
          alignment: alignment,
          child: Ink(
            decoration: ShapeDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.8),
              shape: const CircleBorder()
            ),
            child: SizedBox(
              height: 36,
              width: 36,
              child: IconButton(
                icon: Icon(icon, size: 24),
                onPressed: onTap,
                padding: const EdgeInsets.all(0)
              )
            )
          )
        ),
      );

  DateTime? _lastMoveTime;

  KeyEventResult _onPressed(BuildContext context, LogicalKeyboardKey? key) {
    if (_moving) {
      return _onMovingKey(context, key);
    }
    if (key == null || AppCardKeys.validationKeys.contains(key)) {
      pressThenRun(() => context.read<AppsService>().launchApp(widget.application));
      return KeyEventResult.handled;
    }
    return onEdgeKey(
          key,
          isFirstInRow: widget.isFirstInRow,
          isLastInRow: widget.isLastInRow,
          upGoesToTopBar: widget.upGoesToTopBar,
        ) ??
        KeyEventResult.ignored;
  }

  KeyEventResult _onMovingKey(BuildContext context, LogicalKeyboardKey? key) {
    if (AppCardKeys.isArrowKey(key)) {
      final now = DateTime.now();
      if (_lastMoveTime != null && now.difference(_lastMoveTime!) < const Duration(milliseconds: 50)) {
        return KeyEventResult.handled;
      }
      _lastMoveTime = now;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      // In the dock only the dock's own row follows the card: the page stays put, with the first screen at the top
      final ScrollableState? dockRow =
          context.findAncestorWidgetOfExactType<HomeDock>() != null ? Scrollable.maybeOf(context) : null;
      final RenderObject? card = context.findRenderObject();
      if (dockRow != null && card != null) {
        dockRow.position.ensureVisible(card,
            alignment: 0.1, duration: const Duration(milliseconds: 100), curve: Curves.easeInOut);
        return;
      }
      // Centred, as when the card is selected: near the top instead, the top row would scroll its title under the
      // top bar
      Scrollable.ensureVisible(context,
          alignment: 0.5, duration: const Duration(milliseconds: 100), curve: Curves.easeInOut);
    });
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMove(AxisDirection.left);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.onMove(AxisDirection.up);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMove(AxisDirection.right);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.onMove(AxisDirection.down);
    } else if (AppCardKeys.validationKeys.contains(key)) {
      setState(() => _moving = false);
      widget.onMoveEnd();
    } else if (AppCardKeys.cancelKeys.contains(key)) {
      setState(() => _moving = false);
      widget.onMoveCancel?.call();
      context.read<LauncherState>().suppressBackNavigation();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onLongPress(BuildContext context, LogicalKeyboardKey? key) {
    if (!_moving && (key == null || AppCardKeys.longPressableKeys.contains(key))) {
      _showPanel(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The app's menu. Opens in kids profiles too: arranging their own home is theirs, and the actions a parent
  /// controls ask for the parent PIN themselves (see ApplicationInfoPanel).
  Future<void> _showPanel(BuildContext context) async {
    final result = await showDialog<ApplicationInfoPanelResult>(
      context: context,
      builder: (context) => ApplicationInfoPanel(
        category: widget.category,
        application: widget.application,
        image: _image,
      ),
    );
    if (result == ApplicationInfoPanelResult.reorderApp && mounted) {
      setState(() => _moving = true);
    }
  }
}
