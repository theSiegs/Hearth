package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.Objects;

/**
 * Pushes what the TV is doing to Home Assistant: foreground app, now playing (from any app's media session, which
 * needs notification access), Google TV profile, kids profile, screen time lock, screen on/off, usage today and each
 * app's Android category. Sent on change (debounced) and as a heartbeat. Paired with the Hearth integration
 * ({@link HaIntegration}), it goes there with the TV's secret, and the answer is each profile's limits (kept as the
 * allowance HearthTube enforces). Without a pairing it sends nothing (the older webhook way is retired).
 */
final class HaStatusReporter {
    // HaConfig's keys, under the names the activity and the accessibility service use
    private static final String TAG = "HearthHaStatus";
    private static final long DEBOUNCE_MS = 1_500;
    private static final long HEARTBEAT_MS = 10 * 60_000;
    /**
     * Today's usage keeps growing while something is in front or playing: then a post this often (only when the counts
     * changed). Every post recomputes the household's limits in Home Assistant, so not every minute;
     * what matters at once (another app, play or pause, the profile, the screen, screen time) is posted as it happens.
     */
    private static final long USAGE_TICK_MS = 2 * 60_000;
    private static final String STATE_PREFS = "ltv_ha_status";
    private static final String EVENT_KEY = "screen_time_event";
    private static final String EVENT_AT_KEY = "screen_time_event_at";

    private final Context mContext;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    /** Builds and posts the status (see sender()); stop() shuts it down. Main thread only. */
    private ExecutorService mSender;
    private final List<MediaController> mControllers = new ArrayList<>();
    private MediaSessionManager mSessionManager;
    private String mForegroundPackage;
    private boolean mScreenOn = true;
    private boolean mScreenTimeLock = false;
    private ScreenTimeScreen mScreenTime;
    private long mScreenTimeSeenAt;
    /** The last body sent; used on the sender thread (a new one after a restart, hence volatile). */
    private volatile String mLastSent;
    /**
     * Paired and the screen on, a thread holds the integration's long-poll so a pause, a lock or an answered request
     * arrives in seconds rather than at the next two-minute post. Seconds each wait is held (the integration keeps
     * it under a minute), and how long to wait after a failure before asking again.
     */
    private static final int WAIT_S = 50;
    private static final long WAIT_RETRY_MS = 30_000;
    /** After a 404 (an older integration, or Home Assistant still loading), the long-poll waits this long to try again. */
    private static final long WAIT_UNSUPPORTED_RETRY_MS = 10 * 60_000;
    /** The version of the last state document the integration answered with: what the wait compares against. */
    private volatile String mStateVersion;
    /** Bumped to end the waiting thread: a thread whose generation isn't current stops after its wait. */
    private final AtomicInteger mWaitGeneration = new AtomicInteger();
    private boolean mWaiting;

    /** What the reporter knows, copied on the main thread so the status can be built on the sender thread. */
    private static final class Snapshot {
        final boolean screenOn;
        final String foregroundPackage;
        final boolean screenTimeLock;
        final ScreenTimeScreen screenTime;
        final long screenTimeSeenAt;
        /** The media session shown as now playing: its app (null when there's none), state and metadata. */
        final String mediaPackage;
        final PlaybackState playback;
        final MediaMetadata metadata;
        final boolean nowPlayingAvailable;

        Snapshot(HaStatusReporter reporter, MediaController playing) {
            screenOn = reporter.mScreenOn;
            foregroundPackage = reporter.mForegroundPackage;
            screenTimeLock = reporter.mScreenTimeLock;
            screenTime = reporter.mScreenTime;
            screenTimeSeenAt = reporter.mScreenTimeSeenAt;
            mediaPackage = playing != null ? playing.getPackageName() : null;
            playback = playing != null ? playing.getPlaybackState() : null;
            metadata = playing != null ? playing.getMetadata() : null;
            nowPlayingAvailable = reporter.mSessionManager != null;
        }
    }

    private final MediaController.Callback mControllerCallback = new MediaController.Callback() {
        @Override
        public void onPlaybackStateChanged(PlaybackState state) {
            scheduleSend();
        }

        @Override
        public void onMetadataChanged(MediaMetadata metadata) {
            scheduleSend();
        }

        @Override
        public void onSessionDestroyed() {
            scheduleSend();
        }
    };

    private final MediaSessionManager.OnActiveSessionsChangedListener mSessionsListener = this::setControllers;
    private final Runnable mSend = () -> send(false);
    private final Runnable mHeartbeat = new Runnable() {
        @Override
        public void run() {
            send(true);
            // Paired, each answer refreshes the profiles' limits: often enough that HearthTube's stay fresh (a post
            // to the integration runs no automation)
            mHandler.postDelayed(this, HaIntegration.isPaired(mContext) ? USAGE_TICK_MS : HEARTBEAT_MS);
        }
    };
    /** Sends if today's usage changed (an unchanged status isn't sent again). */
    private final Runnable mUsageTick = new Runnable() {
        @Override
        public void run() {
            scheduleSend();
            mHandler.postDelayed(this, USAGE_TICK_MS);
        }
    };

    HaStatusReporter(Context context) {
        mContext = context;
    }

    static boolean isConfigured(Context context) {
        return HaIntegration.isPaired(context);
    }

    void start() {
        stop();
        if (!isConfigured(mContext)) {
            Log.i(TAG, "Status reporting off (not paired with the Hearth integration)");
            return;
        }
        Log.i(TAG, "Status reporting to Home Assistant started");
        mSessionManager = (MediaSessionManager) mContext.getSystemService(Context.MEDIA_SESSION_SERVICE);
        ComponentName listener = new ComponentName(mContext, LauncherNotificationListenerService.class);
        try {
            mSessionManager.addOnActiveSessionsChangedListener(mSessionsListener, listener, mHandler);
            setControllers(mSessionManager.getActiveSessions(listener));
        } catch (SecurityException e) {
            // No notification access: report apps and profiles without now playing
            mSessionManager = null;
        }
        mHandler.post(mHeartbeat);
        mHandler.postDelayed(mUsageTick, USAGE_TICK_MS);
        startWaiting();
    }

    void stop() {
        stopWaiting();
        mHandler.removeCallbacks(mHeartbeat);
        mHandler.removeCallbacks(mUsageTick);
        if (mSessionManager != null) {
            try {
                mSessionManager.removeOnActiveSessionsChangedListener(mSessionsListener);
            } catch (Exception ignored) {
            }
            mSessionManager = null;
        }
        setControllers(null);
        // After setControllers, which schedules a send: nothing goes out once stopped
        mHandler.removeCallbacks(mSend);
        if (mSender != null) {
            // A post under way still finishes
            mSender.shutdown();
            mSender = null;
        }
    }

    void setForegroundPackage(String packageName) {
        if (!packageName.equals(mForegroundPackage)) {
            mForegroundPackage = packageName;
            scheduleSend();
        }
    }

    void setScreenOn(boolean on) {
        mScreenOn = on;
        scheduleSend();
        if (on) BedtimeHeadsUp.schedule(mContext);
        // Only while someone could be watching: asleep, the two-minute post is soon enough
        if (on) startWaiting();
        else stopWaiting();
    }

    /** Main thread. Starts holding the long-poll, unless it's already held, unpaired, the screen is off or unsupported. */
    private void startWaiting() {
        if (mWaiting || !mScreenOn || !HaIntegration.isPaired(mContext)) return;
        mWaiting = true;
        int generation = mWaitGeneration.incrementAndGet();
        Thread thread = new Thread(() -> waitLoop(generation), "HearthHaWait");
        thread.setDaemon(true);
        thread.start();
    }

    /** Main thread. The waiting thread stops after the wait it holds (at most WAIT_S seconds later). */
    private void stopWaiting() {
        mWaiting = false;
        mWaitGeneration.incrementAndGet();
    }

    /** The waiting thread: hold, refresh on a change, hold again; quits once its generation is old. */
    private void waitLoop(int generation) {
        while (generation == mWaitGeneration.get()) {
            String held = mStateVersion;
            HaIntegration.WaitResult result = HaIntegration.waitForChange(mContext, held, WAIT_S);
            if (generation != mWaitGeneration.get()) return;
            switch (result) {
                case CHANGED:
                    mHandler.post(this::refreshNow);
                    // Until the refreshed answer brings the new version (else the next wait answers at once)
                    for (int i = 0; i < 20 && Objects.equals(held, mStateVersion); i++) {
                        if (!pause(500) || generation != mWaitGeneration.get()) return;
                    }
                    break;
                case NOT_CHANGED:
                    break;
                case UNSUPPORTED:
                    // An older integration, or one restarting (its views register as it loads): the two-minute
                    // post carries on meanwhile, and the long-poll is tried again later rather than given up for good
                    Log.i(TAG, "Home Assistant has no long-poll right now; trying again in a while");
                    if (!pause(WAIT_UNSUPPORTED_RETRY_MS)) return;
                    break;
                case FAILED:
                    if (!pause(WAIT_RETRY_MS)) return;
                    break;
            }
        }
    }

    private static boolean pause(long ms) {
        try {
            Thread.sleep(ms);
            return true;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    /** Posts the status now, changed or not, for a fresh answer (a request for more time waiting for its answer). */
    void refreshNow() {
        if (!HaIntegration.isPaired(mContext)) return;
        mHandler.removeCallbacks(mSend);
        send(true);
    }

    void setScreenTimeLock(boolean locked) {
        if (locked != mScreenTimeLock) {
            mScreenTimeLock = locked;
            recordScreenTimeEvent(locked);
            scheduleSend();
        }
    }

    /**
     * Screen time came up or went: kept (and sent with every status until the next change) so Home Assistant can
     * trigger on screen_time_event_at changing, even if the post at the change is lost. A lock restored after a
     * restart is no new event.
     */
    private void recordScreenTimeEvent(boolean locked) {
        String event = locked ? "appeared" : "cleared";
        android.content.SharedPreferences prefs = mContext.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE);
        String last = prefs.getString(EVENT_KEY, null);
        if (event.equals(last) || last == null && !locked) return;
        prefs.edit().putString(EVENT_KEY, event).putLong(EVENT_AT_KEY, System.currentTimeMillis()).apply();
    }

    /** What Google TV last said about screen time: why it locks and how long is left. */
    void setScreenTime(ScreenTimeScreen screen) {
        mScreenTime = screen;
        mScreenTimeSeenAt = System.currentTimeMillis();
        scheduleSend();
    }

    /** Google TV suspended or released apps: the allowed apps may have changed. */
    void onAppsChanged() {
        scheduleSend();
    }

    /** Profile name or kids state may have changed. */
    void onProfileChanged() {
        // A new profile has its own limits: what the last screen said no longer applies
        mScreenTime = null;
        scheduleSend();
        // The new profile's bedtime heads-up (or none)
        BedtimeHeadsUp.schedule(mContext);
    }

    private void setControllers(List<MediaController> controllers) {
        for (MediaController controller : mControllers) controller.unregisterCallback(mControllerCallback);
        mControllers.clear();
        if (controllers != null) {
            for (MediaController controller : controllers) {
                controller.registerCallback(mControllerCallback, mHandler);
                mControllers.add(controller);
            }
        }
        scheduleSend();
    }

    private void scheduleSend() {
        if (!isConfigured(mContext)) return;
        mHandler.removeCallbacks(mSend);
        mHandler.postDelayed(mSend, DEBOUNCE_MS);
    }

    /** Sends the status unless it's the same as the last one sent; a forced send goes out anyway. */
    private void send(boolean force) {
        if (!HaIntegration.isPaired(mContext)) return;
        Snapshot snapshot = new Snapshot(this, primaryController());
        // Labels, the profile and the allowed apps take PackageManager and UserManager calls: off the main thread
        sender().execute(() -> {
            String body;
            try {
                body = buildStatus(snapshot).toString();
            } catch (JSONException e) {
                Log.w(TAG, "Couldn't build the status", e);
                return;
            }
            if (!force && body.equals(mLastSent)) return;
            mLastSent = body;
            postToIntegration(body);
        });
    }

    /** Made on first use: a change can schedule a send without start(), e.g. once the setup page saves the address. */
    private ExecutorService sender() {
        if (mSender == null) mSender = Executors.newSingleThreadExecutor(r -> new Thread(r, "HearthHaStatus"));
        return mSender;
    }

    private JSONObject buildStatus(Snapshot s) throws JSONException {
        JSONObject status = new JSONObject();
        PackageManager pm = mContext.getPackageManager();
        status.put("screen", s.screenOn ? "on" : "off");
        status.put("app_package", s.foregroundPackage == null ? JSONObject.NULL : s.foregroundPackage);
        status.put("app", s.foregroundPackage == null ? JSONObject.NULL : label(pm, s.foregroundPackage));
        status.put("profile", nullable(LauncherAccessibilityService.getActiveProfileName(mContext)));
        // The stable key of the Google TV profile ("user:<serial>"): survives renames, maps a kid to their TV profile
        String activeKey = LauncherAccessibilityService.getActiveProfileKey(mContext);
        status.put("profile_id", nullable(activeKey));
        // profile_id's serial is this TV's own (one kid is user 10 here and user 12 on the next TV): who the profile
        // is across the household's TVs, for Home Assistant's mapping
        status.put("profile_ref", nullable(ProfileUsers.householdRef(mContext, activeKey)));
        boolean kids = ProfileUsers.isKids(mContext);
        status.put("kids_profile", kids);
        status.put("screen_time_up", s.screenTimeLock);
        // Google TV's own Kids daily limit (not Hearth's): Home Assistant can't lift it, so it says so (explain)
        status.put("google_time_up", ScreenTimeScreen.isGoogleLimit(s.screenTimeLock, s.screenTime));
        // Minutes are as Google TV stated them at screen_time_seen_at (epoch ms); Home Assistant can count down.
        // screen_time_text is Google TV's own wording, so what it says can be checked against the parsing.
        ScreenTimeScreen screenTime = s.screenTime;
        status.put("screen_time_reason", screenTime == null ? JSONObject.NULL : screenTime.reason.id);
        status.put("screen_time_minutes_left", screenTime == null || screenTime.minutesLeft == null
                ? JSONObject.NULL : screenTime.minutesLeft);
        status.put("screen_time_text", screenTime == null ? JSONObject.NULL : screenTime.text);
        status.put("screen_time_seen_at", screenTime == null ? JSONObject.NULL : s.screenTimeSeenAt);
        status.put("screen_time_unlocks_at", screenTime == null ? JSONObject.NULL : nullable(screenTime.unlocksAt));
        status.put("screen_time_unlocks_at_iso", screenTime == null ? JSONObject.NULL
                : nullable(ScreenTimeScreen.unlocksAtIso(screenTime.unlocksAt, s.screenTimeSeenAt)));
        android.content.SharedPreferences events = mContext.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE);
        status.put("screen_time_event", nullable(events.getString(EVENT_KEY, null)));
        long eventAt = events.getLong(EVENT_AT_KEY, 0);
        status.put("screen_time_event_at", eventAt > 0 ? eventAt : JSONObject.NULL);
        // Today's usage: the active profile's, and every profile's (so Home Assistant needn't keep a profile's last
        // post); cumulative for the TV's local day
        long now = System.currentTimeMillis();
        JSONObject usage = UsageToday.today(mContext, now);
        // Each profile's name beside its key, so Home Assistant can tell who's who without knowing the keys
        for (java.util.Iterator<String> keys = usage.keys(); keys.hasNext(); ) {
            String key = keys.next();
            JSONObject entry = usage.optJSONObject(key);
            if (entry != null) {
                entry.put("profile_name", nullable(ProfileUsers.displayName(mContext, key)));
                entry.put("profile_ref", nullable(ProfileUsers.householdRef(mContext, key)));
            }
        }
        status.put("profiles", profiles(usage, activeKey));
        JSONObject mine = usage.optJSONObject(String.valueOf(LauncherAccessibilityService.getActiveProfileKey(mContext)));
        status.put("day", UsageToday.day(now));
        status.put("seconds_today", mine != null ? mine.optLong("seconds") : 0);
        status.put("app_seconds_today", mine != null ? mine.optJSONObject(UsageToday.FRONT) : new JSONObject());
        status.put("playing_seconds_today", mine != null ? mine.optJSONObject(UsageToday.PLAYING) : new JSONObject());
        status.put("usage_today", usage);
        status.put("allowed_apps", kids ? allowedApps(mContext, pm) : JSONObject.NULL);
        status.put("app_categories", categories(pm, usage, s.foregroundPackage));
        // Hearth's own rules for the kids profiles, from before this TV was paired: Home Assistant takes them as each
        // kid's first budgets, once (the integration's Household.import_local_rules)
        JSONObject localRules = new JSONObject();
        java.util.Set<String> taken = LocalAllowance.takenByHomeAssistant(mContext);
        for (java.util.Map.Entry<String, JSONObject> rules : LocalAllowance.all(mContext).entrySet()) {
            if (!taken.contains(rules.getKey())) localRules.put(rules.getKey(), rules.getValue());
        }
        if (localRules.length() > 0) status.put("local_rules", localRules);

        String state = "idle";
        if (s.playback != null) {
            switch (s.playback.getState()) {
                case PlaybackState.STATE_PLAYING:
                case PlaybackState.STATE_BUFFERING:
                    state = "playing";
                    break;
                case PlaybackState.STATE_PAUSED:
                    state = "paused";
                    break;
                default:
                    state = "idle";
            }
        }
        if (!s.screenOn) state = "off";
        status.put("state", state);

        MediaMetadata metadata = s.metadata;
        status.put("media_app", s.mediaPackage == null ? JSONObject.NULL : label(pm, s.mediaPackage));
        status.put("media_title", nullable(text(metadata, MediaMetadata.METADATA_KEY_TITLE, MediaMetadata.METADATA_KEY_DISPLAY_TITLE)));
        status.put("media_artist", nullable(text(metadata, MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)));
        status.put("media_album", nullable(text(metadata, MediaMetadata.METADATA_KEY_ALBUM)));
        status.put("media_duration_s", metadata == null ? JSONObject.NULL
                : Math.max(0, metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) / 1000));
        status.put("now_playing_available", s.nowPlayingAvailable);
        status.put("pin_lockouts", HaParentPins.lockouts(mContext));
        // The parent PINs' hashes come in the answer only when they changed since these
        status.put("parent_pins_version", HaParentPins.version(mContext));
        return status;
    }

    private MediaController primaryController() {
        MediaController first = null;
        for (MediaController controller : mControllers) {
            PlaybackState state = controller.getPlaybackState();
            if (state != null && state.getState() == PlaybackState.STATE_PLAYING) return controller;
            if (first == null) first = controller;
        }
        return first;
    }

    private static String text(MediaMetadata metadata, String... keys) {
        if (metadata == null) return null;
        for (String key : keys) {
            CharSequence value = metadata.getText(key);
            if (value != null && value.length() > 0) return value.toString();
        }
        return null;
    }

    private static Object nullable(String value) {
        return value == null ? JSONObject.NULL : value;
    }

    private static String label(PackageManager pm, String packageName) {
        try {
            return pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString();
        } catch (PackageManager.NameNotFoundException e) {
            return packageName;
        }
    }

    /**
     * The apps a parent approved for this kids profile (also at bedtime, when Google TV blocks them all), Hearth
     * aside. Falls back to the apps Google TV hasn't blocked when the approvals can't be read.
     */
    private static JSONArray allowedApps(Context context, PackageManager pm) {
        String ownPackage = context.getPackageName();
        TreeSet<String> names = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        Set<String> approved = ProfileUsers.activeApprovedApps(context);
        if (approved != null) {
            for (String pkg : approved) {
                if (!ownPackage.equals(pkg)) names.add(label(pm, pkg));
            }
            return new JSONArray(names);
        }
        for (ResolveInfo info : ProfileUsers.launchables(pm)) {
            if ((info.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SUSPENDED) == 0
                    && !ownPackage.equals(info.activityInfo.packageName)) {
                names.add(label(pm, info.activityInfo.packageName));
            }
        }
        return new JSONArray(names);
    }

    /**
     * Android's category of each app in today's usage (and the one in front), for the integration's Video and Games.
     * A kids profile's apps that aren't installed for the TV's owner have none here.
     */
    private static JSONObject categories(PackageManager pm, JSONObject usage, String foreground) throws JSONException {
        TreeSet<String> packages = new TreeSet<>();
        if (foreground != null) packages.add(foreground);
        for (java.util.Iterator<String> keys = usage.keys(); keys.hasNext(); ) {
            JSONObject entry = usage.optJSONObject(keys.next());
            if (entry == null) continue;
            for (String part : new String[]{UsageToday.FRONT, UsageToday.PLAYING}) {
                JSONObject apps = entry.optJSONObject(part);
                if (apps == null) continue;
                for (java.util.Iterator<String> names = apps.keys(); names.hasNext(); ) packages.add(names.next());
            }
        }
        JSONObject categories = new JSONObject();
        for (String pkg : packages) {
            String category = HaIntegration.category(pm, pkg);
            if (category != null) categories.put(pkg, category);
        }
        return categories;
    }

    /**
     * Every profile this TV knows, by its key here: {"user:10": {"name", "ref", "kids"}}. Home Assistant maps
     * profiles by ref (the same on every TV) and answers with each key's limits and YouTube blocks, also for a kid who
     * hasn't used this TV today.
     */
    private JSONObject profiles(JSONObject usage, String activeKey) throws JSONException {
        java.util.Set<String> keys = new java.util.TreeSet<>(ProfilePairing.getHearthProfiles(mContext));
        for (java.util.Iterator<String> it = usage.keys(); it.hasNext(); ) keys.add(it.next());
        if (activeKey != null) keys.add(activeKey);
        JSONObject out = new JSONObject();
        for (String key : keys) {
            // Names saved before keys aren't profiles of their own any more
            if (ProfileUsers.serialOfKey(key) == ProfileUsers.UNKNOWN) continue;
            JSONObject entry = new JSONObject();
            entry.put("name", nullable(ProfileUsers.displayName(mContext, key)));
            entry.put("ref", nullable(ProfileUsers.householdRef(mContext, key)));
            entry.put("kids", ProfilePairing.isKids(mContext, key));
            out.put(key, entry);
        }
        return out;
    }

    /** Posts to the integration; its answer's limits become the profiles' allowance. */
    private void postToIntegration(String body) {
        HaIntegration.Answer answer = HaIntegration.postStatus(mContext, body);
        Log.d(TAG, "Status sent, the Hearth integration answered " + answer.code);
        if (answer.code == 200 && answer.body != null) {
            JSONObject state = answer.body.optJSONObject("state");
            mStateVersion = state != null ? state.optString("version", null) : null;
            HaAllowance.fromDocument(mContext, state);
            LocalAllowance.noteTaken(mContext, answer.body.optJSONArray("local_rules_taken"));
            // A parent's YouTube blocks set in Home Assistant, for HearthTube in the kids profiles
            ParentBlocks.applyDocument(mContext, state);
            // The adults' parent PINs, which are this TV's while Home Assistant names them
            HaParentPins.applyDocument(mContext, state);
            mHandler.post(() -> {
                ProfileProvider.notifyChanged(mContext);
                // A pause, a lock, the next bedtime or a request's answer may have changed
                BedtimeHeadsUp.schedule(mContext);
                MainActivity.notifyHaStateChanged();
            });
            // And up: what kids profiles started since
            HaIntegration.sendStartedLog(mContext);
            return;
        }
        // Retry with the next change or heartbeat
        mLastSent = null;
        if (answer.code == 401) mHandler.post(() -> HaBridgeService.sync(mContext));
    }

}
