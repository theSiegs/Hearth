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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import '../../providers/ha_dashboards.dart';
import '../../providers/profile_service.dart';
import '../../providers/settings_service.dart';
import '../rounded_switch_list_tile.dart';
import 'focusable_settings_tile.dart';
import 'remote_text_field.dart';
import 'ha_dashboard_dialog.dart';
import 'ha_pair_page.dart';
import 'ha_phone_setup_dialog.dart';
import 'settings_page.dart';
import 'setup_checklist_page.dart';

/// Home Assistant: its pop-ups on the TV, its dashboard panel, and the TV's status reported to it. Each has a page
/// of its own; this one shows whether each is on.
class HomeAssistantPage extends StatefulWidget {
  static const String routeName = "home_assistant";

  const HomeAssistantPage({super.key});

  @override
  State<HomeAssistantPage> createState() => _HomeAssistantPageState();
}

class _HomeAssistantPageState extends State<HomeAssistantPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  bool? _notifications;
  bool? _paired;
  // HearthTube's now playing for Home Assistant: null when never asked (HearthTube's own default then, on)
  bool? _shareNowPlaying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _channel.getHaNotificationsEnabled();
      final integration = await _channel.getHaIntegration();
      bool? share;
      try {
        share = await _channel.getHaShareNowPlaying();
      } catch (err) { noteFailure('home_assistant_page', err); }
      if (mounted) {
        setState(() {
          _shareNowPlaying = share;
          _notifications = enabled;
          _paired = integration["paired"] == true;
        });
      }
    } catch (err) { noteFailure('home_assistant_page', err); }
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    _load();
  }

  String _onOff(AppLocalizations l, bool? on) => on == null ? "" : (on ? l.haSummaryOn : l.haSummaryOff);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final panel = context.select<SettingsService, bool>((s) => s.haPanelEnabled);
    // The dashboard panel is for adults: a kids profile has no panel to set up (see haPanelAllowed)
    final kids = context.select<ProfileService?, bool>((p) => p?.isKidsProfile ?? false);
    return SettingsPage(
      title: "Home Assistant",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.link),
          title: Text(l.haPairTitle, style: textTheme.bodyMedium),
          trailing: Text(_paired == null ? "" : (_paired! ? l.haPairPaired : l.haPairNotPaired), style: textTheme.bodySmall),
          onPressed: () => _open(HaPairPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(l.notifications, style: textTheme.bodyMedium),
          trailing: Text(_onOff(l, _notifications), style: textTheme.bodySmall),
          onPressed: () => _open(HaNotificationsPage.routeName),
        ),
        if (!kids) FocusableSettingsTile(
          leading: const Icon(Icons.dashboard_outlined),
          title: Text(l.haPanelTitle, style: textTheme.bodyMedium),
          trailing: Text(_onOff(l, panel), style: textTheme.bodySmall),
          onPressed: () => _open(HaPanelPage.routeName),
        ),
        RoundedSwitchListTile(
          value: _shareNowPlaying ?? true,
          onChanged: (share) async {
            await _channel.setHaShareNowPlaying(share);
            if (mounted) setState(() => _shareNowPlaying = share);
          },
          title: Text(l.haShareNowPlaying, style: textTheme.bodyMedium),
          subtitle: Text(l.haShareNowPlayingDetail, style: textTheme.bodySmall),
          secondary: const Icon(Icons.smart_display_outlined),
        ),
      ],
    );
  }
}

TextStyle? _small(BuildContext context) => Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);

Widget _note(BuildContext context, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(text, style: color == null ? _small(context) : _small(context)?.copyWith(color: color)),
    );

/// Home Assistant pop-ups (doorbell, laundry done, arrivals...). Hearth speaks the protocol of Home Assistant's
/// built-in "Notifications for Android TV / Fire TV" integration, so nothing extra is needed there.
class HaNotificationsPage extends StatefulWidget {
  static const String routeName = "home_assistant_notifications";

  const HaNotificationsPage({super.key});

  @override
  State<HaNotificationsPage> createState() => _HaNotificationsPageState();
}

class _HaNotificationsPageState extends State<HaNotificationsPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  bool _enabled = false;
  String? _ip;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _channel.getHaNotificationsEnabled();
      final ip = await _channel.getLocalIpAddress();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _ip = ip;
        });
      }
    } catch (err) { noteFailure('home_assistant_page', err); }
  }

  Future<void> _setEnabled(bool enabled) async {
    await _channel.setHaNotificationsEnabled(enabled);
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _test() async {
    final shown = await _channel.sendHaTestNotification();
    if (mounted) {
      final l = AppLocalizations.of(context)!;
      setState(() => _testResult = shown ? null : l.haNotificationsNeedsFix(SetupChecklistPage.breadcrumb(l)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsPage(
      title: l.notifications,
      children: [
        RoundedSwitchListTile(
          autofocus: true,
          value: _enabled,
          onChanged: _setEnabled,
          title: Text(l.haNotificationsShow),
          secondary: const Icon(Icons.home_outlined),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(l.haNotificationsSendTest, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _test,
        ),
        if (_testResult != null) _note(context, _testResult!, color: Colors.orangeAccent),
        const SizedBox(height: 8),
        _note(context, l.haNotificationsHelp(_ip ?? l.haNotificationsThisTvIp, SetupChecklistPage.breadcrumb(l))),
      ],
    );
  }
}

/// A Home Assistant dashboard that slides in from the right edge, signed in with a long-lived token.
class HaPanelPage extends StatefulWidget {
  static const String routeName = "home_assistant_panel";
  /// Where this page is, for the hints on other pages that send people here.
  static String breadcrumb(AppLocalizations l) => "${l.settingsTitle} > Home Assistant > ${l.haPanelTitle}";

  const HaPanelPage({super.key});

  @override
  State<HaPanelPage> createState() => _HaPanelPageState();
}

class _HaPanelPageState extends State<HaPanelPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  final TextEditingController _panelToken = TextEditingController();
  final TextEditingController _panelDashboard = TextEditingController();
  bool _panelHasToken = false;
  String? _panelSaved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _panelToken.dispose();
    _panelDashboard.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final panel = await _channel.getHaPanelConfig();
      if (mounted) {
        setState(() {
          _panelHasToken = panel["hasToken"] == true;
          _panelDashboard.text = panel["dashboard"] as String? ?? "";
        });
      }
    } catch (err) { noteFailure('home_assistant_page', err); }
  }

  /// Saves the panel's dashboard path, and the token if one was typed (the saved token is never shown again).
  Future<void> _savePanel() async {
    final token = _panelToken.text.trim();
    await _channel.setHaPanelConfig(token: token.isEmpty ? null : token, dashboard: _panelDashboard.text.trim());
    _panelToken.clear();
    final panel = await _channel.getHaPanelConfig();
    if (mounted) {
      final l = AppLocalizations.of(context)!;
      setState(() {
        _panelHasToken = panel["hasToken"] == true;
        _panelDashboard.text = panel["dashboard"] as String? ?? "";
        _panelSaved = _panelHasToken ? l.haPanelSaved : l.haPanelSavedNoToken;
      });
    }
  }

  /// This profile's own dashboard, picked from Home Assistant's list (or back to the TV's).
  Future<void> _chooseProfileDashboard() async {
    final settings = context.read<SettingsService>();
    ({String url, String token})? connection;
    try {
      connection = await _channel.getHaConnection();
    } catch (err) { noteFailure('home_assistant_page', err); }
    if (!mounted) return;
    final path = await showDialog<String>(
      context: context,
      builder: (_) => HaDashboardDialog(
          dashboards: connection == null ? null : HaDashboards(connection.url, connection.token)),
    );
    if (path != null) await settings.setHaPanelDashboard(path);
  }

  Future<void> _setUpFromPhone() async {
    final received = await showDialog<bool>(context: context, builder: (_) => HaPhoneSetupDialog(channel: _channel));
    if (received == true) {
      await _load();
      if (mounted) {
        setState(() => _panelSaved = AppLocalizations.of(context)!.haPanelReceived);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsPage(
      title: l.haPanelTitle,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<SettingsService, bool>(
          selector: (_, settings) => settings.haPanelEnabled,
          builder: (context, panelEnabled, _) => RoundedSwitchListTile(
            autofocus: true,
            value: panelEnabled,
            onChanged: (enabled) => context.read<SettingsService>().setHaPanelEnabled(enabled),
            title: Text(l.haPanelRightEdge),
            secondary: const Icon(Icons.dashboard_outlined),
          ),
        ),
        Selector<SettingsService, bool>(
          selector: (_, settings) => settings.haPanelFullDashboard,
          builder: (context, full, _) => RoundedSwitchListTile(
            value: full,
            onChanged: (enabled) => context.read<SettingsService>().setHaPanelFullDashboard(enabled),
            title: Text(l.haPanelFullDashboard),
            subtitle: Text(l.haPanelFullDashboardDetail),
            secondary: const Icon(Icons.web_outlined),
          ),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.qr_code_2),
          title: Text(l.haSetUpFromPhone, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _setUpFromPhone,
        ),
        Selector<SettingsService, String>(
          selector: (_, settings) => settings.haPanelDashboard,
          builder: (context, own, _) => FocusableSettingsTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l.haPanelProfileDashboard, style: Theme.of(context).textTheme.bodyMedium),
            trailing: Text(own.isEmpty ? l.haPanelProfileDashboardTv : own,
                style: Theme.of(context).textTheme.bodySmall),
            onPressed: _chooseProfileDashboard,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              RemoteTextField(
                controller: _panelToken,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l.haPanelTokenLabel,
                  hintText: _panelHasToken ? l.haPanelTokenSavedHint : null,
                ),
              ),
              RemoteTextField(
                controller: _panelDashboard,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _savePanel(),
                decoration: InputDecoration(labelText: l.haPanelDashboardLabel, hintText: "lovelace"),
              ),
            ],
          ),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.save_outlined),
          title: Text(l.save, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _savePanel,
        ),
        if (_panelSaved != null) _note(context, _panelSaved!),
        _note(context, l.haPanelHelp(l.haTvStatusTitle)),
      ],
    );
  }
}
