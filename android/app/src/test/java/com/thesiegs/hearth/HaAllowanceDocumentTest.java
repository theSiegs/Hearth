package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

/** The Hearth integration's answer (its state document) as the allowance HearthTube enforces. */
public class HaAllowanceDocumentTest {
    private static JSONObject document(String profiles) throws Exception {
        return new JSONObject("{\"profiles\": " + profiles + ", \"version\": \"abc\"}");
    }

    @Test
    public void theFewestMinutesLeftInAGroupHoldingHearthTube() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"video\", \"minutes_left\": 40, \"apps\": [\"com.thesiegs.hearthtube\", \"com.example.tv\"]},"
                + "{\"id\": \"youtube\", \"minutes_left\": 25, \"apps\": [\"com.thesiegs.hearthtube\"]},"
                + "{\"id\": \"games\", \"minutes_left\": 5, \"apps\": [\"com.example.game\"]}]}}"));
        HaAllowance.Values values = HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L);
        assertEquals(Integer.valueOf(25), values.youtubeMinutesLeft);
        assertFalse(values.scheduleLocked);
    }

    @Test
    public void noGroupWithHearthTubeIsNoLimit() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"minutes_left\": 0, \"apps\": [\"com.example.game\"]}]}, \"user:11\": {\"groups\": []}}"));
        assertNull(HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).youtubeMinutesLeft);
        assertNull(HaAllowance.valuesOf(profiles.optJSONObject("user:11"), 1L).youtubeMinutesLeft);
        assertTrue(profiles.has("user:11"));
    }

    @Test
    public void usedUpIsZeroNeverLess() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"youtube\", \"minutes_left\": -3, \"apps\": [\"com.thesiegs.hearthtube\"]}]}}"));
        assertEquals(Integer.valueOf(0), HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).youtubeMinutesLeft);
    }

    @Test
    public void aPhoneSDocumentOrNothingIsNoAllowance() throws Exception {
        assertNull(HaAllowance.profilesFromDocument(new JSONObject("{\"person\": {\"groups\": []}}")));
        assertNull(HaAllowance.profilesFromDocument(null));
    }

    @Test
    public void lockedIsTheScheduleLock() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": [], \"locked\": true},"
                + " \"user:11\": {\"groups\": []}}"));
        assertTrue(HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).scheduleLocked);
        assertFalse(HaAllowance.valuesOf(profiles.optJSONObject("user:11"), 1L).scheduleLocked);
    }
}
