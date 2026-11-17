package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import java.util.Map;

import org.json.JSONObject;
import org.junit.Test;

/** Home Assistant quiet (the router unplugged): the TV counts its last word's minutes down itself. */
public class HaStaleCountdownTest {
    private static JSONObject entry() throws Exception {
        return new JSONObject("{\"out_of_time\": {}, \"groups\": ["
                + "{\"id\": \"games\", \"name\": \"Games\", \"minutes_left\": 20, \"apps\": [\"com.example.game\"]},"
                + "{\"id\": \"all\", \"name\": \"Daily time\", \"minutes_left\": 30, \"apps\": [],"
                + " \"except\": [\"com.example.reader\"]}],"
                + " \"front_ms_at\": {\"com.example.game\": 600000}}");
    }

    @Test
    public void aGroupRunsOutOnItsOwnCount() throws Exception {
        // 21 more minutes of the game since Home Assistant's word: Games (20 left) is out, daily time (30) isn't
        JSONObject out = HaAllowance.staleCountdown(entry(), Map.of("com.example.game", 600000L + 21 * 60000L));
        assertEquals("Games", out.getJSONObject("out_of_time").getString("com.example.game"));
        assertFalse(out.has("all_out_of_time"));
        HaAllowance.Values values = HaAllowance.valuesOf(out, null);
        assertEquals("Games", values.timeUpGroup("com.example.game", 0));
    }

    @Test
    public void dailyTimeRunsOutAcrossApps() throws Exception {
        JSONObject out = HaAllowance.staleCountdown(entry(),
                Map.of("com.example.game", 600000L + 10 * 60000L, "com.example.tv", 21 * 60000L));
        assertEquals("Daily time", out.getString("all_out_of_time"));
        HaAllowance.Values values = HaAllowance.valuesOf(out, null);
        assertEquals("Daily time", values.timeUpGroup("com.example.tv", 0));
        // Its exceptions stay open
        assertEquals(null, values.timeUpGroup("com.example.reader", 0));
    }

    @Test
    public void lessUseOrNoSnapshotChangesNothing() throws Exception {
        JSONObject out = HaAllowance.staleCountdown(entry(), Map.of("com.example.game", 600000L + 5 * 60000L));
        assertEquals(0, out.getJSONObject("out_of_time").length());
        assertFalse(out.has("all_out_of_time"));
        JSONObject bare = new JSONObject("{\"groups\": []}");
        assertSame(bare, HaAllowance.staleCountdown(bare, Map.of("com.example.game", 1L)));
        assertTrue(HaAllowance.staleCountdown(null, Map.of()) == null);
    }
}
