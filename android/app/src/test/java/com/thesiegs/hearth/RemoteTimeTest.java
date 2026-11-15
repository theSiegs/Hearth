package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** The remote API's minutes and locks from a profile's allowance entry (docs/tv-remote-api.md V2.3). */
public class RemoteTimeTest {
    private static final long NOW = 1_794_336_012_400L;
    private static final String YOUTUBE = RemoteSessionV2Test.YOUTUBE;

    private static JSONObject entry(JSONObject person) throws Exception {
        return RemoteSessionV2Test.entry(person);
    }

    private static JSONObject person(int youtubeLeft, int allLeft) throws Exception {
        return RemoteSessionV2Test.document(youtubeLeft, allLeft, null, null);
    }

    @Test
    public void theGroupWithFewerMinutesBindsAndATieGoesToTheAppsOwn() throws Exception {
        JSONObject time = RemoteTime.front(entry(person(30, 12)), YOUTUBE, NOW);
        assertEquals(12, time.getInt("minutesLeft"));
        assertEquals("all", time.getJSONObject("group").getString("id"));
        assertEquals("All screen time", time.getJSONObject("group").getString("name"));
        time = RemoteTime.front(entry(person(12, 12)), YOUTUBE, NOW);
        assertEquals("youtube", time.getJSONObject("group").getString("id"));
        // An app in no group: All; an app All leaves out, and no group of its own: no limit
        assertEquals("all", RemoteTime.front(entry(person(5, 50)), "com.example.video", NOW)
                .getJSONObject("group").getString("id"));
        time = RemoteTime.front(entry(person(5, 50)), "com.android.dialer", NOW);
        assertTrue(time.isNull("minutesLeft"));
        assertTrue(time.isNull("group"));
        assertEquals("2099-01-01T20:30:00-07:00", time.getString("until")); // the next bedtime still shows
    }

    @Test
    public void noEntryOrNothingToSayIsNull() throws Exception {
        assertNull(RemoteTime.front(null, YOUTUBE, NOW));
        JSONObject bare = entry(new JSONObject().put("groups", new JSONArray()));
        assertNull(RemoteTime.front(bare, YOUTUBE, NOW));
    }

    @Test
    public void locksSayWhyAndUntilWhen() throws Exception {
        JSONObject out = RemoteTime.front(entry(person(0, 40)), YOUTUBE, NOW);
        assertTrue(out.getBoolean("locked"));
        assertEquals("time_up", out.getString("why"));
        assertTrue(out.isNull("until"));

        JSONObject paused = person(20, 40).put("pause", new JSONObject().put("until", "2099-01-01T19:00:00-07:00"));
        out = RemoteTime.front(entry(paused), YOUTUBE, NOW);
        assertEquals("paused", out.getString("why"));
        assertEquals("2099-01-01T19:00:00-07:00", out.getString("until"));

        JSONObject school = RemoteSessionV2Test.document(20, 40, new JSONObject().put("kind", "school_time")
                .put("until", "2099-01-01T15:00:00-07:00"), null);
        out = RemoteTime.front(entry(school), YOUTUBE, NOW);
        assertEquals("school", out.getString("why"));
        assertTrue(out.getBoolean("locked"));

        // A lock that has ended doesn't hold
        JSONObject over = RemoteSessionV2Test.document(20, 40, new JSONObject().put("kind", "bedtime")
                .put("until", "2020-01-01T07:00:00-07:00"), null);
        out = RemoteTime.front(entry(over), YOUTUBE, NOW);
        assertFalse(out.getBoolean("locked"));
        assertTrue(out.isNull("why"));
    }

    @Test
    public void aKidsOwnRulesHoldWhatTheyHold() throws Exception {
        JSONObject entry = entry(person(10, 40));
        assertTrue(RemoteTime.allowed(entry, YOUTUBE, NOW));
        assertFalse(RemoteTime.allowed(entry, RemoteSessionV2Test.GAME, NOW));
        assertTrue(RemoteTime.allowed(null, RemoteSessionV2Test.GAME, NOW));
        JSONObject bedtime = entry(RemoteSessionV2Test.document(10, 40, new JSONObject().put("kind", "bedtime")
                .put("until", "2099-01-02T07:00:00-07:00"), null));
        assertFalse(RemoteTime.allowed(bedtime, YOUTUBE, NOW));
    }

    @Test
    public void localRulesCountMinutesUsed() throws Exception {
        assertEquals(0, LocalRules.usedMinutes(0));
        assertEquals(1, LocalRules.usedMinutes(1));
        assertEquals(2, LocalRules.usedMinutes(60_001));
        assertEquals(58, LocalRules.left(60, 90_000));
    }
}
