import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_next_program.dart';
import 'apps_service.dart';
import 'settings_service.dart';

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

  /// The time "now" for hiding old entries (tests fix it).
  final DateTime Function() _clock;

  final SharedPreferences _sharedPreferences;

  WatchNextService(this._channel, this._sharedPreferences, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
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

  /// Engagement times below this are in seconds: as milliseconds it would be April 1970, as seconds it's 2286.
  static const int _secondsCutoff = 10000000000;

  /// Engagement time in milliseconds (some apps write seconds); 0 when unknown.
  static int _engagementMillis(WatchNextProgram p) {
    final t = p.lastEngagementTime;
    return t > 0 && t < _secondsCutoff ? t * 1000 : t;
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

  // All Google TV profiles share one Watch Next list. An entry belongs to the profile that last used its app here;
  // entries with no known owner are hidden.
  static const _ownershipKey = "watch_next_owners_v2";
  Map<String, dynamic> _ownership = {};
  bool _ownershipLoaded = false;
  // The active profile's key; owners are saved by key.
  String? _activeProfile;

  static String _key(WatchNextProgram p) => "${p.packageName}|${p.id}";

  bool _visibleToActiveProfile(WatchNextProgram p) {
    if (p.profileOwned) return true;
    final owner = (_ownership[_key(p)] as Map?)?["owner"] as String?;
    if (!_ownershipLoaded) return true;
    if (owner == null || _activeProfile == null) return false;
    return owner == _activeProfile;
  }

  /// Records the active profile as the owner of entries that are new or were watched again since last time.
  Future<void> _trackOwners(List<WatchNextProgram> programs) async {
    try {
      if (!_ownershipLoaded) {
        final raw = _sharedPreferences.getString(_ownershipKey);
        _ownership = raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
        _ownershipLoaded = true;
        if (raw == null) {
          await _sharedPreferences.remove("watch_next_owners"); // drop the v1 store
          // First run: what's already there predates tracking, so it has no owner.
          for (final p in programs) {
            _ownership[_key(p)] = {"owner": null, "t": p.lastEngagementTime};
          }
        }
      }
      _activeProfile = await _channel.getActiveProfileKey();
      final appUsers = await _channel.getAppLastProfiles();
      bool changed = false;
      final keys = <String>{};
      for (final p in programs) {
        if (p.profileOwned) continue;
        final key = _key(p);
        keys.add(key);
        final entry = _ownership[key] as Map?;
        if (entry == null || entry["t"] != p.lastEngagementTime) {
          // Only a profile key ("user:11") makes an owner
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
      if (changed || _ownership.length != before) await _sharedPreferences.setString(_ownershipKey, jsonEncode(_ownership));
    } catch (e) {
      log('Failed to track Continue Watching owners', name: 'WatchNextService', error: e);
    }
  }

  @visibleForTesting
  bool get initialized => _initialized;

  String? _refreshedFor;

  /// The profile (key) the programs were last read for: after a switch, the row is this profile's once it matches.
  String? get refreshedFor => _refreshedFor;

  final Set<String> _postersTried = {};

  /// The first few cards' posters are in (or failed, or there are none): what a profile switch waits for.
  bool get postersSettled => programs
      .take(3)
      .every((p) => p.posterArtUri.isEmpty || p.posterBytes != null || _postersTried.contains(p.posterArtUri));
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

    // Only one refresh runs at a time; the count stops an earlier refresh's poster loading.
    final int callSnapshot = ++_callCount;
    try {
      _hasPermission = await checkPermission();
      if (!_hasPermission) {
        _programs = [];
        notifyListeners();
        return;
      }

      final List<WatchNextProgram> newPrograms = [];
      for (final map in await _channel.getWatchNextPrograms()) {
        final program = WatchNextProgram.fromMap(map);
        program.posterBytes = _posters[program.posterArtUri];
        newPrograms.add(program);
      }

      // Newest first
      newPrograms.sort((a, b) {
        final timeA = _engagementMillis(a), timeB = _engagementMillis(b);
        if (timeA != timeB) {
          return timeB.compareTo(timeA);
        }
        return b.id.compareTo(a.id);
      });

      String? refreshedFor;
      try {
        refreshedFor = await _channel.getActiveProfileKey();
      } catch (e) {
        log('Failed to read the active profile', name: 'WatchNextService', error: e);
      }
      await _trackOwners(newPrograms);
      _programs = newPrograms;
      _refreshedFor = refreshedFor;
      notifyListeners();
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
          _postersTried.add(program.posterArtUri);
          if (bytes == null || bytes.isEmpty) {
            if (callSnapshot == _callCount) notifyListeners();
            continue;
          }
          _posters[program.posterArtUri] = bytes;
          program.posterBytes = bytes;
          if (callSnapshot == _callCount) notifyListeners();
        } catch (e) {
          log('Failed to load poster for ${program.title}', name: 'WatchNextService', error: e);
          _postersTried.add(program.posterArtUri);
          if (callSnapshot == _callCount) notifyListeners();
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

  /// Hides or shows an app's entries (the choice is kept in [settings]) and re-reads the list.
  Future<void> setPackageHidden(SettingsService settings, String packageName, bool hidden) async {
    if (hidden) {
      await settings.hideWatchNextPackage(packageName);
    } else {
      await settings.unhideWatchNextPackage(packageName);
    }
    await refresh();
  }

  /// Shows every app's entries again.
  Future<void> unhideAll(SettingsService settings) async {
    await settings.unhideAllWatchNextPackages();
    await refresh();
  }

  Future<bool> launch(WatchNextProgram program) async {
    bool launched = false;
    if (program.intentUri.isNotEmpty) {
      launched = await _channel.launchWatchNextProgram(program.intentUri);
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

    return _channel.deleteWatchNextProgram(program.id);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchNextSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

extension VisibleWatchNext on WatchNextService {
  /// The programs Continue Watching shows: not hidden in Settings, from an app that isn't hidden, and from an app
  /// this profile can open (a kids profile blocks the rest). The home and the row both decide from this.
  List<WatchNextProgram> visiblePrograms(SettingsService settings, AppsService apps) {
    final hiddenIds = settings.hiddenWatchNextProgramIds;
    final hiddenPackages = settings.hiddenWatchNextPackages;
    return programs
        .where((p) =>
            !hiddenIds.contains(p.id.toString()) &&
            !hiddenPackages.contains(p.packageName) &&
            !apps.applications.any((app) => app.packageName == p.packageName && app.hidden) &&
            (apps.applications.isEmpty ||
                apps.applications.any((app) => app.packageName == p.packageName && !app.suspended)))
        .toList();
  }
}
