package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Random;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.After;
import org.junit.Test;

/** The TV-to-TV copy's session: the key exchange, the digits, and what a changed or cut-short stream does. */
public class ShareSessionTest {
    private final ExecutorService pool = Executors.newCachedThreadPool();
    private final List<AutoCloseable> open = new ArrayList<>();

    @After
    public void tearDown() throws Exception {
        for (AutoCloseable c : open) {
            try {
                c.close();
            } catch (Exception ignored) {
            }
        }
        pool.shutdownNow();
    }

    /** A frame as it crosses the wire. */
    private static final class Frame {
        byte type;
        byte flag;
        byte[] body;

        Frame(byte type, byte flag, byte[] body) {
            this.type = type;
            this.flag = flag;
            this.body = body;
        }
    }

    /** Sits between the TVs and may change, drop, repeat or reorder frames: what someone on the network could do. */
    private interface Tamper {
        /** {@code toReceiver}: the frame is going from the sender to the receiver; {@code index}: its place in that direction. */
        List<Frame> apply(boolean toReceiver, int index, Frame frame);
    }

    private static final Tamper HONEST = (toReceiver, index, frame) -> Arrays.asList(frame);

    private static final class Link {
        final Socket sender;
        final Socket receiver;

        Link(Socket sender, Socket receiver) {
            this.sender = sender;
            this.receiver = receiver;
        }
    }

    /** A connected pair of sockets with {@code tamper} in between. */
    private Link link(Tamper tamper) throws Exception {
        ServerSocket senderSide = new ServerSocket(0, 1, InetAddress.getLoopbackAddress());
        ServerSocket proxy = new ServerSocket(0, 1, InetAddress.getLoopbackAddress());
        open.add(senderSide);
        open.add(proxy);
        Future<Socket> accepted = pool.submit(senderSide::accept);
        Socket receiver = new Socket(InetAddress.getLoopbackAddress(), proxy.getLocalPort());
        Socket fromReceiver = proxy.accept();
        Socket toSender = new Socket(InetAddress.getLoopbackAddress(), senderSide.getLocalPort());
        Socket sender = accepted.get(5, TimeUnit.SECONDS);
        for (Socket s : new Socket[]{sender, receiver, fromReceiver, toSender}) {
            s.setSoTimeout(5000);
            open.add(s);
        }
        pool.submit(() -> pump(fromReceiver, toSender, false, tamper));
        pool.submit(() -> pump(toSender, fromReceiver, true, tamper));
        return new Link(sender, receiver);
    }

    private static void pump(Socket from, Socket to, boolean toReceiver, Tamper tamper) {
        try {
            DataInputStream in = new DataInputStream(from.getInputStream());
            DataOutputStream out = new DataOutputStream(to.getOutputStream());
            for (int index = 0; ; index++) {
                byte type = in.readByte();
                byte flag = in.readByte();
                byte[] body = new byte[in.readInt()];
                in.readFully(body);
                for (Frame f : tamper.apply(toReceiver, index, new Frame(type, flag, body))) {
                    out.writeByte(f.type);
                    out.writeByte(f.flag);
                    out.writeInt(f.body.length);
                    out.write(f.body);
                    out.flush();
                }
            }
        } catch (IOException e) {
            // One side closed: close the other so its reader ends too
            try {
                to.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static byte[] random(int n) {
        byte[] b = new byte[n];
        new Random(7).nextBytes(b);
        return b;
    }

    private ShareSession senderOf(Link link) throws IOException {
        return ShareSession.sender(link.sender.getInputStream(), link.sender.getOutputStream());
    }

    private ShareSession receiverOf(Link link) throws IOException {
        return ShareSession.receiver(link.receiver.getInputStream(), link.receiver.getOutputStream());
    }

    private static <T> T get(Future<T> future) throws Exception {
        try {
            return future.get(10, TimeUnit.SECONDS);
        } catch (java.util.concurrent.ExecutionException e) {
            if (e.getCause() instanceof Exception) throw (Exception) e.getCause();
            throw e;
        }
    }

    /** Runs the key exchange on both ends and returns {senderDigits, receiverDigits}. */
    private String[] handshake(ShareSession sender, ShareSession receiver) throws Exception {
        Future<String> a = pool.submit((Callable<String>) sender::handshake);
        Future<String> b = pool.submit((Callable<String>) receiver::handshake);
        return new String[]{get(a), get(b)};
    }

    private void confirmBoth(ShareSession sender, ShareSession receiver) throws Exception {
        Future<Void> a = pool.submit(() -> {
            sender.confirm();
            return null;
        });
        Future<Void> b = pool.submit(() -> {
            receiver.confirm();
            return null;
        });
        get(a);
        get(b);
    }

    @Test
    public void bothTvsShowTheSameSixDigitsAndCopyAPayload() throws Exception {
        Link link = link(HONEST);
        ShareSession sender = senderOf(link);
        ShareSession receiver = receiverOf(link);
        String[] digits = handshake(sender, receiver);
        assertEquals(digits[0], digits[1]);
        assertTrue(digits[0].matches("[0-9]{6}"));
        confirmBoth(sender, receiver);

        byte[] payload = random(300_000);
        Future<byte[]> got = pool.submit(() -> receiver.receive(1_000_000));
        sender.send(payload);
        assertArrayEquals(payload, get(got));

        // The receiver answers the other way, under its own key
        Future<byte[]> report = pool.submit(() -> sender.receive(1000));
        receiver.send("{\"applied\":3}".getBytes("UTF-8"));
        assertEquals("{\"applied\":3}", new String(get(report), "UTF-8"));
    }

    @Test
    public void anEmptyPayloadAndAnExactChunkBoundaryArrive() throws Exception {
        for (int size : new int[]{0, 1, ShareSession.CHUNK_BYTES, ShareSession.CHUNK_BYTES + 1,
                2 * ShareSession.CHUNK_BYTES}) {
            Link link = link(HONEST);
            ShareSession sender = senderOf(link);
            ShareSession receiver = receiverOf(link);
            handshake(sender, receiver);
            confirmBoth(sender, receiver);
            byte[] payload = random(size);
            Future<byte[]> got = pool.submit(() -> receiver.receive(1_000_000));
            sender.send(payload);
            assertArrayEquals("size " + size, payload, get(got));
        }
    }

    @Test
    public void everySessionHasItsOwnDigits() throws Exception {
        java.util.Set<String> seen = new java.util.HashSet<>();
        for (int i = 0; i < 6; i++) {
            Link link = link(HONEST);
            seen.add(handshake(senderOf(link), receiverOf(link))[0]);
        }
        assertTrue("digits repeat: " + seen, seen.size() > 1);
    }

    @Test
    public void aParentWhoSeesDifferentDigitsStopsTheOtherTv() throws Exception {
        Link link = link(HONEST);
        ShareSession sender = senderOf(link);
        ShareSession receiver = receiverOf(link);
        handshake(sender, receiver);
        Future<Void> waiting = pool.submit(() -> {
            sender.confirm();
            return null;
        });
        receiver.abort();
        try {
            get(waiting);
            fail("the sender went on");
        } catch (ShareSession.ShareException expected) {
            assertTrue(expected.getMessage().contains("stopped"));
        }
    }

    @Test
    public void aChangedNonceShowsDifferentDigits() throws Exception {
        // Someone alters what the sender revealed on its way to the receiver
        Link link = link((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 2) {
                frame.body[frame.body.length - 1] ^= 1;
            }
            return Arrays.asList(frame);
        });
        ShareSession sender = senderOf(link);
        ShareSession receiver = receiverOf(link);
        String[] digits = handshake(sender, receiver);
        assertNotEquals("the screens would match", digits[0], digits[1]);
    }

    @Test
    public void aKeyOtherThanTheOneCommittedToIsRefused() throws Exception {
        // The receiver's reveal is replaced by another key pair's point (a man in the middle picking after seeing)
        KeyPair other = ShareCrypto.newKeyPair();
        byte[] otherPoint = ShareCrypto.encodePoint(other.getPublic());
        Link link = link((toReceiver, index, frame) -> {
            if (!toReceiver && frame.type == 3) {
                System.arraycopy(otherPoint, 0, frame.body, 0, otherPoint.length);
            }
            return Arrays.asList(frame);
        });
        ShareSession sender = senderOf(link);
        ShareSession receiver = receiverOf(link);
        Future<String> a = pool.submit((Callable<String>) sender::handshake);
        pool.submit((Callable<String>) receiver::handshake);
        try {
            get(a);
            fail("the sender took a key that wasn't committed to");
        } catch (ShareSession.ShareException expected) {
            assertTrue(expected.getMessage().contains("committed"));
        }
    }

    /** Runs a copy of {@code payload} through {@code tamper} and returns what the receiving end did. */
    private Exception copyThrough(Tamper tamper, byte[] payload, int max) throws Exception {
        Link link = link(tamper);
        ShareSession sender = senderOf(link);
        ShareSession receiver = receiverOf(link);
        handshake(sender, receiver);
        confirmBoth(sender, receiver);
        Future<byte[]> got = pool.submit(() -> receiver.receive(max));
        try {
            sender.send(payload);
            // A sender that finished may close at once; a cut-short stream shows on the receiver's side
            link.sender.close();
        } catch (IOException ignored) {
        }
        try {
            get(got);
            return null;
        } catch (Exception e) {
            return e;
        }
    }

    @Test
    public void aChangedChunkIsAnErrorNotAHalfCopy() throws Exception {
        Exception e = copyThrough((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 6 && index > 3) frame.body[5] ^= 1;
            return Arrays.asList(frame);
        }, random(200_000), 1_000_000);
        assertTrue(String.valueOf(e), e instanceof ShareSession.ShareException);
    }

    @Test
    public void aFlippedLastFlagIsAnError() throws Exception {
        // Making a middle chunk look last (or the last look not last) changes its authenticated header
        Exception e = copyThrough((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 6) frame.flag = (byte) (frame.flag ^ 1);
            return Arrays.asList(frame);
        }, random(200_000), 1_000_000);
        assertTrue(String.valueOf(e), e instanceof ShareSession.ShareException);
    }

    @Test
    public void aCutShortStreamIsAnError() throws Exception {
        // Drops the last chunk and what follows
        Exception e = copyThrough((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 6 && frame.flag == 1) return new ArrayList<>();
            return Arrays.asList(frame);
        }, random(200_000), 1_000_000);
        assertTrue(String.valueOf(e), e instanceof ShareSession.ShareException || e instanceof IOException);
    }

    @Test
    public void aRepeatedOrReorderedChunkIsAnError() throws Exception {
        List<Frame> held = new ArrayList<>();
        Exception reordered = copyThrough((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 6 && frame.flag == 0) {
                if (held.isEmpty()) {
                    held.add(frame);
                    return new ArrayList<>();
                }
                // The second chunk goes first, the first after it
                return Arrays.asList(frame, held.remove(0));
            }
            return Arrays.asList(frame);
        }, random(300_000), 1_000_000);
        assertTrue(String.valueOf(reordered), reordered instanceof ShareSession.ShareException);

        Exception repeated = copyThrough((toReceiver, index, frame) -> {
            if (toReceiver && frame.type == 6 && frame.flag == 0 && index == 3) {
                return Arrays.asList(frame, new Frame(frame.type, frame.flag, frame.body.clone()));
            }
            return Arrays.asList(frame);
        }, random(300_000), 1_000_000);
        assertTrue(String.valueOf(repeated), repeated instanceof ShareSession.ShareException);
    }

    @Test
    public void aPayloadBiggerThanTheReceiverTakesIsRefused() throws Exception {
        Exception e = copyThrough(HONEST, random(200_000), 100_000);
        assertTrue(String.valueOf(e), e instanceof ShareSession.ShareException);
        assertTrue(e.getMessage().contains("More than"));
    }

    @Test
    public void aHugeFrameIsRefusedBeforeItIsRead() throws Exception {
        // A direct pair: the tampering link would wait for the whole body it is told about
        ServerSocket server = new ServerSocket(0, 1, InetAddress.getLoopbackAddress());
        open.add(server);
        Socket receiverSocket = new Socket(InetAddress.getLoopbackAddress(), server.getLocalPort());
        Socket senderSocket = server.accept();
        for (Socket socket : new Socket[]{receiverSocket, senderSocket}) {
            socket.setSoTimeout(5000);
            open.add(socket);
        }
        Link link = new Link(senderSocket, receiverSocket);
        ShareSession receiver = receiverOf(link);
        Future<String> shake = pool.submit((Callable<String>) receiver::handshake);
        // The "sender" answers the receiver's commit with a frame header claiming 100 MB
        DataInputStream in = new DataInputStream(link.sender.getInputStream());
        in.readByte();
        in.readByte();
        byte[] skip = new byte[in.readInt()];
        in.readFully(skip);
        DataOutputStream out = new DataOutputStream(link.sender.getOutputStream());
        out.writeByte(2);
        out.writeByte(0);
        out.writeInt(100 * 1024 * 1024);
        out.flush();
        try {
            get(shake);
            fail("accepted a huge frame");
        } catch (ShareSession.ShareException expected) {
            assertTrue(expected.getMessage().contains("too big"));
        }
    }

    @Test
    public void nothingMovesBeforeBothParentsConfirm() throws Exception {
        Link link = link(HONEST);
        ShareSession sender = senderOf(link);
        handshake(sender, receiverOf(link));
        try {
            sender.send(new byte[1]);
            fail("sent before confirming");
        } catch (IllegalStateException expected) {
            // good
        }
    }

    @Test
    public void aPointNotOnTheCurveIsRefused() throws Exception {
        KeyPair pair = ShareCrypto.newKeyPair();
        byte[] point = ShareCrypto.encodePoint(pair.getPublic());
        point[64] ^= 1;
        try {
            ShareCrypto.decodePoint(point, ShareCrypto.params(pair));
            fail("an off-curve point was taken");
        } catch (GeneralSecurityException expected) {
            // good
        }
        byte[] compressed = Arrays.copyOf(point, point.length);
        compressed[0] = 2;
        try {
            ShareCrypto.decodePoint(compressed, ShareCrypto.params(pair));
            fail("a compressed point was taken");
        } catch (GeneralSecurityException expected) {
            // good
        }
    }

    @Test
    public void hkdfMatchesRfc5869TestCase1() throws Exception {
        byte[] ikm = new byte[22];
        Arrays.fill(ikm, (byte) 0x0b);
        byte[] salt = hex("000102030405060708090a0b0c");
        byte[] info = hex("f0f1f2f3f4f5f6f7f8f9");
        byte[] prk = ShareCrypto.hkdfExtract(salt, ikm);
        assertArrayEquals(hex("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"), prk);
        assertArrayEquals(hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"),
                ShareCrypto.hkdfExpand(prk, info, 42));
    }

    @Test
    public void digitsKeepTheirLeadingZeros() {
        assertEquals("000042", ShareCrypto.sas(new byte[]{0, 0, 0, 42}));
        assertEquals("000000", ShareCrypto.sas(new byte[]{0, 0, 0, 0}));
        assertEquals(6, ShareCrypto.sas(new byte[]{(byte) 0xff, (byte) 0xff, (byte) 0xff, (byte) 0xff}).length());
    }

    private static byte[] hex(String s) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (int i = 0; i < s.length(); i += 2) out.write(Integer.parseInt(s.substring(i, i + 2), 16));
        return out.toByteArray();
    }
}
