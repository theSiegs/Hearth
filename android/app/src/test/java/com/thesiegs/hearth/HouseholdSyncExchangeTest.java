package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

import org.junit.Test;

/** Two TVs trading entries over a real socket: what moves, and what a TV outside the household can't do. */
public class HouseholdSyncExchangeTest {
    private static final long T0 = 1_800_000_000_000L;

    private static final class MapBacking implements HouseholdStore.Backing {
        final Map<String, String> map = new HashMap<>();

        @Override
        public String get(String key) {
            return map.get(key);
        }

        @Override
        public void put(String key, String value) {
            map.put(key, value);
        }

        @Override
        public void remove(String key) {
            map.remove(key);
        }
    }

    private static SecretBox.Keys memoryKeys() {
        Map<String, SecretKey> keys = new HashMap<>();
        return alias -> {
            SecretKey key = keys.get(alias);
            if (key == null) {
                KeyGenerator generator = KeyGenerator.getInstance("AES");
                generator.init(256);
                key = generator.generateKey();
                keys.put(alias, key);
            }
            return key;
        };
    }

    private static HouseholdStore tv() {
        return HouseholdStore.open(new MapBacking(), memoryKeys());
    }

    /** Two TVs in one household. */
    private static HouseholdStore[] pair() {
        HouseholdStore a = tv();
        a.create();
        HouseholdStore b = tv();
        b.join(a.exportKey());
        return new HouseholdStore[] {a, b};
    }

    private static final class Wire {
        final ByteArrayOutputStream seen = new ByteArrayOutputStream();
    }

    /** Runs one exchange: {@code a} connects, {@code b} accepts. */
    private static HouseholdSync.Result[] exchange(HouseholdStore a, HouseholdStore b, Wire wire) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try (ServerSocket server = new ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
            server.setSoTimeout(5000);
            Future<HouseholdSync.Result> accepting = pool.submit(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    return HouseholdSync.run(socket.getInputStream(), socket.getOutputStream(), false, b, T0 + 100);
                }
            });
            Future<HouseholdSync.Result> connecting = pool.submit(() -> {
                try (Socket socket = new Socket(java.net.InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                    socket.setSoTimeout(5000);
                    InputStream in = socket.getInputStream();
                    OutputStream out = socket.getOutputStream();
                    if (wire != null) {
                        return HouseholdSync.run(tapped(in, wire), tapped(out, wire), true, a, T0 + 100);
                    }
                    return HouseholdSync.run(in, out, true, a, T0 + 100);
                }
            });
            return new HouseholdSync.Result[] {connecting.get(10, TimeUnit.SECONDS), accepting.get(10, TimeUnit.SECONDS)};
        } finally {
            pool.shutdownNow();
        }
    }

    private static InputStream tapped(InputStream in, Wire wire) {
        return new InputStream() {
            @Override
            public int read() throws IOException {
                int b = in.read();
                if (b >= 0) wire.seen.write(b);
                return b;
            }

            @Override
            public int read(byte[] buffer, int offset, int length) throws IOException {
                int n = in.read(buffer, offset, length);
                if (n > 0) wire.seen.write(buffer, offset, n);
                return n;
            }
        };
    }

    private static OutputStream tapped(OutputStream out, Wire wire) {
        return new OutputStream() {
            @Override
            public void write(int b) throws IOException {
                wire.seen.write(b);
                out.write(b);
            }

            @Override
            public void write(byte[] buffer, int offset, int length) throws IOException {
                wire.seen.write(buffer, offset, length);
                out.write(buffer, offset, length);
            }

            @Override
            public void flush() throws IOException {
                out.flush();
            }
        };
    }

    @Test
    public void twoTvsEndUpWithEachOthersEntries() throws Exception {
        HouseholdStore[] tvs = pair();
        tvs[0].log().put("pairing", "Alex", "netflix", "Alex R", T0);
        tvs[1].log().put("pin", "Sam", "disney", "135790", T0 + 1);
        HouseholdSync.Result[] results = exchange(tvs[0], tvs[1], null);
        assertEquals(1, results[0].sent);
        assertEquals(1, results[0].received);
        assertEquals(tvs[1].tvId(), results[0].peer);
        assertEquals(tvs[0].tvId(), results[1].peer);
        assertEquals("135790", tvs[0].log().get("pin", "Sam", "disney").value);
        assertEquals("Alex R", tvs[1].log().get("pairing", "Alex", "netflix").value);
        assertEquals(1, results[0].applied.size());
        assertEquals("pin", results[0].applied.get(0).kind);
    }

    @Test
    public void aSecondExchangeSendsNothingNew() throws Exception {
        HouseholdStore[] tvs = pair();
        tvs[0].log().put("pairing", "Alex", "netflix", "x", T0);
        exchange(tvs[0], tvs[1], null);
        HouseholdSync.Result[] again = exchange(tvs[0], tvs[1], null);
        assertEquals(0, again[0].sent);
        assertEquals(0, again[1].sent);
        assertTrue(again[0].applied.isEmpty());
    }

    @Test
    public void aDeleteTravelsAndTheNewestWriteWins() throws Exception {
        HouseholdStore[] tvs = pair();
        tvs[0].log().put("pin", "Sam", "disney", "1111", T0);
        exchange(tvs[0], tvs[1], null);
        tvs[1].log().delete("pin", "Sam", "disney", T0 + 1000);
        tvs[0].log().put("look", "Sam", "theme", "dark", T0 + 2000);
        exchange(tvs[0], tvs[1], null);
        assertNull(tvs[0].log().get("pin", "Sam", "disney"));
        assertEquals("dark", tvs[1].log().get("look", "Sam", "theme").value);
    }

    @Test
    public void nothingReadableCrossesTheWire() throws Exception {
        HouseholdStore[] tvs = pair();
        tvs[0].log().put("pin", "Sam", "disney", "135790", T0);
        Wire wire = new Wire();
        exchange(tvs[0], tvs[1], wire);
        String seen = new String(wire.seen.toByteArray(), java.nio.charset.StandardCharsets.ISO_8859_1);
        assertFalse(seen.contains("135790"));
        assertFalse(seen.contains("disney"));
        assertFalse(seen.contains("sam"));
    }

    @Test
    public void aTvFromAnotherHouseholdCannotTakePart() throws Exception {
        HouseholdStore ours = tv();
        ours.create();
        ours.log().put("pin", "Sam", "disney", "135790", T0);
        HouseholdStore stranger = tv();
        stranger.create();
        try {
            exchange(stranger, ours, null);
            fail("expected a refusal");
        } catch (java.util.concurrent.ExecutionException expected) {
            assertTrue(expected.getCause() instanceof IOException);
        }
        assertNull(stranger.log().get("pin", "Sam", "disney"));
    }

    @Test
    public void aTvNotInAHouseholdCannotRun() throws Exception {
        HouseholdStore none = tv();
        try {
            HouseholdSync.run(new java.io.ByteArrayInputStream(new byte[0]), new ByteArrayOutputStream(), true, none, T0);
            fail("expected a refusal");
        } catch (HouseholdSync.SyncException expected) {
            // not in a household
        }
    }

    @Test
    public void somethingThatIsNotAnExchangeIsRefused() throws Exception {
        HouseholdStore[] tvs = pair();
        byte[] junk = new byte[64];
        java.util.Arrays.fill(junk, (byte) 'x');
        try {
            HouseholdSync.run(new java.io.ByteArrayInputStream(junk), new ByteArrayOutputStream(), false, tvs[0], T0);
            fail("expected a refusal");
        } catch (HouseholdSync.SyncException expected) {
            // not a household exchange
        }
    }

    @Test
    public void threeTvsMeetingInPairsAgree() throws Exception {
        HouseholdStore a = tv();
        a.create();
        HouseholdStore b = tv();
        b.join(a.exportKey());
        HouseholdStore c = tv();
        c.join(a.exportKey());
        a.log().put("look", "Alex", "theme", "dark", T0);
        c.log().put("look", "Sam", "theme", "light", T0 + 5);
        b.log().put("pairing", "Alex", "hulu", "A", T0 + 6);
        exchange(a, b, null);
        exchange(b, c, null);
        exchange(c, a, null);
        for (HouseholdStore tv : new HouseholdStore[] {a, b, c}) {
            assertEquals("dark", tv.log().get("look", "Alex", "theme").value);
            assertEquals("light", tv.log().get("look", "Sam", "theme").value);
            assertEquals("A", tv.log().get("pairing", "Alex", "hulu").value);
        }
    }
}
