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
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * One exchange of entries between two TVs of a household (docs/household-sync.md), over any pair of streams. Both
 * sides trade a random nonce in the clear, then every frame is sealed (ChaCha20-Poly1305) under keys derived from the
 * household key and both nonces, with a counter per direction, so a TV that doesn't have the key can't take part, and a
 * recorded exchange can't be played back. Each side says what it has seen from each TV (its version vector), then
 * sends what the other lacks, then merges what it got. The initiator speaks first at every step, so neither side waits on
 * the other's write. Nothing about a profile or a PIN is in the clear.
 */
final class HouseholdSync {
    private static final byte[] MAGIC = {'H', 'H', 'S', '1'};
    private static final int NONCE_BYTES = 16;
    private static final int MAX_FRAME_BYTES = 8 * 1024 * 1024;
    static final int MAX_ENTRIES = 20_000;
    private static final byte[] LABEL = ShareCrypto.bytes("hearth-household-sync-v1");
    private static final SecureRandom RANDOM = new SecureRandom();

    /** What an exchange did, for the screen and the log. */
    static final class Result {
        final String peer;
        final int sent;
        final int received;
        /** The entries that changed this TV (they beat what it had), for the app to apply. */
        final List<HouseholdEntry> applied;

        Result(String peer, int sent, int received, List<HouseholdEntry> applied) {
            this.peer = peer;
            this.sent = sent;
            this.received = received;
            this.applied = applied;
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
    private final long now;
    private byte[] sendKey;
    private byte[] receiveKey;
    private byte[] aad;
    private long sendCounter;
    private long receiveCounter;

    private HouseholdSync(InputStream in, OutputStream out, boolean initiator, HouseholdStore store, long now) {
        this.in = new DataInputStream(in);
        this.out = new DataOutputStream(out);
        this.initiator = initiator;
        this.store = store;
        this.now = now;
    }

    /**
     * Runs the exchange as the TV that connected ({@code initiator}) or the one that accepted. The log is merged but
     * not saved; the caller saves it ({@link HouseholdStore#save}) and applies {@link Result#applied}.
     */
    static Result run(InputStream in, OutputStream out, boolean initiator, HouseholdStore store, long now)
            throws IOException, GeneralSecurityException {
        if (!store.joined() || store.log() == null) throw new SyncException("Not in a household");
        try {
            return new HouseholdSync(in, out, initiator, store, now).exchange();
        } catch (JSONException e) {
            throw new SyncException("Not a household exchange");
        }
    }

    private Result exchange() throws IOException, GeneralSecurityException, JSONException {
        byte[] mine = new byte[NONCE_BYTES];
        RANDOM.nextBytes(mine);
        byte[] theirs = new byte[NONCE_BYTES];
        byte[] magic = new byte[MAGIC.length];
        if (initiator) {
            sendHello(mine);
            readHello(magic, theirs);
        } else {
            readHello(magic, theirs);
            sendHello(mine);
        }
        deriveKeys(initiator ? mine : theirs, initiator ? theirs : mine);

        // 1. what each side has seen
        JSONObject hello = new JSONObject().put("tv", store.tvId()).put("vector", vectorJson(store.log().vector()));
        JSONObject peerHello;
        if (initiator) {
            writeFrame(hello.toString().getBytes(StandardCharsets.UTF_8));
            peerHello = new JSONObject(readText());
        } else {
            peerHello = new JSONObject(readText());
            writeFrame(hello.toString().getBytes(StandardCharsets.UTF_8));
        }
        String peer = peerHello.getString("tv");
        if (peer.isEmpty() || peer.equals(store.tvId())) throw new SyncException("Bad peer");
        Map<String, Long> peerVector = readVector(peerHello.getJSONObject("vector"));

        // 2. what each side lacks
        List<HouseholdEntry> toSend = store.log().missingFrom(peerVector);
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

        // 3. merge
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
        return new Result(peer, toSend.size(), received, applied);
    }

    private void sendHello(byte[] nonce) throws IOException {
        out.write(MAGIC);
        out.write(nonce);
        out.flush();
    }

    private void readHello(byte[] magic, byte[] nonce) throws IOException {
        in.readFully(magic);
        if (!MessageDigest.isEqual(magic, MAGIC)) throw new SyncException("Not a household exchange");
        in.readFully(nonce);
    }

    private void deriveKeys(byte[] initiatorNonce, byte[] responderNonce) throws IOException, GeneralSecurityException {
        byte[] key = store.exportKey();
        if (key == null) throw new SyncException("Not in a household");
        try {
            byte[] prk = ShareCrypto.hkdfExtract(ShareCrypto.sha256(LABEL, initiatorNonce, responderNonce), key);
            byte[] i2r = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("i2r"), ShareCrypto.KEY_BYTES);
            byte[] r2i = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("r2i"), ShareCrypto.KEY_BYTES);
            sendKey = initiator ? i2r : r2i;
            receiveKey = initiator ? r2i : i2r;
            aad = ShareCrypto.bytes(store.householdId());
        } finally {
            java.util.Arrays.fill(key, (byte) 0);
        }
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
