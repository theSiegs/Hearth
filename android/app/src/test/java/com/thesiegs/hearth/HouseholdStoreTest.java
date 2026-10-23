package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

import org.junit.Test;

/** What a TV keeps of its household: the key and the entries survive a restart, and a lost Keystore key is said, not hidden. */
public class HouseholdStoreTest {
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

    @Test
    public void aNewTvHasAnIdAndIsInNoHousehold() {
        MapBacking backing = new MapBacking();
        HouseholdStore store = HouseholdStore.open(backing, memoryKeys());
        assertTrue(store.tvId().startsWith("tv-"));
        assertFalse(store.joined());
        assertFalse(store.lost());
        assertNull(store.householdId());
        assertTrue(store.enabled());
        // the id stays the same after a restart
        assertEquals(store.tvId(), HouseholdStore.open(backing, memoryKeys()).tvId());
    }

    @Test
    public void startingAHouseholdMakesAKeyThatSurvivesARestart() {
        MapBacking backing = new MapBacking();
        SecretBox.Keys keys = memoryKeys();
        HouseholdStore store = HouseholdStore.open(backing, keys);
        assertTrue(store.create());
        assertFalse(store.create());
        String id = store.householdId();
        assertNotNull(id);
        byte[] key = store.exportKey();
        HouseholdStore again = HouseholdStore.open(backing, keys);
        assertTrue(again.joined());
        assertEquals(id, again.householdId());
        assertArrayEquals(key, again.exportKey());
    }

    @Test
    public void theKeyIsNotInThePreferencesInTheClear() {
        MapBacking backing = new MapBacking();
        HouseholdStore store = HouseholdStore.open(backing, memoryKeys());
        store.create();
        byte[] key = store.exportKey();
        String hex = new java.math.BigInteger(1, key).toString(16);
        for (String value : backing.map.values()) {
            assertFalse(value.contains(hex));
            assertFalse(value.contains(java.util.Base64.getEncoder().encodeToString(key)));
        }
    }

    @Test
    public void entriesSurviveARestartAndAreNotInTheClear() {
        MapBacking backing = new MapBacking();
        SecretBox.Keys keys = memoryKeys();
        HouseholdStore store = HouseholdStore.open(backing, keys);
        store.create();
        store.log().put("pin", "Sam", "disney", "135790", T0);
        store.log().delete("pin", "Sam", "hulu", T0 + 1);
        assertTrue(store.save());
        for (String value : backing.map.values()) assertFalse(value.contains("135790"));
        HouseholdStore again = HouseholdStore.open(backing, keys);
        assertEquals("135790", again.log().get("pin", "Sam", "disney").value);
        assertNull(again.log().get("pin", "Sam", "hulu"));
        assertEquals(2, again.log().all().size());
        assertEquals(2L, again.log().vector().get(store.tvId()).longValue());
        // a write after the restart gets a new sequence and still beats the old one
        HouseholdEntry next = again.log().put("pin", "Sam", "disney", "2468", T0 + 2);
        assertEquals(3, next.seq);
        assertEquals("2468", again.log().get("pin", "Sam", "disney").value);
    }

    @Test
    public void joiningTakesAnotherTvsKeyAndEmptiesTheLog() {
        HouseholdStore first = HouseholdStore.open(new MapBacking(), memoryKeys());
        first.create();
        HouseholdStore second = HouseholdStore.open(new MapBacking(), memoryKeys());
        second.create();
        second.log().put("look", "Alex", "theme", "dark", T0);
        assertNotEquals(first.householdId(), second.householdId());
        assertTrue(second.join(first.exportKey()));
        assertEquals(first.householdId(), second.householdId());
        assertEquals(0, second.log().all().size());
        assertFalse(second.join(new byte[5]));
        assertFalse(second.join(null));
    }

    @Test
    public void leavingForgetsTheKeyAndTheEntries() {
        MapBacking backing = new MapBacking();
        SecretBox.Keys keys = memoryKeys();
        HouseholdStore store = HouseholdStore.open(backing, keys);
        store.create();
        store.log().put("look", "Alex", "theme", "dark", T0);
        store.save();
        store.leave();
        assertFalse(store.joined());
        assertNull(store.exportKey());
        HouseholdStore again = HouseholdStore.open(backing, keys);
        assertFalse(again.joined());
        assertFalse(again.lost());
    }

    @Test
    public void aKeystoreKeyThatIsGoneMakesTheTvLostNotQuietlyNew() {
        MapBacking backing = new MapBacking();
        HouseholdStore store = HouseholdStore.open(backing, memoryKeys());
        store.create();
        // the same preferences with other Keystore keys: what a restored disk or cleared Keystore looks like
        HouseholdStore after = HouseholdStore.open(backing, memoryKeys());
        assertFalse(after.joined());
        assertTrue(after.lost());
        assertNull(after.householdId());
        // joining again clears the lost state
        HouseholdStore other = HouseholdStore.open(new MapBacking(), memoryKeys());
        other.create();
        assertTrue(after.join(other.exportKey()));
        assertTrue(after.joined());
        assertFalse(after.lost());
    }

    @Test
    public void anUnreadableLogStartsEmptyButKeepsTheHousehold() {
        MapBacking backing = new MapBacking();
        SecretBox.Keys keys = memoryKeys();
        HouseholdStore store = HouseholdStore.open(backing, keys);
        store.create();
        store.log().put("look", "Alex", "theme", "dark", T0);
        store.save();
        backing.put("log_sealed", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        HouseholdStore again = HouseholdStore.open(backing, keys);
        assertTrue(again.joined());
        assertEquals(0, again.log().all().size());
    }

    @Test
    public void theSwitchIsOnUntilTurnedOffAndSurvivesARestart() {
        MapBacking backing = new MapBacking();
        HouseholdStore store = HouseholdStore.open(backing, memoryKeys());
        assertTrue(store.enabled());
        store.setEnabled(false);
        assertFalse(HouseholdStore.open(backing, memoryKeys()).enabled());
        store.setEnabled(true);
        assertTrue(HouseholdStore.open(backing, memoryKeys()).enabled());
    }
}
