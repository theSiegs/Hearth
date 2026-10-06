package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
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

    private static final Pattern NETFLIX_COUNT = Pattern.compile("(?i)^(.*?)[,.]?\\s*(\\d+) of (\\d+) profiles?");
    private static final Pattern MAX_ITEM = Pattern.compile("(?i)^\\s*(.+?)\\s+Button\\b[,.]?\\s*(\\d+)\\s+of\\s+(\\d+)");
    private static final Pattern DISNEY_TILE = Pattern.compile("(?i)^Access (.+)'s profile$");

    private static volatile ProfilePairingService sInstance;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private Session mSession;
    private View mCover;
    private TextView mCoverTitle;
    private View mBanner;

    /** How a launch ended: a profile was picked; the picker is left to the user; or nothing to tell them. */
    private static final int PICKED = 0;
    private static final int NO_MATCH = 1;
    private static final int QUIET = 2;
    private static final long NO_MATCH_MESSAGE_MS = 2_000;
    private static final long BANNER_MS = 8_000;

    /** One app launch. Main thread only. */
    private static final class Session {
        final String pkg;
        final String hearthProfile;
        boolean pickerSeen;
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
        /** Where we believe focus is, for apps that don't report it (-1: unknown). */
        int assumedFocus = -1;
        boolean reachedEnd;

        Session(String pkg, String hearthProfile) {
            this.pkg = pkg;
            this.hearthProfile = hearthProfile;
        }
    }

    /** The app whose launch Profile Pairing is handling right now, or null. Read from Hearth voice's thread. */
    private static volatile String sListeningTo;

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
        String hearthProfile = LauncherAccessibilityService.getActiveProfileName(context);
        if (hearthProfile == null || hearthProfile.isEmpty()) {
            Log.i(TAG, packageName + " skipped: the Google TV profile isn't known");
            return;
        }
        ProfilePairing.rememberHearthProfile(context, hearthProfile, null);
        if (ProfilePairing.MODE_PICKER.equals(ProfilePairing.getMode(context, packageName, hearthProfile))) {
            Log.i(TAG, packageName + " skipped: " + hearthProfile + " always gets the picker");
            return;
        }
        if (ProfilePairing.NETFLIX.equals(packageName) && !isVoiceDefault(context)) {
            Log.i(TAG, "Netflix skipped: Hearth's voice isn't the text-to-speech engine");
            return;
        }
        Runnable begin = () -> service.begin(packageName, hearthProfile);
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
    }

    @Override
    public void onDestroy() {
        if (sInstance == this) sInstance = null;
        sListeningTo = null;
        mHandler.removeCallbacksAndMessages(null);
        hideCover();
        hideBanner();
        super.onDestroy();
    }

    @Override
    public void onInterrupt() {
    }

    private static boolean needsScreenReaderMode(String pkg) {
        return ProfilePairing.NETFLIX.equals(pkg) || ProfilePairing.APPLE_TV.equals(pkg)
                || ProfilePairing.MAX.equals(pkg);
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
        if (mSession != null) return;
        setMode(false, false);
        // The app stops speaking once screen-reader mode is off; until then Hearth voice keeps it quiet.
        sListeningTo = null;
    };

    private final Runnable mTimeout = () -> finish(NO_MATCH, "timed out");

    private void begin(String pkg, String hearthProfile) {
        if (mSession != null) finish(QUIET, "replaced");
        mHandler.removeCallbacks(mGoIdle);
        hideCover();
        mSession = new Session(pkg, hearthProfile);
        sListeningTo = pkg;
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
                hideCover();
                announceMatch(s);
            }, COVER_AFTER_PICK_MS);
        } else if (outcome == NO_MATCH && s.pickerSeen && mCoverTitle != null) {
            // Say why the picker is staying up, then get out of the way.
            mCoverTitle.setText("No matching profile for " + s.hearthProfile + ". Choose one on the next screen.");
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
        Session s = mSession;
        if (s == null || !ProfilePairing.NETFLIX.equals(s.pkg) || !s.pkg.equals(callerPackage)) return;
        String t = text.trim();
        String lower = t.toLowerCase(Locale.ROOT);
        if (lower.contains("choose a profile") || lower.contains("profile selection")
                || lower.contains("who's watching")) {
            pickerFound();
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
        String target = ProfilePairing.choose(this, s.pkg, s.hearthProfile, known);
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
            android.graphics.Rect ra = new android.graphics.Rect();
            android.graphics.Rect rb = new android.graphics.Rect();
            a.node.getBoundsInScreen(ra);
            b.node.getBoundsInScreen(rb);
            return ra.top / 100 != rb.top / 100 ? Integer.compare(ra.top, rb.top) : Integer.compare(ra.left, rb.left);
        });
        List<String> names = new ArrayList<>();
        for (Tile tile : tiles) names.add(tile.name);
        ProfilePairing.rememberNames(this, s.pkg, names, true);
        String target = ProfilePairing.choose(this, s.pkg, s.hearthProfile, names);
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
        for (int i = 0; i < tiles.size(); i++) {
            if (hasFocus(tiles.get(i).node, 0) || (tiles.get(i).clickable != null
                    && hasFocus(tiles.get(i).clickable, 0))) {
                focused = i;
                break;
            }
        }
        if (focused < 0 && ProfilePairing.APPLE_TV.equals(s.pkg)) {
            // Apple TV doesn't report focus; its picker opens on the first tile, so count our own presses from there.
            if (s.assumedFocus < 0) s.assumedFocus = 0;
            focused = s.assumedFocus;
        }
        if (focused == targetIndex) {
            pressKey(0);
            s.pickedName = target;
            finish(PICKED, "chose " + target);
        } else if (focused >= 0 && ++s.steps <= MAX_STEPS) {
            int direction = targetIndex > focused ? 1 : -1;
            if (s.assumedFocus >= 0) s.assumedFocus += direction;
            pressKey(direction);
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
                // "com.cbs.ott:id/profile_avatar" with the name on it (2025), or a Compose "profile_avatar" tile
                // with the name on a child (October 2026).
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
            title.setText("Opening " + appLabel(s.pkg) + " as " + s.hearthProfile + "…");
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
                || !ProfilePairing.MODE_AUTO.equals(ProfilePairing.getMode(this, s.pkg, s.hearthProfile))
                || !ProfilePairing.announceOnce(this, s.pkg, s.hearthProfile)) {
            return;
        }
        hideBanner();
        try {
            TextView text = new TextView(this);
            text.setText("Hearth opened " + appLabel(s.pkg) + " as “" + s.pickedName + "” for "
                    + s.hearthProfile + ". To change it: Hearth Settings → Profile Pairing.");
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
            return "the app";
        }
    }

    private int accentColor() {
        String hex = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getString("flutter.accent_color", null);
        try {
            if (hex != null) return Color.parseColor("#" + hex.replace("#", ""));
        } catch (Exception ignored) {
        }
        return Color.parseColor("#7C4DFF");
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
