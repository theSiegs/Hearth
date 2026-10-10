package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.UserHandle;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * "Profile Pairing": when Hearth opens a streaming app, picks the app profile paired with the active Hearth profile
 * on the app's "Who's watching?" screen, behind a cover card ("Opening Netflix as Alex…").
 *
 * Dormant (no events) until Hearth opens a supported app. For that launch it reads the picker the way each app
 * allows: Disney+ and Paramount+ label their tiles; Apple TV and HBO Max only describe their picker to a screen
 * reader, so the service briefly declares spoken feedback (HBO Max also needs isAccessibilityTool, set in the
 * config); Netflix only speaks its picker, through the default text-to-speech engine, which Hearth's silent
 * {@link HearthVoiceService} must be. It then clicks the tile, or moves with the D-pad until the focused name is
 * the right one and presses OK.
 */
public class ProfilePairingService extends AccessibilityService {
    static final String TAG = "HearthPairing";
    private static final long WAIT_FOR_PICKER_MS = 25_000;
    /** The longest Hearth waits through a first sign-in for the picker. */
    private static final long WAIT_THROUGH_SIGN_IN_MS = 5 * 60_000;
    private static final long PICK_TIMEOUT_MS = 15_000;
    private static final long STEP_TIMEOUT_MS = 2_500;
    private static final long SCAN_DELAY_MS = 300;
    private static final long CLICK_CHECK_MS = 1_500;
    private static final long NAME_WAIT_MS = 600;
    private static final long COVER_AFTER_PICK_MS = 1_500;
    private static final long IDLE_AFTER_MS = 3_000;
    private static final long[] MAX_PROBES_MS = {5_000, 9_000};
    private static final int MAX_STEPS = 16;
    private static final int MAX_NODES = 800;
    private static final long NO_MATCH_MESSAGE_MS = 2_000;
    private static final long BANNER_MS = 8_000;

    /** How a launch ended: a profile was picked; the picker is left to the user; or nothing to tell them. */
    private static final int PICKED = 0;
    private static final int NO_MATCH = 1;
    private static final int QUIET = 2;

    private static final Pattern NETFLIX_COUNT = Pattern.compile("(?i)^(.*?)[,.]?\\s*(\\d+) of (\\d+) profiles?");
    private static final Pattern MAX_ITEM = Pattern.compile("(?i)^\\s*(.+?)\\s+Button\\b[,.]?\\s*(\\d+)\\s+of\\s+(\\d+)");
    private static final Pattern DISNEY_TILE = Pattern.compile("(?i)^Access (.+)'s profile$");

    private static volatile ProfilePairingService sInstance;
    /** The app whose launch Profile Pairing is handling right now, or null. Read from Hearth voice's thread. */
    private static volatile String sListeningTo;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private Session mSession;
    private View mCover;
    private TextView mCoverTitle;
    private View mBanner;
    /** Typing a profile PIN after a pick (see PinEntryMachine), or null. */
    private PinRun mPin;
    private View mPinPopup;
    private static final long PIN_SCREEN_WAIT_MS = 6_000;
    /** Long enough for a keypad driven one D-pad move at a time (Netflix, HBO Max). */
    private static final long PIN_OVERALL_MS = 40_000;
    private static final long PIN_OUTCOME_POLL_MS = 400;
    /** What the launched app said lately (speech and announcements), replayed to a PIN recipe as it starts. */
    private static final long RECENT_SPEECH_MS = 15_000;
    private final java.util.ArrayDeque<Object[]> mRecentSpeech = new java.util.ArrayDeque<>();
    private static final long PIN_MESSAGE_MS = 3_500;
    private static final int PIN_BREAKS_BEFORE_PAUSE = 3;

    /** One app launch. Main thread only. */
    private static final class Session {
        final String pkg;
        /** The Google TV profile's key (its choices are saved under it) and name (to match and to show). */
        final String key;
        final String hearthProfile;
        /** A kids profile: name matches must be close (see ProfilePairing.choose). */
        boolean kids;
        boolean pickerSeen;
        boolean signingIn;
        final long startedAt = SystemClock.elapsedRealtime();
        // Apps read through nodes
        boolean clickTried;
        boolean checkingClick;
        boolean scanScheduled;
        // Apps read one focused name at a time (Netflix, HBO Max, Apple TV without a working click)
        final Map<String, Integer> names = new LinkedHashMap<>();
        String current;
        int direction = 1;
        int reversals;
        int steps;
        boolean waitingForStep;
        String pendingName;
        int probes;
        boolean appShown;
        String pickedName;
        /** Apple TV: the tile its last accessibility-focus event named, or null while waiting for one. */
        String highlighted;
        boolean reachedEnd;

        Session(String pkg, String key, String hearthProfile) {
            this.pkg = pkg;
            this.key = key;
            this.hearthProfile = hearthProfile;
        }
    }

    static boolean isRunning() {
        return sInstance != null;
    }

    /**
     * Whether Profile Pairing wants to hear this app right now. Only then does Hearth voice keep the app's speech
     * to itself; otherwise it speaks normally, so a screen reader user still hears every app.
     */
    static boolean isListeningTo(String packageName) {
        return packageName != null && packageName.equals(sListeningTo);
    }

    /** Whether Hearth's voice is the default text-to-speech engine (Netflix's picker can only be heard). */
    static boolean isVoiceDefault(Context context) {
        return context.getPackageName().equals(
                Settings.Secure.getString(context.getContentResolver(), "tts_default_synth"));
    }

    /** Called by Hearth just before it opens {@code packageName}. */
    static void onAppLaunching(Context context, String packageName) {
        ProfilePairingService service = sInstance;
        if (packageName == null || !ProfilePairing.supports(packageName)) return;
        if (service == null) {
            Log.i(TAG, packageName + " skipped: Profile Pairing isn't running");
            return;
        }
        if (!ProfilePairing.isAppEnabled(context, packageName)) {
            Log.i(TAG, packageName + " skipped: turned off for this app");
            return;
        }
        String key = LauncherAccessibilityService.getActiveProfileKey(context);
        if (key == null) {
            Log.i(TAG, packageName + " skipped: the Google TV profile isn't known");
            return;
        }
        ProfilePairing.rememberHearthProfile(context, key, null);
        String mode = ProfilePairing.getMode(context, packageName, key);
        String name = LauncherAccessibilityService.getActiveProfileName(context);
        if (ProfilePairing.MODE_PICKER.equals(mode)) {
            Log.i(TAG, packageName + " skipped: " + key + " always gets the picker");
            return;
        }
        // Without a name only a chosen app profile can be picked (matching needs the name)
        if ((name == null || name.isEmpty()) && !ProfilePairing.MODE_PROFILE.equals(mode)) {
            Log.i(TAG, packageName + " skipped: " + key + " isn't named yet");
            return;
        }
        String hearthProfile = name != null && !name.isEmpty() ? name : ProfileUsers.displayName(context, key);
        // Netflix speaks through its own user's engine: another profile's agent says whether that's Hearth's voice
        UserHandle profileUser = ProfileApps.activeProfileUser(context);
        boolean voice = profileUser != null
                ? AgentHub.isVoiceDefault(ProfileUsers.settledSerial(context)) : isVoiceDefault(context);
        if (ProfilePairing.NETFLIX.equals(packageName) && !voice) {
            Log.i(TAG, "Netflix skipped: Hearth's voice isn't the text-to-speech engine");
            return;
        }
        Runnable begin = () -> service.begin(packageName, key, hearthProfile);
        if (Looper.myLooper() == Looper.getMainLooper()) begin.run(); else service.mHandler.post(begin);
    }

    /** Text an app asked Hearth's voice to say (worker thread). */
    static void onSpeech(String callerPackage, String text) {
        ProfilePairingService service = sInstance;
        if (service == null || text == null) return;
        service.mHandler.post(() -> service.handleSpeech(callerPackage, text));
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        sInstance = this;
        setMode(false, false);
        getContentResolver().registerContentObserver(Settings.Global.getUriFor(RESEARCH_SETTING), false,
                mResearchObserver);
        applyResearch();
        // Just turned on from the setup flow: back to it
        SetupReturn.onConnected(this, SetupReturn.PROFILE_PAIRING);
    }

    // ---- Research mode, for writing PIN recipes (adb only) ----
    // `adb shell settings put global hearth_pin_research <package>` makes the service listen to that app, in
    // screen-reader mode where the app needs it, and log what it announces and focuses (tag HearthResearch), so a
    // person driving the remote by adb can see where the focus is. `settings delete global hearth_pin_research` ends
    // it. Off unless set; it logs keypad labels, so it's for test profiles and throwaway PINs only.
    private static final String RESEARCH_SETTING = "hearth_pin_research";
    private static final String RESEARCH_TAG = "HearthResearch";
    private String mResearch;
    private final android.database.ContentObserver mResearchObserver =
            new android.database.ContentObserver(new Handler(Looper.getMainLooper())) {
                @Override
                public void onChange(boolean selfChange) {
                    applyResearch();
                }
            };

    private void applyResearch() {
        String pkg = Settings.Global.getString(getContentResolver(), RESEARCH_SETTING);
        if (pkg != null && pkg.isEmpty()) pkg = null;
        mResearch = pkg;
        Log.i(RESEARCH_TAG, pkg == null ? "off" : "listening to " + pkg);
        if (pkg != null) {
            // Screen-reader mode for every app here: several (Netflix, Hulu) describe their screens only then
            setMode(true, true);
            setListeningTo(pkg);
        } else {
            mHandler.post(mGoIdle);
        }
    }

    /**
     * Keypad keys and typed digits never reach the log, even in research mode: a person may type a real PIN while it
     * runs. Every digit, figure or English word, becomes "#" (so "Enter a 4 digit code" reads "Enter a # digit
     * code"; the shape stays).
     */
    private static String redactDigits(String text) {
        if (text == null) return null;
        return text.replaceAll("[0-9\u0660-\u0669\u06F0-\u06F9\u0966-\u096F\uFF10-\uFF19]", "#")
                .replaceAll("(?i)\\b(zero|one|two|three|four|five|six|seven|eight|nine)\\b", "#");
    }

    private void logResearch(AccessibilityEvent event) {
        StringBuilder line = new StringBuilder(AccessibilityEvent.eventTypeToString(event.getEventType()));
        line.append(" class=").append(event.getClassName());
        if (!event.getText().isEmpty()) line.append(" text=").append(redactDigits(event.getText().toString()));
        if (event.getContentDescription() != null) {
            line.append(" desc=").append(redactDigits(event.getContentDescription().toString()));
        }
        AccessibilityNodeInfo source = event.getSource();
        if (source != null) {
            line.append(" src[id=").append(source.getViewIdResourceName())
                    .append(" text=").append(redactDigits(String.valueOf(source.getText())))
                    .append(" desc=").append(redactDigits(String.valueOf(source.getContentDescription())))
                    .append(" focused=").append(source.isFocused()).append(']');
        }
        Log.i(RESEARCH_TAG, line.toString());
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) sInstance = null;
        getContentResolver().unregisterContentObserver(mResearchObserver);
        setListeningTo(null);
        mHandler.removeCallbacksAndMessages(null);
        hideCover();
        hideBanner();
        hidePinPopup();
        if (mPin != null) java.util.Arrays.fill(mPin.pin, '\0');
        mPin = null;
        super.onDestroy();
    }

    @Override
    public void onInterrupt() {
    }

    static boolean needsScreenReaderMode(String pkg) {
        return ProfilePairing.NETFLIX.equals(pkg) || ProfilePairing.APPLE_TV.equals(pkg)
                || ProfilePairing.MAX.equals(pkg) || ProfilePairing.HULU.equals(pkg);
    }

    /**
     * Listens to the app only during a launch. Screen-reader mode (spoken feedback) makes Netflix, Apple TV and HBO
     * Max describe their pickers; it's on only for those launches so apps aren't otherwise in screen-reader mode.
     */
    private void setMode(boolean listening, boolean screenReader) {
        AccessibilityServiceInfo info = getServiceInfo();
        if (info == null) return;
        info.eventTypes = listening ? AccessibilityEvent.TYPES_ALL_MASK : 0;
        info.feedbackType = screenReader
                ? AccessibilityServiceInfo.FEEDBACK_SPOKEN : AccessibilityServiceInfo.FEEDBACK_GENERIC;
        int readerFlags = AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE;
        int listenFlags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        info.flags = (listening ? listenFlags : 0) | (screenReader ? readerFlags : 0);
        info.notificationTimeout = 0;
        setServiceInfo(info);
    }

    private final Runnable mGoIdle = () -> {
        if (mSession != null || mPin != null || mResearch != null) return;
        setMode(false, false);
        // The app stops speaking once screen-reader mode is off; until then Hearth voice keeps it quiet.
        setListeningTo(null);
    };

    /** Which app Hearth's voice hands to Profile Pairing: here, and in another profile's user through its agent. */
    private static void setListeningTo(String pkg) {
        sListeningTo = pkg;
        AgentHub.setListening(pkg);
    }

    private final Runnable mTimeout = () -> finish(NO_MATCH, "timed out");

    private void begin(String pkg, String key, String hearthProfile) {
        if (mSession != null) finish(QUIET, "replaced");
        mHandler.removeCallbacks(mGoIdle);
        hideCover();
        mSession = new Session(pkg, key, hearthProfile);
        mRecentSpeech.clear();
        mSession.kids = ProfileUsers.isKids(this);
        setListeningTo(pkg);
        setMode(true, needsScreenReaderMode(pkg));
        mHandler.postDelayed(mTimeout, WAIT_FOR_PICKER_MS);
        Log.i(TAG, "Watching " + pkg + " for " + hearthProfile);
    }

    private void finish(int outcome, String why) {
        Session s = mSession;
        if (s == null) return;
        mSession = null;
        mHandler.removeCallbacks(mTimeout);
        mHandler.removeCallbacks(mStepTimeout);
        mHandler.removeCallbacks(mScan);
        mHandler.removeCallbacks(mDeliverPending);
        mHandler.removeCallbacks(mMaxProbe);
        Log.i(TAG, (outcome == PICKED ? "Picked" : "Stopped") + " in " + s.pkg + ": " + why);
        if (outcome == PICKED) {
            mHandler.postDelayed(() -> {
                // A PIN-protected profile: the cover stays up while Hearth types the saved PIN behind it
                if (startPinEntry(s)) return;
                hideCover();
                announceMatch(s);
            }, COVER_AFTER_PICK_MS);
        } else if (outcome == NO_MATCH && s.pickerSeen && mCoverTitle != null) {
            // Say why the picker is staying up, then get out of the way.
            mCoverTitle.setText(getString(R.string.profile_pairing_no_match, s.hearthProfile));
            mHandler.postDelayed(this::hideCover, NO_MATCH_MESSAGE_MS);
        } else {
            hideCover();
        }
        mHandler.postDelayed(mGoIdle, IDLE_AFTER_MS);
    }

    private void pickerFound() {
        Session s = mSession;
        if (s == null || s.pickerSeen) return;
        s.pickerSeen = true;
        mHandler.removeCallbacks(mTimeout);
        mHandler.removeCallbacks(mMaxProbe);
        mHandler.postDelayed(mTimeout, PICK_TIMEOUT_MS);
        showCover(s);
    }

    // ---- Events ----

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() == AccessibilityEvent.TYPE_ANNOUNCEMENT && event.getPackageName() != null
                && !event.getText().isEmpty()) {
            heard(event.getPackageName().toString(), android.text.TextUtils.join(" ", event.getText()));
        }
        if (mResearch != null && mResearch.contentEquals(event.getPackageName() != null ? event.getPackageName() : "")) {
            logResearch(event);
        }
        if (mPin != null) onPinEvent(event);
        Session s = mSession;
        if (s == null) return;
        CharSequence eventPkg = event.getPackageName();
        int type = event.getEventType();
        if (eventPkg == null || !s.pkg.contentEquals(eventPkg)) {
            // Another app came to the front once the picker was up: the user went elsewhere.
            if (s.pickerSeen && type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && eventPkg != null
                    && !eventPkg.toString().startsWith(getPackageName())
                    && !"com.android.systemui".contentEquals(eventPkg)) {
                finish(QUIET, "left for " + eventPkg);
            }
            return;
        }
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && !s.appShown) {
            s.appShown = true;
            if (ProfilePairing.MAX.equals(s.pkg)) scheduleMaxProbe(s);
        }
        if (ProfilePairing.APPLE_TV.equals(s.pkg) && type == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) {
            // The highlighted profile tile: a Button whose description ends with the name ("Who's Watching?, Select
            // an account or sign in, Alex" for the first tile, just "Sam" for the others).
            AccessibilityNodeInfo source = event.getSource();
            CharSequence desc = source != null ? source.getContentDescription() : null;
            if (source != null && desc != null && source.getClassName() != null
                    && source.getClassName().toString().endsWith("Button")) {
                String[] parts = desc.toString().split(",\\s*");
                s.highlighted = parts[parts.length - 1].trim();
                Log.i(TAG, "Apple TV highlights " + s.highlighted);
            }
        }
        switch (s.pkg) {
            case ProfilePairing.MAX:
                if (type == AccessibilityEvent.TYPE_ANNOUNCEMENT) {
                    String text = eventText(event);
                    if (!text.isEmpty()) handleMaxText(text);
                }
                break;
            case ProfilePairing.NETFLIX:
                break;
            default:
                if (!s.scanScheduled && !s.checkingClick) {
                    s.scanScheduled = true;
                    mHandler.postDelayed(mScan, SCAN_DELAY_MS);
                }
        }
    }

    private static String eventText(AccessibilityEvent event) {
        StringBuilder out = new StringBuilder();
        for (CharSequence t : event.getText()) {
            if (t != null) out.append(t).append(' ');
        }
        if (out.length() == 0 && event.getContentDescription() != null) out.append(event.getContentDescription());
        return out.toString().trim();
    }

    // ---- Netflix: hears the picker through Hearth's voice ----

    private void handleSpeech(String callerPackage, String text) {
        if (mResearch != null && mResearch.equals(callerPackage)) Log.i(RESEARCH_TAG, "speech: " + redactDigits(text));
        heard(callerPackage, text);
        Session s = mSession;
        if (s == null || !ProfilePairing.NETFLIX.equals(s.pkg) || !s.pkg.equals(callerPackage)) return;
        String t = text.trim();
        String lower = t.toLowerCase(Locale.ROOT);
        if (lower.contains("choose a profile") || lower.contains("profile selection")
                || lower.contains("who's watching")) {
            pickerFound();
            return;
        }
        if (!s.pickerSeen && looksLikeSignIn(lower)) {
            stillSigningIn(s);
            return;
        }
        if (!s.pickerSeen || t.isEmpty()) return;
        // Hints and settings Netflix also reads out, not profile names.
        if (lower.startsWith("press ") || lower.startsWith("audio description")) return;
        Matcher count = NETFLIX_COUNT.matcher(t);
        if (count.find()) {
            String name = count.group(1).trim();
            if (name.isEmpty()) name = s.pendingName;
            mHandler.removeCallbacks(mDeliverPending);
            s.pendingName = null;
            if (name != null) {
                onFocusedName(name, Integer.parseInt(count.group(2)), Integer.parseInt(count.group(3)));
            }
            return;
        }
        // A name; its "N of M profiles" usually follows right after.
        s.pendingName = t;
        mHandler.removeCallbacks(mDeliverPending);
        mHandler.postDelayed(mDeliverPending, NAME_WAIT_MS);
    }

    /** What Netflix reads out on its sign-in screens (choosing how, the code or QR page, email and password). */
    private static boolean looksLikeSignIn(String lower) {
        return lower.contains("sign in") || lower.contains("sign-in") || lower.contains("signin")
                || lower.contains("email") || lower.contains("password") || lower.contains("code")
                || lower.contains("use phone") || lower.contains("use remote") || lower.contains("qr")
                || lower.contains("netflix.com/") || lower.contains("verif");
    }

    /**
     * The app is on a sign-in screen: wait for its picker until WAIT_THROUGH_SIGN_IN_MS after the launch instead
     * (a code entered on a phone can take minutes, with the app silent meanwhile).
     */
    private void stillSigningIn(Session s) {
        long left = WAIT_THROUGH_SIGN_IN_MS - (SystemClock.elapsedRealtime() - s.startedAt);
        if (left <= WAIT_FOR_PICKER_MS) return;
        if (!s.signingIn) Log.i(TAG, "Signing in to " + s.pkg + ": waiting for its picker");
        s.signingIn = true;
        mHandler.removeCallbacks(mTimeout);
        mHandler.postDelayed(mTimeout, left);
    }

    private final Runnable mDeliverPending = () -> {
        Session s = mSession;
        if (s == null || s.pendingName == null) return;
        String name = s.pendingName;
        s.pendingName = null;
        onFocusedName(name, -1, -1);
    };

    // ---- HBO Max: announces the focused tile ("Who's Watching?. Alex Button, 1 of 4") ----

    private final Runnable mMaxProbe = () -> {
        Session s = mSession;
        if (s == null || s.pickerSeen) return;
        // Max announces the picker only when focus moves; a Right press shows whether it's up.
        s.probes++;
        Log.i(TAG, "HBO Max: probing for the picker");
        pressKey(1);
        scheduleMaxProbe(s);
    };

    private void scheduleMaxProbe(Session s) {
        if (s.probes < MAX_PROBES_MS.length) {
            long delay = MAX_PROBES_MS[s.probes] - (s.probes == 0 ? 0 : MAX_PROBES_MS[s.probes - 1]);
            mHandler.postDelayed(mMaxProbe, delay);
        }
    }

    private void handleMaxText(String text) {
        Session s = mSession;
        if (s == null) return;
        String rest = text;
        int watching = text.toLowerCase(Locale.ROOT).indexOf("watching?");
        if (watching >= 0) {
            pickerFound();
            rest = text.substring(watching + "watching?".length()).replaceFirst("^[\\s.,]+", "");
        } else if (!s.pickerSeen) {
            if (s.probes > 0) finish(QUIET, "HBO Max opened without its picker");
            return;
        }
        Matcher item = MAX_ITEM.matcher(rest);
        if (!item.find()) return;
        String name = item.group(1).split(",")[0].trim();
        onFocusedName(name, Integer.parseInt(item.group(2)), Integer.parseInt(item.group(3)));
    }

    // ---- Apps read one focused name at a time ----

    private boolean forwardIsDown(Session s) {
        return ProfilePairing.NETFLIX.equals(s.pkg);
    }

    private void pressKey(int direction) {
        Session s = mSession;
        if (s == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return;
        int action;
        if (direction == 0) {
            action = GLOBAL_ACTION_DPAD_CENTER;
        } else if (forwardIsDown(s)) {
            action = direction > 0 ? GLOBAL_ACTION_DPAD_DOWN : GLOBAL_ACTION_DPAD_UP;
        } else {
            action = direction > 0 ? GLOBAL_ACTION_DPAD_RIGHT : GLOBAL_ACTION_DPAD_LEFT;
        }
        performGlobalAction(action);
    }

    private final Runnable mStepTimeout = () -> {
        // No new name after a move: focus was already at the end of the row.
        Session s = mSession;
        if (s == null || !s.waitingForStep) return;
        s.waitingForStep = false;
        reverse(s);
    };

    private void onFocusedName(String name, int index, int count) {
        Session s = mSession;
        if (s == null) return;
        if (!s.pickerSeen) pickerFound();
        mHandler.removeCallbacks(mStepTimeout);
        boolean moved = !name.equals(s.current);
        s.waitingForStep = false;
        s.current = name;
        if (index > 0) s.names.put(name, index);
        boolean complete = count > 0 && s.names.size() >= count;
        if (index > 0) ProfilePairing.rememberNames(this, s.pkg, orderedNames(s), complete);

        Set<String> known = new LinkedHashSet<>(s.names.keySet());
        known.addAll(ProfilePairing.getSeenNames(this, s.pkg));
        String target = ProfilePairing.choose(this, s.pkg, s.key, s.hearthProfile, known, s.kids);
        // Until Hearth has heard the whole list once (for the Profile Pairing menu and nickname matches), walk to
        // the end first, then come back to the right profile.
        Log.i(TAG, "Focused " + name + " (" + index + " of " + count + ")");
        if (count > 0 && index == count) s.reachedEnd = true;
        boolean learning = !complete && count > 0 && ProfilePairing.getSeenNames(this, s.pkg).size() < count
                && !s.reachedEnd && s.reversals == 0;
        if (learning) {
            s.direction = 1;
            step(s);
            return;
        }
        if (target != null && ProfilePairing.normalize(target).equals(ProfilePairing.normalize(name))) {
            pressKey(0);
            s.pickedName = name;
            finish(PICKED, "chose " + name);
            return;
        }
        if (complete && target == null) {
            finish(NO_MATCH, "no profile matches " + s.hearthProfile + " in " + s.names.keySet());
            return;
        }
        // Steer only by positions heard this launch: Netflix's spoken "N of M" doesn't reliably match Up/Down order.
        Integer targetIndex = target != null ? s.names.get(target) : null;
        if (targetIndex != null && index > 0) {
            s.direction = targetIndex > index ? 1 : -1;
        } else if (!moved && s.steps > 0) {
            reverse(s);
            return;
        } else if (count > 0 && index == count && s.direction > 0) {
            s.direction = -1;
            s.reversals++;
        } else if (index == 1 && s.direction < 0) {
            s.direction = 1;
            s.reversals++;
        }
        step(s);
    }

    private void reverse(Session s) {
        s.direction = -s.direction;
        s.reversals++;
        step(s);
    }

    private void step(Session s) {
        if (s.reversals > 2 || ++s.steps > MAX_STEPS) {
            finish(NO_MATCH, "couldn't find the profile for " + s.hearthProfile);
            return;
        }
        s.waitingForStep = true;
        pressKey(s.direction);
        mHandler.postDelayed(mStepTimeout, STEP_TIMEOUT_MS);
    }

    private static List<String> orderedNames(Session s) {
        List<Map.Entry<String, Integer>> entries = new ArrayList<>(s.names.entrySet());
        entries.sort((a, b) -> Integer.compare(a.getValue(), b.getValue()));
        List<String> names = new ArrayList<>();
        for (Map.Entry<String, Integer> e : entries) names.add(e.getKey());
        return names;
    }

    // ---- Disney+, Paramount+, Apple TV: tiles in the node tree ----

    private static final class Tile {
        final String name;
        final AccessibilityNodeInfo node;
        final AccessibilityNodeInfo clickable;

        Tile(String name, AccessibilityNodeInfo node, AccessibilityNodeInfo clickable) {
            this.name = name;
            this.node = node;
            this.clickable = clickable;
        }
    }

    private final Runnable mScan = this::scan;

    private void scan() {
        Session s = mSession;
        if (s == null) return;
        s.scanScheduled = false;
        AccessibilityNodeInfo root = rootOf(s.pkg);
        if (root == null) return;
        List<Tile> tiles = new ArrayList<>();
        boolean[] pickerTitle = new boolean[1];
        collect(s.pkg, root, tiles, pickerTitle, new int[1], 0);
        if (tiles.isEmpty() || (ProfilePairing.APPLE_TV.equals(s.pkg) && !pickerTitle[0])) {
            if (s.checkingClick || s.clickTried) {
                if (s.pickerSeen) finish(PICKED, "picker closed");
            }
            return;
        }
        pickerFound();
        // Screen order (left to right, then top to bottom), so Right/Left moves match the list.
        tiles.sort((a, b) -> {
            Rect ra = new Rect();
            Rect rb = new Rect();
            a.node.getBoundsInScreen(ra);
            b.node.getBoundsInScreen(rb);
            return ra.top / 100 != rb.top / 100 ? Integer.compare(ra.top, rb.top) : Integer.compare(ra.left, rb.left);
        });
        List<String> names = new ArrayList<>();
        for (Tile tile : tiles) names.add(tile.name);
        ProfilePairing.rememberNames(this, s.pkg, names, true);
        String target = ProfilePairing.choose(this, s.pkg, s.key, s.hearthProfile, names, s.kids);
        if (target == null) {
            finish(NO_MATCH, "no profile matches " + s.hearthProfile + " in " + names);
            return;
        }
        int targetIndex = names.indexOf(target);
        // Apple TV opens whichever tile is focused whatever node is clicked, so move focus there instead.
        if (!s.clickTried && !ProfilePairing.APPLE_TV.equals(s.pkg)) {
            s.clickTried = true;
            if (tiles.get(targetIndex).clickable != null
                    && tiles.get(targetIndex).clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                // Done if the picker goes away; otherwise fall back to the D-pad.
                Log.i(TAG, "Clicked " + target + " of " + names);
                s.pickedName = target;
                s.checkingClick = true;
                mHandler.postDelayed(() -> {
                    Session now = mSession;
                    if (now == null) return;
                    now.checkingClick = false;
                    scan();
                }, CLICK_CHECK_MS);
                return;
            }
        }
        int focused = -1;
        if (ProfilePairing.APPLE_TV.equals(s.pkg)) {
            // Apple TV's tiles don't report focus, but its accessibility-focus events name the highlighted tile.
            // Until one arrives after the last press, wait: never press OK on a tile Hearth hasn't seen highlighted.
            if (s.highlighted == null) return;
            for (int i = 0; i < tiles.size() && focused < 0; i++) {
                if (ProfilePairing.normalize(tiles.get(i).name).equals(ProfilePairing.normalize(s.highlighted))) {
                    focused = i;
                }
            }
        } else {
            for (int i = 0; i < tiles.size() && focused < 0; i++) {
                Tile tile = tiles.get(i);
                if (hasFocus(tile.node, 0) || (tile.clickable != null && hasFocus(tile.clickable, 0))) focused = i;
            }
        }
        if (focused == targetIndex) {
            pressKey(0);
            s.pickedName = target;
            finish(PICKED, "chose " + target);
        } else if (focused >= 0 && ++s.steps <= MAX_STEPS) {
            pressKey(targetIndex > focused ? 1 : -1);
            if (ProfilePairing.APPLE_TV.equals(s.pkg)) {
                s.highlighted = null;  // the next focus event says where the highlight landed
                return;
            }
            s.scanScheduled = true;
            mHandler.postDelayed(mScan, SCAN_DELAY_MS * 2);
        } else {
            finish(NO_MATCH, "couldn't move to " + target);
        }
    }

    private AccessibilityNodeInfo rootOf(String pkg) {
        try {
            for (AccessibilityWindowInfo window : getWindows()) {
                AccessibilityNodeInfo root = window.getRoot();
                if (root != null && root.getPackageName() != null && pkg.contentEquals(root.getPackageName())) {
                    return root;
                }
            }
        } catch (Exception ignored) {
        }
        AccessibilityNodeInfo active = getRootInActiveWindow();
        return active != null && active.getPackageName() != null && pkg.contentEquals(active.getPackageName())
                ? active : null;
    }

    private static void collect(String pkg, AccessibilityNodeInfo node, List<Tile> tiles, boolean[] pickerTitle,
                                int[] visited, int depth) {
        if (node == null || depth > 40 || visited[0]++ > MAX_NODES) return;
        CharSequence text = node.getText();
        CharSequence desc = node.getContentDescription();
        String label = text != null ? text.toString().trim() : desc != null ? desc.toString().trim() : "";
        switch (pkg) {
            case ProfilePairing.DISNEY:
                if (desc != null) {
                    Matcher m = DISNEY_TILE.matcher(desc.toString().trim());
                    if (m.matches()) tiles.add(new Tile(m.group(1), node, clickableOf(node)));
                }
                break;
            case ProfilePairing.PARAMOUNT:
                // The name is on the profile_avatar node itself (View layout) or on a child (Compose).
                String id = node.getViewIdResourceName();
                if (id != null && (id.equals("profile_avatar") || id.endsWith("/profile_avatar"))) {
                    String name = desc != null && desc.length() > 0 ? desc.toString().trim() : firstLabel(node, 0);
                    if (name != null && !name.toLowerCase(Locale.ROOT).contains("add profile")) {
                        tiles.add(new Tile(name, node, clickableOf(node)));
                    }
                }
                break;
            case ProfilePairing.APPLE_TV:
                if (label.toLowerCase(Locale.ROOT).contains("who's watching")) pickerTitle[0] = true;
                CharSequence cls = node.getClassName();
                if (cls != null && cls.toString().endsWith("Button") && !label.isEmpty()
                        && !label.toLowerCase(Locale.ROOT).contains("add profile")) {
                    // The first tile also reads the heading: "Who's Watching?, Select an account or sign in, Alex".
                    String[] parts = label.split(",\\s*");
                    tiles.add(new Tile(parts[parts.length - 1].trim(), node, clickableOf(node)));
                }
                break;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            collect(pkg, node.getChild(i), tiles, pickerTitle, visited, depth + 1);
        }
    }

    /** The first content description or text under a node. */
    private static String firstLabel(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 4) return null;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) continue;
            CharSequence label = child.getContentDescription() != null ? child.getContentDescription() : child.getText();
            if (label != null && label.toString().trim().length() > 0) return label.toString().trim();
            String deeper = firstLabel(child, depth + 1);
            if (deeper != null) return deeper;
        }
        return null;
    }

    private static AccessibilityNodeInfo clickableOf(AccessibilityNodeInfo node) {
        AccessibilityNodeInfo n = node;
        for (int i = 0; n != null && i < 6; i++) {
            if (n.isClickable()) return n;
            n = n.getParent();
        }
        return node;
    }

    private static boolean hasFocus(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 4) return false;
        if (node.isFocused() || node.isAccessibilityFocused()) return true;
        for (int i = 0; i < node.getChildCount(); i++) {
            if (hasFocus(node.getChild(i), depth + 1)) return true;
        }
        return false;
    }

    // ---- Profile PIN entry (docs/design/streaming-pin-entry.md) ----

    /** Hearth is typing a profile PIN: the remote's keys are held (Back and Home cancel). */
    static boolean isEnteringPin() {
        ProfilePairingService service = sInstance;
        return service != null && service.mPin != null;
    }

    /** Back or Home while a PIN is typed: stop, and leave the app's PIN screen to the parent. */
    static void cancelPinEntry() {
        ProfilePairingService service = sInstance;
        if (service == null) return;
        service.mHandler.post(() -> {
            if (service.mPin != null) service.mPin.machine.onCancel();
        });
    }

    /**
     * Starts typing the picked profile's saved PIN when everything allows it: the app has a recipe and isn't paused,
     * this is a grown-up Google TV profile paired with that app profile by an explicit choice, and a PIN is saved for
     * it that Hearth may still try. False when not (the cover goes as usual).
     */
    /**
     * The launched app said something (speech through Hearth voice, or an announcement): kept a short while for a PIN
     * recipe that starts after it (the PIN screen often speaks before the cover's pick is done), and handed to a
     * running one. Never logged.
     */
    private void heard(String pkg, String text) {
        if (pkg == null || text == null || !pkg.equals(sListeningTo)) return;
        long now = SystemClock.elapsedRealtime();
        mRecentSpeech.addLast(new Object[] {now, pkg, text});
        while (mRecentSpeech.size() > 60 || (!mRecentSpeech.isEmpty()
                && now - (long) mRecentSpeech.peekFirst()[0] > RECENT_SPEECH_MS)) {
            mRecentSpeech.pollFirst();
        }
        PinRun run = mPin;
        if (run != null && run.session.pkg.equals(pkg)) {
            run.recipe.onSpeech(text);
            checkPinScreen();
        }
    }

    private final Runnable mPinOutcomePoll = new Runnable() {
        @Override
        public void run() {
            if (mPin == null || !mPin.outcomeDue) return;
            checkPinScreen();
            if (mPin != null) mHandler.postDelayed(this, PIN_OUTCOME_POLL_MS);
        }
    };

    private boolean startPinEntry(Session s) {
        String appProfile = s.pickedName;
        PinRecipe recipe = PinRecipes.forPackage(s.pkg);
        if (recipe == null || appProfile == null || s.kids || mCover == null) return false;
        if (!appProfile.equals(ProfilePairing.getChosenProfile(this, s.pkg, s.key))) return false;
        if (!PinVault.has(this, s.pkg, appProfile) || PinVault.isPaused(this, s.pkg)) return false;
        char[] pin = PinVault.open(this, s.pkg, appProfile);
        if (pin == null) return false;
        if (pin.length != recipe.pinLength()) {
            java.util.Arrays.fill(pin, '\0');
            Log.i(TAG, "PIN for " + s.pkg + " skipped: its length doesn't fit the app");
            return false;
        }
        mPin = new PinRun(s, appProfile, recipe, pin);
        long now = SystemClock.elapsedRealtime();
        for (Object[] said : mRecentSpeech) {
            if (s.pkg.equals(said[1]) && now - (long) said[0] <= RECENT_SPEECH_MS) recipe.onSpeech((String) said[2]);
        }
        if (mCoverTitle != null) mCoverTitle.setText(getString(R.string.pin_unlocking));
        mHandler.postDelayed(mPinNoScreen, PIN_SCREEN_WAIT_MS);
        mHandler.postDelayed(mPinBroken, PIN_OVERALL_MS);
        Log.i(TAG, "Waiting for " + s.pkg + "'s PIN screen");
        checkPinScreen();
        return true;
    }

    private final Runnable mPinNoScreen = () -> {
        if (mPin != null) mPin.machine.onNoScreen();
    };
    private final Runnable mPinBroken = () -> {
        if (mPin != null) mPin.machine.onBroken();
    };

    private void onPinEvent(AccessibilityEvent event) {
        PinRun run = mPin;
        CharSequence pkg = event.getPackageName();
        int type = event.getEventType();
        if (pkg != null && !run.session.pkg.contentEquals(pkg)) {
            // Another app in front: the parent left, or something came up over the app
            if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && !pkg.toString().startsWith(getPackageName())
                    && !"com.android.systemui".contentEquals(pkg)) {
                run.machine.onBroken();
            }
            return;
        }
        // Announcements reach the recipe through heard()
        run.recipe.onEvent(event);
        if (type != AccessibilityEvent.TYPE_ANNOUNCEMENT) checkPinScreen();
    }

    /** What the recipe makes of the app's window now: the PIN screen to type on, or the app's answer. */
    private void checkPinScreen() {
        PinRun run = mPin;
        if (run == null) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || !run.session.pkg.contentEquals(root.getPackageName() != null ? root.getPackageName() : "")) {
            return;
        }
        PinEntryMachine.Screen screen = run.recipe.recognize(root);
        if (screen != null) {
            mHandler.removeCallbacks(mPinNoScreen);
            run.machine.onScreen(screen);
        }
        if (mPin == run && run.outcomeDue) {
            PinEntryMachine.Outcome outcome = run.recipe.outcome(root);
            if (outcome != null) run.machine.onOutcome(outcome);
        }
    }

    private final class PinRun implements PinEntryMachine.Driver {
        final Session session;
        final String appProfile;
        final PinRecipe recipe;
        final PinEntryMachine machine;
        char[] pin;
        /** Every digit went in: the app's answer is awaited. */
        boolean outcomeDue;
        private final Runnable stepTimeout = () -> machineBroken();

        PinRun(Session session, String appProfile, PinRecipe recipe, char[] pin) {
            this.session = session;
            this.appProfile = appProfile;
            this.recipe = recipe;
            this.pin = pin;
            this.machine = new PinEntryMachine(this, pin.length);
        }

        private void machineBroken() {
            machine.onBroken();
        }

        @Override
        public void typeDigit(int index) {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) {
                machine.onDigit(false);
                return;
            }
            mHandler.removeCallbacks(stepTimeout);
            mHandler.postDelayed(stepTimeout, recipe.stepTimeoutMs());
            recipe.type(ProfilePairingService.this, root, pin[index], ok -> {
                mHandler.removeCallbacks(stepTimeout);
                if (mPin != this) return;
                if (ok && index == pin.length - 1) {
                    outcomeDue = true;
                    mHandler.postDelayed(stepTimeout, recipe.outcomeTimeoutMs());
                    mHandler.postDelayed(mPinOutcomePoll, PIN_OUTCOME_POLL_MS);
                }
                machine.onDigit(ok);
                if (outcomeDue) checkPinScreen();
            });
        }

        @Override
        public void finished(PinEntryMachine.Result result, int digitsTyped) {
            mHandler.removeCallbacks(stepTimeout);
            endPinEntry(this, result, digitsTyped);
        }
    }

    private void endPinEntry(PinRun run, PinEntryMachine.Result result, int digitsTyped) {
        if (mPin != run) return;
        mPin = null;
        java.util.Arrays.fill(run.pin, '\0');
        mHandler.removeCallbacks(mPinNoScreen);
        mHandler.removeCallbacks(mPinBroken);
        mHandler.removeCallbacks(mPinOutcomePoll);
        mRecentSpeech.clear();
        String pkg = run.session.pkg;
        String app = appLabel(pkg);
        Log.i(TAG, "PIN entry in " + pkg + ": " + result);
        switch (result) {
            case ACCEPTED:
                PinVault.markAccepted(this, pkg, run.appProfile);
                PinVault.resetBreaks(this, pkg);
                hideCover();
                break;
            case REJECTED:
                PinVault.markRejected(this, pkg, run.appProfile);
                showPinPopup(getString(R.string.pin_rejected_title, app, run.appProfile),
                        getString(R.string.pin_rejected_body), pkg);
                break;
            case LOCKED_OUT:
                PinVault.markRejected(this, pkg, run.appProfile);
                showPinPopup(getString(R.string.pin_locked_title, app, run.appProfile),
                        getString(R.string.pin_locked_body), pkg);
                break;
            case SCREEN_CHANGED:
                PinVault.setPaused(this, pkg, true);
                coverMessage(getString(R.string.pin_screen_changed, app));
                break;
            case BROKEN:
                if (PinVault.addBreak(this, pkg) >= PIN_BREAKS_BEFORE_PAUSE) PinVault.setPaused(this, pkg, true);
                coverMessage(digitsTyped > 0
                        ? getString(R.string.pin_broken_digits, digitsTyped) : getString(R.string.pin_broken));
                break;
            case NO_PIN_SCREEN:
            case CANCELLED:
            default:
                hideCover();
        }
        mHandler.postDelayed(mGoIdle, IDLE_AFTER_MS);
    }

    /** Says why Hearth stopped, on the cover, then leaves the app's PIN screen to the parent. */
    private void coverMessage(String text) {
        if (mCoverTitle == null) return;
        mCoverTitle.setText(text);
        mHandler.postDelayed(this::hideCover, PIN_MESSAGE_MS);
    }

    /**
     * Over the cover: the saved PIN wasn't taken. Change PIN opens Hearth's Settings on the app's PINs; Close (and
     * Back) drop the pop-up and the cover, leaving the app's own PIN entry for the parent to type by hand.
     */
    private void showPinPopup(String titleText, String bodyText, String pkg) {
        hidePinPopup();
        try {
            Context c = this;
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setPadding(dp(40), dp(32), dp(40), dp(28));
            GradientDrawable background = new GradientDrawable();
            background.setCornerRadius(dp(16));
            background.setColor(Color.parseColor("#FF202024"));
            background.setStroke(dp(2), accentColor());
            box.setBackground(background);

            TextView title = new TextView(c);
            title.setText(titleText);
            title.setTextColor(Color.WHITE);
            title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
            box.addView(title);

            TextView body = new TextView(c);
            body.setText(bodyText);
            body.setTextColor(Color.parseColor("#B3FFFFFF"));
            body.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
            LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(dp(640),
                    LinearLayout.LayoutParams.WRAP_CONTENT);
            bodyParams.topMargin = dp(12);
            box.addView(body, bodyParams);

            LinearLayout buttons = new LinearLayout(c);
            buttons.setOrientation(LinearLayout.HORIZONTAL);
            buttons.setGravity(Gravity.END);
            LinearLayout.LayoutParams buttonsParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            buttonsParams.topMargin = dp(24);
            TextView change = popupButton(getString(R.string.pin_change));
            TextView close = popupButton(getString(R.string.pin_close));
            buttons.addView(change);
            LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            closeParams.leftMargin = dp(16);
            buttons.addView(close, closeParams);
            box.addView(buttons, buttonsParams);

            change.setOnClickListener(v -> {
                hidePinPopup();
                hideCover();
                Intent open = new Intent(this, MainActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        .putExtra(MainActivity.EXTRA_OPEN_PROFILE_PINS, pkg);
                try {
                    startActivity(open);
                } catch (Exception e) {
                    Log.w(TAG, "Couldn't open Hearth's Settings", e);
                }
            });
            close.setOnClickListener(v -> {
                hidePinPopup();
                hideCover();
            });
            box.setOnKeyListener((v, keyCode, event) -> {
                if (keyCode == android.view.KeyEvent.KEYCODE_BACK
                        && event.getAction() == android.view.KeyEvent.ACTION_UP) {
                    hidePinPopup();
                    hideCover();
                    return true;
                }
                return false;
            });

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.CENTER;
            getSystemService(WindowManager.class).addView(box, params);
            mPinPopup = box;
            close.requestFocus();
        } catch (Exception e) {
            Log.w(TAG, "PIN pop-up failed", e);
            hideCover();
        }
    }

    private TextView popupButton(String label) {
        TextView button = new TextView(this);
        button.setText(label);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        button.setPadding(dp(28), dp(12), dp(28), dp(12));
        button.setFocusable(true);
        button.setClickable(true);
        int accent = accentColor();
        button.setOnFocusChangeListener((v, focused) -> {
            GradientDrawable pill = new GradientDrawable();
            pill.setCornerRadius(dp(24));
            pill.setColor(focused ? accent : Color.parseColor("#33FFFFFF"));
            v.setBackground(pill);
            ((TextView) v).setTextColor(focused ? Color.BLACK : Color.WHITE);
        });
        GradientDrawable pill = new GradientDrawable();
        pill.setCornerRadius(dp(24));
        pill.setColor(Color.parseColor("#33FFFFFF"));
        button.setBackground(pill);
        button.setTextColor(Color.WHITE);
        return button;
    }

    private void hidePinPopup() {
        if (mPinPopup == null) return;
        try {
            getSystemService(WindowManager.class).removeView(mPinPopup);
        } catch (Exception ignored) {
        }
        mPinPopup = null;
    }

    // ---- Cover card ----

    private void showCover(Session s) {
        if (mCover != null) return;
        try {
            Context c = this;
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setGravity(Gravity.CENTER);
            box.setBackgroundColor(Color.parseColor("#FF0E0E12"));  // fully opaque: the picker moving underneath shouldn't show

            ProgressBar spinner = new ProgressBar(c);
            box.addView(spinner, new LinearLayout.LayoutParams(dp(48), dp(48)));

            TextView title = new TextView(c);
            title.setText(getString(R.string.profile_pairing_opening, appLabel(s.pkg), s.hearthProfile));
            title.setTextColor(Color.WHITE);
            title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
            title.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            titleParams.topMargin = dp(20);
            box.addView(title, titleParams);

            View bar = new View(c);
            GradientDrawable accent = new GradientDrawable();
            accent.setCornerRadius(dp(2));
            accent.setColor(accentColor());
            bar.setBackground(accent);
            LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(dp(64), dp(4));
            barParams.topMargin = dp(16);
            box.addView(bar, barParams);

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT);
            getSystemService(WindowManager.class).addView(box, params);
            mCover = box;
            mCoverTitle = title;
        } catch (Exception e) {
            Log.w(TAG, "Cover card failed", e);
        }
    }

    private void hideCover() {
        if (mCover == null) return;
        try {
            getSystemService(WindowManager.class).removeView(mCover);
        } catch (Exception ignored) {
        }
        mCover = null;
        mCoverTitle = null;
    }

    /** The first time Hearth picks a profile by name match for an app, says which, and where to change it. */
    private void announceMatch(Session s) {
        if (s.pickedName == null
                || !ProfilePairing.MODE_AUTO.equals(ProfilePairing.getMode(this, s.pkg, s.key))
                || !ProfilePairing.announceOnce(this, s.pkg, s.key)) {
            return;
        }
        hideBanner();
        try {
            TextView text = new TextView(this);
            text.setText(getString(R.string.profile_pairing_matched, appLabel(s.pkg), s.pickedName, s.hearthProfile));
            text.setTextColor(Color.WHITE);
            text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
            text.setPadding(dp(24), dp(14), dp(24), dp(14));
            GradientDrawable background = new GradientDrawable();
            background.setCornerRadius(dp(12));
            background.setColor(Color.parseColor("#E6202024"));
            background.setStroke(dp(2), accentColor());
            text.setBackground(background);

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
            params.y = dp(48);
            getSystemService(WindowManager.class).addView(text, params);
            mBanner = text;
            mHandler.postDelayed(this::hideBanner, BANNER_MS);
        } catch (Exception e) {
            Log.w(TAG, "Match notice failed", e);
        }
    }

    private void hideBanner() {
        if (mBanner == null) return;
        try {
            getSystemService(WindowManager.class).removeView(mBanner);
        } catch (Exception ignored) {
        }
        mBanner = null;
    }

    private String appLabel(String pkg) {
        try {
            PackageManager pm = getPackageManager();
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            return pm.getApplicationLabel(info).toString();
        } catch (Exception e) {
            return getString(R.string.profile_pairing_the_app);
        }
    }

    private int accentColor() {
        String hex = FlutterPrefs.getString(this, "accent_color", null);
        try {
            if (hex != null) return Color.parseColor("#" + hex.replace("#", ""));
        } catch (Exception ignored) {
        }
        return Color.parseColor("#7C4DFF");
    }

    private int dp(int value) {
        return Dp.px(this, value);
    }
}
