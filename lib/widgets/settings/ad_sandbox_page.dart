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
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'message_dialog.dart';
import 'settings_page.dart';

/// Settings > System > Ad tracking: one switch, on unless a parent turned it off, that keeps Android's Privacy Sandbox
/// off for every profile on this TV (AdSandbox.java looks again whenever the TV wakes). Hearth's own adb does it;
/// letting ad tracking back on asks for the parent PIN where the TV has one.
class AdSandboxPage extends StatefulWidget {
  static const String routeName = "ad_sandbox";

  const AdSandboxPage({super.key});

  @override
  State<AdSandboxPage> createState() => _AdSandboxPageState();
}

class _AdSandboxPageState extends State<AdSandboxPage> {
  /// How long the TV's debugging gets to answer (and the parent to choose Allow on "Allow debugging?").
  static const Duration _selfAdbLimit = Duration(seconds: 60);

  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  Map<dynamic, dynamic>? _status;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _channel.getAdSandbox();
      if (mounted) setState(() => _status = status);
    } catch (err) {
      noteFailure('ad_sandbox_page', err);
    }
  }

  bool get _keptOff => _status?["keptOff"] == true;

  Future<void> _toggle() async {
    final keepOff = !_keptOff;
    // Keeping it off needs no PIN: only turning the sandbox back on does
    if (!keepOff && context.read<SettingsService>().hasParentPin && !await requireParentPin(context)) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _running = true);
    bool ran = true;
    try {
      await _channel.setAdSandboxKeptOff(keepOff).timeout(_selfAdbLimit);
    } catch (err) {
      noteFailure('ad_sandbox_page', err);
      ran = false;
    }
    if (!mounted) return;
    setState(() => _running = false);
    await _refresh();
    if (!ran && mounted) {
      await showMessageDialog(context, title: l.setupFlowFixFailedTitle, message: l.setupFlowFixFailedBody);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final installed = (_status?["installed"] as List?)?.length ?? 0;
    final on = (_status?["on"] as List?)?.length ?? 0;
    final status = !_keptOff ? l.adSandboxStatusAllowed : (on == 0 ? l.adSandboxStatusOff : l.adSandboxStatusOn);
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(text, style: textTheme.bodySmall));
    return SettingsPage(
      title: l.adSandboxTitle,
      children: [
        note(l.adSandboxIntro),
        if (_status != null && installed == 0)
          note(l.adSandboxNone)
        else ...[
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.block),
            title: Text(l.adSandboxKeepOff, style: textTheme.bodyMedium),
            trailing: _running
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_keptOff ? Icons.check_box : Icons.check_box_outline_blank),
            onPressed: _status == null || _running ? null : _toggle,
          ),
          if (_status != null) note(status),
          // Still on: Hearth's debugging may need its one-time approval to do it
          if (_status != null && (!_keptOff || on > 0)) note(l.adSandboxConfirmApproval),
          note(l.adSandboxNote),
        ],
      ],
    );
  }
}
