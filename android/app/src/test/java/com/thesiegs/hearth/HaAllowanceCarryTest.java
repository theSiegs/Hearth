package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

/** A new day before Home Assistant has answered: a running lock or pause still holds, yesterday's minutes don't. */
public class HaAllowanceCarryTest {
    private static final long NOW = 1_794_380_400_000L; // a morning, UTC

    private static JSONObject entry(String lockUntil, String pauseUntil) throws Exception {
        JSONObject locks = new JSONObject();
        if (lockUntil != null) locks.put("lock", new JSONObject().put("kind", "bedtime").put("until", lockUntil));
        if (pauseUntil != null) locks.put("pause", new JSONObject().put("reason", "Dinner").put("until", pauseUntil));
        return new JSONObject().put("youtube_minutes_left", 0)
                .put("out_of_time", new JSONObject().put("com.example.game", "Games"))
                .put("schedule_locked", lockUntil != null)
                .put(HaAllowance.LOCKS_KEY, locks);
    }

    private static String iso(long ms) {
        return java.time.Instant.ofEpochMilli(ms).toString();
    }

    @Test
    public void aBedtimeRunningPastMidnightStillHolds() throws Exception {
        JSONObject kept = HaAllowance.carriedOver(entry(iso(NOW + 3_600_000), null), NOW);
        assertTrue(kept.getBoolean("schedule_locked"));
        assertEquals("bedtime", kept.getJSONObject(HaAllowance.LOCKS_KEY).getJSONObject("lock").getString("kind"));
        // Yesterday's minutes and groups out of time don't
        assertTrue(kept.isNull("youtube_minutes_left"));
        assertEquals(0, kept.getJSONObject("out_of_time").length());
        HaAllowance.Values values = HaAllowance.valuesOf(kept, null);
        assertTrue(values.scheduleLocked);
        assertNull(values.youtubeMinutesLeft);
    }

    @Test
    public void aPauseStillRunningHoldsButNotOneThatEnded() throws Exception {
        JSONObject kept = HaAllowance.carriedOver(entry(null, iso(NOW + 60_000)), NOW);
        assertFalse(kept.getBoolean("schedule_locked"));
        assertTrue(kept.getJSONObject(HaAllowance.LOCKS_KEY).has("pause"));
        assertNull(HaAllowance.carriedOver(entry(iso(NOW - 1), iso(NOW - 1)), NOW));
        assertNull(HaAllowance.carriedOver(null, NOW));
    }
}
