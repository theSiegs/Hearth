package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import java.util.Map;

import org.json.JSONObject;
import org.junit.Test;

/**
 * Seams review probes (2026-11-17): the stale countdown (Home Assistant quiet for 10 minutes) and HearthTube. Each
 * asserts the behaviour a family would expect, and fails on the code as reviewed.
 */
public class SeamsStaleCountdownTest {
    private static final String TUBE = CompanionApps.HEARTHTUBE;

    /** Home Assistant's last word: YouTube 20 min left, daily time 30 min left; HearthTube had 10 min in front. */
    private static JSONObject entry() throws Exception {
        return new JSONObject("{\"youtube_minutes_left\": 20, \"out_of_time\": {}, \"groups\": ["
                + "{\"id\": \"youtube\", \"name\": \"YouTube\", \"minutes_left\": 20, \"apps\": [\"" + TUBE + "\"]},"
                + "{\"id\": \"all\", \"name\": \"Daily time\", \"minutes_left\": 30, \"apps\": []}],"
                + " \"front_ms_at\": {\"" + TUBE + "\": 600000}}");
    }

    @Test
    public void hearthTubeTimeCountsAgainstDailyTime() throws Exception {
        // 31 more minutes of HearthTube since the word: daily time (30 left) is used up, so the game is held
        JSONObject out = HaAllowance.staleCountdown(entry(), Map.of(TUBE, 600000L + 31 * 60000L));
        assertEquals("Daily time", HaAllowance.valuesOf(out, null).timeUpGroup("com.example.game", 0));
    }

    @Test
    public void youTubeIsOutWhenDailyTimeRunsOutInOtherApps() throws Exception {
        // 31 minutes of a game since the word: daily time (30 left) is used up. HearthTube holds itself by
        // youtube_minutes_left (it only takes off what it played itself), so that must say 0 now
        JSONObject out = HaAllowance.staleCountdown(entry(), Map.of(TUBE, 600000L, "com.example.game", 31 * 60000L));
        assertEquals("Daily time", HaAllowance.valuesOf(out, null).timeUpGroup("com.example.game", 0));
        assertEquals(Integer.valueOf(0), HaAllowance.valuesOf(out, null).youtubeMinutesLeft);
    }
}
