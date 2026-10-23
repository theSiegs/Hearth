package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONObject;

import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * What this TV keeps of its household (docs/household-sync.md): this TV's id, the household key (sealed under a
 * Keystore key, and decrypted only to build a {@link HouseholdSeal}), the one on/off switch for syncing, and the
 * {@link HouseholdLog} of entries, saved encrypted because a PIN entry holds the PIN. A household key or log that no
 * longer opens (the Keystore key is gone) makes this TV "not in a household" and says so ({@link #lost}); nothing
 * is ever made up in its place. Not thread safe.
 */
final class HouseholdStore {
    /** Where the pieces are kept: the app's preferences, or a map in tests. */
    interface Backing {
        String get(String key);

        void put(String key, String value);

        void remove(String key);
    }

    static final String KEY_ALIAS = "hearth_household_v1";
    static final String LOG_ALIAS = "hearth_household_log_v1";
    private static final String TV_ID = "tv_id";
    private static final String KEY_SEALED = "key_sealed";
    private static final String LOG_SEALED = "log_sealed";
    private static final String ENABLED = "enabled";

    private final Backing backing;
    private final SecretBox.Keys keys;
    private final String tvId;
    private HouseholdSeal seal;
    private HouseholdLog log;
    private boolean lost;

    private HouseholdStore(Backing backing, SecretBox.Keys keys, String tvId) {
        this.backing = backing;
        this.keys = keys;
        this.tvId = tvId;
    }

    /** Opens the store, loading the household key and the log if this TV is in a household. */
    static HouseholdStore open(Backing backing, SecretBox.Keys keys) {
        String id = backing.get(TV_ID);
        if (id == null || id.isEmpty()) {
            byte[] random = new byte[8];
            new SecureRandom().nextBytes(random);
            StringBuilder hex = new StringBuilder("tv-");
            for (byte b : random) hex.append(String.format("%02x", b));
            id = hex.toString();
            backing.put(TV_ID, id);
        }
        HouseholdStore store = new HouseholdStore(backing, keys, id);
        store.load();
        return store;
    }

    private void load() {
        String sealedKey = backing.get(KEY_SEALED);
        if (sealedKey == null) return;
        byte[] key = SecretBox.open(keys, KEY_ALIAS, sealedKey);
        if (key == null || key.length != HouseholdSeal.HOUSEHOLD_KEY_BYTES) {
            lost = true;
            return;
        }
        try {
            seal = new HouseholdSeal(key);
        } catch (GeneralSecurityException e) {
            lost = true;
            return;
        }
        log = new HouseholdLog(tvId);
        String sealedLog = backing.get(LOG_SEALED);
        if (sealedLog == null) return;
        String json = SecretBox.openText(keys, LOG_ALIAS, sealedLog);
        if (json == null || !readLog(json)) {
            // The entries can't be read: start empty (they come back from the other TVs), but keep the household
            log = new HouseholdLog(tvId);
        }
    }

    private boolean readLog(String json) {
        try {
            JSONObject root = new JSONObject(json);
            List<HouseholdEntry> entries = new ArrayList<>();
            JSONArray array = root.getJSONArray("entries");
            for (int i = 0; i < array.length(); i++) {
                HouseholdEntry entry = HouseholdEntry.fromJson(array.getString(i));
                if (entry != null) entries.add(entry);
            }
            Map<String, Long> vector = new HashMap<>();
            JSONObject seen = root.getJSONObject("vector");
            for (Iterator<String> it = seen.keys(); it.hasNext();) {
                String tv = it.next();
                vector.put(tv, seen.getLong(tv));
            }
            log.restore(entries, vector);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    String tvId() {
        return tvId;
    }

    boolean joined() {
        return seal != null;
    }

    /** The household key couldn't be opened: this TV was in a household and has to join again. */
    boolean lost() {
        return lost;
    }

    /** The household's id (the same on every TV in it); null when not in one. */
    String householdId() {
        return seal == null ? null : seal.id();
    }

    /** The one switch (on by default): whether this TV sends and takes entries. Only matters in a household. */
    boolean enabled() {
        return !"0".equals(backing.get(ENABLED));
    }

    void setEnabled(boolean on) {
        backing.put(ENABLED, on ? "1" : "0");
    }

    HouseholdSeal seal() {
        return seal;
    }

    HouseholdLog log() {
        return log;
    }

    /** Starts a household on this TV with a new key; false when it is already in one. */
    boolean create() {
        if (joined()) return false;
        return adopt(HouseholdSeal.newKey());
    }

    /**
     * Takes the key of a household this TV joined (the TV that has it sent it over the encrypted join). Replaces any
     * household and log held; the first sync brings the entries over.
     */
    boolean join(byte[] key) {
        return adopt(key);
    }

    private boolean adopt(byte[] key) {
        if (key == null || key.length != HouseholdSeal.HOUSEHOLD_KEY_BYTES) return false;
        String sealed = SecretBox.seal(keys, KEY_ALIAS, key);
        if (sealed == null) return false;
        try {
            seal = new HouseholdSeal(key);
        } catch (GeneralSecurityException e) {
            return false;
        }
        backing.put(KEY_SEALED, sealed);
        backing.remove(LOG_SEALED);
        log = new HouseholdLog(tvId);
        lost = false;
        return true;
    }

    /** The household key, to hand to a TV that joins; null when not in a household. The caller wipes it. */
    byte[] exportKey() {
        String sealed = backing.get(KEY_SEALED);
        return sealed == null ? null : SecretBox.open(keys, KEY_ALIAS, sealed);
    }

    /** Leaves the household: the key and the entries are forgotten (the values already applied stay as settings). */
    void leave() {
        backing.remove(KEY_SEALED);
        backing.remove(LOG_SEALED);
        seal = null;
        log = null;
        lost = false;
    }

    /** Saves the log, encrypted; false when it couldn't be sealed (the next change tries again). */
    boolean save() {
        if (log == null) return false;
        try {
            JSONArray entries = new JSONArray();
            for (HouseholdEntry entry : log.all()) entries.put(entry.toJson());
            JSONObject seen = new JSONObject();
            for (Map.Entry<String, Long> e : log.vector().entrySet()) seen.put(e.getKey(), e.getValue());
            String sealed = SecretBox.sealText(keys, LOG_ALIAS,
                    new JSONObject().put("entries", entries).put("vector", seen).toString());
            if (sealed == null) return false;
            backing.put(LOG_SEALED, sealed);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
