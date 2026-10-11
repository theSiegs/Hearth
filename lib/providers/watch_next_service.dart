import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flauncher/flauncher_channel.dart';
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
    // Who-watched-what records from before Hearth read each profile's own list; nothing reads them any more
    for (final key in const ["watch_next_owners_v2", "watch_next_owners"]) {
      if (_sharedPreferences.containsKey(key)) unawaited(_sharedPreferences.remove(key));
    }
    _init();
  }

  /// What Continue Watching shows: the active Google TV profile's own programs (see [_visibleToActiveProfile]), without
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

  // Each kids profile is its own Android user with its own Watch Next list, which comes from that profile's agent
  // (marked profileOwned). Hearth reads the owner's (user 0) itself, and that list is all the grown-ups' profiles'
  // (each a Google account in user 0): an entry is the profile's that had its app open when it was last watched
  // (watchedBy), else the owner's first profile's. So it never shows while another profile is on (for a kids
  // profile Hearth reads only its agent's list, but the list may still be the owner's for a moment around a switch).
  static const String _ownerProfile = "user:0";
  // The active profile's key, read with each refresh; null while Hearth can't tell.
  String? _activeProfile;

  /// The active profile changed: the owner's entries stop showing at once if it's another profile (its own list
  /// comes from its agent, if it has one), and the list is read again for it.
  void profileChanged(String? key) {
    if (key == _activeProfile) return;
    _activeProfile = key;
    notifyListeners();
    refresh();
  }

  bool _visibleToActiveProfile(WatchNextProgram p) =>
      p.profileOwned || _activeProfile == null || (p.watchedBy ?? _ownerProfile) == _activeProfile;

  /// One line in the TV's log per refresh (tag flutter, "HearthWatchNext"): how many entries there are, how many
  /// Continue Watching shows, and why the rest are hidden. Counts and package names only, no titles.
  void _logWhatShows() {
    final visible = _programs.where(_visibleToActiveProfile).toList();
    final shown = selectForRow(visible, _clock());
    final apps = {for (final p in _programs) p.packageName}.join(",");
    debugPrint("HearthWatchNext: ${_programs.length} entries, ${shown.length} shown for $_activeProfile; hidden: "
        "otherProfile=${_programs.length - visible.length} oldFinishedOrPerApp=${visible.length - shown.length}; "
        "apps=$apps");
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
      _activeProfile = refreshedFor;
      _programs = newPrograms;
      _refreshedFor = refreshedFor;
      _logWhatShows();
      notifyListeners();
      // Only for what Continue Watching shows: the list holds every profile's entries, finished and old ones too
      unawaited(_loadPosters(programs, callSnapshot));
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
