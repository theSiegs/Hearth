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
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flauncher/widgets/settings/updates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The move from Hearth's old app id to the new one (docs/design/app-id-change.md), as Hearth starts:
/// - the new Hearth, once, after it brought the old one's data over: what came over and what's left (the services
///   to turn on again, the PINs to enter again, removing the old Hearth); or why it couldn't;
/// - the bridge build (the old id), every start: install the new Hearth, or open it once installed.
class HearthMoveCheck extends StatefulWidget {
  final Widget child;
  final FLauncherChannel? channel;
  final Duration startDelay;

  const HearthMoveCheck({super.key, required this.child, this.channel, this.startDelay = const Duration(seconds: 2)});

  @override
  State<HearthMoveCheck> createState() => _HearthMoveCheckState();
}

class _HearthMoveCheckState extends State<HearthMoveCheck> {
  late final FLauncherChannel _channel = widget.channel ?? context.read<FLauncherChannel>();

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.startDelay, _check);
  }

  Future<void> _check() async {
    if (!mounted) return;
    final status = await _channel.getMoveStatus();
    if (!mounted || status.isEmpty) return;
    if (status["bridge"] == true) {
      await _showBridge(status);
      return;
    }
    if (status["noticeShown"] == true) return;
    final state = status["state"] as String?;
    await _channel.markMoveNoticeShown();
    if (!mounted) return;
    if (state == "imported") {
      await _showImported(status);
    } else if (state == "unavailable" || state == "failed") {
      final l = AppLocalizations.of(context)!;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.moveUnavailableTitle),
          content: SizedBox(
            width: 440,
            child: Text(state == "failed"
                ? l.moveFailedBody(status["detail"] as String? ?? "")
                : l.moveUnavailableBody(status["legacyVersion"] as String? ?? "")),
          ),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(l.notNow)),
          ],
        ),
      );
    }
  }

  Future<void> _showBridge(Map<dynamic, dynamic> status) async {
    final l = AppLocalizations.of(context)!;
    final installed = status["newInstalled"] == true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.bridgeTitle),
        content: SizedBox(
          width: 440,
          child: Text(installed ? l.bridgeInstalledBody(status["newVersion"] as String? ?? "") : l.bridgeBody),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.notNow)),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(installed ? "open" : "updates"),
            child: Text(installed ? l.bridgeOpenNew : l.bridgeOpenUpdates),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == "open") {
      await _channel.openNewHearth(status["newPackage"] as String);
    } else if (choice == "updates") {
      await showDialog(context: context, builder: (_) => const SettingsPanel(initialRoute: UpdatesPage.routeName));
    }
  }

  Future<void> _showImported(Map<dynamic, dynamic> status) async {
    final l = AppLocalizations.of(context)!;
    final pins = (status["pinsToReenter"] as int?) ?? 0;
    final legacyInstalled = status["legacyInstalled"] == true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.moveImportedTitle),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.moveImportedBody(status["fromVersion"] as String? ?? "")),
              if (pins > 0) ...[const SizedBox(height: 12), Text(l.moveImportedPins(pins))],
              const SizedBox(height: 12),
              Text(l.moveFinishSteps),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.notNow)),
          if (legacyInstalled)
            TextButton(onPressed: () => Navigator.of(context).pop("remove"), child: Text(l.moveRemoveOld)),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop("setup"),
            child: Text(l.moveOpenSetup),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == "setup") {
      await showDialog(
          context: context, builder: (_) => const SettingsPanel(initialRoute: SetupChecklistPage.routeName));
    } else if (choice == "remove") {
      await removeOldHearth(context, _channel);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks, then replaces the old Hearth with this one in every profile and uninstalls it (a parent's PIN in a kids profile).
Future<void> removeOldHearth(BuildContext context, FLauncherChannel channel) async {
  final l = AppLocalizations.of(context)!;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.moveRemoveOld),
      content: SizedBox(width: 420, child: Text(l.moveRemoveOldConfirm)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.moveRemoveOld)),
      ],
    ),
  );
  if (go != true || !context.mounted || !await requireParent(context) || !context.mounted) return;
  String message;
  try {
    await channel.replaceOldHearth();
    message = l.moveRemoveOldDone;
  } on PlatformException catch (e) {
    message = e.code == "SELF_ADB" ? l.moveRemoveOldManual : "${e.message}";
  }
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.moveRemoveOld),
      content: SizedBox(width: 420, child: Text(message)),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(l.notNow)),
      ],
    ),
  );
}

/// Backup & restore: bring the old Hearth's data over again (it's installed and offers it), or say why not.
class OldHearthImportTile extends StatefulWidget {
  const OldHearthImportTile({super.key});

  @override
  State<OldHearthImportTile> createState() => _OldHearthImportTileState();
}

class _OldHearthImportTileState extends State<OldHearthImportTile> {
  Map<dynamic, dynamic> _status = const {};

  @override
  void initState() {
    super.initState();
    // Without the Android side (some tests) there's no old Hearth to talk about
    context.read<FLauncherChannel?>()?.getMoveStatus().then((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status["bridge"] == true || _status["legacyInstalled"] != true) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final version = _status["legacyVersion"] as String? ?? "";
    final offers = _status["legacyOffersData"] == true;
    final failed = _status["state"] == "failed";
    final textTheme = Theme.of(context).textTheme;
    final note = offers
        ? (failed ? l.moveFailedBody(_status["detail"] as String? ?? "") : null)
        : l.moveUnavailableBody(version);
    return Column(
      children: [
        FocusableSettingsTile(
          leading: const Icon(Icons.move_down),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.moveImportTile, style: textTheme.bodyMedium),
              if (note != null) Text(note, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
            ],
          ),
          onPressed: offers ? () => _confirm(context, version) : null,
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(l.moveRemoveOld, style: textTheme.bodyMedium),
          onPressed: () => removeOldHearth(context, context.read<FLauncherChannel>()),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, String version) async {
    final l = AppLocalizations.of(context)!;
    final channel = context.read<FLauncherChannel>();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.moveImportTile),
        content: SizedBox(width: 420, child: Text(l.moveImportConfirm(version))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.moveImportTile)),
        ],
      ),
    );
    if (go != true || !context.mounted || !await requireParent(context)) return;
    await channel.importFromOldHearth();
  }
}
