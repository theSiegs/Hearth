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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import '../../providers/ha_calendars.dart';
import '../../providers/ha_dashboards.dart';
import '../../providers/settings_service.dart';
import '../rounded_switch_list_tile.dart';
import 'focusable_settings_tile.dart';
import 'remote_text_field.dart';
import 'ha_dashboard_dialog.dart';
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
  bool? _reporting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _channel.getHaNotificationsEnabled();
      final config = await _channel.getHaStatusConfig();
      if (mounted) {
        setState(() {
          _notifications = enabled;
          _reporting = (config["url"] as String? ?? "").isNotEmpty && (config["webhookId"] as String? ?? "").isNotEmpty;
        });
      }
    } catch (_) {}
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
    return SettingsPage(
      title: "Home Assistant",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(l.notifications, style: textTheme.bodyMedium),
          trailing: Text(_onOff(l, _notifications), style: textTheme.bodySmall),
          onPressed: () => _open(HaNotificationsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.dashboard_outlined),
          title: Text(l.haPanelTitle, style: textTheme.bodyMedium),
          trailing: Text(_onOff(l, panel), style: textTheme.bodySmall),
          onPressed: () => _open(HaPanelPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.sensors_outlined),
          title: Text(l.haTvStatusTitle, style: textTheme.bodyMedium),
          trailing: Text(_reporting == null ? "" : (_reporting! ? l.haSummaryReporting : l.haSummaryOff),
              style: textTheme.bodySmall),
          onPressed: () => _open(HaStatusPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.event_outlined),
          title: Text(l.haCalendarsTitle, style: textTheme.bodyMedium),
          onPressed: () => _open(HaCalendarsPage.routeName),
        ),
      ],
    );
  }
}

/// The Home Assistant calendars that show by the top bar's date and time, for this profile: all of them unless some
/// are turned off here.
class HaCalendarsPage extends StatefulWidget {
  static const String routeName = "home_assistant_calendars";

  const HaCalendarsPage({super.key});

  @override
  State<HaCalendarsPage> createState() => _HaCalendarsPageState();
}

class _HaCalendarsPageState extends State<HaCalendarsPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Asks Home Assistant again, so a calendar added there (or a token just set up) shows here.
  Future<void> _load() async {
    await context.read<HaCalendarService?>()?.refresh(force: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = context.watch<HaCalendarService?>();
    final hidden = context.select<SettingsService, String>((s) => s.hiddenHaCalendars.join("\n")).split("\n").toSet();
    final calendars = service?.calendars ?? const <HaCalendar>[];
    final status = service?.status ?? HaCalendarStatus.notSetUp;
    String? note;
    if (_loading && calendars.isEmpty) {
      note = l.haCalendarsLoading;
    } else if (status == HaCalendarStatus.notSetUp) {
      note = l.haCalendarsNotSetUp(HaPanelPage.breadcrumb(l));
    } else if (status == HaCalendarStatus.unreachable && calendars.isEmpty) {
      note = l.haCalendarsError;
    } else if (calendars.isEmpty) {
      note = l.haCalendarsNone;
    }
    return SettingsPage(
      title: l.haCalendarsTitle,
      children: [
        for (final (i, calendar) in calendars.indexed)
          RoundedSwitchListTile(
            autofocus: i == 0,
            value: !hidden.contains(calendar.entityId),
            onChanged: (shown) => context.read<SettingsService>().setHaCalendarShown(calendar.entityId, shown),
            title: Text(calendar.name),
            subtitle: Text(calendar.entityId),
            secondary: const Icon(Icons.event_outlined),
          ),
        if (note != null)
          Focus(autofocus: calendars.isEmpty, child: _note(context, note)),
        const SizedBox(height: 8),
        _note(context, l.haCalendarsHelp),
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
    } catch (_) {}
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
    } catch (_) {}
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
      // A new sign-in can read the calendars
      context.read<HaCalendarService?>()?.refresh(force: true);
    }
  }

  /// This profile's own dashboard, picked from Home Assistant's list (or back to the TV's).
  Future<void> _chooseProfileDashboard() async {
    final settings = context.read<SettingsService>();
    ({String url, String token})? connection;
    try {
      connection = await _channel.getHaConnection();
    } catch (_) {}
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
        context.read<HaCalendarService?>()?.refresh(force: true);
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

/// What's on the TV, sent to a Home Assistant webhook as it changes.
class HaStatusPage extends StatefulWidget {
  static const String routeName = "home_assistant_status";

  const HaStatusPage({super.key});

  @override
  State<HaStatusPage> createState() => _HaStatusPageState();
}

class _HaStatusPageState extends State<HaStatusPage> with WidgetsBindingObserver {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _webhook = TextEditingController();
  bool _notificationAccess = false;
  String? _statusSaved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _url.dispose();
    _webhook.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAccess();
  }

  Future<void> _load() async {
    try {
      final config = await _channel.getHaStatusConfig();
      if (mounted) {
        setState(() {
          _url.text = config["url"] as String? ?? "";
          _webhook.text = config["webhookId"] as String? ?? "";
        });
      }
    } catch (_) {}
    await _loadAccess();
  }

  Future<void> _loadAccess() async {
    try {
      final access = await _channel.checkNotificationListenerPermission();
      if (mounted) setState(() => _notificationAccess = access);
    } catch (_) {}
  }

  Future<void> _saveStatus() async {
    final url = _url.text.trim();
    final webhook = _webhook.text.trim();
    await _channel.setHaStatusConfig(url.isEmpty ? null : url, webhook.isEmpty ? null : webhook);
    if (mounted) {
      final l = AppLocalizations.of(context)!;
      setState(() => _statusSaved = url.isEmpty || webhook.isEmpty ? l.haStatusReportingOff : l.haStatusSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SettingsPage(
      title: l.haTvStatusTitle,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              RemoteTextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l.haStatusAddressLabel, hintText: "http://192.168.1.10:8123"),
              ),
              RemoteTextField(
                controller: _webhook,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveStatus(),
                decoration: InputDecoration(labelText: l.haStatusWebhookLabel),
              ),
            ],
          ),
        ),
        // Focus starts here, not in a text field, so the keyboard doesn't pop up on the way in
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.save_outlined),
          title: Text(l.save, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _saveStatus,
        ),
        if (_statusSaved != null) _note(context, _statusSaved!),
        FocusableSettingsTile(
          leading: Icon(Icons.music_note_outlined, color: _notificationAccess ? Colors.green : Colors.orange),
          title: Text(
            _notificationAccess ? l.haStatusNowPlayingOn : l.haStatusNowPlayingOff,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          onPressed: () async {
            await _channel.requestNotificationListenerPermission();
          },
        ),
        _note(context, l.haStatusHelp),
      ],
    );
  }
}
