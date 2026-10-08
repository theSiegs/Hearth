/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
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

package com.leanbitlab.ltvL;

import android.app.NotificationManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.*;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.net.ConnectivityManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;
import android.media.tv.TvInputManager;
import android.media.tv.TvInputInfo;
import android.media.tv.TvContract;
import android.database.ContentObserver;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.io.ByteArrayOutputStream;
import android.app.usage.NetworkStats;
import android.app.usage.NetworkStatsManager;
import android.app.AppOpsManager;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

import java.io.Serializable;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import android.service.notification.StatusBarNotification;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "HearthMain";
    // Drawn app images are capped at this many pixels a side.
    private static final int MAX_ICON_PX = 512;
    private static final int[] DATA_USAGE_NETWORKS = {
            ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE, ConnectivityManager.TYPE_ETHERNET};
    private final String METHOD_CHANNEL = "me.efesser.flauncher/method";
    private final String APPS_EVENT_CHANNEL = "me.efesser.flauncher/event_apps";
    private final String NETWORK_EVENT_CHANNEL = "me.efesser.flauncher/event_network";
    private final String NOTIFICATIONS_EVENT_CHANNEL = "me.efesser.flauncher/event_notifications";
    private final String WEATHER_EVENT_CHANNEL = "me.efesser.flauncher/event_weather";
    private final String WATCH_NEXT_EVENT_CHANNEL = "me.efesser.flauncher/event_watch_next";
    private MethodChannel.Result pendingPermissionResult;
    private MethodChannel mMethodChannel;
    private MethodChannel.Result mPendingVoiceResult;
    private static final int VOICE_REQUEST = 4242;
    /** Intent extra asking Hearth to open its search: "voice" to start listening right away. */
    static final String EXTRA_OPEN_SEARCH = "hearth_open_search";
    private static final ExecutorService sIoExecutor = Executors.newFixedThreadPool(4);
    // Builds one app list at a time, so overlapping requests are answered in the order they came.
    private static final ExecutorService sAppsLoader = Executors.newSingleThreadExecutor();
    // The app list's PackageManager lookups, in parallel. Separate from sAppsLoader, which waits on them.
    private static final ExecutorService sAppsExecutor = Executors.newFixedThreadPool(4);

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        sIoExecutor.execute(() -> WatchNextPosters.pruneCache(getApplicationContext()));

        BinaryMessenger messenger = flutterEngine.getDartExecutor().getBinaryMessenger();

        // Opened by the remote's search button. Handled before the channel exists: Flutter isn't running yet, so it
        // picks the search up with takePendingSearch rather than hearing openSearch.
        handleSearchIntent(getIntent());
        mMethodChannel = new MethodChannel(messenger, METHOD_CHANNEL);
        sMethodChannel = new java.lang.ref.WeakReference<>(mMethodChannel);
        mMethodChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getApplications" -> sAppsLoader.execute(() -> {
                    List<Map<String, Serializable>> applications = getApplications();
                    runOnUiThread(() -> result.success(applications));
                });
                case "getApplicationBanner" -> result.success(appImage(call.arguments(), true));
                case "getApplicationIcon" -> result.success(appImage(call.arguments(), false));
                case "launchActivityFromAction" -> result.success(launchActivityFromAction(call.arguments()));
                case "launchApp" -> result.success(launchApp(call.arguments()));
                case "openUrl" -> result.success(openUrl(call.arguments()));
                case "openSettings" -> result.success(openSettings());
                case "openScreensaverSettings" -> result.success(openScreensaverSettings());
                case "openAppInfo" -> result.success(openAppInfo(call.arguments()));
                case "uninstallApp" -> result.success(uninstallApp(call.arguments()));
                case "isDefaultLauncher" -> result.success(isDefaultLauncher());
                case "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability());
                case "startAmbientMode" -> result.success(startAmbientMode());
                case "getActiveNetworkInformation" -> result.success(getActiveNetworkInformation());
                case "getDailyDataUsage", "getWeeklyDataUsage", "getMonthlyDataUsage" -> {
                    long usage = dataUsageSince(periodStart(call.method));
                    if (usage == -1) {
                        result.error("PERMISSION_DENIED", "Usage stats permission not granted", null);
                    } else {
                        result.success(usage);
                    }
                }
                case "checkUsageStatsPermission" -> result.success(checkUsageStatsPermission());
                case "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission();
                    result.success(null);
                }
                case "checkWriteSettingsPermission" -> result.success(checkWriteSettingsPermission());
                case "requestWriteSettingsPermission" -> result.success(requestWriteSettingsPermission());
                case "setSystemBrightness" -> {
                    Integer brightness = call.argument("brightness");
                    if (brightness != null) {
                        result.success(setSystemBrightness(brightness));
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing brightness", null);
                    }
                }
                case "openDefaultLauncherSettings" -> result.success(openDefaultLauncherSettings());
                case "openProfileChooser" -> result.success(openProfileChooser());
                case "getSupportedAbis" -> result.success(java.util.Arrays.asList(Build.SUPPORTED_ABIS));
                case "isKidsProfile" -> {
                    boolean kids = ProfileUsers.isKids(this);
                    ProfilePairing.rememberHearthProfile(
                            this, LauncherAccessibilityService.getActiveProfileKey(this), kids);
                    result.success(kids);
                }
                // Parent-controlled "Add / Remove Hearth from other profiles" (a Settings action) and a read-only
                // state view. The work, and the one-time "Allow debugging?" consent, live in ProfileAppAccess /
                // SelfAdb. Off the main thread (adb I/O); parent-confirmed because these fire only from the Settings
                // row. addHearthToProfiles' argument is whether to include the other adult profiles too.
                case "addHearthToProfiles" -> {
                    boolean includeAdults = Boolean.TRUE.equals(call.arguments());
                    sIoExecutor.execute(() -> runAddToProfiles(includeAdults, result));
                }
                case "removeHearthFromProfiles" -> sIoExecutor.execute(() -> runRemoveFromProfiles(result));
                case "getHearthProfilesState" -> sIoExecutor.execute(() -> runProfilesState(result));
                case "uninstallHearth" -> result.success(uninstallSelf());
                case "openGoogleTvHome" -> result.success(openGoogleTvHome());
                case "voiceSearch" -> startVoiceSearch(result);
                case "getAppLastProfiles" -> {
                    Map<String, Object> users = new HashMap<>(getSharedPreferences("ltv_app_last_profile", MODE_PRIVATE).getAll());
                    result.success(users);
                }
                case "takePendingSearch" -> {
                    String pending = mPendingSearch;
                    mPendingSearch = null;
                    result.success(pending);
                }
                case "openLinkInApp" -> {
                    // A search result: the app's own link for the title, opened in that app (Profile Pairing first).
                    String pkg = call.argument("packageName");
                    String link = call.argument("link");
                    result.success(openInApp(new Intent(Intent.ACTION_VIEW, Uri.parse(link)).setPackage(pkg)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), pkg));
                }
                case "searchInApp" -> {
                    String pkg = call.argument("packageName");
                    Intent intent = new Intent(Intent.ACTION_SEARCH).setPackage(pkg)
                            .putExtra(android.app.SearchManager.QUERY, (String) call.argument("query"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    Boolean inProfile = ProfileApps.open(this, intent);
                    if (inProfile != null) {
                        result.success(inProfile);
                        return;
                    }
                    boolean ok = intent.resolveActivity(getPackageManager()) != null;
                    if (ok) {
                        ProfilePairingService.onAppLaunching(this, pkg);
                        ok = tryStartActivity(intent);
                    }
                    result.success(ok);
                }
                case "openGoogleTv" -> {
                    // Google TV's page for a title (by Knowledge Graph link), or its search for the text.
                    String link = call.argument("link");
                    Intent intent = link != null
                            ? new Intent(Intent.ACTION_VIEW, Uri.parse(link))
                                    .setPackage(LauncherAccessibilityService.GOOGLE_TV_PACKAGE)
                            : new Intent("android.search.action.GLOBAL_SEARCH")
                                    .putExtra(android.app.SearchManager.QUERY, (String) call.argument("query"));
                    result.success(tryStartActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
                }
                case "getProfilePairingApps" -> {
                    List<Map<String, Object>> apps = new ArrayList<>();
                    for (String pkg : ProfilePairing.APPS) {
                        Map<String, Object> app = new HashMap<>();
                        app.put("packageName", pkg);
                        try {
                            ApplicationInfo info = getPackageManager().getApplicationInfo(pkg, 0);
                            app.put("label", getPackageManager().getApplicationLabel(info).toString());
                            app.put("installed", true);
                        } catch (PackageManager.NameNotFoundException e) {
                            app.put("label", ProfilePairing.displayName(pkg));
                            app.put("installed", false);
                        }
                        app.put("seenProfiles", ProfilePairing.getSeenNames(this, pkg));
                        app.put("enabled", ProfilePairing.isAppEnabled(this, pkg));
                        apps.add(app);
                    }
                    result.success(apps);
                }
                case "getProfilePairingChoices" -> {
                    String pkg = call.arguments();
                    List<String> seen = ProfilePairing.getSeenNames(this, pkg);
                    List<String> hearthProfiles = ProfilePairing.getHearthProfiles(this);
                    String active = LauncherAccessibilityService.getActiveProfileKey(this);
                    if (active != null && !hearthProfiles.contains(active)) hearthProfiles.add(active);
                    List<Map<String, Object>> choices = new ArrayList<>();
                    // hearthProfile is the key choices are saved under; displayName is what to show
                    for (String hearth : hearthProfiles) {
                        String name = ProfileUsers.displayName(this, hearth);
                        Map<String, Object> choice = new HashMap<>();
                        choice.put("hearthProfile", hearth);
                        choice.put("displayName", name);
                        choice.put("kids", ProfilePairing.isKids(this, hearth));
                        choice.put("mode", ProfilePairing.getMode(this, pkg, hearth));
                        choice.put("chosenProfile", ProfilePairing.getChosenProfile(this, pkg, hearth));
                        choice.put("autoMatch", ProfilePairing.bestMatch(name, seen));
                        choices.add(choice);
                    }
                    result.success(choices);
                }
                case "setProfilePairingAppEnabled" -> {
                    Boolean enabled = call.argument("enabled");
                    ProfilePairing.setAppEnabled(this, call.argument("packageName"), enabled == null || enabled);
                    result.success(null);
                }
                case "setProfilePairingChoice" -> {
                    ProfilePairing.setChoice(this, call.argument("packageName"), call.argument("hearthProfile"),
                            call.argument("mode"), call.argument("appProfile"));
                    result.success(null);
                }
                case "getHaNotificationsEnabled" -> result.success(LauncherAccessibilityService.isHaNotificationsEnabled(this));
                case "setHaNotificationsEnabled" -> {
                    Boolean enabled = call.arguments();
                    LauncherAccessibilityService.setHaNotificationsEnabled(this, enabled != null && enabled);
                    result.success(null);
                }
                case "sendHaTestNotification" -> {
                    HaNotificationServer.Notification test = new HaNotificationServer.Notification();
                    test.title = "Home Assistant";
                    test.message = "Test notification from Hearth";
                    result.success(LauncherAccessibilityService.showHaNotification(test));
                }
                case "getLocalIpAddress" -> result.success(getLocalIpAddress());
                case "getHaPanelConfig" -> {
                    Map<String, Object> config = new HashMap<>();
                    config.put("hasToken", HaPanelActivity.hasToken(this));
                    config.put("dashboard", HaPanelActivity.getDashboard(this));
                    result.success(config);
                }
                case "setHaPanelConfig" -> {
                    HaPanelActivity.setConfig(this, call.argument("token"), call.argument("dashboard"));
                    result.success(null);
                }
                case "getHaEntities" -> HaApi.EXECUTOR.execute(() -> {
                    String entities = HaApi.actionableEntities(this).toString();
                    runOnUiThread(() -> result.success(entities));
                });
                case "startHaSetup" -> result.success(HaSetupServer.start(this));
                case "stopHaSetup" -> {
                    HaSetupServer.stop();
                    result.success(null);
                }
                case "getHaSetupReceived" -> result.success(HaSetupServer.received());
                case "openHaPanel" -> {
                    startActivity(new Intent(this, HaPanelActivity.class));
                    result.success(null);
                }
                case "getHaStatusConfig" -> {
                    android.content.SharedPreferences prefs =
                            getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, MODE_PRIVATE);
                    Map<String, Object> config = new HashMap<>();
                    config.put("url", prefs.getString(HaStatusReporter.URL_KEY, null));
                    config.put("webhookId", prefs.getString(HaStatusReporter.WEBHOOK_KEY, null));
                    result.success(config);
                }
                case "setHaStatusConfig" -> {
                    LauncherAccessibilityService.setHaStatusConfig(this, call.argument("url"), call.argument("webhookId"));
                    result.success(null);
                }
                case "getButtonMappings" -> result.success(ButtonMapper.getJson(this));
                case "setButtonMappings" -> {
                    try {
                        ButtonMapper.setJson(this, call.arguments());
                        result.success(null);
                    } catch (Exception e) {
                        result.error("INVALID_ARGUMENT", e.getMessage(), null);
                    }
                }
                case "captureButton" -> {
                    boolean started = LauncherAccessibilityService.captureNextKey(keyCode -> {
                        Map<String, Object> captured = new HashMap<>();
                        captured.put("keyCode", keyCode);
                        captured.put("name", ButtonMapper.keyName(keyCode));
                        captured.put("remappable", ButtonMapper.isRemappable(keyCode));
                        result.success(captured);
                    });
                    if (!started) {
                        result.error("SERVICE_OFF", "Home Button Fix (accessibility service) is not running", null);
                    }
                }
                case "cancelButtonCapture" -> {
                    LauncherAccessibilityService.cancelCapture();
                    result.success(null);
                }
                case "getIdleStandbyMinutes" -> result.success(LauncherAccessibilityService.getIdleStandbyMinutes(this));
                case "setIdleStandbyMinutes" -> {
                    Integer minutes = call.arguments();
                    LauncherAccessibilityService.setIdleStandbyMinutes(this, minutes != null ? minutes : 0);
                    result.success(null);
                }
                case "getActiveProfileName" -> result.success(LauncherAccessibilityService.getActiveProfileName(this));
                case "getActiveProfileKey" -> result.success(LauncherAccessibilityService.getActiveProfileKey(this));
                case "isProfileDataReady" -> {
                    // What only Java knows for a profile change: another profile's agent has reported (or it
                    // can't have one)
                    android.os.UserHandle profileUser = ProfileApps.activeProfileUser(this);
                    long serial = ProfileUsers.settledSerial(this);
                    result.success(profileUser == null || AgentHub.hasReported(serial)
                            || !AgentHub.canHaveAgent(this, profileUser));
                }
                case "setProfileReady" -> {
                    LauncherAccessibilityService.setProfileReady(this, call.arguments());
                    result.success(null);
                }
                case "getProfileAvatar" -> {
                    String name = call.arguments();
                    Map<String, Object> avatar = new HashMap<>();
                    avatar.put("modified", ProfileAvatars.modified(this, name));
                    avatar.put("png", ProfileAvatars.read(this, name));
                    result.success(avatar);
                }
                case "openWifiSettings" -> result.success(openWifiSettings());
                case "openVpnSettings" -> result.success(openVpnSettings());
                case "getTvInputs" -> result.success(getTvInputs());
                case "launchTvInput" -> result.success(launchTvInput(call.arguments()));
                case "checkNotificationListenerPermission" -> result.success(checkNotificationListenerPermission());
                case "requestNotificationListenerPermission" -> result.success(requestNotificationListenerPermission());
                case "openAppNotificationSettings" -> result.success(openAppNotificationSettings());
                case "getActiveNotifications" -> result.success(getActiveNotifications());
                case "dismissNotification" -> {
                    String key = call.argument("key");
                    result.success(dismissNotification(key));
                }
                case "dismissAllNotifications" -> result.success(dismissAllNotifications());
                case "checkOverlayPermission" -> result.success(checkOverlayPermission());
                case "requestOverlayPermission" -> result.success(requestOverlayPermission());
                case "requestAccessibilityPermission" -> result.success(openAccessibilitySettings());
                case "getHomeButtonFixStatus" -> {
                    Map<String, Object> status = new HashMap<>();
                    boolean listed = isAccessibilityServiceEnabled();
                    status.put("enabled", listed && LauncherAccessibilityService.isRunning());
                    status.put("listedButStopped", listed && !LauncherAccessibilityService.isRunning());
                    status.put("seenBefore", LauncherAccessibilityService.wasHomeButtonFixSeen(this));
                    status.put("restricted", mayHaveRestrictedSettings());
                    result.success(status);
                }
                case "forgetHomeButtonFix" -> {
                    LauncherAccessibilityService.forgetHomeButtonFix(this);
                    result.success(null);
                }
                case "getProfilePairingStatus" -> {
                    Map<String, Object> status = new HashMap<>();
                    status.put("enabled", ProfilePairingService.isRunning());
                    status.put("voiceDefault", ProfilePairingService.isVoiceDefault(this));
                    result.success(status);
                }
                case "openTextToSpeechSettings" -> result.success(
                        tryStartActivity(new Intent("android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                || openAccessibilitySettings());
                case "checkWatchNextPermission" -> result.success(checkWatchNextPermission());
                case "requestWatchNextPermission" -> {
                    if (checkWatchNextPermission()) {
                        result.success(true);
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (pendingPermissionResult != null) {
                            result.error("ALREADY_REQUESTING", "A permission request is already in progress", null);
                        } else {
                            pendingPermissionResult = result;
                            requestPermissions(new String[]{"android.permission.READ_TV_LISTINGS"}, 1002);
                        }
                    } else {
                        result.success(true);
                    }
                }
                case "getWatchNextPrograms" -> result.success(getWatchNextPrograms());
                case "getWatchNextPoster" -> {
                    String posterArtUri = call.argument("posterArtUri");
                    sIoExecutor.execute(() -> {
                        byte[] posterBytes = WatchNextPosters.load(getApplicationContext(), posterArtUri);
                        runOnUiThread(() -> result.success(posterBytes));
                    });
                }
                case "deleteWatchNextProgram" -> {
                    Number id = call.argument("id");
                    if (id != null) {
                        result.success(deleteWatchNextProgram(id.longValue()));
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing id", null);
                    }
                }
                case "launchWatchNextProgram" -> {
                    String intentUri = call.argument("intentUri");
                    result.success(launchWatchNextProgram(intentUri));
                }
                case "getLatestWeatherData" -> result.success(getLatestWeatherData());
                case "isBreezyWeatherInstalled" -> result.success(isBreezyWeatherInstalled());
                case "openBreezyWeather" -> result.success(openBreezyWeather());
                case "checkInstallPermission" -> result.success(checkInstallPermission());
                case "requestInstallPermission" -> result.success(requestInstallPermission());
                case "installApk" -> result.success(installApk(call.argument("path")));
                case "isInstalledByHearth" -> result.success(CompanionApps.installedByHearth(this, call.arguments()));
                case "getForegroundPackage" -> result.success(LauncherAccessibilityService.foregroundPackage());
                case "companionSettingsChanged" -> {
                    ProfileProvider.notifyChanged(this);  // updates_hearthtube
                    result.success(null);
                }
                case "getPackageVersion" -> result.success(getPackageVersion(call.arguments()));
                case "playClickSound" -> {
                    getWindow().getDecorView().playSoundEffect(android.view.SoundEffectConstants.CLICK);
                    result.success(null);
                }
                default -> result.notImplemented();
            }
        });

        new EventChannel(messenger, APPS_EVENT_CHANNEL).setStreamHandler(
                new LauncherAppsEventStreamHandler(this));

        new EventChannel(messenger, NETWORK_EVENT_CHANNEL).setStreamHandler(
                new NetworkEventStreamHandler(this));

        new EventChannel(messenger, NOTIFICATIONS_EVENT_CHANNEL).setStreamHandler(
                new EventChannel.StreamHandler() {
                    private LauncherNotificationListenerService.NotificationListener listener;

                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        listener = () -> {
                            runOnUiThread(() -> {
                                try {
                                    events.success(getActiveNotifications());
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                            });
                        };
                        LauncherNotificationListenerService.registerListener(listener);
                        // Send current state immediately
                        listener.onNotificationChanged();
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        if (listener != null) {
                            LauncherNotificationListenerService.unregisterListener(listener);
                            listener = null;
                        }
                    }
                }
        );

        new EventChannel(messenger, WEATHER_EVENT_CHANNEL).setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        WeatherReceiver.setListener(weatherJson -> {
                            runOnUiThread(() -> {
                                try {
                                    events.success(weatherJson);
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                            });
                        });
                        String latest = getLatestWeatherData();
                        if (latest != null) {
                            events.success(latest);
                        }
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        WeatherReceiver.setListener(null);
                    }
                }
        );

        new EventChannel(messenger, WATCH_NEXT_EVENT_CHANNEL).setStreamHandler(
                new EventChannel.StreamHandler() {
                    private ContentObserver watchNextObserver;
                    private boolean isObserverRegistered = false;
                    private Runnable debounceRunnable;
                    private final Handler mainHandler = new Handler(Looper.getMainLooper());

                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            return; // Watch Next is unsupported on Android < 8.0 (API < 26)
                        }

                        watchNextObserver = new ContentObserver(mainHandler) {
                            @Override
                            public void onChange(boolean selfChange, Uri uri) {
                                super.onChange(selfChange, uri);
                                if (debounceRunnable != null) {
                                    mainHandler.removeCallbacks(debounceRunnable);
                                }
                                debounceRunnable = () -> {
                                    try {
                                        events.success(true);
                                    } catch (Exception e) {
                                        e.printStackTrace();
                                    }
                                };
                                mainHandler.postDelayed(debounceRunnable, 500);
                            }
                        };

                        registerWatchNextObserverApi26();
                    }

                    @RequiresApi(Build.VERSION_CODES.O)
                    private void registerWatchNextObserverApi26() {
                        try {
                            getContentResolver().registerContentObserver(
                                    TvContract.WatchNextPrograms.CONTENT_URI,
                                    true,
                                    watchNextObserver
                            );
                            // Another profile's Continue Watching, as its agent reports it
                            getContentResolver().registerContentObserver(
                                    AgentHub.watchNextUri(MainActivity.this), false, watchNextObserver);
                            isObserverRegistered = true;
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        if (debounceRunnable != null) {
                            mainHandler.removeCallbacks(debounceRunnable);
                            debounceRunnable = null;
                        }
                        if (isObserverRegistered && watchNextObserver != null) {
                            try {
                                getContentResolver().unregisterContentObserver(watchNextObserver);
                            } catch (Exception e) {
                                e.printStackTrace();
                            }
                            isObserverRegistered = false;
                        }
                        watchNextObserver = null;
                    }
                }
        );
    }

    /**
     * Every launchable app: the TV (leanback) ones, then the others not already listed, plus Settings when neither
     * list has it. The PackageManager lookups run in parallel on sAppsExecutor.
     */
    private List<Map<String, Serializable>> getApplications() {
        List<Map<String, Serializable>> applications = new ArrayList<>();
        try {
            List<Callable<List<ResolveInfo>>> queries = Arrays.asList(
                    () -> queryIntentActivities(false), () -> queryIntentActivities(true));
            List<Future<List<ResolveInfo>>> lists = sAppsExecutor.invokeAll(queries);
            List<ResolveInfo> tvActivitiesInfo = resultOr(lists.get(0), Collections.emptyList());
            List<ResolveInfo> nonTvActivitiesInfo = resultOr(lists.get(1), Collections.emptyList());

            boolean settingsPresent = false;
            Set<String> tvPackages = new HashSet<>();
            List<Callable<Map<String, Serializable>>> builds = new ArrayList<>();
            for (ResolveInfo tvActivityInfo : tvActivitiesInfo) {
                String packageName = tvActivityInfo.activityInfo.packageName;
                settingsPresent |= packageName.equals("com.android.tv.settings");
                tvPackages.add(packageName);
                builds.add(() -> buildAppMap(tvActivityInfo.activityInfo, false, null));
            }
            for (ResolveInfo nonTvActivityInfo : nonTvActivitiesInfo) {
                String packageName = nonTvActivityInfo.activityInfo.packageName;
                settingsPresent |= packageName.equals("com.android.settings");
                if (!tvPackages.contains(packageName)) {
                    builds.add(() -> buildAppMap(nonTvActivityInfo.activityInfo, true, null));
                }
            }
            for (Future<Map<String, Serializable>> app : sAppsExecutor.invokeAll(builds)) {
                Map<String, Serializable> appMap = resultOr(app, null);
                if (appMap != null) applications.add(appMap);
            }

            if (!settingsPresent) {
                ActivityInfo activityInfo = new Intent(Settings.ACTION_SETTINGS)
                        .resolveActivityInfo(getPackageManager(), 0);
                if (activityInfo != null) {
                    applications.add(buildAppMap(activityInfo, false, Settings.ACTION_SETTINGS));
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return applications;
    }

    /** The finished task's result, or fallback when it threw. */
    private static <T> T resultOr(Future<T> future, T fallback) throws InterruptedException {
        try {
            return future.get();
        } catch (ExecutionException e) {
            Log.w(TAG, "App list lookup failed", e.getCause());
            return fallback;
        }
    }

    public Map<String, Serializable> getApplication(String packageName) {
        Map<String, Serializable> map = new java.util.HashMap<>();
        if (packageName.equals(getPackageName())) {
            return map;
        }
        PackageManager packageManager = getPackageManager();
        Intent intent = packageManager.getLeanbackLaunchIntentForPackage(packageName);

        if (intent == null) {
            intent = packageManager.getLaunchIntentForPackage(packageName);
        }

        if (intent != null) {
            ActivityInfo activityInfo = intent.resolveActivityInfo(getPackageManager(), 0);

            if (activityInfo != null) {
                map = buildAppMap(activityInfo, false, null);
            }
        }

        return map;
    }

    /** The app's banner or icon as PNG bytes; empty when it has none or isn't installed. */
    private byte[] appImage(String packageName, boolean banner) {
        PackageManager packageManager = getPackageManager();
        try {
            ApplicationInfo info = packageManager.getApplicationInfo(packageName, 0);
            Drawable drawable = banner ? info.loadBanner(packageManager) : info.loadIcon(packageManager);
            if (drawable != null) {
                return drawableToByteArray(drawable);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
            // Uninstalled since it was listed: no image.
        }
        return new byte[0];
    }

    private List<ResolveInfo> queryIntentActivities(boolean sideloaded) {
        String category;
        if (sideloaded) {
            category = Intent.CATEGORY_LAUNCHER;
        } else {
            category = Intent.CATEGORY_LEANBACK_LAUNCHER;
        }

        // NOTE: Would be nice to query the applications that match *either* of the
        // above categories
        // but from the addCategory function documentation, it says that it will "use
        // activities
        // that provide *all* the requested categories"
        Intent intent = new Intent(Intent.ACTION_MAIN)
                .addCategory(category);

        // Exclude ourselves: launching the launcher from its own grid is a no-op.
        String ownPackage = getPackageName();
        List<ResolveInfo> activities = new ArrayList<>(getPackageManager().queryIntentActivities(intent, 0));
        activities.removeIf(info -> info.activityInfo.packageName.equals(ownPackage));
        return activities;
    }

    private Map<String, Serializable> buildAppMap(ActivityInfo activityInfo, boolean sideloaded, String action) {
        PackageManager packageManager = getPackageManager();

        String applicationName = activityInfo.loadLabel(packageManager).toString(),
                applicationVersionName = "";
        boolean suspended = false;
        try {
            PackageInfo packageInfo = packageManager.getPackageInfo(activityInfo.packageName, 0);
            applicationVersionName = packageInfo.versionName;
            // Google TV suspends apps a kids profile hasn't approved
            suspended = packageInfo.applicationInfo != null
                    && (packageInfo.applicationInfo.flags & ApplicationInfo.FLAG_SUSPENDED) != 0;
        } catch (PackageManager.NameNotFoundException ignored) {
        }

        Map<String, Serializable> appMap = new HashMap<>();
        appMap.put("name", applicationName);
        appMap.put("packageName", activityInfo.packageName);
        appMap.put("version", applicationVersionName);
        appMap.put("sideloaded", sideloaded);
        // Another profile on: its own user's copies count (Google TV blocks the owner's while it's on). Approved =
        // that profile has the app (a kid's parent approved it); suspended = blocked there (screen time) or absent.
        int profileState = ProfileApps.state(this, activityInfo.packageName);
        if (profileState != ProfileApps.OWNER) suspended = profileState != ProfileApps.AVAILABLE;
        appMap.put("suspended", suspended);
        appMap.put("approved", profileState != ProfileApps.ABSENT);

        if (action != null) {
            appMap.put("action", action);
        }
        return appMap;
    }

    private boolean launchActivityFromAction(String action) {
        // Prevent Intent Action Injection by only allowing known actions
        if (Settings.ACTION_SETTINGS.equals(action)) {
            return tryStartActivity(new Intent(action));
        }
        return false;
    }

    private boolean launchApp(String packageName) {
        // Another profile on: its own copy, in its user
        Boolean inProfile = ProfileApps.launch(this, packageName);
        if (inProfile != null) return inProfile;
        PackageManager packageManager = getPackageManager();
        Intent intent = packageManager.getLeanbackLaunchIntentForPackage(packageName);

        if (intent == null) {
            intent = packageManager.getLaunchIntentForPackage(packageName);
        }

        if (intent != null) ProfilePairingService.onAppLaunching(this, packageName);
        return tryStartActivity(intent);
    }

    private boolean openUrl(String url) {
        try {
            Uri uri = Uri.parse(url);
            String scheme = uri.getScheme();
            if (scheme != null && (scheme.equalsIgnoreCase("http") || scheme.equalsIgnoreCase("https"))) {
                Intent intent = new Intent(Intent.ACTION_VIEW, uri);
                return tryStartActivity(intent);
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean openSettings() {
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean openAppInfo(String packageName) {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null));

        return tryStartActivity(intent);
    }

    private boolean uninstallApp(String packageName) {
        Intent intent = new Intent(Intent.ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null));

        return tryStartActivity(intent);
    }

    private boolean checkForGetContentAvailability() {
        List<ResolveInfo> intentActivities = getPackageManager().queryIntentActivities(
                new Intent(Intent.ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"),
                0);

        return !intentActivities.isEmpty();
    }

    private boolean isDefaultLauncher() {
        // On Google TV the Home intent always resolves to Google TV's own home (higher priority), so check the
        // role the user picked instead: holding it also keeps kids profiles from suspending the launcher.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            android.app.role.RoleManager roleManager = getSystemService(android.app.role.RoleManager.class);
            if (roleManager != null && roleManager.isRoleAvailable(android.app.role.RoleManager.ROLE_HOME)) {
                return roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_HOME);
            }
        }
        Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
        ResolveInfo defaultLauncher = getPackageManager().resolveActivity(intent, 0);

        if (defaultLauncher != null && defaultLauncher.activityInfo != null) {
            return defaultLauncher.activityInfo.packageName.equals(getPackageName());
        }

        return false;
    }

    private boolean startAmbientMode() {
        Intent intent = new Intent(Intent.ACTION_MAIN)
                .setClassName("com.android.systemui", "com.android.systemui.Somnambulator");

        return tryStartActivity(intent);
    }

    private Map<String, Object> getActiveNetworkInformation() {
        try {
            ConnectivityManager connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                return NetworkUtils.getNetworkInformation(this, connectivityManager.getActiveNetwork());
            } else {
                // noinspection deprecation
                return NetworkUtils.getNetworkInformation(this, connectivityManager.getActiveNetworkInfo());
            }
        } catch (Exception e) {
            e.printStackTrace();
            Map<String, Object> map = new java.util.HashMap<>();
            map.put(NetworkUtils.KEY_NETWORK_TYPE, NetworkUtils.NETWORK_TYPE_UNKNOWN);
            map.put(NetworkUtils.KEY_NETWORK_ACCESS, false);
            map.put(NetworkUtils.KEY_INTERNET_ACCESS, false);
            map.put(NetworkUtils.KEY_WIRELESS_SIGNAL_LEVEL, 0);
            return map;
        }
    }

    private boolean tryStartActivity(Intent intent) {
        boolean success = true;

        try {
            startActivity(intent);
        } catch (Exception ignored) {
            success = false;
        }

        return success;
    }

    /** Starts the first of the intents that opens, skipping nulls; false when none does. */
    private boolean startFirst(Intent... intents) {
        for (Intent intent : intents) {
            if (intent != null && tryStartActivity(intent)) return true;
        }
        return false;
    }

    /** The intent, or null (skipped by startFirst) when no activity Hearth can see handles it. */
    private Intent ifResolves(Intent intent) {
        return intent.resolveActivity(getPackageManager()) != null ? intent : null;
    }

    private byte[] drawableToByteArray(Drawable drawable) {
        if (drawable.getIntrinsicWidth() <= 0 || drawable.getIntrinsicHeight() <= 0) {
            return new byte[0];
        }
        try {
            Bitmap bitmap;
            if (drawable instanceof BitmapDrawable bitmapDrawable && bitmapDrawable.getBitmap() != null) {
                bitmap = bitmapDrawable.getBitmap();
            } else {
                bitmap = drawableToBitmap(drawable);
            }
            ByteArrayOutputStream stream = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
            return stream.toByteArray();
        } catch (Exception e) {
            Log.w(TAG, "Couldn't encode an app image", e);
            return new byte[0];
        }
    }

    /** Draws a drawable with a positive intrinsic size at that size, capped at MAX_ICON_PX a side. */
    private static Bitmap drawableToBitmap(Drawable drawable) {
        int width = Math.min(drawable.getIntrinsicWidth(), MAX_ICON_PX);
        int height = Math.min(drawable.getIntrinsicHeight(), MAX_ICON_PX);
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, width, height);
        drawable.draw(canvas);
        return bitmap;
    }

    /** Midnight at the start of today, of this week (the locale's first day) or of this month. */
    private static long periodStart(String method) {
        Calendar calendar = Calendar.getInstance();
        switch (method) {
            case "getWeeklyDataUsage" -> calendar.set(Calendar.DAY_OF_WEEK, calendar.getFirstDayOfWeek());
            case "getMonthlyDataUsage" -> calendar.set(Calendar.DAY_OF_MONTH, 1);
            default -> {
            }
        }
        calendar.set(Calendar.HOUR_OF_DAY, 0);
        calendar.set(Calendar.MINUTE, 0);
        calendar.set(Calendar.SECOND, 0);
        calendar.set(Calendar.MILLISECOND, 0);
        return calendar.getTimeInMillis();
    }

    /** Bytes sent and received over Wi-Fi, mobile and Ethernet since startTime; -1 without usage access. */
    private long dataUsageSince(long startTime) {
        if (!checkUsageStatsPermission()) {
            return -1;
        }
        NetworkStatsManager networkStatsManager = (NetworkStatsManager) getSystemService(Context.NETWORK_STATS_SERVICE);
        if (networkStatsManager == null) {
            return 0;
        }
        long endTime = System.currentTimeMillis();
        long totalBytes = 0;
        for (int type : DATA_USAGE_NETWORKS) {
            try {
                NetworkStats.Bucket bucket = networkStatsManager.querySummaryForDevice(type, null, startTime, endTime);
                if (bucket != null) {
                    totalBytes += bucket.getRxBytes() + bucket.getTxBytes();
                }
            } catch (Exception e) {
                Log.w(TAG, "No data usage for network type " + type, e);
            }
        }
        return totalBytes;
    }

    private boolean checkUsageStatsPermission() {
        AppOpsManager appOps = (AppOpsManager) getSystemService(Context.APP_OPS_SERVICE);
        int mode;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mode = appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), getPackageName());
        } else {
            mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), getPackageName());
        }

        if (mode == AppOpsManager.MODE_ALLOWED) {
            return true;
        }

        if (mode == AppOpsManager.MODE_DEFAULT) {
            try {
                NetworkStatsManager networkStatsManager = (NetworkStatsManager) getSystemService(Context.NETWORK_STATS_SERVICE);
                if (networkStatsManager != null) {
                    long now = System.currentTimeMillis();
                    networkStatsManager.querySummaryForDevice(ConnectivityManager.TYPE_WIFI, null, now - 1, now);
                    return true;
                }
            } catch (SecurityException e) {
                return false;
            } catch (Exception e) {
                return true;
            }
        }

        return false;
    }

    private void requestUsageStatsPermission() {
        Intent intent = new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS);
        tryStartActivity(intent);
    }

    private boolean checkWriteSettingsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.System.canWrite(this);
        }
        return true;
    }

    private boolean requestWriteSettingsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS,
                        Uri.parse("package:" + getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                if (tryStartActivity(intent)) {
                    return true;
                }
            } catch (Exception ignored) {}
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                if (tryStartActivity(intent)) {
                    return true;
                }
            } catch (Exception ignored) {}
            try {
                Intent intent = new Intent(Settings.ACTION_SETTINGS);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                return tryStartActivity(intent);
            } catch (Exception ignored) {}
            return false;
        }
        return true;
    }

    private boolean setSystemBrightness(int brightness) {
        if (checkWriteSettingsPermission()) {
            try {
                android.content.ContentResolver resolver = getContentResolver();
                // 1. Standard Android brightness
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
                Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, brightness);
                
                // 2. Try common TV "Backlight" keys (Vendor specific)
                Settings.System.putInt(resolver, "backlight", brightness);
                Settings.System.putInt(resolver, "backlight_level", brightness);
                
                return true;
            } catch (Exception e) {
                // Ignore errors on specific keys as they may not exist
                return true; 
            }
        }
        return false;
    }

    private boolean openDefaultLauncherSettings() {
        return startFirst(new Intent(Settings.ACTION_HOME_SETTINGS),
                new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
                new Intent(Settings.ACTION_SETTINGS));
    }

    // Google TV's own profile switcher: switching here is what applies kids profile restrictions system-wide.
    // Not a public API, so fall back to the accounts settings page if Google TV changes it.
    private boolean openProfileChooser() {
        Intent chooser = new Intent("com.google.android.gms.account.ProfilePickerDelegation")
                .setClassName(LauncherAccessibilityService.GOOGLE_TV_PACKAGE,
                        LauncherAccessibilityService.GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooserActivity");
        return startFirst(chooser, new Intent(Settings.ACTION_SYNC_SETTINGS));
    }

    /**
     * Parent-initiated add/remove of Hearth's own apps in the kids profiles, over Hearth's loopback adb
     * ({@link SelfAdb}). Reached only from the Settings rows, so {@code confirmedByParent} is true. Returns the log
     * of what was done; a first-run "Allow debugging?" that hasn't been approved surfaces as an error the UI explains.
     */
    /**
     * Parent-initiated add of Hearth's apps to the other profiles, over Hearth's loopback adb ({@link SelfAdb}):
     * always the supervised kids (kept installed so the launcher can't strip them), and — when {@code includeAdults}
     * — the other adult profiles too (plain install). Reached only from the Settings action, so parent-confirmed.
     */
    private void runAddToProfiles(boolean includeAdults, io.flutter.plugin.common.MethodChannel.Result result) {
        try (SelfAdb shell = SelfAdb.open(this)) {
            java.util.List<String> log = new java.util.ArrayList<>(
                    ProfileAppAccess.addToProfiles(this, shell, supervisedKidUserIds(), true, true));
            if (includeAdults) {
                log.addAll(ProfileAppAccess.addToProfiles(this, shell, adultProfileUserIds(), false, true));
            }
            runOnUiThread(() -> result.success(log));
        } catch (Exception e) {
            runOnUiThread(() -> result.error("SELF_ADB", e.getMessage(), null));
        }
    }

    /** Parent-initiated removal from every other profile (kids and adults): the clean undo of add. */
    private void runRemoveFromProfiles(io.flutter.plugin.common.MethodChannel.Result result) {
        try (SelfAdb shell = SelfAdb.open(this)) {
            java.util.List<Integer> all = new java.util.ArrayList<>(supervisedKidUserIds());
            all.addAll(adultProfileUserIds());
            java.util.List<String> log = ProfileAppAccess.removeFromProfiles(this, shell, all, true);
            runOnUiThread(() -> result.success(log));
        } catch (Exception e) {
            runOnUiThread(() -> result.error("SELF_ADB", e.getMessage(), null));
        }
    }

    /** Read-only: Hearth/HearthTube state across the other profiles, each row tagged supervised (kid) or not. */
    private void runProfilesState(io.flutter.plugin.common.MethodChannel.Result result) {
        try (SelfAdb shell = SelfAdb.open(this)) {
            java.util.List<Integer> kids = supervisedKidUserIds();
            java.util.List<Integer> all = new java.util.ArrayList<>(kids);
            all.addAll(adultProfileUserIds());
            java.util.Map<Integer, String> names = profileDisplayNames();
            java.util.List<java.util.Map<String, Object>> rows = new java.util.ArrayList<>();
            for (ProfileAppAccess.AppStatus s : ProfileAppAccess.state(this, shell, all)) {
                java.util.Map<String, Object> row = new java.util.HashMap<>();
                row.put("userId", s.userId);
                row.put("packageName", s.packageName);
                row.put("installed", s.installed);
                row.put("protected", s.protectedFromRemoval);
                row.put("supervised", kids.contains(s.userId));
                row.put("name", names.get(s.userId));
                rows.add(row);
            }
            runOnUiThread(() -> result.success(rows));
        } catch (Exception e) {
            runOnUiThread(() -> result.error("SELF_ADB", e.getMessage(), null));
        }
    }

    /**
     * Hands control to Google TV's own home for a while so the parent can use the native interface. Hearth's
     * accessibility service stops bouncing back automatically until the Home button is pressed (or a short window
     * passes); see {@link LauncherAccessibilityService#allowGoogleTvTemporarily()}.
     */
    private boolean openGoogleTvHome() {
        final String googleTv = "com.google.android.apps.tv.launcherx";
        LauncherAccessibilityService.allowGoogleTvTemporarily();
        android.content.Intent intent = new android.content.Intent(android.content.Intent.ACTION_MAIN)
                .addCategory(android.content.Intent.CATEGORY_HOME)
                .setPackage(googleTv)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
        if (intent.resolveActivity(getPackageManager()) == null) {
            android.content.Intent launch = getPackageManager().getLeanbackLaunchIntentForPackage(googleTv);
            if (launch == null) launch = getPackageManager().getLaunchIntentForPackage(googleTv);
            if (launch == null) return false;
            intent = launch.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        return tryStartActivity(intent);
    }

    /** Opens Android's uninstall screen for Hearth itself. The Settings flow runs the profile cleanup first. */
    private boolean uninstallSelf() {
        return tryStartActivity(new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + getPackageName()))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    /** The SUPERVISED kid profiles' user ids — Family Link-supervised profiles of this user. */
    private java.util.List<Integer> supervisedKidUserIds() {
        return profileUserIds(true);
    }

    /** The OTHER ADULT profiles' user ids — secondary profiles that are NOT supervised (grown-ups). */
    private java.util.List<Integer> adultProfileUserIds() {
        return profileUserIds(false);
    }

    /**
     * This user's other profiles, filtered by supervision: {@code wantSupervised} true returns the Family Link kids,
     * false the non-supervised adult profiles. The owner is always excluded.
     * NOTE: the adult branch is unverified on a real 2-adult TV (no test device yet); confirm getUserProfiles()
     * returns adult Google TV profiles there.
     */
    private java.util.List<Integer> profileUserIds(boolean wantSupervised) {
        java.util.List<Integer> ids = new java.util.ArrayList<>();
        android.os.UserManager um = (android.os.UserManager) getSystemService(android.content.Context.USER_SERVICE);
        if (um == null) return ids;
        android.os.UserHandle me = android.os.Process.myUserHandle();
        for (android.os.UserHandle profile : um.getUserProfiles()) {
            if (profile.equals(me)) continue;
            long serial = um.getSerialNumberForUser(profile);
            boolean supervised = Boolean.TRUE.equals(ProfileUsers.isSupervised(this, serial));
            if (supervised != wantSupervised) continue;
            int userId = userIdOf(profile);
            if (userId >= 0) ids.add(userId);
        }
        return ids;
    }

    /** The integer user id behind a {@link android.os.UserHandle} (needed for {@code pm --user}); -1 if unknown. */
    private static int userIdOf(android.os.UserHandle handle) {
        try {
            // UserHandle.getIdentifier() is @hide, so reach it reflectively; fall back to parsing "UserHandle{N}".
            return (int) android.os.UserHandle.class.getMethod("getIdentifier").invoke(handle);
        } catch (Throwable t) {
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\d+").matcher(String.valueOf(handle));
            return m.find() ? Integer.parseInt(m.group()) : -1;
        }
    }

    /** Best display name per profile user id (the name Hearth learned from Google TV's chooser), for the list. */
    private java.util.Map<Integer, String> profileDisplayNames() {
        java.util.Map<Integer, String> names = new java.util.HashMap<>();
        android.os.UserManager um = (android.os.UserManager) getSystemService(android.content.Context.USER_SERVICE);
        if (um == null) return names;
        android.os.UserHandle me = android.os.Process.myUserHandle();
        for (android.os.UserHandle profile : um.getUserProfiles()) {
            if (profile.equals(me)) continue;
            int userId = userIdOf(profile);
            if (userId < 0) continue;
            String name = ProfileUsers.getName(this, um.getSerialNumberForUser(profile));
            if (name != null && !name.isEmpty()) names.put(userId, name);
        }
        return names;
    }

    /** The TV's LAN address, for the Home Assistant integration's host field. */
    private String getLocalIpAddress() {
        try {
            for (java.net.NetworkInterface nif : java.util.Collections.list(java.net.NetworkInterface.getNetworkInterfaces())) {
                if (!nif.isUp() || nif.isLoopback()) continue;
                for (java.net.InetAddress address : java.util.Collections.list(nif.getInetAddresses())) {
                    if (address instanceof java.net.Inet4Address && address.isSiteLocalAddress()) {
                        return address.getHostAddress();
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private boolean openWifiSettings() {
        // 1. Try Android Q+ WiFi panel
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Intent panelIntent = new Intent(Settings.Panel.ACTION_WIFI);
            if (tryStartActivity(panelIntent)) {
                return true;
            }
        }

        // 2. Try standard WiFi settings
        Intent wifiIntent = new Intent(Settings.ACTION_WIFI_SETTINGS);
        if (tryStartActivity(wifiIntent)) {
            return true;
        }

        // 3. Fallback to general wireless settings
        Intent wirelessIntent = new Intent(Settings.ACTION_WIRELESS_SETTINGS);
        if (tryStartActivity(wirelessIntent)) {
            return true;
        }

        // 4. Final fallback - open main settings
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean openVpnSettings() {
        // 1. Try standard VPN settings
        Intent vpnIntent = new Intent(Settings.ACTION_VPN_SETTINGS);
        if (tryStartActivity(vpnIntent)) {
            return true;
        }

        // 2. Fallback to general wireless settings
        Intent wirelessIntent = new Intent(Settings.ACTION_WIRELESS_SETTINGS);
        if (tryStartActivity(wirelessIntent)) {
            return true;
        }

        // 3. Final fallback - open main settings
        return launchActivityFromAction(Settings.ACTION_SETTINGS);
    }

    private boolean openScreensaverSettings() {
        // Google TV's screensaver settings, then Ambient mode, then the stock dream / display / main settings.
        // The first two get their own task, so a Settings screen left open earlier doesn't come back up instead.
        return startFirst(
                ifResolves(new Intent("dreamx.two.panel.SETTINGS")
                        .setPackage("com.google.android.apps.tv.dreamx")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)),
                ifResolves(new Intent("com.google.android.tv.settings.ambient")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK)),
                new Intent(Intent.ACTION_MAIN).setClassName("com.android.tv.settings",
                        "com.android.tv.settings.device.display.daydream.DaydreamActivity"),
                new Intent(Settings.ACTION_DREAM_SETTINGS),
                new Intent(Settings.ACTION_DISPLAY_SETTINGS),
                new Intent(Settings.ACTION_SETTINGS));
    }

    private List<Map<String, Object>> getTvInputs() {
        List<Map<String, Object>> result = new ArrayList<>();
        try {
            TvInputManager manager = (TvInputManager) getSystemService(Context.TV_INPUT_SERVICE);
            if (manager != null) {
                List<TvInputInfo> inputs = manager.getTvInputList();
                for (TvInputInfo input : inputs) {
                    if (input.isPassthroughInput()) {
                        Map<String, Object> map = new HashMap<>();
                        map.put("id", input.getId());
                        CharSequence label = input.loadLabel(this);
                        map.put("label", label != null ? label.toString() : input.getId());
                        map.put("type", input.getType());
                        result.add(map);
                    }
                }
            }
        } catch (Exception e) {
            // TIF might not be supported or initialized on emulator
        }
        return result;
    }

    private boolean launchTvInput(String inputId) {
        try {
            Uri uri = TvContract.buildChannelUriForPassthroughInput(inputId);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setData(uri);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            return tryStartActivity(intent);
        } catch (Exception e) {
            return false;
        }
    }

    private boolean checkNotificationListenerPermission() {
        if (LauncherNotificationListenerService.getInstance() != null) {
            return true;
        }

        // This build's own listener only: the release and debug builds share a class name but not a package.
        ComponentName listener = new ComponentName(this, LauncherNotificationListenerService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null && nm.isNotificationListenerAccessGranted(listener)) {
                return true;
            }
        }

        String flat = Settings.Secure.getString(getContentResolver(), "enabled_notification_listeners");
        if (flat != null) {
            for (String name : flat.split(":")) {
                if (listener.equals(ComponentName.unflattenFromString(name))) {
                    return true;
                }
            }
        }
        return false;
    }

    private boolean requestNotificationListenerPermission() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent detailIntent = new Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS);
                ComponentName cn = new ComponentName(this, LauncherNotificationListenerService.class);
                detailIntent.putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, cn.flattenToString());
                detailIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                if (detailIntent.resolveActivity(getPackageManager()) != null) {
                    startActivity(detailIntent);
                    return true;
                }
            }

            Intent intent = new Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (intent.resolveActivity(getPackageManager()) != null) {
                startActivity(intent);
                return true;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    private boolean openAppNotificationSettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                if (intent.resolveActivity(getPackageManager()) != null) {
                    startActivity(intent);
                    return true;
                }
            }
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private List<Map<String, Object>> getActiveNotifications() {
        List<Map<String, Object>> list = new ArrayList<>();
        LauncherNotificationListenerService service = LauncherNotificationListenerService.getInstance();
        if (service == null) {
            return list;
        }
        try {
            StatusBarNotification[] sbns = service.getActiveNotifications();
            if (sbns != null) {
                for (StatusBarNotification sbn : sbns) {
                    Map<String, Object> map = new HashMap<>();
                    map.put("key", sbn.getKey());
                    map.put("packageName", sbn.getPackageName());
                    
                    android.app.Notification notification = sbn.getNotification();
                    String title = "";
                    String text = "";
                    if (notification != null && notification.extras != null) {
                        CharSequence titleChar = notification.extras.getCharSequence(android.app.Notification.EXTRA_TITLE);
                        CharSequence textChar = notification.extras.getCharSequence(android.app.Notification.EXTRA_TEXT);
                        if (titleChar != null) title = titleChar.toString();
                        if (textChar != null) text = textChar.toString();
                    }
                    map.put("title", title);
                    map.put("text", text);
                    map.put("isClearable", sbn.isClearable());
                    list.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    private boolean dismissNotification(String key) {
        LauncherNotificationListenerService service = LauncherNotificationListenerService.getInstance();
        if (service == null || key == null) {
            return false;
        }
        try {
            service.cancelNotification(key);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean dismissAllNotifications() {
        LauncherNotificationListenerService service = LauncherNotificationListenerService.getInstance();
        if (service == null) {
            return false;
        }
        try {
            service.cancelAllNotifications();
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this);
        }
        return true;
    }

    private boolean requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        return startFirst(
                new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName()))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private boolean checkInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return getPackageManager().canRequestPackageInstalls();
        }
        return true;
    }

    private boolean requestInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return tryStartActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        }
        return true;
    }

    /// Installs an APK previously downloaded by UpdateService through a store-style session (so the app isn't
    /// left "restricted"), falling back to the system package installer via FileProvider so the installer
    /// (a separate app) can read the file across the scoped-storage boundary.
    private boolean installApk(String path) {
        if (path == null) return false;
        try {
            java.io.File apkFile = new java.io.File(path);
            if (!apkFile.exists()) return false;
            if (SessionInstaller.install(this, apkFile)) return true;

            Uri apkUri = androidx.core.content.FileProvider.getUriForFile(
                    this, getPackageName() + ".fileprovider", apkFile);

            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(apkUri, "application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            return tryStartActivity(intent);
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private List<Map<String, Object>> getWatchNextPrograms() {
        // Another profile on: its user's Continue Watching, as its Hearth agent reported it (Android doesn't let
        // Hearth read another user's list); empty until the agent has reported
        if (ProfileApps.activeProfileUser(this) != null) {
            return AgentHub.watchNext(ProfileUsers.settledSerial(this));
        }
        return WatchNextRows.read(this);
    }

    private boolean deleteWatchNextProgram(long id) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false;
        }
        return deleteWatchNextProgramApi26(id);
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private boolean deleteWatchNextProgramApi26(long id) {
        try {
            Uri uri = TvContract.buildWatchNextProgramUri(id);
            int rowsDeleted = getContentResolver().delete(uri, null, null);
            return rowsDeleted > 0;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean launchWatchNextProgram(String intentUri) {
        if (intentUri == null || intentUri.isEmpty()) {
            return false;
        }
        try {
            Intent intent = Intent.parseUri(intentUri, Intent.URI_INTENT_SCHEME);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.setSelector(null);
            return openInApp(intent, packageOf(intent));
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    private static java.lang.ref.WeakReference<MethodChannel> sMethodChannel;

    /** Tells Flutter the active profile changed (it also re-reads it whenever Hearth comes back). */
    static void notifyProfileChanged() {
        MethodChannel channel = sMethodChannel != null ? sMethodChannel.get() : null;
        if (channel == null) return;
        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> channel.invokeMethod("profileChanged", null));
    }

    /**
     * Tells Flutter a switch to the named profile is under way (picked in Google TV's chooser): its welcome card
     * shows now, seconds before the profile user settles and the switch is confirmed.
     */
    static void notifyProfileSwitching(String name) {
        MethodChannel channel = sMethodChannel != null ? sMethodChannel.get() : null;
        if (channel == null || name == null) return;
        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> channel.invokeMethod("profileSwitching", name));
    }

    @Override
    protected void onCreate(android.os.Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // In another Google TV profile's user Hearth is that profile's agent, not a home screen: the first time
        // it's started there it hides this screen from that profile's home and keeps a quiet connection instead.
        if (AgentService.isAgent(this)) {
            AgentService.rememberKey(this, getIntent().getSourceBounds());
            AgentService.hideFromHome(this);
            AgentService.start(this);
            finish();
        }
    }

    /** Whether Hearth is the screen in front (between onResume and onPause). */
    private static volatile boolean sInFront;

    static boolean isInFront() {
        return sInFront;
    }

    @Override
    protected void onResume() {
        super.onResume();
        sInFront = true;
        // Another profile on: make sure its agent runs (starting it needs Hearth's window visible, as now)
        android.os.UserHandle profileUser = ProfileApps.activeProfileUser(this);
        if (profileUser != null) AgentHub.ensureAgent(this, ProfileUsers.settledSerial(this), profileUser);
    }

    @Override
    protected void onPause() {
        sInFront = false;
        super.onPause();
    }

    /** A search request from the remote ("voice" or "text") not yet picked up by Flutter. */
    private String mPendingSearch;

    /** Listens with the TV's speech recognizer (Google's on Google TV) and resolves with what was said, or null. */
    private void startVoiceSearch(MethodChannel.Result result) {
        if (mPendingVoiceResult != null) mPendingVoiceResult.success(null);
        Intent intent = new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        android.speech.RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
                .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Search films and shows")
                .putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1);
        try {
            mPendingVoiceResult = result;
            startActivityForResult(intent, VOICE_REQUEST);
        } catch (Exception e) {
            mPendingVoiceResult = null;
            result.success(null);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == VOICE_REQUEST) {
            MethodChannel.Result pending = mPendingVoiceResult;
            mPendingVoiceResult = null;
            String text = null;
            if (resultCode == RESULT_OK && data != null) {
                List<String> said = data.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS);
                if (said != null && !said.isEmpty()) text = said.get(0);
            }
            if (pending != null) pending.success(text);
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        handleSearchIntent(intent);
    }

    /**
     * The remote's search/mic button (mapped in Remote buttons) opens Hearth's search: Flutter hears openSearch, or
     * picks it up with takePendingSearch when it starts.
     */
    private void handleSearchIntent(Intent intent) {
        String mode = intent != null ? intent.getStringExtra(EXTRA_OPEN_SEARCH) : null;
        if (mode == null) return;
        intent.removeExtra(EXTRA_OPEN_SEARCH);
        mPendingSearch = mode;
        if (mMethodChannel != null) mMethodChannel.invokeMethod("openSearch", mode);
    }

    /**
     * Opens the intent in its app: with another profile on, in that profile's copy of the app, in its user;
     * otherwise here, once something handles it, telling Profile Pairing first.
     */
    private boolean openInApp(Intent intent, String pkg) {
        Boolean inProfile = ProfileApps.open(this, intent);
        if (inProfile != null) return inProfile;
        if (intent.resolveActivity(getPackageManager()) == null) return false;
        ProfilePairingService.onAppLaunching(this, pkg);
        return tryStartActivity(intent);
    }

    /** The app an intent opens, for Profile Pairing. */
    private String packageOf(Intent intent) {
        if (intent.getPackage() != null) return intent.getPackage();
        if (intent.getComponent() != null) return intent.getComponent().getPackageName();
        ResolveInfo info = getPackageManager().resolveActivity(intent, 0);
        return info != null && info.activityInfo != null ? info.activityInfo.packageName : null;
    }

    private boolean isAccessibilityServiceEnabled() {
        String service = getPackageName() + "/" + LauncherAccessibilityService.class.getName();
        int accessibilityEnabled = 0;
        try {
            accessibilityEnabled = Settings.Secure.getInt(
                getContentResolver(),
                Settings.Secure.ACCESSIBILITY_ENABLED
            );
        } catch (Settings.SettingNotFoundException e) {
            e.printStackTrace();
        }

        if (accessibilityEnabled == 1) {
            String settingValue = Settings.Secure.getString(
                getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            );
            if (settingValue != null) {
                String[] services = settingValue.split(":");
                for (String s : services) {
                    if (s.equalsIgnoreCase(service)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /**
     * Android 13+ marks an app installed from a downloaded APK (as the in-app updater does) as restricted:
     * its accessibility service can't be switched on, from the Settings screen or by `settings put`,
     * until `adb shell appops set <package> ACCESS_RESTRICTED_SETTINGS allow`. Apps can't read that app op
     * (it needs a system permission), so this only says whether the last install came from a file, which is
     * when Android applies the restriction.
     */
    private boolean mayHaveRestrictedSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false;
        try {
            int source = getPackageManager().getInstallSourceInfo(getPackageName()).getPackageSource();
            return source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE
                    || source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean openAccessibilitySettings() {
        return startFirst(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private boolean checkWatchNextPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return checkSelfPermission("com.android.providers.tv.permission.READ_WRITE_WATCH_NEXT_PROGRAMS") == PackageManager.PERMISSION_GRANTED
                || checkSelfPermission("android.permission.READ_TV_LISTINGS") == PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }



    /** {versionName, versionCode} of an installed app, or null when it isn't installed. */
    @SuppressWarnings("deprecation")
    private Map<String, Object> getPackageVersion(String packageName) {
        try {
            PackageInfo info = getPackageManager().getPackageInfo(packageName, 0);
            Map<String, Object> version = new HashMap<>();
            version.put("versionName", info.versionName);
            // getLongVersionCode is API 28+; older releases only have the int.
            version.put("versionCode", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    ? info.getLongVersionCode() : info.versionCode);
            return version;
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    private String getLatestWeatherData() {
        android.content.SharedPreferences prefs = getSharedPreferences(WeatherReceiver.PREFS_NAME, Context.MODE_PRIVATE);
        return prefs.getString(WeatherReceiver.KEY_WEATHER_JSON, null);
    }

    private boolean isBreezyWeatherInstalled() {
        try {
            getPackageManager().getPackageInfo("org.breezyweather", 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    private boolean openBreezyWeather() {
        try {
            Intent launchIntent = getPackageManager().getLaunchIntentForPackage("org.breezyweather");
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(launchIntent);
                return true;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == 1002) {
            if (pendingPermissionResult != null) {
                boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
                pendingPermissionResult.success(granted);
                pendingPermissionResult = null;
            }
        }
    }
}
