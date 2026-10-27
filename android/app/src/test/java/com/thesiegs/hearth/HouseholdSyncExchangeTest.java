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
        return exchange(a, null, b, null, wire, now);
    }

    /** Runs one exchange with each side's wallpaper pictures ({@code null}: a side keeps none). */
    static HouseholdSync.Result[] exchange(HouseholdStore a, HouseholdPictures aPictures, HouseholdStore b,
            HouseholdPictures bPictures, Wire wire, long now) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try (ServerSocket server = new ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
            server.setSoTimeout(5000);
            Future<HouseholdSync.Result> accepting = pool.submit(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    // As a TV does: the opening off the household thread, the rest on it
                    HouseholdSync.Accepted opened = HouseholdSync.accept(socket.getInputStream(),
                            socket.getOutputStream(), b.tvId(), b.householdId());
                    return HouseholdSync.run(opened, b, bPictures, "B", now);
                }
            });
            Future<HouseholdSync.Result> connecting = pool.submit(() -> {
                try (Socket socket = new Socket(java.net.InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                    socket.setSoTimeout(5000);
                    InputStream in = socket.getInputStream();
                    OutputStream out = socket.getOutputStream();
                    if (wire != null) {
                        return HouseholdSync.run(tapped(in, wire), tapped(out, wire), true, a, aPictures, "A", now);
                    }
                    return HouseholdSync.run(in, out, true, a, aPictures, "A", now);
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
    public void aTvRemovedHereCantTellThisOneItWasRemoved() throws Exception {
        // a removes b; b (removed, or a device that kept b's key) says a is removed when a connects to it
        HouseholdTvs.Tv[] tvs = pair();
        assertTrue(tvs[0].store.remove(tvs[1].store.tvId(), T0 + 1));
        assertTrue(tvs[1].store.remove(tvs[0].store.tvId(), T0 + 2));
        HouseholdSync.Result[] results = exchange(tvs[0], tvs[1], null);
        // a keeps its household: b is the removed one, and it is told
        assertFalse(results[0].removedHere);
        assertTrue(results[0].peerRemoved);
        assertTrue(results[1].peerRemoved);
        assertTrue(tvs[0].store.joined());
    }

    @Test
    public void aBigExchangeGoesInBatchesThatLoseNothing() {
        HouseholdLog from = new HouseholdLog("tv-a");
        // entries of three TVs, as a TV holds them after syncing with the others
        for (String tv : new String[] {"tv-b", "tv-c"}) {
            HouseholdLog other = new HouseholdLog(tv);
            for (int i = 0; i < 40; i++) from.merge(other.put("look", "Alex", tv + i, "v" + i, T0 + i), T0 + 100);
        }
        for (int i = 0; i < 40; i++) from.put("look", "Sam", "a" + i, "v" + i, T0 + i);
        HouseholdLog to = new HouseholdLog("tv-d");
        for (int round = 0; round < 20; round++) {
            for (HouseholdEntry e : HouseholdSync.batch(from.missingFrom(to.vector()), 25)) to.merge(e, T0 + 100);
        }
        assertEquals(from.all().size(), to.all().size());
        assertTrue(from.missingFrom(to.vector()).isEmpty());
    }

    @Test
    public void aStrangerCantMakeATvReadABigFrameBeforeItProvesItself() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        // A well-formed opening from a TV no one listed, then a frame far bigger than any proof
        ByteArrayOutputStream hello = new ByteArrayOutputStream();
        java.io.DataOutputStream data = new java.io.DataOutputStream(hello);
        data.write(new byte[] {'H', 'H', 'S', '2'});
        data.writeUTF("tv-0123456789abcdef");
        data.write(ShareCrypto.encodePoint(ShareCrypto.newKeyPair().getPublic()));
        data.write(new byte[16]);
        data.writeInt(4 * 1024 * 1024);
        try {
            HouseholdSync.run(new java.io.ByteArrayInputStream(hello.toByteArray()), new ByteArrayOutputStream(),
                    false, tvs[0].store, "A", T0);
            fail("expected a refusal");
        } catch (HouseholdSync.SyncException expected) {
            // refused at its size, before reading it
            assertEquals("Bad frame size", expected.getMessage());
        }
    }

    @Test
    public void theOpeningReadOffTheHouseholdThreadTouchesNoEntriesAndAStrangerGoesNoFurther() throws Exception {
        HouseholdTvs.Tv[] tvs = pair();
        // A stranger's whole opening, proving a key of its own, for this household (its id isn't secret) and with a
        // made-up invitation: what anyone on the network can send
        HouseholdTvs.Tv stranger = new HouseholdTvs.Tv();
        HouseholdStore.Invitation real = tvs[0].store.invite("Office", T0);
        stranger.store.join(new HouseholdStore.Invitation(real.householdId, real.personSalt, real.byTv, real.byKey,
                real.byName, new byte[HouseholdStore.SECRET_BYTES]), "Attic", T0);
        java.io.PipedInputStream toUs = new java.io.PipedInputStream(64 * 1024);
        java.io.PipedOutputStream strangerOut = new java.io.PipedOutputStream(toUs);
        java.io.PipedInputStream toStranger = new java.io.PipedInputStream(64 * 1024);
        java.io.PipedOutputStream ourOut = new java.io.PipedOutputStream(toStranger);
        ExecutorService pool = Executors.newSingleThreadExecutor();
        try {
            pool.submit(() -> HouseholdSync.run(toStranger, strangerOut, true, stranger.store, "X", T0));
            int entries = tvs[0].store.log().all().size();
            HouseholdSync.Accepted opened = HouseholdSync.accept(toUs, ourOut, tvs[0].store.tvId(),
                    tvs[0].store.householdId());
            assertEquals(stranger.store.tvId(), opened.peer());
            assertEquals(entries, tvs[0].store.log().all().size());
            // on the household thread it isn't listed and proves no invitation: refused before anything more is read
            try {
                HouseholdSync.run(opened, tvs[0].store, null, "A", T0);
                fail("expected a refusal");
            } catch (HouseholdSync.SyncException expected) {
                assertEquals("The other TV is not in this household", expected.getMessage());
            }
            // and an opening made for this TV doesn't go on for another (it left, or joined another household since)
            HouseholdTvs.Tv other = first();
            try {
                HouseholdSync.run(opened, other.store, null, "A", T0);
                fail("expected a refusal");
            } catch (HouseholdSync.SyncException expected) {
                assertEquals("Not in a household", expected.getMessage());
            }
        } finally {
            pool.shutdownNow();
        }
        assertEquals(HouseholdMembers.Standing.UNKNOWN,
                HouseholdMembers.standing(tvs[0].store.log(), stranger.store.tvId()));
    }

    @Test
    public void entriesForgedInAnotherTvsNameCantStallItsRealOnes() throws Exception {
        HouseholdTvs.Tv a = first();
        HouseholdTvs.Tv b = joining(a, "Kitchen");
        HouseholdTvs.Tv c = joining(a, "Attic");
        exchange(b, a, null);
        exchange(c, a, null);
        exchange(a, b, null);
        // b hands a an entry in c's name with a sequence far past anything c wrote: a would never ask c's real
        // entries of it again
        HouseholdEntry forged = new HouseholdEntry("look", "alex", "", "{\"forged\":1}", (T0 + 50) << 16,
                c.store.tvId(), 1_000_000_000L, false);
        assertTrue(b.store.log().merge(forged, T0 + 50));
        exchange(b, a, null);
        assertEquals("{\"forged\":1}", a.store.log().get("look", "alex", "").value);
        c.store.log().put("pairing", "sam", "netflix", "Sam", T0 + 60);
        // c, met directly, says how many it wrote: a drops what it never made and takes everything of c's again
        HouseholdSync.Result[] results = exchange(c, a, null);
        assertNull(a.store.log().get("look", "alex", ""));
        assertTrue(results[1].applied.stream().noneMatch(e -> e.value.contains("forged")));
        exchange(c, a, null);
        assertEquals("Sam", a.store.log().get("pairing", "sam", "netflix").value);
        assertTrue(a.store.log().vector().get(c.store.tvId()) < 1_000_000_000L);
        // a TV that took the forged entry too (here b itself) is put right the same way when it meets c
        exchange(c, b, null);
        exchange(c, b, null);
        assertEquals("Sam", b.store.log().get("pairing", "sam", "netflix").value);
    }

    @Test
    public void aTvMetDirectlyIsBelievedAboutItsOwnCountOnly() {
        HouseholdLog log = new HouseholdLog("tv-a");
        HouseholdLog c = new HouseholdLog("tv-c");
        for (int i = 0; i < 3; i++) log.merge(c.put("look", "alex", "i" + i, "v", T0 + i), T0 + 10);
        // nothing wrong: nothing changes
        assertEquals(-1, log.vouch("tv-c", 3));
        assertEquals(-1, log.vouch("tv-c", 5));
        assertEquals(3, log.all().size());
        // this TV's own count is never another TV's to correct
        log.put("look", "sam", "", "v", T0);
        assertEquals(-1, log.vouch("tv-a", 0));
        // a removal in its name is kept, whatever its sequence
        HouseholdEntry removal = new HouseholdEntry(HouseholdMembers.KIND, "", "tv-x", "", T0 << 16, "tv-c", 99,
                true);
        log.merge(removal, T0 + 10);
        assertEquals(0, log.vouch("tv-c", 3));
        assertTrue(log.isRemoved(HouseholdMembers.KIND, "", "tv-x"));
        assertEquals(Long.valueOf(0), log.vector().get("tv-c"));
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
