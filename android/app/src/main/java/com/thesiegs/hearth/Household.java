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
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
    /** How long after a play is saved its title goes out: plays save often, and one sweep covers them all. */
    private static final long WATCH_DELAY_MS = 60_000;

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

    /**
     * Since when this TV, having just joined, holds the household's settings until someone has seen what they change
     * (docs/household-sync.md, "Before joining"); and whether the first exchange has brought them yet.
     */
    private static final String REVIEW_PREF = "join_review";
    private static final String REVIEW_READY_PREF = "join_review_ready";
    /** The copy of this TV's pairings and PINs from before it joined (sealed), and when it was made. */
    private static final String JOIN_BACKUP_PREF = "join_backup";
    private static final String JOIN_BACKUP_AT_PREF = "join_backup_at";
    private static final String JOIN_BACKUP_ALIAS = "hearth_household_join_backup";
    /** How long that copy is kept. */
    static final long JOIN_BACKUP_MS = 14L * 24 * 60 * 60_000;

    private static Context sContext;
    /** Goes up whenever a look, layout or wallpaper changed here (from another TV or published): the app checks it. */
    private static long sLooksVersion = 1;
    private static HouseholdStore sStore;
    private static boolean sSyncQueued;
    private static boolean sWatchQueued;
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

    /** This TV joined and holds the household's settings, and its own, until someone has seen what changes. */
    private static boolean reviewing(Context context) {
        return prefs(context).getString(REVIEW_PREF, null) != null;
    }

    /** A member that takes and gives settings: not one still holding them after joining. */
    private static boolean giving(Context context) {
        return member(context) && !reviewing(context);
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
                    // A profile whose Google account Hearth has seen since takes its titles now
                    applyWatch(null);
                    publishWatch();
                    // A notification past its time leaves the Bell
                    refreshNotices(sContext);
                    syncAll("periodic");
                }, PERIODIC_MS, PERIODIC_MS, TimeUnit.MILLISECONDS);
            }
        }
        EXEC.execute(() -> {
            publishSelf();
            publishUnpublished();
            applyEntries();
            applyWatch(null);
            publishWatch();
            refreshNotices(sContext);
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

    // ---- Continue Watching (HouseholdWatch) ----

    /** Something was played or listed in Continue Watching here: it goes out within a minute (a play saves often). */
    static void onWatchChanged(Context context) {
        if (!mayBeInHousehold(context)) return;
        sContext = context.getApplicationContext();
        synchronized (Household.class) {
            if (sWatchQueued) return;
            sWatchQueued = true;
        }
        EXEC.schedule(() -> {
            synchronized (Household.class) {
                sWatchQueued = false;
            }
            publishWatch();
        }, WATCH_DELAY_MS, TimeUnit.MILLISECONDS);
    }

    /** A profile's title was taken out of Continue Watching here (or finished): gone from the other TVs too. */
    static void onWatchRemoved(Context context, String profileKey, String kind, String pkg, String item) {
        if (!mayBeInHousehold(context) || profileKey == null) return;
        Context app = context.getApplicationContext();
        EXEC.execute(() -> {
            if (member(app)) publish(app, HouseholdBridge.WATCH, profileKey, HouseholdWatch.itemOf(kind, pkg, item), null);
        });
    }

    /** Each person's own newest titles that differ from the household's become entries. On the household thread. */
    private static void publishWatch() {
        if (sContext == null || !member(sContext)) return;
        HouseholdStore store = store(sContext);
        HouseholdLog log = store.log();
        WatchHistory history = WatchHistory.get(sContext);
        HouseholdPictures pictures = pictures(sContext);
        long now = System.currentTimeMillis();
        int sent = 0;
        int[] fetches = {POSTER_FETCHES_PER_ROUND};
        for (Map.Entry<String, String> person : local(sContext).profiles().entrySet()) {
            for (WatchHistory.Entry e : HouseholdWatch.toSend(history.ownEntries(person.getValue()), now)) {
                String item = HouseholdWatch.itemOf(e.kind, e.packageName, e.item);
                // A kept entry's poster goes with it: the other TV can't load this one's address for it
                String poster = WatchHistory.KEPT.equals(e.kind) ? posterOf(history, pictures, e, fetches, now) : null;
                String value = HouseholdWatch.valueOf(e, poster);
                if (!HouseholdWatch.sends(e, value, log.entry(HouseholdBridge.WATCH, person.getKey(), item))) continue;
                if (log.put(HouseholdBridge.WATCH, person.getKey(), item, value, now) != null) sent++;
            }
        }
        if (sent == 0) return;
        store.save();
        Log.i(TAG, "Continue Watching: " + sent + " title(s) for the household");
        syncSoon();
    }

    /** New posters made for the household in one round at most (each may be a download); the rest wait a round. */
    private static final int POSTER_FETCHES_PER_ROUND = 10;

    /**
     * The household picture of a kept entry's poster (its hash), made once per poster address and kept in
     * HouseholdPictures; null when the entry has none or it can't be read. {@code fetches}: how many new ones this
     * round may still make.
     */
    private static String posterOf(WatchHistory history, HouseholdPictures pictures, WatchHistory.Entry e,
            int[] fetches, long now) {
        String uri = posterAddressOf(e.row);
        if (uri == null) return null;
        String own = HouseholdWatch.posterHashOf(uri);
        if (own != null) return pictures.has(own) ? own : null;
        String known = history.posterFor(uri);
        if (WatchHistory.NO_POSTER.equals(known)) return null;
        if (known != null && pictures.has(known)) {
            history.rememberPoster(uri, known, now);
            return known;
        }
        if (fetches[0] <= 0) return null;
        fetches[0]--;
        String hash = null;
        byte[] jpeg = WatchNextPosters.forHousehold(sContext, uri);
        if (jpeg != null) hash = pictures.write(jpeg, null);
        history.rememberPoster(uri, hash != null ? hash : WatchHistory.NO_POSTER, now);
        return hash;
    }

    private static String posterAddressOf(String row) {
        if (row == null) return null;
        try {
            String uri = new org.json.JSONObject(row).optString("posterArtUri", "");
            return uri.isEmpty() ? null : uri;
        } catch (org.json.JSONException e) {
            return null;
        }
    }

    /**
     * Puts the household's Continue Watching entries among {@code entries} (null: all of them) in place for this TV's
     * profiles.
     */
    private static void applyWatch(List<HouseholdEntry> entries) {
        if (sContext == null || !member(sContext)) return;
        if (entries == null) entries = store(sContext).log().all();
        Map<String, String> profiles = local(sContext).profiles();
        WatchHistory history = WatchHistory.get(sContext);
        long now = System.currentTimeMillis();
        int changed = 0;
        for (HouseholdEntry entry : entries) {
            if (!HouseholdBridge.WATCH.equals(entry.kind)) continue;
            String key = profiles.get(entry.profile);
            if (key == null) continue;
            if (entry.deleted) {
                String[] parts = HouseholdWatch.partsOf(entry.item);
                if (parts != null && history.removeShared(key, parts[0], parts[1], parts[2],
                        HouseholdLog.millisOf(entry))) changed++;
                continue;
            }
            HouseholdWatch.Card card = HouseholdWatch.cardOf(entry);
            if (card != null && history.applyShared(key, card, now)) changed++;
        }
        if (changed > 0) Log.i(TAG, "Continue Watching: took " + changed + " title(s) from the household");
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
        if (sContext == null || !giving(sContext)) return;
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
        if (sContext == null || !giving(sContext)) return;
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
        } catch (IOException | RuntimeException | StackOverflowError e) {
            // Whatever a device on the network sends: an uncaught error on this pool's thread would end Hearth
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
            prefs(sContext).edit().remove(SEEN_PREF).remove(REVIEW_PREF).remove(REVIEW_READY_PREF).apply();
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
        // A TV that just joined has the household's entries now: what they'd change can be shown
        if (reviewing(sContext)) prefs(sContext).edit().putString(REVIEW_READY_PREF, "1").apply();
        applyEntries();
        applyWatch(result.applied);
        noticesArrived(result.applied);
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
        // Just joined and holding the household's settings until someone sees what they change; ready once they came
        if (joined && reviewing(context)) {
            Map<String, Object> review = new HashMap<>();
            review.put("ready", prefs(context).getString(REVIEW_READY_PREF, null) != null);
            out.put("review", review);
        }
        // When the copy of this TV's settings from before it joined was made, while it's kept (0: none)
        out.put("joinBackupAt", joinBackupAt(context));
        return out;
    }

    // ---- Before joining: what changes, and the copy to put back (docs/household-sync.md, "Before joining") ----

    /**
     * What the household's entries would change in this TV's pairings and PINs, while it holds them after joining:
     * {profiles: [{key, name, kids, pairings, pins}], tvPins}, a profile listed whether or not anything of it changes
     * (the app adds its looks). Null when this TV isn't holding any. Blocks: not on the main thread.
     */
    static Map<String, Object> joinPreview(Context context) {
        if (!mayBeInHousehold(context)) return null;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app) || !reviewing(app)) return null;
                HouseholdLocal local = local(app);
                Map<String, int[]> changes = HouseholdJoinReview.changes(local, store(app).log());
                List<Map<String, Object>> profiles = new ArrayList<>();
                for (String key : local.profiles().values()) {
                    int[] counts = changes.get(key);
                    Map<String, Object> profile = new HashMap<>();
                    profile.put("key", key);
                    profile.put("name", ProfileUsers.displayName(app, key));
                    profile.put("kids", ProfilePairing.isKids(app, key));
                    profile.put("pairings", counts == null ? 0 : counts[0]);
                    profile.put("pins", counts == null ? 0 : counts[1]);
                    profiles.add(profile);
                }
                int[] tv = changes.get(HouseholdJoinReview.TV);
                Map<String, Object> out = new HashMap<>();
                out.put("profiles", profiles);
                out.put("tvPins", tv == null ? 0 : tv[1]);
                return out;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't tell what joining changes: " + e.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * Someone saw what joining changes and went on: this TV's pairings and PINs are kept as a copy (sealed), then the
     * household's are put in place and this TV's own go out. False when the copy couldn't be kept (nothing changes
     * then). Blocks: not on the main thread.
     */
    static boolean finishJoin(Context context) {
        if (!mayBeInHousehold(context)) return false;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app) || !reviewing(app)) return false;
                String sealed = SecretBox.sealText(SecretBox.keystore(), JOIN_BACKUP_ALIAS,
                        HouseholdJoinReview.snapshot(local(app)));
                if (sealed == null) return false;
                prefs(app).edit()
                        .putString(JOIN_BACKUP_PREF, sealed)
                        .putLong(JOIN_BACKUP_AT_PREF, System.currentTimeMillis())
                        .remove(REVIEW_PREF)
                        .remove(REVIEW_READY_PREF)
                        .apply();
                applyEntries();
                publishUnpublished();
                syncSoon();
                Log.i(TAG, "Joined: the household's settings are in place, this TV's are kept as a copy");
                return true;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't finish joining: " + e.getClass().getSimpleName());
            return false;
        }
    }

    /** When the copy from before joining was made, while it's kept; 0 when there is none (a stale one is dropped). */
    static long joinBackupAt(Context context) {
        SharedPreferences prefs = prefs(context);
        long at = prefs.getLong(JOIN_BACKUP_AT_PREF, 0);
        if (at == 0) return 0;
        if (System.currentTimeMillis() - at > JOIN_BACKUP_MS || prefs.getString(JOIN_BACKUP_PREF, null) == null) {
            prefs.edit().remove(JOIN_BACKUP_PREF).remove(JOIN_BACKUP_AT_PREF).apply();
            return 0;
        }
        return at;
    }

    /**
     * Puts back this TV's pairings and PINs from before it joined (what the household added stays), then drops the
     * copy; the ones put back are the newest now and go to the other TVs. False when there's no copy or it doesn't
     * open. Blocks: not on the main thread.
     */
    static boolean restoreJoinBackup(Context context) {
        Context app = context.getApplicationContext();
        if (joinBackupAt(app) == 0) return false;
        try {
            return EXEC.submit(() -> {
                String text = SecretBox.openText(SecretBox.keystore(), JOIN_BACKUP_ALIAS,
                        prefs(app).getString(JOIN_BACKUP_PREF, null));
                if (text == null) return false;
                int changed = HouseholdJoinReview.restore(local(app), text);
                if (changed < 0) return false;
                prefs(app).edit().remove(JOIN_BACKUP_PREF).remove(JOIN_BACKUP_AT_PREF).apply();
                Log.i(TAG, "Put back " + changed + " setting(s) from before joining");
                return true;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't put back the settings from before joining: " + e.getClass().getSimpleName());
            return false;
        }
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
     * An invitation for a TV allowed to join (HouseholdStore.Invitation, as JSON), making a household here first if
     * there is none; null on failure.
     */
    static String invitationToJoin(Context context) {
        HouseholdStore store = store(context);
        if (!store.joined() && !create(context)) return null;
        HouseholdStore.Invitation inv = store.invite(ShareDiscovery.deviceName(context), System.currentTimeMillis());
        return inv == null ? null : inv.toJson();
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
                if (!HaConfig.isConfigured(app) && applyHa(app, root.optJSONObject("ha"))) {
                    Log.i(TAG, "Joined with the household's Home Assistant settings");
                }
                // The household's settings wait until someone has seen what they change here (finishJoin)
                prefs(app).edit()
                        .putString(REVIEW_PREF, Long.toString(System.currentTimeMillis()))
                        .remove(REVIEW_READY_PREF)
                        .apply();
                stop();
                joined(app);
                return true;
            }).get(2, TimeUnit.MINUTES);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't join with the invitation: " + e.getClass().getSimpleName());
            return false;
        }
    }

    /**
     * The Home Assistant address and token a TV of the household made for this one ({url, token}), saved as this TV's:
     * false when there are none or they're unusable.
     */
    private static boolean applyHa(Context context, org.json.JSONObject ha) {
        if (ha == null) return false;
        String url = HaConfig.normalizeUrl(ha.optString("url", ""));
        String token = ha.optString("token", "").replaceAll("\\s", "");
        if (url == null || token.isEmpty() || token.length() > 4096) return false;
        if (!HaConfig.setToken(context, token)) return false;
        HaConfig.prefs(context).edit().putString(HaConfig.URL_KEY, url).apply();
        HaBridgeService.sync(context);
        return true;
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
        // The copy from before joining stays for its days: it's this TV's own settings
        prefs(context).edit().remove(SEEN_PREF).remove(REVIEW_PREF).remove(REVIEW_READY_PREF).apply();
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
                // Just joined: the app shows what would change rather than taking it (it doesn't give either)
                if (reviewing(app)) out.put("review", true);
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
                if (!giving(app) || !keepsLook(app, profileKey)) return false;
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
                if (!giving(app) || !keepsLook(app, profileKey)) return null;
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

    // ---- The Parent PIN (the app keeps it: HouseholdParentPin on the Dart side) ----

    /** What a stored Parent PIN may look like (ParentPinHash in Dart): the old 64 hex digits or the salted form. */
    static final java.util.regex.Pattern PARENT_PIN_HASH =
            java.util.regex.Pattern.compile("^([0-9a-f]{64}|v2\\$[0-9]{1,7}\\$[0-9a-f]{32}\\$[0-9a-f]{64})$");

    /**
     * The household's Parent PIN: {state: "live" (with its hash), "removed" or "none"}; null when this TV isn't a
     * member. Blocks: not on the main thread.
     */
    static Map<String, Object> parentPin(Context context) {
        if (!mayBeInHousehold(context)) return null;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!member(app)) return null;
                HouseholdEntry entry = store(app).log().entry(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "");
                Map<String, Object> out = new HashMap<>();
                if (entry == null) {
                    out.put("state", "none");
                } else if (entry.deleted) {
                    out.put("state", "removed");
                } else if (PARENT_PIN_HASH.matcher(entry.value).matches()) {
                    out.put("state", "live");
                    out.put("hash", entry.value);
                } else {
                    // Not one a TV would write: as if there were none, and this TV's can replace it
                    out.put("state", "none");
                }
                return out;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't read the household's Parent PIN: " + e.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * This TV's Parent PIN (its stored hash; null: removed) for the household. The app decides when (HouseholdParentPin):
     * only a change made here, past the PIN, goes out. False when this TV isn't a member or the hash isn't one. Blocks:
     * not on the main thread.
     */
    static boolean publishParentPin(Context context, String hash) {
        if (!mayBeInHousehold(context) || (hash != null && !PARENT_PIN_HASH.matcher(hash).matches())) return false;
        Context app = context.getApplicationContext();
        try {
            return EXEC.submit(() -> {
                if (!giving(app)) return false;
                publish(app, HouseholdBridge.PARENT_PIN, null, "", hash);
                return true;
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            return false;
        }
    }

    // ---- Notifications (HouseholdNotices; the Bell shows them through HearthBellItems) ----

    /** How long Home Assistant's request waits for the household thread before the pop-up goes ahead without it. */
    private static final long NOTICE_WAIT_MS = 5_000;
    /**
     * The notifications of a TV that isn't a member (or has sync off): this TV's own, in memory only, so they're gone
     * when Hearth restarts. On the household thread.
     */
    private static final String LOCAL_NOTICES_TV = "this-tv";
    private static final HouseholdLog LOCAL_NOTICES = new HouseholdLog(LOCAL_NOTICES_TV);
    /** What the Bell shows the profile on screen, newest first; made on the household thread. */
    private static volatile List<HouseholdNotices.Notice> sNotices = new ArrayList<>();
    /** The profile {@link #sNotices} is for (its key). */
    private static volatile String sNoticesFor;
    /** The notifications (item and time) already popped up, or there before Hearth started: each pops up once. */
    private static final Set<String> sPopped = new HashSet<>();
    private static boolean sNoticesRead;

    /**
     * The Bell's notifications for the profile on screen (HearthBellItems); none for a moment after a switch, until
     * they're worked out for the profile that came on, so one profile's never show to another.
     */
    static List<HouseholdNotices.Notice> notices(Context context) {
        List<HouseholdNotices.Notice> notices = sNotices;
        String key = LauncherAccessibilityService.getActiveProfileKey(context);
        return key != null && key.equals(sNoticesFor) ? notices : new ArrayList<>();
    }

    /** Where notifications are kept: the household's log while this TV is a member, else this TV's own. */
    private static HouseholdLog noticeLog(Context context) {
        return member(context) ? store(context).log() : LOCAL_NOTICES;
    }

    /** This TV's profiles, each with who it is: its person id in a household, else its key (this TV's alone). */
    private static List<HouseholdNotices.Person> people(Context context) {
        List<HouseholdNotices.Person> out = new ArrayList<>();
        if (member(context)) {
            for (Map.Entry<String, String> p : local(context).profiles().entrySet()) {
                out.add(new HouseholdNotices.Person(p.getValue(), p.getKey(),
                        ProfileUsers.displayName(context, p.getValue()), ProfileUsers.emailOf(context, p.getValue())));
            }
            return out;
        }
        Set<String> keys = new LinkedHashSet<>(ProfilePairing.getHearthProfiles(context));
        String active = LauncherAccessibilityService.getActiveProfileKey(context);
        if (active != null) keys.add(active);
        for (String key : keys) {
            out.add(new HouseholdNotices.Person(key, "k:" + key, ProfileUsers.displayName(context, key),
                    ProfileUsers.emailOf(context, key)));
        }
        return out;
    }

    /** Who the profile on screen is, as {@link #people} names it; null when that isn't known. */
    private static String personOnScreen(Context context) {
        return personOf(context, LauncherAccessibilityService.getActiveProfileKey(context));
    }

    private static String personOf(Context context, String key) {
        if (key == null) return null;
        if (!member(context)) return "k:" + key;
        String id = local(context).personIdOf(key);
        return id == null || id.isEmpty() ? null : id;
    }

    /**
     * A notification from Home Assistant (HaNotificationServer), answered as HaNotificationServer.Listener says. It
     * goes in the Bell, on every TV of the household, for the person its {@code for} names (none: every adult), and
     * pops up here as before when it is for everyone or for the profile on screen. A "clear_notification" with a tag
     * clears the one with that tag instead. Blocks: not on the main thread.
     */
    static int onHaNotification(Context context, HaNotificationServer.Notification n) {
        Context app = context.getApplicationContext();
        sContext = app;
        boolean[] onScreen = {n.target == null};
        java.util.concurrent.Future<Integer> filed = EXEC.submit(() -> {
            String person = HouseholdNotices.ALL_ADULTS;
            if (n.target != null) {
                person = HouseholdNotices.target(n.target, people(app));
                if (person == null) return HaNotificationServer.UNKNOWN_PERSON;
                onScreen[0] = person.equals(personOnScreen(app));
            }
            HouseholdLog log = noticeLog(app);
            long now = System.currentTimeMillis();
            if (n.clears()) {
                String item = HouseholdNotices.haItem(person, n.tag, null, null);
                if (log.get(HouseholdNotices.KIND, person, item) != null) {
                    log.delete(HouseholdNotices.KIND, person, item, now);
                    noticesChanged(app, log);
                }
                return HaNotificationServer.SHOWN;
            }
            String value = HouseholdNotices.haValue(n.title, n.message, n.actions, now);
            if (value == null) return -1;
            String item = HouseholdNotices.haItem(person, n.tag, n.title, n.message);
            String writer = log == LOCAL_NOTICES ? LOCAL_NOTICES_TV : store(app).tvId();
            if (!HouseholdNotices.roomFor(log.all(), writer, item)) {
                // A flood from the network: it pops up as before, but isn't kept
                Log.i(TAG, "A Home Assistant notification isn't kept in the Bell: too many already");
                return -1;
            }
            HouseholdEntry entry = log.put(HouseholdNotices.KIND, person, item, value, now);
            if (entry != null) {
                // It pops up here as it comes (or not at all), never again from the Bell
                long at = HouseholdLog.millisOf(entry);
                synchronized (sPopped) {
                    sPopped.add(entry.item + "@" + at);
                }
                // Its buttons in the pop-up go the household's way: run once, and it goes from every Bell
                HouseholdNotices.Notice kept = HouseholdNotices.parse(entry);
                if (kept != null && kept.actions.size() == n.actions.size() && !n.actions.isEmpty()) {
                    String who = person;
                    n.onAction = index -> pressNotice(app, who, entry.item, at, index);
                }
                noticesChanged(app, log);
            }
            return -1;
        });
        int result;
        boolean show;
        try {
            result = filed.get(NOTICE_WAIT_MS, TimeUnit.MILLISECONDS);
            show = onScreen[0];
        } catch (Exception e) {
            // The household thread is busy (an exchange): the Bell gets it when it's free, and a notification for
            // everyone pops up as before
            Log.i(TAG, "A Home Assistant notification waits for the Bell: " + e.getClass().getSimpleName());
            result = -1;
            show = n.target == null;
        }
        if (result >= 0) return result;
        if (!show) return HaNotificationServer.SHOWN;
        if (LauncherAccessibilityService.showHaNotification(n)) return HaNotificationServer.SHOWN;
        // For everyone: Home Assistant is told it couldn't pop up, as before. One for a person is in their Bell.
        return n.target == null ? HaNotificationServer.CANT_SHOW : HaNotificationServer.SHOWN;
    }

    /** A notification was written or cleared here: saved and sent when it's the household's, and the Bell changes. */
    private static void noticesChanged(Context context, HouseholdLog log) {
        if (log != LOCAL_NOTICES) {
            store(context).save();
            syncSoon();
        }
        refreshNotices(context);
    }

    /** An exchange brought these: the Bell changes when notifications are among them, and a join answer is taken. */
    private static void noticesArrived(List<HouseholdEntry> applied) {
        for (HouseholdEntry entry : applied) {
            if (HouseholdNotices.KIND.equals(entry.kind) || HouseholdNotices.ANSWER.equals(entry.kind)
                    || HouseholdNotices.PRESS.equals(entry.kind)) {
                runPresses(sContext);
                refreshNotices(sContext);
                HouseholdJoining.answeredInHousehold(store(sContext).log().all());
                return;
            }
        }
    }

    /** The profile on screen changed: the Bell shows its notifications. */
    static void noticesProfileChanged(Context context) {
        Context app = context.getApplicationContext();
        sContext = app;
        EXEC.execute(() -> refreshNotices(app));
    }

    /**
     * Works out what the Bell shows the profile on screen, and pops up what came from another TV since: a join request
     * while it waits, another notification while it's a couple of minutes old. On the household thread.
     */
    private static void refreshNotices(Context context) {
        if (context == null) return;
        HouseholdLog log = noticeLog(context);
        long now = System.currentTimeMillis();
        if (log == LOCAL_NOTICES) log.purge(now);
        String ownTv = log == LOCAL_NOTICES ? null : store(context).tvId();
        String key = LauncherAccessibilityService.getActiveProfileKey(context);
        List<HouseholdNotices.Notice> visible = HouseholdNotices.visible(log.all(), personOf(context, key),
                ProfileUsers.isKids(context), ownTv, now);
        sNoticesFor = null;
        sNotices = visible;
        sNoticesFor = key;
        List<HouseholdNotices.Notice> popUp = new ArrayList<>();
        synchronized (sPopped) {
            if (sPopped.size() > 1000) sPopped.clear();
            for (HouseholdNotices.Notice n : visible) {
                if (!sPopped.add(n.item + "@" + n.at) || !sNoticesRead || n.writer.equals(ownTv)) continue;
                if (n.isJoin() || now - n.at < HouseholdNotices.POP_UP_MS) popUp.add(n);
            }
            sNoticesRead = true;
        }
        LauncherNotificationListenerService.hearthItemsChanged();
        for (HouseholdNotices.Notice n : popUp) HearthBellItems.popUp(context, n);
    }

    /** Clears a notification from the Bell, and so from the household's other TVs. */
    static void clearNotice(Context context, String person, String item) {
        Context app = context.getApplicationContext();
        sContext = app;
        EXEC.execute(() -> {
            HouseholdLog log = noticeLog(app);
            if (log.get(HouseholdNotices.KIND, person, item) == null) return;
            log.delete(HouseholdNotices.KIND, person, item, System.currentTimeMillis());
            noticesChanged(app, log);
        });
    }

    /** Clear all in the Bell: every notification the profile on screen sees, except a TV asking to join. */
    static void clearNotices(Context context) {
        Context app = context.getApplicationContext();
        sContext = app;
        EXEC.execute(() -> {
            HouseholdLog log = noticeLog(app);
            long now = System.currentTimeMillis();
            int cleared = 0;
            for (HouseholdNotices.Notice n : sNotices) {
                if (n.isJoin() || log.get(HouseholdNotices.KIND, n.person, n.item) == null) continue;
                log.delete(HouseholdNotices.KIND, n.person, n.item, now);
                cleared++;
            }
            if (cleared > 0) noticesChanged(app, log);
        });
    }

    /**
     * A Home Assistant notification's button pressed in the Bell: only one the profile on screen sees there (so never an
     * adult's on a kids profile). False when it isn't in this TV's Bell, or has no such button.
     */
    static boolean pressNotice(Context context, String person, String item, int index) {
        HouseholdNotices.Notice listed = null;
        for (HouseholdNotices.Notice n : sNotices) {
            if (!n.isJoin() && n.item.equals(item) && n.person.equals(person)) listed = n;
        }
        if (listed == null || index < 0 || index >= listed.actions.size()) return false;
        pressNotice(context, person, item, listed.at, index);
        return true;
    }

    /**
     * Button {@code index} of the notification {@code item} written at {@code at} pressed, in the Bell or a pop-up. A TV
     * with its own Home Assistant connection, or the one that received the notification, deletes it (so it goes from
     * every TV) and calls the service itself; any other asks the receiving TV with a {@link HouseholdNotices#PRESS}
     * entry ({@link #runPresses}). Either way, nothing more happens once it's handled: the button run is the one in
     * this TV's copy, and a second press anywhere finds it gone (or already pressed).
     */
    static void pressNotice(Context context, String person, String item, long at, int index) {
        Context app = context.getApplicationContext();
        sContext = app;
        EXEC.execute(() -> {
            HouseholdLog log = noticeLog(app);
            HouseholdNotices.Notice n = HouseholdNotices.parse(log.get(HouseholdNotices.KIND, person, item));
            if (n == null || n.at != at || index < 0 || index >= n.actions.size()) return;
            long now = System.currentTimeMillis();
            boolean mine = log == LOCAL_NOTICES || n.writer.equals(store(app).tvId());
            if (mine || HaConfig.isConfigured(app)) {
                log.delete(HouseholdNotices.KIND, person, item, now);
                noticesChanged(app, log);
                callAction(app, n.actions.get(index));
                return;
            }
            if (HouseholdNotices.pressed(log.all(), n) >= 0) return;
            log.put(HouseholdNotices.PRESS, person, item, HouseholdNotices.pressValue(index, at), now);
            Log.i(TAG, "A notification's button pressed: the TV that received it runs it");
            noticesChanged(app, log);
        });
    }

    /**
     * Runs the buttons other TVs pressed on notifications this TV received (HouseholdNotices.due): each notification is
     * deleted first, so it goes from every Bell and its button runs at most once. On the household thread.
     */
    private static void runPresses(Context context) {
        if (context == null || !member(context)) return;
        HouseholdLog log = store(context).log();
        List<HouseholdNotices.Due> due = HouseholdNotices.due(log.all(), store(context).tvId(),
                System.currentTimeMillis());
        if (due.isEmpty()) return;
        long now = System.currentTimeMillis();
        for (HouseholdNotices.Due d : due) {
            log.delete(HouseholdNotices.KIND, d.notice.person, d.notice.item, now);
            if (d.action != null) {
                callAction(context, d.action);
            } else {
                Log.i(TAG, "A notification's button pressed on another TV came too late to run; cleared it");
            }
        }
        noticesChanged(context, log);
    }

    /** Calls a notification button's service with this TV's Home Assistant token, off the household thread. */
    private static void callAction(Context context, HouseholdNotices.Action action) {
        String[] service = action.service.split("\\.", 2);
        org.json.JSONObject data = action.dataObject();
        HaApi.EXECUTOR.execute(() -> {
            boolean ok = HaApi.callService(context, service[0], service[1], data);
            Log.i(TAG, "A notification's button ran " + service[0] + (ok ? "" : ": Home Assistant refused or is away"));
        });
    }

    /**
     * Allow or Don't allow pressed for another TV's join request: the answer goes to the TV that holds it, which takes
     * the first answer it hears. A second answer, here or anywhere, changes nothing. False when the request isn't in
     * this TV's Bell.
     */
    static boolean answerJoin(Context context, String item, boolean allow) {
        boolean listed = false;
        for (HouseholdNotices.Notice n : sNotices) listed |= n.isJoin() && n.item.equals(item);
        if (!listed) return false;
        Context app = context.getApplicationContext();
        sContext = app;
        EXEC.execute(() -> {
            if (!member(app)) return;
            HouseholdLog log = store(app).log();
            if (log.get(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, item) == null
                    || HouseholdNotices.answer(log.all(), item) != null) return;
            log.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item, HouseholdNotices.answerValue(allow),
                    System.currentTimeMillis());
            Log.i(TAG, "Answered another TV's join request: " + (allow ? "allow" : "don't allow"));
            noticesChanged(app, log);
        });
        return true;
    }

    /** A TV asks this one to join (HouseholdJoining): the request goes in the Bell of the household's other TVs too. */
    static void joinRequestStarted(Context context, String requestId, String joiner, long untilMs) {
        Context app = context.getApplicationContext();
        EXEC.execute(() -> {
            if (!member(app)) return;
            HouseholdStore store = store(app);
            long now = System.currentTimeMillis();
            store.log().put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, HouseholdNotices.joinItem(requestId),
                    HouseholdNotices.joinValue(joiner, store.tvId(), ShareDiscovery.deviceName(app), now, untilMs), now);
            noticesChanged(app, store.log());
        });
    }

    /** The request was answered, or ran out: it goes from the other TVs' Bells. */
    static void joinRequestEnded(Context context, String requestId) {
        Context app = context.getApplicationContext();
        EXEC.execute(() -> {
            if (!member(app)) return;
            HouseholdLog log = store(app).log();
            String item = HouseholdNotices.joinItem(requestId);
            if (log.get(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, item) == null) return;
            log.delete(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, item, System.currentTimeMillis());
            noticesChanged(app, log);
        });
    }

    /** Syncs now, for the screen's button. */
    static void syncNowAsync(Context context) {
        sContext = context.getApplicationContext();
        EXEC.execute(() -> syncAll("button"));
    }
}
