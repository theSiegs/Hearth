/*
 * LTvLauncher
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import '../../providers/settings_service.dart';
import '../rounded_switch_list_tile.dart';
import 'focusable_settings_tile.dart';
import 'ha_phone_setup_dialog.dart';

/// Home Assistant: its pop-ups on the TV, its dashboard panel, and the TV's status reported to it. Each has a page
/// of its own; this one shows whether each is on.
class HomeAssistantPage extends StatefulWidget {
  static const String routeName = "home_assistant";

  const HomeAssistantPage({super.key});

  @override
  State<HomeAssistantPage> createState() => _HomeAssistantPageState();
}

class _HomeAssistantPageState extends State<HomeAssistantPage> {
  final _channel = FLauncherChannel();
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

  String _onOff(bool? on) => on == null ? "" : (on ? "On" : "Off");

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final panel = context.select<SettingsService, bool>((s) => s.haPanelEnabled);
    return Column(
      children: [
        Text("Home Assistant", style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text("Notifications", style: textTheme.bodyMedium),
                  trailing: Text(_onOff(_notifications), style: textTheme.bodySmall),
                  onPressed: () => _open(HaNotificationsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: Text("Dashboard panel", style: textTheme.bodyMedium),
                  trailing: Text(_onOff(panel), style: textTheme.bodySmall),
                  onPressed: () => _open(HaPanelPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.sensors_outlined),
                  title: Text("TV status", style: textTheme.bodyMedium),
                  trailing: Text(_reporting == null ? "" : (_reporting! ? "Reporting" : "Off"), style: textTheme.bodySmall),
                  onPressed: () => _open(HaStatusPage.routeName),
                ),
              ],
            ),
          ),
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
  final _channel = FLauncherChannel();
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
      setState(() => _testResult =
          shown ? null : "Turn on Home Button Fix (Settings > System > Setup & permissions); it shows the pop-ups.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Notifications", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoundedSwitchListTile(
                  autofocus: true,
                  value: _enabled,
                  onChanged: _setEnabled,
                  title: const Text("Show Home Assistant notifications"),
                  secondary: const Icon(Icons.home_outlined),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text("Send a test notification", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _test,
                ),
                if (_testResult != null) _note(context, _testResult!, color: Colors.orangeAccent),
                const SizedBox(height: 8),
                _note(
                  context,
                  "In Home Assistant, add the \"Notifications for Android TV / Fire TV\" integration with host "
                  "${_ip ?? "(this TV's IP address)"}. Then send notifications to it from automations, for "
                  "example for the doorbell or when the laundry is done.\n\n"
                  "Only devices on your home network can send them (port 7676). Pop-ups appear over any app "
                  "and need Home Button Fix (Settings > System > Setup & permissions) to be on.",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A Home Assistant dashboard that slides in from the right edge, signed in with a long-lived token.
class HaPanelPage extends StatefulWidget {
  static const String routeName = "home_assistant_panel";

  const HaPanelPage({super.key});

  @override
  State<HaPanelPage> createState() => _HaPanelPageState();
}

class _HaPanelPageState extends State<HaPanelPage> {
  final _channel = FLauncherChannel();
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
      setState(() {
        _panelHasToken = panel["hasToken"] == true;
        _panelDashboard.text = panel["dashboard"] as String? ?? "";
        _panelSaved = _panelHasToken ? "Saved" : "Saved. Add an access token to sign in.";
      });
    }
  }

  Future<void> _setUpFromPhone() async {
    final received = await showDialog<bool>(context: context, builder: (_) => HaPhoneSetupDialog(channel: _channel));
    if (received == true) {
      await _load();
      if (mounted) setState(() => _panelSaved = "Received the address and token from your phone");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Dashboard panel", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Selector<SettingsService, bool>(
                  selector: (_, settings) => settings.haPanelEnabled,
                  builder: (context, panelEnabled, _) => RoundedSwitchListTile(
                    autofocus: true,
                    value: panelEnabled,
                    onChanged: (enabled) => context.read<SettingsService>().setHaPanelEnabled(enabled),
                    title: const Text("Right at the right edge opens the panel"),
                    secondary: const Icon(Icons.dashboard_outlined),
                  ),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: Text("Set up from your phone", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _setUpFromPhone,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      TextField(
                        controller: _panelToken,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: "Long-lived access token",
                          hintText: _panelHasToken ? "Saved (type a new one to replace it)" : null,
                        ),
                      ),
                      TextField(
                        controller: _panelDashboard,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _savePanel(),
                        decoration: const InputDecoration(labelText: "Dashboard", hintText: "lovelace"),
                      ),
                    ],
                  ),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.save_outlined),
                  title: Text("Save", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _savePanel,
                ),
                if (_panelSaved != null) _note(context, _panelSaved!),
                _note(
                  context,
                  "On for this profile only. The panel shows a dashboard from the address under TV status, signed "
                  "in with the token. Create the token in Home Assistant while logged in as a non-admin user made "
                  "for this TV (profile page, Security tab).",
                ),
              ],
            ),
          ),
        ),
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
  final _channel = FLauncherChannel();
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
      setState(() => _statusSaved = url.isEmpty || webhook.isEmpty ? "Status reporting is off" : "Saved: reporting to Home Assistant");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("TV status", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: "Home Assistant address", hintText: "http://192.168.1.10:8123"),
                      ),
                      TextField(
                        controller: _webhook,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveStatus(),
                        decoration: const InputDecoration(labelText: "Webhook ID"),
                      ),
                    ],
                  ),
                ),
                // Focus starts here, not in a text field, so the keyboard doesn't pop up on the way in
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.save_outlined),
                  title: Text("Save", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _saveStatus,
                ),
                if (_statusSaved != null) _note(context, _statusSaved!),
                FocusableSettingsTile(
                  leading: Icon(Icons.music_note_outlined, color: _notificationAccess ? Colors.green : Colors.orange),
                  title: Text(
                    _notificationAccess ? "Now playing: on" : "Now playing: turn on notification access",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onPressed: () async {
                    await _channel.requestNotificationListenerPermission();
                  },
                ),
                _note(
                  context,
                  "The TV sends Home Assistant what's on: the app, what's playing, the Google TV profile, and "
                  "kids screen time. It only sends to the address above, as changes happen.",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
