package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * Seams review probes (2026-11-17): what the TV believes about bedtime and locks while Home Assistant is away. Each
 * asserts the behaviour a family would expect, and fails on the code as reviewed.
 */
public class SeamsOfflineLocksTest {
    private static long at(String iso) {
        return HaLocks.parseTime(iso);
    }

    /** Home Assistant's last word at 7:30 PM: not locked, bedtime comes at 8 PM. Then it went quiet. */
    private static JSONObject entryBeforeBedtime() throws Exception {
        JSONObject locks = new JSONObject().put("next_lock", new JSONObject()
                .put("at", "2026-11-16T20:00:00-06:00").put("by", "schedule").put("kind", "bedtime"));
        return new JSONObject().put("youtube_minutes_left", 45).put("out_of_time", new JSONObject())
                .put("schedule_locked", false).put(HaAllowance.LOCKS_KEY, locks)
                .put(HaAllowance.WORD_AT_KEY, at("2026-11-16T19:30:00-06:00"));
    }

    @Test
    public void aBedtimeTheTvStartedItselfStillHoldsAfterMidnight() throws Exception {
        JSONObject entry = entryBeforeBedtime();
        // The router is unplugged: the TV starts bedtime itself (the hardened lockedNow)
        assertTrue(Allowance.lockedNow(entry, at("2026-11-16T23:59:00-06:00")));
        // A minute later it's a new day: entryFor reads the entry through carriedOver
        long later = at("2026-11-17T00:01:00-06:00");
        JSONObject carried = HaAllowance.carriedOver(entry, later);
        assertNotNull("the bedtime the TV started is forgotten at midnight", carried);
        assertTrue("bedtime is over at 00:01 with Home Assistant still away", Allowance.lockedNow(carried, later));
    }

    @Test
    public void aLockWithNoEndStillHoldsAfterMidnight() throws Exception {
        // A lock entity that doesn't say when it ends (lock.until null): it holds until Home Assistant says otherwise
        JSONObject locks = new JSONObject().put("lock", new JSONObject().put("kind", "other")
                .put("by", new JSONArray().put("switch.grounded")).put("until", JSONObject.NULL));
        JSONObject entry = new JSONObject().put("schedule_locked", true).put(HaAllowance.LOCKS_KEY, locks)
                .put(HaAllowance.WORD_AT_KEY, at("2026-11-16T19:30:00-06:00"));
        assertTrue(Allowance.lockedNow(entry, at("2026-11-16T23:59:00-06:00")));
        long later = at("2026-11-17T00:01:00-06:00");
        JSONObject carried = HaAllowance.carriedOver(entry, later);
        assertNotNull("a lock with no end is dropped at midnight", carried);
        assertTrue(Allowance.lockedNow(carried, later));
    }

    @Test
    public void aLiftedBedtimeComesBackWhenItsExtraTimeEnds() throws Exception {
        // 8:40 PM, in bedtime, an adult gave 20 minutes: Home Assistant sends no lock, and bedtime_lifted until 9 PM
        JSONObject person = new JSONObject().put("person", "person.sam").put("locked", false)
                .put("groups", new JSONArray().put(new JSONObject().put("id", "all").put("name", "Daily time")
                        .put("minutes_left", 20).put("apps", new JSONArray())))
                .put("bedtime_lifted", new JSONObject().put("since", "2026-11-16T20:40:00-06:00")
                        .put("until", "2026-11-16T21:00:00-06:00"));
        JSONObject entry = HaAllowance.profilesFromDocument(
                new JSONObject().put("profiles", new JSONObject().put("user:10", person))).getJSONObject("user:10");
        entry.put(HaAllowance.WORD_AT_KEY, at("2026-11-16T20:40:00-06:00"));
        // Home Assistant goes quiet. At 9:05 PM the lift is over: bedtime holds again
        assertTrue("the TV never learns when the lift ends: no bedtime tonight",
                Allowance.lockedNow(entry, at("2026-11-16T21:05:00-06:00")));
    }

    @Test
    public void aLockThatEndedNoLongerLocksYouTube() throws Exception {
        // School time until 3 PM; Home Assistant's last word at 2:50 PM. At 3:10 PM the other apps are open again
        JSONObject locks = new JSONObject().put("lock", new JSONObject().put("kind", "school_time")
                .put("until", "2026-11-16T15:00:00-06:00"));
        JSONObject entry = new JSONObject().put("youtube_minutes_left", 45).put("out_of_time", new JSONObject())
                .put("schedule_locked", true).put(HaAllowance.LOCKS_KEY, locks)
                .put(HaAllowance.WORD_AT_KEY, at("2026-11-16T14:50:00-06:00"));
        long now = at("2026-11-16T15:10:00-06:00");
        boolean appsLocked = Allowance.lockedNow(entry, now);
        // What HearthTube is told (ProfileProvider's schedule_locked, from Allowance.forProfile)
        boolean youtubeLocked = HaAllowance.valuesOf(entry, null).scheduleLocked;
        assertEquals("HearthTube stays locked after the lock's end while every other app opens", appsLocked,
                youtubeLocked);
    }
}
