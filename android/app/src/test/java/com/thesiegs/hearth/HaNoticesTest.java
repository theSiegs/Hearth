package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

/** The Hearth integration's notices: read from the state document, kept in the Bell for adults, and pressed. */
public class HaNoticesTest {
    private static final long NOW = 1_800_000_000_000L;
    private static final String ALEX = "a:alex";
    private static final String KID = "a:kid";

    private static JSONObject notice(String key, String title, String message) throws JSONException {
        return new JSONObject().put("key", key).put("tag", "tag-" + key).put("title", title).put("message", message)
                .put("urgency", "notice").put("actions", new JSONArray()
                        .put(new JSONObject().put("id", "0").put("title", "Allow +15"))
                        .put(new JSONObject().put("id", "1").put("title", "Not now")));
    }

    private static JSONObject document(JSONObject... notices) throws JSONException {
        JSONArray list = new JSONArray();
        for (JSONObject n : notices) list.put(n);
        return new JSONObject().put("version", "abc").put("notices", list);
    }

    private static HouseholdEntry file(HouseholdLog log, String person, HaNotices.Item n, long at) {
        return log.put(HouseholdNotices.KIND, person, HaNotices.item(person, n), HaNotices.value(n, at), at);
    }

    // ---- The document ----

    @Test
    public void readsTheDocumentsNotices_andIgnoresFieldsItDoesntKnow() throws JSONException {
        JSONObject n = notice("suggest:kid:games", "Alex is out of game time", "Give 15 more minutes?")
                .put("for", "person.alex").put("expires", "2027-01-15T08:00:00+00:00").put("colour", "blue");
        List<HaNotices.Item> items = HaNotices.fromDocument(document(n).put("something_new", 1));
        assertEquals(1, items.size());
        HaNotices.Item item = items.get(0);
        assertEquals("suggest:kid:games", item.key);
        assertEquals("tag-suggest:kid:games", item.tag);
        assertEquals("Alex is out of game time", item.title);
        assertEquals("Give 15 more minutes?", item.message);
        assertEquals("person.alex", item.target);
        assertEquals(HaNotices.NOTICE, item.urgency);
        assertEquals(2, item.actions.size());
        assertEquals("0", item.actions.get(0).id);
        assertEquals("Allow +15", item.actions.get(0).title);
        assertNull(item.actions.get(0).service);
        assertEquals(HaLocks.parseTime("2027-01-15T08:00:00+00:00"), item.expiresMs);
    }

    @Test
    public void noNoticesInTheDocumentIsNone() throws JSONException {
        assertTrue(HaNotices.fromDocument(new JSONObject().put("version", "abc")).isEmpty());
        assertTrue(HaNotices.fromDocument(new JSONObject().put("notices", "not a list")).isEmpty());
        assertTrue(HaNotices.fromDocument(null).isEmpty());
    }

    @Test
    public void aNoticeWithoutKeyOrText_isLeftOut_andTheRestStay() throws JSONException {
        JSONObject noKey = notice("", "Title", "Text");
        JSONObject noText = notice("b", "", "");
        JSONObject twice = notice("c", "Second copy", "x");
        List<HaNotices.Item> items = HaNotices.fromDocument(document(noKey, noText, notice("c", "First", "x"), twice,
                new JSONObject().put("key", "d").put("message", "Only a message")));
        assertEquals(2, items.size());
        assertEquals("First", items.get(0).title);
        assertEquals("d", items.get(1).key);
        // No tag: the key is its tag; no urgency: info; no actions: none
        assertEquals("d", items.get(1).tag);
        assertEquals(HaNotices.INFO, items.get(1).urgency);
        assertTrue(items.get(1).actions.isEmpty());
        assertNull(items.get(1).target);
    }

    @Test
    public void onlyButtonsNumberedZeroToTwoWithATitleAreKept_withTheirOwnIds() throws JSONException {
        JSONObject n = new JSONObject().put("key", "k").put("message", "m").put("actions", new JSONArray()
                .put(new JSONObject().put("id", "5").put("title", "Too far"))
                .put(new JSONObject().put("id", "1").put("title", ""))
                .put(new JSONObject().put("id", 2).put("title", "Two"))
                .put(new JSONObject().put("id", "2").put("title", "Two again"))
                .put(new JSONObject().put("title", "No id"))
                .put(new JSONObject().put("id", "0").put("title", "Zero")));
        List<HouseholdNotices.Action> actions = HaNotices.fromDocument(document(n)).get(0).actions;
        assertEquals(2, actions.size());
        assertEquals("2", actions.get(0).id);
        assertEquals("Two", actions.get(0).title);
        assertEquals("0", actions.get(1).id);
    }

    @Test
    public void expiresIsReadAsTheIntegrationSendsIt_orAsANumber() {
        assertEquals(HaLocks.parseTime("2026-11-13T20:00:00-05:00"), HaNotices.expires("2026-11-13T20:00:00-05:00"));
        assertEquals(Long.valueOf(1_800_000_000_000L), HaNotices.expires(1_800_000_000L));
        assertEquals(Long.valueOf(1_800_000_000_000L), HaNotices.expires(1_800_000_000_000L));
        assertNull(HaNotices.expires("tomorrow"));
        assertNull(HaNotices.expires(null));
    }

    // ---- In the Bell ----

    @Test
    public void aFiledNoticeIsTheIntegrations_withButtonsThatCallNoService() throws JSONException {
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "Out of time", "More?"))).get(0);
        HouseholdLog log = new HouseholdLog("tv-a");
        HouseholdNotices.Notice n = HouseholdNotices.parse(file(log, HouseholdNotices.ALL_ADULTS, item, NOW));
        assertTrue(n.fromIntegration());
        assertEquals("k1", n.key);
        assertEquals(HaNotices.NOTICE, n.urgency);
        assertEquals(2, n.actions.size());
        assertEquals("1", n.actions.get(1).id);
        assertNull(n.actions.get(1).service);
        assertFalse(n.actions.get(1).asSent().has("service"));
    }

    @Test
    public void anEntryWithAKeyNeverCarriesServiceButtons() throws JSONException {
        // Another TV wrote an integration notice with Home Assistant service buttons as well: they're not read
        String value = new JSONObject().put("f", "ha").put("ti", "T").put("tx", "x").put("k", "k1")
                .put("ac", new JSONArray().put(new JSONObject().put("ti", "Unlock").put("s", "lock.unlock")
                        .put("d", "{}"))).toString();
        HouseholdLog log = new HouseholdLog("tv-a");
        HouseholdNotices.Notice n = HouseholdNotices.parse(log.put(HouseholdNotices.KIND, ALEX, "ha:x", value, NOW));
        assertTrue(n.fromIntegration());
        assertTrue(n.actions.isEmpty());
    }

    @Test
    public void forEveryAdult_itShowsToAdults_andNeverInAKidsProfile() throws JSONException {
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "Out of time", "More?"))).get(0);
        HouseholdLog log = new HouseholdLog("tv-a");
        file(log, HouseholdNotices.ALL_ADULTS, item, NOW);
        assertEquals(1, HouseholdNotices.visible(log.all(), ALEX, false, "tv-x", NOW).size());
        assertTrue(HouseholdNotices.visible(log.all(), KID, true, "tv-x", NOW).isEmpty());
    }

    @Test
    public void evenOneNamingAKid_neverShowsInAKidsProfile() throws JSONException {
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "T", "x"))).get(0);
        HouseholdLog log = new HouseholdLog("tv-a");
        file(log, KID, item, NOW);
        assertTrue(HouseholdNotices.visible(log.all(), KID, true, "tv-x", NOW).isEmpty());
        // And one for Alex only to Alex
        file(log, ALEX, item, NOW);
        assertEquals(1, HouseholdNotices.visible(log.all(), ALEX, false, "tv-x", NOW).size());
        assertTrue(HouseholdNotices.visible(log.all(), "a:sam", false, "tv-x", NOW).isEmpty());
    }

    @Test
    public void theSameTagReplaces_butNeverAHomeAssistantNotificationWithThatTag() throws JSONException {
        HaNotices.Item first = HaNotices.fromDocument(document(notice("k1", "One", "x"))).get(0);
        HaNotices.Item second = HaNotices.fromDocument(document(notice("k2", "Two", "y").put("tag", "tag-k1"))).get(0);
        assertEquals(HaNotices.item(ALEX, first), HaNotices.item(ALEX, second));
        assertNotEquals(HaNotices.item(ALEX, first), HaNotices.item("a:sam", first));
        assertNotEquals(HaNotices.item(ALEX, first), HouseholdNotices.haItem(ALEX, "tag-k1", null, null));
    }

    @Test
    public void aNoticeReadAgainUnchangedIsTheSame_soItIsntWrittenAgain() throws JSONException {
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "T", "x"))).get(0);
        HaNotices.Item changed = HaNotices.fromDocument(document(notice("k1", "T", "y"))).get(0);
        assertTrue(HaNotices.same(HaNotices.value(item, NOW), HaNotices.value(item, NOW + 60_000)));
        assertFalse(HaNotices.same(HaNotices.value(item, NOW), HaNotices.value(changed, NOW)));
        assertFalse(HaNotices.same(null, HaNotices.value(item, NOW)));
        // A Home Assistant notification with that text isn't the integration's
        assertFalse(HaNotices.same(HouseholdNotices.haValue("T", "x", NOW), HaNotices.value(item, NOW)));
    }

    @Test
    public void itGoesFromTheBellWhenItExpires_andOneAlreadyExpiredIsntFiled() throws JSONException {
        long expires = NOW + 60_000;
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "T", "x").put("expires", expires))).get(0);
        HouseholdLog log = new HouseholdLog("tv-a");
        file(log, HouseholdNotices.ALL_ADULTS, item, NOW);
        assertEquals(1, HouseholdNotices.visible(log.all(), ALEX, false, "tv-x", NOW).size());
        assertTrue(HouseholdNotices.visible(log.all(), ALEX, false, "tv-x", expires).isEmpty());
        assertNull(HaNotices.value(item, expires));
    }

    @Test
    public void anotherTvsPressEntryNeverRunsAnIntegrationNotice() throws JSONException {
        HaNotices.Item item = HaNotices.fromDocument(document(notice("k1", "T", "x"))).get(0);
        HouseholdLog log = new HouseholdLog("tv-a");
        HouseholdEntry e = file(log, HouseholdNotices.ALL_ADULTS, item, NOW);
        log.put(HouseholdNotices.PRESS, HouseholdNotices.ALL_ADULTS, e.item,
                HouseholdNotices.pressValue(0, HouseholdLog.millisOf(e)), NOW + 1);
        assertTrue(HouseholdNotices.due(log.all(), "tv-a", NOW + 2).isEmpty());
    }

    @Test
    public void onlyInfoWaitsInTheBellWithoutPoppingUp() {
        assertFalse(HaNotices.popsUp(HaNotices.INFO));
        assertTrue(HaNotices.popsUp(HaNotices.NOTICE));
        assertTrue(HaNotices.popsUp(HaNotices.URGENT));
    }

    // ---- Cleared when gone from the document ----

    @Test
    public void whatAnEarlierDocumentHadAndThisOneDoesnt_isCleared() {
        String a = HaNotices.filed(HouseholdNotices.ALL_ADULTS, "ha:1");
        String b = HaNotices.filed(ALEX, "ha:2");
        String c = HaNotices.filed(ALEX, "ha:3");
        Set<String> gone = HaNotices.gone(new LinkedHashSet<>(Arrays.asList(a, b)),
                new LinkedHashSet<>(Arrays.asList(b, c)));
        assertEquals(Collections.singleton(a), gone);
        assertEquals(HouseholdNotices.ALL_ADULTS, HaNotices.personOf(a));
        assertEquals("ha:1", HaNotices.itemOf(a));
        assertEquals(ALEX, HaNotices.personOf(b));
        // Kept between documents
        Set<String> kept = HaNotices.fromJson(HaNotices.toJson(new LinkedHashSet<>(Arrays.asList(a, b))).toString());
        assertEquals(new LinkedHashSet<>(Arrays.asList(a, b)), kept);
        assertTrue(HaNotices.fromJson("not json").isEmpty());
        assertTrue(HaNotices.fromJson(null).isEmpty());
    }

    // ---- A button pressed ----

    @Test
    public void thePressCarriesThePin_orAsksThePhones() throws JSONException {
        JSONObject withPin = HaNotices.pressBody("k1", "2", "1234");
        assertEquals("k1", withPin.getString("key"));
        assertEquals(2, withPin.getInt("action"));
        assertEquals("1234", withPin.getString("pin"));
        assertFalse(withPin.has("approval"));
        JSONObject phone = HaNotices.pressBody("k1", "0", null);
        assertEquals("phone", phone.getString("approval"));
        assertFalse(phone.has("pin"));
    }

    @Test
    public void theIntegrationsAnswersAreTold() throws JSONException {
        assertEquals(HaNotices.Outcome.DONE,
                HaNotices.outcome(200, new JSONObject().put("ok", true).put("done", true)).outcome);
        assertEquals(HaNotices.Outcome.PENDING,
                HaNotices.outcome(200, new JSONObject().put("ok", true).put("pending", "phone")).outcome);
        assertEquals(HaNotices.Outcome.GONE, HaNotices.outcome(404, new JSONObject().put("error", "gone")).outcome);
        assertEquals(HaNotices.Outcome.TOO_MANY,
                HaNotices.outcome(429, new JSONObject().put("error", "too_many")).outcome);
        assertEquals(HaNotices.Outcome.BAD_REQUEST,
                HaNotices.outcome(400, new JSONObject().put("error", "bad_request")).outcome);
        assertEquals(HaNotices.Outcome.UNREACHABLE, HaNotices.outcome(0, null).outcome);
        assertEquals(HaNotices.Outcome.FAILED,
                HaNotices.outcome(500, new JSONObject().put("error", "failed")).outcome);
        assertEquals(HaNotices.Outcome.FAILED,
                HaNotices.outcome(503, new JSONObject().put("error", "not_set_up")).outcome);
        assertEquals(HaNotices.Outcome.NOT_PAIRED,
                HaNotices.outcome(401, new JSONObject().put("error", "not_paired")).outcome);
        assertEquals(HaNotices.Outcome.FAILED, HaNotices.outcome(200, new JSONObject().put("ok", false)).outcome);
    }

    @Test
    public void aWrongPin_saysHowLongThePadWaits() throws JSONException {
        HaNotices.Result locked = HaNotices.outcome(403,
                new JSONObject().put("error", "wrong_pin").put("retry_after", 60));
        assertEquals(HaNotices.Outcome.WRONG_PIN, locked.outcome);
        assertEquals(60, locked.retryAfterS);
        HaNotices.Result wrong = HaNotices.outcome(403, new JSONObject().put("error", "wrong_pin"));
        assertEquals(HaNotices.Outcome.WRONG_PIN, wrong.outcome);
        assertEquals(0, wrong.retryAfterS);
        // Another refusal isn't a wrong PIN
        assertEquals(HaNotices.Outcome.FAILED,
                HaNotices.outcome(403, new JSONObject().put("error", "not_local")).outcome);
    }

    @Test
    public void a404WithoutGone_isAnOlderIntegrationWithoutTheEndpoint() throws JSONException {
        assertEquals(HaNotices.Outcome.UNSUPPORTED, HaNotices.outcome(404, null).outcome);
        assertEquals(HaNotices.Outcome.UNSUPPORTED,
                HaNotices.outcome(404, new JSONObject().put("message", "Not Found")).outcome);
        assertEquals(HaNotices.Outcome.UNSUPPORTED,
                HaNotices.outcome(404, new JSONObject().put("error", "not_found")).outcome);
    }
}
