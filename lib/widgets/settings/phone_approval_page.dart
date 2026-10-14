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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'message_dialog.dart';
import 'profile_pairing_page.dart';
import 'settings_page.dart';

/// A Home Assistant companion app's notify service as its phone's name: "mobile_app_alex_phone" reads "Alex Phone".
String phoneName(String service) => service
    .replaceFirst("mobile_app_", "")
    .split("_")
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(" ");

/// The Profiles page's row for approving switches from a phone: greyed out, with what it needs, until Home Assistant
/// is set up.
class PhoneApprovalTile extends StatefulWidget {
  const PhoneApprovalTile({super.key});

  @override
  State<PhoneApprovalTile> createState() => _PhoneApprovalTileState();
}

class _PhoneApprovalTileState extends State<PhoneApprovalTile> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  bool? _haConfigured;
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _channel?.getPhoneApproval() ?? {};
      if (mounted) {
        setState(() {
          _haConfigured = state["haConfigured"] == true;
          _on = state["on"] == true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final available = _haConfigured == true;
    final dim = available ? null : Colors.white38;
    return FocusableSettingsTile(
      leading: Icon(Icons.phonelink_lock, color: dim),
      title: Text(l.approvalTitle, style: textTheme.bodyMedium?.copyWith(color: dim)),
      trailing: Text(available ? (_on ? l.approvalOn : l.approvalOff) : l.approvalNeedsHa,
          style: textTheme.bodySmall?.copyWith(color: dim)),
      onPressed: () async {
        if (!available) {
          await showMessageDialog(context, title: l.approvalTitle, message: l.approvalNeedsHaBody);
          return;
        }
        await Navigator.of(context).pushNamed(PhoneApprovalPage.routeName);
        _load();
      },
    );
  }
}

/// An adult's own profile: when someone switches to it at Google TV's PIN screen, Hearth asks their phone (a Home
/// Assistant notification with Allow and Deny) and, allowed, enters their Google TV PIN.
class PhoneApprovalPage extends StatefulWidget {
  static const String routeName = "phone_approval";

  const PhoneApprovalPage({super.key});

  @override
  State<PhoneApprovalPage> createState() => _PhoneApprovalPageState();
}

class _PhoneApprovalPageState extends State<PhoneApprovalPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  Map<dynamic, dynamic>? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await _channel.getPhoneApproval();
    if (mounted) setState(() => _state = state);
  }

  bool get _pinSaved => ((_state?["pin"] as Map?)?["status"] as String? ?? "none") != "none";

  Future<void> _setOn(bool on) async {
    await _channel.setPhoneApprovalOn(on);
    _load();
  }

  Future<void> _pickPhone() async {
    final l = AppLocalizations.of(context)!;
    final services = await _channel.getHaNotifyServices();
    if (!mounted) return;
    if (services.isEmpty) {
      await showMessageDialog(context, title: l.approvalPhone, message: l.approvalNoPhones);
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.approvalPhonePick),
        children: [
          for (final service in services)
            SimpleDialogOption(
              child: TextButton(
                autofocus: service == _state?["notify"],
                onPressed: () => Navigator.of(context).pop(service),
                child: Text(phoneName(service)),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _channel.setPhoneApprovalNotify(picked);
    _load();
  }

  /// The Google TV PIN, twice on the TV's pad; a saved one can be changed or removed. Its owner's own PIN, so only
  /// they can set one that works; the parent PIN isn't asked.
  Future<void> _editPin() async {
    final l = AppLocalizations.of(context)!;
    if (_pinSaved) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.approvalPin),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
            TextButton(
                autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
          ],
        ),
      );
      if (remove == null || !mounted) return;
      if (remove) {
        await _channel.removeGoogleTvPin();
        _load();
        return;
      }
    }
    final first = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(title: l.approvalPin, subtitle: l.approvalPinSubtitle, length: 4),
    );
    if (first == null || !mounted) return;
    final second = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(title: l.parentPinConfirm, verify: (pin) => pin == first, length: 4),
    );
    if (second == null || !mounted) return;
    final ok = await _channel.saveGoogleTvPin(first);
    if (!ok && mounted) await showMessageDialog(context, title: l.approvalPin, message: l.profilePinSaveFailed);
    _load();
  }

  Future<void> _test() async {
    final l = AppLocalizations.of(context)!;
    final ok = await _channel.testPhoneApproval();
    if (mounted) {
      await showMessageDialog(context, title: l.approvalTest, message: ok ? l.approvalTestSent : l.approvalTestFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final small = textTheme.bodySmall?.copyWith(color: Colors.white54);
    final state = _state;
    final notify = state?["notify"] as String?;
    return SettingsPage(
      title: l.approvalTitle,
      children: [
        if (state == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else ...[
          RoundedSwitchListTile(
            autofocus: true,
            value: state["on"] == true,
            onChanged: _setOn,
            title: Text(l.approvalSwitch, style: textTheme.bodyMedium),
            secondary: Icon(Icons.phonelink_lock, color: state["on"] == true ? Colors.green : Colors.white54),
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.smartphone),
            title: Text(l.approvalPhone, style: textTheme.bodyMedium),
            trailing: Text(notify != null ? phoneName(notify) : l.approvalPhoneNone, style: textTheme.bodySmall),
            onPressed: _pickPhone,
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l.approvalPin, style: textTheme.bodyMedium),
            trailing: Text(profilePinStatus(l, state["pin"] as Map?), style: textTheme.bodySmall),
            onPressed: _editPin,
          ),
          if (notify != null)
            FocusableSettingsTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(l.approvalTest, style: textTheme.bodyMedium),
              onPressed: _test,
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(l.approvalFooter, style: small, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}
