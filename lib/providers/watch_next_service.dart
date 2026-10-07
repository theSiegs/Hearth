import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_next_program.dart';

class WatchNextService extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _channel;
  List<WatchNextProgram> _programs = [];
  bool _initialized = false;
  bool _hasPermission = true;
  Timer? _refreshTimer;
  StreamSubscription<dynamic>? _watchNextSubscription;
  int _callCount = 0;
  final Map<String, Uint8List> _posters = {};
  bool _isFetching = false;
  bool _hasPendingRefresh = false;

  bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  /// The time "now" for hiding old entries (tests fix it).
  final DateTime Function() _clock;

  WatchNextService(this._channel, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    if (!_isTest) {
      WidgetsBinding.instance.addObserver(this);
    }
    _init();
  }

  /// What Continue Watching shows: the programs the active Google TV profile watched (see [_ownership]), without
  /// old or finished ones, and no more than [maxPerApp] from one app (see [selectForRow]).
  List<WatchNextProgram> get programs => List.unmodifiable(selectForRow(_programs.where(_visibleToActiveProfile), _clock()));

  /// At most this many entries from one app, so one app can't fill the row.
  static const int maxPerApp = 3;

  /// An entry left part-way is dropped after this long without being watched.
  static const Duration continueMaxAge = Duration(days: 60);

  /// An entry not started yet (next episode, new, watchlist) is dropped sooner.
  static const Duration upNextMaxAge = Duration(days: 30);

  /// Watched this far, it's finished (apps don't always remove those).
  static const double finishedFraction = 0.95;

  /// From [programs] (newest first), the ones worth showing at [now]: not old, not finished, [maxPerApp] per app.
  static List<WatchNextProgram> selectForRow(Iterable<WatchNextProgram> programs, DateTime now) {
    final shown = <WatchNextProgram>[];
    final perApp = <String, int>{};
    for (final p in programs) {
      if (_isOld(p, now) || _isFinished(p)) continue;
      final count = perApp[p.packageName] ?? 0;
      if (count >= maxPerApp) continue;
      perApp[p.packageName] = count + 1;
      shown.add(p);
    }
    return shown;
  }

  /// Engagement time in milliseconds (some apps write seconds); 0 when unknown.
  static int _engagementMillis(WatchNextProgram p) {
    final t = p.lastEngagementTime;
    return t > 0 && t < 10000000000 ? t * 1000 : t;
  }

  static bool _isOld(WatchNextProgram p, DateTime now) {
    final t = _engagementMillis(p);
    if (t <= 0) return false;
    // WATCH_NEXT_TYPE_CONTINUE is 0; next episode, new and watchlist entries haven't been started
    final maxAge = p.watchNextType == 0 ? continueMaxAge : upNextMaxAge;
    return now.millisecondsSinceEpoch - t > maxAge.inMilliseconds;
  }

  static bool _isFinished(WatchNextProgram p) =>
      p.watchNextType == 0 && p.duration > 0 && p.playbackPosition >= p.duration * finishedFraction;

  // All Google TV profiles share one Android user and so one Watch Next list. When an entry appears or is watched
  // again, Hearth gives it to the profile that last used that app on the TV (so watching on a phone lands with
  // whoever last used the app here), and shows each profile its own. Entries from before tracking are hidden, and
  // so are changes to an app no profile has used here since: better hidden than shown to the wrong person.
  // Version 2 started over: owners given before Hearth knew profiles by their lasting key could be wrong.
  static const _ownershipKey = "watch_next_owners_v2";
  Map<String, dynamic> _ownership = {};
  bool _ownershipLoaded = false;
  // The active profile's key (owners are saved by key), and its name: owners saved before keys are names.
  String? _activeProfile;
  String? _activeProfileName;

  static String _key(WatchNextProgram p) => "${p.packageName}|${p.id}";

  bool _visibleToActiveProfile(WatchNextProgram p) {
    if (p.profileOwned) return true;
    final owner = (_ownership[_key(p)] as Map?)?["owner"] as String?;
    if (!_ownershipLoaded) return true;
    if (owner == null || _activeProfile == null) return false;
    return owner == _activeProfile || (_activeProfileName != null && owner == _activeProfileName);
  }

  /// Records the active profile as the owner of entries that are new or were watched again since last time.
  Future<void> _trackOwners(List<WatchNextProgram> programs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_ownershipLoaded) {
        final raw = prefs.getString(_ownershipKey);
        _ownership = raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
        _ownershipLoaded = true;
        if (raw == null) {
          await prefs.remove("watch_next_owners"); // version 1
          // First run: what's already there predates tracking, so it has no owner.
          for (final p in programs) {
            _ownership[_key(p)] = {"owner": null, "t": p.lastEngagementTime};
          }
        }
      }
      _activeProfile = await _channel.getActiveProfileKey();
      _activeProfileName = await _channel.getActiveProfileName();
      final appUsers = await _channel.getAppLastProfiles();
      bool changed = false;
      final keys = <String>{};
      for (final p in programs) {
        if (p.profileOwned) continue;
        final key = _key(p);
        keys.add(key);
        final entry = _ownership[key] as Map?;
        if (entry == null || entry["t"] != p.lastEngagementTime) {
          // Only an app user known by profile key (names were saved before keys, when they could be wrong)
          final appUser = appUsers[p.packageName] as String?;
          _ownership[key] = {
            "owner": appUser != null && appUser.startsWith("user:") ? appUser : entry?["owner"],
            "t": p.lastEngagementTime,
          };
          changed = true;
        }
      }
      final before = _ownership.length;
      // Only the owner's own list says which of its entries are gone; another profile's (from its agent) doesn't
      if (!programs.any((p) => p.profileOwned)) _ownership.removeWhere((key, _) => !keys.contains(key));
      if (changed || _ownership.length != before) await prefs.setString(_ownershipKey, jsonEncode(_ownership));
    } catch (e) {
      log('Failed to track Continue Watching owners', name: 'WatchNextService', error: e);
    }
  }
  bool get initialized => _initialized;
  bool get hasPermission => _hasPermission;

  Future<void> _init() async {
    await refresh();
    _initialized = true;
    notifyListeners();

    try {
      _watchNextSubscription = _channel.addWatchNextChangedListener((_) {
        refresh();
      });
    } catch (e) {
      log('Failed to listen to watch next events', name: 'WatchNextService', error: e);
    }

    _startPeriodicTimer();
  }

  void _startPeriodicTimer() {
    _refreshTimer?.cancel();
    // Refresh fallback every 5 minutes (reactive ContentObserver handles real-time updates)
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      refresh();
      _startPeriodicTimer();
    }
  }

  Future<void> refresh() async {
    if (_isFetching) {
      _hasPendingRefresh = true;
      return;
    }
    _isFetching = true;

    final int callSnapshot = ++_callCount;
    try {
      final bool hasPermission = await checkPermission();
      if (callSnapshot != _callCount) return;

      _hasPermission = hasPermission;
      if (!hasPermission) {
        if (_programs.isNotEmpty) {
          _programs = [];
        }
        if (callSnapshot == _callCount) notifyListeners();
        return;
      }

      List<Map<dynamic, dynamic>> list;
      try {
        list = await _channel.getWatchNextPrograms();
      } catch (e) {
        log('Failed to fetch watch next programs', name: 'WatchNextService', error: e);
        list = const [];
      }
      if (callSnapshot != _callCount) return;

      final List<WatchNextProgram> newPrograms = [];
      for (final map in list) {
        final program = WatchNextProgram.fromMap(map);
        program.posterBytes = _posters[program.posterArtUri];
        newPrograms.add(program);
      }

      // Explicitly sort programs so the most recently watched content is first
      newPrograms.sort((a, b) {
        int timeA = a.lastEngagementTime;
        int timeB = b.lastEngagementTime;
        if (timeA > 0 && timeA < 10000000000) timeA *= 1000;
        if (timeB > 0 && timeB < 10000000000) timeB *= 1000;
        if (timeA != timeB) {
          return timeB.compareTo(timeA);
        }
        return b.id.compareTo(a.id);
      });

      if (!_isTest) await _trackOwners(newPrograms);
      if (callSnapshot != _callCount) return;
      _programs = newPrograms;
      if (callSnapshot == _callCount) notifyListeners();
      unawaited(_loadPosters(newPrograms, callSnapshot));
    } catch (e) {
      log('Failed to refresh watch next programs', name: 'WatchNextService', error: e);
    } finally {
      _isFetching = false;
      if (_hasPendingRefresh) {
        _hasPendingRefresh = false;
        refresh();
      }
    }
  }

  /// Fills in poster art after the row is on screen, three at a time, so one slow image host doesn't hold up the
  /// rest; each card updates as its poster arrives. Posters stay in memory for programs still on the row.
  Future<void> _loadPosters(List<WatchNextProgram> programs, int callSnapshot) async {
    _posters.removeWhere((uri, _) => !programs.any((p) => p.posterArtUri == uri));
    final queue = programs.where((p) => p.posterArtUri.isNotEmpty && p.posterBytes == null).toList();

    Future<void> worker() async {
      while (queue.isNotEmpty && callSnapshot == _callCount) {
        final program = queue.removeAt(0);
        try {
          final bytes = await _channel.getWatchNextPoster(program.posterArtUri).timeout(const Duration(seconds: 20));
          if (bytes == null || bytes.isEmpty) continue;
          _posters[program.posterArtUri] = bytes;
          program.posterBytes = bytes;
          if (callSnapshot == _callCount) notifyListeners();
        } catch (e) {
          log('Failed to load poster for ${program.title}', name: 'WatchNextService', error: e);
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
  }

  Future<bool> checkPermission() async {
    return await _channel.checkWatchNextPermission();
  }

  Future<bool> requestPermission() async {
    final bool granted = await _channel.requestWatchNextPermission();
    if (granted) {
      await refresh();
    }
    return granted;
  }

  Future<bool> launch(WatchNextProgram program) async {
    bool launched = false;
    if (program.intentUri.isNotEmpty) {
      try {
        launched = await _channel.launchWatchNextProgram(program.intentUri);
      } catch (e) {
        log('Failed to launch watch next program intent', name: 'WatchNextService', error: e);
      }
    }
    if (!launched && program.packageName.isNotEmpty) {
      try {
        await _channel.launchApp(program.packageName);
        launched = true;
      } catch (e) {
        log('Failed to launch app ${program.packageName}', name: 'WatchNextService', error: e);
      }
    }
    return launched;
  }

  Future<bool> deleteProgram(WatchNextProgram program) async {
    // Optimistically remove from local list for instant UI feedback
    _programs = _programs.where((p) => p.id != program.id).toList();
    notifyListeners();

    bool deleted = false;
    try {
      deleted = await _channel.deleteWatchNextProgram(program.id);
    } catch (e) {
      log('Failed to delete watch next program', name: 'WatchNextService', error: e);
    }
    return deleted;
  }

  @override
  void dispose() {
    if (!_isTest) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _watchNextSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
