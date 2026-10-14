package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

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
    // On: Google TV's own home stays in front; Hearth no longer takes over (DEVICE_PREFS)
    static final String GOOGLE_TV_HOME_KEY = "google_tv_home";
    private static final String HOME_FIX_SEEN_KEY = "home_button_fix_seen";
    private static final String HA_ENABLED_KEY = "ha_notifications_enabled";

    private static final long PENDING_BOUNCE_WINDOW_MS = 10_000;
    // How long "use Google TV for now" holds off the automatic bounce-back (the parent returns sooner via Home).
    /** How long after Google's last setup screen Hearth keeps out of the way (refreshed by each setup screen). */
    private static final long GOOGLE_SETUP_HOLD_MS = 2 * 60_000;
    private static final long NEW_PROFILE_HOLD_MS = 15_000;
    // Reading who Google TV's home says is logged in (GoogleTvAccount): it says within about half a second
    private static final long HOME_ACCOUNT_POLL_MS = 150;
    private static final long HOME_ACCOUNT_WAIT_MS = 2_500;
    /** A home naming someone other than the pick is taken at its word once it has had this long to catch up. */
    private static final long HOME_ACCOUNT_SETTLE_MS = 1_200;
    /** How long a home naming someone other than a clicked pick has to catch up (see homeAccountDone). */
    private static final long HOME_ACCOUNT_CONTRADICT_MS = 4_000;
    /** How long after a pick the home that comes up is the one it leads to. */
    private static final long HOME_PICK_FRESH_MS = 10_000;
    /**
     * In a kids profile Google TV's kids home decides bedtime / time up, and only while it is in front: it opens its
     * time up screen once it has loaded (0.45 s after the home on the emulator), and blocks the kid's apps only after
     * that screen has been up. Hearth leaves the home this long first (1.5 s worked on the TV, 2026-10-06).
     */
    /**
     * Google TV's kids home put up a kid's bedtime screen 2.7 s after it came up on a switch between kids (the TV,
     * 2026-10-11); Hearth's welcome card covers the home meanwhile (KidsHomeCover).
     */
    private static final long KIDS_HOME_GRACE_MS = 3_500;
    private static final String KIDS_HOME_GRACE_SETTING = "hearth_kids_home_grace_ms";
    /**
     * Google TV's own home, not after its chooser: the remote's profile button opens the home and then the chooser
     * over it, 0.07 s later on the TV (2026-10-10). Hearth waits this long before covering the home, so it doesn't
     * cover the chooser instead.
     */
    private static final long HOME_GRACE_MS = 300;
    /**
     * After Google TV's profile lock: a cancelled PIN opens its home and then its chooser, which on the TV showed
     * 0.27 s after the home (2026-10-10); a right PIN leaves the home up. Long enough for the chooser to show, with
     * margin, before Hearth covers the home.
     */
    private static final long PROFILE_LOCK_GRACE_MS = 800;
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

    private final Handler mHandler = new Handler(Looper.getMainLooper());

    // Set while Google TV shows a screen time screen: the launcher must never cover it. Volatile, as sInstance.
    private volatile boolean mScreenTimeLock = false;
    // Google TV's own screens (profile chooser, PIN, time up...) are in front: leave Home to Google TV.
    private boolean mGoogleTvScreenInFront = false;
    private long mPendingBounceAt = 0;
    private long mGoogleSetupUntil = 0;
    /**
     * The setup hold is for a just-added profile: it ends as soon as that profile's user starts (a kids profile), or
     * when it runs out with none started and Google TV's home names the pick (an adult's account, see
     * mNewProfileHoldEnd).
     */
    private boolean mNewProfileHold = false;
    /** The just-added profile last picked, until a profile user starts: Google TV may mark it current regardless. */
    private String mUnstartedPick;
    /** The profile Google TV's chooser marked as its current account when it was last read. */
    private String mChooserCurrent;
    /** Reading who Google TV's home says is logged in, before Hearth covers it (readHomeAccount). */
    private boolean mReadingHomeAccount;
    private long mHomeAccountStartedAt;
    /** Who the home should name: the pick that led to it, if any. A read that agrees ends the wait at once. */
    private String mHomeAccountExpected;
    /** The last name the home gave during this read. */
    private String mHomeAccountRead;
    /** Hearth takes over the home once the read is done: always, or only if the home confirmed the pick. */
    private boolean mTakeOverAfterRead;
    private boolean mTakeOverIfConfirmed;
    /** The last pick settled, for the read of the home it leads to. */
    private String mHomePick;
    private long mHomePickAt;
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
    /**
     * Google TV put up a kids screen time / bedtime screen: whatever Android says is running, this is a locked kids
     * profile. At bedtime Google TV stops the kid's profile user and shows its screen from the owner's, so the
     * running user alone reads as the owner. Held until a profile is picked in the chooser, or the kid's own user is
     * running again with its apps unblocked (time's back).
     */
    private boolean mKidsLockHold = false;
    /** Hearth handing the screen back to Google TV while the lock is set: when, and how often lately. */
    private long mStepBackWindowStart = 0;
    private int mStepBacks = 0;
    private static final long STEP_BACK_WINDOW_MS = 60_000;
    private static final int STEP_BACKS_PER_WINDOW = 3;
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
    /** What plays, into each adult profile's watch history. */
    private PlaybackRecorder mPlayback;
    /** How long apps play in this user, into today's usage (UsageToday). */
    private PlayingClock mPlaying;
    // Today's usage: the app in front (Hearth, Google TV's own screens and the screensaver count as none), whose
    // profile it's counted for, and since when (elapsed realtime; 0 while not counting: screen off or dreaming)
    private String mFrontApp;
    private String mFrontProfile;
    private long mFrontSince;
    private boolean mInteractive = true;
    private boolean mDreaming;
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
    private static final ContentPin.Trigger CONTENT_PIN_TRIGGER = new ContentPin.Trigger();
    private final Runnable mReadScreenTime = this::readScreenTime;
    private final Runnable mKidsHomeTakeOver = () -> {
        // Not if Google TV put a screen of its own up (time up, PIN...) or the kid opened an app meanwhile
        if (autoTakeOverAllowed() && !mGoogleTvScreenInFront && GOOGLE_TV_PACKAGE.equals(mLastWindowPackage)) {
            mProfileLockSeenAt = 0; // a profile lock that led here was passed
            takeOverHome();
            // Hearth comes up under the card: it goes once Hearth is drawn, so Google's home never shows
            KidsHomeCover.hideSoon(800);
        } else {
            KidsHomeCover.hideNow();
        }
    };
    private final Runnable mHomeTakeOver = () -> {
        // Not if Google TV put a screen of its own up (the chooser) or an app came up meanwhile
        if (autoTakeOverAllowed() && !mGoogleTvScreenInFront && GOOGLE_TV_PACKAGE.equals(mLastWindowPackage)) {
            takeOverHome();
        }
    };
    /**
     * The hold for a just-added profile ran out and no profile user started: not a kids profile, then, but maybe a
     * adult's account, which lives in the owner's user. Google TV's home says; Hearth takes over if it names the
     * pick (otherwise Google TV may still be busy, and the Home button gets back).
     */
    private final Runnable mNewProfileHoldEnd = () -> {
        if (!mNewProfileHold) return;
        mNewProfileHold = false;
        if (SystemClock.elapsedRealtime() < mGoogleSetupUntil) {
            // Google TV's own setup screens are up: it's still setting the profile up
            Log.i(TAG, "No profile user started for " + LogNames.of(mUnstartedPick) + " yet; Google TV setup in progress");
            return;
        }
        Log.i(TAG, "No profile user started for " + LogNames.of(mUnstartedPick) + ": asking Google TV's home");
        mTakeOverIfConfirmed = true;
        readHomeAccount(false, mUnstartedPick);
    };
    private final Runnable mReadHomeAccount = this::readHomeAccountOnce;
    /**
     * While the chooser is "open": whether Google TV's home is in fact up. Its profile PIN, entered over the chooser,
     * can close onto the home without a window change Hearth hears (2026-10-10: Hearth stayed out, Google TV's home
     * stayed up). The home names who's logged in; the chooser and its PIN pad don't.
     */
    private final Runnable mChooserGoneCheck = this::checkChooserGone;
    private static final long CHOOSER_GONE_CHECK_MS = 1_000;
    private static final int CHOOSER_GONE_MAX_CHECKS = 180;
    /** After Home with one of Google TV's screens in front: when to look whether its home is what's up. */
    private static final long HOME_SCREEN_GONE_CHECK_MS = 700;
    private int mChooserGoneChecks;

    private void checkChooserGone() {
        if (!mChooserOnScreen) {
            checkGoogleTvScreenGone();
            return;
        }
        final AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !GOOGLE_TV_PACKAGE.equals(String.valueOf(root.getPackageName()))) {
            nextChooserGoneCheck();
            return;
        }
        try {
            mAccountReader.execute(() -> {
                String account = GoogleTvAccount.loggedIn(root);
                mHandler.post(() -> onChooserGoneChecked(account));
            });
        } catch (RejectedExecutionException e) {
            // The service is stopping
        }
    }

    private void onChooserGoneChecked(String account) {
        if (!mChooserOnScreen) return;
        if (account == null) {
            nextChooserGoneCheck();
            return;
        }
        Log.i(TAG, "chooser closed (Google TV's home is up, naming " + LogNames.of(account) + ")");
        mChooserOnScreen = false;
        mLastWindowPackage = GOOGLE_TV_PACKAGE;
        // Focus Hearth heard since the home came up was on the home's own tabs ("Home"), not on a profile tile: no
        // pick to settle. The home has said who's on; Hearth goes by that and takes the home over.
        mPendingProfile = null;
        mLastChooserFocus = null;
        checkProfileUser("chooser closed");
        onAccountLoggedIn(account, "Google TV's home");
        onGoogleTvWindow(GOOGLE_TV_HOME_ACTIVITY, null, false);
    }

    /**
     * Another of Google TV's screens is "in front" (its profile lock's PIN pad, an account check): whether its home
     * is in fact up. Those screens are see-through and can close onto the home without a window change Hearth hears;
     * Hearth then left the home up and didn't take Home either, as if the screen were still there.
     */
    private void checkGoogleTvScreenGone() {
        if (!mGoogleTvScreenInFront || mWellbeingInFront) return;
        final AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !GOOGLE_TV_PACKAGE.equals(String.valueOf(root.getPackageName()))) {
            nextChooserGoneCheck();
            return;
        }
        try {
            mAccountReader.execute(() -> {
                String account = GoogleTvAccount.loggedIn(root);
                mHandler.post(() -> onGoogleTvScreenGoneChecked(account));
            });
        } catch (RejectedExecutionException e) {
            // The service is stopping
        }
    }

    private void onGoogleTvScreenGoneChecked(String account) {
        if (!mGoogleTvScreenInFront || mChooserOnScreen || mWellbeingInFront) return;
        if (account == null) {
            nextChooserGoneCheck();
            return;
        }
        Log.i(TAG, "Google TV's screen closed (its home is up, naming " + LogNames.of(account) + ")");
        mGoogleTvScreenInFront = false;
        mLastWindowPackage = GOOGLE_TV_PACKAGE;
        onAccountLoggedIn(account, "Google TV's home");
        onGoogleTvWindow(GOOGLE_TV_HOME_ACTIVITY, null, false);
    }

    /** Starts checking whether Google TV's chooser or other screen has closed onto its home (see above). */
    private void startScreenGoneChecks(long delay) {
        mChooserGoneChecks = 0;
        mHandler.removeCallbacks(mChooserGoneCheck);
        mHandler.postDelayed(mChooserGoneCheck, delay);
    }

    private void nextChooserGoneCheck() {
        if (++mChooserGoneChecks < CHOOSER_GONE_MAX_CHECKS) {
            mHandler.postDelayed(mChooserGoneCheck, CHOOSER_GONE_CHECK_MS);
        }
    }
    private final Runnable mPeriodicCheck = new Runnable() {
        @Override
        public void run() {
            checkIdle();
            // Notification access may have come on since
            if (mPlayback != null) mPlayback.ensureStarted();
            if (mPlaying != null && mPlaying.ensureStarted()) mPlaying.flush();
            addFrontSoFar();
            readAllowance();
            // In case a switch broadcast was missed
            checkProfileUser("periodic check");
            LogNames.refresh(LauncherAccessibilityService.this);
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
            String action = intent.getAction();
            if (Intent.ACTION_DREAMING_STARTED.equals(action) || Intent.ACTION_DREAMING_STOPPED.equals(action)) {
                // The screensaver: nobody's using the app behind it
                addFrontSoFar();
                mDreaming = Intent.ACTION_DREAMING_STARTED.equals(action);
                restartFront();
                return;
            }
            boolean on = Intent.ACTION_SCREEN_ON.equals(action);
            addFrontSoFar();
            mInteractive = on;
            restartFront();
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
        @Override public void onPackageRemoved(String packageName, UserHandle user) {
            mLaunchable.remove(packageName);
        }
        @Override public void onPackageAdded(String packageName, UserHandle user) {
            mLaunchable.remove(packageName);
            onCompanionChanged(packageName);
        }
        @Override public void onPackageChanged(String packageName, UserHandle user) {
            mLaunchable.remove(packageName);
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

    /** Google TV's PIN screen ("Verify your identity", "Enter Google PIN"). */
    static final String GOOGLE_TV_REAUTH_ACTIVITY = "com.google.android.libraries.tv.reauth.ReauthActivity";

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

    /**
     * HearthTube installed or updated: whether Hearth keeps it up to date may have changed (updates_hearthtube), and
     * the kids' profiles get it too once the owner has it (KidsProfiles has the limits).
     */
    private void onCompanionChanged(String packageName) {
        if (!CompanionApps.HEARTHTUBE.equals(packageName)) return;
        ProfileProvider.notifyChanged(this);
        KidsProfiles.autoFixSoon(this);
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        sInstance = this;
        LogNames.refresh(this);
        // One of Google TV's screens may be up already (the service restarted over its chooser)
        AccessibilityNodeInfo front = getRootInActiveWindow();
        setGoogleTvEvents(front != null && GOOGLE_TV_PACKAGE.equals(String.valueOf(front.getPackageName())));
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
        // A kids' profile added while Hearth wasn't running gets Hearth (once a parent has set that up)
        KidsProfiles.autoFixSoon(this);
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
        mPlayback = new PlaybackRecorder(this);
        mPlayback.ensureStarted();
        mPlaying = new PlayingClock(this, mHandler, (pkg, ms, now) -> {
            // Hearth's own user's sessions: an adult's profile (a kid's apps play in its own user)
            String profile = getActiveProfileKey(this);
            if (ProfileUsers.serialOfKey(profile) == ProfileUsers.ownerSerial(this)) {
                UsageToday.addPlaying(this, profile, pkg, ms, now);
            }
        });
        mPlaying.ensureStarted();
        if (mScreenTimeLock) mHaStatus.setScreenTimeLock(true);
        ProfileProvider.notifyChanged(this);  // service_running
        IntentFilter screenFilter = new IntentFilter(Intent.ACTION_SCREEN_ON);
        screenFilter.addAction(Intent.ACTION_SCREEN_OFF);
        screenFilter.addAction(Intent.ACTION_DREAMING_STARTED);
        screenFilter.addAction(Intent.ACTION_DREAMING_STOPPED);
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        mInteractive = power == null || power.isInteractive();
        registerReceiver(mScreenReceiver, screenFilter);
        LauncherApps launcherApps = (LauncherApps) getSystemService(Context.LAUNCHER_APPS_SERVICE);
        if (launcherApps != null) {
            launcherApps.registerCallback(mSuspensionCallback);
        }
        // Just turned on from the setup flow: back to it
        SetupReturn.onConnected(this, SetupReturn.HOME_BUTTON_FIX);
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) sInstance = null;
        mReadingHomeAccount = false;
        mAccountReader.shutdownNow();
        ProfileProvider.notifyChanged(this);  // service_running
        mHandler.removeCallbacksAndMessages(null);
        if (mHaServer != null) mHaServer.stop();
        if (mHaStatus != null) mHaStatus.stop();
        if (mPlayback != null) mPlayback.stop();
        if (mPlaying != null) mPlaying.stop();
        addFrontSoFar();
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
        // between a kids profile and an adult one) may lift the screen time lock.
        boolean picked = commitPendingProfile();
        checkProfileUser("apps suspended/unsuspended");
        boolean kids = ProfileUsers.isKids(this);
        boolean flipped = mKidsState != null && mKidsState != kids;
        mKidsState = kids;
        if (flipped) ProfileProvider.notifyChanged(this);  // kids_profile changed
        // Not mid-switch, when the kids state may still be the last profile's
        if (mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN) {
            ProfilePairing.rememberHearthProfile(this, ProfileUsers.profileKey(this, mActiveSerial), kids);
        }
        if (mayLiftLock(mKidsLockHold, picked, flipped, kids)) {
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
            takeOverHome();
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
        mUnstartedPick = null;
        if (mNewProfileHold && previous != ProfileUsers.UNKNOWN) {
            // The just-added profile is running: Hearth takes over its home again (unless a setup screen is up)
            mNewProfileHold = false;
            mHandler.removeCallbacks(mNewProfileHoldEnd);
            mGoogleSetupUntil = 0;
            mHandler.removeCallbacks(mKidsHomeTakeOver);
            mHandler.postDelayed(mKidsHomeTakeOver, KIDS_HOME_GRACE_MS);
        }
        // Back to an adults' user: the account picked to get there, if Hearth knows it as one of that user's
        // (Google TV's home confirms it, see onAccountLoggedIn)
        String pick = previous != ProfileUsers.UNKNOWN ? recentPick() : null;
        if (pick != null && ProfileUsers.serialOf(this, pick) == serial && ProfileUsers.isGrownUps(this, serial)) {
            ProfileUsers.setLoggedIn(this, serial, pick);
        }
        boolean keyChanged = startProfile(why);
        boolean named = false;
        if (previous != ProfileUsers.UNKNOWN) {
            // A switch, seen whether or not Hearth saw the chooser: pair it with the pick that made it, if any
            mSwitchedSerial = serial;
            mSwitchedAt = SystemClock.elapsedRealtime();
            named = learnProfileUserName();
        }
        announceProfile(keyChanged, named);
        if (previous != ProfileUsers.UNKNOWN) {
            clearScreenTimeLock();
            updateScreenTimeLock("profile switch");
            retryPendingBounce();
            // A kids' profile just added gets Hearth once it's switched away from (KidsProfiles has the limits)
            KidsProfiles.autoFixSoon(this);
        }
    }

    /**
     * A profile comes on (or Hearth starts): its key in place, a new generation, and not ready until Flutter says its
     * home is complete. Returns whether the key changed.
     */
    private boolean startProfile(String why) {
        // Usage so far was the last profile's
        addFrontSoFar();
        long serial = mActiveSerial;
        String key = ProfileUsers.profileKey(this, serial);
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
        Log.i(TAG, "Profile is now " + LogNames.key(key) + " (" + LogNames.of(ProfileUsers.profileName(this, serial)) + ", "
                + why + ")");
        // An adult switching to their own profile is at the remote; a kids' profile always asks for the parent PIN
        if (keyChanged) {
            if (ProfileUsers.isGrownUps(this, serial)) {
                ParentPresence.confirmed(SystemClock.elapsedRealtime());
            } else {
                ParentPresence.ended();
            }
        }
        restartFront();
        // The new profile's allowance, fresh
        HaAllowance.readSoon();
        readAllowance();
        return keyChanged;
    }

    /** Reads each profile's allowance from Home Assistant when due; HearthTube hears through the provider. */
    private void readAllowance() {
        if (!HaAllowance.due()) return;
        HaApi.EXECUTOR.execute(() -> {
            if (HaAllowance.read(this)) mHandler.post(() -> ProfileProvider.notifyChanged(this));
        });
    }

    // --- YouTube in a kids profile ---

    /** YouTube's own TV app. */
    private static final String YOUTUBE = "com.google.android.youtube.tv";
    private static final long STEER_AGAIN_AFTER_MS = 5_000;
    private long mSteeredAt;

    /**
     * YouTube's own app came up in a kids profile that has HearthTube (a voice search, a link, a hidden app shown
     * again): kids watch YouTube only in HearthTube, where their YouTube time applies, so HearthTube opens over it.
     * A kids profile without HearthTube keeps YouTube.
     */
    private void steerKidsToHearthTube() {
        long now = SystemClock.elapsedRealtime();
        if (now - mSteeredAt < STEER_AGAIN_AFTER_MS || !ProfileUsers.isKids(this)) return;
        if (!Boolean.TRUE.equals(ProfileApps.launch(this, CompanionApps.HEARTHTUBE))) return;
        mSteeredAt = now;
        Log.i(TAG, "YouTube in a kids profile: HearthTube instead");
        Toast.makeText(this, R.string.youtube_in_hearthtube, Toast.LENGTH_LONG).show();
    }

    // --- Today's usage (UsageToday) ---

    /** The app in front changed (null: none counted, e.g. Hearth or Google TV's home). */
    private void setFrontApp(String packageName) {
        if (Objects.equals(packageName, mFrontApp)) return;
        addFrontSoFar();
        mFrontApp = packageName;
        restartFront();
    }

    /** Adds the time the app has been in front since counting (re)started, and goes on counting from now. */
    private void addFrontSoFar() {
        if (mFrontSince == 0 || mFrontApp == null) return;
        long now = SystemClock.elapsedRealtime();
        UsageToday.addFront(this, mFrontProfile, mFrontApp, now - mFrontSince, System.currentTimeMillis());
        mFrontSince = now;
    }

    /** Counts from now if an app is in front with the screen on, for the profile that's on now. */
    private void restartFront() {
        boolean counting = mFrontApp != null && mInteractive && !mDreaming;
        mFrontSince = counting ? SystemClock.elapsedRealtime() : 0;
        mFrontProfile = counting ? getActiveProfileKey(this) : null;
    }

    /**
     * HearthTube, the agents and Flutter hear once, with key and name in place: setActiveProfileName tells them, and
     * a new key under the same name is told here (unless naming the profile told them already).
     */
    private void announceProfile(boolean keyChanged, boolean named) {
        // Not named yet: no name until the chooser shows who this is, rather than a guess
        String name = ProfileUsers.profileName(this, mActiveSerial);
        if (name == null) Log.i(TAG, "Serial " + mActiveSerial + " not named yet: profile unknown");
        if (!Objects.equals(name, getActiveProfileName(this))) {
            setActiveProfileName(name);
        } else if (keyChanged && !named) {
            ProfileProvider.notifyChanged(this);
            MainActivity.notifyProfileChanged();
        }
    }

    /** The profile last picked in the chooser, if recent: settled (Google TV's home came up) or only clicked. */
    private String recentPick() {
        long now = SystemClock.elapsedRealtime();
        if (mPendingProfile != null && now - mPendingProfileAt < PROFILE_CLICK_WINDOW_MS) return mPendingProfile;
        if (mHomePick != null && now - mHomePickAt < PROFILE_CLICK_WINDOW_MS) return mHomePick;
        return null;
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
        if (existing != null && ProfileUsers.isGrownUps(this, mSwitchedSerial)) {
            // An adults' user holds a profile per account: the pick is one of them, not a new name for the user
            // (checkProfileUser took it if Hearth knows it; otherwise Google TV's home says, see onAccountLoggedIn)
        } else if (!mLastPickClicked && owner != ProfileUsers.UNKNOWN && owner != mSwitchedSerial) {
            // A guess naming a profile already known to be another serial
            Log.i(TAG, "Not naming serial " + mSwitchedSerial + " " + LogNames.of(mLastPick)
                    + ": that's serial " + owner);
        } else if (existing == null || mLastPickClicked && !existing.equals(mLastPick)) {
            nameSerial(mSwitchedSerial, mLastPick, "pick");
            named = true;
        } else if (!existing.equals(mLastPick)) {
            // Only a guess from the last focused tile: the name learned for this serial wins
            Log.i(TAG, "Serial " + mSwitchedSerial + " stays " + LogNames.of(existing));
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
        // The walk is dozens of calls into Google TV: off the main thread, where remote keys wait
        try {
            mAccountReader.execute(() -> {
                List<String> names = new ArrayList<>();
                List<String> descriptions = new ArrayList<>();
                Map<String, String> emails = new LinkedHashMap<>();
                String current = collectChooserTiles(root, names, descriptions, emails, 0);
                mHandler.post(() -> onChooserRead(current, names, descriptions, emails));
            });
        } catch (RejectedExecutionException e) {
            // The service is stopping
        }
    }

    /** What the chooser shows, read off the main thread (readChooser). */
    private void onChooserRead(String current, List<String> names, List<String> descriptions,
            Map<String, String> emails) {
        if (!mChooserOnScreen) return;
        if (current != null) mChooserCurrent = current;
        // Each profile's Google account address, which the TV's calendars are filed by (TvCalendars)
        for (Map.Entry<String, String> email : emails.entrySet()) {
            ProfileUsers.setEmail(this, email.getKey(), email.getValue());
        }
        // Each profile's Google TV PIN lock: the content PIN is typed only in an adult's locked profile
        for (int i = 0; i < names.size(); i++) {
            Boolean locked = ContentPin.lockedFromTile(descriptions.get(i), names.get(i).equals(current));
            if (locked != null) ProfileUsers.setLocked(this, names.get(i), locked);
        }
        // The current account's tile names the running profile user, unless a switch is still settling. Not when
        // it's a just-added profile that was picked but never started: Google TV can mark that one current while
        // the last profile still runs, and it mustn't rename the profile that's actually running.
        String known = mActiveSerial == ProfileUsers.UNKNOWN ? null : ProfileUsers.getName(this, mActiveSerial);
        if (current != null && mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN) {
            if (known != null && ProfileUsers.isGrownUps(this, mActiveSerial)) {
                // An adults' user holds a profile per account: the current one is the profile that's on
                onAccountLoggedIn(current, "chooser's current account");
            } else if (current.equals(known)) {
                // Already known
            } else if (known == null || !names.contains(known) || !current.equals(mUnstartedPick)) {
                nameSerial(mActiveSerial, current, "chooser's current account");
            } else {
                Log.i(TAG, "Chooser marks " + LogNames.of(current) + " current, but serial " + mActiveSerial + " (" + LogNames.of(known)
                        + ") is running: not renaming");
            }
        }
        List<String> due = new ArrayList<>();
        for (String name : names) {
            if (ProfileAvatars.isDue(this, name)) due.add(name);
        }
        Log.i(TAG, "Chooser shows " + LogNames.of(names) + "; photos due: " + LogNames.of(due));
        photographChooserTile();
    }

    // Profile photos, taken from whichever tile has focus once it's settled (ChooserPhotos says which tiles may be).
    // The chooser opens on the current account's tile, so the first try is early, before the remote moves focus.
    private static final long CHOOSER_FIRST_PHOTO_MS = 700;
    /** After focus lands on a tile: its zoom animation is done. */
    private static final long PHOTO_FOCUS_SETTLE_MS = 450;
    /** While a tile still shows Google's placeholder: the real photo may be loading. */
    private static final long PHOTO_PLACEHOLDER_RETRY_MS = 700;
    private static final int PHOTO_MAX_SHOTS_PER_VISIT = 10;
    private final Runnable mChooserPhoto = this::photographChooserTile;
    private int mChooserPhotoShots;
    private boolean mChooserPhotoBusy;
    /** When the chooser came up (elapsed realtime). */
    private long mChooserVisitAt;

    /** The focused chooser tile, if it's a profile tile. */
    private static final class FocusedTile {
        String name;
        String description;
        final Rect photo = new Rect();
    }

    private static FocusedTile focusedTile(AccessibilityNodeInfo root) {
        AccessibilityNodeInfo focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (focused == null || !TextUtils.equals(LINEAR_LAYOUT, focused.getClassName())) return null;
        FocusedTile tile = new FocusedTile();
        boolean image = false;
        for (int i = 0; i < focused.getChildCount(); i++) {
            AccessibilityNodeInfo child = focused.getChild(i);
            if (child == null || child.getClassName() == null) continue;
            if (TextUtils.equals(TEXT_VIEW, child.getClassName()) && child.getText() != null) {
                tile.name = child.getText().toString().trim();
            } else if (!image) {
                AccessibilityNodeInfo photo = findImage(child, 0);
                if (photo != null) {
                    photo.getBoundsInScreen(tile.photo);
                    image = true;
                }
            }
        }
        if (tile.name == null || tile.name.isEmpty() || !image
                || tile.name.toLowerCase(Locale.ROOT).contains("account")) {
            return null;
        }
        CharSequence desc = focused.getContentDescription();
        tile.description = desc == null ? null : desc.toString();
        return tile;
    }

    /** The name on the chooser tile that has focus (null if none): the selected tile. */
    private static String focusedTileName(AccessibilityNodeInfo root) {
        FocusedTile tile = focusedTile(root);
        return tile == null ? null : tile.name;
    }

    /**
     * Photographs the focused chooser tile for its profile's photo, when that profile is due one and the tile can't
     * be showing Google TV's PIN lock (ChooserPhotos). Runs when the chooser opens, when it's read, and whenever
     * focus settles on a tile, so a quick pass through the chooser still catches the tiles it lingers on.
     */
    private void photographChooserTile() {
        mHandler.removeCallbacks(mChooserPhoto);
        // Nor once a tile was picked in this visit: the picked tile shows the lock while the switch is under way
        if (!mChooserOnScreen || mChooserPhotoBusy || mChooserPhotoShots >= PHOTO_MAX_SHOTS_PER_VISIT
                || mPendingProfileAt >= mChooserVisitAt || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return;
        }
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (power == null || !power.isInteractive()) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !TextUtils.equals(GOOGLE_TV_PACKAGE, root.getPackageName())) return;
        FocusedTile tile = focusedTile(root);
        if (tile == null || !ProfileAvatars.isDue(this, tile.name)) return;
        List<String> names = new ArrayList<>();
        List<String> descriptions = new ArrayList<>();
        String current = collectChooserTiles(root, names, descriptions, new LinkedHashMap<>(), 0);
        String currentDesc = current == null ? null : descriptions.get(names.indexOf(current));
        // Not mid-switch: picking a PIN-protected profile shows its tile locked until the switch is done
        boolean currentIsOn = current != null && mActiveSerial != ProfileUsers.UNKNOWN
                && mCandidateSerial == ProfileUsers.UNKNOWN
                && current.equals(ProfileUsers.profileName(this, mActiveSerial));
        String whyNot = ChooserPhotos.whyNot(tile.name, tile.description, current, currentDesc, currentIsOn);
        if (whyNot != null) {
            Log.i(TAG, "No photo of " + LogNames.of(tile.name) + " now: " + whyNot);
            return;
        }
        final String name = tile.name;
        final Rect bounds = new Rect(tile.photo);
        final long pickedBefore = mPendingProfileAt;
        mChooserPhotoBusy = true;
        mChooserPhotoShots++;
        takeScreenshot(Display.DEFAULT_DISPLAY, getMainExecutor(), new TakeScreenshotCallback() {
            @Override
            public void onSuccess(ScreenshotResult result) {
                mChooserPhotoBusy = false;
                final HardwareBuffer buffer = result.getHardwareBuffer();
                // Focus can move (or the tile be picked) while the screenshot is taken: then it may show the lock
                AccessibilityNodeInfo now = getRootInActiveWindow();
                if (!mChooserOnScreen || mPendingProfileAt != pickedBefore || now == null
                        || !TextUtils.equals(name, focusedTileName(now))) {
                    buffer.close();
                    Log.i(TAG, "Photo of " + LogNames.of(name) + " dropped: the selection moved off its tile");
                    return;
                }
                // Cropping and saving off the main thread; the full screenshot is never kept.
                new Thread(() -> {
                    Bitmap hardware = Bitmap.wrapHardwareBuffer(buffer, result.getColorSpace());
                    Bitmap screen = hardware != null ? hardware.copy(Bitmap.Config.ARGB_8888, false) : null;
                    if (hardware != null) hardware.recycle();
                    buffer.close();
                    if (screen == null) return;
                    int outcome = ProfileAvatars.save(LauncherAccessibilityService.this, name, screen, bounds);
                    screen.recycle();
                    if (outcome == ProfileAvatars.SAVED) {
                        Log.i(TAG, "New photo for " + LogNames.of(name));
                    } else if (outcome == ProfileAvatars.FAILED) {
                        Log.i(TAG, "No usable photo for " + LogNames.of(name));
                    } else if (outcome == ProfileAvatars.PLACEHOLDER
                            || outcome == ProfileAvatars.PLACEHOLDER_SAVED) {
                        Log.i(TAG, "Placeholder on " + LogNames.of(name) + "'s tile"
                                + (outcome == ProfileAvatars.PLACEHOLDER_SAVED ? " (kept for now)" : "")
                                + "; trying again");
                        mHandler.postDelayed(mChooserPhoto, PHOTO_PLACEHOLDER_RETRY_MS);
                    }
                    if (outcome == ProfileAvatars.SAVED || outcome == ProfileAvatars.PLACEHOLDER_SAVED) {
                        MainActivity.notifyProfileChanged();
                    }
                }, "ProfilePhotos").start();
            }

            @Override
            public void onFailure(int errorCode) {
                mChooserPhotoBusy = false;
                Log.i(TAG, "Profile photo screenshot failed: " + errorCode);
            }
        });
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
     * Adds the chooser's profile tiles' names and descriptions, and returns the one marked current account (null if
     * none). A tile is a focusable LinearLayout holding the photo (an ImageView, a few frames down) and the name
     * (TextView), "Add account" aside. The current account's tile says so in its description ("... select to
     * continue with current account"), which names the running profile user without relying on focus.
     */
    private static String collectChooserTiles(AccessibilityNodeInfo node, List<String> names,
            List<String> descriptions, Map<String, String> emails, int depth) {
        if (node == null || depth > 20) return null;
        if (TextUtils.equals(LINEAR_LAYOUT, node.getClassName()) && node.isFocusable()) {
            String name = null;
            boolean photo = false;
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child == null || child.getClassName() == null) continue;
                if (TextUtils.equals(TEXT_VIEW, child.getClassName()) && child.getText() != null) {
                    name = child.getText().toString().trim();
                } else if (!photo) {
                    photo = findImage(child, 0) != null;
                }
            }
            if (name != null && !name.isEmpty() && photo
                    && !name.toLowerCase(Locale.ROOT).contains("account")) {
                CharSequence desc = node.getContentDescription();
                names.add(name);
                descriptions.add(desc == null ? null : desc.toString());
                String email = GoogleTvAccount.emailIn(desc);
                if (email != null) emails.put(name, email);
                if (desc != null && desc.toString().toLowerCase(Locale.ROOT).contains("current account")) return name;
            }
            return null;
        }
        String current = null;
        for (int i = 0; i < node.getChildCount(); i++) {
            String found = collectChooserTiles(node.getChild(i), names, descriptions, emails, depth + 1);
            if (found != null) current = found;
        }
        return current;
    }

    /** Learns a serial's profile name; the active profile takes it on if that's the serial. */
    private void nameSerial(long serial, String name, String how) {
        Log.i(TAG, "Serial " + serial + " is " + LogNames.of(name) + " (" + how + ")");
        ProfileUsers.setName(this, serial, name);
        // Migrate pairings saved under the profile's name to its key
        ProfilePairing.adoptNameChoices(this, ProfileUsers.key(serial), name);
        if (serial == mActiveSerial) {
            // The name may have been one of the user's other accounts, which it now stands for: then the key changed
            boolean keyChanged = !ProfileUsers.profileKey(this, serial).equals(getActiveProfileKey(this))
                    && startProfile(how);
            announceProfile(keyChanged, false);
            ProfilePairing.rememberHearthProfile(this, ProfileUsers.profileKey(this, serial), ProfileUsers.isKids(this));
        }
    }

    /**
     * Google TV says this account is logged in (its home, or the chooser's current account). In an adults' user
     * that's whose profile is on: the user's first account keeps the user's key, and another account is a profile
     * of its own (ProfileUsers.profileKey), with its own home. A kids user has the one account.
     */
    private void onAccountLoggedIn(String account, String how) {
        long serial = mActiveSerial;
        // Mid-switch, or a kid's bedtime (Google TV shows it from the owner's user): not this user's account
        if (account == null || serial == ProfileUsers.UNKNOWN || mCandidateSerial != ProfileUsers.UNKNOWN
                || mKidsLockHold || !ProfileUsers.isGrownUps(this, serial)) {
            return;
        }
        if (account.equals(ProfileUsers.profileName(this, serial))) return;
        long elsewhere = ProfileUsers.serialOf(this, account);
        if (elsewhere != ProfileUsers.UNKNOWN && elsewhere != serial && !ProfileUsers.isGrownUps(this, elsewhere)) {
            Log.i(TAG, "Google TV names " + LogNames.of(account) + ", serial " + elsewhere + "'s profile: serial "
                    + serial + " stays as it is (" + how + ")");
            return;
        }
        if (elsewhere == ProfileUsers.UNKNOWN && mNewProfileHold) {
            // Maybe a kids profile Google TV is still setting up, whose own user starts next: the hold's end decides
            Log.i(TAG, "Google TV names " + LogNames.of(account) + ", new: waiting to see if a profile user starts ("
                    + how + ")");
            return;
        }
        if (ProfileUsers.getName(this, serial) == null) {
            nameSerial(serial, account, how);
            return;
        }
        Log.i(TAG, "Serial " + serial + " is logged in as " + LogNames.of(account) + " (" + how + ")");
        ProfileUsers.setLoggedIn(this, serial, account);
        mUnstartedPick = null;
        boolean keyChanged = startProfile(how);
        // The streaming apps another adult had open would come up as theirs: they start again, at their picker
        if (keyChanged) GrownUpsApps.onProfileChanged(this, ProfileUsers.profileKey(this, serial));
        announceProfile(keyChanged, false);
        ProfilePairing.rememberHearthProfile(this, ProfileUsers.profileKey(this, serial), false);
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
        // Paramount+'s content PIN dialog (a title starting): Profile Pairing may type the saved PIN, once per dialog
        boolean contentPinDialog = ContentPin.PACKAGE.equals(packageName) && ContentPin.isDialogText(event.getText());
        if ((contentPinDialog || (!isHearth && !"com.android.systemui".equals(packageName)))
                && CONTENT_PIN_TRIGGER.onWindow(contentPinDialog)) {
            ProfilePairingService.onContentPinDialog();
        }
        // Hearth's own overlays (the welcome card over Google TV's kids home, toasts, the Home Assistant
        // notification, Profile Pairing's cover) and its agent's invisible screen in a profile's user: whatever was
        // in front is still in front under them, and a takeover waiting for Google TV's home must still see that
        if (isHearth && isHearthOverlay(className)) return;
        boolean isApp = !isHearth && isLaunchableApp(packageName);
        // Nor do the keyboard or a system pop-up (volume, a toast) replace what's in front
        if (!isOverlayPackage(packageName)) {
            mLastWindowPackage = packageName;
            ProfilePairingService.onWindowOf(packageName);
        }
        // Not the keyboard, a system pop-up or the assistant's bar: those come up over the app that's still in use
        if (isHearth || isApp) mLastAppPackage = packageName;
        if (isApp && YOUTUBE.equals(packageName)) steerKidsToHearthTube();
        if (isGoogleTv) {
            setGoogleTvEvents(true);
        } else if (isHearth || isApp) {
            setGoogleTvEvents(false);
        }
        if (isApp && !isGoogleTv) {
            setFrontApp(packageName);
        } else if (isHearth || isGoogleTv || className.startsWith("android.service.dreams.")) {
            setFrontApp(null);
        }
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
            if (mChooserOnScreen) {
                mChooserPhotoShots = 0;
                mChooserVisitAt = SystemClock.elapsedRealtime();
            } else {
                mHandler.removeCallbacks(mChooserPhoto);
                checkProfileUser("chooser closed");
            }
        }

        if (isGoogleTv) {
            onGoogleTvWindow(className, event, wasOnScreen && !mChooserOnScreen);
        } else {
            onOtherWindow(packageName, isHearth, isApp);
        }
    }

    /** Whether focus, click and scroll events (and views not marked important) are asked for now. */
    private boolean mGoogleTvEvents = false;

    /**
     * Focus, click and scroll events, and views not marked important, only while one of Google TV's own screens is in
     * front: the chooser's picks need them, and nothing else does. Every app's focus moves and scrolls otherwise had
     * an event built and sent here, on a main thread every remote key on the TV also waits for. Keys say the remote
     * is in use (idle standby) without them.
     */
    private void setGoogleTvEvents(boolean on) {
        if (on == mGoogleTvEvents) return;
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) return;
        int views = AccessibilityEvent.TYPE_VIEW_FOCUSED | AccessibilityEvent.TYPE_VIEW_CLICKED
                | AccessibilityEvent.TYPE_VIEW_SCROLLED;
        info.eventTypes = on ? info.eventTypes | views : info.eventTypes & ~views;
        info.flags = on ? info.flags | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                : info.flags & ~AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
        setServiceInfo(info);
        mGoogleTvEvents = on;
    }

    /** Hearth's windows that aren't its screens: overlays, and the agent's invisible screen (AgentActivity). */
    static boolean isHearthOverlay(String className) {
        return !className.endsWith("Activity") || className.equals(AgentActivity.class.getName());
    }

    /** A window that comes up over whatever is in front without replacing it: a system pop-up or the keyboard. */
    private boolean isOverlayPackage(String packageName) {
        if ("com.android.systemui".equals(packageName) || "android".equals(packageName)) return true;
        String ime = android.provider.Settings.Secure.getString(getContentResolver(),
                android.provider.Settings.Secure.DEFAULT_INPUT_METHOD);
        return ime != null && ime.startsWith(packageName + "/");
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

    // --- Whose profile is on in an adults' user: Google TV's home names the account (GoogleTvAccount) ---

    /** Searches Google TV's window off the main thread: each search is a call into Google TV. */
    private final ExecutorService mAccountReader = Executors.newSingleThreadExecutor();

    /**
     * Reads who Google TV's home says is logged in, a few times a second for a moment (it says once its profile
     * picture is in), and acts on it (onAccountLoggedIn). takeOver: Hearth takes over the home once it has said,
     * holding off till then. expected: the pick that led here, if any; a home that agrees ends the wait at once.
     */
    private void readHomeAccount(boolean takeOver, String expected) {
        mTakeOverAfterRead |= takeOver;
        if (mReadingHomeAccount) return;
        mReadingHomeAccount = true;
        mHomeAccountStartedAt = SystemClock.elapsedRealtime();
        mHomeAccountExpected = expected;
        mHomeAccountRead = null;
        mHandler.removeCallbacks(mReadHomeAccount);
        mHandler.postDelayed(mReadHomeAccount, HOME_ACCOUNT_POLL_MS);
    }

    private void readHomeAccountOnce() {
        if (!mReadingHomeAccount) return;
        final AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !TextUtils.equals(GOOGLE_TV_PACKAGE, root.getPackageName()) || mGoogleTvScreenInFront) {
            // The home is gone: Hearth, an app or another of Google TV's screens came up
            finishHomeAccount();
            return;
        }
        try {
            mAccountReader.execute(() -> {
                String account = GoogleTvAccount.loggedIn(root);
                mHandler.post(() -> onHomeAccountRead(account));
            });
        } catch (RejectedExecutionException e) {
            // The service is stopping
            mReadingHomeAccount = false;
        }
    }

    private void onHomeAccountRead(String account) {
        if (!mReadingHomeAccount) return;
        if (account != null) mHomeAccountRead = account;
        long waited = SystemClock.elapsedRealtime() - mHomeAccountStartedAt;
        boolean agrees = account != null && (mHomeAccountExpected == null || account.equals(mHomeAccountExpected));
        if (homeAccountDone(agrees, mHomeAccountRead != null, mHomeAccountExpected != null && mLastPickClicked,
                waited)) {
            finishHomeAccount();
        } else {
            mHandler.postDelayed(mReadHomeAccount, HOME_ACCOUNT_POLL_MS);
        }
    }

    /**
     * Whether the read of who Google TV's home names is over: it named the pick (or there was none to name), or it
     * has had its time. A clicked pick the home doesn't name yet gets longer: on a busy TV Google's home still named
     * the last account 1.2 s in and the pick 0.85 s later (2026-10-10), and taking the first at its word showed the
     * last profile, so the switch had to be made again.
     */
    static boolean homeAccountDone(boolean agrees, boolean anyRead, boolean clickedPick, long waited) {
        if (agrees) return true;
        if (anyRead && clickedPick) return waited >= HOME_ACCOUNT_CONTRADICT_MS;
        return waited >= HOME_ACCOUNT_WAIT_MS || anyRead && waited >= HOME_ACCOUNT_SETTLE_MS;
    }

    /** The home has said who's logged in (or won't): act on it, then take over if that was waiting. */
    private void finishHomeAccount() {
        mHandler.removeCallbacks(mReadHomeAccount);
        mReadingHomeAccount = false;
        String expected = mHomeAccountExpected;
        boolean takeOver = mTakeOverAfterRead;
        boolean ifConfirmed = mTakeOverIfConfirmed;
        mTakeOverAfterRead = false;
        mTakeOverIfConfirmed = false;
        if (mHomeAccountRead != null) {
            onAccountLoggedIn(mHomeAccountRead, "Google TV's home");
        } else if (expected != null && mLastPickClicked && ProfileUsers.serialOf(this, expected) == mActiveSerial) {
            // Gone before it said (another window came up): a clicked tile is the best word there is. A cancelled
            // PIN leaves the home up, which says who's on; the chooser's current account corrects it next time.
            Log.i(TAG, "Google TV's home didn't say who's logged in; going by the pick");
            onAccountLoggedIn(expected, "the pick");
        } else {
            Log.i(TAG, "Google TV's home didn't say who's logged in");
        }
        String on = ProfileUsers.profileName(this, mActiveSerial);
        boolean confirmed = expected != null && expected.equals(on);
        if (expected != null && !confirmed && ProfileUsers.serialOf(this, expected) == mActiveSerial) {
            // One of this user's profiles was picked, but Google TV kept the last: its welcome card goes
            Log.i(TAG, "Picked " + LogNames.of(expected) + ", but " + LogNames.of(on) + " is on");
            MainActivity.notifyProfileSwitchCancelled();
        }
        if ((takeOver || ifConfirmed && confirmed) && autoTakeOverAllowed() && !mGoogleTvScreenInFront
                && GOOGLE_TV_PACKAGE.equals(mLastWindowPackage) && SystemClock.elapsedRealtime() >= mGoogleSetupUntil
                && !mNewProfileHold) {
            openLauncher();
        }
    }

    /** Hearth takes over Google TV's home: now, or once the home has said who's logged in, if that's being read. */
    private void takeOverHome() {
        if (mReadingHomeAccount) {
            mTakeOverAfterRead = true;
            return;
        }
        openLauncher();
    }

    /**
     * One of Google TV's windows: its home, the chooser, a screen time screen, a setup flow, or another screen.
     * chooserClosed: it closed the chooser.
     */
    private void onGoogleTvWindow(String className, AccessibilityEvent event, boolean chooserClosed) {
        boolean wellbeing = className.startsWith(GOOGLE_TV_WELLBEING_PREFIX);
        if (wellbeing) {
            // Google's bedtime / time up screen: the kid sees it, not Hearth's card
            KidsHomeCover.hideNow();
            mWellbeingSeenAt = SystemClock.elapsedRealtime();
            // A kids profile's screen, whatever user Android reports (see mKidsLockHold)
            mKidsLockHold = true;
            setScreenTimeLock();
        }
        if (event != null) reportScreenTimeText(className, event, wellbeing);
        if (isProfileLock(className)) mProfileLockSeenAt = SystemClock.elapsedRealtime();
        // Google TV's PIN screen: its owner may allow the switch from their phone instead (PhoneApproval)
        if (GOOGLE_TV_REAUTH_ACTIVITY.equals(className)) mHandler.postDelayed(() -> PhoneApproval.onPinScreen(this), 500);
        if (isChooser(className)) {
            mHandler.removeCallbacks(mReadChooser);
            mHandler.postDelayed(mReadChooser, CHOOSER_READ_DELAY_MS);
            mHandler.removeCallbacks(mChooserPhoto);
            mHandler.postDelayed(mChooserPhoto, CHOOSER_FIRST_PHOTO_MS);
            checkProfileUser("chooser opened");
            startScreenGoneChecks(CHOOSER_GONE_CHECK_MS);
        }

        // Google's own setup flows (a new kids profile's onboarding, sign-in, PIN creation) open Google TV's
        // home behind themselves; Hearth stays out of the way until they're done.
        if (isGoogleSetupScreen(className)) {
            mGoogleSetupUntil = SystemClock.elapsedRealtime() + GOOGLE_SETUP_HOLD_MS;
            Log.i(TAG, "Google TV setup in progress: " + className);
        }
        if (GOOGLE_TV_HOME_ACTIVITY.equals(className)) {
            // A new profile's home: the last one's screen time no longer applies (its own comes up next)
            if (commitPendingProfile()) {
                clearScreenTimeLock();
                // A profile no profile user has run as yet (just added): Google TV sets it up from its own home in
                // this user before it starts the new one, and gives up if Hearth covers that home. Briefly: when
                // Google can't start it, it just stays on its home, and the Home button is the only way back.
                // (Not the profile Google itself marks current: that's the one on now, whatever Hearth calls it)
                if (mLastPick != null && ProfileUsers.serialOf(this, mLastPick) == ProfileUsers.UNKNOWN
                        && !mLastPick.equals(mChooserCurrent)) {
                    mNewProfileHold = true;
                    mUnstartedPick = mLastPick;
                    mHandler.removeCallbacks(mNewProfileHoldEnd);
                    mHandler.postDelayed(mNewProfileHoldEnd, NEW_PROFILE_HOLD_MS);
                    Log.i(TAG, "New profile " + LogNames.of(mLastPick) + ": Google TV sets it up before Hearth takes over");
                }
            }
            // Google TV only opens its home once a switch is done: take the new profile user now, before
            // Hearth takes over, so Hearth never comes up showing the last profile
            checkProfileUser("Google TV home", true);
            updateScreenTimeLock("Google TV home");
            mGoogleTvScreenInFront = false;
            // In an adults' user (a profile per account), whose profile is on is whoever the home says is logged
            // in: after the chooser Hearth reads that before it covers the home
            long now = SystemClock.elapsedRealtime();
            String pick = mHomePick != null && now - mHomePickAt < HOME_PICK_FRESH_MS ? mHomePick : null;
            // The home comes up before a picked kid's user has started, so the user Hearth last settled on is still
            // the last profile's: a fresh pick says which kind of profile this home is for
            long pickSerial = pick != null ? ProfileUsers.serialOf(this, pick) : ProfileUsers.UNKNOWN;
            Boolean pickSupervised = pickSerial != ProfileUsers.UNKNOWN
                    ? ProfileUsers.isSupervised(this, pickSerial) : null;
            // Only an adults' user has an account label worth waiting for
            boolean readAccount = mCandidateSerial == ProfileUsers.UNKNOWN && (pickSupervised != null
                    ? !pickSupervised && pickSerial == mActiveSerial
                    : ProfileUsers.isGrownUps(this, mActiveSerial));
            // Google TV opens its own home by component after a profile switch, on Back from apps, etc.,
            // ignoring the default home app. Bring the launcher back whenever that's allowed.
            boolean afterProfileLock = now - mProfileLockSeenAt < PROFILE_LOCK_HOLD_MS;
            boolean kidsHome = kidsHome(pickSupervised, ProfileUsers.isKids(this), mKidsLockHold);
            long grace = homeGraceMs(kidsHome, afterProfileLock);
            // For measuring how long Google TV's kids home takes to put up its bedtime / time up screen (adb only):
            // `settings put global hearth_kids_home_grace_ms 15000`, `settings delete global ...` to end it
            long graceOverride = android.provider.Settings.Global.getLong(getContentResolver(), KIDS_HOME_GRACE_SETTING, 0);
            if (kidsHome && graceOverride > 0) {
                grace = graceOverride;
                Log.i(TAG, "Kids' home grace set by adb: " + grace + " ms");
            }
            if (now < mGoogleSetupUntil || mNewProfileHold) {
                Log.i(TAG, "Not taking over: Google TV setup in progress");
            } else if (autoTakeOverAllowed() && grace > 0) {
                // Take over only if the home is still in front once the grace is over (see homeGraceMs)
                mHandler.removeCallbacks(mKidsHomeTakeOver);
                mHandler.postDelayed(mKidsHomeTakeOver, grace);
                // A kids profile: Hearth's card over Google's home while it decides on bedtime (it keeps running)
                if (kidsHome) KidsHomeCover.show(this, pick != null ? pick : ProfileUsers.profileName(this, mActiveSerial));
                // Only a pick in the chooser changes whose profile is on (a right PIN doesn't): only then is the home
                // read first, which the takeover waits for
                if (afterProfileLock && readAccount && pick != null) readHomeAccount(false, pick);
            } else if (autoTakeOverAllowed()) {
                if (readAccount && chooserClosed) {
                    readHomeAccount(true, pick);
                } else {
                    // Its chooser may be coming over it (the profile button); a home read under way goes first
                    mHandler.removeCallbacks(mHomeTakeOver);
                    mHandler.postDelayed(mHomeTakeOver, HOME_GRACE_MS);
                }
            } else {
                mPendingBounceAt = now;
                // Google TV's home stays: it's read whenever it comes up
                if (readAccount) readHomeAccount(false, pick);
            }
        } else if (className.startsWith(GOOGLE_TV_PACKAGE + ".") || className.startsWith("com.google.android.libraries.tv.")) {
            // Its own screens (chooser, PIN, time up); plain view classes are overlays on its home.
            mGoogleTvScreenInFront = true;
            if (!mChooserOnScreen) startScreenGoneChecks(CHOOSER_GONE_CHECK_MS);
        }
    }

    /** Any other window: Hearth, an app, or something that comes up over one (the keyboard, a system pop-up). */
    private void onOtherWindow(String packageName, boolean isHearth, boolean isApp) {
        if (isApp) KidsHomeCover.hideNow();
        if (isHearth) {
            // Back in the launcher without Google TV's home in between: the switch was cancelled (its early
            // welcome card goes now, not after its time limit)
            if (mPendingProfile != null) MainActivity.notifyProfileSwitchCancelled();
            mPendingProfile = null;
            mLastChooserFocus = null;
        }
        if (isApp) rememberAppUser(this, packageName);
        // Hearth landed on top of Google TV's screen time screen: give the screen back
        if (isHearth) stepBackIfLocked();
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

    /** The window in front, as the service sees it; null when the service isn't running. */
    static AccessibilityNodeInfo activeRoot() {
        LauncherAccessibilityService service = sInstance;
        return service != null ? service.getRootInActiveWindow() : null;
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
                // Its photo, if it's due one, once the tile has finished growing
                mHandler.removeCallbacks(mChooserPhoto);
                mHandler.postDelayed(mChooserPhoto, PHOTO_FOCUS_SETTLE_MS);
            }
        } else if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_CLICKED && mChooserOnScreen) {
            // Only clicks in the chooser: Google TV's other screens (its keyboard, menus) click LinearLayouts too.
            mHandler.removeCallbacks(mChooserPhoto);
            Log.i(TAG, "Picked " + LogNames.of(label));
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
        if (up == null || up == mScreenTimeLock) return;
        if (up) {
            Log.i(TAG, "Screen time is up: the approved apps are blocked (" + why + ")");
            setScreenTimeLock();
        } else if (!mWellbeingInFront && SystemClock.elapsedRealtime() - mWellbeingSeenAt > WELLBEING_TRUST_MS
                && (!mKidsLockHold || ProfileUsers.isKids(this))) {
            Log.i(TAG, "Screen time is over: the approved apps are unblocked (" + why + ")");
            clearScreenTimeLock();
        }
    }

    /**
     * Whether a profile change may lift the screen time lock: a pick in the chooser always does; a flip between a
     * kids profile and an adult one, or an adult profile reported, only when it wasn't Google TV's own screen
     * that set it (at bedtime the kid's user stops and the owner's is reported, but it's still the kid's bedtime).
     */
    static boolean mayLiftLock(boolean kidsLockHold, boolean picked, boolean flipped, boolean kids) {
        if (picked) return true;
        return !kidsLockHold && (flipped || !kids);
    }

    /**
     * How long Google TV's home stays up before Hearth covers it (0: at once).
     * - A kids profile (or one Google TV's screen time screen locked): always the kids grace. Google TV checks bedtime
     *   and time up only from its kids home while that's in front, and blocks the kid's apps only after its time up
     *   screen has been up, so unblocked apps don't mean there's time left. Covering the home at once (as Hearth did
     *   whenever the apps looked unblocked) meant the screen never came and the apps never got blocked: no bedtime.
     * - Just after Google TV's profile lock: a short wait for the chooser a cancelled PIN brings up.
     */
    /**
     * Whether Google TV's home that just came up is a kids home: what the fresh pick that led to it is, when Hearth
     * knows (null otherwise: the profile on now), and always while a kids screen time screen holds the lock.
     */
    static boolean kidsHome(Boolean pickSupervised, boolean activeIsKids, boolean kidsLockHold) {
        return kidsLockHold || (pickSupervised != null ? pickSupervised : activeIsKids);
    }

    static long homeGraceMs(boolean kids, boolean afterProfileLock) {
        if (kids) return KIDS_HOME_GRACE_MS;
        return afterProfileLock ? PROFILE_LOCK_GRACE_MS : 0;
    }

    /**
     * Hearth came to the front while a kids screen time lock is set: it raced Google TV's screen (Google TV opens it
     * from its home a moment after the home, and Hearth may land on top of it). Hand the screen back to Google TV's
     * home, which shows its screen again. A few times a minute at most, so it can't loop; Google TV's chooser
     * always works to switch profiles (which lifts the lock).
     */
    private void stepBackIfLocked() {
        if (!mScreenTimeLock || !(mKidsLockHold || ProfileUsers.isKids(this))) return;
        long now = SystemClock.elapsedRealtime();
        if (now - mStepBackWindowStart > STEP_BACK_WINDOW_MS) {
            mStepBackWindowStart = now;
            mStepBacks = 0;
        }
        if (++mStepBacks > STEP_BACKS_PER_WINDOW) return;
        Log.i(TAG, "Hearth is in front during screen time: back to Google TV");
        Intent home = new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .setClassName(GOOGLE_TV_PACKAGE, GOOGLE_TV_HOME_ACTIVITY)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(home);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't hand the screen back to Google TV", e);
        }
    }

    private void clearScreenTimeLock() {
        boolean changed = mScreenTimeLock;
        mScreenTimeLock = false;
        mKidsLockHold = false;
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
            Log.i(TAG, "No click seen; using the last focused tile: " + LogNames.of(chosen));
        }
        if (chosen != null) {
            Log.i(TAG, "Pick settled: " + LogNames.of(chosen));
            mHomePick = chosen;
            mHomePickAt = now;
            // Picking the profile that's already on (or backing out of the chooser) starts no profile user
            if (chosen.equals(ProfileUsers.profileName(this, mActiveSerial))
                    && mCandidateSerial == ProfileUsers.UNKNOWN) {
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
        AppWatchers.opened(context, packageName, profile);
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
        // In a kids profile the profile button does Google TV's own job: its way out of the kids profile
        if (keyCode == KeyEvent.KEYCODE_PROFILE_SWITCH && mHeldKey != keyCode
                && (mKidsLockHold || ProfileUsers.isKids(this))) {
            return false;
        }
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
        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getDeviceId() != KeyCharacterMap.VIRTUAL_KEYBOARD) {
            ParentPresence.onKey(SystemClock.elapsedRealtime());
            // Typing the PIN with the remote instead of waiting for the phone (keys Hearth types come from no device)
            if (!ProfilePairingService.isEnteringPin()) PhoneApproval.onRemoteKey(this);
        }
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
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME && event.getAction() == KeyEvent.ACTION_DOWN
                && canTakeOver() && mGoogleTvScreenInFront && !mChooserOnScreen) {
            // Home goes to Google TV as before, which may close its screen onto its home (or find the home already
            // up, with no window change to hear): look a moment later, and take the home over if it's what's up
            startScreenGoneChecks(HOME_SCREEN_GONE_CHECK_MS);
        }
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME && canTakeOver() && !mGoogleTvScreenInFront) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                // Home means the home: Settings, a panel or the Home Assistant panel over it close too. After the
                // key is answered: the TV's input waits for this method to return
                mHandler.post(() -> {
                    HaPanelActivity.closeIfOpen();
                    MainActivity.notifyHomePressed();
                    openLauncher();
                });
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
     * Like {@link #canTakeOver()}, but also false while Google TV's home is turned on in Settings (see
     * {@link #setGoogleTvHome}). The AUTOMATIC bounce-backs use this so Hearth stops grabbing the screen; the Home
     * button keeps using canTakeOver(), so Hearth (and the switch to turn this off) is always one press away.
     */
    private boolean autoTakeOverAllowed() {
        return canTakeOver() && !isGoogleTvHome(this);
    }

    /** Whether Google TV's home is on: Hearth leaves it in front instead of taking over. */
    static boolean isGoogleTvHome(Context context) {
        return context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).getBoolean(GOOGLE_TV_HOME_KEY, false);
    }

    static void setGoogleTvHome(Context context, boolean on) {
        context.getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putBoolean(GOOGLE_TV_HOME_KEY, on).apply();
        Log.i(TAG, "Google TV's home " + (on ? "on" : "off"));
    }

    /** Whether a package is an app with a launcher entry, asked once per package (two PackageManager calls). */
    private boolean isLaunchableApp(String packageName) {
        Boolean known = mLaunchable.get(packageName);
        if (known != null) return known;
        PackageManager pm = getPackageManager();
        boolean launchable = pm.getLeanbackLaunchIntentForPackage(packageName) != null
                || pm.getLaunchIntentForPackage(packageName) != null;
        mLaunchable.put(packageName, launchable);
        return launchable;
    }

    /** isLaunchableApp's answers; a package added, changed or removed is asked again. */
    private final Map<String, Boolean> mLaunchable = new java.util.HashMap<>();

    private void openLauncher() {
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
