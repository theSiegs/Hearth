package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Hearth's own rules for a TV without Home Assistant, as the document Home Assistant would send. */
public class LocalRulesTest {
    private static final ZoneId ZONE = ZoneId.of("America/New_York");
    // A Wednesday and a Saturday
    private static final ZonedDateTime WEDNESDAY_4PM = ZonedDateTime.of(2026, 11, 11, 16, 0, 0, 0, ZONE);
    private static final ZonedDateTime SATURDAY_4PM = ZonedDateTime.of(2026, 11, 14, 16, 0, 0, 0, ZONE);
    private static final String GAME = "com.example.game";
    private static final String VIDEO = "com.example.video";

    private static JSONObject rules() throws Exception {
        return new JSONObject()
                .put("all", new JSONObject().put("weekday", 120).put("weekend", 180))
                .put("groups", new JSONArray().put(new JSONObject().put("id", "games").put("name", "Games")
                        .put("weekday", 30).put("weekend", JSONObject.NULL).put("category", "game")))
                .put("bedtime", new JSONObject().put("from", "20:30").put("to", "07:00").put("days", "all"))
                .put("notCounted", new JSONArray().put("com.example.school"));
    }

    private static Map<String, Long> usage(Object... appAndMinutes) {
        Map<String, Long> out = new HashMap<>();
        for (int i = 0; i < appAndMinutes.length; i += 2) {
            out.put((String) appAndMinutes[i], ((Integer) appAndMinutes[i + 1]) * 60_000L);
        }
        return out;
    }

    private static String category(String app) {
        return GAME.equals(app) ? "game" : null;
    }

    private static JSONObject group(JSONObject document, String id) {
        JSONArray groups = document.optJSONArray("groups");
        for (int i = 0; i < groups.length(); i++) {
            if (id.equals(groups.optJSONObject(i).optString("id"))) return groups.optJSONObject(i);
        }
        return null;
    }

    @Test
    public void countsMinutesLeftOnAWeekday() throws Exception {
        JSONObject document = LocalRules.document(rules(),
                usage(GAME, 20, VIDEO, 40, "com.example.school", 60), List.of(GAME, VIDEO),
                LocalRulesTest::category, WEDNESDAY_4PM);
        // All screen time leaves out what isn't counted
        assertEquals(60, group(document, "all").getInt("minutes_left"));
        assertEquals("com.example.school", group(document, "all").getJSONArray("except").getString(0));
        // Games takes Android's game category
        JSONObject games = group(document, "games");
        assertEquals(10, games.getInt("minutes_left"));
        assertEquals(GAME, games.getJSONArray("apps").getString(0));
        assertFalse(document.getBoolean("locked"));
    }

    @Test
    public void aWeekendWithoutAGroupLimitLeavesTheGroupOut() throws Exception {
        JSONObject document = LocalRules.document(rules(), usage(GAME, 200), List.of(GAME),
                LocalRulesTest::category, SATURDAY_4PM);
        assertNull(group(document, "games"));
        assertEquals(0, group(document, "all").getInt("minutes_left"));
    }

    @Test
    public void aStartedMinuteCounts() {
        assertEquals(29, LocalRules.left(30, 1));
        assertEquals(29, LocalRules.left(30, 60_000));
        assertEquals(0, LocalRules.left(30, 31 * 60_000L));
    }

    @Test
    public void bedtimeLocksAcrossMidnightAndSaysWhenItEnds() throws Exception {
        JSONObject late = LocalRules.document(rules(), usage(), List.of(), null, WEDNESDAY_4PM.withHour(22));
        assertTrue(late.getBoolean("locked"));
        assertEquals("bedtime", late.getJSONObject("lock").getString("kind"));
        assertEquals("2026-11-12T07:00:00-05:00", late.getJSONObject("lock").getString("until"));

        JSONObject early = LocalRules.document(rules(), usage(), List.of(), null, WEDNESDAY_4PM.withHour(6));
        assertTrue(early.getBoolean("locked"));
        assertEquals("2026-11-11T07:00:00-05:00", early.getJSONObject("lock").getString("until"));
    }

    @Test
    public void beforeBedtimeItSaysWhenItStarts() throws Exception {
        JSONObject document = LocalRules.document(rules(), usage(), List.of(), null, WEDNESDAY_4PM);
        assertNotNull(document.optJSONObject("next_lock"));
        assertEquals("2026-11-11T20:30:00-05:00", document.getJSONObject("next_lock").getString("at"));
    }

    @Test
    public void weekdayBedtimeStartsOnlyOnWeekdayEvenings() throws Exception {
        JSONObject rules = rules();
        rules.getJSONObject("bedtime").put("days", "weekdays");
        // Friday night is a weekend night: no bedtime that starts then
        ZonedDateTime fridayNight = ZonedDateTime.of(2026, 11, 13, 22, 0, 0, 0, ZONE);
        assertFalse(LocalRules.document(rules, usage(), List.of(), null, fridayNight).getBoolean("locked"));
        // Thursday's runs into Friday morning
        ZonedDateTime fridayMorning = ZonedDateTime.of(2026, 11, 13, 6, 0, 0, 0, ZONE);
        assertTrue(LocalRules.document(rules, usage(), List.of(), null, fridayMorning).getBoolean("locked"));
    }

    @Test
    public void readsAsHomeAssistantsDocument() throws Exception {
        JSONObject person = LocalRules.document(rules(), usage(GAME, 30), List.of(GAME),
                LocalRulesTest::category, WEDNESDAY_4PM.withHour(22));
        JSONObject profiles = HaAllowance.profilesFromDocument(
                new JSONObject().put("profiles", new JSONObject().put("user:10", person)));
        JSONObject entry = profiles.getJSONObject("user:10");
        assertTrue(entry.getBoolean("schedule_locked"));
        assertEquals("Games", entry.getJSONObject("out_of_time").getString(GAME));
    }
}
