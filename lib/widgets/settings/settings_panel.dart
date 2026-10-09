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

import 'package:flauncher/widgets/settings/updates_page.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flauncher/widgets/settings/family_apps_page.dart';
import 'package:flauncher/widgets/settings/profile_pairing_page.dart';
import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flauncher/widgets/settings/side_panel_overlay.dart';
import 'package:flauncher/widgets/settings/applications_panel_page.dart';
import 'package:flauncher/widgets/settings/launcher_sections_panel_page.dart';
import 'package:flauncher/widgets/settings/gradient_panel_page.dart';
import 'package:flauncher/widgets/settings/launcher_section_panel_page.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flauncher/widgets/settings/status_bar_panel_page.dart';
import 'package:flauncher/widgets/settings/wallpaper_panel_page.dart';
import 'package:flauncher/widgets/settings/data_usage_period_page.dart';
import 'package:flauncher/widgets/settings/back_button_action_page.dart';
import 'package:flauncher/widgets/settings/date_time_format_page.dart';
import 'package:flauncher/widgets/settings/app_details_page.dart';
import 'package:flauncher/widgets/settings/accent_color_page.dart';
import 'package:flauncher/widgets/settings/animations_sound_page.dart';
import 'package:flauncher/widgets/settings/home_screen_settings_page.dart';
import 'package:flauncher/widgets/settings/system_settings_page.dart';
import 'package:flauncher/widgets/settings/card_style_page.dart';
import 'package:flauncher/widgets/settings/dock_labels_page.dart';
import 'package:flauncher/widgets/settings/profiles_settings_page.dart';
import 'package:flauncher/widgets/settings/settings_lock.dart';
import 'package:flauncher/widgets/settings/look_settings_page.dart';
import 'package:flauncher/widgets/settings/remote_search_settings_page.dart';
import 'package:flauncher/widgets/settings/backup_restore_page.dart';
import 'package:flauncher/widgets/settings/app_language_page.dart';
import 'package:flauncher/widgets/settings/blocked_notifications_page.dart';
import 'package:flauncher/widgets/settings/tv_power_settings_page.dart';
import 'package:flauncher/widgets/settings/notifications_settings_page.dart';
import 'package:flauncher/widgets/settings/continue_watching_settings_page.dart';
import 'package:flauncher/widgets/settings/continue_watching_card_size_page.dart';
import 'package:flauncher/widgets/settings/continue_watching_max_items_page.dart';
import 'package:flauncher/widgets/settings/continue_watching_apps_page.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

class SettingsPanel extends StatefulWidget {
  final String? initialRoute;

  /// Opens on this app's Profile Pairing page (Profile Pairing's "Change PIN" when a saved PIN wasn't taken).
  final String? openProfilePinsFor;

  const SettingsPanel({super.key, this.initialRoute, this.openProfilePinsFor});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<bool> _unlocked = ValueNotifier(false);
  ProfileService? _profiles;
  String? _profileKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profiles = context.read<ProfileService?>();
    if (profiles != _profiles) {
      _profiles?.removeListener(_onProfileChanged);
      _profiles = profiles;
      _profileKey = profiles?.activeProfileKey;
      profiles?.addListener(_onProfileChanged);
    }
  }

  /// A parent's unlock is for the profile it was given in: another profile (Profiles > Switch profile, with the
  /// panel still open) starts locked again, back on the first page.
  void _onProfileChanged() {
    final key = _profiles?.activeProfileKey;
    if (key == null || key == _profileKey) return;
    _profileKey = key;
    if (!_unlocked.value) return;
    _unlocked.value = false;
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _profiles?.removeListener(_onProfileChanged);
    _unlocked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final poppedInside = await _navigatorKey.currentState!.maybePop();
        if (!poppedInside && context.mounted) Navigator.of(context).pop();
      },
      child: SidePanelOverlay(
        width: 350,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onArrowAtEdge,
          child: SettingsUnlock(
            notifier: _unlocked,
            child: Navigator(
              key: _navigatorKey,
              initialRoute: widget.openProfilePinsFor != null
                  ? ProfilePairingPage.routeName
                  : widget.initialRoute ?? SettingsPanelPage.routeName,
              onGenerateRoute: (settings) {
                switch (settings.name) {
                  case SettingsPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const SettingsPanelPage());
                  case SystemSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const SystemSettingsPage());
                  case HomeScreenSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const HomeScreenSettingsPage());
                  case WallpaperPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const WallpaperPanelPage());
                  case StatusBarPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const StatusBarPanelPage());
                  case GradientPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const GradientPanelPage());
                  case ApplicationsPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const ApplicationsPanelPage());
                  case LauncherSectionsPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const LauncherSectionsPanelPage());
                  case LauncherSectionPanelPage.routeName:
                    return _FastPageRoute(
                        builder: (_) => LauncherSectionPanelPage(sectionIndex: settings.arguments as int?));
                  case DataUsagePeriodPage.routeName:
                    return _FastPageRoute(builder: (_) => const DataUsagePeriodPage());
                  case BackButtonActionPage.routeName:
                    return _FastPageRoute(builder: (_) => const BackButtonActionPage());
                  case DateTimeFormatPage.routeName:
                    return _FastPageRoute(builder: (_) => const DateTimeFormatPage());
                  case AnimationsSoundPage.routeName:
                    return _FastPageRoute(builder: (_) => const AnimationsSoundPage());
                  case CardStylePage.routeName:
                    return _FastPageRoute(builder: (_) => const CardStylePage());
                  case DockLabelsPage.routeName:
                    return _FastPageRoute(builder: (_) => const DockLabelsPage());
                  case AccentColorPage.routeName:
                    return _FastPageRoute(builder: (_) => const AccentColorPage());
                  case ProfilePairingPage.routeName:
                    return _FastPageRoute(builder: (_) => ProfilePairingPage(openApp: widget.openProfilePinsFor));
                  case ProfilePairingAppPage.routeName:
                    return _FastPageRoute(
                        builder: (_) => ProfilePairingAppPage(app: settings.arguments as Map<dynamic, dynamic>));
                  case SetupChecklistPage.routeName:
                    return _FastPageRoute(builder: (_) => const SetupChecklistPage());
                  case FamilyAppsPage.routeName:
                    return _FastPageRoute(builder: (_) => const FamilyAppsPage());
                  case UpdatesPage.routeName:
                    return _FastPageRoute(builder: (_) => const UpdatesPage());
                  case HomeAssistantPage.routeName:
                    return _FastPageRoute(builder: (_) => const HomeAssistantPage());
                  case RemoteButtonsPage.routeName:
                    return _FastPageRoute(builder: (_) => const RemoteButtonsPage());
                  case ProfilesSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const ProfilesSettingsPage());
                  case LookSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const LookSettingsPage());
                  case RemoteSearchSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const RemoteSearchSettingsPage());
                  case WeatherSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const WeatherSettingsPage());
                  case HaNotificationsPage.routeName:
                    return _FastPageRoute(builder: (_) => const HaNotificationsPage());
                  case HaPanelPage.routeName:
                    return _FastPageRoute(builder: (_) => const HaPanelPage());
                  case HaStatusPage.routeName:
                    return _FastPageRoute(builder: (_) => const HaStatusPage());
                  case BackupRestorePage.routeName:
                    return _FastPageRoute(builder: (_) => const BackupRestorePage());
                  case AppLanguagePage.routeName:
                    return _FastPageRoute(builder: (_) => const AppLanguagePage());
                  case BlockedNotificationsPage.routeName:
                    return _FastPageRoute(builder: (_) => const BlockedNotificationsPage());
                  case TvPowerSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const TvPowerSettingsPage());
                  case NotificationsSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const NotificationsSettingsPage());
                  case ContinueWatchingSettingsPage.routeName:
                    return _FastPageRoute(builder: (_) => const ContinueWatchingSettingsPage());
                  case ContinueWatchingCardSizePage.routeName:
                    return _FastPageRoute(builder: (_) => const ContinueWatchingCardSizePage());
                  case ContinueWatchingMaxItemsPage.routeName:
                    return _FastPageRoute(builder: (_) => const ContinueWatchingMaxItemsPage());
                  case ContinueWatchingAppsPage.routeName:
                    return _FastPageRoute(builder: (_) => const ContinueWatchingAppsPage());
                  case AppDetailsPage.routeName:
                    return _FastPageRoute(builder: (_) => AppDetailsPage(application: settings.arguments as App));
                  default:
                    throw ArgumentError.value(settings.name, "settings.name", "Route not supported.");
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Toward the screen (Right, or Left in a right-to-left language, where the panel is on the right) closes the
  /// panel, and the other way goes back to the page before (on a sub page), unless focus can move that way inside
  /// the page.
  KeyEventResult _onArrowAtEdge(FocusNode node, KeyEvent event) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final bool right = event.logicalKey ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight);
    final bool left = event.logicalKey ==
        (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft);
    if (!(right || left) || event is KeyUpEvent) return KeyEventResult.ignored;
    if (left && !_navigatorKey.currentState!.canPop()) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (event is KeyDownEvent &&
        (focused == null || !focused.focusInDirection(event.logicalKey == LogicalKeyboardKey.arrowRight
                ? TraversalDirection.right
                : TraversalDirection.left))) {
      if (right) {
        Navigator.of(context).pop();
      } else {
        _navigatorKey.currentState!.maybePop();
      }
    }
    return KeyEventResult.handled;
  }
}

/// A page route with no transition animation.
class _FastPageRoute<T> extends PageRouteBuilder<T> {
  _FastPageRoute({required Widget Function(BuildContext) builder})
      : super(
          pageBuilder: (context, _, __) => builder(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
}
