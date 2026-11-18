package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.json.JSONObject;
import org.junit.Test;

/**
 * Seams review probes (2026-11-17): the state document as Home Assistant builds it against what the TV makes of it.
 * Each asserts the behaviour a family would expect, and fails on the code as reviewed.
 */
public class SeamsDocumentTest {
    private static final String TUBE = CompanionApps.HEARTHTUBE;

    private static JSONObject document(String profiles) throws Exception {
        return new JSONObject("{\"profiles\": " + profiles + ", \"version\": \"abc\"}");
    }

    /**
     * Daily time is used up and an adult allows YouTube (hearth.allow with the group, or "+15 min YouTube bonus"):
     * Home Assistant leaves the YouTube group out and lists its apps in Daily time's "except" (household.py
     * _person_document). Every other excepted app opens on the TV; HearthTube must too.
     */
    @Test
    public void anAllowedHearthTubeIsNotHeldByDailyTime() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"all\", \"name\": \"Daily time\", \"minutes_left\": 0, \"apps\": [],"
                + " \"except\": [\"" + TUBE + "\", \"com.google.android.youtube.tv\"]}]}}"));
        HaAllowance.Values values = HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L);
        // The hold of apps opened from the home honours the exception...
        assertNull(values.timeUpGroup("com.google.android.youtube.tv"));
        // ...but HearthTube is handed Daily time's 0 minutes all the same
        assertNull("HearthTube is in Daily time's exceptions, yet it gets Daily time's minutes (0)",
                values.youtubeMinutesLeft);
    }

    /** The same with time left: 5 minutes of Daily time must not cap a YouTube bonus that runs past it. */
    @Test
    public void dailyTimeLeftDoesNotCapAnExceptedHearthTube() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"all\", \"name\": \"Daily time\", \"minutes_left\": 5, \"apps\": [],"
                + " \"except\": [\"" + TUBE + "\"]}]}}"));
        assertEquals(null, HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).youtubeMinutesLeft);
    }
}
