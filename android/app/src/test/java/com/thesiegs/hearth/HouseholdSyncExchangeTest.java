package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.Test;

/**
 * TVs trading entries over a real socket: how a TV is admitted, what moves, what a removed TV is told, and what a TV
 * outside the household can't do.
 */
public class HouseholdSyncExchangeTest {
    private static final long T0 = 1_800_000_000_000L;

    /** A TV that starts a household. */
    private static HouseholdTvs.Tv first() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        return tv;
    }

    /** A TV that joins {@code host}'s household through an invitation (what a copy hands over). */
    private static HouseholdTvs.Tv joining(HouseholdTvs.Tv host, String name) {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        assertTrue(tv.store.join(host.store.invite("Office", T0), name, T0));
        return tv;
    }

    /** Two TVs in one household that have met once. */
    private static HouseholdTvs.Tv[] pair() throws Exception {
        HouseholdTvs.Tv a = first();
        HouseholdTvs.Tv b = joining(a, "Kitchen");
        exchange(b, a, null);
        return new HouseholdTvs.Tv[] {a, b};
    }

    static final class Wire {
        final ByteArrayOutputStream seen = new ByteArrayOutputStream();
    }

    private static HouseholdSync.Result[] exchange(HouseholdTvs.Tv a, HouseholdTvs.Tv b, Wire wire) throws Exception {
        return exchange(a.store, b.store, wire, T0 + 100);
    }

    /** Runs one exchange: {@code a} connects, {@code b} accepts. */
    static HouseholdSync.Result[] exchange(HouseholdStore a, HouseholdStore b, Wire wire, long now)
            throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try (ServerSocket server = new ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
            server.setSoTimeout(5000);
            Future<HouseholdSync.Result> accepting = pool.submit(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    return HouseholdSync.run(socket.getInputStream(), socket.getOutputStream(), false, b, "B", now);
                }
            });
            Future<HouseholdSync.Result> connecting = pool.submit(() -> {
                try (Socket socket = new Socket(java.net.InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                    socket.setSoTimeout(5000);
                    InputStream in = socket.getInputStream();
                    OutputStream out = socket.getOutputStream();
                    if (wire != null) {
                        return HouseholdSync.run(tapped(in, wire), tapped(out, wire), true, a, "A", now);
                    }
                    return HouseholdSync.run(in, out, true, a, "A", now);
                }
            });
            HouseholdSync.Result connected;
            try {
                connected = connecting.get(10, TimeUnit.SECONDS);
            } finally {
                // whichever side refused, the other one's failure is the one a test may look at
                try {
                    accepting.get(10, TimeUnit.SECONDS);
                } catch (ExecutionException ignored) {
                }
            }
            return new HouseholdSync.Result[] {connected, accepting.get(10, TimeUnit.SECONDS)};
        } finally {
            pool.shutdownNow();
        }
    }

    private static void refused(HouseholdTvs.Tv a, HouseholdTvs.Tv b) throws Exception {
        try {
            exchange(a, b, null);
            fail("expected a refusal");
        } catch (ExecutionException expected) {
            assertTrue(expected.getCause() instanceof IOException);
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

    private static HouseholdMembers.Standing standing(HouseholdTvs.Tv on, HouseholdTvs.Tv of) {
        return HouseholdMembers.standing(on.store.log(), of.store.tvId());
    }

    // ---- Joining ----

    @Test
    public void aTvWithAnInvitationIsListedAtItsFirstExchangeEitherWayRound() throws Exception {
        for (boolean joinerConnects : new boolean[] {true, false}) {
            HouseholdTvs.Tv a = first();
            HouseholdTvs.Tv b = joining(a, "Kitchen");
            assertEquals(HouseholdMembers.Standing.UNKNOWN, standing(a, b));
            HouseholdSync.Result[] results = joinerConnects ? exchange(b, a, null) : exchange(a, b, null);
            assertEquals(HouseholdMembers.Standing.MEMBER, standing(a, b));
            // listed under the name it gave in the exchange
            assertEquals(joinerConnects ? "A" : "B", HouseholdMembers.nameOf(
                    a.store.log().get(HouseholdMembers.KIND, HouseholdBridge.SHARED, b.store.tvId()).value));
            // the connecting side hears the name the accepting side gave
            assertEquals("B", results[0].peerName);
            // the invitation is spent on both sides
            assertNull(b.store.joinProofFor(a.store.tvId()));
            HouseholdTvs.Tv c = new HouseholdTvs.Tv();
            c.store.join(HouseholdStore.Invitation.fromJson(a.store.invite("Office", T0).toJson()), "Attic", T0);
            assertNotNull(c.store.joinProofFor(a.store.tvId()));
        }
    }

    @Test
    public void anInvitationAdmitsOnlyOneTv() throws Exception {
        HouseholdTvs.Tv a = first();
        HouseholdStore.Invitation inv = a.store.invite("Office", T0);
        HouseholdTvs.Tv b = new HouseholdTvs.Tv();
        b.store.join(inv, "Kitchen", T0);
        exchange(b, a, null);
        HouseholdTvs.Tv copycat = new HouseholdTvs.Tv();
        copycat.store.join(inv, "Attic", T0);
        refused(copycat, a);
        assertEquals(HouseholdMembers.Standing.UNKNOWN, standing(a, copycat));
    }

    @Test
    public void aTvThatJoinedThroughOneTvIsKnownToTheOthersThroughIt() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        HouseholdTvs.Tv c = joining(tvs[0], "Attic");
        exchange(c, tvs[0], null);
        // b hasn't heard of c yet: they can't sync
        refused(c, tvs[1]);
        exchange(tvs[0], tvs[1], null);
        exchange(c, tvs[1], null);
        assertEquals(HouseholdMembers.Standing.MEMBER, standing(tvs[1], c));
        assertEquals(HouseholdMembers.Standing.MEMBER, standing(c, tvs[1]));
    }

    // ---- Moving entries ----

    @Test
    public void twoTvsEndUpWithEachOthersEntries() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        tvs[0].store.log().put("pairing", "Alex", "netflix", "Alex R", T0);
        tvs[1].store.log().put("pin", "Sam", "disney", "135790", T0 + 1);
        HouseholdSync.Result[] results = exchange(tvs[0], tvs[1], null);
        assertEquals(1, results[0].sent);
        assertEquals(1, results[0].received);
        assertEquals(tvs[1].store.tvId(), results[0].peer);
        assertEquals(tvs[0].store.tvId(), results[1].peer);
        assertEquals("135790", tvs[0].store.log().get("pin", "Sam", "disney").value);
        assertEquals("Alex R", tvs[1].store.log().get("pairing", "Alex", "netflix").value);
        assertEquals("pin", results[0].applied.get(0).kind);
    }

    @Test
    public void aSecondExchangeSendsNothingNew() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        tvs[0].store.log().put("pairing", "Alex", "netflix", "x", T0);
        exchange(tvs[0], tvs[1], null);
        HouseholdSync.Result[] again = exchange(tvs[0], tvs[1], null);
        assertEquals(0, again[0].sent);
        assertEquals(0, again[1].sent);
        assertTrue(again[0].applied.isEmpty());
    }

    @Test
    public void nothingReadableCrossesTheWire() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        tvs[0].store.log().put("pin", "Sam", "disney", "135790", T0);
        Wire wire = new Wire();
        exchange(tvs[0], tvs[1], wire);
        String seen = new String(wire.seen.toByteArray(), java.nio.charset.StandardCharsets.ISO_8859_1);
        assertFalse(seen.contains("135790"));
        assertFalse(seen.contains("disney"));
        assertFalse(seen.contains("Office"));
        assertFalse(seen.contains("Kitchen"));
    }

    @Test
    public void threeTvsMeetingInPairsAgree() throws Exception {
        HouseholdTvs.Tv a = first();
        HouseholdTvs.Tv b = joining(a, "Kitchen");
        HouseholdTvs.Tv c = joining(a, "Attic");
        exchange(b, a, null);
        exchange(c, a, null);
        exchange(a, b, null);
        a.store.log().put("look", "Alex", "theme", "dark", T0);
        c.store.log().put("look", "Sam", "theme", "light", T0 + 5);
        b.store.log().put("pairing", "Alex", "hulu", "A", T0 + 6);
        exchange(a, b, null);
        exchange(b, c, null);
        exchange(c, a, null);
        exchange(a, b, null);
        for (HouseholdTvs.Tv tv : new HouseholdTvs.Tv[] {a, b, c}) {
            assertEquals("dark", tv.store.log().get("look", "Alex", "theme").value);
            assertEquals("light", tv.store.log().get("look", "Sam", "theme").value);
            assertEquals("A", tv.store.log().get("pairing", "Alex", "hulu").value);
        }
    }

    // ---- Who can't take part ----

    @Test
    public void aTvFromAnotherHouseholdCannotTakePart() throws Exception {
        HouseholdTvs.Tv ours = first();
        ours.store.log().put("pin", "Sam", "disney", "135790", T0);
        HouseholdTvs.Tv stranger = first();
        refused(stranger, ours);
        assertNull(stranger.store.log().get("pin", "Sam", "disney"));
    }

    @Test
    public void aTvThatKnowsTheHouseholdButIsNotListedCannotTakePart() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        tvs[0].store.log().put("pin", "Sam", "disney", "135790", T0);
        // the same household id and salt, a key of its own, but no invitation: what hearing the network gives
        HouseholdTvs.Tv outsider = new HouseholdTvs.Tv();
        HouseholdStore.Invitation real = tvs[0].store.invite("Office", T0);
        outsider.store.join(new HouseholdStore.Invitation(real.householdId, real.personSalt, real.byTv, real.byKey,
                real.byName, new byte[HouseholdStore.SECRET_BYTES]), "Attic", T0);
        refused(outsider, tvs[0]);
        refused(tvs[0], outsider);
        assertNull(outsider.store.log().get("pin", "Sam", "disney"));
    }

    @Test
    public void somethingThatIsNotAnExchangeIsRefused() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        byte[] junk = new byte[256];
        java.util.Arrays.fill(junk, (byte) 'x');
        try {
            HouseholdSync.run(new java.io.ByteArrayInputStream(junk), new ByteArrayOutputStream(), false, tvs[0].store,
                    "A", T0);
            fail("expected a refusal");
        } catch (HouseholdSync.SyncException expected) {
            // not a household exchange
        }
    }

    @Test
    public void aTvNotInAHouseholdCannotRun() throws Exception {
        HouseholdTvs.Tv none = new HouseholdTvs.Tv();
        try {
            HouseholdSync.run(new java.io.ByteArrayInputStream(new byte[0]), new ByteArrayOutputStream(), true,
                    none.store, "A", T0);
            fail("expected a refusal");
        } catch (HouseholdSync.SyncException expected) {
            // not in a household
        }
    }

    // ---- Removing and leaving ----

    @Test
    public void aRemovedTvIsToldAndNothingMovesEitherWayRound() throws Exception {
        for (boolean removedConnects : new boolean[] {true, false}) {
            HouseholdTvs.Tv[] tvs = pair();
            assertTrue(tvs[0].store.remove(tvs[1].store.tvId(), T0 + 1));
            tvs[0].store.log().put("pin", "Sam", "disney", "135790", T0 + 2);
            HouseholdSync.Result[] results = removedConnects ? exchange(tvs[1], tvs[0], null)
                    : exchange(tvs[0], tvs[1], null);
            HouseholdSync.Result there = results[removedConnects ? 0 : 1];
            HouseholdSync.Result here = results[removedConnects ? 1 : 0];
            assertTrue(there.removedHere);
            assertTrue(here.peerRemoved);
            assertNull(tvs[1].store.log().get("pin", "Sam", "disney"));
        }
    }

    @Test
    public void aRemovalReachesATvThatWasOffAndCantBeUndone() throws Exception {
        HouseholdTvs.Tv a = first();
        HouseholdTvs.Tv b = joining(a, "Kitchen");
        HouseholdTvs.Tv c = joining(a, "Attic");
        exchange(b, a, null);
        exchange(c, a, null);
        exchange(a, b, null);
        // a removes c while b is off; c, not knowing, renames itself later
        a.store.remove(c.store.tvId(), T0 + 10);
        c.store.publishSelf("Attic 2", T0 + 20 + HouseholdMembers.REFRESH_MS);
        exchange(a, b, null);
        assertEquals(HouseholdMembers.Standing.REMOVED, standing(b, c));
        HouseholdSync.Result[] results = exchange(c, b, null);
        assertTrue(results[0].removedHere);
        assertEquals(HouseholdMembers.Standing.REMOVED, standing(b, c));
    }

    @Test
    public void aTvThatLeavesHandsItsRemovalToTheNextTvItMeets() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        tvs[1].store.beginLeaving(T0 + 1);
        HouseholdSync.Result[] results = exchange(tvs[1], tvs[0], null);
        assertFalse(results[0].removedHere);
        assertEquals(HouseholdMembers.Standing.REMOVED, standing(tvs[0], tvs[1]));
        // once it has, the next try is refused as removed
        assertTrue(exchange(tvs[1], tvs[0], null)[0].removedHere);
    }

    // ---- Converting from version 1 ----

    @Test
    public void twoVersion1TvsConvertAndAdmitEachOtherWithTheOldKey() throws Exception {
        byte[] key = new byte[32];
        new java.security.SecureRandom().nextBytes(key);
        HouseholdTvs.Tv a = HouseholdStoreTest.v1Tv(key);
        HouseholdTvs.Tv b = HouseholdStoreTest.v1Tv(key);
        a.reopen();
        b.reopen();
        a.store.publishSelf("Office", T0);
        b.store.publishSelf("Kitchen", T0);
        exchange(a, b, null);
        assertEquals(HouseholdMembers.Standing.MEMBER, standing(a, b));
        assertEquals(HouseholdMembers.Standing.MEMBER, standing(b, a));
        // a TV that never had the key still can't
        HouseholdTvs.Tv other = HouseholdStoreTest.v1Tv(new byte[32]);
        other.reopen();
        refused(other, a);
    }

    @Test
    public void afterTheGracePeriodTheOldKeyAdmitsNoOne() throws Exception {
        byte[] key = new byte[32];
        new java.security.SecureRandom().nextBytes(key);
        HouseholdTvs.Tv a = HouseholdStoreTest.v1Tv(key);
        HouseholdTvs.Tv b = HouseholdStoreTest.v1Tv(key);
        a.reopen();
        b.reopen();
        a.store.v1AdmitKey(T0);
        b.store.v1AdmitKey(T0);
        long late = T0 + HouseholdStore.V1_GRACE_MS + 1;
        try {
            exchange(a.store, b.store, null, late);
            fail("expected a refusal");
        } catch (ExecutionException expected) {
            assertTrue(expected.getCause() instanceof IOException);
        }
    }
}
