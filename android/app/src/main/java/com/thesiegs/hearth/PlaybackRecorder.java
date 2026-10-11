package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Records what plays on the TV into the active grown-up profile's watch history (WatchHistory), from the apps'
 * media sessions: their title and episode, how long it is and how far it got. Only what plays for a while counts,
 * so trailers and previews that start by themselves mostly don't. Needs Hearth's notification access, as Android
 * only shows other apps' media sessions to a notification listener; a kids profile's apps play in its own user,
 * which Hearth's sessions don't see.
 */
final class PlaybackRecorder {
    private static final String TAG = "HearthWatchNext";
    /** Played this long, it counts as watched. */
    static final long COUNTS_AFTER_MS = 60_000;
    /** While it plays, where it's got to is saved this often. */
    private static final long SAVE_EVERY_MS = 30_000;
    /** Media apps that aren't for watching. */
    private static final Set<String> NOT_WATCHING = new HashSet<>(Arrays.asList(
            LauncherAccessibilityService.GOOGLE_TV_PACKAGE,
            "com.google.android.youtube.tvmusic"));

    private final Context mContext;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService mWriter = Executors.newSingleThreadExecutor(r -> new Thread(r, "HearthHistory"));
    private final List<Tracker> mTrackers = new ArrayList<>();
    private MediaSessionManager mSessions;
    private final MediaSessionManager.OnActiveSessionsChangedListener mListener = this::setControllers;

    PlaybackRecorder(Context context) {
        mContext = context;
    }

    /** Starts listening, if it isn't and Hearth has notification access; false without it (try again later). */
    boolean ensureStarted() {
        if (mSessions != null) return true;
        MediaSessionManager sessions = (MediaSessionManager) mContext.getSystemService(Context.MEDIA_SESSION_SERVICE);
        if (sessions == null) return false;
        ComponentName listener = new ComponentName(mContext, LauncherNotificationListenerService.class);
        try {
            sessions.addOnActiveSessionsChangedListener(mListener, listener, mHandler);
            mSessions = sessions;
            setControllers(sessions.getActiveSessions(listener));
            Log.i(TAG, "Recording what plays, for each profile's watch history");
            return true;
        } catch (SecurityException e) {
            return false;
        }
    }

    void stop() {
        if (mSessions != null) {
            try {
                mSessions.removeOnActiveSessionsChangedListener(mListener);
            } catch (RuntimeException ignored) {
            }
            mSessions = null;
        }
        setControllers(null);
        mWriter.shutdown();
    }

    private void setControllers(List<MediaController> controllers) {
        List<Tracker> before = new ArrayList<>(mTrackers);
        mTrackers.clear();
        if (controllers != null) {
            for (MediaController controller : controllers) {
                if (!isForWatching(controller.getPackageName())) continue;
                // A session still there keeps its tracker (and how long it has played)
                Tracker kept = null;
                for (Tracker tracker : before) {
                    if (tracker.mController.getSessionToken().equals(controller.getSessionToken())) kept = tracker;
                }
                if (kept != null) {
                    before.remove(kept);
                    mTrackers.add(kept);
                    continue;
                }
                Tracker tracker = new Tracker(controller);
                controller.registerCallback(tracker, mHandler);
                mTrackers.add(tracker);
                tracker.onMetadataChanged(controller.getMetadata());
                tracker.onPlaybackStateChanged(controller.getPlaybackState());
            }
        }
        for (Tracker gone : before) gone.close();
    }

    /** An app people watch things in: one with a home-screen icon, not Hearth, Google TV or a music app. */
    private boolean isForWatching(String packageName) {
        if (packageName == null || packageName.equals(mContext.getPackageName()) || NOT_WATCHING.contains(packageName)) {
            return false;
        }
        PackageManager pm = mContext.getPackageManager();
        if (pm.getLeanbackLaunchIntentForPackage(packageName) == null && pm.getLaunchIntentForPackage(packageName) == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                ApplicationInfo info = pm.getApplicationInfo(packageName, 0);
                if (info.category == ApplicationInfo.CATEGORY_AUDIO) return false;
            } catch (PackageManager.NameNotFoundException e) {
                return false;
            }
        }
        return true;
    }

    /** The profile whose history this goes into: the active one, if it's a grown-up's in Hearth's own user. */
    private String profile() {
        String key = LauncherAccessibilityService.getActiveProfileKey(mContext);
        if (key == null || ProfileUsers.serialOfKey(key) != ProfileUsers.ownerSerial(mContext)) return null;
        return ProfileUsers.isKids(mContext) ? null : key;
    }

    /** One app's media session: what it plays, and for how long. */
    private final class Tracker extends MediaController.Callback {
        private final MediaController mController;
        private String mTitle;
        private String mSubtitle;
        private long mDuration;
        /** How long this title has played (not counting now, if it's playing). */
        private long mPlayedMs;
        /** When it started playing (elapsed realtime), 0 when it isn't. */
        private long mPlayingSince;
        /** The profile it counted for, once it has played long enough. */
        private String mProfile;
        private final Runnable mSave = new Runnable() {
            @Override
            public void run() {
                check();
                mHandler.postDelayed(this, SAVE_EVERY_MS);
            }
        };

        Tracker(MediaController controller) {
            mController = controller;
        }

        @Override
        public void onMetadataChanged(MediaMetadata metadata) {
            String title = text(metadata, MediaMetadata.METADATA_KEY_TITLE, MediaMetadata.METADATA_KEY_DISPLAY_TITLE);
            String subtitle = text(metadata, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE,
                    MediaMetadata.METADATA_KEY_ARTIST);
            long duration = metadata != null ? metadata.getLong(MediaMetadata.METADATA_KEY_DURATION) : 0;
            if (duration > 0) mDuration = duration;
            if (eq(title, mTitle) && eq(subtitle, mSubtitle)) return;
            // Something else now: what played before is saved as it stood
            check();
            noteIfUncounted();
            boolean playing = mPlayingSince != 0;
            mTitle = title;
            mSubtitle = subtitle;
            mDuration = Math.max(0, duration);
            mPlayedMs = 0;
            mProfile = null;
            mPlayingSince = playing ? SystemClock.elapsedRealtime() : 0;
        }

        @Override
        public void onPlaybackStateChanged(PlaybackState state) {
            boolean playing = state != null && state.getState() == PlaybackState.STATE_PLAYING;
            long now = SystemClock.elapsedRealtime();
            if (playing && mPlayingSince == 0) {
                mPlayingSince = now;
                mHandler.removeCallbacks(mSave);
                mHandler.postDelayed(mSave, SAVE_EVERY_MS);
            } else if (!playing && mPlayingSince != 0) {
                mPlayedMs += now - mPlayingSince;
                mPlayingSince = 0;
                mHandler.removeCallbacks(mSave);
            }
            check();
        }

        @Override
        public void onSessionDestroyed() {
            close();
        }

        /** Counts it once it has played long enough, and saves where it has got to. */
        private void check() {
            if (mTitle == null) return;
            long played = mPlayedMs + (mPlayingSince != 0 ? SystemClock.elapsedRealtime() - mPlayingSince : 0);
            if (mProfile == null) {
                if (played < COUNTS_AFTER_MS) return;
                mProfile = profile();
                if (mProfile == null) return;
                Log.i(TAG, "Watching in " + mController.getPackageName() + " for " + mProfile + ": " + mTitle
                        + (mSubtitle != null ? " / " + mSubtitle : ""));
            }
            final String profile = mProfile, pkg = mController.getPackageName(), title = mTitle, subtitle = mSubtitle;
            final long duration = mDuration, position = position(mController.getPlaybackState());
            final long now = System.currentTimeMillis();
            try {
                mWriter.execute(() -> WatchHistory.get(mContext)
                        .recordPlay(profile, pkg, title, subtitle, duration, position, now));
            } catch (RuntimeException ignored) {
                // Stopping
            }
        }

        /** In the log (no title): something played, but not long enough to count, or with no profile to count for. */
        private void noteIfUncounted() {
            if (mTitle == null || mProfile != null) return;
            long played = mPlayedMs + (mPlayingSince != 0 ? SystemClock.elapsedRealtime() - mPlayingSince : 0);
            if (played <= 0) return;
            Log.i(TAG, "Not counted in " + mController.getPackageName() + ": played " + played / 1000 + " s"
                    + (played < COUNTS_AFTER_MS ? " (counts after " + COUNTS_AFTER_MS / 1000 + " s)"
                    : ", no grown-up's profile on"));
        }

        void close() {
            check();
            noteIfUncounted();
            mHandler.removeCallbacks(mSave);
            try {
                mController.unregisterCallback(this);
            } catch (RuntimeException ignored) {
            }
        }
    }

    /** Where playback has got to now, from the session's last report. */
    static long position(PlaybackState state) {
        if (state == null || state.getPosition() < 0) return 0;
        long position = state.getPosition();
        if (state.getState() == PlaybackState.STATE_PLAYING && state.getLastPositionUpdateTime() > 0) {
            long since = SystemClock.elapsedRealtime() - state.getLastPositionUpdateTime();
            position += (long) (since * state.getPlaybackSpeed());
        }
        return Math.max(0, position);
    }

    private static String text(MediaMetadata metadata, String... keys) {
        if (metadata == null) return null;
        for (String key : keys) {
            CharSequence value = metadata.getText(key);
            if (value != null && value.toString().trim().length() > 0) return value.toString().trim();
        }
        return null;
    }

    private static boolean eq(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }
}
