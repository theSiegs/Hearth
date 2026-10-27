package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONObject;

import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * What this TV keeps of its household (docs/household-sync.md): its TV key (HouseholdIdentity), the household's id and
 * person salt, the one on/off switch, the {@link HouseholdLog} of entries (the member list among them), and the
 * invitations it has handed out. Secrets are sealed under Keystore keys (SecretBox); the log is saved encrypted because a
 * PIN entry holds the PIN. A household whose TV key or salt no longer opens (the Keystore was cleared) makes this TV
 * "not in a household" and says so ({@link #lost}); nothing is ever made up in its place.
 *
 * <p>A TV that still holds a version 1 household key converts on opening: it makes its TV key, keeps the household's id
 * and person ids, and keeps the old key for {@link #V1_GRACE_MS} only to admit the household's other TVs as they
 * convert. Not thread safe.
 */
final class HouseholdStore {
    /** Where the pieces are kept: the app's preferences, or a map in tests. */
    interface Backing {
        String get(String key);

        void put(String key, String value);

        void remove(String key);
    }

    /** What a TV that joins is handed once its join request is allowed: enough to find and prove itself. */
    static final class Invitation {
        final String householdId;
        final byte[] personSalt;
        final String byTv;
        final byte[] byKey;
        final String byName;
        final byte[] secret;
        /** The inviting TV signs its member, removal and Parent PIN entries (false from a TV older than signing). */
        final boolean signing;

        Invitation(String householdId, byte[] personSalt, String byTv, byte[] byKey, String byName, byte[] secret) {
            this(householdId, personSalt, byTv, byKey, byName, secret, true);
        }

        Invitation(String householdId, byte[] personSalt, String byTv, byte[] byKey, String byName, byte[] secret,
                boolean signing) {
            this.householdId = householdId;
            this.personSalt = personSalt;
            this.byTv = byTv;
            this.byKey = byKey;
            this.byName = byName;
            this.secret = secret;
            this.signing = signing;
        }

        String toJson() {
            try {
                Base64.Encoder b64 = Base64.getEncoder();
                return new JSONObject().put("id", householdId).put("salt", b64.encodeToString(personSalt))
                        .put("tv", byTv).put("key", b64.encodeToString(byKey)).put("name", byName == null ? "" : byName)
                        .put("secret", b64.encodeToString(secret)).put("signs", signing).toString();
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        /** The invitation in {@code json}, or null when it isn't one. */
        static Invitation fromJson(String json) {
            try {
                JSONObject o = new JSONObject(json);
                Base64.Decoder b64 = Base64.getDecoder();
                Invitation inv = new Invitation(o.getString("id"), b64.decode(o.getString("salt")), o.getString("tv"),
                        b64.decode(o.getString("key")), o.optString("name", ""), b64.decode(o.getString("secret")),
                        o.optBoolean("signs", false));
                if (inv.householdId.isEmpty() || inv.personSalt.length != HouseholdSeal.SALT_BYTES
                        || inv.secret.length != SECRET_BYTES || !HouseholdIdentity.tvIdOf(inv.byKey).equals(inv.byTv)) {
                    return null;
                }
                return inv;
            } catch (Exception e) {
                return null;
            }
        }
    }

    static final String SALT_ALIAS = "hearth_household_salt_v2";
    static final String INVITES_ALIAS = "hearth_household_invites_v2";
    static final String KEY_ALIAS = "hearth_household_v1";
    static final String LOG_ALIAS = "hearth_household_log_v1";
    /** How long an invitation can be used. */
    static final long INVITE_MS = 60L * 60 * 1000;
    /** How long a converted TV keeps the version 1 key to admit the household's other TVs. */
    static final long V1_GRACE_MS = 90L * 24 * 60 * 60 * 1000;
    /** How long a TV that left with no other TV on keeps trying to tell one. */
    static final long LEAVING_MS = 90L * 24 * 60 * 60 * 1000;
    static final int SECRET_BYTES = 32;

    private static final String TV_ID = "tv_id";
    private static final String HOUSEHOLD_ID = "household_id";
    private static final String SALT_SEALED = "salt_sealed";
    private static final String V1_KEY_SEALED = "key_sealed";
    private static final String V1_UNTIL = "v1_until";
    private static final String LOG_SEALED = "log_sealed";
    private static final String INVITES_SEALED = "invites_sealed";
    private static final String JOIN_PROOF_SEALED = "join_proof_sealed";
    private static final String JOIN_PROOF_FOR = "join_proof_for";
    private static final String LEAVING_SINCE = "leaving_since";
    private static final String REMOVED = "removed";
    private static final String ENABLED = "enabled";
    private static final SecureRandom RANDOM = new SecureRandom();

    private final Backing backing;
    private final SecretBox.Keys keys;
    private final HouseholdIdentity.Keys identities;
    private HouseholdIdentity.Signer identity;
    private String tvId;
    private String householdId;
    private HouseholdSeal seal;
    private HouseholdLog log;
    private boolean lost;

    private HouseholdStore(Backing backing, SecretBox.Keys keys, HouseholdIdentity.Keys identities) {
        this.backing = backing;
        this.keys = keys;
        this.identities = identities;
    }

    /** Opens the store, loading (or converting) the household if this TV is in one. */
    static HouseholdStore open(Backing backing, SecretBox.Keys keys, HouseholdIdentity.Keys identities) {
        HouseholdStore store = new HouseholdStore(backing, keys, identities);
        store.load();
        return store;
    }

    private void load() {
        if (backing.get(HOUSEHOLD_ID) == null && backing.get(V1_KEY_SEALED) != null) {
            convertFromV1();
            if (lost) return;
        }
        householdId = backing.get(HOUSEHOLD_ID);
        if (householdId == null) return;
        identity = identities.load();
        byte[] salt = SecretBox.open(keys, SALT_ALIAS, backing.get(SALT_SEALED));
        if (identity == null || salt == null || salt.length != HouseholdSeal.SALT_BYTES) {
            // Kept, so the TV keeps saying it lost its household until it starts or joins one
            identity = null;
            lost = true;
            return;
        }
        tvId = HouseholdIdentity.tvIdOf(identity.publicKey());
        seal = new HouseholdSeal(salt);
        Arrays.fill(salt, (byte) 0);
        log = newLog();
        String sealedLog = backing.get(LOG_SEALED);
        if (sealedLog == null) return;
        String json = SecretBox.openText(keys, LOG_ALIAS, sealedLog);
        if (json == null || !readLog(json)) {
            // The entries can't be read: start empty (they come back from the other TVs), but keep the household
            log = newLog();
        }
    }

    /** An empty log for this TV, signing what it writes of the kinds that carry a signature. */
    private HouseholdLog newLog() {
        HouseholdLog made = new HouseholdLog(tvId);
        HouseholdIdentity.Signer signer = identity;
        made.setSigner(entry -> {
            try {
                return Base64.getEncoder().encodeToString(signer.sign(entry.signedBytes()));
            } catch (GeneralSecurityException | RuntimeException e) {
                return null;
            }
        });
        return made;
    }

    /** A version 1 household becomes this TV's: a TV key, the same id and person ids, the old key kept a while. */
    private void convertFromV1() {
        byte[] key = SecretBox.open(keys, KEY_ALIAS, backing.get(V1_KEY_SEALED));
        try {
            if (key == null || key.length != HouseholdSeal.V1_KEY_BYTES) {
                // Kept, so the TV keeps saying it lost its household until it joins one again
                lost = true;
                return;
            }
            HouseholdIdentity.Signer made = identities.create();
            byte[] salt = HouseholdSeal.v1PersonSalt(key);
            String sealedSalt = SecretBox.seal(keys, SALT_ALIAS, salt);
            Arrays.fill(salt, (byte) 0);
            if (made == null || sealedSalt == null) {
                // Try again next time; the version 1 key is kept
                lost = true;
                return;
            }
            backing.put(SALT_SEALED, sealedSalt);
            backing.put(HOUSEHOLD_ID, HouseholdSeal.v1Id(key));
            backing.put(TV_ID, HouseholdIdentity.tvIdOf(made.publicKey()));
        } catch (GeneralSecurityException e) {
            lost = true;
        } finally {
            if (key != null) Arrays.fill(key, (byte) 0);
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

    /** This TV's id in its household; null when it is in none. */
    String tvId() {
        return tvId;
    }

    /** This TV's public key; null when it is in no household. */
    byte[] publicKey() {
        return identity == null ? null : identity.publicKey();
    }

    HouseholdIdentity.Signer identity() {
        return identity;
    }

    boolean joined() {
        return identity != null && seal != null && !leaving();
    }

    /** In a household, or still telling one that this TV left: whether it takes part in exchanges. */
    boolean syncs() {
        return identity != null && seal != null;
    }

    /** The household couldn't be opened: this TV was in one and has to join again. */
    boolean lost() {
        return lost;
    }

    /** Another TV removed this one from the household (it was told so); cleared by starting or joining one. */
    boolean removed() {
        return "1".equals(backing.get(REMOVED));
    }

    /** The household's id (the same on every TV in it); null when not in one. */
    String householdId() {
        return syncs() ? householdId : null;
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

    // ---- Starting and joining ----

    /** Starts a household on this TV: a new TV key and salt, this TV the only member. False when already in one. */
    boolean create(String name, long nowMs) {
        if (joined()) return false;
        return begin(null, HouseholdSeal.newSalt(), name, nowMs);
    }

    /**
     * Joins the household an invitation is for: a new TV key, the household's id and salt, and the inviting TV listed
     * so this TV accepts it. The inviting TV lists this one when they first sync and this TV proves it holds the
     * invitation's secret. Replaces any household and entries held.
     */
    boolean join(Invitation inv, String name, long nowMs) {
        if (inv == null) return false;
        String sealedProof = SecretBox.seal(keys, INVITES_ALIAS, inv.secret);
        if (sealedProof == null) return false;
        if (!begin(inv.householdId, inv.personSalt.clone(), name, nowMs)) return false;
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, inv.byTv,
                HouseholdMembers.value(inv.byName, inv.byKey, inv.byTv, inv.signing), nowMs);
        backing.put(JOIN_PROOF_SEALED, sealedProof);
        backing.put(JOIN_PROOF_FOR, inv.byTv);
        save();
        return true;
    }

    /** Starts this TV in a household: a new TV key, and the household {@code id} (null: a new one, named after it). */
    private boolean begin(String id, byte[] salt, String name, long nowMs) {
        String sealedSalt = SecretBox.seal(keys, SALT_ALIAS, salt);
        if (sealedSalt == null) return false;
        forgetState();
        HouseholdIdentity.Signer made = identities.create();
        if (made == null) return false;
        if (id == null) id = HouseholdSeal.newId(HouseholdIdentity.tvIdOf(made.publicKey()));
        identity = made;
        tvId = HouseholdIdentity.tvIdOf(made.publicKey());
        householdId = id;
        seal = new HouseholdSeal(salt);
        Arrays.fill(salt, (byte) 0);
        log = newLog();
        backing.put(SALT_SEALED, sealedSalt);
        backing.put(HOUSEHOLD_ID, id);
        backing.put(TV_ID, tvId);
        backing.remove(REMOVED);
        lost = false;
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, tvId, HouseholdMembers.value(name, made.publicKey(), tvId,
                true), nowMs);
        save();
        return true;
    }

    // ---- Admitting other TVs ----

    /** A new invitation for one TV to join, good for {@link #INVITE_MS}; null when not in a household. */
    Invitation invite(String name, long nowMs) {
        if (!joined()) return null;
        byte[] secret = new byte[SECRET_BYTES];
        RANDOM.nextBytes(secret);
        JSONArray invites = invites(nowMs);
        try {
            invites.put(new JSONObject().put("secret", Base64.getEncoder().encodeToString(secret))
                    .put("until", nowMs + INVITE_MS));
        } catch (Exception e) {
            return null;
        }
        if (!saveInvites(invites)) return null;
        byte[] salt = saltBytes();
        if (salt == null) return null;
        return new Invitation(householdId, salt, tvId, identity.publicKey(), name, secret);
    }

    private byte[] saltBytes() {
        return SecretBox.open(keys, SALT_ALIAS, backing.get(SALT_SEALED));
    }

    /** The invitations not yet used or expired. */
    private JSONArray invites(long nowMs) {
        JSONArray out = new JSONArray();
        String json = SecretBox.openText(keys, INVITES_ALIAS, backing.get(INVITES_SEALED));
        if (json == null) return out;
        try {
            JSONArray all = new JSONArray(json);
            for (int i = 0; i < all.length(); i++) {
                JSONObject inv = all.getJSONObject(i);
                if (inv.getLong("until") > nowMs) out.put(inv);
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    private boolean saveInvites(JSONArray invites) {
        if (invites.length() == 0) {
            backing.remove(INVITES_SEALED);
            return true;
        }
        String sealed = SecretBox.sealText(keys, INVITES_ALIAS, invites.toString());
        if (sealed == null) return false;
        backing.put(INVITES_SEALED, sealed);
        return true;
    }

    /**
     * Whether {@code mac} proves an unused invitation (HMAC of {@code data} under its secret). A matching one is used up.
     */
    boolean useInvite(byte[] data, byte[] mac, long nowMs) {
        if (mac == null) return false;
        JSONArray invites = invites(nowMs);
        for (int i = 0; i < invites.length(); i++) {
            try {
                byte[] secret = Base64.getDecoder().decode(invites.getJSONObject(i).getString("secret"));
                if (MessageDigest.isEqual(ShareCrypto.hkdfExtract(secret, data), mac)) {
                    invites.remove(i);
                    saveInvites(invites);
                    return true;
                }
            } catch (Exception ignored) {
            }
        }
        return false;
    }

    /** The invitation's secret this TV proves to {@code peer} (the TV that invited it), or null. */
    byte[] joinProofFor(String peer) {
        if (peer == null || !peer.equals(backing.get(JOIN_PROOF_FOR))) return null;
        return SecretBox.open(keys, INVITES_ALIAS, backing.get(JOIN_PROOF_SEALED));
    }

    /** The inviting TV has listed this one: the invitation's secret is no longer needed. */
    void joinProofUsed() {
        backing.remove(JOIN_PROOF_SEALED);
        backing.remove(JOIN_PROOF_FOR);
    }

    /** The key two TVs of a version 1 household prove to each other while converting; null when past or none. */
    byte[] v1AdmitKey(long nowMs) {
        String sealed = backing.get(V1_KEY_SEALED);
        if (sealed == null) return null;
        String until = backing.get(V1_UNTIL);
        if (until == null) {
            backing.put(V1_UNTIL, Long.toString(nowMs + V1_GRACE_MS));
        } else if (nowMs > Long.parseLong(until)) {
            backing.remove(V1_KEY_SEALED);
            backing.remove(V1_UNTIL);
            return null;
        }
        byte[] key = SecretBox.open(keys, KEY_ALIAS, sealed);
        if (key == null) return null;
        try {
            return HouseholdSeal.v1AdmitKey(key);
        } catch (GeneralSecurityException e) {
            return null;
        } finally {
            Arrays.fill(key, (byte) 0);
        }
    }

    /** Writes this TV's own member entry when it's missing, renamed or a day old; true when it wrote. */
    boolean publishSelf(String name, long nowMs) {
        if (!joined()) return false;
        byte[] key = identity.publicKey();
        if (!HouseholdMembers.selfNeedsWrite(log, tvId, name, key, nowMs)) return false;
        HouseholdEntry had = log.get(HouseholdMembers.KIND, HouseholdBridge.SHARED, tvId);
        String by = had == null ? tvId : HouseholdMembers.byOf(had.value, tvId);
        return log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, tvId, HouseholdMembers.value(name, key, by, true), nowMs)
                != null;
    }

    /**
     * Lists a TV that proved itself: its key, its name, this TV as the one that added it, and whether it said it signs
     * its entries ({@code signing}).
     */
    void admit(String peer, byte[] publicKey, String name, boolean signing, long nowMs) {
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, peer,
                HouseholdMembers.value(name, publicKey, tvId, signing), nowMs);
    }

    // ---- Leaving and removal ----

    /** Removes another TV from the household; false for this TV (that's {@link #beginLeaving}) or when not in one. */
    boolean remove(String peer, long nowMs) {
        if (!joined() || peer == null || peer.equals(tvId)) return false;
        if (log.isRemoved(HouseholdMembers.KIND, HouseholdBridge.SHARED, peer)) return true;
        return log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, peer, nowMs) != null;
    }

    /**
     * This TV leaves: it removes itself from the list and stays only to hand that to another TV of the household. The
     * caller forgets the household ({@link #leave}) once an exchange has carried it, or after {@link #LEAVING_MS}.
     */
    void beginLeaving(long nowMs) {
        if (!joined()) return;
        log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, tvId, nowMs);
        backing.put(LEAVING_SINCE, Long.toString(nowMs));
        save();
    }

    boolean leaving() {
        return backing.get(LEAVING_SINCE) != null;
    }

    /** Whether a TV that is leaving has waited too long to tell another. */
    boolean leavingExpired(long nowMs) {
        String since = backing.get(LEAVING_SINCE);
        return since != null && nowMs - Long.parseLong(since) > LEAVING_MS;
    }

    /** Forgets the household: the TV key, the salt and the entries (the values already applied stay as settings). */
    void leave() {
        forgetState();
        lost = false;
    }

    /** Another TV said this one was removed: forget the household and say so until this TV starts or joins one. */
    void markRemoved() {
        forgetState();
        backing.put(REMOVED, "1");
        lost = false;
    }

    private void forgetState() {
        for (String key : new String[] {TV_ID, HOUSEHOLD_ID, SALT_SEALED, V1_KEY_SEALED, V1_UNTIL, LOG_SEALED,
                INVITES_SEALED, JOIN_PROOF_SEALED, JOIN_PROOF_FOR, LEAVING_SINCE}) {
            backing.remove(key);
        }
        identities.delete();
        identity = null;
        tvId = null;
        householdId = null;
        seal = null;
        log = null;
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
