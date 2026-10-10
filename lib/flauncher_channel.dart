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

import 'package:flutter/services.dart';

class FLauncherChannel {
  static const _methodChannel = MethodChannel('me.efesser.flauncher/method');
  static const _appsEventChannel = EventChannel('me.efesser.flauncher/event_apps');
  static const _networkEventChannel = EventChannel('me.efesser.flauncher/event_network');
  static const _notificationsEventChannel = EventChannel('me.efesser.flauncher/event_notifications');
  static const _weatherEventChannel = EventChannel('me.efesser.flauncher/event_weather');
  static const _watchNextEventChannel = EventChannel('me.efesser.flauncher/event_watch_next');

  Future<List<Map<dynamic, dynamic>>> getApplications() async {
    try {
      List<Map<dynamic, dynamic>>? applications = await _methodChannel.invokeListMethod("getApplications");
      return applications ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List> getApplicationBanner(String packageName) async {
    try {
      final Uint8List? bytes = await _methodChannel.invokeMethod("getApplicationBanner", packageName);
      return bytes ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<Uint8List> getApplicationIcon(String packageName) async {
    try {
      final Uint8List? bytes = await _methodChannel.invokeMethod("getApplicationIcon", packageName);
      return bytes ?? Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<void> launchActivityFromAction(String action) async => await _methodChannel.invokeMethod('launchActivityFromAction', action);

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  Future<bool> openUrl(String url) async {
    try {
      final bool? success = await _methodChannel.invokeMethod("openUrl", url);
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSettings() async => await _methodChannel.invokeMethod('openSettings');

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<Map<String, dynamic>> getActiveNetworkInformation() async {
    Map<dynamic, dynamic> map = await _methodChannel.invokeMethod("getActiveNetworkInformation");
    return map.cast<String, dynamic>();
  }

  Future<int> getDailyDataUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getDailyDataUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getWeeklyDataUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getWeeklyDataUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getMonthlyDataUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getMonthlyDataUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<bool> checkUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("checkUsageStatsPermission");

  Future<void> requestUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("requestUsageStatsPermission");

  Future<void> openWifiSettings() async =>
      await _methodChannel.invokeMethod("openWifiSettings");

  Future<void> openVpnSettings() async {
    try {
      await _methodChannel.invokeMethod("openVpnSettings");
    } catch (_) {
      // Ignore error in non-Android or test environments
    }
  }

  Future<void> openDefaultLauncherSettings() async =>
      await _methodChannel.invokeMethod("openDefaultLauncherSettings");

  Future<void> openProfileChooser() async => await _methodChannel.invokeMethod("openProfileChooser");

  Future<String?> getActiveProfileName() async => await _methodChannel.invokeMethod<String>("getActiveProfileName");

  /// The active Google TV profile's lasting key ("user:11"), known before its name and unchanged by renames;
  /// per-profile things are saved under it. Null when Hearth can't tell.
  Future<String?> getActiveProfileKey() async => await _methodChannel.invokeMethod<String>("getActiveProfileKey");

  /// Hearth is the app's installer of record, so Android lets Hearth update it without asking.
  Future<bool> isInstalledByHearth(String packageName) async =>
      await _methodChannel.invokeMethod<bool>("isInstalledByHearth", packageName) ?? false;

  /// The app whose window is in front (as Hearth's accessibility service last saw it), or null.
  Future<String?> getForegroundPackage() async => await _methodChannel.invokeMethod<String>("getForegroundPackage");

  /// The companion update setting changed (HearthTube reads it from Hearth's provider).
  Future<void> companionSettingsChanged() async => await _methodChannel.invokeMethod("companionSettingsChanged");

  /// After a profile change: what only Hearth's native side knows is in (another profile's agent has reported its
  /// Continue Watching, or that profile can't have an agent).
  Future<bool> isProfileDataReady() async => await _methodChannel.invokeMethod<bool>("isProfileDataReady") ?? true;

  /// Hearth's home is complete for this profile (shared with HearthTube as profile_ready).
  Future<void> setProfileReady(String key) async => await _methodChannel.invokeMethod("setProfileReady", key);

  /// A Google TV profile's photo (PNG, cropped from its chooser) and when it last changed (0: no photo).
  Future<({Uint8List? png, int modified})> getProfileAvatar(String name) async {
    final map = await _methodChannel.invokeMapMethod<String, dynamic>("getProfileAvatar", name);
    return (png: map?["png"] as Uint8List?, modified: (map?["modified"] as int?) ?? 0);
  }

  Future<bool> isKidsProfile() async => await _methodChannel.invokeMethod<bool>("isKidsProfile") ?? false;

  /// Parent-initiated: add Hearth and HearthTube to the TV's other Google TV profiles. Supervised kids profiles are
  /// kept installed (protected from Google TV's profile-start uninstall); when [includeAdults] is true, the other
  /// adult profiles get a plain install too (the launcher leaves theirs alone). Returns a short log of what was done.
  /// The first time, the TV shows a one-time "Allow debugging?" prompt the parent approves; until then this throws a
  /// PlatformException (code "SELF_ADB"). Only ever touches Hearth's own two apps. Adding sends one Family Link
  /// "app added" notification per kid — the Settings confirmation copy should say so.
  Future<List<String>> addHearthToProfiles({required bool includeAdults}) async =>
      await _methodChannel.invokeListMethod<String>("addHearthToProfiles", includeAdults) ?? [];

  /// Parent-initiated: release any keep-installed flag and uninstall Hearth and HearthTube from every other profile
  /// (kids and adults) — the clean undo of [addHearthToProfiles], and what must run before Hearth itself is
  /// uninstalled.
  Future<List<String>> removeHearthFromProfiles() async =>
      await _methodChannel.invokeListMethod<String>("removeHearthFromProfiles") ?? [];

  /// Read-only: for each other profile, [{userId, packageName, installed, protected, supervised}] — so Settings can
  /// show exactly where Hearth's apps are and nothing is hidden.
  Future<List<Map<dynamic, dynamic>>> getHearthProfilesState() async =>
      await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>("getHearthProfilesState") ?? [];

  /// Opens Android's uninstall screen for Hearth itself. Call [removeHearthFromProfiles] first so the copies on the
  /// other profiles are cleaned up before Hearth goes (otherwise the kids' copies would be left behind).
  Future<void> uninstallHearth() async => await _methodChannel.invokeMethod("uninstallHearth");

  /// Hands control to Google TV's own home so the parent can use the native interface for a bit. Hearth stops
  /// bouncing back on its own until they press the Home button (or a short window passes). False if it couldn't open.
  Future<bool> openGoogleTvHome() async =>
      await _methodChannel.invokeMethod<bool>("openGoogleTvHome") ?? false;

  /// Profile Pairing's state: {enabled, voiceDefault}.
  Future<Map<dynamic, dynamic>> getProfilePairingStatus() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getProfilePairingStatus") ?? {};

  /// For each app, the Google TV profile that last had it in front on the TV.
  Future<Map<dynamic, dynamic>> getAppLastProfiles() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getAppLastProfiles") ?? {};

  /// Listens with the TV's speech recognizer; what was said, or null when cancelled or nothing was heard.
  Future<String?> voiceSearch() async => await _methodChannel.invokeMethod<String>("voiceSearch");

  /// A search the remote asked for before Flutter was listening: "voice", "text" or null.
  Future<String?> takePendingSearch() async => await _methodChannel.invokeMethod<String>("takePendingSearch");

  /// The app whose profile PINs Profile Pairing's "Change PIN" asked for before Flutter was listening, or null.
  Future<String?> takePendingProfilePins() async =>
      await _methodChannel.invokeMethod<String>("takePendingProfilePins");

  /// Calls [onOpen] with the app's package when Profile Pairing's "Change PIN" asks for its PINs in Settings.
  static void listenForProfilePins(void Function(String packageName) onOpen) {
    _onOpenProfilePins = onOpen;
    _listen();
  }

  static void Function(String packageName)? _onOpenProfilePins;

  /// Whether Hearth can type profile PINs in the app yet (it has a recipe for the app's PIN screen).
  Future<bool> profilePinEntrySupported(String packageName) async =>
      await _methodChannel.invokeMethod<bool>("profilePinEntrySupported", packageName) ?? false;

  /// A saved streaming-app profile PIN's state, never the PIN: {status ("none", "saved", "rejected"),
  /// length, savedAt, rejections, paused}.
  Future<Map<dynamic, dynamic>> getProfilePinStatus(String packageName, String appProfile) async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
          "getProfilePinStatus", {"packageName": packageName, "appProfile": appProfile}) ??
      {};

  /// Hands the PIN to the Android side, which encrypts it at once (Keystore); false when it couldn't be saved.
  Future<bool> saveProfilePin(String packageName, String appProfile, String pin) async =>
      await _methodChannel.invokeMethod<bool>(
          "saveProfilePin", {"packageName": packageName, "appProfile": appProfile, "pin": pin}) ??
      false;

  Future<void> removeProfilePin(String packageName, String appProfile) async =>
      await _methodChannel.invokeMethod("removeProfilePin", {"packageName": packageName, "appProfile": appProfile});

  /// Locks the current grown-up profile with Google TV's own profile lock (its PIN screen). False in a kids profile
  /// or when it couldn't be opened.
  Future<bool> lockProfile() async => await _methodChannel.invokeMethod<bool>("lockProfile") ?? false;

  /// "Lock when the TV sleeps": minutes the TV must sleep before it locks on waking (0 for any sleep), or -1 for off.
  Future<int> getLockOnSleepMinutes() async => await _methodChannel.invokeMethod<int>("getLockOnSleepMinutes") ?? -1;

  Future<void> setLockOnSleepMinutes(int minutes) async =>
      await _methodChannel.invokeMethod("setLockOnSleepMinutes", minutes);

  /// Every saved profile PIN (when the parent PIN that guards them is removed).
  Future<void> removeAllProfilePins() async => await _methodChannel.invokeMethod("removeAllProfilePins");

  /// Calls [onOpenSearch] ("voice" or "text") when the remote's mapped search button is pressed.
  static void listenForSearch(void Function(String mode) onOpenSearch) {
    _onOpenSearch = onOpenSearch;
    _listen();
  }

  /// Calls [onProfileChanged] when the accessibility service sees the active Google TV profile change.
  static void listenForProfileChanges(void Function() onProfileChanged) {
    _onProfileChanged = onProfileChanged;
    _listen();
  }

  static void Function(String mode)? _onOpenSearch;
  static void Function()? _onProfileChanged;
  static void Function(String name)? _onProfileSwitching;

  /// [onSwitching] hears of a switch to the named profile as soon as it's picked in Google TV's chooser, before
  /// it's confirmed.
  static void listenForProfileSwitching(void Function(String name) onSwitching, {void Function()? onCancelled}) {
    _onProfileSwitching = onSwitching;
    _onProfileSwitchCancelled = onCancelled;
    _listen();
  }

  static void Function()? _onProfileSwitchCancelled;

  static bool _listening = false;

  /// Installs the handler for the calls the Android side makes into Flutter (once; the listeners above share it).
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == "openSearch") _onOpenSearch?.call(call.arguments as String? ?? "text");
      if (call.method == "profileChanged") _onProfileChanged?.call();
      if (call.method == "profileSwitching") _onProfileSwitching?.call(call.arguments as String);
      if (call.method == "profileSwitchCancelled") _onProfileSwitchCancelled?.call();
      if (call.method == "openProfilePins") _onOpenProfilePins?.call(call.arguments as String);
      if (call.method == "resumeSetup") _onResumeSetup?.call(call.arguments as String? ?? "");
      return null;
    });
  }

  /// Opens a link in a specific app (a search result's title page). False when the app can't open it.
  Future<bool> openLinkInApp(String packageName, String link) async =>
      await _methodChannel.invokeMethod<bool>("openLinkInApp", {"packageName": packageName, "link": link}) ?? false;

  /// Opens an app's own search for the text. False when the app has no search to open.
  Future<bool> searchInApp(String packageName, String query) async =>
      await _methodChannel.invokeMethod<bool>("searchInApp", {"packageName": packageName, "query": query}) ?? false;

  /// Google TV's page for a title ([link]), or Google TV's search for [query].
  Future<bool> openGoogleTv({String? link, String? query}) async =>
      await _methodChannel.invokeMethod<bool>("openGoogleTv", {"link": link, "query": query}) ?? false;

  Future<void> setProfilePairingAppEnabled(String packageName, bool enabled) async =>
      await _methodChannel.invokeMethod("setProfilePairingAppEnabled", {"packageName": packageName, "enabled": enabled});

  /// The streaming apps Profile Pairing handles: [{packageName, label, installed, seenProfiles, enabled}].
  Future<List<Map<dynamic, dynamic>>> getProfilePairingApps() async =>
      await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>("getProfilePairingApps") ?? [];

  /// Each known Hearth profile's choice for one app: [{hearthProfile (its key), displayName, kids, mode, chosenProfile,
  /// autoMatch}], where mode is "auto", "profile" or "picker".
  Future<List<Map<dynamic, dynamic>>> getProfilePairingChoices(String packageName) async =>
      await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>("getProfilePairingChoices", packageName) ?? [];

  Future<void> setProfilePairingChoice(String packageName, String hearthProfile, String mode, String? appProfile) async =>
      await _methodChannel.invokeMethod("setProfilePairingChoice", {
        "packageName": packageName,
        "hearthProfile": hearthProfile,
        "mode": mode,
        "appProfile": appProfile,
      });

  /// The setup flow is about to send the owner to Android's screen for a switch ("home_button_fix",
  /// "profile_pairing" or "notification_access"): when that switch's service starts, Hearth comes back to the front
  /// by itself. Null: no longer waiting.
  Future<void> setSetupWaitingFor(String? what) async => await _methodChannel.invokeMethod("setSetupWaitingFor", what);

  /// Calls [onResume] when a switch the setup flow was waiting for came on and brought Hearth back.
  static void listenForSetupResume(void Function(String what) onResume) {
    _onResumeSetup = onResume;
    _listen();
  }

  static void Function(String what)? _onResumeSetup;

  /// Whether the TV's debugging switch (Developer options) is on: Hearth's own fixes ([runSetupFixes]) need it.
  Future<bool> isAdbEnabled() async => await _methodChannel.invokeMethod<bool>("isAdbEnabled") ?? false;

  /// The shell commands one of the setup flow's named fixes runs, to show the parent before it does: "restricted_settings",
  /// "home_button_fix", "profile_pairing", "watch_next" or "notification_access". Null for another name, or when the
  /// fix can't be run safely as things are.
  Future<List<String>?> getSetupFixCommands(String fix) async =>
      await _methodChannel.invokeListMethod<String>("getSetupFixCommands", fix);

  /// Parent-confirmed: runs the named fixes through Hearth's own loopback adb, and returns what the TV's shell said.
  /// The first time, the TV asks "Allow debugging?"; until the parent allows it this throws a PlatformException
  /// (code "SELF_ADB"). They only ever change Hearth's own permissions.
  Future<List<String>> runSetupFixes(List<String> fixes) async =>
      await _methodChannel.invokeListMethod<String>("runSetupFixes", fixes) ?? [];

  Future<bool> openTextToSpeechSettings() async =>
      await _methodChannel.invokeMethod<bool>("openTextToSpeechSettings") ?? false;

  /// Google TV's screensaver settings, or the nearest screen this TV has to them. False when none would open.
  Future<bool> openScreensaverSettings() async =>
      await _methodChannel.invokeMethod<bool>("openScreensaverSettings") ?? false;

  Future<int> getIdleStandbyMinutes() async => await _methodChannel.invokeMethod<int>("getIdleStandbyMinutes") ?? 0;

  Future<void> setIdleStandbyMinutes(int minutes) async =>
      await _methodChannel.invokeMethod("setIdleStandbyMinutes", minutes);

  Future<String> getButtonMappings() async => await _methodChannel.invokeMethod<String>("getButtonMappings") ?? "{}";

  Future<void> setButtonMappings(String json) async => await _methodChannel.invokeMethod("setButtonMappings", json);

  /// Resolves with the next remote button pressed ({keyCode, name, remappable}).
  Future<Map<dynamic, dynamic>?> captureButton() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("captureButton");

  Future<void> cancelButtonCapture() async => await _methodChannel.invokeMethod("cancelButtonCapture");

  Future<bool> getHaNotificationsEnabled() async =>
      await _methodChannel.invokeMethod<bool>("getHaNotificationsEnabled") ?? false;

  Future<void> setHaNotificationsEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod("setHaNotificationsEnabled", enabled);

  /// False when Home Button Fix (the accessibility service) isn't running.
  Future<bool> sendHaTestNotification() async =>
      await _methodChannel.invokeMethod<bool>("sendHaTestNotification") ?? false;

  /// {hasToken, dashboard}: the Home Assistant panel's sign-in and dashboard path (the token itself stays native).
  Future<Map<dynamic, dynamic>> getHaPanelConfig() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getHaPanelConfig") ?? {};

  /// Null leaves a value unchanged; an empty token removes it.
  Future<void> setHaPanelConfig({String? token, String? dashboard}) async =>
      await _methodChannel.invokeMethod("setHaPanelConfig", {"token": token, "dashboard": dashboard});

  Future<void> openHaPanel() async => await _methodChannel.invokeMethod("openHaPanel");

  /// JSON list of {entity_id, name, domain} a remote button can run; empty without a Home Assistant sign-in.
  Future<String> getHaEntities() async => await _methodChannel.invokeMethod<String>("getHaEntities") ?? "[]";

  /// Starts the phone setup page and returns its one-time link (for the QR code), or null without a network.
  Future<String?> startHaSetup() async => await _methodChannel.invokeMethod<String>("startHaSetup");

  Future<void> stopHaSetup() async => await _methodChannel.invokeMethod("stopHaSetup");

  /// True once a phone has sent the address and token through the setup page.
  Future<bool> getHaSetupReceived() async => await _methodChannel.invokeMethod<bool>("getHaSetupReceived") ?? false;

  Future<Map<dynamic, dynamic>> getHaStatusConfig() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getHaStatusConfig") ?? {};

  Future<void> setHaStatusConfig(String? url, String? webhookId) async =>
      await _methodChannel.invokeMethod("setHaStatusConfig", {"url": url, "webhookId": webhookId});

  Future<String?> getLocalIpAddress() async => await _methodChannel.invokeMethod<String>("getLocalIpAddress");

  /// Device ABIs in preference order (Build.SUPPORTED_ABIS).
  Future<List<String>> getSupportedAbis() async =>
      (await _methodChannel.invokeListMethod<String>("getSupportedAbis")) ?? const [];

  Future<void> playClickSound() async {
    try {
      await _methodChannel.invokeMethod("playClickSound");
    } catch (_) {
      // Ignore error in non-Android or test environments
    }
  }

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  StreamSubscription addAppsChangedListener(void Function(Map<String, dynamic>) listener) =>
      _appsEventChannel.receiveBroadcastStream().listen((event) {
        Map<dynamic, dynamic> eventMap = event;
        listener(eventMap.cast<String, dynamic>());
      });

  StreamSubscription addNetworkChangedListener(void Function(Map<String, dynamic>) listener) =>
      _networkEventChannel.receiveBroadcastStream().listen((event) {
        Map<dynamic, dynamic> eventMap = event;
        listener(eventMap.cast<String, dynamic>());
      });

  Future<List<Map<dynamic, dynamic>>> getTvInputs() async {
    try {
      final List<dynamic> inputs = await _methodChannel.invokeMethod("getTvInputs");
      return inputs.cast<Map<dynamic, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<bool> launchTvInput(String inputId) async {
    try {
      final bool success = await _methodChannel.invokeMethod("launchTvInput", inputId);
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkNotificationListenerPermission() async =>
      await _methodChannel.invokeMethod("checkNotificationListenerPermission");

  Future<bool> requestNotificationListenerPermission() async {
    final bool? success = await _methodChannel.invokeMethod<bool>("requestNotificationListenerPermission");
    return success ?? false;
  }

  Future<bool> openAppNotificationSettings() async {
    final bool? success = await _methodChannel.invokeMethod<bool>("openAppNotificationSettings");
    return success ?? false;
  }

  Future<bool> checkOverlayPermission() async =>
      await _methodChannel.invokeMethod("checkOverlayPermission");

  Future<bool> requestOverlayPermission() async {
    final bool? success = await _methodChannel.invokeMethod<bool>("requestOverlayPermission");
    return success ?? false;
  }

  /// {enabled, listedButStopped, seenBefore, restricted}: whether Home Button Fix is on, whether Android lists it as
  /// on while it isn't running, whether it has ever been on here, and whether Android blocks turning it on (its
  /// restricted-settings app-op is denied; where that can't be read, a guess from an install from an APK file).
  Future<Map<dynamic, dynamic>> getHomeButtonFixStatus() async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getHomeButtonFixStatus") ?? {};

  /// Stops the "Home Button Fix is off" reminder until the service is turned on again.
  Future<void> forgetHomeButtonFix() async => await _methodChannel.invokeMethod("forgetHomeButtonFix");

  Future<bool> requestAccessibilityPermission() async {
    final bool? success = await _methodChannel.invokeMethod<bool>("requestAccessibilityPermission");
    return success ?? false;
  }

  Future<List<Map<dynamic, dynamic>>> getActiveNotifications() async {
    try {
      final List<dynamic> list = await _methodChannel.invokeMethod("getActiveNotifications");
      return list.cast<Map<dynamic, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  StreamSubscription addNotificationsChangedListener(void Function(List<Map<dynamic, dynamic>>) listener) =>
      _notificationsEventChannel.receiveBroadcastStream().listen((event) {
        final List<dynamic> eventList = event;
        listener(eventList.cast<Map<dynamic, dynamic>>());
      });

  Future<bool> dismissNotification(String key) async {
    try {
      final bool success = await _methodChannel.invokeMethod("dismissNotification", {"key": key});
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> dismissAllNotifications() async {
    try {
      final bool success = await _methodChannel.invokeMethod("dismissAllNotifications");
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<dynamic, dynamic>>> getWatchNextPrograms() async {
    try {
      final List<dynamic>? list = await _methodChannel.invokeMethod("getWatchNextPrograms");
      return list?.cast<Map<dynamic, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> launchWatchNextProgram(String intentUri) async {
    try {
      final bool success = await _methodChannel.invokeMethod("launchWatchNextProgram", {"intentUri": intentUri});
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Poster art for a Watch Next entry, downscaled; null when it can't be loaded.
  Future<Uint8List?> getWatchNextPoster(String posterArtUri) async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>("getWatchNextPoster", {"posterArtUri": posterArtUri});
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteWatchNextProgram(int id) async {
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>("deleteWatchNextProgram", {"id": id});
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkWatchNextPermission() async {
    try {
      final bool? allowed = await _methodChannel.invokeMethod<bool>("checkWatchNextPermission");
      return allowed ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestWatchNextPermission() async {
    try {
      final bool? allowed = await _methodChannel.invokeMethod<bool>("requestWatchNextPermission");
      return allowed ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getLatestWeatherData() async {
    try {
      final String? json = await _methodChannel.invokeMethod("getLatestWeatherData");
      return json;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isBreezyWeatherInstalled() async {
    try {
      final bool? installed = await _methodChannel.invokeMethod<bool>("isBreezyWeatherInstalled");
      return installed ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openBreezyWeather() async {
    try {
      final bool? opened = await _methodChannel.invokeMethod<bool>("openBreezyWeather");
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  StreamSubscription<dynamic> addWeatherChangedListener(void Function(dynamic) onEvent) =>
      _weatherEventChannel.receiveBroadcastStream().listen(onEvent);

  StreamSubscription<dynamic> addWatchNextChangedListener(void Function(dynamic) onEvent) =>
      _watchNextEventChannel.receiveBroadcastStream().listen(onEvent);

  Future<bool> checkInstallPermission() async {
    try {
      final bool? allowed = await _methodChannel.invokeMethod<bool>("checkInstallPermission");
      return allowed ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestInstallPermission() async {
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>("requestInstallPermission");
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> installApk(String path) async {
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>("installApk", {"path": path});
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// {versionName, versionCode} of an installed app, or null when it isn't installed.
  Future<Map<dynamic, dynamic>?> getPackageVersion(String packageName) async =>
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>("getPackageVersion", packageName);

  /// The package an APK file installs, or null when it can't be read.
  Future<String?> getApkPackageName(String path) async =>
      await _methodChannel.invokeMethod<String>("getApkPackageName", path);

  /// Hands Hearth's current wallpaper (WallpaperService.providerState) to the provider HearthTube reads.
  Future<void> setWallpaperState(Map<String, Object?> state) async {
    try {
      await _methodChannel.invokeMethod("setWallpaperState", state);
    } catch (_) {
      // No Android side (tests): nobody to tell
    }
  }
}
