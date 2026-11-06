package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.util.List;
import java.util.Map;

/** The integration's pause, locks, next lock and request, as the time's up card and the bedtime heads-up read them. */
public class HaLocksTest {
    private static final long MIN = 60_000L;

    private static JSONObject entry(String json) throws Exception {
        return new JSONObject(json);
    }

    @Test
    public void timesWithAnOffsetAreRead() {
        assertEquals(Long.valueOf(1793059200000L), HaLocks.parseTime("2026-10-26T19:00:00-05:00"));
        assertEquals(HaLocks.parseTime("2026-10-27T00:00:00+00:00"), HaLocks.parseTime("2026-10-26T19:00:00-05:00"));
        assertNull(HaLocks.parseTime(null));
        assertNull(HaLocks.parseTime("null"));
        assertNull(HaLocks.parseTime(""));
        assertNull(HaLocks.parseTime("7 PM"));
    }

    @Test
    public void theCardGetsThePauseTheLockTheNextLockAndTheRequest() throws Exception {
        long until = HaLocks.parseTime("2026-10-26T19:00:00-05:00");
        JSONObject stored = entry("{\"out_of_time\": {\"com.example.game\": \"Games\", \"com.example.toy\": \"Games\"},"
                + " \"all_out_of_time\": \"All screen time\", \"locks\": {"
                + "\"pause\": {\"until\": \"2026-10-26T19:00:00-05:00\", \"reason\": \"Dinner\"},"
                + "\"lock\": {\"by\": [\"pause\"], \"kind\": \"pause\", \"kinds\": [\"pause\"], \"until\": \"2026-10-26T19:00:00-05:00\"},"
                + "\"next_lock\": {\"at\": \"2026-10-26T20:30:00-05:00\", \"by\": \"binary_sensor.x\", \"kind\": \"bedtime\"},"
                + "\"request\": {\"id\": \"r1\", \"status\": \"approved\", \"minutes\": 30, \"asked_minutes\": 15,"
                + " \"group\": \"all\", \"expires\": \"2026-10-26T19:30:00-05:00\", \"answered\": \"2026-10-26T19:05:00-05:00\"}}}");
        Map<String, Object> card = HaLocks.forFlutter(stored, true, true, until - 10 * MIN);
        assertEquals(true, card.get("paired"));
        assertEquals(true, card.get("kids"));
        @SuppressWarnings("unchecked") Map<String, Object> pause = (Map<String, Object>) card.get("pause");
        assertEquals("Dinner", pause.get("reason"));
        assertEquals(until, pause.get("until"));
        @SuppressWarnings("unchecked") Map<String, Object> lock = (Map<String, Object>) card.get("lock");
        assertEquals("pause", lock.get("kind"));
        @SuppressWarnings("unchecked") Map<String, Object> next = (Map<String, Object>) card.get("nextLock");
        assertEquals("bedtime", next.get("kind"));
        assertEquals(until + 90 * MIN, next.get("at"));
        @SuppressWarnings("unchecked") Map<String, Object> request = (Map<String, Object>) card.get("request");
        assertEquals("approved", request.get("status"));
        assertEquals(30, request.get("minutes"));
        assertEquals(15, request.get("askedMinutes"));
        assertEquals(until + 5 * MIN, request.get("answered"));
        // What an older Hearth kept: the names alone
        @SuppressWarnings("unchecked") List<Map<String, Object>> timeUp = (List<Map<String, Object>>) card.get("timeUp");
        assertEquals(2, timeUp.size());
        assertEquals("All screen time", timeUp.get(0).get("name"));
        assertEquals("Games", timeUp.get(1).get("name"));
        assertNull(timeUp.get(0).get("id"));
    }

    @Test
    public void theGroupsOutOfTimeCarryTheirIds() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(new JSONObject("{\"profiles\": {\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"name\": \"Games\", \"minutes_left\": 0, \"apps\": [\"com.example.game\"]},"
                + "{\"id\": \"tv\", \"name\": \"TV\", \"minutes_left\": 20, \"apps\": [\"com.example.tv\"]}]}}}"));
        List<Map<String, Object>> timeUp = HaLocks.timeUpGroups(new JSONObject(profiles.toString()).optJSONObject("user:10"));
        assertEquals(1, timeUp.size());
        assertEquals("games", timeUp.get(0).get("id"));
        assertEquals("Games", timeUp.get(0).get("name"));
    }

    @Test
    public void aPauseOrNextLockThatsOverIsLeftOut() throws Exception {
        long until = HaLocks.parseTime("2026-10-26T19:00:00-05:00");
        JSONObject stored = entry("{\"locks\": {\"pause\": {\"until\": \"2026-10-26T19:00:00-05:00\", \"reason\": \"Dinner\"},"
                + "\"next_lock\": {\"at\": \"2026-10-26T19:00:00-05:00\", \"kind\": \"school_time\"}}}");
        Map<String, Object> card = HaLocks.forFlutter(stored, true, true, until);
        assertFalse(card.containsKey("pause"));
        assertFalse(card.containsKey("nextLock"));
        assertNull(HaLocks.nextLockAt(stored, until));
        assertEquals("school_time", HaLocks.nextLockKind(stored));
    }

    @Test
    public void everyGroupWithALimitAndItsMinutesLeft() throws Exception {
        JSONObject profiles = HaAllowance.profilesFromDocument(new JSONObject("{\"profiles\": {\"user:10\": {\"groups\": ["
                + "{\"id\": \"games\", \"name\": \"Games\", \"minutes_left\": 20, \"apps\": [\"com.example.game\"]},"
                + "{\"id\": \"all\", \"name\": \"All screen time\", \"minutes_left\": -1, \"apps\": [],"
                + " \"except\": [\"com.example.music\"]},"
                + "{\"id\": \"music\", \"minutes_left\": null, \"apps\": [\"com.example.music\"]}]}}}"));
        Map<String, Object> card = HaLocks.forFlutter(profiles.optJSONObject("user:10"), true, true, 1L);
        @SuppressWarnings("unchecked") List<Map<String, Object>> groups = (List<Map<String, Object>>) card.get("groups");
        assertEquals(2, groups.size());
        assertEquals("Games", groups.get(0).get("name"));
        assertEquals(20, groups.get(0).get("minutesLeft"));
        assertEquals(java.util.Collections.singletonList("com.example.game"), groups.get(0).get("apps"));
        assertEquals(0, groups.get(1).get("minutesLeft"));
        assertTrue(((List<?>) groups.get(1).get("apps")).isEmpty());
        assertEquals(java.util.Collections.singletonList("com.example.music"), groups.get(1).get("except"));
        assertTrue(((List<?>) HaLocks.forFlutter(null, false, false, 1L).get("groups")).isEmpty());
    }

    @Test
    public void nothingFromHomeAssistantIsAnEmptyCard() {
        Map<String, Object> card = HaLocks.forFlutter(null, false, true, 1L);
        assertEquals(false, card.get("paired"));
        assertFalse(card.containsKey("pause"));
        assertFalse(card.containsKey("lock"));
        assertFalse(card.containsKey("request"));
        assertTrue(((java.util.List<?>) card.get("timeUp")).isEmpty());
    }

    @Test
    public void anUnknownLockKindIsOther() throws Exception {
        Map<String, Object> card = HaLocks.forFlutter(entry("{\"locks\": {\"lock\": {\"kind\": \"homework\"}}}"),
                true, true, 1L);
        @SuppressWarnings("unchecked") Map<String, Object> lock = (Map<String, Object>) card.get("lock");
        assertEquals("other", lock.get("kind"));
        assertNull(lock.get("until"));
    }

    @Test
    public void headsUpFifteenThenFiveMinutesBefore() {
        long at = 1_000_000_000L;
        assertEquals(0, HaLocks.headsUpMark(at, at - 16 * MIN));
        assertEquals(15, HaLocks.headsUpMark(at, at - 15 * MIN));
        // Missed at its moment: still due while its stretch lasts
        assertEquals(15, HaLocks.headsUpMark(at, at - 6 * MIN));
        assertEquals(5, HaLocks.headsUpMark(at, at - 5 * MIN));
        assertEquals(5, HaLocks.headsUpMark(at, at - 1));
        assertEquals(0, HaLocks.headsUpMark(at, at));
    }

    @Test
    public void theNextHeadsUpIsTheNextMarkToCome() {
        long at = 1_000_000_000L;
        assertEquals(at - 15 * MIN, HaLocks.nextHeadsUpAt(at, at - 60 * MIN));
        assertEquals(at - 5 * MIN, HaLocks.nextHeadsUpAt(at, at - 15 * MIN));
        assertEquals(-1, HaLocks.nextHeadsUpAt(at, at - 5 * MIN));
    }

    @Test
    public void minutesLeftRoundUp() {
        long at = 1_000_000_000L;
        assertEquals(15, HaLocks.minutesUntil(at, at - 15 * MIN));
        assertEquals(15, HaLocks.minutesUntil(at, at - 14 * MIN - 10_000));
        assertEquals(1, HaLocks.minutesUntil(at, at - 1));
    }

    @Test
    public void anAskAnswerAsTheTvShowsIt() throws Exception {
        JSONObject ok = HaIntegration.askResult(200, entry("{\"ok\": true, \"request\": {\"id\": \"r1\", \"status\": \"pending\"}}"));
        assertTrue(ok.optBoolean("ok"));
        assertEquals("r1", ok.optJSONObject("request").optString("id"));
        JSONObject open = HaIntegration.askResult(409, entry("{\"error\": \"already_open\", \"request\": {\"id\": \"r0\"}}"));
        assertEquals("already_open", open.optString("error"));
        assertEquals("r0", open.optJSONObject("request").optString("id"));
        JSONObject cooldown = HaIntegration.askResult(429, entry("{\"error\": \"cooldown\", \"retry_in\": 420}"));
        assertEquals("cooldown", cooldown.optString("error"));
        assertEquals(420, cooldown.optInt("retry_in"));
        assertEquals("too_often", HaIntegration.askResult(429, entry("{\"error\": \"too_often\"}")).optString("error"));
        assertEquals("no_person", HaIntegration.askResult(404, entry("{\"error\": \"no_person\"}")).optString("error"));
        assertEquals("not_paired", HaIntegration.askResult(401, entry("{\"error\": \"not_paired\"}")).optString("error"));
        assertEquals("unreachable", HaIntegration.askResult(0, null).optString("error"));
        assertEquals("failed", HaIntegration.askResult(400, entry("{\"error\": \"bad_request\"}")).optString("error"));
    }
}
