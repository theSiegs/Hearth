import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/actions.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/card_style.dart';
import 'package:flauncher/widgets/focus_highlight.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/launcher_card_behavior.dart';
import 'package:flauncher/widgets/watch_next_info_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/continue_watching_grid_page.dart';
import 'package:flauncher/widgets/search/title_card.dart';

class ContinueWatchingRow extends StatefulWidget {
  final bool isFirstSection;

  const ContinueWatchingRow({
    super.key,
    this.isFirstSection = true,
  });

  @override
  State<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

/// "S3 E12 · 14 min left · Disney+": what's shown under a program's name, above the row and in the grid.
String watchNextDetail(WatchNextProgram program, AppsService appsService) {
  final description = program.description.trim();
  final parts = <String>[
    if (description.isNotEmpty && description.toLowerCase() != program.title.trim().toLowerCase()) description,
  ];
  if (program.duration > 0 && program.playbackPosition > 0 && program.playbackPosition < program.duration) {
    final minutes = ((program.duration - program.playbackPosition) / 60000).ceil();
    parts.add(minutes >= 60 ? "${minutes ~/ 60} h ${minutes % 60} min left" : "$minutes min left");
  }
  final app = appsService.applications.where((a) => a.packageName == program.packageName).firstOrNull;
  if (app != null) parts.add(app.name);
  return parts.join(" \u00b7 ");
}

class _ContinueWatchingRowState extends State<ContinueWatchingRow> {
  /// The focused program, named above the cards (as HearthTube and search do).
  final ValueNotifier<WatchNextProgram?> _focused = ValueNotifier(null);

  @override
  void dispose() {
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFirstSection = widget.isFirstSection;
    final settingsService = Provider.of<SettingsService>(context);
    if (!settingsService.showContinueWatching) {
      return const SizedBox.shrink();
    }

    return Consumer2<WatchNextService, AppsService>(
      builder: (context, watchNextService, appsService, _) {
        if (!watchNextService.hasPermission) {
          return const SizedBox.shrink();
        }

        List<WatchNextProgram> programs = watchNextService.visiblePrograms(settingsService, appsService);

        // "See all" shows every one, beyond the row's limit
        final allPrograms = programs;
        final maxItems = settingsService.continueWatchingMaxItems;
        if (maxItems > 0 && programs.length > maxItems) {
          programs = programs.sublist(0, maxItems);
        }

        if (programs.isEmpty) {
          return const SizedBox.shrink();
        }

        double cardHeight;
        final int? customHeight = int.tryParse(settingsService.continueWatchingCardSize);
        if (customHeight != null) {
          cardHeight = customHeight.toDouble();
        } else {
          switch (settingsService.continueWatchingCardSize) {
            case 'compact':
              cardHeight = 112.0;
              break;
            case 'large':
              cardHeight = 157.0;
              break;
            case 'normal':
            default:
              cardHeight = 135.0;
              break;
          }
        }
        final double rowHeight = cardHeight + 36.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Selector<SettingsService, bool>(
                selector: (context, service) => service.showCategoryTitles,
                builder: (context, showCategoryTitles, _) {
                  final shadow = [const Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];
                  return ValueListenableBuilder<WatchNextProgram?>(
                    valueListenable: _focused,
                    builder: (context, focused, _) {
                      final program = programs.contains(focused) ? focused! : programs.first;
                      final detail = watchNextDetail(program, appsService);
                      return Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showCategoryTitles)
                              Text(
                                AppLocalizations.of(context)!.continueWatching.toUpperCase(),
                                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                                    color: Colors.white70, letterSpacing: 1.0, shadows: shadow),
                              ),
                            Text(
                              program.title.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall!
                                  .copyWith(fontWeight: FontWeight.w700, shadows: shadow),
                            ),
                            Text(
                              detail.isEmpty ? " " : detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge!
                                  .copyWith(color: Colors.white70, shadows: shadow),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              SizedBox(
                height: rowHeight,
                child: ListView.builder(
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.all(8),
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  itemCount: programs.length + 1,
                  itemBuilder: (context, index) {
                    // Last: "See all", every program in a grid
                    if (index == programs.length) {
                      return Padding(
                        key: const ValueKey("see_all"),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onKeyEvent: (_, event) {
                              // All the way right still opens the Home Assistant panel when it's on
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.arrowRight &&
                                  context.read<SettingsService>().haPanelEnabled) {
                                Actions.maybeInvoke(context, const OpenHaPanelIntent());
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: MoreCard(
                              label: "See all",
                              detail: "${allPrograms.length} in progress",
                              height: cardHeight,
                              onPressed: () => ContinueWatchingGridPage.open(context, allPrograms),
                            ),
                          ),
                        ),
                      );
                    }
                    final program = programs[index];
                    return Padding(
                      key: ValueKey(program.id),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: RepaintBoundary(
                        child: WatchNextCard(
                          program: program,
                          appsService: appsService,
                          watchNextService: watchNextService,
                          upGoesToTopBar: isFirstSection,
                          isFirstInRow: index == 0,
                          isLastInRow: false,
                          autofocus: index == 0,
                          onFocused: (p) => _focused.value = p,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WatchNextCard extends StatefulWidget {
  final WatchNextProgram program;
  final AppsService appsService;
  final WatchNextService watchNextService;
  final bool upGoesToTopBar;
  final bool isFirstInRow;
  final bool isLastInRow;
  final bool autofocus;

  /// Called when this card gains focus (the row names it above the cards).
  final ValueChanged<WatchNextProgram>? onFocused;

  const WatchNextCard({
    super.key,
    required this.program,
    required this.appsService,
    required this.watchNextService,
    this.upGoesToTopBar = true,
    this.isFirstInRow = false,
    this.isLastInRow = false,
    this.autofocus = false,
    this.onFocused,
  });

  @override
  State<WatchNextCard> createState() => _WatchNextCardState();
}

class _WatchNextCardState extends State<WatchNextCard> with SingleTickerProviderStateMixin, LauncherCardBehavior {
  late final FocusNode _focusNode;
  Uint8List? _appIconBytes;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    FocusManager.instance.addHighlightModeListener(_focusHighlightModeChanged);
    _loadAppIcon();
  }

  void _focusHighlightModeChanged(FocusHighlightMode mode) {
    setState(() {});
  }

  bool _shouldHighlight() {
    return FocusManager.instance.highlightMode == FocusHighlightMode.traditional && _focusNode.hasFocus;
  }

  Future<void> _loadAppIcon() async {
    try {
      final bytes = await widget.appsService.getAppIcon(widget.program.packageName);
      if (mounted && bytes.isNotEmpty) {
        setState(() => _appIconBytes = bytes);
      }
    } catch (_) {
      // Without its icon the card still shows the program.
    }
  }

  @override
  void didUpdateWidget(covariant WatchNextCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.program.packageName != widget.program.packageName) {
      _loadAppIcon();
    }
  }

  void _onFocusChange() {
    setState(() {});
    if (_focusNode.hasFocus) {
      widget.onFocused?.call(widget.program);
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 100),
      );
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_focusHighlightModeChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _launch() => pressThenRun(() => widget.watchNextService.launch(widget.program));

  Future<void> _showPanel() async {
    final bool allowed = await requireParent(context);
    if (!allowed || !mounted) return;
    showDialog(
      context: context,
      builder: (context) => WatchNextInfoPanel(
        program: widget.program,
        watchNextService: widget.watchNextService,
        appsService: widget.appsService,
        appIconBytes: _appIconBytes,
      ),
    );
  }

  KeyEventResult _onPressed(LogicalKeyboardKey key) {
    if (AppCardKeys.validationKeys.contains(key)) {
      _launch();
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

  KeyEventResult _onLongPress(LogicalKeyboardKey key) {
    if (AppCardKeys.longPressableKeys.contains(key) || AppCardKeys.menuKeys.contains(key)) {
      _showPanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final CardStyle style = CardStyle.of(context.select<SettingsService, String>((s) => s.themes));
    final Color accentColor = context.select<SettingsService, Color>((s) => s.accentColor);
    final bool appHighlightAnimationEnabled = context.select<SettingsService, bool>((s) => s.appHighlightAnimationEnabled);
    final bool hideHighlightOutlineOnHomescreen = context.select<SettingsService, bool>((s) => s.hideHighlightOutlineOnHomescreen);
    final bool appSelectorTransitionAnimationEnabled = context.select<SettingsService, bool>((s) => s.appSelectorTransitionAnimationEnabled);
    final String cardSize = context.select<SettingsService, String>((s) => s.continueWatchingCardSize);
    final bool showProgress = context.select<SettingsService, bool>((s) => s.continueWatchingShowProgress);
    final bool showPercentage = context.select<SettingsService, bool>((s) => s.continueWatchingShowPercentage);
    final bool showDescription = context.select<SettingsService, bool>((s) => s.continueWatchingShowDescription);
    final Duration focusDuration = appSelectorTransitionAnimationEnabled ? const Duration(milliseconds: 200) : Duration.zero;

    double cardWidth;
    double cardHeight;
    final int? customHeight = int.tryParse(cardSize);
    if (customHeight != null) {
      cardHeight = customHeight.toDouble();
      cardWidth = (cardHeight * 16 / 9).roundToDouble();
    } else {
      switch (cardSize) {
        case 'compact':
          cardWidth = 200.0;
          cardHeight = 112.0;
          break;
        case 'large':
          cardWidth = 280.0;
          cardHeight = 157.0;
          break;
        case 'normal':
        default:
          cardWidth = 240.0;
          cardHeight = 135.0;
          break;
      }
    }

    final bool shouldHighlight = _shouldHighlight();
    final double scale = shouldHighlight ? style.focusScaleFor(cardWidth) : 1.0;
    final bool hasPoster = widget.program.posterBytes?.isNotEmpty ?? false;
    final String title = widget.program.title.trim();
    final String description = widget.program.description.trim();
    final bool showsDescription =
        showDescription && description.isNotEmpty && description.toLowerCase() != title.toLowerCase();

    double progress = 0;
    if (widget.program.duration > 0 && widget.program.playbackPosition >= 0) {
      progress = widget.program.playbackPosition / widget.program.duration;
      if (progress > 1.0) progress = 1.0;
    }

    return FocusKeyboardListener(
      onPressed: _onPressed,
      onLongPress: _onLongPress,
      builder: (context) => bumpable(InkWell(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: _launch,
        onLongPress: _showPanel,
        child: pressable(AnimatedContainer(
          duration: focusDuration,
          curve: Curves.easeOutBack,
          width: cardWidth,
          height: cardHeight,
          transform: Matrix4.diagonal3Values(scale, scale, 1.0),
          transformAlignment: Alignment.center,
          child: Material(
            borderRadius: style.borderRadius,
            clipBehavior: Clip.antiAlias,
            elevation: shouldHighlight ? style.focusElevation : 0,
            shadowColor: shouldHighlight ? style.focusShadowColor(accentColor) : Colors.black,
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasPoster)
                  Image.memory(
                    widget.program.posterBytes!,
                    fit: BoxFit.cover,
                    cacheWidth: (cardWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                // Card surface: a dark gradient, or a scrim over the poster so the text stays readable
                Container(
                  decoration: BoxDecoration(
                    borderRadius: style.borderRadius,
                    gradient: hasPoster
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.3, 0.55, 1.0],
                            colors: [
                              Colors.black.withOpacity(0.35),
                              Colors.black.withOpacity(0.05),
                              Colors.black.withOpacity(0.45),
                              Colors.black.withOpacity(0.92),
                            ],
                          )
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF141517),
                              Color(0xFF090A0B),
                            ],
                          ),
                    border: Border.all(
                      color: shouldHighlight ? Colors.transparent : Colors.white.withOpacity(0.06),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // App icon and progress badge
                      Row(
                        children: [
                          if (_appIconBytes != null)
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.memory(
                                  _appIconBytes!,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.low,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (showPercentage && progress > 0)
                            Container(
                              // Over poster art the badge needs its own backing to stay readable.
                              padding: hasPoster
                                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                                  : EdgeInsets.zero,
                              decoration: hasPoster
                                  ? BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(6),
                                    )
                                  : null,
                              child: Text(
                                '${(progress * 100).round()}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: accentColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                        ),
                        maxLines: showsDescription ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showsDescription) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // With a poster the text sits at the bottom, clear of any title logo in the art.
                      if (hasPoster) const SizedBox(height: 8) else const Spacer(),
                      if (showProgress && progress > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                            minHeight: 3.5,
                          ),
                        )
                      else
                        const SizedBox(height: 3.5),
                    ],
                  ),
                ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: focusDuration,
                    curve: Curves.easeInOut,
                    opacity: shouldHighlight ? 0 : 0.10,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: style.borderRadius,
                        color: Colors.black,
                      ),
                    ),
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
        )),
      )),
    );
  }
}
