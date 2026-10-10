/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _appKeyClickEnabledKey = "app_key_click_enabled";
const _autoHideAppBarKey = "auto_hide_app_bar";
const _gradientUuidKey = "gradient_uuid";
const _backButtonActionKey = "back_button_action";
const _dateFormatKey = "date_format";
const _showCategoryTitlesKey = "show_category_titles";
const _showCategoryAppCountKey = "show_category_app_count";
const _showAppNamesBelowIconsKey = "show_app_names_below_icons";
const _themesKey = "app_banner_shape";
const _hideHighlightOutlineOnHomescreenKey = "hide_highlight_outline_on_homescreen";
const _appSelectorTransitionAnimationEnabledKey = "app_selector_transition_animation_enabled";
const _showDateInStatusBarKey = "show_date_in_status_bar";
const _showTimeInStatusBarKey = "show_time_in_status_bar";
const _timeFormatKey = "time_format";
const _dataUsagePeriodKey = "wifi_usage_period";
const _showDataWidgetInStatusBarKey = "show_wifi_widget_in_status_bar";
const String _showNetworkIndicatorInStatusBarKey = "show_network_indicator_in_status_bar";
const String _accentColorKey = "accent_color";
const String _timeBasedWallpaperEnabledKey = "time_based_wallpaper_enabled";
const String _bingWallpaperEnabledKey = "bing_wallpaper_enabled";
const String _pushToAdultProfilesKey = "push_to_adult_profiles";
const String _matchSelectedAppBackgroundKey = "match_selected_app_background";
const String _dockEnabledKey = "dock_enabled";
const String _dockBlurEnabledKey = "dock_blur_enabled";
const String _dockDarkBackgroundKey = "dock_dark_background";
const String _dockShadowEnabledKey = "dock_shadow_enabled";
const String _blurWallpaperBelowDockKey = "blur_wallpaper_below_dock";
const String _haPanelEnabledKey = "ha_panel_enabled";
const String _showInputsWidgetInStatusBarKey = "show_inputs_widget_in_status_bar";
const String _showContinueWatchingKey = "show_continue_watching";
const String _continueWatchingCardSizeKey = "continue_watching_card_size";
const String _continueWatchingMaxItemsKey = "continue_watching_max_items";
const String _continueWatchingShowProgressKey = "continue_watching_show_progress";
const String _continueWatchingShowPercentageKey = "continue_watching_show_percentage";
const String _continueWatchingShowDescriptionKey = "continue_watching_show_description";
const String _continueWatchingOrderKey = "continue_watching_order";
const String _hiddenWatchNextProgramIdsKey = "hidden_watch_next_program_ids";
const String _hiddenWatchNextPackagesKey = "hidden_watch_next_packages";
const String _startOnBootKey = "start_on_boot";
// device_ prefix: shared by all profiles, never part of a per-profile layout
const String _parentPinHashKey = "device_parent_pin_hash";
const String _updatesIncludePrereleasesKey = "device_updates_include_prereleases";
// A TMDB key users could once type in; search now uses the one built into the release only
const String _retiredTmdbApiKeyKey = "tmdb_api_key";
const String _oldDateTimeDefaultsClearedKey = "device_old_date_time_defaults_cleared";
const String _showNotificationsWidgetInStatusBarKey = "show_notifications_widget_in_status_bar";
const String _autoHideNotificationsWidgetKey = "auto_hide_notifications_widget";
const String _appLanguageKey = "app_language";
const String _showWeatherInStatusBarKey = "show_weather_in_status_bar";
const String _showWeatherWarningsKey = "show_weather_warnings";
// One unit for the whole TV (it's in one place), and a new key: the old "temperature_unit" was saved into layouts and
// backups as the old default (Celsius) even when nobody chose it, and mustn't override the region's unit.
const String _temperatureUnitKey = "device_temperature_unit";

// What Back does on the home screen
const String backButtonActionNothing = "";
const String backButtonActionClock = "CLOCK";
const String backButtonActionScreensaver = "SCREENSAVER";

const String temperatureUnitCelsius = "celsius";
const String temperatureUnitFahrenheit = "fahrenheit";

/// The regions that use Fahrenheit (as Android's own temperature preference has it): the US and its territories,
/// the Bahamas, Belize, the Cayman Islands, Liberia, Palau and the Marshall Islands and Micronesia.
const Set<String> _fahrenheitRegions = {"US", "AS", "GU", "MP", "PR", "UM", "VI", "BS", "BZ", "KY", "LR", "PW", "MH", "FM"};

/// The temperature unit a TV in [locale]'s region uses.
String defaultTemperatureUnit(Locale locale) =>
    _fahrenheitRegions.contains(locale.countryCode?.toUpperCase()) ? temperatureUnitFahrenheit : temperatureUnitCelsius;

// WiFi usage period options
const String dataUsageDaily = "daily";
const String dataUsageWeekly = "weekly";
const String dataUsageMonthly = "monthly";

// Accent color presets (hex values)
const String accentColorPurple = "7C4DFF";
const String accentColorTeal = "00BFA5";
const String accentColorBlue = "2979FF";
const String accentColorOrange = "FF6D00";
const String accentColorPink = "F50057";
const String accentColorGreen = "00C853";
const String accentColorWhite = "FFFFFF";
const String accentColorYellow = "FFD600";
const String accentColorRed = "D50000";
const String accentColorCyan = "00E5FF";
const String accentColorIndigo = "536DFE";
const String accentColorLime = "AEEA00";
const String accentColorAmber = "FFAB00";
const String accentColorRose = "FF4081";
const String accentColorIceBlue = "80D8FF";

/// An "RRGGBB" accent hex as an opaque color; one that doesn't parse is purple.
Color accentColorFromHex(String hex) => Color(int.tryParse("0xFF$hex") ?? 0xFF7C4DFF);

class SettingsService extends ChangeNotifier {
  static final defaultDateFormat = "EEE, MMM d";
  static final defaultTimeFormat = "h:mm a";

  /// The defaults before 2026-10, which older backups and profile layouts saved as if they'd been chosen.
  static const _oldDefaultDateFormat = "EEEE d";
  static const _oldDefaultTimeFormat = "H:mm";

  static const _defaultContinueWatchingCardHeight = 135;

  /// Card sizes were saved by name before a height could be picked; these are the heights they drew.
  static const _legacyContinueWatchingCardHeights = {"compact": 112, "normal": 135, "large": 157};

  /// Every setting this service stores. A backup or profile layout without one of them had it at its default.
  static const Set<String> _settingKeys = {
    _appHighlightAnimationEnabledKey,
    _appKeyClickEnabledKey,
    _autoHideAppBarKey,
    _gradientUuidKey,
    _backButtonActionKey,
    _dateFormatKey,
    _showCategoryTitlesKey,
    _showCategoryAppCountKey,
    _showAppNamesBelowIconsKey,
    _themesKey,
    _hideHighlightOutlineOnHomescreenKey,
    _appSelectorTransitionAnimationEnabledKey,
    _showDateInStatusBarKey,
    _showTimeInStatusBarKey,
    _timeFormatKey,
    _dataUsagePeriodKey,
    _showDataWidgetInStatusBarKey,
    _showNetworkIndicatorInStatusBarKey,
    _accentColorKey,
    _timeBasedWallpaperEnabledKey,
    _bingWallpaperEnabledKey,
    _pushToAdultProfilesKey,
    _matchSelectedAppBackgroundKey,
    _dockEnabledKey,
    _dockBlurEnabledKey,
    _dockDarkBackgroundKey,
    _dockShadowEnabledKey,
    _blurWallpaperBelowDockKey,
    _haPanelEnabledKey,
    _showInputsWidgetInStatusBarKey,
    _showContinueWatchingKey,
    _continueWatchingCardSizeKey,
    _continueWatchingMaxItemsKey,
    _continueWatchingShowProgressKey,
    _continueWatchingShowPercentageKey,
    _continueWatchingShowDescriptionKey,
    _continueWatchingOrderKey,
    _hiddenWatchNextProgramIdsKey,
    _hiddenWatchNextPackagesKey,
    _startOnBootKey,
    _showNotificationsWidgetInStatusBarKey,
    _autoHideNotificationsWidgetKey,
    _appLanguageKey,
    _showWeatherInStatusBarKey,
    _showWeatherWarningsKey,
    _temperatureUnitKey,
  };

  final SharedPreferences _sharedPreferences;

  /// The TV's language and region, for defaults that depend on where it is (the temperature unit); the platform's
  /// unless a test gives one.
  final Locale Function() _region;

  SettingsService(this._sharedPreferences, {Locale Function()? region})
      : _region = region ?? (() => ui.PlatformDispatcher.instance.locale) {
    if (_sharedPreferences.containsKey(_retiredTmdbApiKeyKey)) {
      unawaited(_sharedPreferences.remove(_retiredTmdbApiKeyKey));
    }
    _clearOldDateTimeDefaults();
  }

  /// Once per TV: the old default date and time, restored from a layout or backup that saved them as if chosen,
  /// count as never chosen. After that, choosing that pair sticks.
  void _clearOldDateTimeDefaults() {
    if (_sharedPreferences.getBool(_oldDateTimeDefaultsClearedKey) == true) return;
    if (_sharedPreferences.getString(_dateFormatKey) == _oldDefaultDateFormat &&
        _sharedPreferences.getString(_timeFormatKey) == _oldDefaultTimeFormat) {
      unawaited(_sharedPreferences.remove(_dateFormatKey));
      unawaited(_sharedPreferences.remove(_timeFormatKey));
    }
    unawaited(_sharedPreferences.setBool(_oldDateTimeDefaultsClearedKey, true));
  }

  /// In settings saved before backups held only chosen settings, the old default date and time weren't a choice.
  static void forgetOldDefaults(Map<String, dynamic> settings) {
    if (settings[_dateFormatKey] == _oldDefaultDateFormat && settings[_timeFormatKey] == _oldDefaultTimeFormat) {
      settings.remove(_dateFormatKey);
      settings.remove(_timeFormatKey);
    }
  }

  /// The keys of the settings this service stores, whether set or not.
  Set<String> get settingKeys => _settingKeys;

  /// Tells listeners the stored settings changed underneath (after a restore).
  void reload() => notifyListeners();

  /// SharedPreferences key: the profile (its key, "user:11") whose layout and settings are the ones stored now.
  /// ProfileService keeps it; HearthWallpaper.java reads it too.
  static const String layoutOwnerKey = "device_layout_owner";

  /// The profile whose settings these are (null before Hearth has seen one).
  String? get layoutOwner => _sharedPreferences.getString(layoutOwnerKey);

  bool _bool(String key, bool fallback) => _sharedPreferences.getBool(key) ?? fallback;
  int _int(String key, int fallback) => _sharedPreferences.getInt(key) ?? fallback;
  String _string(String key, String fallback) => _sharedPreferences.getString(key) ?? fallback;
  List<String> _list(String key) => List.unmodifiable(_sharedPreferences.getStringList(key) ?? const <String>[]);

  Future<void> _setBool(String key, bool value) async {
    await _sharedPreferences.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setInt(String key, int value) async {
    await _sharedPreferences.setInt(key, value);
    notifyListeners();
  }

  Future<void> _setString(String key, String value) async {
    await _sharedPreferences.setString(key, value);
    notifyListeners();
  }

  /// An empty list is stored as no list: the default.
  Future<void> _saveList(String key, List<String> list) async {
    if (list.isEmpty) {
      await _sharedPreferences.remove(key);
    } else {
      await _sharedPreferences.setStringList(key, list);
    }
    notifyListeners();
  }

  bool get appHighlightAnimationEnabled => _bool(_appHighlightAnimationEnabledKey, true);

  bool get appKeyClickEnabled => _bool(_appKeyClickEnabledKey, true);

  bool get autoHideAppBarEnabled => _bool(_autoHideAppBarKey, false);

  bool get showCategoryTitles => _bool(_showCategoryTitlesKey, true);

  bool get showCategoryAppCount => _bool(_showCategoryAppCountKey, false);

  bool get showAppNamesBelowIcons => _bool(_showAppNamesBelowIconsKey, false);

  String get themes => _string(_themesKey, "modern");

  bool get hideHighlightOutlineOnHomescreen => _bool(_hideHighlightOutlineOnHomescreenKey, false);

  bool get appSelectorTransitionAnimationEnabled => _bool(_appSelectorTransitionAnimationEnabledKey, true);

  bool get showDateInStatusBar => _bool(_showDateInStatusBarKey, true);

  bool get showTimeInStatusBar => _bool(_showTimeInStatusBarKey, true);

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  String get backButtonAction => _string(_backButtonActionKey, backButtonActionNothing);

  String get dateFormat => _string(_dateFormatKey, defaultDateFormat);

  String get timeFormat => _string(_timeFormatKey, defaultTimeFormat);

  String get dataUsagePeriod => _string(_dataUsagePeriodKey, dataUsageDaily);

  bool get showDataWidgetInStatusBar => _bool(_showDataWidgetInStatusBarKey, false);

  bool get showNetworkIndicatorInStatusBar => _bool(_showNetworkIndicatorInStatusBarKey, true);

  bool get showInputsWidgetInStatusBar => _bool(_showInputsWidgetInStatusBarKey, true);

  bool get showContinueWatching => _bool(_showContinueWatchingKey, false);

  /// The Continue Watching cards' height, in dp.
  int get continueWatchingCardHeight {
    final String size = _string(_continueWatchingCardSizeKey, "normal");
    return int.tryParse(size) ?? _legacyContinueWatchingCardHeights[size] ?? _defaultContinueWatchingCardHeight;
  }

  int get continueWatchingMaxItems => _int(_continueWatchingMaxItemsKey, 15);

  bool get continueWatchingShowProgress => _bool(_continueWatchingShowProgressKey, true);

  bool get continueWatchingShowPercentage => _bool(_continueWatchingShowPercentageKey, false);

  bool get continueWatchingShowDescription => _bool(_continueWatchingShowDescriptionKey, true);

  int get continueWatchingOrder => _int(_continueWatchingOrderKey, 0);

  List<String> get hiddenWatchNextProgramIds => _list(_hiddenWatchNextProgramIdsKey);

  List<String> get hiddenWatchNextPackages => _list(_hiddenWatchNextPackagesKey);

  /// On unless turned off: on Google TV, Hearth then comes up after a restart instead of Google TV's home.
  bool get startOnBoot => _bool(_startOnBootKey, true);

  /// When on (the default), setting up Hearth on the kids' profiles also installs it on the TV's other adult
  /// profiles, so another adult doesn't have to sideload it themselves. Adult profiles need no keep-installed flag.
  bool get pushToAdultProfiles => _bool(_pushToAdultProfilesKey, true);

  Future<void> setPushToAdultProfiles(bool value) => _setBool(_pushToAdultProfilesKey, value);

  /// Whether Hearth's updater offers pre-releases too. On by default while Hearth is in early development: every
  /// Hearth release is a pre-release for now, so with this off nobody would get updates. For the whole TV.
  bool get updatesIncludePrereleases => _bool(_updatesIncludePrereleasesKey, true);

  Future<void> setUpdatesIncludePrereleases(bool value) => _setBool(_updatesIncludePrereleasesKey, value);

  bool get hasParentPin => _sharedPreferences.getString(_parentPinHashKey) != null;

  bool verifyParentPin(String pin) => _sharedPreferences.getString(_parentPinHashKey) == _hashPin(pin);

  Future<void> setParentPin(String? pin) async {
    if (pin == null) {
      await _sharedPreferences.remove(_parentPinHashKey);
    } else {
      await _sharedPreferences.setString(_parentPinHashKey, _hashPin(pin));
    }
    notifyListeners();
  }

  static String _hashPin(String pin) => sha256.convert(utf8.encode("ltv-parent-pin:$pin")).toString();

  bool get showNotificationsWidgetInStatusBar => _bool(_showNotificationsWidgetInStatusBarKey, true);

  bool get autoHideNotificationsWidget => _bool(_autoHideNotificationsWidgetKey, false);

  bool get showWeatherInStatusBar => _bool(_showWeatherInStatusBarKey, true);

  bool get showWeatherWarnings => _bool(_showWeatherWarningsKey, true);

  /// Celsius or Fahrenheit: until someone picks one, whichever the TV's region uses ([defaultTemperatureUnit]).
  String get temperatureUnit =>
      _string(_temperatureUnitKey, defaultTemperatureUnit(_region()));

  bool get useFahrenheit => temperatureUnit == temperatureUnitFahrenheit;

  String get appLanguage => _string(_appLanguageKey, "");

  Locale? get appLocale => appLanguage.isEmpty ? null : Locale(appLanguage);

  String get accentColorHex => _string(_accentColorKey, accentColorPurple);

  Color get accentColor => accentColorFromHex(accentColorHex);

  Future<void> importSettingsMap(Map<String, dynamic> settingsMap) async {
    for (final entry in settingsMap.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == _retiredTmdbApiKeyKey) continue; // old backups and layouts may still carry it
      if (value is bool) {
        await _sharedPreferences.setBool(key, value);
      } else if (value is int) {
        await _sharedPreferences.setInt(key, value);
      } else if (value is double) {
        await _sharedPreferences.setDouble(key, value);
      } else if (value is String) {
        await _sharedPreferences.setString(key, value);
      } else if (value is List) {
        await _sharedPreferences.setStringList(key, value.map((e) => e.toString()).toList());
      }
    }
    reload();
  }

  Future<void> setAppLanguage(String value) => _setString(_appLanguageKey, value);

  Future<void> setAppHighlightAnimationEnabled(bool value) => _setBool(_appHighlightAnimationEnabledKey, value);

  Future<void> setAppKeyClickEnabled(bool value) => _setBool(_appKeyClickEnabledKey, value);

  Future<void> setAutoHideAppBarEnabled(bool value) => _setBool(_autoHideAppBarKey, value);

  Future<void> setGradientUuid(String value) => _setString(_gradientUuidKey, value);

  Future<void> setBackButtonAction(String value) => _setString(_backButtonActionKey, value);

  Future<void> setDateTimeFormat(String dateFormatString, String timeFormatString) async {
    await Future.wait([
      _sharedPreferences.setString(_dateFormatKey, dateFormatString),
      _sharedPreferences.setString(_timeFormatKey, timeFormatString)
    ]);
    notifyListeners();
  }

  Future<void> setShowCategoryTitles(bool show) => _setBool(_showCategoryTitlesKey, show);

  Future<void> setShowCategoryAppCount(bool show) => _setBool(_showCategoryAppCountKey, show);

  Future<void> setShowAppNamesBelowIcons(bool show) => _setBool(_showAppNamesBelowIconsKey, show);

  Future<void> setThemes(String shape) => _setString(_themesKey, shape);

  Future<void> setHideHighlightOutlineOnHomescreen(bool enabled) =>
      _setBool(_hideHighlightOutlineOnHomescreenKey, enabled);

  Future<void> setAppSelectorTransitionAnimationEnabled(bool enabled) =>
      _setBool(_appSelectorTransitionAnimationEnabledKey, enabled);

  Future<void> setShowDateInStatusBar(bool show) => _setBool(_showDateInStatusBarKey, show);

  Future<void> setShowTimeInStatusBar(bool show) => _setBool(_showTimeInStatusBarKey, show);

  Future<void> setDataUsagePeriod(String period) => _setString(_dataUsagePeriodKey, period);

  Future<void> setShowDataWidgetInStatusBar(bool show) => _setBool(_showDataWidgetInStatusBarKey, show);

  Future<void> setShowNetworkIndicatorInStatusBar(bool show) => _setBool(_showNetworkIndicatorInStatusBarKey, show);

  Future<void> setAccentColor(String colorHex) => _setString(_accentColorKey, colorHex);

  bool get timeBasedWallpaperEnabled => _bool(_timeBasedWallpaperEnabledKey, false);

  Future<void> setTimeBasedWallpaperEnabled(bool enabled) => _setBool(_timeBasedWallpaperEnabledKey, enabled);

  bool get bingWallpaperEnabled => _bool(_bingWallpaperEnabledKey, false);

  Future<void> setBingWallpaperEnabled(bool enabled) => _setBool(_bingWallpaperEnabledKey, enabled);

  bool get matchSelectedAppBackground => _bool(_matchSelectedAppBackgroundKey, false);

  Future<void> setMatchSelectedAppBackground(bool enabled) => _setBool(_matchSelectedAppBackgroundKey, enabled);

  /// Favorites shown as a frosted dock at the bottom of the first screen, with
  /// Continue Watching above it and the other sections below.
  bool get dockEnabled => _bool(_dockEnabledKey, true);

  Future<void> setDockEnabled(bool enabled) => _setBool(_dockEnabledKey, enabled);

  bool get dockBlurEnabled => _bool(_dockBlurEnabledKey, true);

  Future<void> setDockBlurEnabled(bool enabled) => _setBool(_dockBlurEnabledKey, enabled);

  bool get dockDarkBackground => _bool(_dockDarkBackgroundKey, false);

  Future<void> setDockDarkBackground(bool enabled) => _setBool(_dockDarkBackgroundKey, enabled);

  bool get dockShadowEnabled => _bool(_dockShadowEnabledKey, true);

  Future<void> setDockShadowEnabled(bool enabled) => _setBool(_dockShadowEnabledKey, enabled);

  /// Blur the wallpaper while browsing the sections below the dock.
  bool get blurWallpaperBelowDock => _bool(_blurWallpaperBelowDockKey, true);

  Future<void> setBlurWallpaperBelowDock(bool enabled) => _setBool(_blurWallpaperBelowDockKey, enabled);

  /// Right at the right edge of the home screen opens the Home Assistant panel. Per profile, off by default.
  bool get haPanelEnabled => _bool(_haPanelEnabledKey, false);

  Future<void> setHaPanelEnabled(bool enabled) => _setBool(_haPanelEnabledKey, enabled);

  Future<void> setShowInputsWidgetInStatusBar(bool show) => _setBool(_showInputsWidgetInStatusBarKey, show);

  Future<void> setShowContinueWatching(bool show) => _setBool(_showContinueWatchingKey, show);

  Future<void> setContinueWatchingCardHeight(int height) =>
      _setString(_continueWatchingCardSizeKey, height.toString());

  Future<void> setContinueWatchingMaxItems(int count) => _setInt(_continueWatchingMaxItemsKey, count);

  Future<void> setContinueWatchingShowProgress(bool show) => _setBool(_continueWatchingShowProgressKey, show);

  Future<void> setContinueWatchingShowPercentage(bool show) => _setBool(_continueWatchingShowPercentageKey, show);

  Future<void> setContinueWatchingShowDescription(bool show) => _setBool(_continueWatchingShowDescriptionKey, show);

  Future<void> setContinueWatchingOrder(int order) => _setInt(_continueWatchingOrderKey, order);

  Future<void> hideWatchNextProgram(int id) async {
    final ids = hiddenWatchNextProgramIds;
    if (!ids.contains(id.toString())) await _saveList(_hiddenWatchNextProgramIdsKey, [...ids, id.toString()]);
  }

  Future<void> hideWatchNextPackage(String packageName) async {
    final packages = hiddenWatchNextPackages;
    if (!packages.contains(packageName)) await _saveList(_hiddenWatchNextPackagesKey, [...packages, packageName]);
  }

  Future<void> unhideWatchNextPackage(String packageName) async {
    final packages = hiddenWatchNextPackages;
    if (packages.contains(packageName)) {
      await _saveList(_hiddenWatchNextPackagesKey, [...packages]..remove(packageName));
    }
  }

  Future<void> unhideAllWatchNextPackages() => _saveList(_hiddenWatchNextPackagesKey, const []);

  Future<void> clearHiddenWatchNextPrograms() => _saveList(_hiddenWatchNextProgramIdsKey, const []);

  Future<void> setStartOnBoot(bool enabled) => _setBool(_startOnBootKey, enabled);

  Future<void> setShowNotificationsWidgetInStatusBar(bool show) =>
      _setBool(_showNotificationsWidgetInStatusBarKey, show);

  Future<void> setAutoHideNotificationsWidget(bool value) => _setBool(_autoHideNotificationsWidgetKey, value);

  Future<void> setShowWeatherInStatusBar(bool show) => _setBool(_showWeatherInStatusBarKey, show);

  Future<void> setShowWeatherWarnings(bool show) => _setBool(_showWeatherWarningsKey, show);

  Future<void> setTemperatureUnit(String unit) => _setString(_temperatureUnitKey, unit);
}
