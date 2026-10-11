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

import 'package:flauncher/actions.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/ha_calendars.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

const List<Shadow> _shadow = [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];

/// The calendars' colors, by their place in Home Assistant's list.
const List<Color> _calendarColors = [
  Color(0xFF64B5F6),
  Color(0xFFFFB74D),
  Color(0xFF81C784),
  Color(0xFFF06292),
  Color(0xFFBA68C8),
  Color(0xFF4DD0E1),
  Color(0xFFFFF176),
  Color(0xFFA1887F),
];

Color _colorOf(HaCalendarService? service, String calendarId) {
  final i = service?.calendars.indexWhere((c) => c.entityId == calendarId) ?? -1;
  return _calendarColors[(i < 0 ? 0 : i) % _calendarColors.length];
}

/// Times of day as the top bar's clock shows them (its Time format setting), in the app's language.
class CalendarTimes {
  final DateFormat _format;

  CalendarTimes._(this._format);

  factory CalendarTimes(String timeFormat, String locale) {
    // Events start on the minute: no seconds
    final pattern = timeFormat.replaceAll(RegExp(r"[:.]ss"), "").trim();
    DateFormat format;
    try {
      format = DateFormat(pattern.isEmpty ? SettingsService.defaultTimeFormat : pattern, locale);
      format.format(DateTime(2026));
    } catch (_) {
      format = DateFormat(SettingsService.defaultTimeFormat, "en_US");
    }
    return CalendarTimes._(format);
  }

  /// From [context]'s settings and language.
  static CalendarTimes of(BuildContext context) {
    String timeFormat = SettingsService.defaultTimeFormat;
    try {
      timeFormat = context.select<SettingsService, String>((s) => s.timeFormat);
    } catch (_) {}
    return CalendarTimes(timeFormat, AppLocalizations.of(context)!.localeName);
  }

  String format(DateTime time) => _format.format(time);

  /// When [event] is on [day]: all day, "7:00 PM – 8:00 PM", "until 10:00 AM" (it began on an earlier day), or "Now ·
  /// until 8:00 PM" when it's on as of [now].
  String label(AppLocalizations l, CalendarEvent event, DateTime day, DateTime now) {
    if (event.allDay) return l.calendarAllDay;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    final startsToday = !event.start.isBefore(dayStart);
    final endsToday = !event.end.isAfter(dayEnd);
    if (!startsToday && !endsToday) return l.calendarAllDay;
    if (event.isOn(now)) return endsToday ? "${l.calendarNow} · ${l.calendarUntil(format(event.end))}" : l.calendarNow;
    if (!startsToday) return l.calendarUntil(format(event.end));
    if (!endsToday || !event.end.isAfter(event.start)) return format(event.start);
    return "${format(event.start)} – ${format(event.end)}";
  }
}

/// A day's name: today, tomorrow, or its weekday and date ("Monday, October 12").
String calendarDayName(AppLocalizations l, DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return l.weatherForecastToday;
  if (d == DateTime(today.year, today.month, today.day + 1)) return l.calendarTomorrow;
  try {
    return DateFormat.MMMMEEEEd(l.localeName).format(d);
  } catch (_) {
    return DateFormat.MMMMEEEEd("en_US").format(d);
  }
}

/// What's left of today on the calendars, over the home in Continue Watching's spot while the top bar's date and time
/// have focus (as the weather's forecast while the weather has it). Nothing in it takes focus: the date keeps it, and
/// OK on it opens the coming week ([CalendarAgendaPage]).
class CalendarTodayRow extends StatelessWidget {
  /// How many events show; more are counted on a last tile.
  static const int maxEvents = 4;

  final DateTime Function() now;

  const CalendarTodayRow({super.key, this.now = DateTime.now});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = context.watch<HaCalendarService?>();
    if (service == null || !service.available) return const SizedBox.shrink();
    final times = CalendarTimes.of(context);
    final at = now();
    final events = HaCalendarParser.eventsOn(service.events, at, at);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TitlePill(
            child: Text(
              l.calendar.toUpperCase(),
              style: text.labelLarge!.copyWith(color: Colors.white, letterSpacing: 1.0, shadows: TitlePill.textShadow),
            ),
          ),
          const SizedBox(height: 4),
          Text(l.calendarRestOfToday,
              style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w700, shadows: _shadow)),
          Text(l.calendarShowWeek, style: text.bodyLarge!.copyWith(color: Colors.white70, shadows: _shadow)),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(l.calendarNothingToday, style: text.bodyLarge!.copyWith(color: Colors.white70, shadows: _shadow))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final event in events.take(maxEvents))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _EventTile(
                      when: times.label(l, event, at, at),
                      title: event.summary.isEmpty ? l.calendarNoTitle : event.summary,
                      calendar: event.calendarName,
                      color: _colorOf(service, event.calendarId),
                      now: event.isOn(at),
                    ),
                  ),
                if (events.length > maxEvents)
                  _MoreTile(text: l.calendarMore(events.length - maxEvents)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// One event over the home: when, what, and which calendar.
class _EventTile extends StatelessWidget {
  final String when;
  final String title;
  final String calendar;
  final Color color;
  final bool now;

  const _EventTile({required this.when, required this.title, required this.calendar, required this.color, this.now = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 180,
      height: 128,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: now ? color.withOpacity(0.8) : Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when,
              style: text.bodyMedium!.copyWith(color: now ? color : Colors.white70, fontWeight: now ? FontWeight.w700 : null),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Expanded(
            child: Text(title,
                style: text.titleMedium!.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(calendar,
                  style: text.bodySmall!.copyWith(color: Colors.white60), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final String text;

  const _MoreTile({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: 112,
        height: 128,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Colors.white70)),
      );
}

/// The coming week on the calendars, opened by OK on the top bar's date and time: day by day, Up and Down move
/// through the events, Back closes it.
class CalendarAgendaPage extends StatelessWidget {
  final DateTime Function() now;

  const CalendarAgendaPage({super.key, this.now = DateTime.now});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.8),
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => const CalendarAgendaPage(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final service = context.watch<HaCalendarService?>();
    final times = CalendarTimes.of(context);
    final at = now();
    final week = service == null ? const <(DateTime, List<CalendarEvent>)>[] : HaCalendarParser.agenda(service.events, at, days: HaCalendarService.days);
    final text = Theme.of(context).textTheme;
    return Actions(
      actions: {BackIntent: BackAction(context)},
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.35),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TitlePill(
                  child: Text(
                    l.calendar.toUpperCase(),
                    style: text.labelLarge!.copyWith(color: Colors.white, letterSpacing: 1.0, shadows: TitlePill.textShadow),
                  ),
                ),
                const SizedBox(height: 4),
                Text(l.calendarNextDays(HaCalendarService.days),
                    style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w700, shadows: _shadow)),
                const SizedBox(height: 16),
                Expanded(
                  child: week.isEmpty
                      ? Focus(
                          autofocus: true,
                          child: Text(l.calendarNothingWeek(HaCalendarService.days),
                              style: text.bodyLarge!.copyWith(color: Colors.white70)),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 48),
                          children: [
                            for (final (day, events) in week) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 12, bottom: 8),
                                child: Text(calendarDayName(l, day, at),
                                    style: text.titleLarge!.copyWith(fontWeight: FontWeight.w700, shadows: _shadow)),
                              ),
                              for (final (i, event) in events.indexed)
                                _AgendaRow(
                                  autofocus: day == week.first.$1 && i == 0,
                                  when: times.label(l, event, day, at),
                                  title: event.summary.isEmpty ? l.calendarNoTitle : event.summary,
                                  detail: [event.calendarName, if (event.location != null) event.location!].join(" · "),
                                  color: _colorOf(service, event.calendarId),
                                  now: event.isOn(at),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One event in the week: a focus stop, so Up and Down scroll through them.
class _AgendaRow extends StatelessWidget {
  final bool autofocus;
  final String when;
  final String title;
  final String detail;
  final Color color;
  final bool now;

  const _AgendaRow(
      {required this.autofocus,
      required this.when,
      required this.title,
      required this.detail,
      required this.color,
      required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusableTap(
        autofocus: autofocus,
        onPressed: () {},
        onFocusChange: (focused) {
          if (focused) Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 150));
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: focused ? theme.colorScheme.primary : Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: Text(when,
                    style: text.bodyLarge!.copyWith(color: now ? color : Colors.white70, fontWeight: now ? FontWeight.w700 : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium!.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(detail, style: text.bodySmall!.copyWith(color: Colors.white60), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
