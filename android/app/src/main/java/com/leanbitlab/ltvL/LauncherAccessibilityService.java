package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
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

    // Which profile is active comes from Google TV's profile users (ProfileUsers), keyed by serial; their names
    // come from Google TV's chooser, which opens with the current profile focused and reports the picked tile in
    // a click event. The chooser only names profiles: the profile users alone say which one is active.
    private long mActiveSerial = ProfileUsers.UNKNOWN;
    // The last profile switch seen in the profile users, and the last chooser pick: whichever comes second pairs
    // the new serial with the picked name.
    private long mSwitchedSerial = ProfileUsers.UNKNOWN;
    private long mSwitchedAt = 0;
    private String mLastPick;
    private boolean mLastPickClicked;
    private long mLastPickAt = 0;
    private static final long PROFILE_USER_RECHECK_MS = 1_500;
    private static final long PROFILE_SETTLE_MS = 2_000;
    private static final long OWNER_SETTLE_MS = 5_000;
    private long mCandidateSerial = ProfileUsers.UNKNOWN;
    private long mCandidateAt = 0;
    private final Runnable mSettleCheck = () -> checkProfileUser("settled");
    private int mProfileUserRechecks = 0;
    private final Runnable mProfileUserRecheck = new Runnable() {
        @Override
        public void run() {
            checkProfileUser("recheck");
            if (--mProfileUserRechecks > 0) mIdleHandler.postDelayed(this, PROFILE_USER_RECHECK_MS);
        }
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
    private static final String GOOGLE_TV_CHOOSER_ACTIVITY = GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooserActivity";
    private static final String PROFILE_PREFS = "ltv_active_profile";
    private static final String PROFILE_NAME_KEY = "name";
    private static final String PROFILE_KEY_KEY = "key";
    private static final long PROFILE_CLICK_WINDOW_MS = 60_000;
    private static final long CHOOSER_INITIAL_FOCUS_MS = 1_500;
    private long mChooserOpenedAt = 0;
    private String mFirstFocusLabel;
    private long mFirstFocusAt = 0;
    private String mPendingProfile;
    private long mPendingProfileAt = 0;
    private String mLastChooserFocus;
    /** Google TV's profile chooser is the window in front. */
    private boolean mChooserOnScreen;
    private long mLastChooserFocusAt = 0;
    private static final String PROFILE_TAG = "HearthProfile";
    /** How long after Google's last setup screen Hearth keeps out of the way (refreshed by each setup screen). */
    private static final long GOOGLE_SETUP_HOLD_MS = 2 * 60_000;
    private long mGoogleSetupUntil = 0;

    /** Google TV's profile chooser, in either form (ProfileChooserActivity or ProfileChooserTransparentActivity). */
    private static boolean isChooser(String className) {
        return className.startsWith(GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooser");
    }

    private static boolean isGoogleSetupScreen(String className) {
        String c = className.toLowerCase(java.util.Locale.ROOT);
        // Not the account check Google TV runs on every chooser visit (AccountVerification/Reauth), or Hearth
        // would hold back after ordinary switches.
        // Nor the PIN prompt (CreatePinActivity) Google TV shows on every switch into or out of a kids profile.
        return c.contains(".onboarding.") || c.contains("setup");
    }
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
        mKidsState = ProfileUsers.isKids(this);
        android.content.IntentFilter userFilter = new android.content.IntentFilter(ProfileUsers.ACTION_PROFILE_ACCESSIBLE);
        userFilter.addAction(ProfileUsers.ACTION_PROFILE_INACCESSIBLE);
        // Android 11's Google TV toggles quiet mode instead
        userFilter.addAction(Intent.ACTION_MANAGED_PROFILE_AVAILABLE);
        userFilter.addAction(Intent.ACTION_MANAGED_PROFILE_UNAVAILABLE);
        registerReceiver(mProfileUserReceiver, userFilter);
        checkProfileUser("service start");
        // Restarted (Android killed the service, an update) while this profile's screen time was up: still up,
        // until Google TV says otherwise or the profile changes.
        if (mActiveSerial != ProfileUsers.UNKNOWN && ProfileUsers.screenTimeUpSerial(this) == mActiveSerial) {
            android.util.Log.i(PROFILE_TAG, "Screen time was up before the restart: still up");
            mScreenTimeLock = true;
        }
        updateScreenTimeLock("service start");
        getSharedPreferences(DEVICE_PREFS, MODE_PRIVATE).edit().putBoolean(HOME_FIX_SEEN_KEY, true).apply();
        mIdleHandler.postDelayed(mIdleCheck, IDLE_CHECK_MS);
        mHaOverlay = new HaNotificationOverlay(this);
        updateHaServer();
        mHaStatus = new HaStatusReporter(this);
        mHaStatus.start();
        if (mScreenTimeLock) mHaStatus.setScreenTimeLock(true);
        ProfileProvider.notifyChanged(this);  // service_running
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
        ProfileProvider.notifyChanged(this);  // service_running
        mIdleHandler.removeCallbacks(mIdleCheck);
        mIdleHandler.removeCallbacks(mKidsHomeTakeOver);
        mIdleHandler.removeCallbacks(mReadScreenTime);
        mIdleHandler.removeCallbacks(mProfileUserRecheck);
        mIdleHandler.removeCallbacks(mSettleCheck);
        mIdleHandler.removeCallbacks(mReadChooser);
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
    private void onProfileChanged() {
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
                && canTakeOver()) {
            mPendingBounceAt = 0;
            openLauncher();
        }
    }

    /** Reads which profile user is running and follows a switch there. */
    private void checkProfileUser(String why) {
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
            long settle = owner ? OWNER_SETTLE_MS : PROFILE_SETTLE_MS;
            if (serial != mCandidateSerial) {
                mCandidateSerial = serial;
                mCandidateAt = now;
            }
            if (now - mCandidateAt < settle || owner && mChooserOnScreen) {
                if (now - mCandidateAt >= settle) {
                    // Rechecked when the chooser closes
                    return;
                }
                mIdleHandler.removeCallbacks(mSettleCheck);
                mIdleHandler.postDelayed(mSettleCheck, settle - (now - mCandidateAt));
                return;
            }
        }
        mCandidateSerial = ProfileUsers.UNKNOWN;
        long previous = mActiveSerial;
        mActiveSerial = serial;
        if (!ProfileUsers.key(serial).equals(getActiveProfileKey(this))) {
            getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).edit().putString(PROFILE_KEY_KEY, ProfileUsers.key(serial)).apply();
            ProfileProvider.notifyChanged(this);
            MainActivity.notifyProfileChanged();
        }
        android.util.Log.i(PROFILE_TAG, "Profile user is now serial " + serial + " ("
                + ProfileUsers.getName(this, serial) + ", " + why + ")");
        if (previous != ProfileUsers.UNKNOWN) {
            // A switch, seen whether or not Hearth saw the chooser: pair it with the pick that made it, if any
            mSwitchedSerial = serial;
            mSwitchedAt = SystemClock.elapsedRealtime();
            learnProfileUserName();
        }
        // Not named yet: no name until the chooser shows who this is, rather than a guess
        String name = ProfileUsers.getName(this, serial);
        if (name == null) android.util.Log.i(PROFILE_TAG, "Serial " + serial + " not named yet: profile unknown");
        if (name == null ? getActiveProfileName(this) != null : !name.equals(getActiveProfileName(this))) {
            setActiveProfileName(name);
        }
        if (previous != ProfileUsers.UNKNOWN) {
            clearScreenTimeLock();
            updateScreenTimeLock("profile switch");
            retryPendingBounce();
        }
    }

    private void scheduleProfileUserRechecks() {
        mProfileUserRechecks = 3;
        mIdleHandler.removeCallbacks(mProfileUserRecheck);
        mIdleHandler.postDelayed(mProfileUserRecheck, PROFILE_USER_RECHECK_MS);
    }

    /** Pairs a switch in the profile users with the chooser pick that made it, whichever came first. */
    private void learnProfileUserName() {
        long now = SystemClock.elapsedRealtime();
        if (mLastPick == null || mSwitchedSerial == ProfileUsers.UNKNOWN
                || now - mLastPickAt > PROFILE_CLICK_WINDOW_MS || now - mSwitchedAt > PROFILE_CLICK_WINDOW_MS) {
            return;
        }
        String existing = ProfileUsers.getName(this, mSwitchedSerial);
        long owner = ProfileUsers.serialOf(this, mLastPick);
        if (!mLastPickClicked && owner != ProfileUsers.UNKNOWN && owner != mSwitchedSerial) {
            // A guess naming a profile already known to be another serial
            android.util.Log.i(PROFILE_TAG, "Not naming serial " + mSwitchedSerial + " " + mLastPick
                    + ": that's serial " + owner);
        } else if (existing == null || mLastPickClicked && !existing.equals(mLastPick)) {
            nameSerial(mSwitchedSerial, mLastPick, "pick");
        } else if (!existing.equals(mLastPick)) {
            // Only a guess from the last focused tile: the name learned for this serial wins
            android.util.Log.i(PROFILE_TAG, "Serial " + mSwitchedSerial + " stays " + existing);
        }
        mLastPick = null;
        mSwitchedSerial = ProfileUsers.UNKNOWN;
    }

    /** The chooser opened on the current profile: that's who the running profile user is. */
    private void onChooserOpenedOn(String label) {
        android.util.Log.i(PROFILE_TAG, "Chooser opened on " + label);
        checkProfileUser("chooser opened");
        // Not mid-switch, when the running user may not be the one the chooser shows yet
        if (mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN
                && !label.equals(ProfileUsers.getName(this, mActiveSerial))) {
            nameSerial(mActiveSerial, label, "chooser focus");
        }
    }

    // Once the chooser has laid out (and its focus animation settled): which tile is the current account, and
    // photos for profiles that have none yet or weren't checked today.
    private static final long CHOOSER_READ_DELAY_MS = 1_200;
    private final Runnable mReadChooser = this::readChooser;

    private void readChooser() {
        android.view.accessibility.AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !mChooserOnScreen
                || !GOOGLE_TV_PACKAGE.contentEquals(root.getPackageName() != null ? root.getPackageName() : "")) {
            android.util.Log.i(PROFILE_TAG, "Chooser not readable (" + (root == null ? "no window" : root.getPackageName())
                    + ", on screen " + mChooserOnScreen + ")");
            return;
        }
        java.util.List<String> names = new java.util.ArrayList<>();
        java.util.List<android.graphics.Rect> photos = new java.util.ArrayList<>();
        collectChooserTiles(root, names, photos, 0);
        java.util.Map<String, android.graphics.Rect> due = new java.util.LinkedHashMap<>();
        for (int i = 0; i < names.size(); i++) {
            if (ProfileAvatars.isDue(this, names.get(i))) due.put(names.get(i), photos.get(i));
        }
        android.util.Log.i(PROFILE_TAG, "Chooser shows " + names + "; photos due: " + due.keySet());
        android.os.PowerManager power = (android.os.PowerManager) getSystemService(Context.POWER_SERVICE);
        if (due.isEmpty() || android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R
                || power == null || !power.isInteractive()) {
            return;
        }
        takeScreenshot(android.view.Display.DEFAULT_DISPLAY, getMainExecutor(), new TakeScreenshotCallback() {
            @Override
            public void onSuccess(ScreenshotResult result) {
                final android.hardware.HardwareBuffer buffer = result.getHardwareBuffer();
                // Cropping and saving off the main thread; the full screenshot is never kept.
                new Thread(() -> {
                    android.graphics.Bitmap hardware = android.graphics.Bitmap.wrapHardwareBuffer(buffer, result.getColorSpace());
                    android.graphics.Bitmap screen = hardware != null
                            ? hardware.copy(android.graphics.Bitmap.Config.ARGB_8888, false) : null;
                    if (hardware != null) hardware.recycle();
                    buffer.close();
                    if (screen == null) return;
                    boolean saved = false;
                    for (java.util.Map.Entry<String, android.graphics.Rect> photo : due.entrySet()) {
                        int outcome = ProfileAvatars.save(LauncherAccessibilityService.this, photo.getKey(), screen,
                                photo.getValue());
                        if (outcome == ProfileAvatars.SAVED) {
                            android.util.Log.i(PROFILE_TAG, "New photo for " + photo.getKey());
                            saved = true;
                        } else if (outcome == ProfileAvatars.FAILED) {
                            android.util.Log.i(PROFILE_TAG, "No usable photo for " + photo.getKey());
                        }
                    }
                    screen.recycle();
                    if (saved) MainActivity.notifyProfileChanged();
                }, "ProfilePhotos").start();
            }

            @Override
            public void onFailure(int errorCode) {
                android.util.Log.i(PROFILE_TAG, "Profile photo screenshot failed: " + errorCode);
            }
        });
    }

    /** The first ImageView in a node's subtree. */
    private static android.view.accessibility.AccessibilityNodeInfo findImage(
            android.view.accessibility.AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 6) return null;
        if ("android.widget.ImageView".contentEquals(node.getClassName() != null ? node.getClassName() : "")) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            android.view.accessibility.AccessibilityNodeInfo image = findImage(node.getChild(i), depth + 1);
            if (image != null) return image;
        }
        return null;
    }

    /**
     * The chooser's profile tiles: a focusable LinearLayout holding the photo (an ImageView, a few frames down)
     * and the name (TextView), "Add account" aside. The current account's tile says so in its description ("... select to
     * continue with current account"), which names the running profile user without relying on focus.
     */
    private void collectChooserTiles(android.view.accessibility.AccessibilityNodeInfo node, java.util.List<String> names,
            java.util.List<android.graphics.Rect> photos, int depth) {
        if (node == null || depth > 20) return;
        if ("android.widget.LinearLayout".contentEquals(node.getClassName() != null ? node.getClassName() : "")
                && node.isFocusable()) {
            String name = null;
            android.graphics.Rect photo = null;
            for (int i = 0; i < node.getChildCount(); i++) {
                android.view.accessibility.AccessibilityNodeInfo child = node.getChild(i);
                if (child == null || child.getClassName() == null) continue;
                if ("android.widget.TextView".contentEquals(child.getClassName()) && child.getText() != null) {
                    name = child.getText().toString().trim();
                } else if (photo == null) {
                    android.view.accessibility.AccessibilityNodeInfo image = findImage(child, 0);
                    if (image != null) {
                        photo = new android.graphics.Rect();
                        image.getBoundsInScreen(photo);
                    }
                }
            }
            if (name != null && !name.isEmpty() && photo != null
                    && !name.toLowerCase(java.util.Locale.ROOT).contains("account")) {
                names.add(name);
                photos.add(photo);
                CharSequence desc = node.getContentDescription();
                if (desc != null && desc.toString().toLowerCase(java.util.Locale.ROOT).contains("current account")
                        && mActiveSerial != ProfileUsers.UNKNOWN && mCandidateSerial == ProfileUsers.UNKNOWN
                        && !name.equals(ProfileUsers.getName(this, mActiveSerial))) {
                    nameSerial(mActiveSerial, name, "chooser's current account");
                }
            }
            return;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            collectChooserTiles(node.getChild(i), names, photos, depth + 1);
        }
    }

    /** Learns a serial's profile name; the active profile takes it on if that's the serial. */
    private void nameSerial(long serial, String name, String how) {
        android.util.Log.i(PROFILE_TAG, "Serial " + serial + " is " + name + " (" + how + ")");
        ProfileUsers.setName(this, serial, name);
        // Pairings saved under the name, before profiles had keys
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
        mLastWindowPackage = packageName;
        mWellbeingInFront = GOOGLE_TV_PACKAGE.equals(packageName) && className.startsWith(GOOGLE_TV_WELLBEING_PREFIX);
        // The chooser stays "open" while Google TV lays its account check / PIN screens over it; it's over once
        // Google TV's home or any other app comes up.
        boolean wasOnScreen = mChooserOnScreen;
        if (GOOGLE_TV_PACKAGE.equals(packageName) && isChooser(className)) {
            mChooserOnScreen = true;
        } else if (GOOGLE_TV_HOME_ACTIVITY.equals(className)
                || (!GOOGLE_TV_PACKAGE.equals(packageName) && !"com.android.systemui".equals(packageName)
                    && !"android".equals(packageName) && !packageName.equals(getPackageName()))) {
            // Not Hearth's own windows: Hearth reports window changes as it goes behind the chooser.
            // (Coming back to Hearth without a pick is handled below: it cancels the pending pick.)
            mChooserOnScreen = false;
        }
        if (wasOnScreen != mChooserOnScreen) {
            android.util.Log.i(PROFILE_TAG, "chooser " + (mChooserOnScreen ? "open" : "closed") + " (" + packageName
                    + "/" + className + ")");
            if (!mChooserOnScreen) checkProfileUser("chooser closed");
        }

        if (GOOGLE_TV_PACKAGE.equals(packageName)) {
            boolean wellbeing = className.startsWith(GOOGLE_TV_WELLBEING_PREFIX);
            if (wellbeing) {
                mWellbeingSeenAt = SystemClock.elapsedRealtime();
                setScreenTimeLock();
            }
            reportScreenTimeText(className, event, wellbeing);
            if (isChooser(className)) {
                mIdleHandler.removeCallbacks(mReadChooser);
                mIdleHandler.postDelayed(mReadChooser, CHOOSER_READ_DELAY_MS);
                long now = SystemClock.elapsedRealtime();
                if (mFirstFocusLabel != null && now - mFirstFocusAt < CHOOSER_INITIAL_FOCUS_MS) {
                    // Initial focus was reported before the window change
                    onChooserOpenedOn(mFirstFocusLabel);
                    mChooserOpenedAt = 0;
                } else {
                    mChooserOpenedAt = now;
                }
                mFirstFocusLabel = null;
            }

            // Google's own setup flows (a new kids profile's onboarding, sign-in, PIN creation) open Google TV's
            // home behind themselves; Hearth stays out of the way until they're done.
            if (isGoogleSetupScreen(className)) {
                mGoogleSetupUntil = SystemClock.elapsedRealtime() + GOOGLE_SETUP_HOLD_MS;
                android.util.Log.i(PROFILE_TAG, "Google TV setup in progress: " + className);
            }
            if (GOOGLE_TV_HOME_ACTIVITY.equals(className)) {
                // A new profile's home: the last one's screen time no longer applies (its own comes up next)
                if (commitPendingProfile()) clearScreenTimeLock();
                checkProfileUser("Google TV home");
                updateScreenTimeLock("Google TV home");
                mGoogleTvScreenInFront = false;
                // Google TV opens its own home by component after a profile switch, on Back from apps, etc.,
                // ignoring the default home app. Bring the launcher back whenever that's allowed.
                if (SystemClock.elapsedRealtime() < mGoogleSetupUntil) {
                    android.util.Log.i(PROFILE_TAG, "Not taking over: Google TV setup in progress");
                } else if (canTakeOver() && ProfileUsers.isKids(this) && !mScreenTimeKnown) {
                    // A kids profile whose screen time the apps can't tell: Google TV opens its time up / bedtime
                    // screen from its home a moment after the home itself, and covering the home first would hide
                    // it (Hearth, the home app, can't be suspended). Take over only if the home is still in front.
                    mIdleHandler.removeCallbacks(mKidsHomeTakeOver);
                    mIdleHandler.postDelayed(mKidsHomeTakeOver, KIDS_HOME_GRACE_MS);
                } else if (canTakeOver()) {
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
            mLastChooserFocus = null;
        }
        if (mHaStatus != null && (packageName.equals(getPackageName()) || isLaunchableApp(packageName))) {
            mHaStatus.setForegroundPackage(packageName);
        }
        if (!packageName.equals(getPackageName()) && isLaunchableApp(packageName)) {
            rememberAppUser(this, packageName);
        }

        // The screen time lock only clears on a profile switch: failing safe beats covering a time up screen.
        if (packageName.equals(getPackageName()) || isLaunchableApp(packageName)) {
            mGoogleTvScreenInFront = false;
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
            mIdleHandler.removeCallbacks(mReadScreenTime);
            mScreenTimeClass = className;
            mIdleHandler.postDelayed(mReadScreenTime, SCREEN_TIME_READ_DELAY_MS);
        }
    }

    private static final long KIDS_HOME_GRACE_MS = 1_500;
    private String mLastWindowPackage;
    private final Runnable mKidsHomeTakeOver = () -> {
        // Not if Google TV put a screen of its own up (time up, PIN...) or the kid opened an app meanwhile
        if (canTakeOver() && !mGoogleTvScreenInFront && GOOGLE_TV_PACKAGE.equals(mLastWindowPackage)) {
            openLauncher();
        }
    };

    private static final long SCREEN_TIME_READ_DELAY_MS = 700;
    private String mScreenTimeClass;
    private final Runnable mReadScreenTime = this::readScreenTime;

    private void readScreenTime() {
        if (mHaStatus == null) return;
        android.view.accessibility.AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !GOOGLE_TV_PACKAGE.contentEquals(root.getPackageName() != null ? root.getPackageName() : "")) {
            return;
        }
        java.util.List<CharSequence> texts = new java.util.ArrayList<>();
        collectTexts(root, texts, 0);
        if (!texts.isEmpty()) mHaStatus.setScreenTime(ScreenTimeScreen.parse(mScreenTimeClass, texts));
    }

    /** The visible text views of a window, in screen order (button labels are content descriptions, so left out). */
    private static void collectTexts(android.view.accessibility.AccessibilityNodeInfo node, java.util.List<CharSequence> out,
            int depth) {
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
        if (label.isEmpty() || !"android.widget.LinearLayout".contentEquals(event.getClassName() != null ? event.getClassName() : "")) return;
        if (label.toLowerCase(java.util.Locale.ROOT).contains("account")) return;

        long now = SystemClock.elapsedRealtime();
        if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_FOCUSED) {
            // OK picks the focused tile, and Google TV doesn't always report the click: remember the last one.
            if (mChooserOnScreen) {
                mLastChooserFocus = label;
                mLastChooserFocusAt = now;
            }
            // The chooser opens with the current profile focused; later focus moves are just browsing.
            if (mChooserOpenedAt != 0 && now - mChooserOpenedAt < CHOOSER_INITIAL_FOCUS_MS) {
                mChooserOpenedAt = 0;
                onChooserOpenedOn(label);
            } else {
                mFirstFocusLabel = label;
                mFirstFocusAt = now;
            }
        } else if (event.getEventType() == AccessibilityEvent.TYPE_VIEW_CLICKED && mChooserOnScreen) {
            // Only clicks in the chooser: Google TV's other screens (its keyboard, menus) click LinearLayouts too.
            android.util.Log.i(PROFILE_TAG, "Picked " + label);
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

    // When Google TV last showed a time up / bedtime screen; it blocks the apps a moment around that, so the apps'
    // state doesn't overrule the screen for a while.
    private long mWellbeingSeenAt = 0;
    /** Google TV's time up / bedtime screen is the window in front: never lift the lock under it. */
    private boolean mWellbeingInFront = false;
    private static final long WELLBEING_TRUST_MS = 15_000;
    /** The apps' state settled screen time the last time it was checked (see ProfileUsers.isScreenTimeUp). */
    private boolean mScreenTimeKnown = false;

    /**
     * Screen time from the apps: in a kids profile Google TV blocks even the approved apps while time is up, and
     * unblocks them when it isn't (bedtime over, bonus time), so the lock follows that, seen or not. When the apps
     * can't tell, Google TV's own screens decide as before.
     */
    private void updateScreenTimeLock(String why) {
        if (mActiveSerial == ProfileUsers.UNKNOWN || mCandidateSerial != ProfileUsers.UNKNOWN) return;
        Boolean up = ProfileUsers.isScreenTimeUp(this, mActiveSerial);
        mScreenTimeKnown = up != null;
        if (up == null || up == mScreenTimeLock) return;
        if (up) {
            android.util.Log.i(PROFILE_TAG, "Screen time is up: the approved apps are blocked (" + why + ")");
            setScreenTimeLock();
        } else if (!mWellbeingInFront && SystemClock.elapsedRealtime() - mWellbeingSeenAt > WELLBEING_TRUST_MS) {
            android.util.Log.i(PROFILE_TAG, "Screen time is over: the approved apps are unblocked (" + why + ")");
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
            android.util.Log.i(PROFILE_TAG, "No click seen; using the last focused tile: " + chosen);
        }
        if (chosen != null) {
            android.util.Log.i(PROFILE_TAG, "Pick settled: " + chosen);
            // Picking the profile that's already on (or backing out of the chooser) starts no profile user
            if (chosen.equals(ProfileUsers.getName(this, mActiveSerial)) && mCandidateSerial == ProfileUsers.UNKNOWN) {
                chosen = null;
            }
            mLastPick = chosen;
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

    private static final String APP_USERS_PREFS = "ltv_app_last_profile";

    /** Records that the active Google TV profile (its key) is using this app (for Continue Watching ownership). */
    private static void rememberAppUser(Context context, String packageName) {
        String profile = getActiveProfileKey(context);
        if (profile == null) return;
        SharedPreferences prefs = context.getSharedPreferences(APP_USERS_PREFS, MODE_PRIVATE);
        if (!profile.equals(prefs.getString(packageName, null))) prefs.edit().putString(packageName, profile).apply();
    }

    /** The Google TV profile (key; a name for apps last used before keys) that last had this app in front, or null. */
    static String getAppLastProfile(Context context, String packageName) {
        return context.getSharedPreferences(APP_USERS_PREFS, MODE_PRIVATE).getString(packageName, null);
    }

    static String getActiveProfileName(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getString(PROFILE_NAME_KEY, null);
    }

    /** The active profile's lasting key ({@link ProfileUsers#key}), known even before its name; null until read. */
    static String getActiveProfileKey(Context context) {
        return context.getSharedPreferences(PROFILE_PREFS, MODE_PRIVATE).getString(PROFILE_KEY_KEY, null);
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
            // In case a switch broadcast was missed
            checkProfileUser("periodic check");
            updateScreenTimeLock("periodic check");
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
            android.widget.Toast.makeText(this, "No activity: going to sleep in 1 minute. Press any button to stay on.",
                    android.widget.Toast.LENGTH_LONG).show();
        }
    }

    /**
     * An app reports playing through its media session (video apps often don't play on the music stream, which
     * is all isMusicActive sees). Needs Hearth's notification access; false without it.
     */
    private boolean isMediaPlaying() {
        android.media.session.MediaSessionManager sessions =
                (android.media.session.MediaSessionManager) getSystemService(Context.MEDIA_SESSION_SERVICE);
        if (sessions == null) return false;
        try {
            for (android.media.session.MediaController controller : sessions.getActiveSessions(
                    new android.content.ComponentName(this, LauncherNotificationListenerService.class))) {
                android.media.session.PlaybackState state = controller.getPlaybackState();
                if (state != null && state.getState() == android.media.session.PlaybackState.STATE_PLAYING) return true;
            }
        } catch (SecurityException e) {
            return false;
        }
        return false;
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
        // Google TV can open its screens (a kids profile's PIN screen, the chooser) behind Hearth; with Hearth in
        // front none of them is showing, so Home stays with Hearth instead of waking them.
        if (MainActivity.isInFront()) mGoogleTvScreenInFront = false;
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME && event.getAction() == KeyEvent.ACTION_DOWN) {
            android.util.Log.i("HearthHome", "Home: screenTimeLock=" + mScreenTimeLock + " suspended=" + isSuspended(this)
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

    private boolean isLaunchableApp(String packageName) {
        PackageManager pm = getPackageManager();
        return pm.getLeanbackLaunchIntentForPackage(packageName) != null || pm.getLaunchIntentForPackage(packageName) != null;
    }

    private void openLauncher() {
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
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
