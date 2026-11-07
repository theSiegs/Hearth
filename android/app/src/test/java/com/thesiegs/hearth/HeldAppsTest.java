package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import org.json.JSONObject;
import org.junit.Test;

/** Which apps Hearth's home shows out of time for a kids profile. */
public class HeldAppsTest {
    private static final List<String> APPS = Arrays.asList(
            "com.example.game", "com.example.tv", "com.thesiegs.hearth", "com.android.tv.settings", CompanionApps.HEARTHTUBE);
    private static final long NOW = 1_000_000L;

    @Test
    public void aGroupOutOfTimeHoldsItsAppsOnly() throws Exception {
        JSONObject entry = new JSONObject("{\"out_of_time\": {\"com.example.game\": \"Games\"}}");
        Map<String, String> held = Allowance.heldApps(APPS, entry, null, "YouTube", NOW);
        assertEquals(Map.of("com.example.game", "Games"), held);
    }

    @Test
    public void aPauseOrALockHoldsEverythingButHearthsOwn() throws Exception {
        JSONObject paused = new JSONObject("{\"locks\": {\"pause\": {\"reason\": \"Dinner\"}}}");
        Map<String, String> held = Allowance.heldApps(APPS, paused, null, "YouTube", NOW);
        assertEquals(Map.of("com.example.game", "", "com.example.tv", "", CompanionApps.HEARTHTUBE, ""), held);
        JSONObject locked = new JSONObject("{\"locks\": {\"lock\": {\"kind\": \"bedtime\"}}}");
        assertEquals(held, Allowance.heldApps(APPS, locked, null, "YouTube", NOW));
        // A lock that has ended holds nothing
        JSONObject over = new JSONObject("{\"locks\": {\"lock\": {\"kind\": \"bedtime\", \"until\": \"1970-01-01T00:00:01Z\"}}}");
        assertTrue(Allowance.heldApps(APPS, over, null, "YouTube", NOW).isEmpty());
    }

    @Test
    public void hearthTubeIsOutWhenItsYouTubeMinutesAre() {
        // Hearth's own limit, without Home Assistant
        assertEquals(Map.of(CompanionApps.HEARTHTUBE, "YouTube"), Allowance.heldApps(APPS, null, 0, "YouTube", NOW));
        assertTrue(Allowance.heldApps(APPS, null, 5, "YouTube", NOW).isEmpty());
        assertTrue(Allowance.heldApps(APPS, null, null, "YouTube", NOW).isEmpty());
    }
}
