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
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/kids_profiles.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'kids_profiles_page.dart';
import 'profile_pairing_page.dart';
import 'settings_lock.dart';
import 'settings_page.dart';
import 'streaming_pins_page.dart';

/// Google TV profiles, Profile Pairing in the streaming apps, and the parent PIN.
class ProfilesSettingsPage extends StatelessWidget {
  static const String routeName = "profiles_settings";

  const ProfilesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final hasPin = context.select<SettingsService, bool>((s) => s.hasParentPin);
    final bool locked = settingsLocked(context);
    return SettingsPage(
      title: l.profilesTitle,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.people_outline),
          title: Text(l.profilesSwitchProfile, style: textTheme.bodyMedium),
          trailing: Text(activeProfileLabel(context) ?? "", style: textTheme.bodySmall),
          onPressed: () => context.read<FLauncherChannel>().openProfileChooser(),
        ),
        // Grown-up profiles: Google TV's own profile lock, now or whenever the TV wakes from a sleep
        if (!(context.select<ProfileService?, bool>((p) => p?.isKidsProfile ?? false))) ...[
          FocusableSettingsTile(
            leading: const Icon(Icons.lock_person_outlined),
            title: Text(l.profileLockNow, style: textTheme.bodyMedium),
            onPressed: () => context.read<FLauncherChannel?>()?.lockProfile(),
          ),
          const _LockOnSleepTile(),
        ],
        // No PIN of its own: in a kids profile, Settings already took the parent PIN to get here, and
        // grown-up profiles are only reached past Google TV's PIN.
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.switch_account),
            title: Text(l.profilePairingTitle, style: textTheme.bodyMedium),
            onPressed: () => Navigator.of(context).pushNamed(ProfilePairingPage.routeName),
          ),
        // Each streaming app's profile PINs in one place, matched by name or chosen in Profile Pairing
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l.streamingPinsTitle, style: textTheme.bodyMedium),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: () => Navigator.of(context).pushNamed(StreamingPinsPage.routeName),
          ),
        if (!locked) const _KidsProfilesTile(),
        // A grown-up may set their own limit here; each kid's is set in Kids' profiles, without switching to them
        if (!locked && !(context.select<ProfileService?, bool>((p) => p?.isKidsProfile ?? false)))
          const YouTubeLimitTile(),
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l.parentPinTitle, style: textTheme.bodyMedium),
            trailing: Text(hasPin ? l.parentPinOn : l.parentPinOff, style: textTheme.bodySmall),
            onPressed: () => _editParentPin(context),
          ),
      ],
    );
  }

  /// The signed-in Google TV profile's name, when Hearth knows it (and there is a ProfileService).
  static String? activeProfileLabel(BuildContext context) =>
      context.select<ProfileService?, String?>((p) => p?.activeProfileName);

  Future<void> _editParentPin(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    if (settings.hasParentPin) {
      final current = await showDialog<String>(
        context: context,
        builder: (_) => ParentPinDialog(title: l.parentPinCurrent, verify: settings.verifyParentPin),
      );
      if (current == null || !context.mounted) return;
      final bool? remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.parentPinTitle),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
            TextButton(
                autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
          ],
        ),
      );
      if (remove == null || !context.mounted) return;
      if (remove) {
        await settings.setParentPin(null);
        // The streaming apps' profile PINs were saved under the parent PIN: they go with it
        if (context.mounted) await context.read<FLauncherChannel>().removeAllProfilePins();
        return;
      }
    }
    await chooseNewParentPin(context);
  }
}

/// Kids' profiles: how many need a fix, read as the page opens (what Android lists; no adb).
class _KidsProfilesTile extends StatefulWidget {
  const _KidsProfilesTile();

  @override
  State<_KidsProfilesTile> createState() => _KidsProfilesTileState();
}

class _KidsProfilesTileState extends State<_KidsProfilesTile> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  KidsProfilesState? _state;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final map = await _channel?.getKidsProfilesState();
      if (mounted && map != null) setState(() => _state = KidsProfilesState.fromMap(map));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final state = _state;
    final needing = state?.needingFix ?? 0;
    return FocusableSettingsTile(
      leading: const Icon(Icons.child_care),
      title: Text(l.kidsProfilesTitle, style: textTheme.bodyMedium),
      trailing: state == null || state.kids.isEmpty
          ? const Icon(Icons.chevron_right, color: Colors.white54)
          : Text(needing > 0 ? l.kidsProfilesNeedFixCount(needing) : l.kidsProfilesReady,
              style: textTheme.bodySmall?.copyWith(color: needing > 0 ? Colors.amber : Colors.green)),
      onPressed: () async {
        await Navigator.of(context).pushNamed(KidsProfilesPage.routeName);
        _read();
      },
    );
  }
}

/// "Lock when the TV sleeps": Google TV's profile lock comes up as the TV wakes after sleeping at least this long.
class _LockOnSleepTile extends StatefulWidget {
  const _LockOnSleepTile();

  @override
  State<_LockOnSleepTile> createState() => _LockOnSleepTileState();
}

class _LockOnSleepTileState extends State<_LockOnSleepTile> {
  /// -1 off, 0 every time, else minutes asleep.
  static const List<int> _options = [-1, 0, 5, 15, 30, 60];
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  int _minutes = -1;

  @override
  void initState() {
    super.initState();
    _channel?.getLockOnSleepMinutes().then((m) {
      if (mounted) setState(() => _minutes = m);
    }).catchError((_) {});
  }

  static String _label(AppLocalizations l, int minutes) => switch (minutes) {
        -1 => l.parentPinOff,
        0 => l.profileLockEveryTime,
        _ => l.profileLockAfterMinutes(minutes),
      };

  Future<void> _choose() async {
    final l = AppLocalizations.of(context)!;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.profileLockOnSleep),
        children: [
          for (final option in _options)
            SimpleDialogOption(
              child: TextButton(
                autofocus: option == _minutes,
                onPressed: () => Navigator.of(context).pop(option),
                child: Row(
                  children: [
                    Icon(option == _minutes ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(_label(l, option), style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(l.profileLockNeedsGoogleLock,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await _channel?.setLockOnSleepMinutes(picked);
    if (mounted) setState(() => _minutes = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FocusableSettingsTile(
      leading: const Icon(Icons.bedtime_outlined),
      title: Text(l.profileLockOnSleep, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(_label(l, _minutes), style: Theme.of(context).textTheme.bodySmall),
      onPressed: _choose,
    );
  }
}

/// How long HearthTube may play a day for a profile: the one on now, or a kids' profile by its [profileKey]. Hearth
/// counts it on its own; with Home Assistant set up, a limit shared with the family's other devices can count too
/// (the stricter wins).
class YouTubeLimitTile extends StatefulWidget {
  final String? profileKey;
  final bool autofocus;

  const YouTubeLimitTile({super.key, this.profileKey, this.autofocus = false});

  @override
  State<YouTubeLimitTile> createState() => _YouTubeLimitTileState();
}

class _YouTubeLimitTileState extends State<YouTubeLimitTile> {
  /// 0 is no limit.
  static const List<int> _options = [0, 15, 30, 45, 60, 90, 120, 180];
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    _channel?.getYouTubeDailyMinutes(profileKey: widget.profileKey).then((m) {
      if (mounted) setState(() => _minutes = m);
    }).catchError((_) {});
  }

  static String _label(AppLocalizations l, int minutes) =>
      minutes <= 0 ? l.youTubeLimitNone : l.youTubeLimitMinutes(minutes);

  Future<void> _choose() async {
    final l = AppLocalizations.of(context)!;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.youTubeLimitTitle),
        children: [
          for (final option in _options)
            SimpleDialogOption(
              child: TextButton(
                autofocus: option == _minutes,
                onPressed: () => Navigator.of(context).pop(option),
                child: Row(
                  children: [
                    Icon(option == _minutes ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(_label(l, option), style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(l.youTubeLimitHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await _channel?.setYouTubeDailyMinutes(picked, profileKey: widget.profileKey);
    if (mounted) setState(() => _minutes = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FocusableSettingsTile(
      autofocus: widget.autofocus,
      leading: const Icon(Icons.timer_outlined),
      title: Text(l.youTubeLimitTitle, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(_label(l, _minutes), style: Theme.of(context).textTheme.bodySmall),
      onPressed: _choose,
    );
  }
}
