import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'open_meteo_client.dart';

class WeatherService extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _channel;
  final SharedPreferences _sharedPreferences;
  final OpenMeteoClient _openMeteo;
  // Shared by every profile: weather is about the house, not the person
  static const String locationKey = "device_weather_location";
  static const Duration _builtInRefreshInterval = Duration(minutes: 30);
  DateTime? _lastBuiltInFetch;
  bool _builtInError = false;
  StreamSubscription<dynamic>? _subscription;
  Timer? _refreshTimer;
  DateTime? _lastResumeCheck;
  String? _lastJson;

  WeatherData? _weatherData;
  bool _isBreezyInstalled = false;
  bool _initialized = false;

  WeatherService(this._channel, {required SharedPreferences sharedPreferences, OpenMeteoClient? openMeteo})
      : _sharedPreferences = sharedPreferences,
        _openMeteo = openMeteo ?? OpenMeteoClient() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  WeatherData? get weatherData => _weatherData;
  @visibleForTesting
  bool get isBreezyInstalled => _isBreezyInstalled;
  @visibleForTesting
  bool get initialized => _initialized;
  bool get hasWeather => _weatherData != null;

  /// Location for built-in weather (Open-Meteo); null means weather comes from Breezy Weather, if installed.
  WeatherPlace? get location {
    final raw = _sharedPreferences.getString(locationKey);
    if (raw == null) return null;
    try {
      return WeatherPlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool get builtInError => _builtInError;

  Future<List<WeatherPlace>> searchPlaces(String query) => _openMeteo.searchPlaces(query);

  Future<void> setLocation(WeatherPlace? place) async {
    if (place == null) {
      await _sharedPreferences.remove(locationKey);
      _weatherData = null;
      _lastJson = null;
    } else {
      await _sharedPreferences.setString(locationKey, jsonEncode(place.toJson()));
    }
    _lastBuiltInFetch = null;
    await _fetchLatest();
    notifyListeners();
  }

  Future<void> _init() async {
    try {
      await _fetchLatest();

      _subscription = _channel.addWeatherChangedListener((event) {
        // Built-in weather wins over Breezy broadcasts once a location is set
        if (event is String && event.isNotEmpty && location == null) {
          _processWeatherJson(event);
        }
      });
      _startPeriodicTimer();
    } catch (e, stack) {
      developer.log("Error initializing WeatherService", error: e, stackTrace: stack);
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  void _startPeriodicTimer() {
    _refreshTimer?.cancel();
    // 15-minute fallback timer in case a broadcast was missed while paused
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) => _fetchLatest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _checkWeatherOnResume();
      _startPeriodicTimer();
    }
  }

  Future<void> _checkWeatherOnResume() async {
    final now = DateTime.now();
    if (_lastResumeCheck != null && now.difference(_lastResumeCheck!).inSeconds < 60) {
      return;
    }
    _lastResumeCheck = now;
    await _fetchLatest();
  }

  Future<void> _fetchLatest() async {
    final WeatherPlace? place = location;
    if (place != null) {
      await _fetchBuiltIn(place);
      return;
    }
    try {
      _isBreezyInstalled = await _channel.isBreezyWeatherInstalled();
      final latestJson = await _channel.getLatestWeatherData();
      if (latestJson != null && latestJson.isNotEmpty) {
        _processWeatherJson(latestJson);
      }
    } catch (e, stack) {
      developer.log("Failed to fetch latest weather data", error: e, stackTrace: stack);
    }
  }

  Future<void> _fetchBuiltIn(WeatherPlace place) async {
    final now = DateTime.now();
    if (_lastBuiltInFetch != null && now.difference(_lastBuiltInFetch!) < _builtInRefreshInterval) return;
    try {
      _processWeatherJson(await _openMeteo.fetchWeatherJson(place));
      _lastBuiltInFetch = now;
      _builtInError = false;
    } catch (e, stack) {
      developer.log("Failed to fetch Open-Meteo weather", error: e, stackTrace: stack);
      _builtInError = true;
      notifyListeners();
    }
  }

  void _processWeatherJson(String jsonString) {
    if (jsonString == _lastJson && _weatherData != null) {
      return;
    }
    try {
      _weatherData = WeatherData.fromJsonString(jsonString);
      _lastJson = jsonString;
      notifyListeners();
    } catch (e, stack) {
      developer.log("Failed to parse weather JSON", error: e, stackTrace: stack);
    }
  }

  Future<bool> openBreezyWeather() => _channel.openBreezyWeather();

  @visibleForTesting
  Future<void> refresh() async {
    await _fetchLatest();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
