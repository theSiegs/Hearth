package com.thesiegs.hearth;

import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.LauncherActivityInfo;
import android.content.pm.LauncherApps;
import android.graphics.Rect;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.UserHandle;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/**
 * Hearth's side (the owner's user) of its agents: Hearth itself, running in each other Google TV profile's user
 * (see {@link AgentService}), reports that user's Watch Next and opens things there for Hearth, since Android lets
 * nothing else cross users. They talk over the TV's own loopback address, the one channel users share, one JSON
 * object per line. Each profile's agent has a key Hearth hands it when it starts it (in the launch's source bounds,
 * the only thing a launch into another user carries). Neither side ever sends it: Hearth proves it has the key first,
 * then the agent does (AgentAuth), so another app on the TV can't pose as either.
 *
 * Handshake: agent {"type":"hello","serial":n,"nonce":"…","hasAdbKey":bool,"voiceDefault":bool,
 * "wallpaperVersion":n}; Hearth {"type":"challenge","nonce":"…","proof":"…"} (or {"type":"denied"}); agent
 * {"type":"auth","proof":"…"}; Hearth {"type":"welcome"} (or {"type":"denied"}), then, to an agent whose hello says
 * hasAdbKey (Hearth up to 2026.10.60 shared its adb key with the agents), {"type":"forgetAdbKey"}.
 *
 * Agent to Hearth:
 * {"type":"watchNext","rows":[…]},
 * {"type":"ping"}, {"type":"playing","package":"…","ms":n} (an app played that long in the profile's user),
 * {"type":"played","package":"…","title":"…","subtitle":"…","duration":ms,"position":ms} (what plays there, for the
 * profile's watch history),
 * {"type":"started","t":ms,"v":"id","title":"…","ch":"…","cid":"…"} (a video HearthTube started there, for the
 * parent's log: StartedLog), {"type":"opened","ok":bool}, {"type":"speech","package":"…","text":"…"} (what an app said through
 * Hearth's voice there, for Profile Pairing), {"type":"calendar","access":bool,"calendars":[…],"events":[…]} (the
 * Google calendars synced to that profile's user and their coming days' events, TvCalendars' maps). Hearth to agent: {"type":"welcome"}, {"type":"open","intent":"intent:…"},
 * {"type":"listen","package":"…" or null} (the app Profile Pairing is handling, whose speech to relay),
 * {"type":"hearth","row":{column: value}} (Hearth's provider row, mirrored by the agent's provider there),
 * {"type":"wallpaper",…} (that profile's own wallpaper, picture included, only to its own agent: AgentWallpaper) and
 * {"type":"pinResult","id":n,"ok":bool,"wait":s} answering an agent's {"type":"verifyPin","id":n,"pin":"…"}, and
 * {"type":"calendarRefresh"} (read the calendars again now: Hearth was just let read them there).
 */
final class AgentHub {
    static final int PORT = 47474;
    private static final int HANDSHAKE_TIMEOUT_MS = 10_000;
    private static final String TAG = "HearthAgent";
    private static final String PREFS = "ltv_agents";
    private static final String KEY_PREFIX = "key|";
    /** Program ids from an agent are offset by its serial, so they never match the owner's own rows. */
    private static final long ID_OFFSET = 1_000_000_000L;

    /** The application context, set by start; read on the connections' threads. */
    private static volatile Context sContext;
    /** Guarded by AgentHub.class. */
    private static boolean sStarted;
    private static final Map<Long, Connection> sConnections = new ConcurrentHashMap<>();
    /** When ensureAgent last started each profile's agent (elapsed realtime). */
    private static final Map<Long, Long> sEnsuredAt = new ConcurrentHashMap<>();
    private static final long ENSURE_AGAIN_MS = 15_000;
    private static final Map<Long, List<Map<String, Object>>> sWatchNext = new ConcurrentHashMap<>();
    private static final Map<Long, Boolean> sVoiceDefault = new ConcurrentHashMap<>();
    private static final Map<Long, CalendarReport> sCalendars = new ConcurrentHashMap<>();
    private static volatile String sListening;
    private static final ExecutorService SENDER = Executors.newSingleThreadExecutor();
    /** Keeps what a kids profile's agent reports in WatchHistory, off the connection's thread. */
    private static final ExecutorService HISTORY = Executors.newSingleThreadExecutor();

    private static final class Connection {
        final long serial;
        final Socket socket;
        final PrintWriter out;

        // Only touched on SENDER: the picture version the agent has, and the last wallpaper message sent (no image)
        private long wallpaperVersionThere;
        private String lastWallpaper;

        Connection(long serial, Socket socket, PrintWriter out, long wallpaperVersionThere) {
            this.serial = serial;
            this.socket = socket;
            this.out = out;
            this.wallpaperVersionThere = wallpaperVersionThere;
        }

        /**
         * Sends the agent its profile's wallpaper (AgentWallpaper), when that's the one in place and it changed since
         * the last time; the picture only when the agent doesn't have it yet.
         */
        void sendWallpaper(Context context) {
            SENDER.execute(() -> {
                try {
                    JSONObject message = AgentWallpaper.message(context, serial, wallpaperVersionThere);
                    if (message == null) return;
                    Object image = message.remove("image");
                    String withoutImage = message.toString();
                    if (image == null && withoutImage.equals(lastWallpaper)) return;
                    if (image != null) message.put("image", image);
                    out.println(message.toString());
                    lastWallpaper = withoutImage;
                    // Sent, or tried and too big: either way not again for this version
                    if (!HearthWallpaper.KIND_GRADIENT.equals(message.optString("kind"))) {
                        wallpaperVersionThere = message.optLong("version");
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Couldn't send the wallpaper to the agent for serial " + serial + ": " + e);
                }
            });
        }

        /**
         * Queues the message for the agent. Writes go out on one background thread, in order: callers are often on
         * the main thread, where Android refuses socket writes (NetworkOnMainThreadException).
         */
        void send(JSONObject message) {
            final String line = message.toString();
            SENDER.execute(() -> out.println(line));
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
            // A connection that never finishes the handshake doesn't hold its thread for good
            socket.setSoTimeout(HANDSHAKE_TIMEOUT_MS);
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            JSONObject hello = new JSONObject(in.readLine());
            long serial = hello.optLong("serial", -1);
            String key = keyFor(sContext, serial, false);
            String agentNonce = hello.optString("nonce");
            if (!"hello".equals(hello.optString("type")) || key == null || agentNonce.isEmpty()) {
                Log.i(TAG, "Agent for serial " + serial + " refused: no key for it");
                out.println(new JSONObject().put("type", "denied").toString());
                socket.close();
                return;
            }
            // Each side proves it has the agent's key without sending it (AgentAuth)
            String hubNonce = AgentAuth.nonce();
            out.println(new JSONObject().put("type", "challenge").put("nonce", hubNonce)
                    .put("proof", AgentAuth.proof(key, AgentAuth.HUB, agentNonce, hubNonce)).toString());
            String answer = in.readLine();
            JSONObject auth = answer != null ? new JSONObject(answer) : new JSONObject();
            if (!"auth".equals(auth.optString("type")) || !AgentAuth.verify(
                    AgentAuth.proof(key, AgentAuth.AGENT, agentNonce, hubNonce), auth.optString("proof", null))) {
                Log.i(TAG, "Agent for serial " + serial + " refused: wrong key");
                out.println(new JSONObject().put("type", "denied").toString());
                socket.close();
                return;
            }
            // A proven agent stays connected, quiet for as long as nothing changes
            socket.setSoTimeout(0);
            connection = new Connection(serial, socket, out, hello.optLong("wallpaperVersion"));
            Connection old = sConnections.put(serial, connection);
            if (old != null) closeQuietly(old.socket);
            sVoiceDefault.put(serial, hello.optBoolean("voiceDefault"));
            connection.send(json("type", "welcome"));
            connection.send(listenMessage(sListening));
            connection.send(hearthState(sContext));
            connection.sendWallpaper(sContext);
            // Hearth up to 2026.10.60 shared its adb key with the agents. An agent that still holds it is told to
            // delete it: only owner-Hearth runs shell commands now
            if (hello.optBoolean("hasAdbKey")) {
                connection.send(json("type", "forgetAdbKey"));
                Log.i(TAG, "Agent for serial " + serial + " told to forget the adb key an older Hearth shared");
            }
            Log.i(TAG, "Agent for serial " + serial + " connected (Hearth voice there: " + hello.optBoolean("voiceDefault") + ")");
            String line;
            while ((line = in.readLine()) != null) {
                JSONObject message = new JSONObject(line);
                switch (message.optString("type")) {
                    case "watchNext":
                        sWatchNext.put(serial, rows(serial, message.optJSONArray("rows")));
                        notifyWatchNextChanged();
                        // Kept and sent to the household now, not only when the row is next read for that profile
                        HISTORY.execute(() -> kidsContinueWatching(sContext, serial));
                        break;
                    case "calendar":
                        sCalendars.put(serial, new CalendarReport(message.optBoolean("access"),
                                maps(message.optJSONArray("calendars")), maps(message.optJSONArray("events"))));
                        break;
                    case "playing":
                        // An app played in this profile's user (its agent counts what Hearth can't see)
                        String played = message.optString("package", null);
                        if (CompanionApps.HEARTHTUBE.equals(played)) {
                            // Its allowance may have gone down: the agent gets the new row when it did
                            new Handler(Looper.getMainLooper()).post(() -> ProfileProvider.addHearthTubePlaying(
                                    sContext, ProfileUsers.key(serial), message.optLong("ms")));
                        } else {
                            UsageToday.addPlaying(sContext, ProfileUsers.key(serial), played, message.optLong("ms"),
                                    System.currentTimeMillis());
                        }
                        break;
                    case "started": {
                        // A video HearthTube started in this profile's user (never an adult's: a kid's log only)
                        if (serial == ProfileUsers.ownerSerial(sContext)) break;
                        String profile = ProfileUsers.profileKey(sContext, serial);
                        HISTORY.execute(() -> StartedLog.record(sContext, profile, message.optLong("t"),
                                message.optString("v", null), message.optString("title", ""),
                                message.optString("ch", ""), message.optString("cid", "")));
                        break;
                    }
                    case "played": {
                        // What plays in this profile's user, into its own watch history (never an adult's: the
                        // owner's user is Hearth's own recorder's)
                        Played p = played(message);
                        if (p == null || serial == ProfileUsers.ownerSerial(sContext)) break;
                        // Saved while it plays, as for an adult: Continue Watching shows it when it's next read
                        HISTORY.execute(() -> WatchHistory.get(sContext).recordPlay(
                                ProfileUsers.profileKey(sContext, serial), p.packageName, p.title, p.subtitle,
                                p.durationMs, p.positionMs, System.currentTimeMillis()));
                        break;
                    }
                    case "speech": {
                        // Only the app Profile Pairing is handling (ProfilePairingService checks too)
                        String pkg = message.optString("package");
                        if (pkg.equals(sListening)) ProfilePairingService.onSpeech(pkg, message.optString("text"));
                        break;
                    }
                    case "verifyPin": {
                        // A kid's HearthTube checking the parent PIN through its agent (PINs stay with Hearth)
                        Bundle result = ProfileProvider.verifyParentPin(sContext, message.optString("pin"));
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

    /** What an agent says plays in its profile, checked: the agent is another user's app, so nothing is taken as is. */
    static final class Played {
        final String packageName;
        final String title;
        final String subtitle;
        final long durationMs;
        final long positionMs;

        Played(String packageName, String title, String subtitle, long durationMs, long positionMs) {
            this.packageName = packageName;
            this.title = title;
            this.subtitle = subtitle;
            this.durationMs = durationMs;
            this.positionMs = positionMs;
        }
    }

    static final int MAX_PLAYED_TITLE = 200;
    /** Longer than any show or film: a duration or position past it isn't one. */
    static final long MAX_PLAYED_MS = 24L * 60 * 60 * 1000;
    private static final Pattern PACKAGE_NAME =
            Pattern.compile("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");

    /** A "played" message as Hearth keeps it, or null when it isn't one (no app or title, or numbers that aren't). */
    static Played played(JSONObject message) {
        String pkg = message.optString("package", "");
        if (pkg.length() > 255 || !PACKAGE_NAME.matcher(pkg).matches()) return null;
        String title = playedText(message.opt("title"));
        if (title == null) return null;
        long duration = message.optLong("duration", 0);
        long position = message.optLong("position", 0);
        if (duration < 0 || duration > MAX_PLAYED_MS || position < 0 || position > MAX_PLAYED_MS) return null;
        if (duration > 0 && position > duration) position = duration;
        return new Played(pkg, title, playedText(message.opt("subtitle")), duration, position);
    }

    /** A title or episode as kept: on one line, without control characters, cut to a sane length; null if empty. */
    private static String playedText(Object value) {
        if (!(value instanceof String)) return null;
        StringBuilder out = new StringBuilder();
        String text = (String) value;
        for (int i = 0; i < text.length(); ) {
            int c = text.codePointAt(i);
            i += Character.charCount(c);
            int type = Character.getType(c);
            boolean invisible = type == Character.CONTROL || type == Character.FORMAT || type == Character.SURROGATE
                    || type == Character.UNASSIGNED || type == Character.LINE_SEPARATOR
                    || type == Character.PARAGRAPH_SEPARATOR;
            out.appendCodePoint(invisible ? ' ' : c);
        }
        String clean = out.toString().replaceAll("\\s+", " ").trim();
        if (clean.isEmpty()) return null;
        if (clean.codePointCount(0, clean.length()) > MAX_PLAYED_TITLE) {
            clean = clean.substring(0, clean.offsetByCodePoints(0, MAX_PLAYED_TITLE)).trim();
        }
        return clean;
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

    /** JSON objects as maps for Flutter (JSON's null as null). */
    static List<Map<String, Object>> maps(JSONArray array) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (array == null) return out;
        for (int i = 0; i < array.length(); i++) {
            JSONObject object = array.optJSONObject(i);
            if (object == null) continue;
            Map<String, Object> map = new HashMap<>();
            for (Iterator<String> it = object.keys(); it.hasNext(); ) {
                String name = it.next();
                map.put(name, object.isNull(name) ? null : object.opt(name));
            }
            out.add(map);
        }
        return out;
    }

    /** What a profile's agent last said about its user's calendars. */
    private static final class CalendarReport {
        final boolean access;
        final List<Map<String, Object>> calendars;
        final List<Map<String, Object>> events;

        CalendarReport(boolean access, List<Map<String, Object>> calendars, List<Map<String, Object>> events) {
            this.access = access;
            this.calendars = calendars;
            this.events = events;
        }
    }

    /** Whether the profile's agent may read its calendars; null before it has said. */
    static Boolean calendarAccess(long serial) {
        CalendarReport report = sCalendars.get(serial);
        return report == null ? null : report.access;
    }

    /** The calendars the profile's agent last reported (empty before it has). */
    static List<Map<String, Object>> calendars(long serial) {
        CalendarReport report = sCalendars.get(serial);
        return report == null ? Collections.emptyList() : new ArrayList<>(report.calendars);
    }

    /** Of the events the profile's agent last reported (its coming days), those between start and end. */
    static List<Map<String, Object>> calendarEvents(long serial, long start, long end) {
        CalendarReport report = sCalendars.get(serial);
        List<Map<String, Object>> out = new ArrayList<>();
        if (report == null) return out;
        for (Map<String, Object> event : report.events) {
            long from = event.get("start") instanceof Number ? ((Number) event.get("start")).longValue() : 0;
            long to = event.get("end") instanceof Number ? ((Number) event.get("end")).longValue() : from;
            if (TvCalendars.overlaps(from, to, start, end)) out.add(event);
        }
        return out;
    }

    /** Asks the profile's agent to read its calendars again (it was just let read them); false when not connected. */
    static boolean refreshCalendars(long serial) {
        Connection connection = sConnections.get(serial);
        if (connection == null) return false;
        connection.send(json("type", "calendarRefresh"));
        return true;
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
    private static JSONObject hearthState(Context context) throws JSONException {
        JSONObject row = new JSONObject();
        String[] columns = ProfileProvider.columns();
        Object[] values = ProfileProvider.row(context);
        for (int i = 0; i < columns.length; i++) row.put(columns[i], values[i] != null ? values[i] : JSONObject.NULL);
        return new JSONObject().put("type", "hearth").put("row", row);
    }

    /** Hearth's provider row changed: the agents' copies follow. */
    static void pushHearthState(Context context) {
        if (sConnections.isEmpty()) return;
        try {
            JSONObject state = hearthState(context);
            for (Connection connection : sConnections.values()) {
                connection.send(state);
                // Its own wallpaper too, to the agent whose profile it is (the others get none)
                connection.sendWallpaper(context.getApplicationContext());
            }
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
        JSONObject message = listenMessage(pkg);
        for (Connection connection : sConnections.values()) connection.send(message);
    }

    private static JSONObject listenMessage(String pkg) {
        return json("type", "listen", "package", pkg != null ? pkg : JSONObject.NULL);
    }

    /** The profile's agent has reported its Watch Next at least once since Hearth started. */
    static boolean hasReported(long serial) {
        return sWatchNext.containsKey(serial);
    }

    /** Hearth is installed for that profile, so it can have an agent (a parent approved it there). */
    static boolean canHaveAgent(Context context, UserHandle user) {
        try {
            return ownActivity(context, user) != null;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /** Hearth's own launcher activity in that user; null when Hearth isn't installed there. */
    private static ComponentName ownActivity(Context context, UserHandle user) {
        LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
        List<LauncherActivityInfo> activities = launcherApps.getActivityList(context.getPackageName(), user);
        return activities.isEmpty() ? null : activities.get(0).getComponentName();
    }

    static boolean isConnected(long serial) {
        return sConnections.containsKey(serial);
    }

    /**
     * A kids profile's Continue Watching: its agent's rows, every one its own, through WatchHistory (kept under its
     * key for the household, with what the household's other TVs had for it).
     */
    static List<Map<String, Object>> kidsContinueWatching(Context context, long serial) {
        return WatchHistory.get(context).kidsContinueWatching(context, watchNext(serial),
                ProfileUsers.profileKey(context, serial), hasReported(serial), ProfileUsers.approvedApps(context, serial),
                System.currentTimeMillis());
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
        connection.send(json("type", "open", "intent", intentUri));
        return launchAgent(context, serial, user);
    }

    /**
     * Starts the profile's agent when it isn't connected (the first time ever, an agent only runs once Hearth starts
     * it; after that it starts with its profile). Needs Hearth's window to be visible; false when Hearth isn't
     * installed for that profile (a parent hasn't approved it).
     */
    static boolean ensureAgent(Context context, long serial, UserHandle user) {
        if (isConnected(serial)) return true;
        // Not over and over while one is starting (its screen comes up over Hearth each time)
        long now = android.os.SystemClock.elapsedRealtime();
        Long last = sEnsuredAt.get(serial);
        if (last != null && now - last < ENSURE_AGAIN_MS) return false;
        sEnsuredAt.put(serial, now);
        return launchAgent(context, serial, user);
    }

    private static boolean launchAgent(Context context, long serial, UserHandle user) {
        try {
            ComponentName activity = ownActivity(context, user);
            if (activity == null) {
                Log.i(TAG, "Hearth isn't installed for serial " + serial + ": no agent");
                return false;
            }
            LauncherApps launcherApps = (LauncherApps) context.getSystemService(Context.LAUNCHER_APPS_SERVICE);
            launcherApps.startMainActivity(activity, user, keyRect(context, serial), null);
            return true;
        } catch (RuntimeException e) {
            Log.i(TAG, "Couldn't start the agent for serial " + serial + ": " + e);
            return false;
        }
    }

    /** The profile's agent key ("l,t,r,b" of a Rect), made the first time; null when absent and not to be made. */
    private static synchronized String keyFor(Context context, long serial, boolean create) {
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
        String[] parts = keyFor(context, serial, true).split(",");
        return new Rect(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]), Integer.parseInt(parts[2]),
                Integer.parseInt(parts[3]));
    }

    /** A message from name/value pairs. put throws only for a NaN or infinite number, which no message here holds. */
    private static JSONObject json(Object... pairs) {
        try {
            JSONObject object = new JSONObject();
            for (int i = 0; i + 1 < pairs.length; i += 2) object.put((String) pairs[i], pairs[i + 1]);
            return object;
        } catch (JSONException e) {
            throw new IllegalArgumentException(e);
        }
    }

    private static void closeQuietly(Socket socket) {
        try {
            socket.close();
        } catch (Exception ignored) {
        }
    }
}
