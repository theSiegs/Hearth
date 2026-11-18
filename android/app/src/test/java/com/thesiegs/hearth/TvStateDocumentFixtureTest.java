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
        // The next lock ends with the weekly schedule's wake time
        JSONObject next = HaLocks.locksOf(entry).getJSONObject("next_lock");
        assertEquals("bedtime", next.getString("kind"));
        assertEquals(at("2026-11-18T06:45:00-08:00"), (long) HaLocks.parseTime(next.getString("until")));
        assertNull(Allowance.lockInForce(entry, at("2026-11-17T21:00:00-08:00")));
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
        // Past midnight it still holds; at wake time it's over
        long afterMidnight = at("2026-11-18T00:01:00-08:00");
        JSONObject carried = HaAllowance.carriedOver(entry, afterMidnight);
        assertNotNull(carried);
        assertTrue(Allowance.lockedNow(carried, afterMidnight));
        assertTrue(HaAllowance.valuesOf(carried, null, afterMidnight).scheduleLocked);
        long morning = at("2026-11-18T06:46:00-08:00");
        assertFalse(Allowance.lockedNow(carried, morning));
        assertFalse(HaAllowance.valuesOf(carried, null, morning).scheduleLocked);
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
        // Home Assistant away: bedtime is back after the lift's end (and the grace), until the wake time
        assertFalse(Allowance.lockedNow(entry, at("2026-11-17T22:16:00-08:00")));
        assertTrue(Allowance.lockedNow(entry, at("2026-11-17T22:20:00-08:00")));
        assertFalse(Allowance.lockedNow(entry, at("2026-11-18T06:46:00-08:00")));
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
