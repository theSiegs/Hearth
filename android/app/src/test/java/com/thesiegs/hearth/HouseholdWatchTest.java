package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

/** Continue Watching across the household: what goes out, what's taken, and what's finished everywhere. */
public class HouseholdWatchTest {
    private static final long HOUR = 60 * 60_000L;
    private static final long NOW = 1_800_000_000_000L;
    private static final String NETFLIX = "com.netflix.ninja";

    private static WatchHistory.Entry played(String title, String subtitle, long duration, long position, long lastAt,
            boolean shared) {
        return new WatchHistory.Entry(1, WatchHistory.PLAYED, "user:0:alex", NETFLIX,
                WatchHistory.playedItem(title, subtitle), title, subtitle, duration, position, lastAt, null, 0, shared);
    }

    private static WatchHistory.Entry kept(String title, String row, long lastAt) {
        return new WatchHistory.Entry(2, WatchHistory.KEPT, "user:0:alex", NETFLIX, "id:81", title, null, 0, 0, lastAt,
                row, 0, false);
    }

    /** What another TV wrote for a title (its log is the household's). */
    private static HouseholdEntry fromOtherTv(WatchHistory.Entry e) {
        HouseholdLog other = new HouseholdLog("tv-b");
        return other.put(HouseholdBridge.WATCH, "p:alex", HouseholdWatch.itemOf(e.kind, e.packageName, e.item),
                HouseholdWatch.valueOf(e), NOW);
    }

    @Test
    public void aPlayedTitleGoesOutAndComesBackTheSame() {
        WatchHistory.Entry e = played("Dark", "S1:E4", 50 * 60_000, 20 * 60_000, NOW - HOUR, false);
        HouseholdWatch.Card card = HouseholdWatch.cardOf(fromOtherTv(e));
        assertNotNull(card);
        assertEquals(WatchHistory.PLAYED, card.kind);
        assertEquals(NETFLIX, card.packageName);
        assertEquals(e.item, card.item);
        assertEquals("Dark", card.title);
        assertEquals("S1:E4", card.subtitle);
        assertEquals(20 * 60_000, card.position);
        assertEquals(NOW - HOUR, card.lastAt);
        assertNull(card.row);
    }

    @Test
    public void aKeptEntryCarriesItsDeepLink_butOnlyIntoItsOwnApp() {
        String row = "{\"packageName\":\"" + NETFLIX + "\",\"title\":\"Dark\",\"intentUri\":\"intent://watch/81#Intent;end\"}";
        HouseholdWatch.Card card = HouseholdWatch.cardOf(fromOtherTv(kept("Dark", row, NOW - HOUR)));
        assertNotNull(card);
        assertEquals(row, card.row);
        // A row filed under another app would open that app: not taken
        String elsewhere = "{\"packageName\":\"com.example.other\",\"title\":\"Dark\"}";
        assertNull(HouseholdWatch.cardOf(fromOtherTv(kept("Dark", elsewhere, NOW - HOUR))));
    }

    @Test
    public void itemsSplitBackIntoKindAppAndTitle_andRefuseOddOnes() {
        assertArrayEquals(new String[]{"played", NETFLIX, "dark|s1e4"},
                HouseholdWatch.partsOf("played|" + NETFLIX + "|dark|s1e4"));
        assertNull(HouseholdWatch.partsOf("other|" + NETFLIX + "|dark"));
        assertNull(HouseholdWatch.partsOf("played|not a package|dark"));
        assertNull(HouseholdWatch.partsOf("played|" + NETFLIX + "|"));
        assertNull(HouseholdWatch.partsOf(null));
    }

    @Test
    public void theNewerPlayWins_andOldOrFutureOnesArentTaken() {
        HouseholdWatch.Card card = HouseholdWatch.cardOf(
                fromOtherTv(played("Dark", "S1:E4", 50 * 60_000, 20 * 60_000, NOW - HOUR, false)));
        assertTrue(HouseholdWatch.takes(null, card, NOW));
        assertTrue(HouseholdWatch.takes(played("Dark", "S1:E4", 0, 0, NOW - 2 * HOUR, false), card, NOW));
        assertFalse(HouseholdWatch.takes(played("Dark", "S1:E4", 0, 0, NOW - HOUR, false), card, NOW));
        assertFalse(HouseholdWatch.takes(played("Dark", "S1:E4", 0, 0, NOW, false), card, NOW));
        HouseholdWatch.Card old = HouseholdWatch.cardOf(fromOtherTv(
                played("Dark", "S1:E1", 1, 1, NOW - WatchHistory.MAX_AGE_MS - HOUR, false)));
        assertFalse(HouseholdWatch.takes(null, old, NOW));
        HouseholdWatch.Card ahead = HouseholdWatch.cardOf(fromOtherTv(played("Dark", "S1:E2", 1, 1, NOW + 3 * 24 * HOUR, false)));
        assertFalse(HouseholdWatch.takes(null, ahead, NOW));
    }

    @Test
    public void onlyThisTvsOwnRecentTitlesGoOut_atMostSoMany() {
        List<WatchHistory.Entry> own = new ArrayList<>();
        for (int i = 0; i < HouseholdWatch.SENT_PER_PERSON + 10; i++) {
            own.add(played("Show " + i, null, 1, 1, NOW - i * HOUR, false));
        }
        own.add(1, played("From the household", null, 1, 1, NOW, true));
        own.add(played("Long ago", null, 1, 1, NOW - WatchHistory.MAX_AGE_MS - HOUR, false));
        List<WatchHistory.Entry> sent = HouseholdWatch.toSend(own, NOW);
        assertEquals(HouseholdWatch.SENT_PER_PERSON, sent.size());
        for (WatchHistory.Entry e : sent) {
            assertFalse(e.shared);
            assertFalse("Long ago".equals(e.title));
        }
        // A kept entry without its row has nothing to open on another TV
        assertTrue(HouseholdWatch.toSend(Collections.singletonList(kept("Dark", null, NOW)), NOW).isEmpty());
    }

    @Test
    public void aTitleGoesOutWhenItChanged_butNeverOverANewerOneOrARemoval() {
        WatchHistory.Entry e = played("Dark", "S1:E4", 50 * 60_000, 20 * 60_000, NOW - HOUR, false);
        HouseholdLog log = new HouseholdLog("tv-a");
        String item = HouseholdWatch.itemOf(e.kind, e.packageName, e.item);
        assertTrue(HouseholdWatch.sends(e, null));
        HouseholdEntry same = log.put(HouseholdBridge.WATCH, "p:alex", item, HouseholdWatch.valueOf(e), NOW);
        assertFalse(HouseholdWatch.sends(e, same));
        WatchHistory.Entry further = played("Dark", "S1:E4", 50 * 60_000, 30 * 60_000, NOW, false);
        assertTrue(HouseholdWatch.sends(further, same));
        // Another TV played it later: this TV's older play doesn't replace it
        HouseholdEntry newer = log.put(HouseholdBridge.WATCH, "p:alex", item, HouseholdWatch.valueOf(further), NOW);
        assertFalse(HouseholdWatch.sends(e, newer));
        // Taken out of Continue Watching on another TV: only a play since brings it back
        HouseholdEntry removed = new HouseholdLog("tv-b").delete(HouseholdBridge.WATCH, "p:alex", item, NOW - HOUR / 2);
        assertFalse(HouseholdWatch.sends(e, removed));
        assertTrue(HouseholdWatch.sends(further, removed));
    }

    @Test
    public void finishedAnywhere_aContinueCardForItGoes() {
        List<WatchHistory.Entry> played = Arrays.asList(
                played("Dark", "S1:E4", 50 * 60_000, 49 * 60_000, NOW - HOUR, true),
                played("Ozark", "S2:E1", 50 * 60_000, 10 * 60_000, NOW - HOUR, false));
        assertTrue(WatchHistory.finishedSince(played, "user:0:alex", NETFLIX, "Dark", NOW - 2 * HOUR));
        // Not finished; another profile's; a card newer than the finish
        assertFalse(WatchHistory.finishedSince(played, "user:0:alex", NETFLIX, "Ozark", NOW - 2 * HOUR));
        assertFalse(WatchHistory.finishedSince(played, "user:0:sam", NETFLIX, "Dark", NOW - 2 * HOUR));
        assertFalse(WatchHistory.finishedSince(played, "user:0:alex", NETFLIX, "Dark", NOW));
        assertFalse(WatchHistory.finishedSince(played, null, NETFLIX, "Dark", NOW - 2 * HOUR));
    }

    @Test
    public void oldContinueWatchingEntriesLeaveTheLog_otherKindsStay() {
        HouseholdLog log = new HouseholdLog("tv-a");
        long then = NOW - WatchHistory.MAX_AGE_MS - HOUR;
        log.put(HouseholdBridge.WATCH, "p:alex", "played|" + NETFLIX + "|dark|", "{}", then);
        log.put(HouseholdBridge.PAIRING, "p:alex", NETFLIX, "{\"mode\":\"picker\"}", then);
        log.put(HouseholdBridge.WATCH, "p:alex", "played|" + NETFLIX + "|ozark|", "{}", NOW);
        assertEquals(1, log.purge(NOW));
        assertNull(log.entry(HouseholdBridge.WATCH, "p:alex", "played|" + NETFLIX + "|dark|"));
        assertNotNull(log.get(HouseholdBridge.PAIRING, "p:alex", NETFLIX));
        assertNotNull(log.get(HouseholdBridge.WATCH, "p:alex", "played|" + NETFLIX + "|ozark|"));
    }
}
