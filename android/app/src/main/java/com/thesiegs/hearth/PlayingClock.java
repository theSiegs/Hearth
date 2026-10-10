package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.SystemClock;

import java.util.ArrayList;
import java.util.List;

/**
 * How long apps' media sessions play, in this user (UsageToday's "playing"): handed to a sink as each stretch of
 * playing ends, and so far whenever {@link #flush} is called. Android shows other apps' sessions only to an enabled
 * notification listener, and only the listener's own user's: Hearth counts the owner's user, and Hearth's agent in a
 * kids profile's user counts that one if it has notification access there.
 */
final class PlayingClock {
    /** Where the played time goes: this app played for ms, ending now (wall clock). */
    interface Sink {
        void played(String packageName, long ms, long now);
    }

    private final Context mContext;
    private final Handler mHandler;
    private final Sink mSink;
    private final List<Session> mSessions = new ArrayList<>();
    private MediaSessionManager mManager;
    private final MediaSessionManager.OnActiveSessionsChangedListener mListener = this::setControllers;

    PlayingClock(Context context, Handler handler, Sink sink) {
        mContext = context;
        mHandler = handler;
        mSink = sink;
    }

    /** Starts counting if it isn't and notification access allows it; false without access (try again later). */
    boolean ensureStarted() {
        if (mManager != null) return true;
        MediaSessionManager manager = (MediaSessionManager) mContext.getSystemService(Context.MEDIA_SESSION_SERVICE);
        if (manager == null) return false;
        ComponentName listener = new ComponentName(mContext, LauncherNotificationListenerService.class);
        try {
            manager.addOnActiveSessionsChangedListener(mListener, listener, mHandler);
            mManager = manager;
            setControllers(manager.getActiveSessions(listener));
            return true;
        } catch (SecurityException e) {
            return false;
        }
    }

    void stop() {
        if (mManager != null) {
            try {
                mManager.removeOnActiveSessionsChangedListener(mListener);
            } catch (RuntimeException ignored) {
            }
            mManager = null;
        }
        setControllers(null);
    }

    /** Hands over the time played so far by sessions that are still playing. */
    void flush() {
        for (Session session : mSessions) session.flush(false);
    }

    private void setControllers(List<MediaController> controllers) {
        List<Session> before = new ArrayList<>(mSessions);
        mSessions.clear();
        if (controllers != null) {
            for (MediaController controller : controllers) {
                String pkg = controller.getPackageName();
                // HearthTube reports its own playing time (exactly, also in a kids profile's user)
                if (pkg == null || pkg.equals(mContext.getPackageName()) || CompanionApps.HEARTHTUBE.equals(pkg)
                        || LauncherAccessibilityService.GOOGLE_TV_PACKAGE.equals(pkg)) {
                    continue;
                }
                Session kept = null;
                for (Session session : before) {
                    if (session.mController.getSessionToken().equals(controller.getSessionToken())) kept = session;
                }
                if (kept != null) {
                    before.remove(kept);
                    mSessions.add(kept);
                    continue;
                }
                Session session = new Session(controller);
                controller.registerCallback(session, mHandler);
                mSessions.add(session);
                session.onPlaybackStateChanged(controller.getPlaybackState());
            }
        }
        for (Session gone : before) gone.close();
    }

    private final class Session extends MediaController.Callback {
        private final MediaController mController;
        /** When it started playing (elapsed realtime), 0 when it isn't. */
        private long mPlayingSince;

        Session(MediaController controller) {
            mController = controller;
        }

        @Override
        public void onPlaybackStateChanged(PlaybackState state) {
            boolean playing = state != null && state.getState() == PlaybackState.STATE_PLAYING;
            if (playing && mPlayingSince == 0) {
                mPlayingSince = SystemClock.elapsedRealtime();
            } else if (!playing && mPlayingSince != 0) {
                flush(true);
            }
        }

        @Override
        public void onSessionDestroyed() {
            flush(true);
        }

        /** Hands over the time since it started playing (or since the last flush); stopped: it isn't playing now. */
        void flush(boolean stopped) {
            if (mPlayingSince == 0) return;
            long now = SystemClock.elapsedRealtime();
            mSink.played(mController.getPackageName(), now - mPlayingSince, System.currentTimeMillis());
            mPlayingSince = stopped ? 0 : now;
        }

        void close() {
            flush(true);
            try {
                mController.unregisterCallback(this);
            } catch (RuntimeException ignored) {
            }
        }
    }
}
