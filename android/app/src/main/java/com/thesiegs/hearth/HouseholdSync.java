package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * One exchange of entries between two TVs of a household (docs/household-sync.md, "Moving entries"), over any pair of
 * streams. Each side sends its TV id, a fresh ECDH key and a nonce in the clear; every frame after that is sealed
 * (ChaCha20-Poly1305) under keys derived from the shared secret and the whole opening (the transcript), with a counter
 * per direction, so it can't be read, altered or played back. Then each side signs the transcript with its TV key, and
 * the other checks that key against its member list: a listed TV goes on, a removed one is told so, an unknown one is
 * refused unless it proves an invitation or the version 1 household key, which lists it. Then each says what it has seen
 * from each TV (its version vector), sends what the other lacks, and merges what it got. Last, each says which wallpaper
 * pictures its entries name that it doesn't have, and the other sends those it has (HouseholdPictures). The initiator
 * speaks first at every step, so neither side waits on the other's write.
 */
final class HouseholdSync {
    private static final byte[] MAGIC = {'H', 'H', 'S', '2'};
    private static final int NONCE_BYTES = 16;
    private static final int POINT_BYTES = 65;
    private static final int MAX_FRAME_BYTES = 8 * 1024 * 1024;
    static final int MAX_ENTRIES = 20_000;
    private static final byte[] LABEL = ShareCrypto.bytes("hearth-household-sync-v2");
    private static final Pattern TV_ID = Pattern.compile("tv-[0-9a-f]{16}");
    private static final String MEMBER = "member";
    private static final String REMOVED = "removed";
    private static final SecureRandom RANDOM = new SecureRandom();
    /** Pictures asked for or sent in one exchange: three slots for a household's worth of profiles. */
    static final int MAX_PICTURES = 48;

    /** What an exchange did, for the screen and the log. */
    static final class Result {
        final String peer;
        /** The name the other TV gave. */
        final String peerName;
        final int sent;
        final int received;
        /** The entries that changed this TV (they beat what it had), for the app to apply. */
        final List<HouseholdEntry> applied;
        /** The other TV is removed from this TV's list; it was told, and nothing moved. */
        final boolean peerRemoved;
        /** The other TV has this one removed; nothing moved. The caller forgets the household. */
        final boolean removedHere;
        /** Wallpaper pictures that came from the other TV. */
        final int pictures;

        Result(String peer, String peerName, int sent, int received, List<HouseholdEntry> applied, boolean peerRemoved,
                boolean removedHere, int pictures) {
            this.peer = peer;
            this.peerName = peerName;
            this.sent = sent;
            this.received = received;
            this.applied = applied;
            this.peerRemoved = peerRemoved;
            this.removedHere = removedHere;
            this.pictures = pictures;
        }
    }

    /** The other end isn't in this household, broke the protocol, or sent something that doesn't open. */
    static final class SyncException extends IOException {
        SyncException(String message) {
            super(message);
        }
    }

    private final DataInputStream in;
    private final DataOutputStream out;
    private final boolean initiator;
    private final HouseholdStore store;
    /** Where wallpaper pictures are kept; null: this side has none and asks for none. */
    private final HouseholdPictures pictures;
    private final String name;
    private final long now;
    private byte[] transcript;
    private byte[] sendKey;
    private byte[] receiveKey;
    private byte[] aad;
    private long sendCounter;
    private long receiveCounter;
    private String peer;
    private String peerName;

    private HouseholdSync(InputStream in, OutputStream out, boolean initiator, HouseholdStore store,
            HouseholdPictures pictures, String name, long now) {
        this.in = new DataInputStream(in);
        this.out = new DataOutputStream(out);
        this.initiator = initiator;
        this.store = store;
        this.pictures = pictures;
        this.name = name;
        this.now = now;
    }

    /**
     * Runs the exchange as the TV that connected ({@code initiator}) or the one that accepted; {@code name} is this TV's
     * name, for a TV that lists it. The log is merged but not saved; the caller saves it ({@link HouseholdStore#save})
     * and applies {@link Result#applied}.
     */
    static Result run(InputStream in, OutputStream out, boolean initiator, HouseholdStore store, String name, long now)
            throws IOException, GeneralSecurityException {
        return run(in, out, initiator, store, null, name, now);
    }

    /** As {@link #run(InputStream, OutputStream, boolean, HouseholdStore, String, long)}, trading wallpaper pictures too. */
    static Result run(InputStream in, OutputStream out, boolean initiator, HouseholdStore store,
            HouseholdPictures pictures, String name, long now) throws IOException, GeneralSecurityException {
        if (!store.syncs() || store.log() == null) throw new SyncException("Not in a household");
        try {
            return new HouseholdSync(in, out, initiator, store, pictures, name, now).exchange();
        } catch (JSONException | IllegalArgumentException e) {
            throw new SyncException("Not a household exchange");
        }
    }

    private Result exchange() throws IOException, GeneralSecurityException, JSONException {
        open();

        // 1. who each side is, and where the other stands
        JSONObject mine = auth();
        boolean peerRemoved;
        if (initiator) {
            writeJson(mine);
            JSONObject theirs = readJson();
            peerRemoved = check(theirs) == HouseholdMembers.Standing.REMOVED;
            if (REMOVED.equals(theirs.optString("verdict"))) return stopped(false, true);
            writeJson(new JSONObject().put("verdict", peerRemoved ? REMOVED : MEMBER));
            if (peerRemoved) return stopped(true, false);
        } else {
            peerRemoved = check(readJson()) == HouseholdMembers.Standing.REMOVED;
            writeJson(mine.put("verdict", peerRemoved ? REMOVED : MEMBER));
            if (peerRemoved) return stopped(true, false);
            if (REMOVED.equals(readJson().optString("verdict"))) return stopped(false, true);
        }

        // 2. what each side has seen
        JSONObject vector = new JSONObject().put("vector", vectorJson(store.log().vector()));
        JSONObject peerVector;
        if (initiator) {
            writeJson(vector);
            peerVector = readJson();
        } else {
            peerVector = readJson();
            writeJson(vector);
        }
        Map<String, Long> theirVector = readVector(peerVector.getJSONObject("vector"));

        // 3. what each side lacks
        List<HouseholdEntry> toSend = store.log().missingFrom(theirVector);
        if (toSend.size() > MAX_ENTRIES) toSend = toSend.subList(0, MAX_ENTRIES);
        String payload = entriesJson(toSend);
        String incoming;
        if (initiator) {
            writeFrame(payload.getBytes(StandardCharsets.UTF_8));
            incoming = readText();
        } else {
            incoming = readText();
            writeFrame(payload.getBytes(StandardCharsets.UTF_8));
        }

        // 4. merge
        JSONArray array = new JSONArray(incoming);
        if (array.length() > MAX_ENTRIES) throw new SyncException("Too many entries");
        List<HouseholdEntry> applied = new ArrayList<>();
        int received = 0;
        for (int i = 0; i < array.length(); i++) {
            HouseholdEntry entry = HouseholdEntry.fromJson(array.getString(i));
            if (entry == null) continue;
            received++;
            if (store.log().merge(entry, now)) applied.add(entry);
        }
        // 5. the pictures the entries name that a side lacks
        int took = tradePictures();

        // The TV that invited this one has listed it: the invitation is spent
        if (store.joinProofFor(peer) != null) store.joinProofUsed();
        return new Result(peer, peerName, toSend.size(), received, applied, false, false, took);
    }

    private Result stopped(boolean peerRemoved, boolean removedHere) {
        return new Result(peer, peerName, 0, 0, new ArrayList<>(), peerRemoved, removedHere, 0);
    }

    /** Asks for the pictures this side's entries name and it lacks, sends those the other asks for; how many came. */
    private int tradePictures() throws IOException, GeneralSecurityException, JSONException {
        JSONArray wanted = new JSONArray();
        if (pictures != null) {
            for (String hash : HouseholdBridge.pictures(store.log())) {
                if (wanted.length() >= MAX_PICTURES) break;
                if (!pictures.has(hash)) wanted.put(hash);
            }
        }
        JSONArray asked;
        if (initiator) {
            writeFrame(wanted.toString().getBytes(StandardCharsets.UTF_8));
            asked = new JSONArray(readText());
        } else {
            asked = new JSONArray(readText());
            writeFrame(wanted.toString().getBytes(StandardCharsets.UTF_8));
        }
        if (asked.length() > MAX_PICTURES) throw new SyncException("Too many pictures asked for");
        if (initiator) {
            sendPictures(asked);
            return takePictures(wanted);
        }
        int took = takePictures(wanted);
        sendPictures(asked);
        return took;
    }

    /** Says which of the asked-for pictures follow, then sends each as a frame of its own. */
    private void sendPictures(JSONArray asked) throws IOException, GeneralSecurityException, JSONException {
        List<byte[]> bytes = new ArrayList<>();
        JSONArray names = new JSONArray();
        for (int i = 0; i < asked.length() && pictures != null; i++) {
            String hash = asked.optString(i, "");
            byte[] picture = HouseholdPictures.validHash(hash) ? pictures.read(hash) : null;
            if (picture == null) continue;
            names.put(hash);
            bytes.add(picture);
        }
        writeFrame(names.toString().getBytes(StandardCharsets.UTF_8));
        for (byte[] picture : bytes) writeFrame(picture);
    }

    /** Takes the pictures the other side sends; one that wasn't asked for, isn't a picture or isn't its hash fails. */
    private int takePictures(JSONArray wanted) throws IOException, GeneralSecurityException, JSONException {
        JSONArray names = new JSONArray(readText());
        if (names.length() > wanted.length()) throw new SyncException("More pictures than asked for");
        java.util.Set<String> asked = new java.util.HashSet<>();
        for (int i = 0; i < wanted.length(); i++) asked.add(wanted.getString(i));
        int took = 0;
        for (int i = 0; i < names.length(); i++) {
            String hash = names.getString(i);
            byte[] picture = readFrame();
            if (!asked.remove(hash) || pictures == null || pictures.write(picture, hash) == null) {
                throw new SyncException("A picture that wasn't asked for, or isn't the one named");
            }
            took++;
        }
        return took;
    }

    // ---- Opening: the clear hellos, the shared secret, the session keys ----

    private void open() throws IOException, GeneralSecurityException {
        KeyPair ephemeral = ShareCrypto.newKeyPair();
        byte[] point = ShareCrypto.encodePoint(ephemeral.getPublic());
        byte[] nonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(nonce);
        String peerId;
        byte[] peerPoint = new byte[POINT_BYTES];
        byte[] peerNonce = new byte[NONCE_BYTES];
        if (initiator) {
            sendHello(point, nonce);
            peerId = readHello(peerPoint, peerNonce);
        } else {
            peerId = readHello(peerPoint, peerNonce);
            sendHello(point, nonce);
        }
        if (peerId.equals(store.tvId())) throw new SyncException("Bad peer");
        peer = peerId;
        byte[] shared = ShareCrypto.agree(ephemeral, ShareCrypto.decodePoint(peerPoint, ShareCrypto.params(ephemeral)));
        try {
            byte[] household = ShareCrypto.bytes(store.householdId());
            String iId = initiator ? store.tvId() : peerId;
            String rId = initiator ? peerId : store.tvId();
            transcript = ShareCrypto.sha256(LABEL, household, ShareCrypto.bytes(iId), initiator ? point : peerPoint,
                    initiator ? nonce : peerNonce, ShareCrypto.bytes(rId), initiator ? peerPoint : point,
                    initiator ? peerNonce : nonce);
            byte[] prk = ShareCrypto.hkdfExtract(transcript, shared);
            byte[] i2r = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("i2r"), ShareCrypto.KEY_BYTES);
            byte[] r2i = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("r2i"), ShareCrypto.KEY_BYTES);
            sendKey = initiator ? i2r : r2i;
            receiveKey = initiator ? r2i : i2r;
            aad = household;
        } finally {
            java.util.Arrays.fill(shared, (byte) 0);
        }
    }

    private void sendHello(byte[] point, byte[] nonce) throws IOException {
        out.write(MAGIC);
        out.writeUTF(store.tvId());
        out.write(point);
        out.write(nonce);
        out.flush();
    }

    private String readHello(byte[] point, byte[] nonce) throws IOException {
        byte[] magic = new byte[MAGIC.length];
        in.readFully(magic);
        if (!MessageDigest.isEqual(magic, MAGIC)) throw new SyncException("Not a household exchange");
        String id = in.readUTF();
        if (!TV_ID.matcher(id).matches()) throw new SyncException("Not a household exchange");
        in.readFully(point);
        in.readFully(nonce);
        return id;
    }

    // ---- Proving who each side is ----

    private byte[] signed(boolean ofInitiator, String purpose) {
        byte[] role = ShareCrypto.bytes((ofInitiator ? "i" : "r") + purpose);
        byte[] out = java.util.Arrays.copyOf(transcript, transcript.length + role.length);
        System.arraycopy(role, 0, out, transcript.length, role.length);
        return out;
    }

    /** This side's proof: its key, its signature over the transcript, its name, and what admits it if it isn't listed. */
    private JSONObject auth() throws GeneralSecurityException, JSONException {
        Base64.Encoder b64 = Base64.getEncoder();
        JSONObject auth = new JSONObject()
                .put("key", b64.encodeToString(store.publicKey()))
                .put("sig", b64.encodeToString(store.identity().sign(signed(initiator, ""))))
                .put("name", name == null ? "" : name);
        byte[] v1 = store.v1AdmitKey(now);
        if (v1 != null) auth.put("v1", b64.encodeToString(ShareCrypto.hkdfExtract(v1, signed(initiator, "v1"))));
        byte[] invite = store.joinProofFor(peer);
        if (invite != null) {
            auth.put("invite", b64.encodeToString(ShareCrypto.hkdfExtract(invite, signed(initiator, "invite"))));
            java.util.Arrays.fill(invite, (byte) 0);
        }
        return auth;
    }

    /**
     * Checks the other side's proof and returns where it stands; one not listed is listed if it proves an invitation or
     * the version 1 key, and refused otherwise.
     */
    private HouseholdMembers.Standing check(JSONObject auth) throws IOException, GeneralSecurityException {
        Base64.Decoder b64 = Base64.getDecoder();
        byte[] key = b64.decode(auth.optString("key", ""));
        byte[] sig = b64.decode(auth.optString("sig", ""));
        boolean ofInitiator = !initiator;
        if (!HouseholdIdentity.tvIdOf(key).equals(peer) || !HouseholdIdentity.verify(key, signed(ofInitiator, ""), sig)) {
            throw new SyncException("The other TV isn't who it says");
        }
        String given = auth.optString("name", "").trim();
        peerName = given.isEmpty() ? null : given;
        HouseholdMembers.Standing standing = HouseholdMembers.standing(store.log(), peer);
        if (standing != HouseholdMembers.Standing.UNKNOWN) return standing;
        byte[] v1 = store.v1AdmitKey(now);
        String v1Mac = auth.optString("v1", "");
        if (v1 != null && !v1Mac.isEmpty()
                && MessageDigest.isEqual(ShareCrypto.hkdfExtract(v1, signed(ofInitiator, "v1")), b64.decode(v1Mac))) {
            store.admit(peer, key, peerName, now);
            return HouseholdMembers.Standing.MEMBER;
        }
        String inviteMac = auth.optString("invite", "");
        if (!inviteMac.isEmpty() && store.useInvite(signed(ofInitiator, "invite"), b64.decode(inviteMac), now)) {
            store.admit(peer, key, peerName, now);
            return HouseholdMembers.Standing.MEMBER;
        }
        throw new SyncException("The other TV is not in this household");
    }

    // ---- Frames ----

    private void writeJson(JSONObject json) throws IOException, GeneralSecurityException {
        writeFrame(json.toString().getBytes(StandardCharsets.UTF_8));
    }

    private JSONObject readJson() throws IOException, GeneralSecurityException, JSONException {
        return new JSONObject(readText());
    }

    private void writeFrame(byte[] plain) throws IOException, GeneralSecurityException {
        if (plain.length > MAX_FRAME_BYTES) throw new SyncException("Too much to send");
        byte[] sealed = ShareCrypto.seal(sendKey, sendCounter++, aad, plain);
        out.writeInt(sealed.length);
        out.write(sealed);
        out.flush();
    }

    private byte[] readFrame() throws IOException, GeneralSecurityException {
        int length = in.readInt();
        if (length < 16 || length > MAX_FRAME_BYTES + 16) throw new SyncException("Bad frame size");
        byte[] sealed = new byte[length];
        in.readFully(sealed);
        try {
            return ShareCrypto.open(receiveKey, receiveCounter++, aad, sealed);
        } catch (GeneralSecurityException e) {
            throw new SyncException("The other TV is not in this household");
        }
    }

    private String readText() throws IOException, GeneralSecurityException {
        return new String(readFrame(), StandardCharsets.UTF_8);
    }

    private static JSONObject vectorJson(Map<String, Long> vector) throws JSONException {
        JSONObject json = new JSONObject();
        for (Map.Entry<String, Long> e : vector.entrySet()) json.put(e.getKey(), e.getValue());
        return json;
    }

    private static Map<String, Long> readVector(JSONObject json) throws JSONException {
        Map<String, Long> vector = new HashMap<>();
        for (Iterator<String> it = json.keys(); it.hasNext();) {
            String tv = it.next();
            vector.put(tv, json.getLong(tv));
        }
        return vector;
    }

    private static String entriesJson(List<HouseholdEntry> entries) {
        JSONArray array = new JSONArray();
        for (HouseholdEntry entry : entries) array.put(entry.toJson());
        return array.toString();
    }
}
