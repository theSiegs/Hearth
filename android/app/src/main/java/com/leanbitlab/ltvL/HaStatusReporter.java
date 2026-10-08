package com.leanbitlab.ltvL;

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

/**
 * Pushes what the TV is doing to a Home Assistant webhook: foreground app, now playing (from any app's media
 * session, which needs notification access), Google TV profile, kids profile, screen time lock, screen on/off.
 * Sent on change (debounced) and as a heartbeat, so Home Assistant needs no credentials for the TV.
 */
final class HaStatusReporter {
    // HaConfig's keys, under the names the activity and the accessibility service use
    static final String URL_KEY = HaConfig.URL_KEY;
    static final String WEBHOOK_KEY = HaConfig.WEBHOOK_KEY;
    private static final String TAG = "HearthHaStatus";
    private static final long DEBOUNCE_MS = 1_500;
    private static final long HEARTBEAT_MS = 10 * 60_000;

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
            mHandler.postDelayed(this, HEARTBEAT_MS);
        }
    };

    HaStatusReporter(Context context) {
        mContext = context;
    }

    static boolean isConfigured(Context context) {
        return webhookUrl(context) != null;
    }

    static String webhookUrl(Context context) {
        String base = HaConfig.baseUrl(context);
        String id = HaConfig.prefs(context).getString(HaConfig.WEBHOOK_KEY, null);
        if (base == null || id == null || id.trim().isEmpty()) return null;
        return base + "/api/webhook/" + id.trim();
    }

    void start() {
        stop();
        if (!isConfigured(mContext)) {
            Log.i(TAG, "Status reporting off (no Home Assistant address/webhook)");
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
    }

    void stop() {
        mHandler.removeCallbacks(mHeartbeat);
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
    }

    void setScreenTimeLock(boolean locked) {
        if (locked != mScreenTimeLock) {
            mScreenTimeLock = locked;
            scheduleSend();
        }
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
        String url = webhookUrl(mContext);
        if (url == null) return;
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
            post(url, body);
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
        boolean kids = ProfileUsers.isKids(mContext);
        status.put("kids_profile", kids);
        status.put("screen_time_up", s.screenTimeLock);
        // Minutes are as Google TV stated them at screen_time_seen_at (epoch ms); Home Assistant can count down.
        // screen_time_text is Google TV's own wording, so what it says can be checked against the parsing.
        ScreenTimeScreen screenTime = s.screenTime;
        status.put("screen_time_reason", screenTime == null ? JSONObject.NULL : screenTime.reason.id);
        status.put("screen_time_minutes_left", screenTime == null || screenTime.minutesLeft == null
                ? JSONObject.NULL : screenTime.minutesLeft);
        status.put("screen_time_text", screenTime == null ? JSONObject.NULL : screenTime.text);
        status.put("screen_time_seen_at", screenTime == null ? JSONObject.NULL : s.screenTimeSeenAt);
        status.put("screen_time_unlocks_at", screenTime == null ? JSONObject.NULL : nullable(screenTime.unlocksAt));
        status.put("allowed_apps", kids ? allowedApps(mContext, pm) : JSONObject.NULL);

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

    private void post(String url, String body) {
        HttpURLConnection connection = null;
        try {
            URL target = new URL(url);
            if (!LocalNet.allows(target)) {
                Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
                return;
            }
            connection = (HttpURLConnection) target.openConnection();
            connection.setConnectTimeout(5_000);
            connection.setReadTimeout(5_000);
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            try (OutputStream out = connection.getOutputStream()) {
                out.write(body.getBytes(StandardCharsets.UTF_8));
            }
            int code = connection.getResponseCode();
            Log.d(TAG, "Status sent, Home Assistant answered " + code);
            if (code >= 300) {
                Log.w(TAG, "Home Assistant webhook returned " + code);
                mLastSent = null;
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't reach Home Assistant: " + e.getMessage());
            // Retry with the next change or heartbeat
            mLastSent = null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
