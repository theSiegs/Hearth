package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.LauncherApps;
import android.content.pm.PackageManager;
import android.os.SystemClock;
import android.os.UserHandle;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

public class LauncherAccessibilityService extends AccessibilityService {
    static final String GOOGLE_TV_PACKAGE = "com.google.android.apps.tv.launcherx";
    private static final String GOOGLE_TV_HOME_ACTIVITY = GOOGLE_TV_PACKAGE + ".home.HomeActivity";
    // Kids screen time / bedtime screens
    private static final String GOOGLE_TV_WELLBEING_PREFIX = GOOGLE_TV_PACKAGE + ".kids.wellbeing.";
    private static final long PENDING_BOUNCE_WINDOW_MS = 10_000;

    private static LauncherAccessibilityService sInstance;

    // Set while Google TV shows a screen time screen: the launcher must never cover it.
    private boolean mScreenTimeLock = false;
    // Google TV's own screens (profile chooser, PIN, time up...) are in front: leave Home to Google TV.
    private boolean mGoogleTvScreenInFront = false;
    private long mPendingBounceAt = 0;

    // Google TV offers no API for the active profile. Every switch goes through its chooser, which opens
    // with the current profile focused and reports the picked tile in a click event, so track it there.
    private static final String GOOGLE_TV_CHOOSER_ACTIVITY = GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooserActivity";
    private static final String PROFILE_PREFS = "ltv_active_profile";
    private static final String PROFILE_NAME_KEY = "name";
    private static final long PROFILE_CLICK_WINDOW_MS = 60_000;
    private static final long CHOOSER_INITIAL_FOCUS_MS = 1_500;
    private long mChooserOpenedAt = 0;
    private String mFirstFocusLabel;
    private long mFirstFocusAt = 0;
    private String mPendingProfile;
    private long mPendingProfileAt = 0;
    private long mProfileCommittedAt = 0;
    /** Whether Google TV is suspending apps (a kids profile), as last seen; null until first checked. */
    private Boolean mKidsState;

    private final LauncherApps.Callback mSuspensionCallback = new LauncherApps.Callback() {
        @Override public void onPackageRemoved(String packageName, UserHandle user) {}
        @Override public void onPackageAdded(String packageName, UserHandle user) {}
        @Override public void onPackageChanged(String packageName, UserHandle user) {}
        @Override public void onPackagesAvailable(String[] packageNames, UserHandle user, boolean replacing) {}
        @Override public void onPackagesUnavailable(String[] packageNames, UserHandle user, boolean replacing) {}

        @Override
        public void onPackagesSuspended(String[] packageNames, UserHandle user) {
            onProfileChanged();
        }

        @Override
        public void onPackagesUnsuspended(String[] packageNames, UserHandle user) {
            onProfileChanged();
        }
    };

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        sInstance = this;
        mKidsState = hasSuspendedApps(this);
        getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putBoolean(HOME_FIX_SEEN_KEY, true).apply();
        mIdleHandler.postDelayed(mIdleCheck, IDLE_CHECK_MS);
        mHaOverlay = new HaNotificationOverlay(this);
        updateHaServer();
        mHaStatus = new HaStatusReporter(this);
        mHaStatus.start();
        android.content.IntentFilter screenFilter = new android.content.IntentFilter(Intent.ACTION_SCREEN_ON);
        screenFilter.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(mScreenReceiver, screenFilter);
        LauncherApps launcherApps = (LauncherApps) getSystemService(Context.LAUNCHER_APPS_SERVICE);
        if (launcherApps != null) {
            launcherApps.registerCallback(mSuspensionCallback);
        }
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) sInstance = null;
        mIdleHandler.removeCallbacks(mIdleCheck);
        if (mHaServer != null) mHaServer.stop();
        if (mHaStatus != null) mHaStatus.stop();
        try {
            unregisterReceiver(mScreenReceiver);
        } catch (Exception ignored) {
        }
        if (mHaOverlay != null) mHaOverlay.dismissAll();
        LauncherApps launcherApps = (LauncherApps) getSystemService(Context.LAUNCHER_APPS_SERVICE);
        if (launcherApps != null) {
            launcherApps.unregisterCallback(mSuspensionCallback);
        }
        super.onDestroy();
    }

    /**
     * A Google TV profile switch changes which apps are suspended. Leaving a kids profile, Google TV opens
     * its home first and lifts suspensions a moment later, so retry a bounce we held back.
     */
    private void onProfileChanged() {
        mScreenTimeLock = false;
        if (mHaStatus != null) {
            mHaStatus.setScreenTimeLock(false);
            mHaStatus.onProfileChanged();
        }
        commitPendingProfile();
        // Suspensions also change when apps are installed, updated or re-approved, so only a flip between a kids
        // profile and a grown-up one means a switch we didn't see: then better no name than a wrong one.
        boolean kids = hasSuspendedApps(this);
        boolean flipped = mKidsState != null && mKidsState != kids;
        mKidsState = kids;
        if (flipped && SystemClock.elapsedRealtime() - mProfileCommittedAt > PROFILE_CLICK_WINDOW_MS) {
            setActiveProfileName(null);
        }
        if (mPendingBounceAt != 0 && SystemClock.elapsedRealtime() - mPendingBounceAt < PENDING_BOUNCE_WINDOW_MS
                && canTakeOver()) {
            mPendingBounceAt = 0;
            openLauncher();
        }
    }

    public static class UnsuspendedReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            LauncherAccessibilityService service = sInstance;
            if (service != null) {
                service.onProfileChanged();
            }
        }
    }

    /**
     * Entering a kids profile that hasn't approved us, the bounce back can land before Google TV suspends us,
     * leaving the launcher on screen for the kid. Hand the screen back to Google TV's (kids) home.
     */
    public static class SuspendedReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            Intent home = new Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .setClassName(GOOGLE_TV_PACKAGE, GOOGLE_TV_HOME_ACTIVITY)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                context.startActivity(home);
            } catch (Exception ignored) {
            }
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Remote navigation moves focus or scrolls: activity for idle standby even where key events
        // don't reach the service.
        int type = event.getEventType();
        if (type == AccessibilityEvent.TYPE_VIEW_FOCUSED || type == AccessibilityEvent.TYPE_VIEW_CLICKED
                || type == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            onUserInput();
        }
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (GOOGLE_TV_PACKAGE.contentEquals(event.getPackageName() != null ? event.getPackageName() : "")) {
                onGoogleTvViewEvent(event);
            }
            return;
        }
        CharSequence pkg = event.getPackageName();
        CharSequence cls = event.getClassName();
        if (pkg == null || cls == null) return;

        String packageName = pkg.toString();
        String className = cls.toString();

        if (GOOGLE_TV_PACKAGE.equals(packageName)) {
            if (className.startsWith(GOOGLE_TV_WELLBEING_PREFIX)) {
                mScreenTimeLock = true;
                if (mHaStatus != null) mHaStatus.setScreenTimeLock(true);
            }
            if (GOOGLE_TV_CHOOSER_ACTIVITY.equals(className)) {
                long now = SystemClock.elapsedRealtime();
                if (mFirstFocusLabel != null && now - mFirstFocusAt < CHOOSER_INITIAL_FOCUS_MS) {
                    // Initial focus was reported before the window change
                    setActiveProfileName(mFirstFocusLabel);
                    mChooserOpenedAt = 0;
                } else {
                    mChooserOpenedAt = now;
                }
                mFirstFocusLabel = null;
            }

            if (GOOGLE_TV_HOME_ACTIVITY.equals(className)) {
                commitPendingProfile();
                mGoogleTvScreenInFront = false;
                // Google TV opens its own home by component after a profile switch, on Back from apps, etc.,
                // ignoring the default home app. Bring the launcher back whenever that's allowed.
                if (canTakeOver()) {
                    openLauncher();
                } else {
                    mPendingBounceAt = SystemClock.elapsedRealtime();
                }
            } else if (className.startsWith(GOOGLE_TV_PACKAGE + ".") || className.startsWith("com.google.android.libraries.tv.")) {
                // Its own screens (chooser, PIN, time up); plain view classes are overlays on its home.
                mGoogleTvScreenInFront = true;
            }
            return;
        }

        if (packageName.equals(getPackageName())) {
            // Back in the launcher without Google TV's home in between: the switch was cancelled.
            mPendingProfile = null;
        }
        if (mHaStatus != null && (packageName.equals(getPackageName()) || isLaunchableApp(packageName))) {
            mHaStatus.setForegroundPackage(packageName);
        }

        // The screen time lock only clears on a profile switch: failing safe beats covering a time up screen.
        if (packageName.equals(getPackageName()) || isLaunchableApp(packageName)) {
            mGoogleTvScreenInFront = false;
        }
    }

    private void onGoogleTvViewEvent(AccessibilityEvent event) {
        if (event.getText() == null || event.getText().isEmpty()) return;
        String label = event.getText().get(0) != null ? event.getText().get(0).toString().trim() : "";
        // Only the round profile tiles; skip "Add account" and "Manage accounts"
        if (label.isEmpty() || !"android.widget.LinearLayout".contentEquals(event.getClassName() != null ? event.getClassName() : "")) return;
        if (label.toLowerCase(java.util.Locale.ROOT).contains("account")) return;

        long now = SystemClock.elapsedRealtime();
        if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_FOCUSED) {
            // The chooser opens with the current profile focused; later focus moves are just browsing.
            if (mChooserOpenedAt != 0 && now - mChooserOpenedAt < CHOOSER_INITIAL_FOCUS_MS) {
                mChooserOpenedAt = 0;
                setActiveProfileName(label);
            } else {
                mFirstFocusLabel = label;
                mFirstFocusAt = now;
            }
        } else if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            mPendingProfile = label;
            mPendingProfileAt = now;
        }
    }

    private void commitPendingProfile() {
        if (mPendingProfile != null && SystemClock.elapsedRealtime() - mPendingProfileAt < PROFILE_CLICK_WINDOW_MS) {
            setActiveProfileName(mPendingProfile);
            mProfileCommittedAt = SystemClock.elapsedRealtime();
        }
        mPendingProfile = null;
    }

    private void setActiveProfileName(String name) {
        getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).edit().putString(PROFILE_NAME_KEY, name).apply();
        if (mHaStatus != null) mHaStatus.onProfileChanged();
        ProfileProvider.notifyChanged(this);
    }

    static String getActiveProfileName(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getString(PROFILE_NAME_KEY, null);
    }

    @Override
    public void onInterrupt() {
    }

    // --- Idle standby: sleep after N minutes without a remote press, unless something is playing ---

    static final String DEVICE_PREFS = "ltv_device";
    static final String IDLE_MINUTES_KEY = "idle_standby_minutes";
    private static final long IDLE_CHECK_MS = 30_000;
    private static final long IDLE_WARNING_MS = 60_000;

    private final android.os.Handler mIdleHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private long mLastInputAt = SystemClock.elapsedRealtime();
    private boolean mIdleWarned = false;

    private final Runnable mIdleCheck = new Runnable() {
        @Override
        public void run() {
            checkIdle();
            mIdleHandler.postDelayed(this, IDLE_CHECK_MS);
        }
    };

    // --- Home Button Fix lost: an update (or anything else) turned the service off after it had been on ---

    static final String HOME_FIX_SEEN_KEY = "home_button_fix_seen";

    /** True while the service is actually connected; Android can kill it while Settings still shows it on. */
    static boolean isRunning() {
        return sInstance != null;
    }

    static boolean wasHomeButtonFixSeen(Context context) {
        return context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).getBoolean(HOME_FIX_SEEN_KEY, false);
    }

    /** Stops the "Home Button Fix is off" reminder until the service is turned on again. */
    static void forgetHomeButtonFix(Context context) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().remove(HOME_FIX_SEEN_KEY).apply();
    }

    static int getIdleStandbyMinutes(Context context) {
        return context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).getInt(IDLE_MINUTES_KEY, 0);
    }

    static void setIdleStandbyMinutes(Context context, int minutes) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putInt(IDLE_MINUTES_KEY, minutes).apply();
        LauncherAccessibilityService service = sInstance;
        if (service != null) service.onUserInput();
    }

    private void onUserInput() {
        mLastInputAt = SystemClock.elapsedRealtime();
        mIdleWarned = false;
    }

    private void checkIdle() {
        int minutes = getIdleStandbyMinutes(this);
        android.os.PowerManager power = (android.os.PowerManager) getSystemService(Context.POWER_SERVICE);
        if (minutes <= 0 || power == null || !power.isInteractive()) {
            onUserInput();
            return;
        }
        android.media.AudioManager audio = (android.media.AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (audio != null && audio.isMusicActive()) {
            // Watching something counts as activity
            onUserInput();
            return;
        }

        long idleFor = SystemClock.elapsedRealtime() - mLastInputAt;
        long limit = minutes * 60_000L;
        if (idleFor >= limit) {
            onUserInput();
            sleepNow();
        } else if (!mIdleWarned && idleFor >= limit - IDLE_WARNING_MS) {
            mIdleWarned = true;
            android.widget.Toast.makeText(this, "No activity: going to sleep in 1 minute. Press any button to stay on.",
                    android.widget.Toast.LENGTH_LONG).show();
        }
    }

    void sleepNow() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
        }
    }

    // --- Home Assistant notifications ("Notifications for Android TV / Fire TV" protocol, port 7676) ---

    static final String HA_ENABLED_KEY = "ha_notifications_enabled";
    private HaStatusReporter mHaStatus;
    private final BroadcastReceiver mScreenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (mHaStatus != null) mHaStatus.setScreenOn(Intent.ACTION_SCREEN_ON.equals(intent.getAction()));
        }
    };

    /** Status reporting to a Home Assistant webhook; empty values turn it off. */
    static void setHaStatusConfig(Context context, String baseUrl, String webhookId) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit()
                .putString(HaStatusReporter.URL_KEY, baseUrl)
                .putString(HaStatusReporter.WEBHOOK_KEY, webhookId)
                .apply();
        LauncherAccessibilityService service = sInstance;
        if (service != null && service.mHaStatus != null) service.mHaStatus.start();
    }
    private HaNotificationServer mHaServer;
    private HaNotificationOverlay mHaOverlay;

    static boolean isHaNotificationsEnabled(Context context) {
        return context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).getBoolean(HA_ENABLED_KEY, false);
    }

    static void setHaNotificationsEnabled(Context context, boolean enabled) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putBoolean(HA_ENABLED_KEY, enabled).apply();
        LauncherAccessibilityService service = sInstance;
        if (service != null) service.updateHaServer();
    }

    /** False when the service isn't running, so nothing can be shown. */
    static boolean showHaNotification(HaNotificationServer.Notification notification) {
        LauncherAccessibilityService service = sInstance;
        if (service == null || service.mHaOverlay == null) return false;
        service.mHaOverlay.enqueue(notification);
        return true;
    }

    private void updateHaServer() {
        boolean enabled = isHaNotificationsEnabled(this);
        if (enabled && mHaServer == null) {
            mHaServer = new HaNotificationServer(notification -> mHaOverlay.enqueue(notification));
            mHaServer.start();
        } else if (!enabled && mHaServer != null) {
            mHaServer.stop();
            mHaServer = null;
        }
    }

    // --- Remote button remapping ---

    interface KeyCaptureCallback {
        void onCaptured(int keyCode);
    }

    private static final long LONG_PRESS_MS = 600;
    private KeyCaptureCallback mCapture;
    private int mHeldKey = KeyEvent.KEYCODE_UNKNOWN;
    private boolean mLongPressFired = false;
    private final Runnable mLongPress = () -> {
        mLongPressFired = true;
        runMapping(mHeldKey, ButtonMapper.PRESS_LONG);
    };

    /** The next remote button press is reported instead of acted on. False when the service isn't running. */
    static boolean captureNextKey(KeyCaptureCallback callback) {
        LauncherAccessibilityService service = sInstance;
        if (service == null) return false;
        service.mCapture = callback;
        return true;
    }

    static void cancelCapture() {
        LauncherAccessibilityService service = sInstance;
        if (service != null) service.mCapture = null;
    }

    private void runMapping(int keyCode, String press) {
        java.util.Map<String, org.json.JSONObject> mapping = ButtonMapper.forKey(this, keyCode);
        if (mapping == null) return;
        // Only a long press set: fall back to it for short presses too, rather than swallowing the button
        org.json.JSONObject action = mapping.containsKey(press) ? mapping.get(press) : mapping.values().iterator().next();
        ButtonMapper.run(this, action);
    }

    /** Returns true when the key was a capture or a remapped button. */
    private boolean handleRemap(KeyEvent event) {
        int keyCode = event.getKeyCode();
        if (mCapture != null) {
            if (event.getAction() == KeyEvent.ACTION_UP) {
                KeyCaptureCallback callback = mCapture;
                mCapture = null;
                callback.onCaptured(keyCode);
            }
            return true;
        }
        // Never let remaps get around a screen time screen
        if (mScreenTimeLock || !ButtonMapper.isRemappable(keyCode)) return false;
        java.util.Map<String, org.json.JSONObject> mapping = ButtonMapper.forKey(this, keyCode);
        if (mapping == null) return false;

        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
            mHeldKey = keyCode;
            mLongPressFired = false;
            if (mapping.containsKey(ButtonMapper.PRESS_LONG)) {
                mIdleHandler.postDelayed(mLongPress, LONG_PRESS_MS);
            }
        } else if (event.getAction() == KeyEvent.ACTION_UP && keyCode == mHeldKey) {
            mIdleHandler.removeCallbacks(mLongPress);
            if (!mLongPressFired) runMapping(keyCode, ButtonMapper.PRESS_SHORT);
            mHeldKey = KeyEvent.KEYCODE_UNKNOWN;
        }
        return true;
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        onUserInput();
        if (handleRemap(event)) return true;
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME && canTakeOver() && !mGoogleTvScreenInFront) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                openLauncher();
            }
            return true;
        }
        return super.onKeyEvent(event);
    }

    // Kids profiles that haven't approved this app suspend it; screen time screens must stay in front.
    private boolean canTakeOver() {
        return !mScreenTimeLock && !isSuspended(this);
    }

    private boolean isLaunchableApp(String packageName) {
        PackageManager pm = getPackageManager();
        return pm.getLeanbackLaunchIntentForPackage(packageName) != null || pm.getLaunchIntentForPackage(packageName) != null;
    }

    private void openLauncher() {
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
    }

    /** Whether any launchable app is suspended: Google TV does that only in kids profiles. */
    static boolean hasSuspendedApps(Context context) {
        PackageManager pm = context.getPackageManager();
        for (String category : new String[]{Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            for (android.content.pm.ResolveInfo info : pm.queryIntentActivities(
                    new Intent(Intent.ACTION_MAIN).addCategory(category), 0)) {
                if ((info.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SUSPENDED) != 0) return true;
            }
        }
        return false;
    }

    static boolean isSuspended(Context context) {
        try {
            ApplicationInfo info = context.getPackageManager().getApplicationInfo(context.getPackageName(), 0);
            return (info.flags & ApplicationInfo.FLAG_SUSPENDED) != 0;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }
}
