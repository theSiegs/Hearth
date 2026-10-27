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
    public void allScreenTimeHoldsHearthTubeSMinutesToo() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"all\", \"minutes_left\": 15, \"apps\": []},"
                + "{\"id\": \"youtube\", \"minutes_left\": 25, \"apps\": [\"com.thesiegs.hearthtube\"]}]}}"));
        assertEquals(Integer.valueOf(15), HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).youtubeMinutesLeft);
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

    @Test
    public void aGroupWithNoTimeLeftHoldsItsApps() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"name\": \"Games\", \"minutes_left\": 0, \"apps\": [\"com.example.game\"]},"
                + "{\"id\": \"streaming\", \"name\": \"Streaming\", \"minutes_left\": 30, \"apps\": [\"com.example.tv\"]}]}}"));
        HaAllowance.Values values = HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L);
        assertEquals("Games", values.timeUpGroup("com.example.game"));
        assertNull(values.timeUpGroup("com.example.tv"));
        assertNull(values.timeUpGroup("com.example.other"));
        assertNull(values.allOutOfTime);
    }

    @Test
    public void hearthTubeSettingsAndGoogleTvAreNeverHeld() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"youtube\", \"name\": \"YouTube\", \"minutes_left\": 0, \"apps\": [\"com.thesiegs.hearthtube\","
                + " \"com.google.android.youtube.tv\", \"com.android.tv.settings\", \"com.google.android.apps.tv.launcherx\"]}]}}"));
        HaAllowance.Values values = HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L);
        assertEquals("YouTube", values.timeUpGroup("com.google.android.youtube.tv"));
        assertNull(values.timeUpGroup("com.thesiegs.hearthtube"));
        assertNull(values.timeUpGroup("com.android.tv.settings"));
        assertNull(values.timeUpGroup("com.google.android.apps.tv.launcherx"));
        // HearthTube holds YouTube time itself
        assertEquals(Integer.valueOf(0), values.youtubeMinutesLeft);
    }

    @Test
    public void allScreenTimeUsedUpHoldsEveryApp() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"all\", \"name\": \"All screen time\", \"minutes_left\": 0, \"apps\": []}]},"
                + " \"user:11\": {\"groups\": [{\"id\": \"all\", \"minutes_left\": 10, \"apps\": []}]}}"));
        HaAllowance.Values values = HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L);
        assertEquals("All screen time", values.timeUpGroup("com.example.anything"));
        assertNull(values.timeUpGroup("com.thesiegs.hearth"));
        assertNull(HaAllowance.valuesOf(profiles.optJSONObject("user:11"), 1L).timeUpGroup("com.example.anything"));
    }

    @Test
    public void noLimitOrNoEntryHoldsNothing() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"minutes_left\": null, \"apps\": [\"com.example.game\"]}]}}"));
        assertNull(HaAllowance.valuesOf(profiles.optJSONObject("user:10"), 1L).timeUpGroup("com.example.game"));
        assertNull(HaAllowance.valuesOf(null, 1L).timeUpGroup("com.example.game"));
        // What an older Hearth stored, without the held apps
        assertNull(HaAllowance.valuesOf(new JSONObject("{\"youtube_minutes_left\": 5}"), 1L)
                .timeUpGroup("com.example.game"));
    }

    @Test
    public void heldAppsSurviveBeingStored() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(document("{\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"name\": \"Games\", \"minutes_left\": 0, \"apps\": [\"com.example.game\"]}]}}"));
        JSONObject stored = new JSONObject(profiles.toString());
        assertEquals("Games", HaAllowance.valuesOf(stored.optJSONObject("user:10"), 1L).timeUpGroup("com.example.game"));
    }
}
