package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.LauncherActivityInfo;
import android.content.pm.LauncherApps;
import android.graphics.Rect;
import android.net.Uri;
import android.os.UserHandle;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Hearth's side (the owner's user) of its agents: Hearth itself, running in each other Google TV profile's user
 * (see {@link AgentService}), reports that user's Watch Next and opens things there for Hearth, since Android lets
 * nothing else cross users. They talk over the TV's own loopback address, the one channel users share, one JSON
 * object per line. Each profile's agent proves itself with a key Hearth hands it when it starts it (in the launch's
 * source bounds, the only thing a launch into another user carries), so another app on the TV can't pose as one.
 *
 * Agent to Hearth: {"type":"hello","serial":n,"key":"…","voiceDefault":bool}, {"type":"watchNext","rows":[…]},
 * {"type":"ping"}, {"type":"opened","ok":bool}, {"type":"speech","package":"…","text":"…"} (what an app said through
 * Hearth's voice there, for Profile Pairing). Hearth to agent: {"type":"welcome"}, {"type":"open","intent":"intent:…"},
 * {"type":"listen","package":"…" or null} (the app Profile Pairing is handling, whose speech to relay),
 * {"type":"hearth","row":{column: value}} (Hearth's provider row, mirrored by the agent's provider there) and
 * {"type":"pinResult","id":n,"ok":bool,"wait":s} answering an agent's {"type":"verifyPin","id":n,"pin":"…"}.
 */
final class AgentHub {
    static final int PORT = 47474;
    private static final String TAG = "HearthAgent";
    private static final String PREFS = "ltv_agents";
    private static final String KEY_PREFIX = "key|";
    /** Program ids from an agent are offset by its serial, so they never match the owner's own rows. */
    private static final long ID_OFFSET = 1_000_000_000L;

    private static Context sContext;
    private static boolean sStarted;
    private static final Map<Long, Connection> sConnections = new ConcurrentHashMap<>();
    private static final Map<Long, List<Map<String, Object>>> sWatchNext = new ConcurrentHashMap<>();
    private static final Map<Long, Boolean> sVoiceDefault = new ConcurrentHashMap<>();
    private static volatile String sListening;
    private static final java.util.concurrent.ExecutorService SENDER =
            java.util.concurrent.Executors.newSingleThreadExecutor();

    private static final class Connection {
        final long serial;
        final Socket socket;
        final PrintWriter out;

        Connection(long serial, Socket socket, PrintWriter out) {
            this.serial = serial;
            this.socket = socket;
            this.out = out;
        }

        /**
         * Queues the message for the agent. Writes go out on a background thread, in order: callers are often on
         * the main thread, where Android refuses socket writes (NetworkOnMainThreadException).
         */
        void send(JSONObject message) {
            final String line = message.toString();
            SENDER.execute(() -> {
                synchronized (this) {
                    out.println(line);
                }
            });
        }
    }

    private AgentHub() {
    }

    /** Starts listening (once); Hearth's accessibility service calls it in the owner's user. */
    static synchronized void start(Context context) {
        if (sStarted) return;
        sStarted = true;
        sContext = context.getApplicationContext();
        Thread server = new Thread(AgentHub::serve, "AgentHub");
        server.setDaemon(true);
        server.start();
    }

    private static void serve() {
        try (ServerSocket server = new ServerSocket(PORT, 8, InetAddress.getByName("127.0.0.1"))) {
            Log.i(TAG, "Listening for profile agents on 127.0.0.1:" + PORT);
            while (true) {
                Socket socket = server.accept();
                Thread reader = new Thread(() -> handle(socket), "AgentHub-conn");
                reader.setDaemon(true);
                reader.start();
            }
        } catch (Exception e) {
            Log.w(TAG, "Agent hub stopped: " + e);
            synchronized (AgentHub.class) {
                sStarted = false;
            }
        }
    }

    private static void handle(Socket socket) {
        Connection connection = null;
        try {
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            JSONObject hello = new JSONObject(in.readLine());
            long serial = hello.optLong("serial", -1);
            String key = keyFor(serial, false);
            if (!"hello".equals(hello.optString("type")) || key == null || !key.equals(hello.optString("key"))) {
                Log.i(TAG, "Agent for serial " + serial + " refused: no or wrong key");
                out.println(new JSONObject().put("type", "denied").toString());
                socket.close();
                return;
            }
            connection = new Connection(serial, socket, out);
            Connection old = sConnections.put(serial, connection);
            if (old != null) closeQuietly(old.socket);
            sVoiceDefault.put(serial, hello.optBoolean("voiceDefault"));
            connection.send(new JSONObject().put("type", "welcome"));
            connection.send(new JSONObject().put("type", "listen").put("package", sListening != null ? sListening : JSONObject.NULL));
            connection.send(hearthState(sContext));
            // Share owner-Hearth's already-authorized adb key over this loopback channel, so if Hearth is ever
            // uninstalled from the owner the agent can still clean up its own profile (see AgentService). Local only.
            String[] adbKey = SelfAdb.keyMaterial(sContext);
            if (adbKey != null) {
                connection.send(new JSONObject().put("type", "adbKey").put("priv", adbKey[0]).put("pub", adbKey[1]));
            }
            Log.i(TAG, "Agent for serial " + serial + " connected (Hearth voice there: " + hello.optBoolean("voiceDefault") + ")");
            String line;
            while ((line = in.readLine()) != null) {
                JSONObject message = new JSONObject(line);
                switch (message.optString("type")) {
                    case "watchNext":
                        sWatchNext.put(serial, rows(serial, message.optJSONArray("rows")));
                        notifyWatchNextChanged();
                        break;
                    case "speech": {
                        // Only the app Profile Pairing is handling (ProfilePairingService checks too)
                        String pkg = message.optString("package");
                        if (pkg.equals(sListening)) ProfilePairingService.onSpeech(pkg, message.optString("text"));
                        break;
                    }
                    case "verifyPin": {
                        // A kid's HearthTube checking the parent PIN through its agent (PINs stay with Hearth)
                        android.os.Bundle result = ProfileProvider.verifyParentPin(sContext, message.optString("pin"));
                        connection.send(new JSONObject().put("type", "pinResult").put("id", message.optLong("id"))
                                .put("ok", result.getBoolean("ok")).put("wait", result.getInt("wait_seconds", 0)));
                        break;
                    }
                    case "opened":
                        Log.i(TAG, "Agent for serial " + serial + " opened: " + message.optBoolean("ok"));
                        break;
                    default:
                        break;
                }
            }
        } catch (Exception e) {
            Log.i(TAG, "Agent connection ended: " + e.getMessage());
        } finally {
            if (connection != null) sConnections.remove(connection.serial, connection);
            closeQuietly(socket);
        }
    }

    private static List<Map<String, Object>> rows(long serial, JSONArray array) {
        List<Map<String, Object>> rows = new ArrayList<>();
        if (array == null) return rows;
        for (int i = 0; i < array.length(); i++) {
            JSONObject row = array.optJSONObject(i);
            if (row == null) continue;
            Map<String, Object> map = new HashMap<>();
            for (Iterator<String> it = row.keys(); it.hasNext(); ) {
                String name = it.next();
                map.put(name, row.opt(name));
            }
            map.put("id", serial * ID_OFFSET + row.optLong("id"));
            map.put("lastEngagementTime", row.optLong("lastEngagementTime"));
            map.put("playbackPosition", row.optLong("playbackPosition"));
            map.put("duration", row.optLong("duration"));
            map.put("watchNextType", row.optInt("watchNextType"));
            // Already this profile's: no owner to work out (see WatchNextService)
            map.put("profileOwned", true);
            rows.add(map);
        }
        return rows;
    }

    /** Tells Hearth's Continue Watching to re-read (MainActivity listens on this address too). */
    private static void notifyWatchNextChanged() {
        Context context = sContext;
        if (context != null) context.getContentResolver().notifyChange(watchNextUri(context), null);
    }

    static Uri watchNextUri(Context context) {
        return Uri.parse("content://" + context.getPackageName() + ".profile/agent_watch_next");
    }

    /** Hearth's provider row as a message for the agents. */
    private static JSONObject hearthState(Context context) throws org.json.JSONException {
        JSONObject row = new JSONObject();
        String[] columns = ProfileProvider.columns();
        Object[] values = ProfileProvider.row(context);
        for (int i = 0; i < columns.length; i++) row.put(columns[i], values[i] != null ? values[i] : JSONObject.NULL);
        return new JSONObject().put("type", "hearth").put("row", row);
    }

    /** Hearth's provider row changed: the agents' copies follow. */
    static void pushHearthState(Context context) {
        if (sConnections.isEmpty() || sContext == null) return;
        try {
            JSONObject state = hearthState(sContext);
            for (Connection connection : sConnections.values()) connection.send(state);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't send Hearth's state to the agents: " + e);
        }
    }

    /** Hearth's voice is the text-to-speech engine in that profile's user, as its agent reported. */
    static boolean isVoiceDefault(long serial) {
        return Boolean.TRUE.equals(sVoiceDefault.get(serial));
    }

    /**
     * The app Profile Pairing is handling (null: none): every agent relays what that app says through Hearth's voice
     * in its user.
     */
    static void setListening(String pkg) {
        sListening = pkg;
        for (Connection connection : sConnections.values()) {
            try {
                connection.send(new JSONObject().put("type", "listen").put("package", pkg != null ? pkg : JSONObject.NULL));
            } catch (Exception ignored) {
            }
        }
    }

    /** The profile's agent has reported its Watch Next at least once since Hearth started. */
    static boolean hasReported(long serial) {
        return sWatchNext.containsKey(serial);
    }

    /** Hearth is installed for that profile, so it can have an agent (a parent approved it there). */
    static boolean canHaveAgent(Context context, UserHandle user) {
        try {
            LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
            return !launcherApps.getActivityList(context.getPackageName(), user).isEmpty();
        } catch (RuntimeException e) {
            return false;
        }
    }

    static boolean isConnected(long serial) {
        return sConnections.containsKey(serial);
    }

    /** The profile's Watch Next as its agent last reported it (empty before it has). */
    static List<Map<String, Object>> watchNext(long serial) {
        List<Map<String, Object>> rows = sWatchNext.get(serial);
        return rows != null ? new ArrayList<>(rows) : Collections.emptyList();
    }

    /**
     * Opens the intent in the profile's user through its agent: the agent is told what to open, then started, and
     * its screen (a visible window, which Android requires for starting activities) opens it. False when the
     * agent isn't connected.
     */
    static boolean open(Context context, long serial, UserHandle user, String intentUri) {
        Connection connection = sConnections.get(serial);
        if (connection == null) return false;
        try {
            connection.send(new JSONObject().put("type", "open").put("intent", intentUri));
        } catch (Exception e) {
            return false;
        }
        return launchAgent(context, serial, user);
    }

    /**
     * Starts the profile's agent when it isn't connected (the first time ever, an agent only runs once Hearth starts
     * it; after that it starts with its profile). Needs Hearth's window to be visible; false when Hearth isn't
     * installed for that profile (a parent hasn't approved it).
     */
    static boolean ensureAgent(Context context, long serial, UserHandle user) {
        if (isConnected(serial)) return true;
        return launchAgent(context, serial, user);
    }

    private static boolean launchAgent(Context context, long serial, UserHandle user) {
        try {
            LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
            List<LauncherActivityInfo> activities = launcherApps.getActivityList(context.getPackageName(), user);
            if (activities.isEmpty()) {
                Log.i(TAG, "Hearth isn't installed for serial " + serial + ": no agent");
                return false;
            }
            launcherApps.startMainActivity(activities.get(0).getComponentName(), user, keyRect(context, serial), null);
            return true;
        } catch (RuntimeException e) {
            Log.i(TAG, "Couldn't start the agent for serial " + serial + ": " + e);
            return false;
        }
    }

    /** The profile's agent key ("l,t,r,b" of a Rect), made the first time; null when absent and not to be made. */
    private static synchronized String keyFor(long serial, boolean create) {
        Context context = sContext;
        if (context == null || serial < 0) return null;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String key = prefs.getString(KEY_PREFIX + serial, null);
        if (key == null && create) {
            SecureRandom random = new SecureRandom();
            key = random.nextInt() + "," + random.nextInt() + "," + random.nextInt() + "," + random.nextInt();
            prefs.edit().putString(KEY_PREFIX + serial, key).apply();
        }
        return key;
    }

    private static Rect keyRect(Context context, long serial) {
        if (sContext == null) sContext = context.getApplicationContext();
        String[] parts = keyFor(serial, true).split(",");
        return new Rect(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]), Integer.parseInt(parts[2]),
                Integer.parseInt(parts[3]));
    }

    private static void closeQuietly(Socket socket) {
        try {
            socket.close();
        } catch (Exception ignored) {
        }
    }
}
