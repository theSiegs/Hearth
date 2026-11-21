package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * The state document as Home Assistant sends it (ha_tests/contract_fixtures/tv_state_document.json, which
 * ha_tests/test_client_contract.py checks against the integration), and what the TV makes of it: HearthTube's minutes,
 * the lock and its words, minutes used, and the next lock it starts itself while Home Assistant is away.
 */
public class TvStateDocumentFixtureTest {
    private static final String TUBE = CompanionApps.HEARTHTUBE;
    private static final JSONObject MOMENTS = moments();

    private static JSONObject moments() {
        try {
            return new JSONObject(PinFakes.file("../../ha_tests/contract_fixtures/tv_state_document.json"))
                    .getJSONObject("moments");
        } catch (Exception e) {
            throw new AssertionError(e);
        }
    }

    /** The TV's entry for Sam at [moment], as kept after Home Assistant's word at [wordAt]. */
    private static JSONObject entry(String moment, String wordAt) throws Exception {
        JSONObject state = new JSONObject().put("profiles", new JSONObject().put("user:10", MOMENTS.get(moment)))
                .put("version", "fixture");
        JSONObject entry = HaAllowance.profilesFromDocument(state).getJSONObject("user:10");
        return entry.put(HaAllowance.WORD_AT_KEY, at(wordAt));
    }

    private static long at(String iso) {
        return HaLocks.parseTime(iso);
    }

    private static Integer used(JSONObject entry, String group) {
        JSONArray groups = entry.optJSONArray(HaAllowance.GROUPS_KEY);
        for (int i = 0; groups != null && i < groups.length(); i++) {
            JSONObject limit = groups.optJSONObject(i);
            if (group.equals(limit.optString("id"))) {
                return limit.has("minutes_used") ? limit.optInt("minutes_used") : null;
            }
        }
        throw new AssertionError("no group " + group);
    }

    @Test
    public void inTheEveningHearthTubeHasVideoSMinutesAndBedtimeIsNext() throws Exception {
        JSONObject entry = entry("evening", "2026-11-17T20:00:00-08:00");
        HaAllowance.Values values = HaAllowance.valuesOf(entry, 1L, at("2026-11-17T20:00:00-08:00"));
        assertEquals(Integer.valueOf(20), values.youtubeMinutesLeft);
        assertFalse(values.scheduleLocked);
        // Minutes used come from the document's time (Home Assistant sends none with a group)
        assertEquals(Integer.valueOf(15), used(entry, "all"));
        assertEquals(Integer.valueOf(10), used(entry, "video"));
        // The next lock ends when Home Assistant says (Family Link's own bedtime end)
        JSONObject next = HaLocks.locksOf(entry).getJSONObject("next_lock");
        assertEquals("bedtime", next.getString("kind"));
        assertEquals(at("2026-11-18T07:00:00-08:00"), (long) HaLocks.parseTime(next.getString("until")));
        assertNull(Allowance.lockInForce(entry, at("2026-11-17T21:00:00-08:00")));
    }

    @Test
    public void aNextLockWithNoEndOfItsOwnEndsAtTheScheduleSWakeTime() throws Exception {
        JSONObject evening = new JSONObject(MOMENTS.getJSONObject("evening").toString());
        evening.getJSONObject("next_lock").remove("until");
        JSONObject state = new JSONObject().put("profiles", new JSONObject().put("user:10", evening));
        JSONObject entry = HaAllowance.profilesFromDocument(state).getJSONObject("user:10");
        JSONObject next = HaLocks.locksOf(entry).getJSONObject("next_lock");
        assertEquals(at("2026-11-18T06:45:00-08:00"), (long) HaLocks.parseTime(next.getString("until")));
    }

    @Test
    public void withHomeAssistantAwayTheTvStartsBedtimeAndEndsItAtWakeTime() throws Exception {
        JSONObject entry = entry("evening", "2026-11-17T20:00:00-08:00");
        long night = at("2026-11-17T21:40:00-08:00");
        assertTrue(Allowance.lockedNow(entry, night));
        assertTrue(HaAllowance.valuesOf(entry, 1L, night).scheduleLocked);
        JSONObject lock = Allowance.lockInForce(entry, night);
        assertEquals("bedtime", lock.getString("kind"));
        assertEquals(R.string.bedtime_until, Allowance.lockMessage(lock.getString("kind"), true));
        // Past midnight it still holds; at its end (Family Link's 7:00) it's over
        long afterMidnight = at("2026-11-18T00:01:00-08:00");
        JSONObject carried = HaAllowance.carriedOver(entry, afterMidnight);
        assertNotNull(carried);
        assertTrue(Allowance.lockedNow(carried, afterMidnight));
        assertTrue(HaAllowance.valuesOf(carried, null, afterMidnight).scheduleLocked);
        assertTrue(Allowance.lockedNow(carried, at("2026-11-18T06:59:00-08:00")));
        long morning = at("2026-11-18T07:01:00-08:00");
        carried = HaAllowance.carriedOver(entry, morning);
        assertFalse(Allowance.lockedNow(carried, morning));
        assertFalse(HaAllowance.valuesOf(carried, null, morning).scheduleLocked);
        // Then the new day's first lock, School time, as tomorrow named it, until its end
        long school = at("2026-11-18T08:00:00-08:00");
        carried = HaAllowance.carriedOver(entry, school);
        assertTrue(Allowance.lockedNow(carried, school));
        assertEquals("school_time", Allowance.lockInForce(carried, school).getString("kind"));
        long afternoon = at("2026-11-18T15:16:00-08:00");
        assertFalse(Allowance.lockedNow(HaAllowance.carriedOver(entry, afternoon), afternoon));
    }

    @Test
    public void aNewDayWithHomeAssistantAwayStartsFromTomorrowSMinutes() throws Exception {
        JSONObject entry = entry("evening", "2026-11-17T20:00:00-08:00");
        long morning = at("2026-11-18T16:00:00-08:00");
        JSONObject carried = HaAllowance.carriedOver(entry, morning);
        // Daily time 60 and Video 30, nothing used yet: HearthTube has Video's 30
        HaAllowance.Values values = HaAllowance.valuesOf(carried, null, morning);
        assertEquals(Integer.valueOf(30), values.youtubeMinutesLeft);
        assertNull(values.timeUpGroup("com.example.game", morning));
        // 31 minutes of YouTube and Video is out; 61 minutes in all and daily time is too
        java.util.Map<String, Long> front = new java.util.HashMap<>();
        front.put("com.google.android.youtube.tv", 31 * 60_000L);
        values = HaAllowance.valuesOf(HaAllowance.staleCountdown(carried, front), null, morning);
        assertEquals("Video", values.timeUpGroup("com.google.android.youtube.tv", morning));
        assertNull(values.timeUpGroup("com.example.game", morning));
        assertEquals(Integer.valueOf(0), values.youtubeMinutesLeft);
        front.put("com.example.game", 30 * 60_000L);
        values = HaAllowance.valuesOf(HaAllowance.staleCountdown(carried, front), null, morning);
        assertEquals("Daily time", values.timeUpGroup("com.example.game", morning));
    }

    @Test
    public void anOlderHomeAssistantWithoutTomorrowCarriesTodaySBaseMinutes() throws Exception {
        JSONObject evening = new JSONObject(MOMENTS.getJSONObject("evening").toString());
        evening.remove("tomorrow");
        evening.getJSONObject("time").put("base_minutes", 50)
                .getJSONArray("categories").getJSONObject(0).put("limit", 25);
        JSONObject state = new JSONObject().put("profiles", new JSONObject().put("user:10", evening));
        JSONObject entry = HaAllowance.profilesFromDocument(state).getJSONObject("user:10");
        long morning = at("2026-11-18T16:00:00-08:00");
        assertEquals(Integer.valueOf(25),
                HaAllowance.valuesOf(HaAllowance.carriedOver(entry, morning), null, morning).youtubeMinutesLeft);
        // Knowing neither, the new day has no minutes (as before), and nothing holds after the night's lock
        evening.getJSONObject("time").remove("base_minutes");
        evening.getJSONObject("time").getJSONArray("categories").getJSONObject(0).remove("limit");
        entry = HaAllowance.profilesFromDocument(state).getJSONObject("user:10");
        assertNull(HaAllowance.carriedOver(entry, morning));
    }

    @Test
    public void aGroupWithNoMinutesTomorrowIsHeldFromTheStart() throws Exception {
        JSONObject evening = new JSONObject(MOMENTS.getJSONObject("evening").toString());
        evening.getJSONObject("tomorrow").getJSONArray("groups").getJSONObject(1).put("minutes", 0);
        JSONObject state = new JSONObject().put("profiles", new JSONObject().put("user:10", evening));
        JSONObject entry = HaAllowance.profilesFromDocument(state).getJSONObject("user:10");
        long morning = at("2026-11-18T16:00:00-08:00");
        HaAllowance.Values values = HaAllowance.valuesOf(HaAllowance.carriedOver(entry, morning), null, morning);
        assertEquals("Video", values.timeUpGroup("com.google.android.youtube.tv", morning));
        assertEquals(Integer.valueOf(0), values.youtubeMinutesLeft);
    }

    @Test
    public void anAllowThatEndsWithHomeAssistantAwayHoldsTheGroupAgain() throws Exception {
        JSONObject entry = entry("allowed_until", "2026-11-17T17:00:00-08:00");
        entry.put(HaAllowance.FRONT_AT_KEY, new JSONObject());
        java.util.Map<String, Long> front = new java.util.HashMap<>();
        // An hour of YouTube in the allow, then 10 minutes more
        front.put("com.google.android.youtube.tv", 70 * 60_000L);
        // Until its end and the grace, it's still open
        assertNull(HaAllowance.liftsEnded(entry, at("2026-11-17T18:02:00-08:00"), front));
        long after = at("2026-11-17T18:10:00-08:00");
        JSONObject lifted = HaAllowance.liftsEnded(entry, after, front);
        assertNotNull(lifted);
        HaAllowance.Values values = HaAllowance.valuesOf(HaAllowance.staleCountdown(lifted, front), null, after);
        assertNull(values.timeUpGroup("com.google.android.youtube.tv", after));
        assertNotNull(values.youtubeMinutesLeft);
        // 20 minutes after the allow's end: Video's 20 are spent
        front.put("com.google.android.youtube.tv", 81 * 60_000L);
        long later = at("2026-11-17T18:21:00-08:00");
        values = HaAllowance.valuesOf(HaAllowance.staleCountdown(HaAllowance.liftsEnded(entry, later, front), front),
                null, later);
        assertEquals("Video", values.timeUpGroup("com.google.android.youtube.tv", later));
        assertEquals(Integer.valueOf(0), values.youtubeMinutesLeft);
        // The allowed hour isn't daily time: other apps still have it
        assertNull(values.timeUpGroup("com.example.game", later));
        // A word from Home Assistant after the end is the truth
        JSONObject heard = entry("allowed_until", "2026-11-17T18:01:00-08:00");
        assertNull(HaAllowance.liftsEnded(heard, later, front));
    }

    @Test
    public void aCategoryBonusThatRunsOutWithHomeAssistantAwayHoldsTheGroup() throws Exception {
        JSONObject entry = entry("allowed", "2026-11-17T17:10:00-08:00");
        entry.put(HaAllowance.FRONT_AT_KEY, new JSONObject());
        java.util.Map<String, Long> front = new java.util.HashMap<>();
        front.put("com.google.android.youtube.tv", 10 * 60_000L);
        long now = at("2026-11-17T17:30:00-08:00");
        // 10 of the bonus's 15 minutes: still open
        assertNull(HaAllowance.liftsEnded(entry, now, front));
        front.put("com.google.android.youtube.tv", 15 * 60_000L);
        JSONObject lifted = HaAllowance.liftsEnded(entry, now, front);
        HaAllowance.Values values = HaAllowance.valuesOf(HaAllowance.staleCountdown(lifted, front), null, now);
        // Daily time is out, and YouTube counts in it again
        assertNotNull(values.timeUpGroup("com.google.android.youtube.tv", now));
        assertEquals(Integer.valueOf(0), values.youtubeMinutesLeft);
    }

    @Test
    public void atBedtimeTheLockIsBedtimeUntilItsEnd() throws Exception {
        JSONObject entry = entry("bedtime", "2026-11-17T21:45:00-08:00");
        long now = at("2026-11-17T21:50:00-08:00");
        assertTrue(HaAllowance.valuesOf(entry, 1L, now).scheduleLocked);
        JSONObject lock = Allowance.lockInForce(entry, now);
        assertEquals("bedtime", lock.getString("kind"));
        assertEquals(at("2026-11-18T07:00:00-08:00"), (long) HaLocks.parseTime(lock.getString("until")));
        assertEquals(Integer.valueOf(45), HaAllowance.valuesOf(entry, 1L, now).youtubeMinutesLeft);
        // When its end has passed with Home Assistant away, HearthTube isn't locked either
        assertFalse(HaAllowance.valuesOf(entry, 1L, at("2026-11-18T07:01:00-08:00")).scheduleLocked);
    }

    @Test
    public void aLiftedBedtimeComesBackAtTheLiftSEnd() throws Exception {
        JSONObject entry = entry("lifted", "2026-11-17T21:45:00-08:00");
        assertFalse(HaAllowance.valuesOf(entry, 1L, at("2026-11-17T21:50:00-08:00")).scheduleLocked);
        JSONObject next = HaLocks.locksOf(entry).getJSONObject("next_lock");
        assertEquals("bedtime", next.getString("kind"));
        assertEquals(at("2026-11-17T22:15:00-08:00"), (long) HaLocks.parseTime(next.getString("at")));
        // Home Assistant away: bedtime is back after the lift's end (and the grace), until its end
        assertFalse(Allowance.lockedNow(entry, at("2026-11-17T22:16:00-08:00")));
        assertTrue(Allowance.lockedNow(entry, at("2026-11-17T22:20:00-08:00")));
        assertFalse(Allowance.lockedNow(entry, at("2026-11-18T07:01:00-08:00")));
        // A word from Home Assistant after the lift's end is the truth (more extra time, say)
        JSONObject later = entry("lifted", "2026-11-17T22:16:00-08:00");
        assertFalse(Allowance.lockedNow(later, at("2026-11-17T22:20:00-08:00")));
    }

    @Test
    public void aPauseIsALockOfItsOwnKind() throws Exception {
        JSONObject entry = entry("paused", "2026-11-17T17:10:00-08:00");
        long now = at("2026-11-17T17:20:00-08:00");
        HaAllowance.Values values = HaAllowance.valuesOf(entry, 1L, now);
        assertTrue(values.scheduleLocked);
        assertEquals(at("2026-11-17T17:53:00-08:00"), (long) values.pausedUntil);
        assertEquals("pause", Allowance.lockInForce(entry, now).getString("kind"));
        assertFalse(HaAllowance.valuesOf(entry, 1L, at("2026-11-17T17:54:00-08:00")).scheduleLocked);
    }

    @Test
    public void anAllowedYouTubeIsNotHeldByDailyTime() throws Exception {
        JSONObject entry = entry("allowed", "2026-11-17T17:10:00-08:00");
        HaAllowance.Values values = HaAllowance.valuesOf(entry, 1L, at("2026-11-17T17:10:00-08:00"));
        assertNull(values.youtubeMinutesLeft);
        assertNull(values.timeUpGroup(TUBE, at("2026-11-17T17:10:00-08:00")));
        assertNull(values.timeUpGroup("com.google.android.youtube.tv", at("2026-11-17T17:10:00-08:00")));
        assertEquals(Integer.valueOf(15), used(entry, "all"));
    }
}
