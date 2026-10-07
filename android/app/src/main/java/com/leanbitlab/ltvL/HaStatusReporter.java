package com.leanbitlab.ltvL;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Pushes what the TV is doing to a Home Assistant webhook: foreground app, now playing (from any app's media
 * session, which needs notification access), Google TV profile, kids profile, screen time lock, screen on/off.
 * Sent on change (debounced) and as a heartbeat, so Home Assistant needs no credentials for the TV.
 */
final class HaStatusReporter {
    static final String URL_KEY = "ha_base_url";
    static final String WEBHOOK_KEY = "ha_webhook_id";
    private static final String TAG = "LTvHaStatus";
    private static final long DEBOUNCE_MS = 1_500;
    private static final long HEARTBEAT_MS = 10 * 60_000;

    private final Context mContext;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService mSender = Executors.newSingleThreadExecutor();
    private final List<MediaController> mControllers = new ArrayList<>();
    private MediaSessionManager mSessionManager;
    private String mForegroundPackage;
    private boolean mScreenOn = true;
    private boolean mScreenTimeLock = false;
    private ScreenTimeScreen mScreenTime;
    private long mScreenTimeSeenAt;
    private String mLastSent;

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
    private final Runnable mSend = this::send;
    private final Runnable mHeartbeat = new Runnable() {
        @Override
        public void run() {
            mLastSent = null; // force
            send();
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
        android.content.SharedPreferences prefs =
                context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
        String base = prefs.getString(URL_KEY, null);
        String id = prefs.getString(WEBHOOK_KEY, null);
        if (base == null || base.trim().isEmpty() || id == null || id.trim().isEmpty()) return null;
        base = base.trim();
        if (!base.startsWith("http://") && !base.startsWith("https://")) base = "http://" + base;
        if (base.endsWith("/")) base = base.substring(0, base.length() - 1);
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
        mHandler.removeCallbacks(mSend);
        if (mSessionManager != null) {
            try {
                mSessionManager.removeOnActiveSessionsChangedListener(mSessionsListener);
            } catch (Exception ignored) {
            }
            mSessionManager = null;
        }
        setControllers(null);
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

    private void send() {
        String url = webhookUrl(mContext);
        if (url == null) return;
        String body;
        try {
            body = buildStatus().toString();
        } catch (JSONException e) {
            return;
        }
        if (body.equals(mLastSent)) return;
        mLastSent = body;
        mSender.execute(() -> post(url, body));
    }

    JSONObject buildStatus() throws JSONException {
        JSONObject status = new JSONObject();
        PackageManager pm = mContext.getPackageManager();
        status.put("screen", mScreenOn ? "on" : "off");
        status.put("app_package", mForegroundPackage == null ? JSONObject.NULL : mForegroundPackage);
        status.put("app", mForegroundPackage == null ? JSONObject.NULL : label(pm, mForegroundPackage));
        status.put("profile", nullable(LauncherAccessibilityService.getActiveProfileName(mContext)));
        boolean kids = ProfileUsers.isKids(mContext);
        status.put("kids_profile", kids);
        status.put("screen_time_up", mScreenTimeLock);
        // Minutes are as Google TV stated them at screen_time_seen_at (epoch ms); Home Assistant can count down.
        // screen_time_text is Google TV's own wording, so what it says can be checked against the parsing.
        status.put("screen_time_reason", mScreenTime == null ? JSONObject.NULL : mScreenTime.reason.id);
        status.put("screen_time_minutes_left", mScreenTime == null || mScreenTime.minutesLeft == null
                ? JSONObject.NULL : mScreenTime.minutesLeft);
        status.put("screen_time_text", mScreenTime == null ? JSONObject.NULL : mScreenTime.text);
        status.put("screen_time_seen_at", mScreenTime == null ? JSONObject.NULL : mScreenTimeSeenAt);
        status.put("screen_time_unlocks_at", mScreenTime == null ? JSONObject.NULL : nullable(mScreenTime.unlocksAt));
        status.put("allowed_apps", kids ? allowedApps(pm, mContext.getPackageName()) : JSONObject.NULL);

        MediaController playing = primaryController();
        String state = "idle";
        if (playing != null && playing.getPlaybackState() != null) {
            switch (playing.getPlaybackState().getState()) {
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
        if (!mScreenOn) state = "off";
        status.put("state", state);

        MediaMetadata metadata = playing != null ? playing.getMetadata() : null;
        status.put("media_app", playing == null ? JSONObject.NULL : label(pm, playing.getPackageName()));
        status.put("media_title", nullable(text(metadata, MediaMetadata.METADATA_KEY_TITLE, MediaMetadata.METADATA_KEY_DISPLAY_TITLE)));
        status.put("media_artist", nullable(text(metadata, MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)));
        status.put("media_album", nullable(text(metadata, MediaMetadata.METADATA_KEY_ALBUM)));
        status.put("media_duration_s", metadata == null ? JSONObject.NULL
                : Math.max(0, metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) / 1000));
        status.put("now_playing_available", mSessionManager != null);
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

    /** Google TV kids profiles suspend every app a parent hasn't approved. */
    /** The apps this kids profile can open: every launchable app Google TV hasn't suspended, Hearth aside. */
    private static JSONArray allowedApps(PackageManager pm, String ownPackage) {
        java.util.TreeSet<String> names = new java.util.TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        for (String category : new String[]{Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER}) {
            Intent intent = new Intent(Intent.ACTION_MAIN).addCategory(category);
            for (ResolveInfo info : pm.queryIntentActivities(intent, 0)) {
                if ((info.activityInfo.applicationInfo.flags & ApplicationInfo.FLAG_SUSPENDED) == 0
                        && !ownPackage.equals(info.activityInfo.packageName)) {
                    names.add(label(pm, info.activityInfo.packageName));
                }
            }
        }
        return new JSONArray(names);
    }

    private void post(String url, String body) {
        HttpURLConnection connection = null;
        try {
            URL target = new URL(url);
            // Plain HTTP only inside the home network; anything on the internet must use HTTPS
            if ("http".equalsIgnoreCase(target.getProtocol())
                    && !HaNotificationServer.isLocal(java.net.InetAddress.getByName(target.getHost()))) {
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
                mHandler.post(() -> mLastSent = null);
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't reach Home Assistant: " + e.getMessage());
            // Retry with the next change or heartbeat
            mHandler.post(() -> mLastSent = null);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
