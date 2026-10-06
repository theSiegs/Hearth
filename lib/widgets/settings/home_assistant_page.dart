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

/// Home Assistant pop-ups (doorbell, laundry done, arrivals...). LTvLauncher speaks the protocol of Home
/// Assistant's built-in "Notifications for Android TV / Fire TV" integration, so nothing extra is needed there.
class HomeAssistantPage extends StatefulWidget {
  static const String routeName = "home_assistant";

  const HomeAssistantPage({super.key});

  @override
  State<HomeAssistantPage> createState() => _HomeAssistantPageState();
}

class _HomeAssistantPageState extends State<HomeAssistantPage> {
  final _channel = FLauncherChannel();
  bool _enabled = false;
  String? _ip;
  String? _testResult;
  bool _notificationAccess = false;
  final TextEditingController _url = TextEditingController();
  final TextEditingController _webhook = TextEditingController();
  String? _statusSaved;
  final TextEditingController _panelToken = TextEditingController();
  final TextEditingController _panelDashboard = TextEditingController();
  bool _panelHasToken = false;
  String? _panelSaved;

  @override
  void dispose() {
    _url.dispose();
    _webhook.dispose();
    _panelToken.dispose();
    _panelDashboard.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _channel.getHaNotificationsEnabled();
      final ip = await _channel.getLocalIpAddress();
      final config = await _channel.getHaStatusConfig();
      final access = await _channel.checkNotificationListenerPermission();
      final panel = await _channel.getHaPanelConfig();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _ip = ip;
          _url.text = config["url"] as String? ?? "";
          _webhook.text = config["webhookId"] as String? ?? "";
          _notificationAccess = access;
          _panelHasToken = panel["hasToken"] == true;
          _panelDashboard.text = panel["dashboard"] as String? ?? "";
        });
      }
    } catch (_) {}
  }

  Future<void> _setEnabled(bool enabled) async {
    await _channel.setHaNotificationsEnabled(enabled);
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _saveStatus() async {
    final url = _url.text.trim();
    final webhook = _webhook.text.trim();
    await _channel.setHaStatusConfig(url.isEmpty ? null : url, webhook.isEmpty ? null : webhook);
    if (mounted) {
      setState(() => _statusSaved = url.isEmpty || webhook.isEmpty ? "Status reporting is off" : "Saved: reporting to Home Assistant");
    }
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

  Future<void> _test() async {
    final shown = await _channel.sendHaTestNotification();
    if (mounted) {
      setState(() => _testResult =
          shown ? null : "Turn on Home Button Fix (Settings > Accessibility); it shows the pop-ups.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return Column(
      children: [
        Text("Home Assistant", style: Theme.of(context).textTheme.titleLarge),
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
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(_testResult!, style: small?.copyWith(color: Colors.orangeAccent)),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text("Home Assistant panel", style: Theme.of(context).textTheme.titleMedium),
                ),
                Selector<SettingsService, bool>(
                  selector: (_, settings) => settings.haPanelEnabled,
                  builder: (context, panelEnabled, _) => RoundedSwitchListTile(
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
                        decoration: const InputDecoration(labelText: "Dashboard", hintText: "hearth-tv/family_room"),
                      ),
                    ],
                  ),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.save_outlined),
                  title: Text("Save panel settings", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _savePanel,
                ),
                if (_panelSaved != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_panelSaved!, style: small)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "On for this profile only. The panel shows a dashboard from the address below, signed in with "
                    "the token. Create the token in Home Assistant while logged in as a non-admin user made for "
                    "this TV (profile page, Security tab).",
                    style: small,
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text("TV status for Home Assistant", style: Theme.of(context).textTheme.titleMedium),
                ),
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
                FocusableSettingsTile(
                  leading: const Icon(Icons.save_outlined),
                  title: Text("Save status settings", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: _saveStatus,
                ),
                if (_statusSaved != null)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_statusSaved!, style: small)),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "The TV sends Home Assistant what's on: the app, what's playing, the Google TV profile, and "
                    "kids screen time. It only sends to the address above, as changes happen.",
                    style: small,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "In Home Assistant, add the \"Notifications for Android TV / Fire TV\" integration with host "
                    "${_ip ?? "(this TV's IP address)"}. Then send notifications to it from automations, for "
                    "example for the doorbell or when the laundry is done.\n\n"
                    "Only devices on your home network can send them (port 7676). Pop-ups appear over any app "
                    "and need Home Button Fix (Settings > Accessibility) to be on.",
                    style: small,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
