package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** What joining would change in a TV's pairings and PINs, and the copy that puts them back. */
public class HouseholdJoinReviewTest {
    private static final long T0 = 1_800_000_000_000L;
    private static final String PICKER = "{\"mode\":\"picker\"}";

    /** A TV's own settings in maps. */
    private static final class FakeTv implements HouseholdBridge.Local {
        final Map<String, String> profiles = new HashMap<>();
        final Map<String, Map<String, String>> pairings = new HashMap<>();
        final Map<String, Map<String, String>> pins = new HashMap<>();
        int writes;

        FakeTv with(String name, String key) {
            profiles.put(name, key);
            return this;
        }

        @Override
        public Map<String, String> profiles() {
            return profiles;
        }

        @Override
        public Map<String, String> pairings(String key) {
            return pairings.computeIfAbsent(key, k -> new HashMap<>());
        }

        @Override
        public void setPairing(String key, String pkg, String value) {
            writes++;
            if (value == null) pairings(key).remove(pkg);
            else pairings(key).put(pkg, value);
        }

        @Override
        public Map<String, String> pins(String key) {
            return pins.computeIfAbsent(key == null ? "<tv>" : key, k -> new HashMap<>());
        }

        @Override
        public void setPin(String key, String item, String digits) {
            writes++;
            if (digits == null) pins(key).remove(item);
            else pins(key).put(item, digits);
        }
    }

    private static HouseholdLog householdWith(java.util.function.Consumer<HouseholdLog> entries) {
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        entries.accept(other);
        for (HouseholdEntry e : other.all()) log.merge(e, T0);
        return log;
    }

    @Test
    public void onlyWhatWouldChangeIsCounted_perProfileAndForTheWholeTv() {
        FakeTv tv = new FakeTv().with("alex", "user:12").with("sam", "user:14");
        tv.pairings("user:12").put(ProfilePairing.NETFLIX, PICKER);
        tv.pins("user:12").put(ProfilePairing.DISNEY + "|Alex", "1234");
        HouseholdLog log = householdWith(other -> {
            // the same as here: no change
            other.put("pairing", "alex", ProfilePairing.NETFLIX, PICKER, T0);
            // a different PIN, and a new one: two changes
            other.put("pin", "alex", ProfilePairing.DISNEY + "|Alex", "2468", T0);
            other.put("pin", "alex", ProfilePairing.HULU + "|Alex", "1111", T0);
            // a profile this TV doesn't have: nothing here changes
            other.put("pin", "riley", ProfilePairing.HULU + "|Riley", "2222", T0);
            // a removal of what Sam doesn't have: no change
            other.delete("pairing", "sam", ProfilePairing.NETFLIX, T0);
            other.put("pin", "", ProfilePairing.PARAMOUNT + "|Everyone", "5555", T0);
        });
        Map<String, int[]> changes = HouseholdJoinReview.changes(tv, log);
        assertArrayEquals(new int[] {0, 2}, changes.get("user:12"));
        assertNull(changes.get("user:14"));
        assertArrayEquals(new int[] {0, 1}, changes.get(HouseholdJoinReview.TV));
        // Counting changes nothing
        assertEquals(0, tv.writes);
    }

    @Test
    public void aRemovalOfSomethingHereIsAChange_andJunkIsnt() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        tv.pairings("user:12").put(ProfilePairing.NETFLIX, PICKER);
        HouseholdLog log = householdWith(other -> {
            other.delete("pairing", "alex", ProfilePairing.NETFLIX, T0);
            other.put("pin", "alex", ProfilePairing.HULU + "|Alex", "12ab", T0);
        });
        assertArrayEquals(new int[] {1, 0}, HouseholdJoinReview.changes(tv, log).get("user:12"));
    }

    @Test
    public void theCopyPutsBackWhatTheTvHad_andLeavesWhatTheHouseholdAdded() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        tv.pairings("user:12").put(ProfilePairing.NETFLIX, PICKER);
        tv.pins("user:12").put(ProfilePairing.DISNEY + "|Alex", "1234");
        tv.pins(null).put(ProfilePairing.PARAMOUNT + "|Everyone", "5555");
        String copy = HouseholdJoinReview.snapshot(tv);

        // The household's go in
        tv.pairings("user:12").put(ProfilePairing.NETFLIX, HouseholdBridge.pairingValue("profile", "Alex R"));
        tv.pins("user:12").put(ProfilePairing.DISNEY + "|Alex", "2468");
        tv.pins("user:12").put(ProfilePairing.HULU + "|Alex", "1111");
        tv.pins(null).remove(ProfilePairing.PARAMOUNT + "|Everyone");
        tv.writes = 0;

        assertEquals(3, HouseholdJoinReview.restore(tv, copy));
        assertEquals(PICKER, tv.pairings("user:12").get(ProfilePairing.NETFLIX));
        assertEquals("1234", tv.pins("user:12").get(ProfilePairing.DISNEY + "|Alex"));
        assertEquals("5555", tv.pins(null).get(ProfilePairing.PARAMOUNT + "|Everyone"));
        // Taking this away would take it from every TV
        assertEquals("1111", tv.pins("user:12").get(ProfilePairing.HULU + "|Alex"));
        // Putting back again changes nothing
        assertEquals(0, HouseholdJoinReview.restore(tv, copy));
    }

    @Test
    public void aCopyThatDoesntReadPutsNothingBack() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        assertEquals(-1, HouseholdJoinReview.restore(tv, "not json"));
        assertEquals(0, tv.writes);
        String empty = HouseholdJoinReview.snapshot(new FakeTv());
        assertTrue(empty.contains("pins"));
        assertFalse(empty.contains("user:"));
        assertEquals(0, HouseholdJoinReview.restore(tv, empty));
    }
}
