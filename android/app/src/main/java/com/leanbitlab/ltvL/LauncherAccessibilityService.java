package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.LauncherApps;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.hardware.HardwareBuffer;
import android.media.AudioManager;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.os.UserHandle;
import android.text.TextUtils;
import android.util.Log;
import android.view.Display;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;

public class LauncherAccessibilityService extends AccessibilityService {
    private static final String TAG = "HearthProfile";

    static final String GOOGLE_TV_PACKAGE = "com.google.android.apps.tv.launcherx";
    private static final String GOOGLE_TV_HOME_ACTIVITY = GOOGLE_TV_PACKAGE + ".home.HomeActivity";
    static final String GOOGLE_TV_CHOOSER_ACTIVITY = GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooserActivity";
    // Kids screen time / bedtime screens
    private static final String GOOGLE_TV_WELLBEING_PREFIX = GOOGLE_TV_PACKAGE + ".kids.wellbeing.";
    // The class names Google TV's views report to accessibility
    private static final String IMAGE_VIEW = "android.widget.ImageView";
    private static final String LINEAR_LAYOUT = "android.widget.LinearLayout";
    private static final String TEXT_VIEW = "android.widget.TextView";

    private static final String PROFILE_PREFS = "ltv_active_profile";
    private static final String PROFILE_NAME_KEY = "name";
    private static final String PROFILE_KEY_KEY = "key";
    private static final String PROFILE_GENERATION_KEY = "generation";
    private static final String PROFILE_READY_KEY = "ready_key";
    private static final String APP_USERS_PREFS = "ltv_app_last_profile";
    static final String DEVICE_PREFS = "ltv_device";
    private static final String IDLE_MINUTES_KEY = "idle_standby_minutes";
    private static final String HOME_FIX_SEEN_KEY = "home_button_fix_seen";
    private static final String HA_ENABLED_KEY = "ha_notifications_enabled";

    private static final long PENDING_BOUNCE_WINDOW_MS = 10_000;
    // How long "use Google TV for now" holds off the automatic bounce-back (the parent returns sooner via Home).
    private static final long GOOGLE_TV_ALLOW_MS = 10 * 60 * 1000L;
    /** How long after Google's last setup screen Hearth keeps out of the way (refreshed by each setup screen). */
    private static final long GOOGLE_SETUP_HOLD_MS = 2 * 60_000;
    private static final long KIDS_HOME_GRACE_MS = 1_500;
    private static final long PROFILE_USER_RECHECK_MS = 1_500;
    private static final long PROFILE_SETTLE_MS = 2_000;
    private static final long OWNER_SETTLE_MS = 5_000;
    /** ProfileTransitionOverlay.maxWait: the longest a profile change keeps profile_ready at 0. */
    private static final long PROFILE_READY_FALLBACK_MS = 4_000;
    private static final long PROFILE_CLICK_WINDOW_MS = 60_000;
    // The chooser is read once it has laid out and its focus animation has settled
    private static final long CHOOSER_READ_DELAY_MS = 1_200;
    private static final long SCREEN_TIME_READ_DELAY_MS = 700;
    private static final long WELLBEING_TRUST_MS = 15_000;
    private static final long IDLE_CHECK_MS = 30_000;
    private static final long IDLE_WARNING_MS = 60_000;
    private static final long LONG_PRESS_MS = 600;

    // Volatile: ProfileProvider's binder calls and AgentHub's socket threads read it too
    private static volatile LauncherAccessibilityService sInstance;
    // > now while the parent chose to use Google TV for a while: the automatic bounce-back pauses until then.
    private static volatile long sAllowGoogleTvUntil = 0;

    private final Handler mHandler = new Handler(Looper.getMainLooper());

    // Set while Google TV shows a screen time screen: the launcher must never cover it. Volatile, as sInstance.
    private volatile boolean mScreenTimeLock = false;
    // Google TV's own screens (profile chooser, PIN, time up...) are in front: leave Home to Google TV.
    private boolean mGoogleTvScreenInFront = false;
    private long mPendingBounceAt = 0;
    private long mGoogleSetupUntil = 0;
    /**
     * When Google TV's profile lock (its PIN screen for the current profile) last came up. Cancelling it opens Google
     * TV's home and, a moment later, its profile chooser over it: Hearth taking over in between would land back in
     * the locked profile, unlocked.
     */
    private long mProfileLockSeenAt = 0;
    private static final long PROFILE_LOCK_HOLD_MS = 10 * 60_000;
    // When Google TV last showed a time up / bedtime screen; it blocks the apps a moment around that, so the apps'
    // state doesn't overrule the screen for a while.
    private long mWellbeingSeenAt = 0;
    /** Google TV's time up / bedtime screen is the window in front: never lift the lock under it. */
    private boolean mWellbeingInFront = false;
    /** The apps' state settled screen time the last time it was checked (see ProfileUsers.isScreenTimeUp). */
    private boolean mScreenTimeKnown = false;
    private String mScreenTimeClass;
    /** Whether Google TV is suspending apps (a kids profile), as last seen; null until first checked. */
    private Boolean mKidsState;
    private String mLastWindowPackage;
    private String mLastAppPackage;

    // The active profile user's serial (ProfileUsers); names are learned from the chooser's current-account tile
    // and picks.
    private long mActiveSerial = ProfileUsers.UNKNOWN;
    // The last profile switch seen in the profile users, and the last chooser pick: whichever comes second pairs
    // the new serial with the picked name.
    private long mSwitchedSerial = ProfileUsers.UNKNOWN;
    private long mSwitchedAt = 0;
    private String mLastPick;
    private boolean mLastPickClicked;
    private long mLastPickAt = 0;
    private long mCandidateSerial = ProfileUsers.UNKNOWN;
    private long mCandidateAt = 0;
    /** Google TV's home came up while this candidate was waiting: it's taken without waiting any longer. */
    private boolean mCandidateSettled;
    private int mProfileUserRechecks = 0;
    private String mPendingProfile;
    private long mPendingProfileAt = 0;
    private String mLastChooserFocus;
    private long mLastChooserFocusAt = 0;
    /** Google TV's profile chooser is the window in front. */
    private boolean mChooserOnScreen;

    private HaStatusReporter mHaStatus;
    private HaNotificationServer mHaServer;
    private HaNotificationOverlay mHaOverlay;

    // Idle standby
    private long mLastInputAt = SystemClock.elapsedRealtime();
    private boolean mIdleWarned = false;

    // Remote button remapping
    private KeyCaptureCallback mCapture;
    private int mHeldKey = KeyEvent.KEYCODE_UNKNOWN;
    private boolean mLongPressFired = false;

    private final Runnable mSettleCheck = () -> checkProfileUser("settled");
    private final Runnable mProfileUserRecheck = new Runnable() {
        @Override
        public void run() {
            checkProfileUser("recheck");
            if (--mProfileUserRechecks > 0) mHandler.postDelayed(this, PROFILE_USER_RECHECK_MS);
        }
    };
    private final Runnable mReadyFallback = () -> setProfileReady(this, getActiveProfileKey(this));
    private final Runnable mReadChooser = this::readChooser;
    private final Runnable mReadScreenTime = this::readScreenTime;
    private final Runnable mKidsHomeTakeOver = () -> {
        // Not if Google TV put a screen of its own up (time up, PIN...) or the kid opened an app meanwhile
        if (autoTakeOverAllowed() && !mGoogleTvScreenInFront && GOOGLE_TV_PACKAGE.equals(mLastWindowPackage)) {
            mProfileLockSeenAt = 0; // a profile lock that led here was passed
            openLauncher();
        }
    };
    private final Runnable mPeriodicCheck = new Runnable() {
        @Override
        public void run() {
            checkIdle();
            // In case a switch broadcast was missed
            checkProfileUser("periodic check");
            updateScreenTimeLock("periodic check");
            mHandler.postDelayed(this, IDLE_CHECK_MS);
        }
    };
    private final Runnable mLongPress = () -> {
        mLongPressFired = true;
        runMapping(mHeldKey, ButtonMapper.PRESS_LONG);
    };
    private final BroadcastReceiver mProfileUserReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            UserHandle user = intent.getParcelableExtra(Intent.EXTRA_USER);
            checkProfileUser(intent.getAction() + " " + user);
            // A stopping user can still count as running for a moment
            scheduleProfileUserRechecks();
        }
    };
    private final BroadcastReceiver mScreenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            boolean on = Intent.ACTION_SCREEN_ON.equals(intent.getAction());
            if (mHaStatus != null) mHaStatus.setScreenOn(on);
            // "Lock when the TV sleeps": Google TV's profile lock on waking after long enough asleep
            if (on) {
                ProfileLock.onScreenOn(context);
            } else {
                ProfileLock.onScreenOff();
            }
        }
    };
    private final LauncherApps.Callback mSuspensionCallback = new LauncherApps.Callback() {
        @Override public void onPackageRemoved(String packageName, UserHandle user) {}
        @Override public void onPackageAdded(String packageName, UserHandle user) {
            onCompanionChanged(packageName);
        }
        @Override public void onPackageChanged(String packageName, UserHandle user) {
            onCompanionChanged(packageName);
        }
        @Override public void onPackagesAvailable(String[] packageNames, UserHandle user, boolean replacing) {}
        @Override public void onPackagesUnavailable(String[] packageNames, UserHandle user, boolean replacing) {}

        @Override
        public void onPackagesSuspended(String[] packageNames, UserHandle user) {
            onSuspensionsChanged();
        }

        @Override
        public void onPackagesUnsuspended(String[] packageNames, UserHandle user) {
            onSuspensionsChanged();
        }
    };

    /** Opens Google TV's own profile chooser. Not a public API, so starting it can fail. */
    static Intent profileChooserIntent() {
        return new Intent("com.google.android.gms.account.ProfilePickerDelegation")
                .setClassName(GOOGLE_TV_PACKAGE, GOOGLE_TV_CHOOSER_ACTIVITY);
    }

    /** Google TV's profile chooser, in either form (ProfileChooserActivity or ProfileChooserTransparentActivity). */
    private static boolean isChooser(String className) {
        return className.startsWith(GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooser");
    }

    /** Google TV's profile lock: its wrapper, or the PIN screen ("Verify your identity") it opens. */
    private static boolean isProfileLock(String className) {
        return className.startsWith(GOOGLE_TV_PACKAGE + ".profile.lock.")
                || className.equals("com.google.android.libraries.tv.reauth.ReauthActivity");
    }

    private static boolean isGoogleSetupScreen(String className) {
        String c = className.toLowerCase(Locale.ROOT);
        // Not the account check Google TV runs on every chooser visit (AccountVerification/Reauth), or Hearth
        // would hold back after ordinary switches.
        // Nor the PIN prompt (CreatePinActivity) Google TV shows on every switch into or out of a kids profile.
        return c.contains(".onboarding.") || c.contains("setup");
    }

    /** HearthTube installed or updated: whether Hearth keeps it up to date may have changed (updates_hearthtube). */
    private void onCompanionChanged(String packageName) {
        if (CompanionApps.HEARTHTUBE.equals(packageName)) ProfileProvider.notifyChanged(this);
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        sInstance = this;
        mKidsState = ProfileUsers.isKids(this);
        IntentFilter userFilter = new IntentFilter(ProfileUsers.ACTION_PROFILE_ACCESSIBLE);
        userFilter.addAction(ProfileUsers.ACTION_PROFILE_INACCESSIBLE);
        // Android 11's Google TV toggles quiet mode instead
        userFilter.addAction(Intent.ACTION_MANAGED_PROFILE_AVAILABLE);
        userFilter.addAction(Intent.ACTION_MANAGED_PROFILE_UNAVAILABLE);
        registerReceiver(mProfileUserReceiver, userFilter);
        checkProfileUser("service start");
        // Hearth's agents in the other profiles' users report and open things through this
        AgentHub.start(this);
        // Restarted (Android killed the service, an update) while this profile's screen time was up: still up,
        // until Google TV says otherwise or the profile changes.
        if (mActiveSerial != ProfileUsers.UNKNOWN && ProfileUsers.screenTimeUpSerial(this) == mActiveSerial) {
            Log.i(TAG, "Screen time was up before the restart: still up");
            mScreenTimeLock = true;
        }
        updateScreenTimeLock("service start");
        getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putBoolean(HOME_FIX_SEEN_KEY, true).apply();
        mHandler.postDelayed(mPeriodicCheck, IDLE_CHECK_MS);
        mHaOverlay = new HaNotificationOverlay(this);
        updateHaServer();
        mHaStatus = new HaStatusReporter(this);
        mHaStatus.start();
        if (mScreenTimeLock) mHaStatus.setScreenTimeLock(true);
        ProfileProvider.notifyChanged(this);  // service_running
        IntentFilter screenFilter = new IntentFilter(Intent.ACTION_SCREEN_ON);
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
        ProfileProvider.notifyChanged(this);  // service_running
        mHandler.removeCallbacksAndMessages(null);
        if (mHaServer != null) mHaServer.stop();
        if (mHaStatus != null) mHaStatus.stop();
        try {
            unregisterReceiver(mScreenReceiver);
        } catch (Exception ignored) {
        }
        try {
            unregisterReceiver(mProfileUserReceiver);
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
    private void onSuspensionsChanged() {
        // Suspensions also change when apps are installed, updated or re-approved, and Google TV re-suspends apps
        // whenever its time up screen opens, so only a switch (a chooser pick, a new profile user, or a flip
        // between a kids profile and a grown-up one) may lift the screen time lock.
        boolean picked = commitPendingProfile();
        checkProfileUser("apps suspended/unsuspended");
        boolean kids = ProfileUsers.isKids(this);
        boolean flipped = mKidsState != null && mKidsState != kids;
        mKidsState = kids;
        if (flipped) ProfileProvider.notifyChanged(this);  // kids_profile changed
        // Not mid-switch, when the kids state may still be the last profile's
        if (mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN) {
            ProfilePairing.rememberHearthProfile(this, ProfileUsers.key(mActiveSerial), kids);
        }
        if (picked || flipped || !kids) {
            clearScreenTimeLock();
        } else if (mHaStatus != null) {
            mHaStatus.onAppsChanged();
        }
        updateScreenTimeLock("apps blocked/unblocked");
        retryPendingBounce();
    }

    private void retryPendingBounce() {
        if (mPendingBounceAt != 0 && SystemClock.elapsedRealtime() - mPendingBounceAt < PENDING_BOUNCE_WINDOW_MS
                && autoTakeOverAllowed()) {
            mPendingBounceAt = 0;
            openLauncher();
        }
    }

    /** Reads which profile user is running and follows a switch there. */
    private void checkProfileUser(String why) {
        checkProfileUser(why, false);
    }

    /**
     * Reads which profile user is running and follows a switch there. settleNow: Google TV's home is up, which it
     * only opens once a switch is done, so the waiting candidate needn't hold any longer.
     */
    private void checkProfileUser(String why, boolean settleNow) {
        if (settleNow && mCandidateSerial != ProfileUsers.UNKNOWN) mCandidateSettled = true;
        long serial = ProfileUsers.activeSerial(this);
        if (serial == ProfileUsers.UNKNOWN) return;
        if (serial == mActiveSerial) {
            mCandidateSerial = ProfileUsers.UNKNOWN;
            return;
        }
        if (mActiveSerial != ProfileUsers.UNKNOWN) {
            // A switch stops every other profile user first, then starts the new one (up to 30 s), which reads as
            // the owner meanwhile: act on a new serial only once it has held for a while (longer for the owner),
            // and never on the owner while the chooser is still up (Google TV's home only opens after the switch).
            long now = SystemClock.elapsedRealtime();
            boolean owner = serial == ProfileUsers.ownerSerial(this);
            if (serial != mCandidateSerial) {
                mCandidateSerial = serial;
                mCandidateAt = now;
                mCandidateSettled = false;
            }
            long wait = (owner ? OWNER_SETTLE_MS : PROFILE_SETTLE_MS) - (now - mCandidateAt);
            if (wait > 0 && !mCandidateSettled) {
                mHandler.removeCallbacks(mSettleCheck);
                mHandler.postDelayed(mSettleCheck, wait);
                return;
            }
            // Rechecked when the chooser closes
            if (owner && mChooserOnScreen) return;
        }
        mCandidateSerial = ProfileUsers.UNKNOWN;
        long previous = mActiveSerial;
        mActiveSerial = serial;
        // A new profile (or Hearth starting): not ready until Flutter says its home is complete
        String key = ProfileUsers.key(serial);
        SharedPreferences prefs = getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE);
        boolean keyChanged = !key.equals(prefs.getString(PROFILE_KEY_KEY, null));
        prefs.edit()
                .putInt(PROFILE_GENERATION_KEY, prefs.getInt(PROFILE_GENERATION_KEY, 0) + 1)
                .remove(PROFILE_READY_KEY)
                .putString(PROFILE_KEY_KEY, key)
                .apply();
        // Flutter's welcome card says sooner when the home finishes first; with Hearth off screen (asleep, after a
        // restart) nothing would, so ready after the card's own limit regardless
        mHandler.removeCallbacks(mReadyFallback);
        mHandler.postDelayed(mReadyFallback, PROFILE_READY_FALLBACK_MS);
        Log.i(TAG, "Profile user is now serial " + serial + " ("
                + ProfileUsers.getName(this, serial) + ", " + why + ")");
        boolean named = false;
        if (previous != ProfileUsers.UNKNOWN) {
            // A switch, seen whether or not Hearth saw the chooser: pair it with the pick that made it, if any
            mSwitchedSerial = serial;
            mSwitchedAt = SystemClock.elapsedRealtime();
            named = learnProfileUserName();
        }
        // Not named yet: no name until the chooser shows who this is, rather than a guess
        String name = ProfileUsers.getName(this, serial);
        if (name == null) Log.i(TAG, "Serial " + serial + " not named yet: profile unknown");
        // HearthTube, the agents and Flutter hear once, with key and name in place: setActiveProfileName tells them
        // (here, or above when the pick named this serial); a new key under the same name tells them itself
        if (!Objects.equals(name, getActiveProfileName(this))) {
            setActiveProfileName(name);
        } else if (keyChanged && !named) {
            ProfileProvider.notifyChanged(this);
            MainActivity.notifyProfileChanged();
        }
        if (previous != ProfileUsers.UNKNOWN) {
            clearScreenTimeLock();
            updateScreenTimeLock("profile switch");
            retryPendingBounce();
        }
    }

    private void scheduleProfileUserRechecks() {
        mProfileUserRechecks = 3;
        mHandler.removeCallbacks(mProfileUserRecheck);
        mHandler.postDelayed(mProfileUserRecheck, PROFILE_USER_RECHECK_MS);
    }

    /**
     * Pairs a switch in the profile users with the chooser pick that made it, whichever came first. Returns whether
     * it named the switched serial.
     */
    private boolean learnProfileUserName() {
        long now = SystemClock.elapsedRealtime();
        if (mLastPick == null || mSwitchedSerial == ProfileUsers.UNKNOWN
                || now - mLastPickAt > PROFILE_CLICK_WINDOW_MS || now - mSwitchedAt > PROFILE_CLICK_WINDOW_MS) {
            return false;
        }
        boolean named = false;
        String existing = ProfileUsers.getName(this, mSwitchedSerial);
        long owner = ProfileUsers.serialOf(this, mLastPick);
        if (!mLastPickClicked && owner != ProfileUsers.UNKNOWN && owner != mSwitchedSerial) {
            // A guess naming a profile already known to be another serial
            Log.i(TAG, "Not naming serial " + mSwitchedSerial + " " + mLastPick
                    + ": that's serial " + owner);
        } else if (existing == null || mLastPickClicked && !existing.equals(mLastPick)) {
            nameSerial(mSwitchedSerial, mLastPick, "pick");
            named = true;
        } else if (!existing.equals(mLastPick)) {
            // Only a guess from the last focused tile: the name learned for this serial wins
            Log.i(TAG, "Serial " + mSwitchedSerial + " stays " + existing);
        }
        mLastPick = null;
        mSwitchedSerial = ProfileUsers.UNKNOWN;
        return named;
    }

    /**
     * Once the chooser has laid out: which tile is the current account, and photos for profiles that have none
     * yet or weren't checked today.
     */
    private void readChooser() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !mChooserOnScreen
                || !TextUtils.equals(GOOGLE_TV_PACKAGE, root.getPackageName())) {
            Log.i(TAG, "Chooser not readable (" + (root == null ? "no window" : root.getPackageName())
                    + ", on screen " + mChooserOnScreen + ")");
            return;
        }
        List<String> names = new ArrayList<>();
        List<Rect> photos = new ArrayList<>();
        String current = collectChooserTiles(root, names, photos, 0);
        // The current account's tile names the running profile user, unless a switch is still settling
        if (current != null && mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN
                && !current.equals(ProfileUsers.getName(this, mActiveSerial))) {
            nameSerial(mActiveSerial, current, "chooser's current account");
        }
        // Only the current account's tile, and only while it's the selected one: Google TV draws its PIN lock (and
        // dimming) on a PIN-protected profile's tile whenever another tile has focus, the current one included
        if (current != null && !current.equals(focusedTileName(root))) {
            Log.i(TAG, "Chooser shows " + names + "; photo waits until the current account's tile is selected");
            return;
        }
        // Nor mid-switch: picking a PIN-protected profile from another one shows its tile locked until the switch
        // is done, so only a profile that's already running (settled, no switch under way) is photographed
        boolean settled = mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN;
        if (current != null && (!settled || !current.equals(ProfileUsers.getName(this, mActiveSerial)))) {
            Log.i(TAG, "Chooser shows " + names + "; photo waits until " + current + " is the running profile");
            return;
        }
        Map<String, Rect> due = new LinkedHashMap<>();
        for (int i = 0; i < names.size(); i++) {
            if (names.get(i).equals(current) && ProfileAvatars.isDue(this, names.get(i))) {
                due.put(names.get(i), photos.get(i));
            }
        }
        Log.i(TAG, "Chooser shows " + names + "; photos due: " + due.keySet());
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (due.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.R
                || power == null || !power.isInteractive()) {
            return;
        }
        // A moment more first: on a slow TV the chooser draws Google's placeholder initial before the real photo
        mHandler.postDelayed(() -> {
        if (!mChooserOnScreen) return;
        takeScreenshot(Display.DEFAULT_DISPLAY, getMainExecutor(), new TakeScreenshotCallback() {
            @Override
            public void onSuccess(ScreenshotResult result) {
                final HardwareBuffer buffer = result.getHardwareBuffer();
                // Focus can move while the screenshot is taken: then the tile may already show the lock
                AccessibilityNodeInfo now = getRootInActiveWindow();
                if (now == null || !TextUtils.equals(current, focusedTileName(now))) {
                    buffer.close();
                    Log.i(TAG, "Photo dropped: the selection moved off the current account's tile");
                    return;
                }
                // Cropping and saving off the main thread; the full screenshot is never kept.
                new Thread(() -> {
                    Bitmap hardware = Bitmap.wrapHardwareBuffer(buffer, result.getColorSpace());
                    Bitmap screen = hardware != null ? hardware.copy(Bitmap.Config.ARGB_8888, false) : null;
                    if (hardware != null) hardware.recycle();
                    buffer.close();
                    if (screen == null) return;
                    boolean saved = false;
                    for (Map.Entry<String, Rect> photo : due.entrySet()) {
                        int outcome = ProfileAvatars.save(LauncherAccessibilityService.this, photo.getKey(), screen,
                                photo.getValue());
                        if (outcome == ProfileAvatars.SAVED) {
                            Log.i(TAG, "New photo for " + photo.getKey());
                            saved = true;
                        } else if (outcome == ProfileAvatars.FAILED) {
                            Log.i(TAG, "No usable photo for " + photo.getKey());
                        }
                    }
                    screen.recycle();
                    if (saved) MainActivity.notifyProfileChanged();
                }, "ProfilePhotos").start();
            }

            @Override
            public void onFailure(int errorCode) {
                Log.i(TAG, "Profile photo screenshot failed: " + errorCode);
            }
        });
        }, PHOTO_DELAY_MS);
    }

    private static final long PHOTO_DELAY_MS = 2_000;

    /** The name on the chooser tile that has focus (null if none): the selected tile. */
    private static String focusedTileName(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo focused = node.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (focused == null) return null;
        for (int i = 0; i < focused.getChildCount(); i++) {
            AccessibilityNodeInfo child = focused.getChild(i);
            if (child != null && TextUtils.equals(TEXT_VIEW, child.getClassName()) && child.getText() != null) {
                return child.getText().toString().trim();
            }
        }
        return null;
    }

    /** The first ImageView in a node's subtree. */
    private static AccessibilityNodeInfo findImage(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 6) return null;
        if (TextUtils.equals(IMAGE_VIEW, node.getClassName())) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo image = findImage(node.getChild(i), depth + 1);
            if (image != null) return image;
        }
        return null;
    }

    /**
     * Adds the chooser's profile tiles to names and photos, and returns the one marked current account (null if
     * none). A tile is a focusable LinearLayout holding the photo (an ImageView, a few frames down) and the name
     * (TextView), "Add account" aside. The current account's tile says so in its description ("... select to
     * continue with current account"), which names the running profile user without relying on focus.
     */
    private static String collectChooserTiles(AccessibilityNodeInfo node, List<String> names, List<Rect> photos,
            int depth) {
        if (node == null || depth > 20) return null;
        if (TextUtils.equals(LINEAR_LAYOUT, node.getClassName()) && node.isFocusable()) {
            String name = null;
            Rect photo = null;
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child == null || child.getClassName() == null) continue;
                if (TextUtils.equals(TEXT_VIEW, child.getClassName()) && child.getText() != null) {
                    name = child.getText().toString().trim();
                } else if (photo == null) {
                    AccessibilityNodeInfo image = findImage(child, 0);
                    if (image != null) {
                        photo = new Rect();
                        image.getBoundsInScreen(photo);
                    }
                }
            }
            if (name != null && !name.isEmpty() && photo != null
                    && !name.toLowerCase(Locale.ROOT).contains("account")) {
                names.add(name);
                photos.add(photo);
                CharSequence desc = node.getContentDescription();
                if (desc != null && desc.toString().toLowerCase(Locale.ROOT).contains("current account")) return name;
            }
            return null;
        }
        String current = null;
        for (int i = 0; i < node.getChildCount(); i++) {
            String found = collectChooserTiles(node.getChild(i), names, photos, depth + 1);
            if (found != null) current = found;
        }
        return current;
    }

    /** Learns a serial's profile name; the active profile takes it on if that's the serial. */
    private void nameSerial(long serial, String name, String how) {
        Log.i(TAG, "Serial " + serial + " is " + name + " (" + how + ")");
        ProfileUsers.setName(this, serial, name);
        // Migrate pairings saved under the profile's name to its key
        ProfilePairing.adoptNameChoices(this, ProfileUsers.key(serial), name);
        if (serial == mActiveSerial) {
            setActiveProfileName(name);
            ProfilePairing.rememberHearthProfile(this, ProfileUsers.key(serial), ProfileUsers.isKids(this));
        }
    }

    public static class UnsuspendedReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            LauncherAccessibilityService service = sInstance;
            if (service != null) {
                service.onSuspensionsChanged();
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
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (TextUtils.equals(GOOGLE_TV_PACKAGE, event.getPackageName())) {
                onGoogleTvViewEvent(event);
            }
            return;
        }
        CharSequence pkg = event.getPackageName();
        CharSequence cls = event.getClassName();
        if (pkg == null || cls == null) return;

        String packageName = pkg.toString();
        String className = cls.toString();
        boolean isGoogleTv = GOOGLE_TV_PACKAGE.equals(packageName);
        boolean isHearth = packageName.equals(getPackageName());
        boolean isApp = !isHearth && isLaunchableApp(packageName);
        mLastWindowPackage = packageName;
        // Not the keyboard, a system pop-up or the assistant's bar: those come up over the app that's still in use
        if (isHearth || isApp) mLastAppPackage = packageName;
        mWellbeingInFront = wellbeingInFront(mWellbeingInFront, isGoogleTv, isHearth || isApp, className);
        // The chooser stays "open" while Google TV lays its account check / PIN screens over it; it's over once
        // Google TV's home or any other app comes up.
        boolean wasOnScreen = mChooserOnScreen;
        if (isGoogleTv && isChooser(className)) {
            mChooserOnScreen = true;
        } else if (GOOGLE_TV_HOME_ACTIVITY.equals(className)
                || (!isGoogleTv && !"com.android.systemui".equals(packageName)
                    && !"android".equals(packageName) && !isHearth)) {
            // Not Hearth's own windows: Hearth reports window changes as it goes behind the chooser.
            mChooserOnScreen = false;
        }
        if (wasOnScreen != mChooserOnScreen) {
            Log.i(TAG, "chooser " + (mChooserOnScreen ? "open" : "closed") + " (" + packageName
                    + "/" + className + ")");
            if (!mChooserOnScreen) checkProfileUser("chooser closed");
        }

        if (isGoogleTv) {
            onGoogleTvWindow(className, event);
        } else {
            onOtherWindow(packageName, isHearth, isApp);
        }
    }

    /**
     * Whether Google TV's time up / bedtime screen is still in front after this window change. Only Google TV's own
     * windows, Hearth and apps replace it: the keyboard, a system pop-up (volume, a toast-like panel) or Google's
     * "ask a parent" flow (Play services) come up over it while it's still there, and must not lift the lock under it.
     * Nor do Google TV's plain view classes (android.widget..., android.app.Dialog): those are overlays on whichever
     * of its screens is up.
     */
    static boolean wellbeingInFront(boolean before, boolean isGoogleTv, boolean isHearthOrApp, String className) {
        if (isGoogleTv) {
            if (className.startsWith("android.")) return before;
            return className.startsWith(GOOGLE_TV_WELLBEING_PREFIX);
        }
        return !isHearthOrApp && before;
    }

    /** One of Google TV's windows: its home, the chooser, a screen time screen, a setup flow, or another screen. */
    private void onGoogleTvWindow(String className, AccessibilityEvent event) {
        boolean wellbeing = className.startsWith(GOOGLE_TV_WELLBEING_PREFIX);
        if (wellbeing) {
            mWellbeingSeenAt = SystemClock.elapsedRealtime();
            setScreenTimeLock();
        }
        reportScreenTimeText(className, event, wellbeing);
        if (isProfileLock(className)) mProfileLockSeenAt = SystemClock.elapsedRealtime();
        if (isChooser(className)) {
            mHandler.removeCallbacks(mReadChooser);
            mHandler.postDelayed(mReadChooser, CHOOSER_READ_DELAY_MS);
            checkProfileUser("chooser opened");
        }

        // Google's own setup flows (a new kids profile's onboarding, sign-in, PIN creation) open Google TV's
        // home behind themselves; Hearth stays out of the way until they're done.
        if (isGoogleSetupScreen(className)) {
            mGoogleSetupUntil = SystemClock.elapsedRealtime() + GOOGLE_SETUP_HOLD_MS;
            Log.i(TAG, "Google TV setup in progress: " + className);
        }
        if (GOOGLE_TV_HOME_ACTIVITY.equals(className)) {
            // A new profile's home: the last one's screen time no longer applies (its own comes up next)
            if (commitPendingProfile()) clearScreenTimeLock();
            // Google TV only opens its home once a switch is done: take the new profile user now, before
            // Hearth takes over, so Hearth never comes up showing the last profile
            checkProfileUser("Google TV home", true);
            updateScreenTimeLock("Google TV home");
            mGoogleTvScreenInFront = false;
            // Google TV opens its own home by component after a profile switch, on Back from apps, etc.,
            // ignoring the default home app. Bring the launcher back whenever that's allowed.
            if (SystemClock.elapsedRealtime() < mGoogleSetupUntil) {
                Log.i(TAG, "Not taking over: Google TV setup in progress");
            } else if (autoTakeOverAllowed()
                    && SystemClock.elapsedRealtime() - mProfileLockSeenAt < PROFILE_LOCK_HOLD_MS) {
                // Just after Google TV's profile lock: a right PIN leaves its home up (take over then), a cancelled
                // one brings its chooser up over the home a moment later, which keeps Hearth out (the profile
                // stays locked until someone picks a profile or enters the PIN)
                mHandler.removeCallbacks(mKidsHomeTakeOver);
                mHandler.postDelayed(mKidsHomeTakeOver, KIDS_HOME_GRACE_MS);
            } else if (autoTakeOverAllowed() && ProfileUsers.isKids(this) && !mScreenTimeKnown) {
                // A kids profile whose screen time the apps can't tell: Google TV opens its time up / bedtime
                // screen from its home a moment after the home itself, and covering the home first would hide
                // it (Hearth, the home app, can't be suspended). Take over only if the home is still in front.
                mHandler.removeCallbacks(mKidsHomeTakeOver);
                mHandler.postDelayed(mKidsHomeTakeOver, KIDS_HOME_GRACE_MS);
            } else if (autoTakeOverAllowed()) {
                openLauncher();
            } else {
                mPendingBounceAt = SystemClock.elapsedRealtime();
            }
        } else if (className.startsWith(GOOGLE_TV_PACKAGE + ".") || className.startsWith("com.google.android.libraries.tv.")) {
            // Its own screens (chooser, PIN, time up); plain view classes are overlays on its home.
            mGoogleTvScreenInFront = true;
        }
    }

    /** Any other window: Hearth, an app, or something that comes up over one (the keyboard, a system pop-up). */
    private void onOtherWindow(String packageName, boolean isHearth, boolean isApp) {
        if (isHearth) {
            // Back in the launcher without Google TV's home in between: the switch was cancelled (its early
            // welcome card goes now, not after its time limit)
            if (mPendingProfile != null) MainActivity.notifyProfileSwitchCancelled();
            mPendingProfile = null;
            mLastChooserFocus = null;
        }
        if (isApp) rememberAppUser(this, packageName);
        // Hearth or an app is in front: Google TV's own screens are gone.
        if (isHearth || isApp) {
            mGoogleTvScreenInFront = false;
            if (mHaStatus != null) mHaStatus.setForegroundPackage(packageName);
        }
    }

    /**
     * Reads why and for how long from a screen time screen, or from one of Google TV's warnings that time is
     * running out (those aren't in the wellbeing classes). Other Google TV text is ignored.
     */
    private void reportScreenTimeText(String className, AccessibilityEvent event, boolean wellbeing) {
        if (mHaStatus == null) return;
        ScreenTimeScreen screen = ScreenTimeScreen.parse(className, event.getText());
        if (wellbeing || screen.isScreenTimeText() && screen.minutesLeft != null) {
            mHaStatus.setScreenTime(screen);
        }
        if (wellbeing) {
            // The window event carries no text ("Time for bed" etc. are in its views), and the views are only
            // laid out a moment later.
            mHandler.removeCallbacks(mReadScreenTime);
            mScreenTimeClass = className;
            mHandler.postDelayed(mReadScreenTime, SCREEN_TIME_READ_DELAY_MS);
        }
    }

    /** The app last in front (Hearth included), ignoring windows that come up over it (keyboard, pop-ups). */
    static String appInFront() {
        LauncherAccessibilityService service = sInstance;
        return service != null ? service.mLastAppPackage : null;
    }

    /** The app whose window was last in front (null before the service has seen one). */
    static String foregroundPackage() {
        LauncherAccessibilityService service = sInstance;
        return service != null ? service.mLastWindowPackage : null;
    }

    private void readScreenTime() {
        if (mHaStatus == null) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !TextUtils.equals(GOOGLE_TV_PACKAGE, root.getPackageName())) {
            return;
        }
        List<CharSequence> texts = new ArrayList<>();
        collectTexts(root, texts, 0);
        if (!texts.isEmpty()) mHaStatus.setScreenTime(ScreenTimeScreen.parse(mScreenTimeClass, texts));
    }

    /** The visible text views of a window, in screen order (button labels are content descriptions, so left out). */
    private static void collectTexts(AccessibilityNodeInfo node, List<CharSequence> out, int depth) {
        if (node == null || depth > 30 || !node.isVisibleToUser()) return;
        CharSequence text = node.getText();
        if (text != null && text.length() > 0) out.add(text);
        for (int i = 0; i < node.getChildCount(); i++) {
            collectTexts(node.getChild(i), out, depth + 1);
        }
    }

    private void onGoogleTvViewEvent(AccessibilityEvent event) {
        // Never log these events' text: while the chooser is up they include Google TV's PIN keypad.
        if (event.getText() == null || event.getText().isEmpty()) return;
        String label = event.getText().get(0) != null ? event.getText().get(0).toString().trim() : "";
        // Only the round profile tiles; skip "Add account" and "Manage accounts"
        if (label.isEmpty() || !TextUtils.equals(LINEAR_LAYOUT, event.getClassName())) return;
        if (label.toLowerCase(Locale.ROOT).contains("account")) return;

        long now = SystemClock.elapsedRealtime();
        if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_FOCUSED) {
            // OK picks the focused tile, and Google TV doesn't always report the click: remember the last one.
            if (mChooserOnScreen) {
                mLastChooserFocus = label;
                mLastChooserFocusAt = now;
            }
        } else if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_CLICKED && mChooserOnScreen) {
            // Only clicks in the chooser: Google TV's other screens (its keyboard, menus) click LinearLayouts too.
            Log.i(TAG, "Picked " + label);
            mPendingProfile = label;
            mPendingProfileAt = now;
        }
    }

    /** Google TV is showing (or last showed) a kids screen time / bedtime lock; for HearthTube via ProfileProvider. */
    static boolean isScreenTimeUp() {
        LauncherAccessibilityService service = sInstance;
        return service != null && service.mScreenTimeLock;
    }

    private void setScreenTimeLock() {
        boolean changed = !mScreenTimeLock;
        mScreenTimeLock = true;
        ProfileUsers.setScreenTimeUpSerial(this, mActiveSerial);
        if (mHaStatus != null) mHaStatus.setScreenTimeLock(true);
        if (changed) ProfileProvider.notifyChanged(this);
    }

    /**
     * Screen time from the apps: in a kids profile Google TV blocks even the approved apps while time is up, and
     * unblocks them when it isn't (bedtime over, bonus time), so the lock follows that, seen or not. When they
     * can't tell, Google TV's own screens decide.
     */
    private void updateScreenTimeLock(String why) {
        if (mActiveSerial == ProfileUsers.UNKNOWN || mCandidateSerial != ProfileUsers.UNKNOWN) return;
        Boolean up = ProfileUsers.isScreenTimeUp(this, mActiveSerial);
        mScreenTimeKnown = up != null;
        if (up == null || up == mScreenTimeLock) return;
        if (up) {
            Log.i(TAG, "Screen time is up: the approved apps are blocked (" + why + ")");
            setScreenTimeLock();
        } else if (!mWellbeingInFront && SystemClock.elapsedRealtime() - mWellbeingSeenAt > WELLBEING_TRUST_MS) {
            Log.i(TAG, "Screen time is over: the approved apps are unblocked (" + why + ")");
            clearScreenTimeLock();
        }
    }

    private void clearScreenTimeLock() {
        boolean changed = mScreenTimeLock;
        mScreenTimeLock = false;
        if (changed) ProfileUsers.setScreenTimeUpSerial(this, ProfileUsers.UNKNOWN);
        if (changed) ProfileProvider.notifyChanged(this);
        if (mHaStatus != null) {
            mHaStatus.setScreenTimeLock(false);
            mHaStatus.onProfileChanged();
        }
    }

    /** Settles a profile picked in the chooser, if any, to name the profile user it starts; whether one was. */
    private boolean commitPendingProfile() {
        long now = SystemClock.elapsedRealtime();
        String chosen = null;
        boolean clicked = false;
        if (mPendingProfile != null && now - mPendingProfileAt < PROFILE_CLICK_WINDOW_MS) {
            chosen = mPendingProfile;
            clicked = true;
        } else if (mLastChooserFocus != null && now - mLastChooserFocusAt < PROFILE_CLICK_WINDOW_MS) {
            chosen = mLastChooserFocus;
            Log.i(TAG, "No click seen; using the last focused tile: " + chosen);
        }
        if (chosen != null) {
            Log.i(TAG, "Pick settled: " + chosen);
            // Picking the profile that's already on (or backing out of the chooser) starts no profile user
            if (chosen.equals(ProfileUsers.getName(this, mActiveSerial)) && mCandidateSerial == ProfileUsers.UNKNOWN) {
                chosen = null;
            }
            mLastPick = chosen;
            if (chosen != null) MainActivity.notifyProfileSwitching(chosen);
            mLastPickClicked = clicked;
            mLastPickAt = now;
            // The profile user may have switched already
            checkProfileUser("chooser pick");
            learnProfileUserName();
        }
        mPendingProfile = null;
        mLastChooserFocus = null;
        return chosen != null;
    }

    private void setActiveProfileName(String name) {
        getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).edit().putString(PROFILE_NAME_KEY, name).apply();
        if (mHaStatus != null) mHaStatus.onProfileChanged();
        ProfileProvider.notifyChanged(this);
        MainActivity.notifyProfileChanged();
    }

    /** Records that the active Google TV profile (its key) is using this app (for Continue Watching ownership). */
    private static void rememberAppUser(Context context, String packageName) {
        String profile = getActiveProfileKey(context);
        if (profile == null) return;
        SharedPreferences prefs = context.getSharedPreferences(APP_USERS_PREFS, MODE_PRIVATE);
        if (!profile.equals(prefs.getString(packageName, null))) prefs.edit().putString(packageName, profile).apply();
    }

    /**
     * For each app, the Google TV profile (key; a name for apps last used before keys) that last had it in front.
     * It comes from SharedPreferences.getAll, so callers copy it rather than change it.
     */
    static Map<String, ?> getAppLastProfiles(Context context) {
        return context.getSharedPreferences(APP_USERS_PREFS, MODE_PRIVATE).getAll();
    }

    static String getActiveProfileName(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getString(PROFILE_NAME_KEY, null);
    }

    /** Counts profile changes (and Hearth starts): HearthTube can tell a new profile from the same one. */
    static int getProfileGeneration(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getInt(PROFILE_GENERATION_KEY, 0);
    }

    /** Whether Hearth's home is complete for the active profile (Flutter reports it, see ProfileTransitionOverlay). */
    static boolean isProfileReady(Context context) {
        String key = getActiveProfileKey(context);
        return key != null && key.equals(context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE)
                .getString(PROFILE_READY_KEY, null));
    }

    static void setProfileReady(Context context, String key) {
        if (key == null || !key.equals(getActiveProfileKey(context))) return;
        context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).edit().putString(PROFILE_READY_KEY, key).apply();
        ProfileProvider.notifyChanged(context);
    }

    /** The active profile's lasting key ({@link ProfileUsers#key}), known even before its name; null until read. */
    static String getActiveProfileKey(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getString(PROFILE_KEY_KEY, null);
    }

    @Override
    public void onInterrupt() {
    }

    // --- Home Button Fix lost: an update (or anything else) turned the service off after it had been on ---

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

    // --- Idle standby: sleep after N minutes without a remote press, unless something is playing ---

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
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (minutes <= 0 || power == null || !power.isInteractive()) {
            onUserInput();
            return;
        }
        AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (isMediaPlaying() || audio != null && audio.isMusicActive()) {
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
            Toast.makeText(this, R.string.idle_sleep_warning, Toast.LENGTH_LONG).show();
        }
    }

    /**
     * An app reports playing through its media session (video apps often don't play on the music stream, which
     * is all isMusicActive sees). Needs Hearth's notification access; false without it.
     */
    private boolean isMediaPlaying() {
        MediaSessionManager sessions = (MediaSessionManager) getSystemService(Context.MEDIA_SESSION_SERVICE);
        if (sessions == null) return false;
        try {
            for (MediaController controller : sessions.getActiveSessions(
                    new ComponentName(this, LauncherNotificationListenerService.class))) {
                PlaybackState state = controller.getPlaybackState();
                if (state != null && state.getState() == PlaybackState.STATE_PLAYING) return true;
            }
        } catch (SecurityException e) {
            return false;
        }
        return false;
    }

    void sleepNow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
        }
    }

    // --- Home Assistant notifications ("Notifications for Android TV / Fire TV" protocol, port 7676) ---

    /** Status reporting to a Home Assistant webhook; empty values turn it off. */
    static void setHaStatusConfig(Context context, String baseUrl, String webhookId) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit()
                .putString(HaConfig.URL_KEY, baseUrl)
                .putString(HaConfig.WEBHOOK_KEY, webhookId)
                .apply();
        LauncherAccessibilityService service = sInstance;
        if (service != null && service.mHaStatus != null) service.mHaStatus.start();
    }

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
        Map<String, JSONObject> mapping = ButtonMapper.forKey(this, keyCode);
        if (mapping == null) return;
        // Only a long press set: fall back to it for short presses too, rather than swallowing the button
        JSONObject action = mapping.containsKey(press) ? mapping.get(press) : mapping.values().iterator().next();
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
        Map<String, JSONObject> mapping = ButtonMapper.forKey(this, keyCode);
        if (mapping == null) return false;
        // "Only on Hearth's home screen": in an app the button does its normal job. The press that started on
        // Hearth finishes there (its release follows its press even if Hearth just left the front).
        if (ButtonMapper.homeOnly(this, keyCode) && !MainActivity.isInFront() && mHeldKey != keyCode) return false;

        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
            mHeldKey = keyCode;
            mLongPressFired = false;
            if (mapping.containsKey(ButtonMapper.PRESS_LONG)) {
                mHandler.postDelayed(mLongPress, LONG_PRESS_MS);
            }
        } else if (event.getAction() == KeyEvent.ACTION_UP && keyCode == mHeldKey) {
            mHandler.removeCallbacks(mLongPress);
            if (!mLongPressFired) runMapping(keyCode, ButtonMapper.PRESS_SHORT);
            mHeldKey = KeyEvent.KEYCODE_UNKNOWN;
        }
        return true;
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        onUserInput();
        // Hearth is typing a saved profile PIN behind the cover: keys would land on the app's keypad. Back and Home
        // stop it (Home still goes on to do its usual job), everything else waits.
        // Keys Hearth injects itself (Profile Pairing moving a keypad's focus) come from no real device and pass.
        if (ProfilePairingService.isEnteringPin() && event.getDeviceId() != KeyCharacterMap.VIRTUAL_KEYBOARD) {
            int code = event.getKeyCode();
            if (code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_HOME) {
                if (event.getAction() == KeyEvent.ACTION_DOWN) ProfilePairingService.cancelPinEntry();
                if (code == KeyEvent.KEYCODE_BACK) return true;
            } else {
                return true;
            }
        }
        if (handleRemap(event)) return true;
        // Google TV can open its screens (a kids profile's PIN screen, the chooser) behind Hearth; with Hearth in
        // front none of them is showing, so Home stays with Hearth instead of waking them.
        if (MainActivity.isInFront()) mGoogleTvScreenInFront = false;
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME && event.getAction() == KeyEvent.ACTION_DOWN) {
            Log.i(TAG, "Home: screenTimeLock=" + mScreenTimeLock + " suspended=" + isSuspended(this)
                    + " googleTvInFront=" + mGoogleTvScreenInFront + " hearthInFront=" + MainActivity.isInFront());
        }
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

    /**
     * Like {@link #canTakeOver()}, but also false while the parent chose to use Google TV for a while (see
     * {@link #allowGoogleTvTemporarily()}). The AUTOMATIC bounce-backs use this so Hearth stops grabbing the screen;
     * the Home button keeps using canTakeOver(), so the parent can always get back to Hearth.
     */
    private boolean autoTakeOverAllowed() {
        return canTakeOver() && SystemClock.elapsedRealtime() >= sAllowGoogleTvUntil;
    }

    /** The parent picked "use Google TV for now": hold off the automatic bounce-back until they return or it lapses. */
    static void allowGoogleTvTemporarily() {
        sAllowGoogleTvUntil = SystemClock.elapsedRealtime() + GOOGLE_TV_ALLOW_MS;
    }

    private boolean isLaunchableApp(String packageName) {
        PackageManager pm = getPackageManager();
        return pm.getLeanbackLaunchIntentForPackage(packageName) != null || pm.getLaunchIntentForPackage(packageName) != null;
    }

    private void openLauncher() {
        // Returning to Hearth (the Home button, or any explicit open) ends a "use Google TV for now" window.
        sAllowGoogleTvUntil = 0;
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
    }

    private static boolean isSuspended(Context context) {
        try {
            ApplicationInfo info = context.getPackageManager().getApplicationInfo(context.getPackageName(), 0);
            return (info.flags & ApplicationInfo.FLAG_SUSPENDED) != 0;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }
}
