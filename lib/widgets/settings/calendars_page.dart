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
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/calendars.dart';
import '../../providers/profile_service.dart';
import '../../providers/settings_service.dart';
import '../rounded_switch_list_tile.dart';
import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// The active profile's Google calendars on the TV that show by the top bar's date and time: all of them unless some
/// are turned off here (each profile its own). Without calendar access, a way to allow it.
class CalendarsPage extends StatefulWidget {
  static const String routeName = "calendars";

  const CalendarsPage({super.key});

  @override
  State<CalendarsPage> createState() => _CalendarsPageState();
}

class _CalendarsPageState extends State<CalendarsPage> {
  bool _loading = true;
  bool _asking = false;

  /// Asking didn't get access (turned down, or a kids profile Hearth couldn't let read them by itself).
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads them again, so a calendar just synced (or access just allowed elsewhere) shows here.
  Future<void> _load() async {
    await context.read<CalendarService?>()?.refresh(force: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _allow() async {
    final service = context.read<CalendarService?>();
    if (service == null || _asking) return;
    setState(() => _asking = true);
    final granted = await service.requestAccess();
    if (mounted) {
      setState(() {
        _asking = false;
        _refused = !granted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = context.watch<CalendarService?>();
    final hidden = context.select<SettingsService, String>((s) => s.hiddenCalendars.join("\n")).split("\n").toSet();
    bool kids = false;
    try {
      kids = context.select<ProfileService, bool>((p) => p.isKidsProfile);
    } catch (err) { noteFailure('calendars_page', err); }
    final calendars = service?.calendars ?? const <TvCalendar>[];
    final access = service?.access ?? TvCalendarAccess.denied;
    final kidsFixPlace = "${l.settingsTitle} > ${l.profilesTitle} > ${l.kidsProfilesTitle}";
    final needsAccess = access == TvCalendarAccess.denied;
    String? note;
    if (_loading && calendars.isEmpty && access == TvCalendarAccess.unknown) {
      note = l.calendarsLoading;
    } else if (access == TvCalendarAccess.waiting) {
      note = l.calendarsWaiting;
    } else if (needsAccess) {
      note = _refused ? (kids ? l.calendarsKidsAccess(kidsFixPlace) : l.calendarsDenied) : l.calendarsAccessHelp;
    } else if (access == TvCalendarAccess.granted && calendars.isEmpty) {
      note = l.calendarsNone;
    }
    return SettingsPage(
      title: l.calendarsTitle,
      children: [
        if (needsAccess)
          FocusableSettingsTile(
            key: const Key("calendars_allow"),
            autofocus: true,
            leading: const Icon(Icons.lock_open_outlined),
            title: Text(l.calendarsAllow, style: Theme.of(context).textTheme.bodyMedium),
            trailing: _asking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onPressed: _allow,
          ),
        for (final (i, calendar) in calendars.indexed)
          RoundedSwitchListTile(
            autofocus: i == 0,
            value: !calendar.hiddenBy(hidden),
            onChanged: (shown) =>
                context.read<SettingsService>().setCalendarShown(calendar.key, shown, id: calendar.id),
            title: Text(calendar.name),
            subtitle: calendar.account.isEmpty || calendar.account == calendar.name ? null : Text(calendar.account),
            secondary: Icon(Icons.event_outlined,
                color: calendar.color == null ? null : Color(calendar.color!)),
          ),
        if (note != null)
          Focus(autofocus: calendars.isEmpty && !needsAccess, child: _note(context, note)),
        const SizedBox(height: 8),
        _note(context, l.calendarsHelp),
      ],
    );
  }
}

Widget _note(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
    );
