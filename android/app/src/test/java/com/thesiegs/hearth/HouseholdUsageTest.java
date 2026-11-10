package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import java.util.List;
import java.util.Map;

/** A kid's minutes on the household's other TVs, summed for Hearth's own rules. */
public class HouseholdUsageTest {
    private static final String DAY = "2026-11-11";

    @Test
    public void sumsTheOtherTvsMinutesForToday() {
        HouseholdLog den = new HouseholdLog("den");
        HouseholdLog loft = new HouseholdLog("loft");
        HouseholdLog here = new HouseholdLog("here");
        long now = 1_000_000L;
        List<HouseholdEntry> entries = List.of(
                den.put(HouseholdBridge.USAGE, "p:sam", HouseholdUsage.item("den", DAY),
                        HouseholdUsage.valueOf(Map.of("com.example.game", 600_000L)), now),
                loft.put(HouseholdBridge.USAGE, "p:sam", HouseholdUsage.item("loft", DAY),
                        HouseholdUsage.valueOf(Map.of("com.example.game", 300_000L, "com.example.video", 60_000L)), now),
                // This TV's own and yesterday's don't count
                here.put(HouseholdBridge.USAGE, "p:sam", HouseholdUsage.item("here", DAY),
                        HouseholdUsage.valueOf(Map.of("com.example.game", 999_000L)), now),
                den.put(HouseholdBridge.USAGE, "p:sam", HouseholdUsage.item("den", "2026-11-10"),
                        HouseholdUsage.valueOf(Map.of("com.example.game", 999_000L)), now),
                // Someone this TV has no profile for
                den.put(HouseholdBridge.USAGE, "p:alex", HouseholdUsage.item("den", DAY),
                        HouseholdUsage.valueOf(Map.of("com.example.game", 1L)), now));

        Map<String, Map<String, Long>> others = HouseholdUsage.others(entries, "here", DAY, Map.of("p:sam", "user:10"));
        assertEquals(900_000L, (long) others.get("user:10").get("com.example.game"));
        assertEquals(60_000L, (long) others.get("user:10").get("com.example.video"));
        assertFalse(others.containsKey("p:alex"));
        assertNull(others.get("user:0"));
    }

    @Test
    public void anUnchangedCountReadsTheSame() {
        assertEquals(HouseholdUsage.valueOf(Map.of("b", 2L, "a", 1L)), HouseholdUsage.valueOf(Map.of("a", 1L, "b", 2L)));
    }
}
