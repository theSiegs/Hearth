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
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'kids_profiles_page.dart';
import 'message_dialog.dart';

/// Settings > System > Uninstall Hearth, the safe way: take it off the kids profiles first (so nothing is left behind
/// there), then open Android's uninstall screen for Hearth itself. If that can't run yet, stop and ask for the
/// approval rather than uninstall with copies left behind.
class UninstallHearthTile extends StatefulWidget {
  const UninstallHearthTile({super.key});

  @override
  State<UninstallHearthTile> createState() => _UninstallHearthTileState();
}

class _UninstallHearthTileState extends State<UninstallHearthTile> {
  bool _busy = false;

  Future<void> _uninstall() async {
    final l = AppLocalizations.of(context)!;
    final channel = context.read<FLauncherChannel>();
    final go = await _dialog<bool>(l.uninstallHearthTitle, [l.uninstallHearthBody, l.uninstallHearthWhyHere], [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
      TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.uninstall)),
    ]);
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    bool ok;
    try {
      await channel.removeHearthFromKidsProfiles().timeout(KidsProfilesPage.selfAdbLimit);
      ok = true;
    } catch (err) {
      noteFailure('uninstall_hearth_tile', err);
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      await _dialog<void>(l.uninstallHearthApprovalFirstTitle,
          [l.uninstallHearthApprovalFirstBody, l.uninstallHearthApprovalFirstRetry], [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(l.ok)),
      ]);
      return;
    }
    await channel.uninstallHearth();
  }

  Future<T?> _dialog<T>(String title, List<String> lines, List<Widget> actions) =>
      showLinesDialog<T>(context, title: title, lines: lines, actions: (_) => actions);

  @override
  Widget build(BuildContext context) => FocusableSettingsTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(AppLocalizations.of(context)!.uninstallHearthTitle, style: Theme.of(context).textTheme.bodyMedium),
        trailing: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        onPressed: _busy ? null : _uninstall,
      );
}
