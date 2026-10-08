import 'package:flauncher/actions.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/inputs_panel.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'daily_data_usage_widget.dart';
import 'date_time_widget.dart';
import 'focusable_tap.dart';
import '../providers/home_search.dart';
import 'weather_status_bar_widget.dart';

class FocusAwareAppBar extends StatefulWidget implements PreferredSizeWidget
{
  const FocusAwareAppBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return FocusAwareAppBarState();
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

class FocusAwareAppBarState extends State<FocusAwareAppBar>
{
  bool _focused = false;
  late FocusNode _profileFocusNode;
  late FocusNode _inputsFocusNode;
  late FocusNode _notificationsFocusNode;
  late FocusNode _weatherFocusNode;

  @visibleForTesting
  FocusNode get profileFocusNode => _profileFocusNode;

  @override
  void initState() {
    super.initState();
    _profileFocusNode = FocusNode();
    _inputsFocusNode = FocusNode();
    _notificationsFocusNode = FocusNode();
    _weatherFocusNode = FocusNode();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _profileFocusNode.dispose();
    _inputsFocusNode.dispose();
    _notificationsFocusNode.dispose();
    _weatherFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  late final FocusNode _searchFocusNode;

  /// Focuses the search button (or the current search's pill).
  void focusSearch() {
    _searchFocusNode.requestFocus();
  }

  /// Focuses the top bar's leftmost button, the profile button.
  void focusTopBar() {
    _profileFocusNode.requestFocus();
  }

  /// Opens Settings. In kids profiles its risky parts ask for the parent PIN themselves (settings_lock.dart).
  Future<void> openSettings() async {
    showDialog(context: context, builder: (_) => const SettingsPanel());
  }

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, bool>(
      selector: (_, settings) => settings.autoHideAppBarEnabled,
      builder: (context, autoHide, widget) {
        if (autoHide) {
          return Focus(
            canRequestFocus: false,
            child: AnimatedContainer(
              curve: Curves.decelerate,
              duration: Duration(milliseconds: 150),
              height: _focused ? kToolbarHeight : 0,
              child: widget!
            ),
            onFocusChange: (hasFocus) {
              this.setState(() {
                _focused = hasFocus;
              });
            }
          );
        }

        return widget!;
      },
      // Right past the last button opens the Home Assistant panel (when it's on), as it does from the dock.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Down goes back to the home screen's first row (the home decides which: see LeaveTopBarIntent)
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && event is! KeyUpEvent) {
            return Actions.maybeInvoke(context, const LeaveTopBarIntent()) == true
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          }
          if (event.logicalKey != LogicalKeyboardKey.arrowRight || event is KeyUpEvent) return KeyEventResult.ignored;
          final focused = FocusManager.instance.primaryFocus;
          if (focused == null || focused.focusInDirection(TraversalDirection.right)) return KeyEventResult.handled;
          if (event is KeyDownEvent && context.read<SettingsService>().haPanelEnabled) {
            Actions.maybeInvoke(context, const OpenHaPanelIntent());
          }
          return KeyEventResult.handled;
        },
        child: RepaintBoundary(
        child: AppBar(
          // Line the profile circle up with the left edge of the app tiles below
          // (sections indent 16 + 8 card margin + 8 tile inset = 32dp).
          titleSpacing: 32,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          // Left side: profile, inputs, notifications. There's no Settings button:
          // pressing Left at the left edge (here or on the home screen) opens Settings.
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) {
                  if (event.logicalKey != LogicalKeyboardKey.arrowLeft || event is KeyUpEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event is KeyDownEvent) openSettings();
                  return KeyEventResult.handled;
                },
                child: _ProfileButton(focusNode: _profileFocusNode),
              ),
              Selector<SettingsService, bool>(
                selector: (_, settings) => settings.showInputsWidgetInStatusBar,
                builder: (context, showInputs, _) => showInputs
                  ? Consumer<TvInputsService>(
                      builder: (context, tvInputsService, _) {
                        if (tvInputsService.hasInputs) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 16),
                              _FocusableIconButton(
                                icon: Icons.tv,
                                focusNode: _inputsFocusNode,
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => const InputsPanel(),
                                ),
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    )
                  : const SizedBox.shrink(),
              ),
              Selector<SettingsService, (bool, bool)>(
                selector: (_, settings) => (
                  settings.showNotificationsWidgetInStatusBar,
                  settings.autoHideNotificationsWidget
                ),
                builder: (context, settingsState, _) {
                  final (showNotifications, autoHide) = settingsState;
                  return showNotifications
                    ? Consumer<NotificationsService>(
                        builder: (context, notificationsService, _) {
                          if (notificationsService.hasPermission) {
                            final count = notificationsService.notifications.length;
                            if (autoHide && count == 0) {
                              return const SizedBox.shrink();
                            }
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 16),
                                _FocusableIconButton(
                                  icon: count > 0 ? Icons.notifications_active : Icons.notifications,
                                  focusNode: _notificationsFocusNode,
                                  badgeCount: count,
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => const NotificationsPanel(),
                                  ),
                                ),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      )
                    : const SizedBox.shrink();
                },
              ),
              const SizedBox(width: 16),
              // Search: the magnifier, or the current search as a white pill (press to edit it)
              Builder(builder: (context) {
                final query = context.select<HomeSearch?, String>((s) => s?.query ?? "");
                return query.isEmpty
                    ? _FocusableIconButton(
                        key: const Key("statusbar_search"),
                        focusNode: _searchFocusNode,
                        icon: Icons.search,
                        onPressed: () => Actions.maybeInvoke(context, const StartSearchIntent()),
                      )
                    : _SearchPill(
                        focusNode: _searchFocusNode,
                        query: query,
                        onPressed: () => Actions.maybeInvoke(context, const StartSearchIntent()),
                      );
              }),
              const SizedBox(width: 16),
              // Data usage widget
              Selector<SettingsService, bool>(
                selector: (_, settings) => settings.showDataWidgetInStatusBar,
                builder: (context, showData, _) => showData
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      child: const DailyDataUsageWidget(),
                    )
                  : const SizedBox.shrink(),
              ),
            ],
          ),
          // Right side: Weather and Date/Time
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer<WeatherService>(
                    builder: (context, weatherService, _) {
                      return Selector<SettingsService, bool>(
                        selector: (_, settings) => settings.showWeatherInStatusBar,
                        builder: (context, showWeather, _) {
                          if (showWeather && weatherService.hasWeather) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WeatherStatusBarWidget(focusNode: _weatherFocusNode),
                                const SizedBox(width: 12),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  ),
                  Selector<SettingsService,
                      ({
                        bool showDateInStatusBar,
                        bool showTimeInStatusBar,
                        String dateFormat,
                        String timeFormat })>(
                    selector: (context, service) => (
                    showDateInStatusBar: service.showDateInStatusBar,
                    showTimeInStatusBar: service.showTimeInStatusBar,
                    dateFormat: service.dateFormat,
                    timeFormat: service.timeFormat),
                    builder: (context, dateTimeSettings, _) {
                      // Define standard text style
                      const textStyle = TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)
                        ],
                      );

                      if (!dateTimeSettings.showDateInStatusBar && !dateTimeSettings.showTimeInStatusBar) {
                        return const SizedBox.shrink();
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Date
                            if (dateTimeSettings.showDateInStatusBar)
                              DateTimeWidget(
                                dateTimeSettings.dateFormat,
                                key: const Key("statusbar_date"),
                                textStyle: textStyle,
                              ),
                            
                            if (dateTimeSettings.showDateInStatusBar && dateTimeSettings.showTimeInStatusBar)
                                const SizedBox(width: 12),

                            // Clock
                            if (dateTimeSettings.showTimeInStatusBar)
                              DateTimeWidget(
                                dateTimeSettings.timeFormat,
                                key: const Key("statusbar_clock"),
                                textStyle: textStyle.copyWith(fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Opens Google TV's profile chooser and shows the active profile's name.
class _ProfileButton extends StatelessWidget {
  final FocusNode? focusNode;

  const _ProfileButton({this.focusNode});

  @override
  Widget build(BuildContext context) => _FocusableIconButton(
        icon: Icons.person,
        focusNode: focusNode,
        image: context.select<ProfileService?, Uint8List?>((p) => p?.activeProfileAvatar),
        label: context.select<ProfileService?, String?>((p) => p?.activeProfileName),
        onPressed: () => FLauncherChannel().openProfileChooser(),
      );
}

/// A dark circle with a filled icon (accent when focused); the label, if any, sits beside it.
class _FocusableIconButton extends StatelessWidget {
  static const double _circleSize = 44;

  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final int badgeCount;
  final String? label;
  /// Shown in the circle instead of the icon (a profile photo, PNG).
  final Uint8List? image;

  const _FocusableIconButton(
      {super.key, required this.icon, required this.onPressed, this.focusNode, this.badgeCount = 0, this.label, this.image});

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      focusNode: focusNode,
      onPressed: onPressed,
      splashShape: const StadiumBorder(),
      builder: (context, focused) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            isLabelVisible: badgeCount > 0,
            label: Text(badgeCount.toString(), style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
            offset: const Offset(-2, 2),
            child: Container(
              width: _circleSize,
              height: _circleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused ? Theme.of(context).colorScheme.primary : const Color(0xE6202024),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
              ),
              // A photo sits inside the accent ring when focused
              padding: image != null && focused ? const EdgeInsets.all(3) : EdgeInsets.zero,
              child: image != null
                  ? ClipOval(child: Image.memory(image!, fit: BoxFit.cover, gaplessPlayback: true))
                  : Icon(icon, size: 26, color: Colors.white),
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 12),
            Text(
              label!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

/// The current search in the top bar: a white pill with the query, as HearthTube shows its selected tab. Pressing
/// it reopens the search box to change the search.
class _SearchPill extends StatelessWidget {
  final String query;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  const _SearchPill({required this.query, required this.onPressed, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return FocusableTap(
      focusNode: focusNode,
      onPressed: onPressed,
      builder: (context, focused) => Container(
        height: 44,
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.only(left: 12, right: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: focused ? accent : Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search, size: 22, color: Colors.black87),
          const SizedBox(width: 8),
          Flexible(
            child: Text(query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }
}
