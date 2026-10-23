package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** Which of a TV's settings are household entries, and what an arriving entry does to them. */
public class HouseholdBridgeTest {
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

    @Test
    public void whatIsSetHereButNotYetInTheLogIsPublished() {
        FakeTv tv = new FakeTv().with("alex", "user:10");
        tv.pairings("user:10").put(ProfilePairing.NETFLIX, PICKER);
        tv.pins("user:10").put(ProfilePairing.DISNEY + "|Alex", "1234");
        tv.pins(null).put(ProfilePairing.PARAMOUNT + "|Everyone", "9999");
        HouseholdLog log = new HouseholdLog("tv-a");
        Map<String, String[]> out = HouseholdBridge.unpublished(tv, log);
        assertEquals(3, out.size());
        assertEquals(PICKER, out.get("pairing|alex|" + ProfilePairing.NETFLIX)[3]);
        assertEquals("1234", out.get("pin|alex|" + ProfilePairing.DISNEY + "|Alex")[3]);
        assertEquals("9999", out.get("pin||" + ProfilePairing.PARAMOUNT + "|Everyone")[3]);
    }

    @Test
    public void whatTheLogHasAlreadyIsNotPublishedAgain_andADeletedOneIsNotBroughtBack() {
        FakeTv tv = new FakeTv().with("alex", "user:10");
        tv.pairings("user:10").put(ProfilePairing.NETFLIX, PICKER);
        tv.pins("user:10").put(ProfilePairing.DISNEY + "|Alex", "1234");
        HouseholdLog log = new HouseholdLog("tv-a");
        log.put("pairing", "alex", ProfilePairing.NETFLIX, PICKER, T0);
        log.put("pin", "alex", ProfilePairing.DISNEY + "|Alex", "1234", T0);
        log.delete("pin", "alex", ProfilePairing.DISNEY + "|Alex", T0 + 1);
        assertTrue(HouseholdBridge.unpublished(tv, log).isEmpty());
    }

    @Test
    public void anArrivingEntryChangesTheMatchingProfileHere() throws Exception {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        log.merge(other.put("pairing", "Alex", ProfilePairing.NETFLIX, HouseholdBridge.pairingValue("profile", "Alex R"), T0), T0);
        log.merge(other.put("pin", "Alex", ProfilePairing.DISNEY + "|Alex R", "2468", T0 + 1), T0);
        assertEquals(2, HouseholdBridge.apply(tv, log));
        assertEquals("Alex R", new org.json.JSONObject(tv.pairings("user:12").get(ProfilePairing.NETFLIX)).optString("appProfile"));
        assertEquals("2468", tv.pins("user:12").get(ProfilePairing.DISNEY + "|Alex R"));
        // applying again changes nothing
        assertEquals(0, HouseholdBridge.apply(tv, log));
    }

    @Test
    public void anEntryForAProfileNotHereWaitsUntilItAppears() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        log.merge(other.put("pin", "Sam", ProfilePairing.DISNEY + "|Sam", "1357", T0), T0);
        assertEquals(0, HouseholdBridge.apply(tv, log));
        assertEquals(1, log.all().size());
        tv.with("sam", "user:14");
        assertEquals(1, HouseholdBridge.apply(tv, log));
        assertEquals("1357", tv.pins("user:14").get(ProfilePairing.DISNEY + "|Sam"));
    }

    @Test
    public void aDeleteRemovesTheSettingHere() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        tv.pins("user:12").put(ProfilePairing.DISNEY + "|Alex", "1234");
        tv.pairings("user:12").put(ProfilePairing.NETFLIX, PICKER);
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        log.merge(other.delete("pin", "alex", ProfilePairing.DISNEY + "|Alex", T0), T0);
        log.merge(other.delete("pairing", "alex", ProfilePairing.NETFLIX, T0 + 1), T0);
        assertEquals(2, HouseholdBridge.apply(tv, log));
        assertNull(tv.pins("user:12").get(ProfilePairing.DISNEY + "|Alex"));
        assertNull(tv.pairings("user:12").get(ProfilePairing.NETFLIX));
    }

    @Test
    public void theWholeTvsPinTravelsWithoutAProfile() {
        FakeTv tv = new FakeTv();
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        log.merge(other.put("pin", "", ProfilePairing.PARAMOUNT + "|Everyone", "5555", T0), T0);
        assertEquals(1, HouseholdBridge.apply(tv, log));
        assertEquals("5555", tv.pins(null).get(ProfilePairing.PARAMOUNT + "|Everyone"));
    }

    @Test
    public void junkFromAnotherTvIsNotApplied() {
        FakeTv tv = new FakeTv().with("alex", "user:12");
        HouseholdLog log = new HouseholdLog("tv-b");
        HouseholdLog other = new HouseholdLog("tv-a");
        log.merge(other.put("pin", "alex", ProfilePairing.DISNEY + "|Alex", "12ab", T0), T0);
        log.merge(other.put("pin", "alex", "nobar", "1234", T0 + 1), T0);
        log.merge(other.put("pin", "alex", ProfilePairing.HULU + "|Alex", "1234567890123", T0 + 2), T0);
        log.merge(other.put("pairing", "alex", ProfilePairing.NETFLIX, "{\"mode\":\"profile\"}", T0 + 3), T0);
        log.merge(other.put("pairing", "alex", ProfilePairing.MAX, "not json", T0 + 4), T0);
        log.merge(other.put("pairing", "alex", ProfilePairing.DISNEY, "{\"mode\":\"whatever\"}", T0 + 5), T0);
        log.merge(other.put("mystery", "alex", "x", "y", T0 + 6), T0);
        assertEquals(0, HouseholdBridge.apply(tv, log));
        assertEquals(0, tv.writes);
    }

    @Test
    public void aPickerChoiceAndAProfileChoiceKeepTheirShape() {
        assertEquals("{\"mode\":\"picker\"}", HouseholdBridge.pairingValue("picker", null));
        assertTrue(HouseholdBridge.validPairing(HouseholdBridge.pairingValue("profile", "Alex")));
        assertTrue(HouseholdBridge.validPairing(HouseholdBridge.pairingValue("picker", null)));
        assertFalse(HouseholdBridge.validPairing(HouseholdBridge.pairingValue("profile", "  ")));
    }
}
