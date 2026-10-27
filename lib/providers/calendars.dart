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

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../flauncher_channel.dart';
import 'package:flauncher/quiet_failure.dart';

/// Whether Hearth may read the active profile's calendars on the TV.
enum TvCalendarAccess {
  /// Not asked yet.
  unknown,
  granted,

  /// Hearth may not read them (the calendar permission isn't granted in that profile).
  denied,

  /// A kids profile whose Hearth (its agent) hasn't said yet.
  waiting,
}

/// One of the Google calendars synced to the TV, for the active profile ("tv:12", "Family").
class TvCalendar {
  /// Its id in this TV's calendar store ("tv:12"): this TV's own.
  final String id;

  /// The same calendar on every TV that has its account ("cal:" and a hash of the account and the calendar,
  /// TvCalendars.keyOf): what a profile's hidden calendars are kept by, so they follow the person. [id] when Hearth's
  /// Android side didn't say (a kids profile's agent from before keys).
  final String key;

  final String name;

  /// The Google account it belongs to (alex@example.com).
  final String account;

  /// Its color (ARGB), if it has one.
  final int? color;

  const TvCalendar(this.id, this.name, {String? key, this.account = "", this.color}) : key = key ?? id;

  /// Whether [hidden] (a profile's hidden calendars) hides it: by its key, or by its id here from before keys.
  bool hiddenBy(Set<String> hidden) => hidden.contains(key) || hidden.contains(id);

  @override
  bool operator ==(Object other) =>
      other is TvCalendar &&
      other.id == id &&
      other.key == key &&
      other.name == name &&
      other.account == account &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, key, name, account, color);

  @override
  String toString() => "$name ($id)";
}

/// One event on a calendar, in the TV's time. An all-day event runs from its first day's midnight to the midnight
/// after its last day.
class CalendarEvent {
  final String calendarId;
  final String calendarName;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  /// The event's own color (ARGB), else its calendar's.
  final int? color;

  const CalendarEvent({
    required this.calendarId,
    required this.calendarName,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.color,
  });

  /// It's on the day that starts at [day] (a midnight).
  bool occursOn(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    if (!start.isBefore(dayEnd)) return false;
    // An event with no length (a reminder) is on the day it's at
    if (!end.isAfter(start)) return !start.isBefore(dayStart);
    return end.isAfter(dayStart);
  }

  /// It has ended by [now]; all-day events last the whole day.
  bool isOver(DateTime now) {
    if (allDay) return !end.isAfter(DateTime(now.year, now.month, now.day));
    // An event with no length is over once its time has passed
    if (!end.isAfter(start)) return start.isBefore(now);
    return !end.isAfter(now);
  }

  /// It has started and not ended.
  bool isOn(DateTime now) => !allDay && !start.isAfter(now) && end.isAfter(now);

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.calendarId == calendarId &&
      other.calendarName == calendarName &&
      other.summary == summary &&
      other.start == start &&
      other.end == end &&
      other.allDay == allDay &&
      other.location == location &&
      other.color == color;

  @override
  int get hashCode => Object.hash(calendarId, calendarName, summary, start, end, allDay, location, color);

  @override
  String toString() => "$summary ($start - $end${allDay ? ", all day" : ""})";
}

/// Reading the TV's calendars and their events out of what Hearth's Android side answers (TvCalendars.java), and
/// laying the events out by day.
class CalendarParser {
  /// The prefix of a TV calendar's id, before its id in Android's calendar store.
  static const String tvPrefix = "tv:";

  /// A calendar's key, the same on every TV (TvCalendars.keyOf): "cal:" and 32 hex digits.
  static final RegExp keyPattern = RegExp(r'^cal:[0-9a-f]{32}$');

  /// getCalendarAccess: "granted", "denied" or "waiting".
  static TvCalendarAccess parseAccess(Object? value) => switch (value) {
        "granted" => TvCalendarAccess.granted,
        "waiting" => TvCalendarAccess.waiting,
        _ => TvCalendarAccess.denied,
      };

  /// getCalendars: [{"id": 12, "key": "cal:…", "name": "Family", "color": -12396910, "account": "alex@example.com"},
  /// ...], by name.
  static List<TvCalendar> parseCalendars(Object? json) {
    final out = <TvCalendar>[];
    if (json is! List) return out;
    for (final c in json) {
      if (c is! Map) continue;
      final id = c["id"];
      if (id is! int) continue;
      final name = c["name"];
      final account = c["account"];
      final key = c["key"];
      out.add(TvCalendar("$tvPrefix$id", name is String && name.trim().isNotEmpty ? name.trim() : "$id",
          key: key is String && keyPattern.hasMatch(key) ? key : null,
          account: account is String ? account : "",
          color: _color(c["color"])));
    }
    out.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return out;
  }

  /// getCalendarEvents: [{"calendarId": 12, "calendarName": "Family", "color": ..., "title": ..., "location": ...,
  /// "start": ms, "end": ms, "allDay": bool}, ...]. An all-day event's times are midnights in UTC: it's on those
  /// days here. Events it can't read are left out.
  static List<CalendarEvent> parseEvents(Object? json) {
    final out = <CalendarEvent>[];
    if (json is! List) return out;
    for (final e in json) {
      if (e is! Map) continue;
      final calendarId = e["calendarId"];
      final startMs = e["start"];
      if (calendarId is! int || startMs is! int) continue;
      final endMs = e["end"] is int ? e["end"] as int : startMs;
      final allDay = e["allDay"] == true;
      DateTime start, end;
      if (allDay) {
        start = _day(startMs);
        end = _day(endMs);
        if (!end.isAfter(start)) end = DateTime(start.year, start.month, start.day + 1);
      } else {
        start = DateTime.fromMillisecondsSinceEpoch(startMs);
        end = DateTime.fromMillisecondsSinceEpoch(endMs < startMs ? startMs : endMs);
      }
      final title = e["title"];
      final location = e["location"];
      final calendarName = e["calendarName"];
      out.add(CalendarEvent(
        calendarId: "$tvPrefix$calendarId",
        calendarName: calendarName is String ? calendarName.trim() : "",
        summary: title is String && title.trim().isNotEmpty ? title.trim() : "",
        start: start,
        end: end,
        allDay: allDay,
        location: location is String && location.trim().isNotEmpty ? location.trim() : null,
        color: _color(e["color"]),
      ));
    }
    return out;
  }

  /// A UTC midnight as that day's midnight here.
  static DateTime _day(int ms) {
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Android's color (a signed ARGB int) as an opaque ARGB value.
  static int? _color(Object? value) => value is int ? (value & 0xFFFFFF) | 0xFF000000 : null;

  /// [events] on the day of [day], in order: all-day ones first, then by start. On today ([now]'s day), those that
  /// have ended are left out.
  static List<CalendarEvent> eventsOn(Iterable<CalendarEvent> events, DateTime day, DateTime now) {
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final out = events.where((e) => e.occursOn(day) && !(isToday && e.isOver(now))).toList();
    out.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      final byStart = a.allDay ? 0 : a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
    });
    return out;
  }

  /// [days] days from [now]'s, each with its events (see [eventsOn]); days with nothing on are left out.
  static List<(DateTime, List<CalendarEvent>)> agenda(Iterable<CalendarEvent> events, DateTime now, {int days = 7}) {
    final out = <(DateTime, List<CalendarEvent>)>[];
    for (var i = 0; i < days; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final on = eventsOn(events, day, now);
      if (on.isNotEmpty) out.add((day, on));
    }
    return out;
  }
}

/// What the TV's calendar store said for the active profile.
typedef CalendarReading = ({TvCalendarAccess access, List<TvCalendar> calendars, List<CalendarEvent> events});

/// The coming week of the active profile's Google calendars on the TV (Android's calendar store, which Google's
/// calendar sync fills), for the top bar's date and time. Only the profile's own: an adult's account's calendars,
/// or a kids profile's own (relayed by Hearth there). Without calendar access, or with no calendar, [available] stays
/// false and nothing new shows. Readings are kept a few minutes.
class CalendarService extends ChangeNotifier {
  /// How long a reading is kept before it's asked for again.
  static const Duration cacheFor = Duration(minutes: 5);

  /// After a failed try (or a kids profile whose Hearth hasn't reported yet), how long until the next.
  static const Duration retryAfter = Duration(minutes: 1);

  /// How often it reads them in the background.
  static const Duration refreshEvery = Duration(minutes: 15);

  /// Events older than this (a reading that keeps failing) are dropped.
  static const Duration keepStaleFor = Duration(hours: 12);

  /// How many days it reads, today included.
  static const int days = 7;

  final Future<CalendarReading> Function(DateTime from, DateTime to) _read;
  final Future<bool> Function()? _requestAccess;
  final List<String> Function() _hidden;

  /// Puts each calendar's key in place of its id here in the profile's hidden calendars (from before keys).
  final Future<void> Function(Map<String, String> idToKey)? _rekeyHidden;
  final String? Function() _profileKey;
  final DateTime Function() _now;
  final Listenable? _settings;

  TvCalendarAccess _access = TvCalendarAccess.unknown;
  List<TvCalendar> _calendars = const [];
  List<CalendarEvent> _events = const [];
  DateTime? _triedAt;
  DateTime? _readAt;
  bool _lastTryFailed = false;
  Future<void>? _inFlight;
  Timer? _timer;
  String _hiddenKey = "";
  String? _readFor;
  bool _disposed = false;

  CalendarService({
    required Future<CalendarReading> Function(DateTime from, DateTime to) read,
    required List<String> Function() hiddenCalendars,
    Future<void> Function(Map<String, String> idToKey)? rekeyHiddenCalendars,
    Future<bool> Function()? requestAccess,
    String? Function()? profileKey,
    DateTime Function()? now,
    Listenable? settings,
  })  : _read = read,
        _requestAccess = requestAccess,
        _hidden = hiddenCalendars,
        _rekeyHidden = rekeyHiddenCalendars,
        _profileKey = profileKey ?? (() => null),
        _now = now ?? DateTime.now,
        _settings = settings {
    _hiddenKey = _hidden().join("\n");
    _readFor = _profileKey();
    _settings?.addListener(_settingsChanged);
  }

  /// Reads Hearth's Android side over [channel].
  static Future<CalendarReading> readChannel(FLauncherChannel channel, DateTime from, DateTime to) async {
    final access = CalendarParser.parseAccess(await channel.getCalendarAccess());
    if (access != TvCalendarAccess.granted) return (access: access, calendars: const <TvCalendar>[], events: const <CalendarEvent>[]);
    final calendars = CalendarParser.parseCalendars(await channel.getCalendars());
    final events = CalendarParser.parseEvents(await channel.getCalendarEvents(from, to));
    return (access: access, calendars: calendars, events: events);
  }

  /// Reads the calendars now and then every [refreshEvery].
  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(refreshEvery, (_) => refresh());
  }

  TvCalendarAccess get access => _access;

  /// Every calendar of this profile on the TV, shown or not.
  List<TvCalendar> get calendars => _calendars;

  /// The calendars this profile shows (all but those turned off).
  List<TvCalendar> get shownCalendars {
    final hidden = _hidden().toSet();
    return _calendars.where((c) => !c.hiddenBy(hidden)).toList();
  }

  /// There's a calendar this profile shows: the date and time take focus.
  bool get available => _access == TvCalendarAccess.granted && shownCalendars.isNotEmpty;

  /// The shown calendars' events over the coming [days].
  List<CalendarEvent> get events {
    final hidden = _hidden().toSet();
    final hiddenIds = {...hidden, for (final c in _calendars) if (c.hiddenBy(hidden)) c.id};
    return _events.where((e) => !hiddenIds.contains(e.calendarId)).toList();
  }

  /// What's left of today.
  List<CalendarEvent> today() {
    final now = _now();
    return CalendarParser.eventsOn(events, now, now);
  }

  /// The coming [days], each with what's on (days with nothing are left out).
  List<(DateTime, List<CalendarEvent>)> week() => CalendarParser.agenda(events, _now(), days: days);

  /// Asks to read this profile's calendars (Android's permission dialog for an adult; for a kids profile, Hearth
  /// grants it there itself when the TV trusts it), then reads them. Whether it may now.
  Future<bool> requestAccess() async {
    var granted = false;
    try {
      granted = await (_requestAccess?.call() ?? Future.value(false));
    } catch (err) { noteFailure('calendars', err); }
    await refresh(force: true);
    return granted || _access == TvCalendarAccess.granted;
  }

  /// Reads the calendars again, unless they were read in the last [cacheFor] (or tried and failed in the last
  /// [retryAfter]); [force] reads them anyway. Never throws.
  Future<void> refresh({bool force = false}) {
    final now = _now();
    final wait = _lastTryFailed ? retryAfter : cacheFor;
    if (!force && _triedAt != null && now.difference(_triedAt!) < wait) return Future.value();
    return _inFlight ??= _readNow().whenComplete(() => _inFlight = null);
  }

  Future<void> _readNow() async {
    final now = _now();
    _triedAt = now;
    final profile = _profileKey();
    // A day either side: all-day events are read by their UTC days
    final from = DateTime(now.year, now.month, now.day - 1);
    final to = DateTime(now.year, now.month, now.day + days + 1);
    try {
      final reading = await _read(from, to);
      if (profile != _profileKey()) return; // the profile changed meanwhile: its own reading follows
      _lastTryFailed = reading.access == TvCalendarAccess.waiting;
      if (reading.access == TvCalendarAccess.granted) _readAt = now;
      _set(reading.access, reading.calendars, reading.events);
      await _rekey(reading.calendars);
    } catch (err) {
        noteFailure('calendars', err);
      _lastTryFailed = true;
      // Quietly: what was read last stays a while
      if (_readAt == null || now.difference(_readAt!) > keepStaleFor) {
        _set(_access, const [], const []);
      }
    }
  }

  /// The profile's calendars hidden by their id here (from before keys) are kept by their key from now on, so they
  /// follow the person to the household's other TVs. Once per profile: a calendar it hides later is kept by its key.
  Future<void> _rekey(List<TvCalendar> calendars) async {
    final rekey = _rekeyHidden;
    if (rekey == null || _disposed) return;
    final hidden = _hidden().toSet();
    final idToKey = {
      for (final c in calendars)
        if (c.key != c.id && hidden.contains(c.id)) c.id: c.key,
    };
    if (idToKey.isEmpty) return;
    try {
      await rekey(idToKey);
    } catch (err) {
      noteFailure('calendars', err);
    }
  }

  void _set(TvCalendarAccess access, List<TvCalendar> calendars, List<CalendarEvent> events) {
    if (_disposed) return;
    final changed = access != _access || !listEquals(calendars, _calendars) || !listEquals(events, _events);
    _access = access;
    _calendars = List.unmodifiable(calendars);
    _events = List.unmodifiable(events);
    if (changed) notifyListeners();
  }

  /// A profile switch reads the new profile's calendars; a calendar turned on or off changes what shows.
  void _settingsChanged() {
    final profile = _profileKey();
    if (profile != _readFor) {
      _readFor = profile;
      _hiddenKey = _hidden().join("\n");
      _readAt = null;
      _set(TvCalendarAccess.unknown, const [], const []);
      // A reading under way is the last profile's (and is dropped): this one's comes after it
      final pending = _inFlight;
      unawaited(pending != null ? pending.whenComplete(() => refresh(force: true)) : refresh(force: true));
      return;
    }
    final key = _hidden().join("\n");
    if (key == _hiddenKey) return;
    _hiddenKey = key;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _settings?.removeListener(_settingsChanged);
    super.dispose();
  }
}
