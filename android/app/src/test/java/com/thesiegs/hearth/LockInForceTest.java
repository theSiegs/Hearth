package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * The lock the kid is told about (Allowance.lockInForce, lockMessage), a next lock's own end (next_lock.until), and
 * minutes used read from the document's time.
 */
public class LockInForceTest {
    private static long at(String iso) {
        return HaLocks.parseTime(iso);
    }

    private static JSONObject entry(JSONObject locks, String wordAt) throws Exception {
        return new JSONObject().put("schedule_locked", locks.has("lock")).put(HaAllowance.LOCKS_KEY, locks)
                .put(HaAllowance.WORD_AT_KEY, at(wordAt));
    }

    @Test
    public void eachKindHasItsOwnWords() {
        assertEquals(R.string.bedtime_until, Allowance.lockMessage("bedtime", true));
        assertEquals(R.string.bedtime_now, Allowance.lockMessage("bedtime", false));
        assertEquals(R.string.school_time_until, Allowance.lockMessage("school_time", true));
        assertEquals(R.string.school_time_now, Allowance.lockMessage("school_time", false));
        assertEquals(R.string.locked_until, Allowance.lockMessage("other", true));
        assertEquals(R.string.locked_now, Allowance.lockMessage("", false));
    }

    @Test
    public void theLockHomeAssistantSentWhileItLasts() throws Exception {
        JSONObject school = new JSONObject().put("kind", "school_time").put("until", "2026-11-17T15:00:00-06:00");
        JSONObject entry = entry(new JSONObject().put("lock", school), "2026-11-17T08:00:00-06:00");
        assertEquals("school_time", Allowance.lockInForce(entry, at("2026-11-17T09:00:00-06:00")).getString("kind"));
        // Ended: nothing holds
        assertNull(Allowance.lockInForce(entry, at("2026-11-17T15:01:00-06:00")));
        // A lock that names no end holds until Home Assistant says otherwise
        JSONObject open = new JSONObject().put("kind", "other").put("until", JSONObject.NULL);
        JSONObject grounded = entry(new JSONObject().put("lock", open), "2026-11-17T08:00:00-06:00");
        assertEquals("other", Allowance.lockInForce(grounded, at("2026-11-18T09:00:00-06:00")).getString("kind"));
    }

    @Test
    public void afterAnEndedLockTheNextLockTheTvStartedItself() throws Exception {
        JSONObject locks = new JSONObject()
                .put("lock", new JSONObject().put("kind", "school_time").put("until", "2026-11-17T15:00:00-06:00"))
                .put("next_lock", new JSONObject().put("at", "2026-11-17T20:00:00-06:00").put("kind", "bedtime"));
        JSONObject entry = entry(locks, "2026-11-17T14:00:00-06:00");
        assertNull(Allowance.lockInForce(entry, at("2026-11-17T19:00:00-06:00")));
        assertEquals("bedtime", Allowance.lockInForce(entry, at("2026-11-17T20:05:00-06:00")).getString("kind"));
    }

    @Test
    public void aNextLockIsOverAtItsOwnEnd() throws Exception {
        JSONObject next = new JSONObject().put("at", "2026-11-17T20:00:00-06:00").put("kind", "bedtime")
                .put("until", "2026-11-18T07:00:00-06:00");
        JSONObject entry = entry(new JSONObject().put("next_lock", next), "2026-11-17T19:30:00-06:00");
        assertTrue(Allowance.lockedNow(entry, at("2026-11-18T06:59:00-06:00")));
        assertFalse(Allowance.lockedNow(entry, at("2026-11-18T07:00:00-06:00")));
        // Without an end it holds on (until Home Assistant's word)
        next.remove("until");
        assertTrue(Allowance.lockedNow(entry, at("2026-11-18T09:00:00-06:00")));
    }

    @Test
    public void aNextLockThatSaysItsOwnEndKeepsIt() throws Exception {
        JSONObject person = new JSONObject()
                .put("next_lock", new JSONObject().put("at", "2026-11-17T20:00:00-06:00").put("kind", "bedtime")
                        .put("until", "2026-11-18T06:30:00-06:00"))
                .put("schedule", new JSONObject().put("bedtime", new JSONObject()
                        .put("at", "2026-11-17T20:00:00-06:00").put("wake", "2026-11-18T07:00:00-06:00")));
        JSONObject entry = HaAllowance.profilesFromDocument(new JSONObject().put("profiles",
                new JSONObject().put("user:10", person))).getJSONObject("user:10");
        assertEquals("2026-11-18T06:30:00-06:00",
                HaLocks.locksOf(entry).getJSONObject("next_lock").getString("until"));
        // The document's own object is left as it came
        assertEquals("2026-11-18T06:30:00-06:00", person.getJSONObject("next_lock").getString("until"));
    }

    @Test
    public void aNextLockBeforeTheLiftSEndIsKept() throws Exception {
        // A newer Home Assistant names the lift's end itself, or something earlier comes first
        JSONObject person = new JSONObject()
                .put("bedtime_lifted", new JSONObject().put("since", "2026-11-17T20:45:00-06:00")
                        .put("until", "2026-11-17T21:15:00-06:00"))
                .put("next_lock", new JSONObject().put("at", "2026-11-17T21:00:00-06:00").put("by", "switch.x")
                        .put("kind", "other"));
        JSONObject entry = HaAllowance.profilesFromDocument(new JSONObject().put("profiles",
                new JSONObject().put("user:10", person))).getJSONObject("user:10");
        JSONObject next = HaLocks.locksOf(entry).getJSONObject("next_lock");
        assertEquals("other", next.getString("kind"));
        assertEquals("2026-11-17T21:00:00-06:00", next.getString("at"));
    }

    private static JSONObject group(String id, int left) throws Exception {
        return new JSONObject().put("id", id).put("name", id).put("minutes_left", left).put("apps", new JSONArray());
    }

    private static JSONObject limits(JSONObject person) throws Exception {
        JSONArray groups = HaAllowance.profilesFromDocument(new JSONObject().put("profiles",
                new JSONObject().put("user:10", person))).getJSONObject("user:10")
                .getJSONArray(HaAllowance.GROUPS_KEY);
        JSONObject byId = new JSONObject();
        for (int i = 0; i < groups.length(); i++) byId.put(groups.getJSONObject(i).getString("id"), groups.get(i));
        return byId;
    }

    @Test
    public void minutesUsedComeFromTheDocumentSTime() throws Exception {
        JSONObject time = new JSONObject().put("used", 42).put("categories", new JSONArray()
                .put(new JSONObject().put("id", "games").put("used", 17))
                .put(new JSONObject().put("id", "video").put("used", JSONObject.NULL)));
        JSONObject person = new JSONObject().put("time", time).put("groups", new JSONArray()
                .put(group("all", 18)).put(group("games", 3)).put(group("video", 5)).put(group("music", 9)));
        JSONObject limits = limits(person);
        assertEquals(42, limits.getJSONObject("all").getInt("minutes_used"));
        assertEquals(17, limits.getJSONObject("games").getInt("minutes_used"));
        // Unknown: none rather than 0
        assertFalse(limits.getJSONObject("video").has("minutes_used"));
        assertFalse(limits.getJSONObject("music").has("minutes_used"));
        // A group's own minutes_used wins
        person.getJSONArray("groups").getJSONObject(1).put("minutes_used", 20);
        assertEquals(20, limits(person).getJSONObject("games").getInt("minutes_used"));
        // No time at all: none
        person.remove("time");
        assertFalse(limits(person).getJSONObject("all").has("minutes_used"));
    }
}
