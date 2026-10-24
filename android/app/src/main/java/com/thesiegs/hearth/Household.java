package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * This TV's part in a household (docs/household-sync.md): the one place that knows whether sync is on, hears about
 * changes to Profile Pairing and saved PINs, runs the exchanges with the other TVs, and adds, removes and leaves.
 * Everything that touches the entries runs on one thread, so changes and exchanges never overlap. Where this TV is in no
 * household every call here is a cheap no-op, and the Keystore is never touched.
 */
final class Household {
    private static final String TAG = "HearthHousehold";
    private static final String PREFS = "household";
    /** Any of these in the preferences: this TV is, was, or is leaving a household (version 1 kept only the key). */
    private static final String[] HOUSEHOLD_PREFS = {"household_id", "key_sealed", "removed"};
    /** The TVs this one has synced with ({tvId: {name, at}}), for the list of members. */
    private static final String SEEN_PREF = "seen";
    /** How long leaving waits to tell the TVs on now that this one is gone. */
    private static final long LEAVE_SYNC_MS = 10_000;
    /** A short wait after a change so several changes go out together; the periodic check is the backstop. */
    private static final long SYNC_DELAY_MS = 2_000;
    private static final long PERIODIC_MS = 5 * 60_000;
    private static final int SOCKET_TIMEOUT_MS = 15_000;

    private static final ScheduledExecutorService EXEC = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread thread = new Thread(r, "household");
        thread.setDaemon(true);
        return thread;
    });

    /**
     * Reads what a connection is (an exchange or a join request) off the household thread, which never waits on one; a
     * join request waits on a parent here. A few at a time: a connection beyond that is closed, so idle connections
     * can't use up a TV's threads.
     */
    private static final ExecutorService NET = new java.util.concurrent.ThreadPoolExecutor(0, 4, 30,
            TimeUnit.SECONDS, new java.util.concurrent.SynchronousQueue<>(), r -> {
        Thread thread = new Thread(r, "household-net");
        thread.setDaemon(true);
        return thread;
    });
    /** How long a connection has to say what it is. */
    private static final int ROUTE_TIMEOUT_MS = 5_000;

    private static Context sContext;
    /** Goes up whenever a look, layout or wallpaper changed here (from another TV or published): the app checks it. */
    private static long sLooksVersion = 1;
    private static HouseholdStore sStore;
    private static boolean sSyncQueued;
    private static boolean sPeriodicScheduled;
    private static long sLastSyncAt;
    private static String sLastResult;

    private Household() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Whether this TV has ever been in a household, without touching the Keystore. */
    private static boolean mayBeInHousehold(Context context) {
        SharedPreferences prefs = prefs(context);
        for (String key : HOUSEHOLD_PREFS) {
            if (prefs.getString(key, null) != null) return true;
        }
        return false;
    }

    private static synchronized HouseholdStore store(Context context) {
        sContext = context.getApplicationContext();
        if (sStore == null) {
            final SharedPreferences prefs = prefs(sContext);
            sStore = HouseholdStore.open(new HouseholdStore.Backing() {
                @Override public String get(String key) {
                    return prefs.getString(key, null);
                }

                @Override public void put(String key, String value) {
                    prefs.edit().putString(key, value).apply();
                }

                @Override public void remove(String key) {
                    prefs.edit().remove(key).apply();
                }
            }, SecretBox.keystore(), HouseholdIdentity.keystore());
        }
        return sStore;
    }

    /** The household's wallpaper pictures, in this app's own files. */
    static HouseholdPictures pictures(Context context) {
        return new HouseholdPictures(new java.io.File(context.getFilesDir(), "household_pictures"));
    }

    private static HouseholdLocal local(Context context) {
        return new HouseholdLocal(context, store(context).seal());
    }

    /** Sync is on: in a household (or leaving one and still telling it) and the switch is on. */
    private static boolean active(Context context) {
        if (!mayBeInHousehold(context)) return false;
        HouseholdStore store = store(context);
        return store.syncs() && store.enabled();
    }

    /** Sync is on and this TV is a member, not leaving: its own settings go out and the household's come in. */
    private static boolean member(Context context) {
        return active(context) && store(context).joined();
    }

    // ---- Starting and stopping ----

    /** Starts listening, announcing and syncing when this TV is in a household with sync on; stops when it isn't. */
    static void start(Context context) {
        if (!active(context)) {
            stop();
            return;
        }
        HouseholdStore store = store(context);
        if (store.leavingExpired(System.currentTimeMillis())) {
            EXEC.execute(() -> forget(context));
            return;
        }
        HouseholdNet.start(context, store.tvId(), store.householdId(), socket -> {
            try {
                NET.execute(() -> route(socket));
            } catch (java.util.concurrent.RejectedExecutionException e) {
                try {
                    socket.close();
                } catch (IOException ignored) {
                }
            }
        });
        synchronized (Household.class) {
            if (!sPeriodicScheduled) {
                sPeriodicScheduled = true;
                EXEC.scheduleWithFixedDelay(() -> {
                    publishSelf();
                    syncAll("periodic");
                }, PERIODIC_MS, PERIODIC_MS, TimeUnit.MILLISECONDS);
            }
        }
        EXEC.execute(() -> {
            publishSelf();
            publishUnpublished();
            applyEntries();
        });
        syncSoon();
    }

    /** This TV's own member entry (HouseholdMembers), so the others list it: written when missing, renamed or a day old. */
    private static void publishSelf() {
        if (sContext == null || !member(sContext)) return;
        HouseholdStore store = store(sContext);
        if (!store.publishSelf(ShareDiscovery.deviceName(sContext), System.currentTimeMillis())) return;
        store.save();
        syncSoon();
    }

    /** A TV of the household synced with this one: when, for the list of members. */
    private static void noteSeen(String tvId, String name) {
        if (tvId == null || sContext == null) return;
        try {
            SharedPreferences prefs = prefs(sContext);
            org.json.JSONObject seen = new org.json.JSONObject(prefs.getString(SEEN_PREF, "{}"));
            seen.put(tvId, new org.json.JSONObject().put("name", name == null ? "" : name)
                    .put("at", System.currentTimeMillis()));
            prefs.edit().putString(SEEN_PREF, seen.toString()).apply();
        } catch (org.json.JSONException e) {
            prefs(sContext).edit().remove(SEEN_PREF).apply();
        }
    }

    private static Map<String, HouseholdMembers.Seen> seen(Context context) {
        Map<String, HouseholdMembers.Seen> out = new HashMap<>();
        try {
            org.json.JSONObject seen = new org.json.JSONObject(prefs(context).getString(SEEN_PREF, "{}"));
            for (java.util.Iterator<String> it = seen.keys(); it.hasNext(); ) {
                String id = it.next();
                org.json.JSONObject s = seen.optJSONObject(id);
                if (s == null) continue;
                String name = s.optString("name", "").trim();
                out.put(id, new HouseholdMembers.Seen(name.isEmpty() ? null : name, s.optLong("at")));
            }
        } catch (org.json.JSONException ignored) {
        }
        return out;
    }

    static void stop() {
        HouseholdNet.stop();
    }

    /** A TV of the household was heard on the network. */
    static void peerFound() {
        if (sContext != null) syncSoon();
    }

    // ---- Changes made on this TV ----

    static void onPinSaved(Context context, String owner, String pkg, String appProfile) {
        if (!mayBeInHousehold(context)) return;
        EXEC.execute(() -> {
            if (!member(context)) return;
            char[] pin = PinVault.open(context, owner, pkg, appProfile);
            if (pin == null) return;
            try {
                publish(context, HouseholdBridge.PIN, owner, pkg + "|" + appProfile, new String(pin));
            } finally {
                Arrays.fill(pin, '\0');
            }
        });
    }

    static void onPinRemoved(Context context, String owner, String pkg, String appProfile) {
        if (!mayBeInHousehold(context)) return;
        EXEC.execute(() -> {
            if (member(context)) publish(context, HouseholdBridge.PIN, owner, pkg + "|" + appProfile, null);
        });
    }

    static void onPairingChanged(Context context, String pkg, String profileKey) {
        if (!mayBeInHousehold(context)) return;
        EXEC.execute(() -> {
            if (!member(context)) return;
            publish(context, HouseholdBridge.PAIRING, profileKey, pkg, local(context).pairings(profileKey).get(pkg));
        });
    }

    /** Writes one setting as an entry if it differs from the log's (null: delete it if the log has it). */
    private static void publish(Context context, String kind, String ownerKey, String item, String value) {
        HouseholdStore store = store(context);
        HouseholdLocal local = local(context);
        String name = local.personIdOf(ownerKey);
        if (name == null || (ownerKey != null && !ownerKey.equals(local.profiles().get(name)))) return;
        HouseholdLog log = store.log();
        HouseholdEntry have = log.get(kind, name, item);
        long now = System.currentTimeMillis();
        if (value == null) {
            if (have == null) return;
            log.delete(kind, name, item, now);
        } else {
            if (have != null && have.value.equals(value)) return;
            log.put(kind, name, item, value, now);
        }
        store.save();
        syncSoon();
    }

    /** Settings that are set here and have no entry yet become entries (the household's values win over this TV's). */
    private static void publishUnpublished() {
        if (sContext == null || !member(sContext)) return;
        HouseholdStore store = store(sContext);
        long now = System.currentTimeMillis();
        Map<String, String[]> fresh = HouseholdBridge.unpublished(local(sContext), store.log());
        for (String[] f : fresh.values()) store.log().put(f[0], f[1], f[2], f[3], now);
        if (!fresh.isEmpty()) {
            store.save();
            syncSoon();
        }
    }

    private static void applyEntries() {
        if (sContext == null || !member(sContext)) return;
        int changed = HouseholdBridge.apply(local(sContext), store(sContext).log());
        if (changed > 0) Log.i(TAG, "Applied " + changed + " setting(s) from the household");
    }

    // ---- Exchanges ----

    private static synchronized void syncSoon() {
        if (sSyncQueued) return;
        sSyncQueued = true;
        EXEC.schedule(() -> {
            synchronized (Household.class) {
                sSyncQueued = false;
            }
            syncAll("change");
        }, SYNC_DELAY_MS, TimeUnit.MILLISECONDS);
    }

    /** Exchanges with every TV of the household that is on the network. */
    static void syncAll(String why) {
        if (sContext == null || !active(sContext)) return;
        for (HouseholdNet.Peer peer : HouseholdNet.peers()) {
            // An exchange can end the household here (this TV was removed, or it finished leaving)
            if (!active(sContext)) return;
            exchangeWith(peer, why);
        }
    }

    private static void exchangeWith(HouseholdNet.Peer peer, String why) {
        HouseholdStore store = store(sContext);
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(peer.host, peer.port), 5_000);
            socket.setSoTimeout(SOCKET_TIMEOUT_MS);
            HouseholdSync.Result result = HouseholdSync.run(socket.getInputStream(), socket.getOutputStream(), true,
                    store, pictures(sContext), ShareDiscovery.deviceName(sContext), System.currentTimeMillis());
            finish(store, result, "to " + why);
        } catch (IOException | java.security.GeneralSecurityException e) {
            sLastResult = "failed: " + e.getClass().getSimpleName();
            Log.i(TAG, "Couldn't sync with a TV of the household: " + e.getClass().getSimpleName());
        }
    }

    /** A TV connected: a join request is served here (it waits on a parent), an exchange on the household thread. */
    private static void route(Socket socket) {
        try {
            socket.setSoTimeout(ROUTE_TIMEOUT_MS);
            BufferedInputStream in = new BufferedInputStream(socket.getInputStream());
            in.mark(HouseholdJoin.MAGIC.length);
            byte[] magic = new byte[HouseholdJoin.MAGIC.length];
            new java.io.DataInputStream(in).readFully(magic);
            if (Arrays.equals(magic, HouseholdJoin.MAGIC)) {
                if (member(sContext)) {
                    HouseholdJoining.serve(sContext, socket, in);
                } else {
                    socket.close();
                }
                return;
            }
            in.reset();
            EXEC.execute(() -> accept(socket, in));
        } catch (IOException e) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static void accept(Socket socket, InputStream in) {
        try (Socket s = socket) {
            if (!active(sContext)) return;
            s.setSoTimeout(SOCKET_TIMEOUT_MS);
            HouseholdStore store = store(sContext);
            HouseholdSync.Result result = HouseholdSync.run(in, s.getOutputStream(), false, store, pictures(sContext),
                    ShareDiscovery.deviceName(sContext), System.currentTimeMillis());
            finish(store, result, "from a TV");
        } catch (IOException | java.security.GeneralSecurityException e) {
            Log.i(TAG, "A TV tried to sync and couldn't: " + e.getClass().getSimpleName());
        }
    }

    private static void finish(HouseholdStore store, HouseholdSync.Result result, String how) {
        if (result.removedHere) {
            Log.i(TAG, "Another TV of the household has this one removed: forgetting the household");
            stop();
            store.markRemoved();
            prefs(sContext).edit().remove(SEEN_PREF).apply();
            pictures(sContext).clear();
            return;
        }
        if (result.peerRemoved) {
            Log.i(TAG, "A TV removed from the household tried to sync, and was told");
            return;
        }
        noteSeen(result.peer, result.peerName);
        if (store.leaving()) {
            // This TV's removal of itself reached a TV of the household: nothing more to tell
            Log.i(TAG, "Left the household: another TV has it now");
            forget(sContext);
            return;
        }
        store.log().purge(System.currentTimeMillis());
        store.save();
        for (HouseholdEntry entry : result.applied) {
            if (isLook(entry.kind)) {
                looksChanged();
                break;
            }
        }
        if (result.pictures > 0) looksChanged();
        pictures(sContext).keepOnly(HouseholdBridge.pictures(store.log()));
        applyEntries();
        publishUnpublished();
        sLastSyncAt = System.currentTimeMillis();
        sLastResult = "sent " + result.sent + ", took " + result.received;
        Log.i(TAG, "Synced " + how + ": sent " + result.sent + ", took " + result.received + ", changed "
                + result.applied.size());
    }

    // ---- For the settings screen ----

    static Map<String, Object> status(Context context) {
        Map<String, Object> out = new HashMap<>();
        boolean in = mayBeInHousehold(context);
        HouseholdStore store = in ? store(context) : null;
        out.put("joined", store != null && store.joined());
        out.put("lost", store != null && store.lost());
        out.put("removed", store != null && !store.joined() && store.removed());
        out.put("enabled", store == null || store.enabled());
        out.put("tvId", store == null ? null : store.tvId());
        List<Map<String, Object>> peers = new ArrayList<>();
        for (HouseholdNet.Peer peer : HouseholdNet.peers()) {
            Map<String, Object> p = new HashMap<>();
            p.put("tvId", peer.tvId);
            peers.add(p);
        }
        out.put("peers", peers);
        out.put("lastSyncAt", sLastSyncAt);
        out.put("lastResult", sLastResult);
        boolean joined = store != null && store.joined();
        List<Map<String, Object>> members = new ArrayList<>();
        if (joined) {
            Map<String, String> online = new HashMap<>();
            for (HouseholdNet.Peer peer : HouseholdNet.peers()) online.put(peer.tvId, peer.name);
            // The log is the household thread's; an exchange holding it up only leaves out the TVs known from it
            List<HouseholdEntry> entries = new ArrayList<>();
            try {
                entries = EXEC.submit(() -> {
                    HouseholdLog log = store.log();
                    return log == null ? new ArrayList<HouseholdEntry>() : log.all();
                }).get(2, TimeUnit.SECONDS);
            } catch (Exception e) {
                Log.i(TAG, "The list of TVs left out the household's entries: " + e.getClass().getSimpleName());
            }
            for (HouseholdMembers.Member m : HouseholdMembers.list(entries, seen(context), online, store.tvId(),
                    ShareDiscovery.deviceName(context), System.currentTimeMillis())) {
                Map<String, Object> member = new HashMap<>();
                member.put("tvId", m.tvId);
                member.put("name", m.name);
                member.put("self", m.self);
                member.put("online", m.online);
                member.put("lastSeen", m.lastSeen);
                members.add(member);
            }
        }
        out.put("members", members);
        // Households on the network this TV could join (each a list of its TVs' names; a name may be null)
        out.put("nearby", HouseholdMembers.nearby(HouseholdNet.heard(), joined ? store.householdId() : null));
        // A TV asking this one to let it join, for a parent to answer here; and this TV's own request to join one
        out.put("join", HouseholdJoining.status());
        // The name of a TV asking to join, while its request waits for an answer in the Bell
        out.put("asking", HouseholdJoining.requestName());
        return out;
    }

    /** Looks for households on the network to show (the Household page, setup), while this TV is in none. */
    static void lookAround(Context context) {
        if (!active(context)) HouseholdNet.lookAround(context);
    }

    static void stopLooking() {
        HouseholdNet.stopLooking();
    }

    /** Starts a household here. False when this TV is already in one. */
    static boolean create(Context context) {
        boolean ok = store(context).create(ShareDiscovery.deviceName(context), System.currentTimeMillis());
        if (ok) {
            prefs(context).edit().remove(SEEN_PREF).apply();
            start(context);
        }
        return ok;
    }

    /**
     * An invitation for the TV a copy goes to (HouseholdStore.Invitation, as JSON), making a household here first if
     * there is none; null on failure.
     */
    static String invitationToJoin(Context context) {
        HouseholdStore store = store(context);
        if (!store.joined() && !create(context)) return null;
        HouseholdStore.Invitation inv = store.invite(ShareDiscovery.deviceName(context), System.currentTimeMillis());
        return inv == null ? null : inv.toJson();
    }

    /**
     * Joins the household that {@code secrets} (a copy from another TV) carries an invitation to, or the key of when
     * the other TV still runs version 1. False if it carries neither.
     */
    static boolean joinFromSecrets(Context context, String secrets) {
        try {
            org.json.JSONObject root = new org.json.JSONObject(secrets);
            boolean ok;
            String invitation = root.optString("household2", "");
            if (!invitation.isEmpty()) {
                ok = store(context).join(HouseholdStore.Invitation.fromJson(invitation),
                        ShareDiscovery.deviceName(context), System.currentTimeMillis());
            } else {
                String encoded = root.optString("household", "");
                if (encoded.isEmpty()) return false;
                byte[] key = java.util.Base64.getDecoder().decode(encoded);
                ok = store(context).joinV1(key);
                Arrays.fill(key, (byte) 0);
            }
            if (ok) joined(context);
            return ok;
        } catch (Exception e) {
            return false;
        }
    }

    /** A household was joined: a fresh list of TVs seen, sync on, and the first exchange soon. */
    private static void joined(Context context) {
        // The TVs of a household this one was in before aren't members of this one
        prefs(context).edit().remove(SEEN_PREF).apply();
        store(context).setEnabled(true);
        start(context);
    }

    /**
     * Joins with what a TV of the household sent once a parent allowed (HouseholdJoin): its invitation, and its Home
     * Assistant settings when this TV had none. Blocks: not on the main thread.
     */
    static boolean joinFromInvitation(Context context, String payload) {
        Context app = context.getApplicationContext();
        try {
            org.json.JSONObject root = new org.json.JSONObject(payload);
            HouseholdStore.Invitation inv = HouseholdStore.Invitation.fromJson(root.optString("invitation", ""));
            if (inv == null) return false;
            // All of it on the household thread, so a slow exchange there delays the join but can't split it in two
            return EXEC.submit(() -> {
                HouseholdStore store = store(app);
                if (!store.join(inv, ShareDiscovery.deviceName(app), System.currentTimeMillis())) {
                    // The household this TV was in, if any, carries on
                    start(app);
                    return false;
                }
                if (!HaConfig.isConfigured(app) && ShareSecrets.applyHa(app, payload)) {
                    Log.i(TAG, "Joined with the household's Home Assistant settings");
                }
                stop();
                joined(app);
                return true;
            }).get(2, TimeUnit.MINUTES);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't join with the invitation: " + e.getClass().getSimpleName());
            return false;
        }
    }

    /** Asks a TV of the household heard on the network to let this one join (HouseholdJoining). */
    static boolean requestJoin(Context context) {
        HouseholdStore store = store(context);
        return HouseholdJoining.start(context, store.joined() ? store.householdId() : null);
    }

    /** Turns syncing on or off (the one switch). */
    static void setEnabled(Context context, boolean on) {
        store(context).setEnabled(on);
        start(context);
    }

    /**
     * Leaves the household: this TV removes itself from the member list and hands that to the TVs on now (for at most
     * {@link #LEAVE_SYNC_MS}); the first that takes it ends the household here. With none on, this TV stays only to hand
     * it to the first it meets, for up to HouseholdStore.LEAVING_MS. Blocks: not on the main thread.
     */
    static void leave(Context context) {
        if (!mayBeInHousehold(context)) return;
        sContext = context.getApplicationContext();
        try {
            EXEC.submit(() -> {
                HouseholdStore store = store(sContext);
                if (!store.joined()) return;
                store.beginLeaving(System.currentTimeMillis());
                if (store.enabled()) {
                    syncAll("leave");
                } else {
                    // Sync is off: there's no one to tell
                    forget(sContext);
                }
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Leaving the household: no TV took it yet (" + e.getClass().getSimpleName() + ")");
        }
    }

    /** Forgets the household here. On the household thread. */
    private static void forget(Context context) {
        stop();
        store(context).leave();
        prefs(context).edit().remove(SEEN_PREF).apply();
        pictures(context).clear();
    }

    /**
     * Removes another TV from the household: it is taken off the member list, which reaches the other TVs like any
     * change, and they stop syncing with it. False for this TV (that's {@link #leave}) or one this TV can't remove.
     * Blocks: not on the main thread.
     */
    static boolean removeTv(Context context, String tvId) {
        if (!mayBeInHousehold(context)) return false;
        sContext = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                HouseholdStore store = store(sContext);
                if (!store.remove(tvId, System.currentTimeMillis())) return false;
                store.save();
                try {
                    org.json.JSONObject seen = new org.json.JSONObject(prefs(sContext).getString(SEEN_PREF, "{}"));
                    seen.remove(tvId);
                    prefs(sContext).edit().putString(SEEN_PREF, seen.toString()).apply();
                } catch (org.json.JSONException ignored) {
                }
                syncSoon();
                return true;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't remove the TV: " + e.getClass().getSimpleName());
            return false;
        }
    }

    // ---- Looks, layouts and wallpapers (the app puts them in place: they're its settings and files) ----

    private static boolean isLook(String kind) {
        return HouseholdBridge.LOOK.equals(kind) || HouseholdBridge.LAYOUT.equals(kind)
                || HouseholdBridge.WALLPAPER.equals(kind);
    }

    private static synchronized void looksChanged() {
        sLooksVersion++;
    }

    private static synchronized long looksVersion() {
        return sLooksVersion;
    }

    /**
     * The profiles whose look this TV's Hearth keeps: every one, kids' included (Hearth in the owner's user is every
     * profile's home and swaps their layouts; Hearth in a kids profile's own user is only its agent).
     */
    private static boolean keepsLook(Context context, String profileKey) {
        return profileKey != null;
    }

    /**
     * The household's looks, layouts and wallpapers for this TV's profiles (kids' included), when they changed since {@code since} (a
     * version this returned before; 0 for all): {version, profiles: {profileKey: {look, layout, wallpapers: {slot:
     * {hash, path}}}}}. Just {version} when nothing changed, and null when this TV isn't a member. Blocks: not on the
     * main thread.
     */
    static Map<String, Object> looks(Context context, long since) {
        if (!mayBeInHousehold(context)) return null;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app)) return null;
                Map<String, Object> out = new HashMap<>();
                long version = looksVersion();
                out.put("version", version);
                if (since == version) return out;
                HouseholdLog log = store(app).log();
                HouseholdPictures pictures = pictures(app);
                Map<String, Object> profiles = new HashMap<>();
                for (Map.Entry<String, String> profile : local(app).profiles().entrySet()) {
                    String key = profile.getValue();
                    if (!keepsLook(app, key)) continue;
                    Map<String, Object> state = new HashMap<>();
                    HouseholdEntry look = log.get(HouseholdBridge.LOOK, profile.getKey(), "");
                    HouseholdEntry layout = log.get(HouseholdBridge.LAYOUT, profile.getKey(), "");
                    if (look != null) state.put("look", look.value);
                    if (layout != null) state.put("layout", layout.value);
                    Map<String, Object> wallpapers = new HashMap<>();
                    for (String slot : HouseholdBridge.SLOTS) {
                        HouseholdEntry picture = log.get(HouseholdBridge.WALLPAPER, profile.getKey(), slot);
                        if (picture == null) {
                            // Deleted in the household (or never set): the app keeps what it has unless it was a delete
                            if (log.hasEntry(HouseholdBridge.WALLPAPER, profile.getKey(), slot)) wallpapers.put(slot, null);
                            continue;
                        }
                        String hash = HouseholdBridge.pictureOf(picture.value);
                        // A picture not here yet comes with a later exchange: it's left out until then
                        if (hash == null || !pictures.has(hash)) continue;
                        Map<String, Object> file = new HashMap<>();
                        file.put("hash", hash);
                        file.put("path", pictures.file(hash).getAbsolutePath());
                        wallpapers.put(slot, file);
                    }
                    state.put("wallpapers", wallpapers);
                    profiles.put(key, state);
                }
                out.put("profiles", profiles);
                return out;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't read the household's looks: " + e.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * A profile's look or layout ({@code kind}: HouseholdBridge.LOOK or LAYOUT) as this TV has it now, for the
     * household. False when this TV isn't a member, the profile isn't one whose look it keeps, or the value is too big.
     * Blocks: not on the main thread.
     */
    static boolean publishLook(Context context, String profileKey, String kind, String value) {
        if (!mayBeInHousehold(context) || value == null || value.length() > HouseholdBridge.MAX_LOOK_CHARS) return false;
        if (!HouseholdBridge.LOOK.equals(kind) && !HouseholdBridge.LAYOUT.equals(kind)) return false;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app) || !keepsLook(app, profileKey)) return false;
                publish(app, kind, profileKey, "", value);
                looksChanged();
                return true;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * One of a profile's wallpaper pictures ({@code jpeg}; null: the slot has none now) for the household. Returns the
     * picture's hash ("" for none), or null when it couldn't be. Blocks: not on the main thread.
     */
    static String publishPicture(Context context, String profileKey, String slot, byte[] jpeg) {
        if (!mayBeInHousehold(context) || !HouseholdBridge.SLOTS.contains(slot)) return null;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app) || !keepsLook(app, profileKey)) return null;
                String hash = "";
                if (jpeg != null) {
                    hash = pictures(app).write(jpeg, null);
                    if (hash == null) return null;
                }
                publish(app, HouseholdBridge.WALLPAPER, profileKey, slot,
                        jpeg == null ? null : HouseholdBridge.wallpaperValue(hash));
                looksChanged();
                return hash;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            return null;
        }
    }

    /** Syncs now, for the screen's button. */
    static void syncNowAsync(Context context) {
        sContext = context.getApplicationContext();
        EXEC.execute(() -> syncAll("button"));
    }
}
