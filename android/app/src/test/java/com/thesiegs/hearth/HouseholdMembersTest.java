package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.Test;

/** The member list: where a TV stands, which TVs the Household page lists, and the households it finds to join. */
public class HouseholdMembersTest {
    private static final long T0 = 1_800_000_000_000L;
    private static final long DAY = 24L * 60 * 60 * 1000;

    private static final byte[] KEY = {1, 2, 3};

    private static String value(String name) {
        return HouseholdMembers.value(name, KEY, "tv-a");
    }

    private static HouseholdLog logWith(String tv, String name, long at) {
        HouseholdLog log = new HouseholdLog(tv);
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, tv, value(name), at);
        return log;
    }

    @Test
    public void listsThisTvFirstThenTheOthersFromTheirEntries() {
        HouseholdLog log = logWith("tv-b", "Kitchen", T0 - 3 * DAY);
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-a", value("Bedroom"), T0);
        List<HouseholdMembers.Member> members = HouseholdMembers.list(log.all(), Collections.emptyMap(),
                Collections.emptyMap(), "tv-a", "Bedroom", T0);
        assertEquals(2, members.size());
        assertTrue(members.get(0).self);
        assertEquals("Bedroom", members.get(0).name);
        assertEquals("Kitchen", members.get(1).name);
        assertFalse(members.get(1).online);
        assertEquals(T0 - 3 * DAY, members.get(1).lastSeen);
    }

    @Test
    public void aTvThatLeftIsNotListed() {
        HouseholdLog log = logWith("tv-b", "Kitchen", T0 - DAY);
        log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-b", T0);
        List<HouseholdMembers.Member> members = HouseholdMembers.list(log.all(), Collections.emptyMap(),
                Collections.emptyMap(), "tv-a", "Bedroom", T0);
        assertEquals(1, members.size());
    }

    @Test
    public void whenThisTvLastSyncedWithAMemberCountsButASyncAloneIsNotMembership() {
        HouseholdLog log = logWith("tv-b", "Kitchen", T0 - 3 * DAY);
        Map<String, HouseholdMembers.Seen> seen = new HashMap<>();
        seen.put("tv-b", new HouseholdMembers.Seen("Kitchen", T0 - DAY));
        seen.put("tv-c", new HouseholdMembers.Seen("Gone", T0 - DAY));
        List<HouseholdMembers.Member> members = HouseholdMembers.list(log.all(), seen, Collections.emptyMap(), "tv-a",
                "Bedroom", T0);
        assertEquals(2, members.size());
        assertEquals(T0 - DAY, members.get(1).lastSeen);
    }

    @Test
    public void whereATvStands() {
        String id = HouseholdIdentity.tvIdOf(KEY);
        HouseholdLog log = new HouseholdLog("tv-a");
        assertEquals(HouseholdMembers.Standing.UNKNOWN, HouseholdMembers.standing(log, id));
        // an entry that gives the id another key doesn't count
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, id, HouseholdMembers.value("Kitchen", new byte[] {9}, "tv-a"), T0);
        assertEquals(HouseholdMembers.Standing.UNKNOWN, HouseholdMembers.standing(log, id));
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, id, value("Kitchen"), T0 + 1);
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(log, id));
        assertArrayEquals(KEY, HouseholdMembers.keyFor(log, id));
        log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, id, T0 + 2);
        assertEquals(HouseholdMembers.Standing.REMOVED, HouseholdMembers.standing(log, id));
        assertNull(HouseholdMembers.keyFor(log, id));
    }

    @Test
    public void aTvOnlyHeardOnTheNetworkIsNotAMember() {
        // The household's id isn't secret: hearing it proves nothing, only a sealed exchange or an entry does
        Map<String, String> online = new HashMap<>();
        online.put("tv-x", "Stranger");
        List<HouseholdMembers.Member> members = HouseholdMembers.list(Collections.emptyList(), Collections.emptyMap(),
                online, "tv-a", "Bedroom", T0);
        assertEquals(1, members.size());
    }

    @Test
    public void theTvsOnNowComeBeforeTheOthers() {
        HouseholdLog log = logWith("tv-b", "Attic", T0 - DAY);
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-c", value("Kitchen"), T0 - DAY);
        Map<String, String> online = new HashMap<>();
        online.put("tv-c", "Kitchen");
        List<HouseholdMembers.Member> members = HouseholdMembers.list(log.all(), Collections.emptyMap(), online, "tv-a",
                "Bedroom", T0);
        assertEquals("Kitchen", members.get(1).name);
        assertEquals("Attic", members.get(2).name);
    }

    @Test
    public void thisTvsEntryIsWrittenWhenMissingRenamedOrADayOld() {
        HouseholdLog log = new HouseholdLog("tv-a");
        assertTrue(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", KEY, T0));
        // one from before signing is written again at once, saying this TV signs
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-a", value("Bedroom"), T0);
        assertTrue(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", KEY, T0 + 60_000));
        log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-a",
                HouseholdMembers.value("Bedroom", KEY, "tv-a", true), T0);
        assertFalse(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", KEY, T0 + 60_000));
        assertTrue(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Guest room", KEY, T0 + 60_000));
        assertTrue(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", new byte[] {4}, T0 + 60_000));
        assertTrue(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", KEY, T0 + DAY));
        // a TV that is removed (or leaving) doesn't write itself back
        log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, "tv-a", T0 + DAY);
        assertFalse(HouseholdMembers.selfNeedsWrite(log, "tv-a", "Bedroom", KEY, T0 + 2 * DAY));
    }

    @Test
    public void nearbyGroupsByHouseholdAndLeavesOutThisTvsOwn() {
        List<HouseholdNet.Heard> heard = Arrays.asList(
                new HouseholdNet.Heard("tv-b", "h1", "Kitchen"),
                new HouseholdNet.Heard("tv-c", "h1", null),
                new HouseholdNet.Heard("tv-d", "h2", "Office"),
                new HouseholdNet.Heard("tv-e", "mine", "Attic"));
        List<List<String>> nearby = HouseholdMembers.nearby(heard, "mine");
        assertEquals(2, nearby.size());
        assertEquals(Arrays.asList("Kitchen", null), nearby.get(0));
        assertEquals(Collections.singletonList("Office"), nearby.get(1));
    }
}
