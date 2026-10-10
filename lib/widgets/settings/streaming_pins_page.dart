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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'message_dialog.dart';
import 'profile_pairing_page.dart';
import 'settings_page.dart';
import 'setup_checklist_page.dart';

/// One grown-up's Google TV profile in one app: the app profile Hearth picks for it, and that profile's PIN.
class _PinRow {
  final PairingChoice choice;

  /// The chosen app profile, or the one its name matches; null when the app's picker shows.
  final String? appProfile;
  final Map<dynamic, dynamic>? pin;

  const _PinRow(this.choice, this.appProfile, this.pin);
}

/// Settings > Profiles > Streaming app PINs: for each installed app Hearth can type PINs in, each grown-up's Google TV
/// profile with the app profile Hearth picks for it and that profile's PIN, all in one place. Setting a PIN on a
/// profile Hearth matched by name pairs the two for good, so the PIN always goes with the right app profile. Kids'
/// profiles never get one.
class StreamingPinsPage extends StatefulWidget {
  static const String routeName = "streaming_pins";

  const StreamingPinsPage({super.key});

  @override
  State<StreamingPinsPage> createState() => _StreamingPinsPageState();
}

class _StreamingPinsPageState extends State<StreamingPinsPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();

  /// Each app with its rows, once loaded.
  List<(Map<dynamic, dynamic>, List<_PinRow>)>? _apps;
  bool _serviceOn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = <(Map<dynamic, dynamic>, List<_PinRow>)>[];
    bool serviceOn = true;
    try {
      serviceOn = (await _channel.getProfilePairingStatus())["enabled"] == true;
      for (final app in await _channel.getProfilePairingApps()) {
        final pkg = app["packageName"] as String;
        if (app["installed"] != true || !await _channel.profilePinEntrySupported(pkg)) continue;
        final rows = <_PinRow>[];
        for (final map in await _channel.getProfilePairingChoices(pkg)) {
          final choice = PairingChoice.fromMap(map);
          if (choice.kids) continue;
          final appProfile = switch (choice.mode) {
            "profile" => choice.chosenProfile,
            "auto" => choice.autoMatch,
            _ => null,
          };
          rows.add(_PinRow(choice, appProfile,
              appProfile != null ? await _channel.getProfilePinStatus(pkg, appProfile) : null));
        }
        apps.add((app, rows));
      }
    } catch (_) {
      // No Android side: nothing to list
    }
    if (mounted) {
      setState(() {
        _apps = apps;
        _serviceOn = serviceOn;
      });
    }
  }

  /// The row's PIN: a profile with no app profile yet gets one picked first. Setting the PIN of a name match pairs it
  /// for good, only once the PIN is actually saved.
  Future<void> _edit(Map<dynamic, dynamic> app, _PinRow row) async {
    final l = AppLocalizations.of(context)!;
    final pkg = app["packageName"] as String;
    final label = app["label"] as String;
    String? appProfile = row.appProfile;
    Map<dynamic, dynamic>? pin = row.pin;
    if (appProfile == null) {
      final seen = ((app["seenProfiles"] as List?) ?? const []).cast<String>();
      if (seen.isEmpty) {
        await showMessageDialog(context, title: label, message: l.pairingAppNotSeenFooter);
        return;
      }
      appProfile = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.pairingProfileInApp(row.choice.displayName, label)),
          children: [
            for (final (index, profile) in seen.indexed)
              SimpleDialogOption(
                child: TextButton(
                  autofocus: index == 0,
                  onPressed: () => Navigator.of(context).pop(profile),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: Text(profile)),
                ),
              ),
          ],
        ),
      );
      if (appProfile == null || !mounted) return;
      pin = await _channel.getProfilePinStatus(pkg, appProfile);
      if (!mounted) return;
    }
    final chosen = appProfile;
    final paired = row.choice.mode == "profile" && row.choice.chosenProfile == chosen;
    await editProfilePin(
      context,
      packageName: pkg,
      appLabel: label,
      appProfile: chosen,
      saved: (pin?["status"] as String? ?? "none") != "none",
      beforeSave: paired
          ? null
          : () => _channel.setProfilePairingChoice(pkg, row.choice.hearthProfile, "profile", chosen),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final apps = _apps;
    if (apps == null) {
      return SettingsPage.custom(title: l.streamingPinsTitle, body: const Center(child: CircularProgressIndicator()));
    }
    bool first = true;
    bool takeFirst() {
      final was = first;
      first = false;
      return was;
    }

    final heading = textTheme.bodySmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600);
    final small = textTheme.bodySmall?.copyWith(color: Colors.white54);
    return SettingsPage(
      title: l.streamingPinsTitle,
      children: [
        if (!_serviceOn)
          FocusableSettingsTile(
            autofocus: takeFirst(),
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: Text(l.pairingOffSetUp, style: textTheme.bodyMedium),
            onPressed: () async {
              await Navigator.of(context).pushNamed(SetupChecklistPage.routeName);
              _load();
            },
          ),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(l.streamingPinsNone, style: small),
          ),
        for (final (app, rows) in apps) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(app["label"] as String, style: heading),
          ),
          // Pairing turned off for the app: no PIN is typed there, so the way to turn it back on
          if (app["enabled"] == false)
            FocusableSettingsTile(
              autofocus: takeFirst(),
              leading: const Icon(Icons.switch_account),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.pairingPairIn(app["label"] as String), style: textTheme.bodyMedium),
                  Text(l.pairingAppOff, style: small),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onPressed: () async {
                await Navigator.of(context).pushNamed(ProfilePairingAppPage.routeName, arguments: app);
                _load();
              },
            )
          else
            for (final row in rows)
              FocusableSettingsTile(
                autofocus: takeFirst(),
                leading: const Icon(Icons.pin_outlined),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.choice.displayName, style: textTheme.bodyMedium),
                    Text(
                      row.appProfile != null
                          ? "${row.appProfile} · ${l.profilePinRow}: ${profilePinStatus(l, row.pin)}"
                          : row.choice.summary(l),
                      style: small,
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onPressed: () => _edit(app, row),
              ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l.streamingPinsFooter, style: small, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
