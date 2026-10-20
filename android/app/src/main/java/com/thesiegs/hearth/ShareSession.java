package com.thesiegs.hearth;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.spec.ECParameterSpec;
import java.util.Arrays;

/**
 * One copy of a profile from one TV to another, on the home network, with a parent at both screens. No key is stored
 * anywhere: each session makes its own and forgets it.
 *
 * <p>The receiving TV connects to the sending TV. It commits to its public key first, the sender reveals its own, then
 * the receiver reveals the one it committed to, so a man in the middle can't pick a key after seeing the other's.
 * Both ends derive the same two directional keys and the same six digits; the parent checks that the screens show
 * the same digits and says so on each ({@link #confirm}), which sends a sealed confirmation each way before anything
 * else moves. After that {@link #send} and {@link #receive} move one payload in chunks, each sealed and numbered, the
 * last one marked, so a changed, dropped, repeated, reordered or cut-short chunk is an error, not a half copy.
 *
 * <p>Frames are {@code type(1) flag(1) length(4) body}. The type and flag of a sealed frame are authenticated as its
 * additional data. The streams' timeouts are the caller's.
 */
final class ShareSession {
    /** A peer that refused (a parent saw different digits) or a stream that broke the protocol. */
    static final class ShareException extends IOException {
        ShareException(String message) {
            super(message);
        }
    }

    private static final int VERSION = 1;
    private static final byte COMMIT = 1;
    private static final byte REVEAL_A = 2;
    private static final byte REVEAL_B = 3;
    private static final byte ABORT = 4;
    private static final byte CONFIRM = 5;
    private static final byte DATA = 6;
    /** A sealed frame's body is at most this many plain bytes; the receiver refuses a bigger frame outright. */
    static final int CHUNK_BYTES = 64 * 1024;
    private static final int MAX_FRAME_BODY = CHUNK_BYTES + 64;
    private static final int NONCE_BYTES = 16;
    private static final byte[] LABEL = ShareCrypto.bytes("hearth-share v1");
    private static final SecureRandom RANDOM = new SecureRandom();

    private final boolean mSender;
    private final DataInputStream mIn;
    private final OutputStream mOut;
    private byte[] mSendKey;
    private byte[] mReceiveKey;
    private long mSendCounter;
    private long mReceiveCounter;
    private String mSas;
    private boolean mConfirmed;

    private ShareSession(boolean sender, InputStream in, OutputStream out) {
        mSender = sender;
        mIn = new DataInputStream(in);
        mOut = out;
    }

    /** The TV that has the profile and listens (the side that accepted the connection). */
    static ShareSession sender(InputStream in, OutputStream out) {
        return new ShareSession(true, in, out);
    }

    /** The TV that wants the profile and connected. */
    static ShareSession receiver(InputStream in, OutputStream out) {
        return new ShareSession(false, in, out);
    }

    /**
     * Runs the key exchange and returns the six digits to show. Call it once, first. Throws {@link ShareException} if
     * the other end broke the protocol or backed out.
     */
    String handshake() throws IOException, GeneralSecurityException {
        KeyPair pair = ShareCrypto.newKeyPair();
        ECParameterSpec params = ShareCrypto.params(pair);
        byte[] mine = ShareCrypto.encodePoint(pair.getPublic());
        byte[] myNonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(myNonce);
        byte[] commit;
        byte[] pubA;
        byte[] nonceA;
        byte[] pubB;
        byte[] nonceB;
        if (mSender) {
            byte[] hello = read(COMMIT);
            if (hello.length != 1 + 32 || hello[0] != VERSION) throw new ShareException("Not the same version");
            commit = Arrays.copyOfRange(hello, 1, hello.length);
            pubA = mine;
            nonceA = myNonce;
            write(REVEAL_A, 0, concat(pubA, nonceA));
            byte[] reveal = read(REVEAL_B);
            if (reveal.length != ShareCrypto.POINT_BYTES + NONCE_BYTES) throw new ShareException("Bad reveal");
            pubB = Arrays.copyOfRange(reveal, 0, ShareCrypto.POINT_BYTES);
            nonceB = Arrays.copyOfRange(reveal, ShareCrypto.POINT_BYTES, reveal.length);
            // What was committed to is what was revealed
            if (!MessageDigest.isEqual(commit, ShareCrypto.sha256(pubB, nonceB))) {
                throw new ShareException("The key changed after it was committed to");
            }
        } else {
            pubB = mine;
            nonceB = myNonce;
            commit = ShareCrypto.sha256(pubB, nonceB);
            write(COMMIT, 0, concat(new byte[]{VERSION}, commit));
            byte[] reveal = read(REVEAL_A);
            if (reveal.length != ShareCrypto.POINT_BYTES + NONCE_BYTES) throw new ShareException("Bad reveal");
            pubA = Arrays.copyOfRange(reveal, 0, ShareCrypto.POINT_BYTES);
            nonceA = Arrays.copyOfRange(reveal, ShareCrypto.POINT_BYTES, reveal.length);
            write(REVEAL_B, 0, concat(pubB, nonceB));
        }
        PublicKey theirs = ShareCrypto.decodePoint(mSender ? pubB : pubA, params);
        byte[] z = ShareCrypto.agree(pair, theirs);
        byte[] transcript = ShareCrypto.sha256(LABEL, commit, pubA, nonceA, pubB, nonceB);
        byte[] prk = ShareCrypto.hkdfExtract(transcript, z);
        byte[] aToB = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("hearth-share v1 a2b"), ShareCrypto.KEY_BYTES);
        byte[] bToA = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("hearth-share v1 b2a"), ShareCrypto.KEY_BYTES);
        mSendKey = mSender ? aToB : bToA;
        mReceiveKey = mSender ? bToA : aToB;
        mSas = ShareCrypto.sas(ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("hearth-share v1 sas"), 4));
        Arrays.fill(z, (byte) 0);
        return mSas;
    }

    /**
     * The parent on this TV saw the same six digits as on the other. Seals a confirmation to the peer and waits for
     * its own; both must arrive before anything else moves. Throws {@link ShareException} if the peer backed out.
     */
    void confirm() throws IOException, GeneralSecurityException {
        if (mSas == null) throw new IllegalStateException("handshake first");
        writeSealed(CONFIRM, 0, new byte[0]);
        Frame frame = readFrame();
        if (frame.type == ABORT) throw new ShareException("The other TV stopped");
        if (frame.type != CONFIRM) throw new ShareException("Expected a confirmation");
        openFrame(frame);
        mConfirmed = true;
    }

    /** The digits didn't match (or the parent said no): tells the peer, which then stops. */
    void abort() {
        try {
            write(ABORT, 0, new byte[0]);
        } catch (IOException ignored) {
        }
    }

    /** Sends one payload to the peer, in sealed chunks. After {@link #confirm}. */
    void send(byte[] payload) throws IOException, GeneralSecurityException {
        requireConfirmed();
        int offset = 0;
        do {
            int n = Math.min(CHUNK_BYTES, payload.length - offset);
            boolean last = offset + n >= payload.length;
            writeSealed(DATA, last ? 1 : 0, Arrays.copyOfRange(payload, offset, offset + n));
            offset += n;
        } while (offset < payload.length);
    }

    /** Receives one payload of at most {@code maxBytes}; throws if it was changed, cut short, or too big. */
    byte[] receive(int maxBytes) throws IOException, GeneralSecurityException {
        requireConfirmed();
        ByteArrayOutputStream whole = new ByteArrayOutputStream();
        while (true) {
            Frame frame = readFrame();
            if (frame.type == ABORT) throw new ShareException("The other TV stopped");
            if (frame.type != DATA) throw new ShareException("Expected data");
            byte[] chunk = openFrame(frame);
            if (whole.size() + chunk.length > maxBytes) throw new ShareException("More than this TV will take");
            whole.write(chunk);
            if (frame.flag == 1) return whole.toByteArray();
            if (frame.flag != 0) throw new ShareException("Bad frame");
        }
    }

    // ---- Frames ----

    private static final class Frame {
        final byte type;
        final byte flag;
        final byte[] body;

        Frame(byte type, byte flag, byte[] body) {
            this.type = type;
            this.flag = flag;
            this.body = body;
        }
    }

    private void requireConfirmed() {
        if (!mConfirmed) throw new IllegalStateException("confirm first");
    }

    private void write(byte type, int flag, byte[] body) throws IOException {
        byte[] header = {type, (byte) flag, (byte) (body.length >>> 24), (byte) (body.length >>> 16),
                (byte) (body.length >>> 8), (byte) body.length};
        synchronized (mOut) {
            mOut.write(header);
            mOut.write(body);
            mOut.flush();
        }
    }

    private void writeSealed(byte type, int flag, byte[] plain) throws IOException, GeneralSecurityException {
        byte[] sealed = ShareCrypto.seal(mSendKey, mSendCounter++, new byte[]{type, (byte) flag}, plain);
        write(type, flag, sealed);
    }

    private Frame readFrame() throws IOException {
        byte type;
        try {
            type = mIn.readByte();
        } catch (EOFException e) {
            throw new ShareException("The other TV closed the connection");
        }
        byte flag = mIn.readByte();
        int length = mIn.readInt();
        if (length < 0 || length > MAX_FRAME_BODY) throw new ShareException("Frame too big");
        byte[] body = new byte[length];
        mIn.readFully(body);
        return new Frame(type, flag, body);
    }

    private byte[] read(byte expected) throws IOException {
        Frame frame = readFrame();
        if (frame.type == ABORT) throw new ShareException("The other TV stopped");
        if (frame.type != expected) throw new ShareException("Out of order");
        return frame.body;
    }

    /** Opens a sealed frame with the next counter; a frame out of order, repeated or changed fails here. */
    private byte[] openFrame(Frame frame) throws ShareException {
        try {
            return ShareCrypto.open(mReceiveKey, mReceiveCounter++, new byte[]{frame.type, frame.flag}, frame.body);
        } catch (GeneralSecurityException e) {
            throw new ShareException("A frame didn't check out");
        }
    }

    private static byte[] concat(byte[] a, byte[] b) {
        byte[] out = Arrays.copyOf(a, a.length + b.length);
        System.arraycopy(b, 0, out, a.length, b.length);
        return out;
    }
}
