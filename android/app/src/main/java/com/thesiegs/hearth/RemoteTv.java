package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.LauncherActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.os.UserHandle;
import android.os.UserManager;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * The TV for the remote API ({@link RemoteSession.Tv}), in the TV owner's user: the media sessions it sees (through
 * Hearth's notification access), the volume, the app in front and the active profile. A kids profile is another
 * Android user, whose media sessions this user can't see or control: there the state carries what Hearth's agent last
 * reported playing (title, position) with no actions, and apps open through the agent.
 */
final class RemoteTv implements RemoteSession.Tv {
    /** A kids profile's report counts as playing for this long after it was sent. */
    private static final long AGENT_PLAYED_FRESH_MS = 2 * 60 * 1000;
    private static final int ART_SIZE = 320;

    private final Context mContext;
    private final Runnable mOnChange;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final List<MediaController> mControllers = new CopyOnWriteArrayList<>();
    private MediaSessionManager mSessions;
    private String mArtId;
    private byte[] mArt;

    private final MediaSessionManager.OnActiveSessionsChangedListener mSessionsListener = this::setControllers;

    private final MediaController.Callback mCallback = new MediaController.Callback() {
        @Override
        public void onPlaybackStateChanged(PlaybackState state) {
            mOnChange.run();
        }

        @Override
        public void onMetadataChanged(MediaMetadata metadata) {
            mOnChange.run();
        }

        @Override
        public void onSessionDestroyed() {
            mOnChange.run();
        }

        @Override
        public void onAudioInfoChanged(MediaController.PlaybackInfo info) {
            mOnChange.run();
        }
    };

    RemoteTv(Context context, Runnable onChange) {
        mContext = context.getApplicationContext();
        mOnChange = onChange;
    }

    /** Follows the media sessions (main thread). Without notification access, states carry no now playing. */
    void start() {
        mSessions = (MediaSessionManager) mContext.getSystemService(Context.MEDIA_SESSION_SERVICE);
        ComponentName listener = new ComponentName(mContext, LauncherNotificationListenerService.class);
        try {
            mSessions.addOnActiveSessionsChangedListener(mSessionsListener, listener, mMain);
            setControllers(mSessions.getActiveSessions(listener));
        } catch (SecurityException e) {
            mSessions = null;
        }
    }

    void stop() {
        if (mSessions != null) {
            try {
                mSessions.removeOnActiveSessionsChangedListener(mSessionsListener);
            } catch (RuntimeException ignored) {
            }
            mSessions = null;
        }
        setControllers(null);
    }

    private void setControllers(List<MediaController> controllers) {
        for (MediaController c : mControllers) c.unregisterCallback(mCallback);
        mControllers.clear();
        if (controllers != null) {
            for (MediaController c : controllers) {
                c.registerCallback(mCallback, mMain);
                mControllers.add(c);
            }
        }
        mOnChange.run();
    }

    /** The session shown as now playing: the playing one, else the first. */
    private MediaController controller() {
        MediaController first = null;
        for (MediaController c : mControllers) {
            PlaybackState state = c.getPlaybackState();
            if (state != null && state.getState() == PlaybackState.STATE_PLAYING) return c;
            if (first == null) first = c;
        }
        return first;
    }

    /** The active profile's user serial when it's another user's (a kids profile), else -1. */
    private long otherSerial() {
        String key = LauncherAccessibilityService.getActiveProfileKey(mContext);
        if (key == null) return -1;
        long serial = ProfileUsers.serialOfKey(key);
        return serial >= 0 && serial != ProfileUsers.ownerSerial(mContext) ? serial : -1;
    }

    @Override
    public JSONObject state() {
        JSONObject s = new JSONObject();
        try {
            PowerManager power = (PowerManager) mContext.getSystemService(Context.POWER_SERVICE);
            s.put("on", power != null && power.isInteractive());
            s.put("profile", nullable(LauncherAccessibilityService.getActiveProfileName(mContext)));
            s.put("kid", ProfileUsers.isKids(mContext));
            String app = HaBridgeService.lastForegroundPackage();
            s.put("app", nullable(app));
            s.put("appLabel", nullable(app == null ? null : label(app)));
            putMedia(s);
            AudioManager audio = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
            if (audio != null) {
                int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                int now = audio.getStreamVolume(AudioManager.STREAM_MUSIC);
                boolean fixed = audio.isVolumeFixed();
                s.put("volume", fixed || max <= 0 ? JSONObject.NULL : Math.round(now * 100f / max));
                s.put("muted", audio.isStreamMute(AudioManager.STREAM_MUSIC));
                s.put("volumeSettable", !fixed);
            } else {
                s.put("volume", JSONObject.NULL).put("muted", false).put("volumeSettable", false);
            }
        } catch (JSONException e) {
            throw new IllegalStateException(e);
        }
        return s;
    }

    private void putMedia(JSONObject s) throws JSONException {
        JSONObject actions = new JSONObject().put("seek", false).put("next", false).put("prev", false)
                .put("playPause", false);
        long serial = otherSerial();
        if (serial >= 0) {
            AgentHub.LastPlayed last = AgentHub.lastPlayed(serial);
            boolean fresh = last != null && System.currentTimeMillis() - last.at < AGENT_PLAYED_FRESH_MS;
            s.put("title", fresh ? last.played.title : JSONObject.NULL);
            s.put("subtitle", fresh ? nullable(last.played.subtitle) : JSONObject.NULL);
            s.put("artId", JSONObject.NULL);
            s.put("playing", fresh);
            s.put("positionMs", fresh ? last.played.positionMs : JSONObject.NULL);
            s.put("durationMs", fresh && last.played.durationMs > 0 ? last.played.durationMs : JSONObject.NULL);
            s.put("positionAtMs", fresh ? last.at : JSONObject.NULL);
            s.put("speed", fresh ? 1.0 : 0.0);
            s.put("actions", actions);
            return;
        }
        MediaController c = controller();
        PlaybackState playback = c == null ? null : c.getPlaybackState();
        MediaMetadata metadata = c == null ? null : c.getMetadata();
        String title = text(metadata, MediaMetadata.METADATA_KEY_DISPLAY_TITLE, MediaMetadata.METADATA_KEY_TITLE);
        s.put("title", nullable(title));
        s.put("subtitle", nullable(text(metadata, MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE,
                MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_ALBUM)));
        s.put("artId", nullable(artId(c, metadata, title)));
        boolean playing = playback != null && playback.getState() == PlaybackState.STATE_PLAYING;
        s.put("playing", playing);
        long duration = metadata == null ? 0 : metadata.getLong(MediaMetadata.METADATA_KEY_DURATION);
        s.put("durationMs", duration > 0 ? duration : JSONObject.NULL);
        if (playback != null && playback.getPosition() >= 0
                && playback.getState() != PlaybackState.STATE_NONE && playback.getState() != PlaybackState.STATE_STOPPED) {
            // The session's position was true at its last update (elapsed realtime): as the TV's wall clock
            long at = System.currentTimeMillis() - (SystemClock.elapsedRealtime() - playback.getLastPositionUpdateTime());
            s.put("positionMs", playback.getPosition());
            s.put("positionAtMs", at);
            s.put("speed", playing ? playback.getPlaybackSpeed() : 0.0);
        } else {
            s.put("positionMs", JSONObject.NULL).put("positionAtMs", JSONObject.NULL).put("speed", 0.0);
        }
        if (playback != null) {
            long a = playback.getActions();
            actions.put("seek", (a & PlaybackState.ACTION_SEEK_TO) != 0);
            actions.put("next", (a & PlaybackState.ACTION_SKIP_TO_NEXT) != 0);
            actions.put("prev", (a & PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0);
            actions.put("playPause", (a & (PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_PAUSE
                    | PlaybackState.ACTION_PLAY)) != 0);
        }
        s.put("actions", actions);
    }

    /** The art's id: changes with the title (the art itself is read only when a phone asks for it). */
    private String artId(MediaController c, MediaMetadata metadata, String title) {
        if (metadata == null || title == null) return null;
        Bitmap art = art(metadata);
        if (art == null) return null;
        return Integer.toHexString((c.getPackageName() + "\n" + title).hashCode());
    }

    private static Bitmap art(MediaMetadata metadata) {
        Bitmap art = metadata.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if (art == null) art = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if (art == null) art = metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON);
        return art;
    }

    @Override
    public synchronized byte[] art(String id) {
        if (id.equals(mArtId)) return mArt;
        MediaController c = controller();
        MediaMetadata metadata = c == null ? null : c.getMetadata();
        String title = text(metadata, MediaMetadata.METADATA_KEY_DISPLAY_TITLE, MediaMetadata.METADATA_KEY_TITLE);
        if (!id.equals(artId(c, metadata, title))) return null;
        Bitmap art = art(metadata);
        float scale = Math.min(1f, (float) ART_SIZE / Math.max(art.getWidth(), art.getHeight()));
        Bitmap small = scale < 1f ? Bitmap.createScaledBitmap(art, Math.round(art.getWidth() * scale),
                Math.round(art.getHeight() * scale), true) : art;
        byte[] jpeg = null;
        for (int quality = 85; quality >= 40; quality -= 15) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            small.compress(Bitmap.CompressFormat.JPEG, quality, out);
            jpeg = out.toByteArray();
            if (jpeg.length <= RemoteSession.MAX_ART) break;
        }
        mArtId = id;
        mArt = jpeg != null && jpeg.length <= RemoteSession.MAX_ART ? jpeg : null;
        return mArt;
    }

    @Override
    public void media(String action) throws RemoteSession.Refused {
        MediaController.TransportControls t = controls();
        switch (action) {
            case "play": t.play(); break;
            case "pause": t.pause(); break;
            case "stop": t.stop(); break;
            case "next": t.skipToNext(); break;
            case "prev": t.skipToPrevious(); break;
            default: {
                PlaybackState state = controller().getPlaybackState();
                if (state != null && state.getState() == PlaybackState.STATE_PLAYING) t.pause(); else t.play();
            }
        }
    }

    @Override
    public void seekTo(long positionMs) throws RemoteSession.Refused {
        MediaController.TransportControls t = controls();
        PlaybackState state = controller().getPlaybackState();
        if (state == null || (state.getActions() & PlaybackState.ACTION_SEEK_TO) == 0) {
            throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        }
        long duration = 0;
        MediaMetadata metadata = controller().getMetadata();
        if (metadata != null) duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION);
        t.seekTo(duration > 0 ? Math.min(positionMs, duration) : positionMs);
    }

    @Override
    public void seekBy(long deltaMs) throws RemoteSession.Refused {
        controls();
        PlaybackState state = controller().getPlaybackState();
        if (state == null || state.getPosition() < 0) throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        long now = state.getPosition();
        if (state.getState() == PlaybackState.STATE_PLAYING) {
            now += (long) ((SystemClock.elapsedRealtime() - state.getLastPositionUpdateTime())
                    * state.getPlaybackSpeed());
        }
        seekTo(Math.max(0, now + deltaMs));
    }

    /** The now playing session's controls; refused while a kids profile (another user) or nothing plays. */
    private MediaController.TransportControls controls() throws RemoteSession.Refused {
        if (otherSerial() >= 0) throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        MediaController c = controller();
        if (c == null) throw new RemoteSession.Refused(RemoteSession.NO_SESSION);
        return c.getTransportControls();
    }

    @Override
    public void launch(String pkg) throws RemoteSession.Refused {
        if (pkg.equals(mContext.getPackageName())) {
            // Hearth itself: its home
            Intent home = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).setPackage(pkg);
            startOwner(home);
            return;
        }
        long serial = otherSerial();
        if (serial >= 0) {
            UserManager users = (UserManager) mContext.getSystemService(Context.USER_SERVICE);
            UserHandle user = users == null ? null : users.getUserForSerialNumber(serial);
            Set<String> approved = ProfileUsers.approvedApps(mContext, serial);
            if (user == null || approved == null || !approved.contains(pkg)) {
                throw new RemoteSession.Refused(RemoteSession.NOT_ALLOWED);
            }
            Intent intent = launchIntent(pkg);
            if (intent == null || !AgentHub.open(mContext, serial, user, intent.toUri(Intent.URI_INTENT_SCHEME))) {
                throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
            }
            return;
        }
        Intent intent = launchIntent(pkg);
        if (intent == null) throw new RemoteSession.Refused(RemoteSession.BAD_REQUEST);
        startOwner(intent);
    }

    private Intent launchIntent(String pkg) {
        PackageManager pm = mContext.getPackageManager();
        Intent intent = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (intent == null) intent = pm.getLaunchIntentForPackage(pkg);
        return intent;
    }

    private void startOwner(Intent intent) throws RemoteSession.Refused {
        try {
            mContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (RuntimeException e) {
            // Android may refuse a start from the background: open it through the accessibility service then
            throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        }
    }

    @Override
    public void volumeSet(int percent) throws RemoteSession.Refused {
        AudioManager audio = audio();
        int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(percent * max / 100f), 0);
    }

    @Override
    public void volumeStep(int direction) throws RemoteSession.Refused {
        audio().adjustStreamVolume(AudioManager.STREAM_MUSIC,
                direction > 0 ? AudioManager.ADJUST_RAISE : AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI);
    }

    @Override
    public void mute(boolean muted) throws RemoteSession.Refused {
        audio().adjustStreamVolume(AudioManager.STREAM_MUSIC,
                muted ? AudioManager.ADJUST_MUTE : AudioManager.ADJUST_UNMUTE, 0);
    }

    private AudioManager audio() throws RemoteSession.Refused {
        AudioManager audio = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        if (audio.isVolumeFixed()) throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
        return audio;
    }

    @Override
    public JSONArray apps() {
        JSONArray list = new JSONArray();
        long serial = otherSerial();
        UserHandle user = null;
        if (serial >= 0) {
            UserManager users = (UserManager) mContext.getSystemService(Context.USER_SERVICE);
            user = users == null ? null : users.getUserForSerialNumber(serial);
            if (user == null) return list;
        }
        Map<String, LauncherActivityInfo> apps = ProfileApps.readApps(mContext,
                user != null ? user : android.os.Process.myUserHandle());
        if (apps == null) return list;
        List<String> sorted = new ArrayList<>(apps.keySet());
        java.util.Collections.sort(sorted, (a, b) ->
                String.valueOf(apps.get(a).getLabel()).compareToIgnoreCase(String.valueOf(apps.get(b).getLabel())));
        for (String pkg : sorted) {
            try {
                list.put(new JSONObject().put("pkg", pkg).put("label", String.valueOf(apps.get(pkg).getLabel())));
            } catch (JSONException ignored) {
            }
        }
        return list;
    }

    @Override
    public boolean allowed(String pkg) {
        long serial = otherSerial();
        if (serial >= 0) {
            Set<String> approved = ProfileUsers.approvedApps(mContext, serial);
            if (approved == null || !approved.contains(pkg)) return false;
        }
        return !Allowance.heldApps(mContext, java.util.Collections.singletonList(pkg)).containsKey(pkg);
    }

    private String label(String pkg) {
        try {
            PackageManager pm = mContext.getPackageManager();
            return String.valueOf(pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)));
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    private static String text(MediaMetadata metadata, String... keys) {
        if (metadata == null) return null;
        for (String key : keys) {
            CharSequence value = metadata.getText(key);
            if (value != null && value.length() > 0) return value.toString();
        }
        return null;
    }

    private static Object nullable(Object value) {
        return value == null ? JSONObject.NULL : value;
    }
}
