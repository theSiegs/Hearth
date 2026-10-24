package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * This TV's part in a household (docs/household-sync.md): the one place that knows whether sync is on, hears about
 * changes to Profile Pairing and saved PINs, and runs the exchanges with the other TVs. Everything that touches the
 * entries runs on one thread, so changes and exchanges never overlap. Where this TV is in no household every call
 * here is a cheap no-op, and the Keystore is never touched.
 */
final class Household {
    private static final String TAG = "HearthHousehold";
    private static final String PREFS = "household";
    private static final String KEY_SEALED_PREF = "key_sealed";
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

    private static Context sContext;
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
        return prefs(context).getString(KEY_SEALED_PREF, null) != null;
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
            }, SecretBox.keystore());
        }
        return sStore;
    }

    private static HouseholdLocal local(Context context) {
        return new HouseholdLocal(context, store(context).seal());
    }

    /** Sync is on: in a household and the switch is on. */
    private static boolean active(Context context) {
        if (!mayBeInHousehold(context)) return false;
        HouseholdStore store = store(context);
        return store.joined() && store.enabled();
    }

    // ---- Starting and stopping ----

    /** Starts listening, announcing and syncing when this TV is in a household with sync on; stops when it isn't. */
    static void start(Context context) {
        if (!active(context)) {
            stop();
            return;
        }
        HouseholdStore store = store(context);
        HouseholdNet.start(context, store.tvId(), store.householdId(), socket -> EXEC.execute(() -> accept(socket)));
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

    /** This TV's own entry (HouseholdMembers), so the others list it: written when missing, renamed or a day old. */
    private static void publishSelf() {
        if (sContext == null || !active(sContext)) return;
        HouseholdStore store = store(sContext);
        String name = ShareDiscovery.deviceName(sContext);
        long now = System.currentTimeMillis();
        if (!HouseholdMembers.selfNeedsWrite(store.log(), store.tvId(), name, now)) return;
        store.log().put(HouseholdMembers.KIND, HouseholdBridge.SHARED, store.tvId(), HouseholdMembers.value(name), now);
        store.save();
        syncSoon();
    }

    /** A TV of the household synced with this one: kept, so it is listed while it's off. */
    private static void noteSeen(HouseholdNet.Peer peer) {
        if (peer == null || sContext == null) return;
        try {
            SharedPreferences prefs = prefs(sContext);
            org.json.JSONObject seen = new org.json.JSONObject(prefs.getString(SEEN_PREF, "{}"));
            seen.put(peer.tvId, new org.json.JSONObject().put("name", peer.name == null ? "" : peer.name)
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

    private static HouseholdNet.Peer peerAt(java.net.InetAddress address) {
        if (address == null) return null;
        for (HouseholdNet.Peer peer : HouseholdNet.peers()) {
            if (peer.host.equals(address.getHostAddress())) return peer;
        }
        return null;
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
            if (!active(context)) return;
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
            if (active(context)) publish(context, HouseholdBridge.PIN, owner, pkg + "|" + appProfile, null);
        });
    }

    static void onPairingChanged(Context context, String pkg, String profileKey) {
        if (!mayBeInHousehold(context)) return;
        EXEC.execute(() -> {
            if (!active(context)) return;
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
        if (sContext == null || !active(sContext)) return;
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
        if (sContext == null || !active(sContext)) return;
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
        for (HouseholdNet.Peer peer : HouseholdNet.peers()) exchangeWith(peer, why);
    }

    private static void exchangeWith(HouseholdNet.Peer peer, String why) {
        HouseholdStore store = store(sContext);
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(peer.host, peer.port), 5_000);
            socket.setSoTimeout(SOCKET_TIMEOUT_MS);
            HouseholdSync.Result result = HouseholdSync.run(socket.getInputStream(), socket.getOutputStream(), true,
                    store, System.currentTimeMillis());
            finish(store, result, "to " + why);
            noteSeen(peer);
        } catch (IOException | java.security.GeneralSecurityException e) {
            sLastResult = "failed: " + e.getClass().getSimpleName();
            Log.i(TAG, "Couldn't sync with a TV of the household: " + e.getClass().getSimpleName());
        }
    }

    private static void accept(Socket socket) {
        try (Socket s = socket) {
            if (!active(sContext)) return;
            s.setSoTimeout(SOCKET_TIMEOUT_MS);
            HouseholdStore store = store(sContext);
            HouseholdSync.Result result = HouseholdSync.run(s.getInputStream(), s.getOutputStream(), false, store,
                    System.currentTimeMillis());
            finish(store, result, "from a TV");
            // The sealed exchange is what shows it's of the household; its id comes from what the network announces
            noteSeen(peerAt(s.getInetAddress()));
        } catch (IOException | java.security.GeneralSecurityException e) {
            Log.i(TAG, "A TV tried to sync and couldn't: " + e.getClass().getSimpleName());
        }
    }

    private static void finish(HouseholdStore store, HouseholdSync.Result result, String how) {
        store.log().purge(System.currentTimeMillis());
        store.save();
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
        boolean ok = store(context).create();
        if (ok) start(context);
        return ok;
    }

    /** The household key to hand to a TV that joins, making a household here first if there is none; null on failure. */
    static byte[] keyToJoin(Context context) {
        HouseholdStore store = store(context);
        if (!store.joined() && !create(context)) return null;
        return store.exportKey();
    }

    /** Joins the household whose key {@code secrets} carries (a copy from another TV). False if it has none. */
    static boolean joinFromSecrets(Context context, String secrets) {
        try {
            String encoded = new org.json.JSONObject(secrets).optString("household", "");
            if (encoded.isEmpty()) return false;
            byte[] key = java.util.Base64.getDecoder().decode(encoded);
            boolean ok = store(context).join(key);
            Arrays.fill(key, (byte) 0);
            if (ok) {
                // The TVs of a household this one was in before aren't members of this one
                prefs(context).edit().remove(SEEN_PREF).apply();
                store(context).setEnabled(true);
                start(context);
            }
            return ok;
        } catch (Exception e) {
            return false;
        }
    }

    /** Turns syncing on or off (the one switch). */
    static void setEnabled(Context context, boolean on) {
        store(context).setEnabled(on);
        start(context);
    }

    /**
     * Leaves the household: first tells the TVs on now that this one is gone (it deletes its own entry and syncs, for at
     * most {@link #LEAVE_SYNC_MS}; a TV that's off hears it from them), then forgets the key and the entries here. Blocks:
     * not on the main thread.
     */
    static void leave(Context context) {
        if (!mayBeInHousehold(context)) return;
        sContext = context.getApplicationContext();
        try {
            EXEC.submit(() -> {
                if (!active(sContext)) return;
                HouseholdStore store = store(sContext);
                store.log().delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, store.tvId(), System.currentTimeMillis());
                store.save();
                syncAll("leave");
            }).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            Log.i(TAG, "Left without telling every TV: " + e.getClass().getSimpleName());
        }
        Runnable forget = () -> {
            stop();
            store(sContext).leave();
            prefs(sContext).edit().remove(SEEN_PREF).apply();
        };
        try {
            EXEC.submit(forget).get(LEAVE_SYNC_MS, TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            // The household thread is stuck: forget here, so leaving can't fail
            forget.run();
        }
    }

    /** Syncs now, for the screen's button. */
    static void syncNowAsync(Context context) {
        sContext = context.getApplicationContext();
        EXEC.execute(() -> syncAll("button"));
    }
}
