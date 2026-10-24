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
import 'package:flauncher/providers/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'phone_approval_page.dart';
import 'settings_lock.dart';
import 'settings_page.dart';
import 'streaming_pins_page.dart';

/// Settings > Profiles: the Google TV profile on now, short and most used first: switching, the profile lock (an
/// adult's), and its streaming app PINs. What's the whole TV's (the parent PIN, kids profiles, Profile Pairing,
/// Household sync) is in Settings > Family.
class ProfilesSettingsPage extends StatelessWidget {
  static const String routeName = "profiles_settings";

  const ProfilesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
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
        // Adult profiles: Google TV's own profile lock, now or whenever the TV wakes from a sleep, and unlocking it
        // from the owner's phone (Home Assistant), where Hearth enters the PIN
        if (!(context.select<ProfileService?, bool>((p) => p?.isKidsProfile ?? false))) ...[
          FocusableSettingsTile(
            leading: const Icon(Icons.lock_person_outlined),
            title: Text(l.profileLockNow, style: textTheme.bodyMedium),
            onPressed: () => context.read<FLauncherChannel?>()?.lockProfile(),
          ),
          const _LockOnSleepTile(),
          const PhoneApprovalTile(),
        ],
        // This profile's PINs in each streaming app, matched by name or chosen in Profile Pairing
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l.streamingPinsTitle, style: textTheme.bodyMedium),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: () => Navigator.of(context).pushNamed(StreamingPinsPage.routeName),
          ),
      ],
    );
  }

  /// The signed-in Google TV profile's name, when Hearth knows it (and there is a ProfileService).
  static String? activeProfileLabel(BuildContext context) =>
      context.select<ProfileService?, String?>((p) => p?.activeProfileName);
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

/// How long HearthTube may play a day for a profile: the one on now, or a kids profile by its [profileKey]. Hearth
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
