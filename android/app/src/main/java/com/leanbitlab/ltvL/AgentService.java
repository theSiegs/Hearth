package com.leanbitlab.ltvL;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.database.ContentObserver;
import android.graphics.Rect;
import android.media.tv.TvContract;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;
import android.os.UserHandle;
import android.os.UserManager;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Hearth as an agent: when Hearth runs in another Google TV profile's user (one a parent approved Hearth for), it
 * shows nothing there and instead keeps this connection to Hearth in the owner's user (see {@link AgentHub}): it
 * reports this user's Watch Next and opens what Hearth asks for (via {@link AgentActivity}). It starts with the
 * profile (BOOT_COMPLETED, once Hearth has started it here the first time) and lives while the profile user runs.
 */
public class AgentService extends Service {
    private static final String TAG = "HearthAgent";
    private static final String PREFS = "ltv_agent";
    private static final String KEY = "key";
    private static final String HEARTH_ROW = "hearth_row";
    private static final String CHANNEL = "hearth_agent";
    private static final long RETRY_MS = 5_000;
    private static final long PING_MS = 30_000;
    private static final long WATCH_NEXT_DEBOUNCE_MS = 1_000;
    private static final long PIN_REPLY_SECONDS = 3;
    // About a minute of owner-Hearth being unreachable before the agent checks whether it was actually uninstalled.
    private static final int SELF_CLEAN_AFTER_FAILURES = 12;

    private static final AtomicLong sPinIds = new AtomicLong();
    private static final Map<Long, BlockingQueue<JSONObject>> sPinReplies = new ConcurrentHashMap<>();
    private static volatile String sPendingOpen;
    private static volatile String sListeningTo;
    private static volatile boolean sConnected;
    private static volatile AgentService sInstance;

    private HandlerThread mThread;
    private Handler mHandler;
    private volatile boolean mRunning;
    private int mFailedConnects = 0;
    private volatile boolean mSelfCleaned = false;
    private volatile PrintWriter mOut;
    private volatile Socket mSocket;
    private ContentObserver mWatchNextObserver;

    /** Whether Hearth is running in a profile user other than the owner's (the system user), as an agent. */
    static boolean isAgent(Context context) {
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        return users != null && !users.isSystemUser();
    }

    static void start(Context context) {
        Intent intent = new Intent(context, AgentService.class);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't start the agent: " + e);
        }
    }

    /** Keeps the key Hearth passed in the launch's source bounds, and reconnects with it. */
    static void rememberKey(Context context, Rect bounds) {
        if (bounds == null) return;
        String key = bounds.left + "," + bounds.top + "," + bounds.right + "," + bounds.bottom;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (key.equals(prefs.getString(KEY, null))) return;
        prefs.edit().putString(KEY, key).apply();
        AgentService service = sInstance;
        if (service != null) service.reconnect();
    }

    /** Hearth's Profile Pairing is handling this app: Hearth's voice here relays what it says (HearthVoiceService). */
    static boolean isListeningTo(String packageName) {
        return packageName != null && packageName.equals(sListeningTo);
    }

    /** Relays what an app said through Hearth's voice here to Profile Pairing in Hearth. */
    static void relaySpeech(String packageName, String text) {
        AgentService service = sInstance;
        if (service != null && text != null) service.send(json("type", "speech", "package", packageName, "text", text));
    }

    /**
     * Hearth's provider row as Hearth last sent it, in ProfileProvider's column order, for the provider here (a kid's
     * HearthTube in this user can't reach Hearth's). service_running says whether this agent is connected to
     * Hearth now; there's no wallpaper picture here (wallpaper_stamp 0, wallpaper_kind "gradient": Hearth's gradient).
     * Defaults before the first.
     */
    static Object[] mirroredRow(Context context) {
        String[] columns = ProfileProvider.columns();
        Object[] values = new Object[columns.length];
        JSONObject row = null;
        try {
            String saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(HEARTH_ROW, null);
            if (saved != null) row = new JSONObject(saved);
        } catch (Exception ignored) {
        }
        for (int i = 0; i < columns.length; i++) {
            Object value = row != null && !row.isNull(columns[i]) ? row.opt(columns[i]) : null;
            switch (columns[i]) {
                case "service_running":
                    value = sConnected && row != null ? 1 : 0;
                    break;
                case "wallpaper_stamp":
                    value = 0;
                    break;
                case "wallpaper_kind":
                    // No picture here: Hearth's gradient stands in (wallpaper_gradient, with its own brightness)
                    value = HearthWallpaper.KIND_GRADIENT;
                    break;
                case "wallpaper_brightness":
                case "wallpaper_title":
                case "wallpaper_credit":
                    value = null;
                    break;
                case "contract_version":
                    value = ProfileProvider.CONTRACT_VERSION;
                    break;
                default:
                    break;
            }
            values[i] = value;
        }
        return values;
    }

    /** Checks a PIN with Hearth (it stays there); null when Hearth doesn't answer within a few seconds. */
    static Bundle verifyPinWithHearth(String pin) {
        AgentService service = sInstance;
        if (service == null || service.mOut == null) return null;
        long id = sPinIds.incrementAndGet();
        BlockingQueue<JSONObject> reply = new ArrayBlockingQueue<>(1);
        sPinReplies.put(id, reply);
        try {
            service.send(json("type", "verifyPin", "id", id, "pin", pin));
            JSONObject answer = reply.poll(PIN_REPLY_SECONDS, TimeUnit.SECONDS);
            if (answer == null) return null;
            Bundle result = new Bundle();
            result.putBoolean("ok", answer.optBoolean("ok"));
            if (answer.optInt("wait") > 0) result.putInt("wait_seconds", answer.optInt("wait"));
            return result;
        } catch (InterruptedException e) {
            return null;
        } finally {
            sPinReplies.remove(id);
        }
    }

    private void onConnectionChanged(boolean connected) {
        sConnected = connected;
        getContentResolver().notifyChange(ProfileProvider.activeUri(this), null);
    }

    /** What Hearth asked to open, once (AgentActivity polls for it). */
    static String takePendingOpen() {
        String pending = sPendingOpen;
        sPendingOpen = null;
        return pending;
    }

    static void reportOpened(boolean ok) {
        AgentService service = sInstance;
        if (service != null) service.send(json("type", "opened", "ok", ok));
    }

    /**
     * Hides Hearth from this profile's own home (Google TV's): the full launcher screen gives way to AgentActivity,
     * which only Hearth itself opens. Done the first time Hearth runs here.
     */
    static void hideFromHome(Context context) {
        PackageManager pm = context.getPackageManager();
        pm.setComponentEnabledSetting(new ComponentName(context, AgentActivity.class),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
        pm.setComponentEnabledSetting(new ComponentName(context, MainActivity.class),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        sInstance = this;
        startInForeground();
        mThread = new HandlerThread("HearthAgent");
        mThread.start();
        mHandler = new Handler(mThread.getLooper());
        mRunning = true;
        mWatchNextObserver = new ContentObserver(mHandler) {
            @Override
            public void onChange(boolean selfChange) {
                mHandler.removeCallbacks(mSendWatchNext);
                mHandler.postDelayed(mSendWatchNext, WATCH_NEXT_DEBOUNCE_MS);
            }
        };
        try {
            getContentResolver().registerContentObserver(TvContract.WatchNextPrograms.CONTENT_URI, true, mWatchNextObserver);
        } catch (RuntimeException e) {
            Log.w(TAG, "Can't watch Watch Next here: " + e);
        }
        new Thread(this::connectLoop, "HearthAgent-socket").start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    private void startInForeground() {
        NotificationManager notifications = getSystemService(NotificationManager.class);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(
                    new NotificationChannel(CHANNEL, getString(R.string.agent_channel_name), NotificationManager.IMPORTANCE_MIN));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hearth")
                .setContentText(getString(R.string.agent_notification_text))
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(1, notification);
        }
    }

    private void connectLoop() {
        long serial = ((UserManager) getSystemService(Context.USER_SERVICE))
                .getSerialNumberForUser(Process.myUserHandle());
        while (mRunning) {
            String key = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null);
            if (key != null) {
                boolean connected = session(serial, key);
                if (!mRunning) return;
                if (connected) {
                    mFailedConnects = 0;
                } else {
                    mFailedConnects++;
                    maybeSelfClean();
                }
            }
            synchronized (this) {
                if (!mRunning) return;
                try {
                    wait(RETRY_MS);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }
    }

    /** One connection to Hearth, handled until it ends. Returns whether Hearth accepted this agent. */
    private boolean session(long serial, String key) {
        boolean connected = false;
        try (Socket socket = new Socket(InetAddress.getByName("127.0.0.1"), AgentHub.PORT)) {
            mSocket = socket;
            if (!mRunning) return false;
            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            out.println(new JSONObject().put("type", "hello").put("serial", serial).put("key", key)
                    .put("voiceDefault", ProfilePairingService.isVoiceDefault(this)));
            JSONObject reply = new JSONObject(in.readLine());
            if (!"welcome".equals(reply.optString("type"))) {
                Log.i(TAG, "Hearth refused this agent's key");
                return false;
            }
            Log.i(TAG, "Connected to Hearth as serial " + serial);
            mOut = out;
            connected = true;
            onConnectionChanged(true);
            mHandler.post(mSendWatchNext);
            mHandler.post(this::retireOldAdmin);
            mHandler.postDelayed(mPing, PING_MS);
            String line;
            while ((line = in.readLine()) != null) onMessage(new JSONObject(line));
        } catch (Exception e) {
            Log.i(TAG, "Hearth unreachable: " + e.getMessage());
        } finally {
            mSocket = null;
            boolean wasConnected = mOut != null;
            mOut = null;
            sListeningTo = null;
            if (wasConnected) onConnectionChanged(false);
            mHandler.removeCallbacks(mPing);
        }
        return connected;
    }

    /** One message from Hearth (the protocol is in {@link AgentHub}). */
    private void onMessage(JSONObject message) {
        switch (message.optString("type")) {
            case "open":
                sPendingOpen = message.optString("intent");
                break;
            case "listen":
                sListeningTo = message.isNull("package") ? null : message.optString("package");
                Log.i(TAG, "Listening to " + sListeningTo);
                break;
            case "hearth": {
                JSONObject row = message.optJSONObject("row");
                if (row != null) {
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                            .putString(HEARTH_ROW, row.toString()).apply();
                    getContentResolver().notifyChange(ProfileProvider.activeUri(this), null);
                }
                break;
            }
            case "pinResult": {
                BlockingQueue<JSONObject> reply = sPinReplies.get(message.optLong("id"));
                if (reply != null) reply.offer(message);
                break;
            }
            case "adbKey":
                storeSharedKey(message.optString("priv"), message.optString("pub"));
                mHandler.post(this::retireOldAdmin);
                break;
            default:
                break;
        }
    }

    private synchronized void reconnect() {
        notifyAll();
    }

    /**
     * Queues the message for Hearth on the agent's thread, in order: callers include the main thread, where Android
     * refuses socket writes (NetworkOnMainThreadException).
     */
    private void send(JSONObject message) {
        if (message == null || mOut == null) return;
        String line = message.toString();
        mHandler.post(() -> {
            PrintWriter out = mOut;
            if (out != null) out.println(line);
        });
    }

    private final Runnable mSendWatchNext = () -> {
        JSONArray rows = new JSONArray();
        for (Map<String, Object> row : WatchNextRows.read(this)) rows.put(new JSONObject(row));
        send(json("type", "watchNext", "rows", rows));
    };

    private final Runnable mPing = new Runnable() {
        @Override
        public void run() {
            send(json("type", "ping"));
            mHandler.postDelayed(this, PING_MS);
        }
    };

    /** Stores owner-Hearth's shared adb key (received over the channel) so the agent can self-adb if Hearth is gone. */
    private void storeSharedKey(String priv, String pub) {
        if (priv == null || priv.isEmpty() || pub == null || pub.isEmpty()) return;
        try {
            File dir = new File(getFilesDir(), "selfadb");
            if (!dir.exists() && !dir.mkdirs()) return;
            File pk = new File(dir, "adbkey");
            if (pk.exists()) return; // write once
            write(pk, priv);
            write(new File(dir, "adbkey.pub"), pub);
        } catch (Exception e) {
            Log.w(TAG, "couldn't store the shared key: " + e);
        }
    }

    private static void write(File f, String text) throws IOException {
        try (FileOutputStream o = new FileOutputStream(f)) {
            o.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }

    private void retireOldAdmin() {
        // Kids profiles set up before the block-uninstall flag kept Hearth installed by making it a device admin
        // (AgentAdminReceiver). Android won't uninstall an active admin, and only the app itself can give it up, so
        // "remove from profiles" failed there. Swap it for the flag (through the shell, with the key owner-Hearth
        // shared), then give the admin up: the profile stays protected, and the flag can be lifted for a removal.
        DevicePolicyManager dpm = getSystemService(DevicePolicyManager.class);
        ComponentName admin = new ComponentName(this, AgentAdminReceiver.class);
        if (dpm == null || !dpm.isAdminActive(admin)) return;
        if (!new File(new File(getFilesDir(), "selfadb"), "adbkey").exists()) return; // no shell yet: next connect
        int me = userIdSelf();
        if (me <= 0) return;
        try (SelfAdb shell = SelfAdb.open(this)) {
            if (!ProfileAppAccess.keepInstalled(this, shell, getPackageName(), me)) {
                Log.w(TAG, "couldn't set the keep-installed flag; keeping the old device admin");
                return;
            }
            dpm.removeActiveAdmin(admin);
            Log.i(TAG, "replaced the old device admin with the keep-installed flag in user " + me);
        } catch (Exception e) {
            Log.i(TAG, "old device admin not retired yet (will retry on the next connect): " + e.getMessage());
        }
    }

    /**
     * When owner-Hearth has been unreachable for a while, check — as the shell user, via the shared key — whether it
     * is really gone from the owner (user 0). If it was uninstalled, release THIS profile's Hearth/HearthTube so
     * Google TV's launcher removes them at the next profile start; that way a plain Android uninstall of Hearth
     * doesn't leave zombie copies behind. If owner-Hearth is still installed (just not running), do nothing.
     */
    private void maybeSelfClean() {
        if (mSelfCleaned || mFailedConnects < SELF_CLEAN_AFTER_FAILURES) return;
        File priv = new File(new File(getFilesDir(), "selfadb"), "adbkey");
        if (!priv.exists()) return; // no shared key -> no shell; nothing we can do
        try (SelfAdb shell = SelfAdb.open(this)) {
            String owner = shell.run("pm list packages --user 0 " + ProfileAppAccess.HEARTH);
            if (owner != null && owner.contains("package:" + ProfileAppAccess.HEARTH)) {
                mFailedConnects = 0; // owner-Hearth is still installed, just down; leave everything alone
                return;
            }
            int me = userIdSelf();
            if (me > 0) {
                ProfileAppAccess.cleanupUser(this, shell, me);
                mSelfCleaned = true;
                Log.i(TAG, "owner Hearth is gone; released this profile's copies for the launcher to remove");
            }
        } catch (Exception e) {
            Log.i(TAG, "self-clean check failed (will retry later): " + e.getMessage());
        }
    }

    /** This agent's own profile user id (for {@code pm --user}); -1 if unknown. */
    private int userIdSelf() {
        try {
            return (int) UserHandle.class.getMethod("getIdentifier").invoke(Process.myUserHandle());
        } catch (Exception e) {
            Matcher m = Pattern.compile("\\d+").matcher(String.valueOf(Process.myUserHandle()));
            return m.find() ? Integer.parseInt(m.group()) : -1;
        }
    }

    private static JSONObject json(Object... pairs) {
        try {
            JSONObject object = new JSONObject();
            for (int i = 0; i + 1 < pairs.length; i += 2) object.put((String) pairs[i], pairs[i + 1]);
            return object;
        } catch (Exception e) {
            return null;
        }
    }

    @Override
    public void onDestroy() {
        mRunning = false;
        // Ends the socket thread's read, so it stops handling Hearth's messages and Hearth sees the agent go.
        Socket socket = mSocket;
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException e) {
                Log.w(TAG, "Couldn't close the connection to Hearth: " + e);
            }
        }
        reconnect();
        if (mWatchNextObserver != null) getContentResolver().unregisterContentObserver(mWatchNextObserver);
        if (mThread != null) mThread.quitSafely();
        if (sInstance == this) sInstance = null;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
