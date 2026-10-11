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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A Home Assistant calendar ("calendar.family", "Family").
class HaCalendar {
  final String entityId;
  final String name;

  const HaCalendar(this.entityId, this.name);

  @override
  bool operator ==(Object other) => other is HaCalendar && other.entityId == entityId && other.name == name;

  @override
  int get hashCode => Object.hash(entityId, name);

  @override
  String toString() => "$name ($entityId)";
}

/// One event from a Home Assistant calendar, in the TV's time. An all-day event runs from its first day's midnight
/// to the midnight after its last day.
class CalendarEvent {
  final String calendarId;
  final String calendarName;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  const CalendarEvent({
    required this.calendarId,
    required this.calendarName,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
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
  String toString() => "$summary ($start - $end${allDay ? ", all day" : ""})";
}

/// Reading Home Assistant's calendars and what's in them out of its REST API's replies.
class HaCalendarParser {
  /// GET /api/calendars: [{"entity_id": "calendar.family", "name": "Family"}, ...]
  static List<HaCalendar> parseCalendars(Object? json) {
    final out = <HaCalendar>[];
    if (json is! List) return out;
    for (final c in json) {
      if (c is! Map) continue;
      final id = c["entity_id"];
      if (id is! String || id.isEmpty) continue;
      final name = c["name"];
      out.add(HaCalendar(id, name is String && name.isNotEmpty ? name : id));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// GET /api/calendars/<entity_id>: [{"summary": ..., "start": {"dateTime" or "date": ...}, "end": {...},
  /// "location": ...}, ...]. Events it can't read are left out.
  static List<CalendarEvent> parseEvents(Object? json, HaCalendar calendar) {
    final out = <CalendarEvent>[];
    if (json is! List) return out;
    for (final e in json) {
      if (e is! Map) continue;
      final start = _when(e["start"]);
      if (start == null) continue;
      final allDay = start.$2;
      final parsedEnd = _when(e["end"]);
      // Without an end: an hour, or the one day
      var end = parsedEnd?.$1 ??
          (allDay ? DateTime(start.$1.year, start.$1.month, start.$1.day + 1) : start.$1.add(const Duration(hours: 1)));
      if (end.isBefore(start.$1)) end = start.$1;
      final summary = e["summary"];
      final location = e["location"];
      out.add(CalendarEvent(
        calendarId: calendar.entityId,
        calendarName: calendar.name,
        summary: summary is String && summary.trim().isNotEmpty ? summary.trim() : "",
        start: start.$1,
        end: end,
        allDay: allDay,
        location: location is String && location.trim().isNotEmpty ? location.trim() : null,
      ));
    }
    return out;
  }

  /// {"dateTime": "2026-10-10T19:00:00-05:00"} in the TV's time, or {"date": "2026-10-10"} as that day's midnight
  /// (all day); a bare string is read the same way. Null when it can't be read.
  static (DateTime, bool)? _when(Object? value) {
    Object? dateTime, date;
    if (value is Map) {
      dateTime = value["dateTime"] ?? value["date_time"];
      date = value["date"];
    } else if (value is String) {
      if (value.length <= 10) {
        date = value;
      } else {
        dateTime = value;
      }
    }
    if (dateTime is String) {
      final parsed = DateTime.tryParse(dateTime);
      if (parsed != null) return (parsed.isUtc ? parsed.toLocal() : parsed, false);
    }
    if (date is String) {
      final parsed = DateTime.tryParse(date);
      if (parsed != null) return (DateTime(parsed.year, parsed.month, parsed.day), true);
    }
    return null;
  }

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

/// Home Assistant's calendars over its REST API, with the long-lived token the panel uses.
class HaCalendarClient {
  static const Duration timeout = Duration(seconds: 10);

  final String baseUrl;
  final String token;
  final Future<Object?> Function(Uri uri, String token) _getJson;

  HaCalendarClient(this.baseUrl, this.token, {Future<Object?> Function(Uri uri, String token)? getJson})
      : _getJson = getJson ?? _httpGetJson;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.trim().replaceAll(RegExp(r"/+$"), ""));
    return base.replace(path: "${base.path}$path", queryParameters: query);
  }

  Future<List<HaCalendar>> calendars() async => HaCalendarParser.parseCalendars(await _getJson(_uri("/api/calendars"), token));

  /// [calendar]'s events between [start] and [end].
  Future<List<CalendarEvent>> events(HaCalendar calendar, DateTime start, DateTime end) async {
    final json = await _getJson(
        _uri("/api/calendars/${calendar.entityId}", {
          "start": start.toUtc().toIso8601String(),
          "end": end.toUtc().toIso8601String(),
        }),
        token);
    return HaCalendarParser.parseEvents(json, calendar);
  }

  static Future<Object?> _httpGetJson(Uri uri, String token) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, "Bearer $token");
      request.headers.set(HttpHeaders.acceptHeader, "application/json");
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) throw HttpException("HTTP ${response.statusCode}", uri: uri);
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }
}

/// Whether the calendars could be read.
enum HaCalendarStatus {
  /// Not asked yet.
  unknown,

  /// Home Assistant isn't set up on this TV (it's optional).
  notSetUp,

  /// It's set up but didn't answer (or turned the token down).
  unreachable,
  ok,
}

/// The coming week of the Home Assistant calendars this profile shows, for the top bar's date and time. Without
/// Home Assistant there's nothing: [available] stays false and nothing new shows. Results are kept a few minutes,
/// and a Home Assistant that can't be reached is tried again quietly a little later.
class HaCalendarService extends ChangeNotifier {
  /// How long a reading is kept before it's asked for again.
  static const Duration cacheFor = Duration(minutes: 5);

  /// After a failed try, how long until the next.
  static const Duration retryAfter = Duration(minutes: 1);

  /// How often it reads them in the background.
  static const Duration refreshEvery = Duration(minutes: 15);

  /// Events older than this (Home Assistant gone for a long while) are dropped.
  static const Duration keepStaleFor = Duration(hours: 12);

  /// How many days it reads, today included.
  static const int days = 7;

  final Future<({String url, String token})?> Function() _connection;
  final HaCalendarClient Function(String url, String token) _client;
  final List<String> Function() _hidden;
  final DateTime Function() _now;
  final Listenable? _settings;

  HaCalendarStatus _status = HaCalendarStatus.unknown;
  List<HaCalendar> _calendars = const [];
  List<CalendarEvent> _events = const [];
  DateTime? _triedAt;
  DateTime? _readAt;
  bool _lastTryFailed = false;
  Future<void>? _inFlight;
  Timer? _timer;
  String _hiddenKey = "";
  bool _disposed = false;

  HaCalendarService({
    required Future<({String url, String token})?> Function() connection,
    required List<String> Function() hiddenCalendars,
    HaCalendarClient Function(String url, String token)? client,
    DateTime Function()? now,
    Listenable? settings,
  })  : _connection = connection,
        _hidden = hiddenCalendars,
        _client = client ?? ((url, token) => HaCalendarClient(url, token)),
        _now = now ?? DateTime.now,
        _settings = settings {
    _hiddenKey = _hidden().join("\n");
    _settings?.addListener(_settingsChanged);
  }

  /// Reads the calendars now and then every [refreshEvery].
  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(refreshEvery, (_) => refresh());
  }

  HaCalendarStatus get status => _status;

  /// Every calendar Home Assistant has, shown or not.
  List<HaCalendar> get calendars => _calendars;

  /// The calendars this profile shows (all but those turned off).
  List<HaCalendar> get shownCalendars {
    final hidden = _hidden().toSet();
    return _calendars.where((c) => !hidden.contains(c.entityId)).toList();
  }

  /// Home Assistant is set up and has a calendar this profile shows: the date and time take focus.
  bool get available => _calendars.isNotEmpty && _status != HaCalendarStatus.notSetUp && shownCalendars.isNotEmpty;

  /// The shown calendars' events over the coming [days].
  List<CalendarEvent> get events {
    final hidden = _hidden().toSet();
    return _events.where((e) => !hidden.contains(e.calendarId)).toList();
  }

  /// What's left of today.
  List<CalendarEvent> today() {
    final now = _now();
    return HaCalendarParser.eventsOn(events, now, now);
  }

  /// The coming [days], each with what's on (days with nothing are left out).
  List<(DateTime, List<CalendarEvent>)> week() => HaCalendarParser.agenda(events, _now(), days: days);

  /// Reads the calendars again, unless they were read in the last [cacheFor] (or tried and failed in the last
  /// [retryAfter]); [force] reads them anyway. Never throws.
  Future<void> refresh({bool force = false}) {
    final now = _now();
    final wait = _lastTryFailed ? retryAfter : cacheFor;
    if (!force && _triedAt != null && now.difference(_triedAt!) < wait) return Future.value();
    return _inFlight ??= _read().whenComplete(() => _inFlight = null);
  }

  Future<void> _read() async {
    final now = _now();
    _triedAt = now;
    ({String url, String token})? connection;
    try {
      connection = await _connection();
    } catch (_) {}
    if (connection == null || connection.url.trim().isEmpty || connection.token.isEmpty) {
      _lastTryFailed = false;
      _set(HaCalendarStatus.notSetUp, const [], const []);
      return;
    }
    try {
      final client = _client(connection.url, connection.token);
      final calendars = await client.calendars();
      final from = DateTime(now.year, now.month, now.day);
      final to = DateTime(now.year, now.month, now.day + days);
      final events = <CalendarEvent>[];
      var anyRead = calendars.isEmpty;
      for (final calendar in calendars) {
        try {
          events.addAll(await client.events(calendar, from, to));
          anyRead = true;
        } catch (_) {
          // One calendar that can't be read leaves the others
          events.addAll(_events.where((e) => e.calendarId == calendar.entityId));
        }
      }
      if (!anyRead) throw const HttpException("no calendar could be read");
      _lastTryFailed = false;
      _readAt = now;
      _set(HaCalendarStatus.ok, calendars, events);
    } catch (_) {
      _lastTryFailed = true;
      // Quietly: what was read last stays a while
      final stale = _readAt == null || now.difference(_readAt!) > keepStaleFor;
      _set(HaCalendarStatus.unreachable, stale ? const [] : _calendars, stale ? const [] : _events);
    }
  }

  void _set(HaCalendarStatus status, List<HaCalendar> calendars, List<CalendarEvent> events) {
    if (_disposed) return;
    final changed = status != _status ||
        !listEquals(calendars, _calendars) ||
        events.length != _events.length ||
        !_sameEvents(events, _events);
    _status = status;
    _calendars = List.unmodifiable(calendars);
    _events = List.unmodifiable(events);
    if (changed) notifyListeners();
  }

  static bool _sameEvents(List<CalendarEvent> a, List<CalendarEvent> b) {
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.calendarId != y.calendarId ||
          x.summary != y.summary ||
          x.start != y.start ||
          x.end != y.end ||
          x.allDay != y.allDay ||
          x.location != y.location) {
        return false;
      }
    }
    return true;
  }

  /// A profile switch or a calendar turned on or off changes what shows.
  void _settingsChanged() {
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
