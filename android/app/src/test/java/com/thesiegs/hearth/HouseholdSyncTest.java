package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** The household's entries: who wins, what a delete does, what a TV lacks, and what a stranger can't read. */
public class HouseholdSyncTest {
    private static final long DAY = 24L * 60 * 60 * 1000;
    private static final long T0 = 1_800_000_000_000L;

    private static void sync(HouseholdLog from, HouseholdLog to, long now) {
        for (HouseholdEntry entry : from.missingFrom(to.vector())) to.merge(entry, now);
    }

    @Test
    public void theNewestWriteWinsOnEveryTv() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        a.put("pairing", "Alex", "netflix", "Alex", T0);
        sync(a, b, T0);
        b.put("pairing", "Alex", "netflix", "Alex R", T0 + 1000);
        sync(b, a, T0 + 1000);
        sync(a, b, T0 + 1000);
        assertEquals("Alex R", a.get("pairing", "Alex", "netflix").value);
        assertEquals("Alex R", b.get("pairing", "Alex", "netflix").value);
    }

    @Test
    public void profileNamesMatchWithoutCaseOrSpaces() {
        HouseholdLog a = new HouseholdLog("tv-a");
        a.put("pairing", "  Alex ", "netflix", "x", T0);
        assertNotNull(a.get("pairing", "alex", "netflix"));
        assertNotNull(a.get("pairing", "ALEX", "netflix"));
    }

    @Test
    public void aDeleteStaysDeletedOnATvThatWasOffAndComesBack() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        a.put("pin", "Sam", "disney", "sealed", T0);
        sync(a, b, T0);
        // b goes off; a deletes the PIN
        a.delete("pin", "Sam", "disney", T0 + DAY);
        // b still has the old value; when they meet, the delete wins both ways
        sync(a, b, T0 + 2 * DAY);
        sync(b, a, T0 + 2 * DAY);
        assertNull(a.get("pin", "Sam", "disney"));
        assertNull(b.get("pin", "Sam", "disney"));
    }

    @Test
    public void aWriteAfterADeleteBringsTheValueBack() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        a.put("pin", "Sam", "disney", "one", T0);
        sync(a, b, T0);
        b.delete("pin", "Sam", "disney", T0 + 1000);
        sync(b, a, T0 + 1000);
        a.put("pin", "Sam", "disney", "two", T0 + 2000);
        sync(a, b, T0 + 2000);
        assertEquals("two", b.get("pin", "Sam", "disney").value);
    }

    @Test
    public void aTieGoesToTheLowerTvIdOnBothTvs() {
        HouseholdEntry fromA = new HouseholdEntry("look", "Alex", "theme", "dark", 500, "tv-a", 1, false);
        HouseholdEntry fromB = new HouseholdEntry("look", "Alex", "theme", "light", 500, "tv-b", 1, false);
        HouseholdLog c = new HouseholdLog("tv-c");
        HouseholdLog d = new HouseholdLog("tv-d");
        c.merge(fromA, T0);
        c.merge(fromB, T0);
        d.merge(fromB, T0);
        d.merge(fromA, T0);
        assertEquals("dark", c.get("look", "Alex", "theme").value);
        assertEquals("dark", d.get("look", "Alex", "theme").value);
    }

    @Test
    public void aSecondWriteInTheSameMillisecondStillWins() {
        HouseholdLog a = new HouseholdLog("tv-a");
        a.put("look", "Alex", "theme", "dark", T0);
        a.put("look", "Alex", "theme", "light", T0);
        assertEquals("light", a.get("look", "Alex", "theme").value);
    }

    @Test
    public void aTvAsksOnlyForWhatItLacks() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        a.put("look", "Alex", "one", "1", T0);
        a.put("look", "Alex", "two", "2", T0 + 1);
        sync(a, b, T0 + 1);
        assertTrue(a.missingFrom(b.vector()).isEmpty());
        a.put("look", "Alex", "three", "3", T0 + 2);
        assertEquals(1, a.missingFrom(b.vector()).size());
        assertEquals(3, a.missingFrom(Collections.<String, Long>emptyMap()).size());
    }

    @Test
    public void mergingTheSameEntryTwiceChangesNothingTheSecondTime() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        HouseholdEntry entry = a.put("look", "Alex", "theme", "dark", T0);
        assertTrue(b.merge(entry, T0));
        assertFalse(b.merge(entry, T0));
    }

    @Test
    public void aClockFarInTheFutureIsRefused() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdEntry future = new HouseholdEntry("look", "Alex", "theme", "dark",
                (T0 + 30 * DAY) << 16, "tv-b", 1, false);
        assertFalse(a.merge(future, T0));
        assertNull(a.get("look", "Alex", "theme"));
        assertTrue(a.vector().isEmpty());
    }

    @Test
    public void anEntryClaimingToBeFromThisTvWithASequenceItNeverMadeIsRefused() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdEntry forged = new HouseholdEntry("look", "Alex", "theme", "dark", T0 << 16, "tv-a", 40, false);
        assertFalse(a.merge(forged, T0));
        assertNull(a.get("look", "Alex", "theme"));
    }

    @Test
    public void oldDeletesAreForgottenAfterNinetyDaysAndLiveValuesNever() {
        HouseholdLog a = new HouseholdLog("tv-a");
        a.put("pin", "Sam", "disney", "x", T0);
        a.put("pin", "Sam", "hulu", "y", T0);
        a.delete("pin", "Sam", "hulu", T0 + 1000);
        assertEquals(0, a.purge(T0 + 80 * DAY));
        assertEquals(1, a.purge(T0 + 100 * DAY));
        assertEquals(1, a.all().size());
        assertNotNull(a.get("pin", "Sam", "disney"));
    }

    @Test
    public void anEntryRoundTripsThroughJsonAndBadJsonIsNull() {
        HouseholdEntry entry = new HouseholdEntry("look", "Alex", "theme", "{\"a\":1}", 77, "tv-a", 3, true);
        HouseholdEntry back = HouseholdEntry.fromJson(entry.toJson());
        assertEquals(entry.id(), back.id());
        assertEquals("{\"a\":1}", back.value);
        assertEquals(77, back.clock);
        assertEquals(3, back.seq);
        assertTrue(back.deleted);
        assertNull(HouseholdEntry.fromJson("not json"));
        assertNull(HouseholdEntry.fromJson("{\"k\":\"\",\"p\":\"a\",\"i\":\"b\",\"v\":\"\",\"c\":1,\"t\":\"x\",\"s\":1,\"d\":false}"));
        assertNull(HouseholdEntry.fromJson("{\"k\":\"look\"}"));
    }

    @Test
    public void aSealedEntryOpensOnlyWithTheHouseholdKey() throws Exception {
        HouseholdSeal ours = new HouseholdSeal(HouseholdSeal.newKey());
        HouseholdSeal stranger = new HouseholdSeal(HouseholdSeal.newKey());
        HouseholdEntry entry = new HouseholdEntry("pin", "Sam", "disney", "secret", T0, "tv-a", 1, false);
        byte[] blob = ours.seal(entry);
        assertEquals("secret", ours.open(blob).value);
        assertNull(stranger.open(blob));
        assertFalse(new String(blob, java.nio.charset.StandardCharsets.ISO_8859_1).contains("secret"));
    }

    @Test
    public void aTamperedOrTruncatedBlobDoesNotOpen() throws Exception {
        HouseholdSeal seal = new HouseholdSeal(HouseholdSeal.newKey());
        byte[] blob = seal.seal(new HouseholdEntry("look", "Alex", "theme", "dark", T0, "tv-a", 1, false));
        byte[] flipped = blob.clone();
        flipped[flipped.length - 1] ^= 1;
        assertNull(seal.open(flipped));
        byte[] flippedNonce = blob.clone();
        flippedNonce[0] ^= 1;
        assertNull(seal.open(flippedNonce));
        assertNull(seal.open(Arrays.copyOf(blob, blob.length - 1)));
        assertNull(seal.open(new byte[3]));
        assertNull(seal.open(null));
    }

    @Test
    public void sealingTheSameEntryTwiceGivesDifferentBytes() throws Exception {
        HouseholdSeal seal = new HouseholdSeal(HouseholdSeal.newKey());
        HouseholdEntry entry = new HouseholdEntry("look", "Alex", "theme", "dark", T0, "tv-a", 1, false);
        assertFalse(Arrays.equals(seal.seal(entry), seal.seal(entry)));
    }

    @Test
    public void theHouseholdIdIsStableAndDoesNotShowTheKey() throws Exception {
        byte[] key = HouseholdSeal.newKey();
        String id = new HouseholdSeal(key).id();
        assertEquals(id, new HouseholdSeal(key).id());
        assertEquals(16, id.length());
        assertNotEquals(id, new HouseholdSeal(HouseholdSeal.newKey()).id());
    }

    @Test
    public void aWrongSizedKeyIsRefused() {
        try {
            new HouseholdSeal(new byte[5]);
            org.junit.Assert.fail("expected a refusal");
        } catch (IllegalArgumentException | java.security.GeneralSecurityException expected) {
            // refused
        }
    }

    @Test
    public void threeTvsThatMeetInAnyOrderEndUpTheSame() {
        Map<String, HouseholdLog> tvs = new HashMap<>();
        for (String id : new String[] {"tv-a", "tv-b", "tv-c"}) tvs.put(id, new HouseholdLog(id));
        tvs.get("tv-a").put("pairing", "Alex", "netflix", "A1", T0);
        tvs.get("tv-b").put("pairing", "Alex", "netflix", "B1", T0 + 10);
        tvs.get("tv-c").put("look", "Sam", "theme", "dark", T0 + 5);
        tvs.get("tv-c").delete("look", "Sam", "theme", T0 + 20);
        String[][] meetings = {{"tv-a", "tv-b"}, {"tv-c", "tv-a"}, {"tv-b", "tv-c"}, {"tv-a", "tv-b"}};
        for (String[] m : meetings) {
            sync(tvs.get(m[0]), tvs.get(m[1]), T0 + 30);
            sync(tvs.get(m[1]), tvs.get(m[0]), T0 + 30);
        }
        for (HouseholdLog log : tvs.values()) {
            assertEquals("B1", log.get("pairing", "Alex", "netflix").value);
            assertNull(log.get("look", "Sam", "theme"));
        }
    }
}
