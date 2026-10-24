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
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'message_dialog.dart';
import 'phone_setup_dialog.dart';
import 'profile_pairing_page.dart';
import 'settings_page.dart';
import 'setup_checklist_page.dart';

/// The Google TV profile on now, in one app: the app profile Hearth picks for it, and that profile's PIN.
class _PinRow {
  final PairingChoice choice;

  /// The chosen app profile, or the one its name matches; null when the app's picker shows.
  final String? appProfile;
  final Map<dynamic, dynamic>? pin;

  const _PinRow(this.choice, this.appProfile, this.pin);
}

/// Settings > Profiles > Streaming app PINs: the PINs of the Google TV profile on now (each profile sees and sets
/// only its own), one row per installed app Hearth can type PINs in, with the app profile Hearth picks for it. A
/// kids profile has them too, set past the parent PIN like every profile PIN. Setting a PIN on a profile Hearth
/// matched by name pairs the two for good, so the PIN always goes with the right app profile. In an adult's profile
/// it also has Paramount+'s content PIN, one for the whole TV ([editContentPin]).
class StreamingPinsPage extends StatefulWidget {
  static const String routeName = "streaming_pins";

  /// The app with an account-wide content PIN (Paramount+): one PIN for the TV, typed when a title starts, in
  /// adults' profiles with a Google TV PIN lock only. Its row is an adult's to see.
  static const String contentPinPackage = "com.cbs.ott";

  /// What Profile Pairing's "Change PIN" sends for the content PIN: Settings opens here (ContentPin.SETTINGS_TARGET).
  static const String contentPinTarget = "content_pin";

  const StreamingPinsPage({super.key});

  @override
  State<StreamingPinsPage> createState() => _StreamingPinsPageState();
}

class _StreamingPinsPageState extends State<StreamingPinsPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();

  /// Each app with its rows, once loaded.
  List<(Map<dynamic, dynamic>, List<_PinRow>)>? _apps;
  bool _serviceOn = true;

  /// The content PIN's app and its state, in an adult's profile with the app installed; else null.
  (Map<dynamic, dynamic>, Map<dynamic, dynamic>)? _contentPin;

  /// Whether Hearth types saved PINs at all, and the last entries on this TV (newest first).
  bool _typingOn = true;
  List<Map<dynamic, dynamic>> _log = const [];
  final Map<String, String> _appLabels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = <(Map<dynamic, dynamic>, List<_PinRow>)>[];
    bool serviceOn = true;
    (Map<dynamic, dynamic>, Map<dynamic, dynamic>)? contentPin;
    final active = context.read<ProfileService?>()?.activeProfileKey;
    // Not known to be an adult's profile: no content PIN row
    final adult = !(context.read<ProfileService?>()?.isKidsProfile ?? true);
    bool typingOn = true;
    List<Map<dynamic, dynamic>> log = const [];
    try {
      typingOn = await _channel.isPinTypingOn();
      log = await _channel.getPinEntryLog();
    } catch (err) {
        noteFailure('streaming_pins_page', err);
      // An older Android side: typing on, no log
    }
    try {
      serviceOn = (await _channel.getProfilePairingStatus())["enabled"] == true;
      for (final app in await _channel.getProfilePairingApps()) {
        final pkg = app["packageName"] as String;
        _appLabels[pkg] = app["label"] as String? ?? pkg;
        if (adult && pkg == StreamingPinsPage.contentPinPackage && app["installed"] == true) {
          contentPin = (app, await _channel.getContentPinStatus(pkg));
        }
        if (app["installed"] != true || !await _channel.profilePinEntrySupported(pkg)) continue;
        final rows = <_PinRow>[];
        for (final map in await _channel.getProfilePairingChoices(pkg)) {
          final choice = PairingChoice.fromMap(map);
          if (choice.hearthProfile != active) continue;
          final appProfile = switch (choice.mode) {
            "profile" => choice.chosenProfile,
            "auto" => choice.autoMatch,
            _ => null,
          };
          rows.add(_PinRow(choice, appProfile,
              appProfile != null ? await _channel.getProfilePinStatus(pkg, appProfile) : null));
        }
        // Not seen with this app yet: matched by name, which finds nothing until a profile is picked
        if (rows.isEmpty && active != null) {
          rows.add(_PinRow(PairingChoice.fromMap({"hearthProfile": active, "mode": "auto"}), null, null));
        }
        apps.add((app, rows));
      }
    } catch (err) {
        noteFailure('streaming_pins_page', err);
      // No Android side: nothing to list
    }
    if (mounted) {
      setState(() {
        _apps = apps;
        _serviceOn = serviceOn;
        _contentPin = contentPin;
        _typingOn = typingOn;
        _log = log;
      });
    }
  }

  /// The PINs of the profile on now, typed on a phone: the parent PIN and what typing PINs involves first, as for
  /// one typed here.
  Future<void> _setUpOnPhone() async {
    final l = AppLocalizations.of(context)!;
    final labels = [for (final (app, _) in _apps ?? const <(Map<dynamic, dynamic>, List<_PinRow>)>[]) app["label"]];
    if (!await requireParentPin(context)) return;
    if (!mounted) return;
    if (!await confirmPinConsent(context, labels.join(", "))) return;
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => PhoneSetupDialog(
        title: l.pinPhoneSetupRow,
        scanText: l.pinPhoneSetupScan,
        start: _channel.startPinSetup,
        stop: _channel.stopPinSetup,
        done: () async => await _channel.getPinSetupSaved() >= 0,
      ),
    );
    if (mounted) _load();
  }

  Future<void> _setTypingOn(bool on) async {
    await _channel.setPinTypingOn(on);
    if (mounted) setState(() => _typingOn = on);
  }

  /// A log entry's outcome in words.
  static String _result(AppLocalizations l, String? result) => switch (result) {
        "ACCEPTED" => l.pinLogAccepted,
        "REJECTED" => l.pinLogRejected,
        "LOCKED_OUT" => l.pinLogLockedOut,
        "SCREEN_CHANGED" => l.pinLogScreenChanged,
        "BROKEN" => l.pinLogBroken,
        "NO_PIN_SCREEN" => l.pinLogNoScreen,
        "CANCELLED" => l.pinLogCancelled,
        _ => result ?? "?",
      };

  /// "Netflix · Oct 13, 8:04 PM · Accepted" (the content PIN's row names it as such).
  String _logLine(AppLocalizations l, Map<dynamic, dynamic> entry) {
    final pkg = entry["package"] as String? ?? "?";
    final label = _appLabels[pkg] ?? pkg;
    final app = entry["content"] == true ? l.contentPinRow(label) : label;
    final at = DateTime.fromMillisecondsSinceEpoch(entry["at"] as int? ?? 0);
    final locale = Localizations.localeOf(context).toString();
    final when = "${DateFormat.MMMd(locale).format(at)} ${DateFormat.jm(locale).format(at)}";
    return "$app · $when · ${_result(l, entry["result"] as String?)}";
  }

  /// The row's PIN: a profile with no app profile yet gets one picked first. Setting the PIN of a name match pairs it
  /// for good, only once the PIN is actually saved.
  Future<void> _edit(Map<dynamic, dynamic> app, _PinRow row) async {
    final l = AppLocalizations.of(context)!;
    final pkg = app["packageName"] as String;
    final label = app["label"] as String;
    final name = context.read<ProfileService?>()?.activeProfileName ?? row.choice.displayName;
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
          title: Text(l.pairingProfileInApp(name, label)),
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
        RoundedSwitchListTile(
          autofocus: takeFirst(),
          value: _typingOn,
          onChanged: _setTypingOn,
          title: Text(l.pinTypingSwitch, style: textTheme.bodyMedium),
          subtitle: _typingOn ? null : Text(l.pinTypingSwitchOff, style: small),
          secondary: Icon(Icons.pin_outlined, color: _typingOn ? Colors.green : Colors.white54),
        ),
        if (_serviceOn && (apps.isNotEmpty || _contentPin != null))
          FocusableSettingsTile(
            leading: const Icon(Icons.qr_code_2),
            title: Text(l.pinPhoneSetupRow, style: textTheme.bodyMedium),
            trailing: const Icon(Icons.chevron_right),
            onPressed: _setUpOnPhone,
          ),
        const Divider(),
        if (apps.isEmpty && _contentPin == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(l.streamingPinsNone, style: small),
          ),
        for (final (app, rows) in apps) ...[
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
                    Text(app["label"] as String, style: textTheme.bodyMedium),
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
        if (_contentPin case (final app, final pin))
          FocusableSettingsTile(
            autofocus: takeFirst(),
            leading: const Icon(Icons.pin_outlined),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.contentPinRow(app["label"] as String), style: textTheme.bodyMedium),
                Text("${profilePinStatus(l, pin)} · ${l.contentPinRowHint}", style: small),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onPressed: () async {
              await editContentPin(
                context,
                packageName: app["packageName"] as String,
                appLabel: app["label"] as String,
                saved: (pin["status"] as String? ?? "none") != "none",
              );
              if (mounted) _load();
            },
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l.streamingPinsFooter, style: small, textAlign: TextAlign.center),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text(l.pinLogTitle, style: textTheme.titleSmall),
        ),
        if (_log.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(l.pinLogEmpty, style: small),
          ),
        for (final entry in _log)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            child: Text(_logLine(l, entry), style: small),
          ),
      ],
    );
  }
}
