package com.leanbitlab.ltvL;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
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
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Process;
import android.os.UserManager;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

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
    private static final String CHANNEL = "hearth_agent";
    private static final long RETRY_MS = 5_000;
    private static final long PING_MS = 30_000;

    private static volatile String sPendingOpen;
    private static volatile AgentService sInstance;

    private HandlerThread mThread;
    private Handler mHandler;
    private volatile boolean mRunning;
    private volatile PrintWriter mOut;
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
                mHandler.postDelayed(mSendWatchNext, 1_000);
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
                    new NotificationChannel(CHANNEL, "Hearth for this profile", NotificationManager.IMPORTANCE_MIN));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hearth")
                .setContentText("Keeps Hearth's home in step with this profile")
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
                try (Socket socket = new Socket(InetAddress.getByName("127.0.0.1"), AgentHub.PORT)) {
                    PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
                    BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
                    out.println(new JSONObject().put("type", "hello").put("serial", serial).put("key", key));
                    JSONObject reply = new JSONObject(in.readLine());
                    if ("welcome".equals(reply.optString("type"))) {
                        Log.i(TAG, "Connected to Hearth as serial " + serial);
                        mOut = out;
                        mHandler.post(mSendWatchNext);
                        mHandler.postDelayed(mPing, PING_MS);
                        String line;
                        while ((line = in.readLine()) != null) {
                            JSONObject message = new JSONObject(line);
                            if ("open".equals(message.optString("type"))) sPendingOpen = message.optString("intent");
                        }
                    } else {
                        Log.i(TAG, "Hearth refused this agent's key");
                    }
                } catch (Exception e) {
                    Log.i(TAG, "Hearth unreachable: " + e.getMessage());
                } finally {
                    mOut = null;
                    mHandler.removeCallbacks(mPing);
                }
            }
            synchronized (this) {
                try {
                    wait(RETRY_MS);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }
    }

    private synchronized void reconnect() {
        notifyAll();
    }

    private void send(JSONObject message) {
        PrintWriter out = mOut;
        if (out == null || message == null) return;
        synchronized (out) {
            out.println(message.toString());
        }
    }

    private final Runnable mSendWatchNext = () -> {
        JSONArray rows = new JSONArray();
        for (Map<String, Object> row : WatchNextRows.read(this)) rows.put(new JSONObject(row));
        try {
            send(new JSONObject().put("type", "watchNext").put("rows", rows));
        } catch (Exception ignored) {
        }
    };

    private final Runnable mPing = new Runnable() {
        @Override
        public void run() {
            send(json("type", "ping"));
            mHandler.postDelayed(this, PING_MS);
        }
    };

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
