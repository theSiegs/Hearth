package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.json.JSONObject;
import org.junit.Test;

/**
 * A kids profile's Continue Watching across the household (its own Android user, its agent's rows all its own), and
 * the posters that go with kept cards.
 */
public class KidsWatchTest {
    private static final long HOUR = 60 * 60_000L;
    private static final long NOW = 1_800_000_000_000L;
    private static final String KID = "user:11";
    private static final String OTHER_KID = "user:12";
    private static final String ADULT = "user:0:alex";
    private static final String DISNEY = "com.disney.disneyplus";
    private static final String HASH = "ab".repeat(32);

    private static String row(String title, String internalId) {
        return "{\"packageName\":\"" + DISNEY + "\",\"title\":\"" + title + "\",\"internalId\":\"" + internalId
                + "\",\"watchNextType\":0,\"lastEngagementTime\":" + (NOW - HOUR)
                + ",\"intentUri\":\"intent://play/" + internalId + "#Intent;end\",\"posterArtUri\":\"content://x/1\"}";
    }

    private static WatchHistory.Entry kept(long id, String profile, String title, String internalId, long lastAt,
            boolean shared, long goneAt) {
        return new WatchHistory.Entry(id, WatchHistory.KEPT, profile, DISNEY, "id:" + internalId, title, null, 0, 0,
                lastAt, row(title, internalId), goneAt, shared);
    }

    private static Map<String, Object> listedRow(String title, String internalId) {
        Map<String, Object> row = new HashMap<>();
        row.put("id", 11_000_000_001L);
        row.put("packageName", DISNEY);
        row.put("title", title);
        row.put("internalId", internalId);
        row.put("watchNextType", 0);
        row.put("lastEngagementTime", NOW - HOUR);
        row.put("profileOwned", true);
        row.put("watchedBy", KID);
        return row;
    }

    @Test
    public void aKidsCardFromAnotherTvShowsInTheirRow_withTheirListedOnes() {
        List<WatchHistory.Entry> mine = Arrays.asList(
                kept(5, KID, "Bluey", "b1", NOW - 2 * HOUR, true, NOW),
                // On this TV's list too: shown once, from the list
                kept(6, KID, "Moana", "m1", NOW - 2 * HOUR, true, NOW));
        List<Map<String, Object>> cards = WatchHistory.kidsCards(mine,
                new ArrayList<>(Collections.singletonList(listedRow("Moana", "m1"))), KID, pkg -> true, NOW);
        assertEquals(2, cards.size());
        Map<String, Object> bluey = cards.get(1);
        assertEquals("Bluey", bluey.get("title"));
        assertEquals(-5L, bluey.get("id"));
        assertEquals(KID, bluey.get("watchedBy"));
        assertEquals(Boolean.TRUE, bluey.get("profileOwned"));
        assertEquals("intent://play/b1#Intent;end", bluey.get("intentUri"));
    }

    @Test
    public void aKidsRowNeverHasAnyoneElsesCards() {
        List<WatchHistory.Entry> mixed = Arrays.asList(
                kept(5, OTHER_KID, "Bluey", "b1", NOW - HOUR, true, NOW),
                kept(6, ADULT, "Dark", "d1", NOW - HOUR, true, NOW));
        assertTrue(WatchHistory.kidsCards(mixed, new ArrayList<>(), KID, pkg -> true, NOW).isEmpty());
    }

    @Test
    public void anAdultsRowNeverHasAKidsCards_andIgnoresWhatARowFromAnotherTvClaims() {
        WatchHistory.Entry kids = kept(5, KID, "Bluey", "b1", NOW - HOUR, true, NOW);
        WatchHistory.Entry adults = new WatchHistory.Entry(6, WatchHistory.KEPT, ADULT, DISNEY, "id:d1", "Dark", null,
                0, 0, NOW - HOUR, "{\"packageName\":\"" + DISNEY + "\",\"title\":\"Dark\",\"profileOwned\":true}", NOW,
                true);
        List<Map<String, Object>> cards = WatchHistory.keptCards(Arrays.asList(kids, adults), 0, pkg -> true);
        assertEquals(1, cards.size());
        assertEquals("Dark", cards.get(0).get("title"));
        assertEquals(ADULT, cards.get(0).get("watchedBy"));
        // profileOwned would show it to whoever is on: it's the adult's only
        assertNull(cards.get(0).get("profileOwned"));
    }

    @Test
    public void aKidsCardIsShownOnlyInAnAppTheyHave() {
        List<WatchHistory.Entry> mine = Collections.singletonList(kept(5, KID, "Bluey", "b1", NOW - HOUR, true, NOW));
        assertTrue(WatchHistory.kidsCards(mine, new ArrayList<>(), KID, pkg -> false, NOW).isEmpty());
    }

    @Test
    public void whatTheKidsListDropsIsLetGo_butNotWhatCameFromAnotherTv() {
        WatchHistory.Entry ownGone = kept(1, KID, "Bluey", "b1", NOW - HOUR, false, 0);
        WatchHistory.Entry ownListed = kept(2, KID, "Moana", "m1", NOW - HOUR, false, 0);
        WatchHistory.Entry fromOtherTv = kept(3, KID, "Encanto", "e1", NOW - HOUR, true, NOW);
        WatchHistory.Entry old = kept(4, KID, "Frozen", "f1", NOW - 100 * 24 * HOUR, true, NOW);
        List<WatchHistory.Entry> dropped = WatchHistory.kidsDropped(Arrays.asList(ownGone, ownListed, fromOtherTv, old),
                Collections.singletonList(listedRow("Moana", "m1")), NOW);
        assertEquals(Arrays.asList(ownGone, old), dropped);
    }

    @Test
    public void aKeptRowAsKeptCarriesNoOwnerMarks() {
        Map<String, Object> kept = WatchHistory.withoutOwner(listedRow("Moana", "m1"));
        assertFalse(kept.containsKey("watchedBy"));
        assertFalse(kept.containsKey("profileOwned"));
    }

    // --- posters ---

    @Test
    public void aKeptCardNamesItsPoster_andTheOtherTvShowsThatPicture() throws Exception {
        WatchHistory.Entry e = kept(5, KID, "Bluey", "b1", NOW - HOUR, false, 0);
        String value = HouseholdWatch.valueOf(e, HASH);
        HouseholdEntry entry = new HouseholdLog("tv-b").put(HouseholdBridge.WATCH, "p:kid",
                HouseholdWatch.itemOf(e.kind, e.packageName, e.item), value, NOW);
        assertEquals(HASH, HouseholdWatch.posterOf(entry));
        HouseholdWatch.Card card = HouseholdWatch.cardOf(entry);
        assertNotNull(card);
        assertEquals(HASH, card.poster);
        String shown = new JSONObject(card.shownRow()).getString("posterArtUri");
        assertEquals("hearth-poster:" + HASH, shown);
        assertEquals(HASH, HouseholdWatch.posterHashOf(shown));
        // The rest of the row (its deep link) is as it was
        assertEquals("intent://play/b1#Intent;end", new JSONObject(card.shownRow()).getString("intentUri"));
    }

    @Test
    public void aPosterNameThatIsntAHashIsIgnored() {
        WatchHistory.Entry e = kept(5, KID, "Bluey", "b1", NOW - HOUR, false, 0);
        assertFalse(HouseholdWatch.valueOf(e, "../../etc").contains("\"ph\""));
        assertNull(HouseholdWatch.posterHashOf("hearth-poster:../x"));
        assertNull(HouseholdWatch.posterHashOf("content://x/1"));
        // No poster: the row is shown as it came
        HouseholdEntry entry = new HouseholdLog("tv-b").put(HouseholdBridge.WATCH, "p:kid",
                HouseholdWatch.itemOf(e.kind, e.packageName, e.item), HouseholdWatch.valueOf(e), NOW);
        HouseholdWatch.Card card = HouseholdWatch.cardOf(entry);
        assertNull(card.poster);
        assertEquals(card.row, card.shownRow());
    }

    @Test
    public void postersAreAskedForAfterWallpapers_andGoWhenNoCardNamesThem() throws Exception {
        HouseholdLog log = new HouseholdLog("tv-a");
        String wallpaper = "cd".repeat(32);
        WatchHistory.Entry e = kept(5, KID, "Bluey", "b1", NOW - HOUR, false, 0);
        String item = HouseholdWatch.itemOf(e.kind, e.packageName, e.item);
        log.put(HouseholdBridge.WATCH, "p:kid", item, HouseholdWatch.valueOf(e, HASH), NOW);
        log.put(HouseholdBridge.WALLPAPER, "p:kid", "any", "{\"hash\":\"" + wallpaper + "\"}", NOW);
        List<String> named = new ArrayList<>(HouseholdBridge.pictures(log));
        assertEquals(Arrays.asList(wallpaper, HASH), named);

        File dir = Files.createTempDirectory("pictures").toFile();
        HouseholdPictures pictures = new HouseholdPictures(dir);
        byte[] jpeg = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 1, 2, 3};
        String poster = pictures.write(jpeg, null);
        assertNotNull(poster);
        Set<String> keep = new HashSet<>(HouseholdBridge.pictures(log));
        pictures.keepOnly(keep);
        // Not named by any entry: gone
        assertFalse(pictures.has(poster));

        log.put(HouseholdBridge.WATCH, "p:kid", item, HouseholdWatch.valueOf(e, poster), NOW + 1);
        pictures.write(jpeg, null);
        pictures.keepOnly(new HashSet<>(HouseholdBridge.pictures(log)));
        assertTrue(pictures.has(poster));
        // Taken out of Continue Watching: its poster goes too
        log.delete(HouseholdBridge.WATCH, "p:kid", item, NOW + 2);
        pictures.keepOnly(new HashSet<>(HouseholdBridge.pictures(log)));
        assertFalse(pictures.has(poster));
    }
}
