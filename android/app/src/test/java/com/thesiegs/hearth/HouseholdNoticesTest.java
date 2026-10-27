package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

/** Notifications across the household: who sees them, clearing, expiry, and a join request answered from any TV. */
public class HouseholdNoticesTest {
    private static final long NOW = 1_800_000_000_000L;
    private static final String ALEX = "a:alex";
    private static final String SAM = "a:sam";
    private static final String KID = "a:kid";

    private static HouseholdEntry ha(HouseholdLog log, String person, String tag, String title, String text, long at) {
        return log.put(HouseholdNotices.KIND, person, HouseholdNotices.haItem(person, tag, title, text),
                HouseholdNotices.haValue(title, text, at), at);
    }

    private static List<HouseholdNotices.Notice> seenBy(HouseholdLog log, String person, boolean kids, long now) {
        return HouseholdNotices.visible(log.all(), person, kids, "tv-x", now);
    }

    @Test
    public void aFloodOfNotificationsFromTheNetworkStopsGrowingTheLog() {
        HouseholdLog log = new HouseholdLog("tv-a");
        // another TV's don't count against this one's
        HouseholdLog other = new HouseholdLog("tv-b");
        for (int i = 0; i < 50; i++) log.merge(ha(other, ALEX, null, "Other", "n" + i, NOW), NOW);
        int kept = 0;
        for (int i = 0; i < HouseholdNotices.MAX_FROM_TV + 200; i++) {
            String item = HouseholdNotices.haItem(HouseholdNotices.ALL_ADULTS, null, "Spam", "n" + i);
            if (!HouseholdNotices.roomFor(log.all(), "tv-a", item)) continue;
            ha(log, HouseholdNotices.ALL_ADULTS, null, "Spam", "n" + i, NOW + i);
            kept++;
        }
        assertEquals(HouseholdNotices.MAX_FROM_TV, kept);
        assertEquals(HouseholdNotices.MAX_FROM_TV + 50, log.all().size());
        // one already held (a tag sent again, the same text again) still replaces itself
        assertTrue(HouseholdNotices.roomFor(log.all(), "tv-a",
                HouseholdNotices.haItem(HouseholdNotices.ALL_ADULTS, null, "Spam", "n0")));
        // and once they leave the log, there is room again
        log.purge(NOW + HouseholdNotices.MAX_AGE_MS + HouseholdNotices.MAX_FROM_TV + 1);
        assertTrue(HouseholdNotices.roomFor(log.all(), "tv-a", HouseholdNotices.haItem(ALEX, null, "New", "x")));
    }

    @Test
    public void oneForEveryAdultShowsToEachAdult_butNotToAKid() {
        HouseholdLog log = new HouseholdLog("tv-a");
        ha(log, HouseholdNotices.ALL_ADULTS, null, "Washer", "The wash is done", NOW);
        assertEquals(1, seenBy(log, ALEX, false, NOW).size());
        assertEquals(1, seenBy(log, SAM, false, NOW).size());
        assertEquals("The wash is done", seenBy(log, SAM, false, NOW).get(0).text);
        assertTrue(seenBy(log, KID, true, NOW).isEmpty());
    }

    @Test
    public void oneForAPersonShowsOnlyToThem() {
        HouseholdLog log = new HouseholdLog("tv-a");
        ha(log, ALEX, null, "Parcel", "Your parcel came", NOW);
        assertEquals(1, seenBy(log, ALEX, false, NOW).size());
        assertTrue(seenBy(log, SAM, false, NOW).isEmpty());
        assertTrue(seenBy(log, KID, true, NOW).isEmpty());
        // Nor to a profile Hearth can't name yet
        assertTrue(seenBy(log, null, false, NOW).isEmpty());
    }

    @Test
    public void oneForAKidShowsToThatKidOnly() {
        HouseholdLog log = new HouseholdLog("tv-a");
        ha(log, KID, null, "Dinner", "Dinner is ready", NOW);
        assertEquals(1, seenBy(log, KID, true, NOW).size());
        assertTrue(seenBy(log, ALEX, false, NOW).isEmpty());
    }

    @Test
    public void receivedOnOneTvShowsOnTheOther_andClearedOnOneIsClearedOnBoth() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        HouseholdEntry sent = ha(a, ALEX, null, "Parcel", "Your parcel came", NOW);
        assertTrue(b.merge(sent, NOW));
        assertEquals(1, seenBy(b, ALEX, false, NOW).size());

        HouseholdEntry cleared = b.delete(HouseholdNotices.KIND, ALEX, sent.item, NOW + 1000);
        assertTrue(a.merge(cleared, NOW + 1000));
        assertTrue(seenBy(a, ALEX, false, NOW + 1000).isEmpty());
        assertTrue(seenBy(b, ALEX, false, NOW + 1000).isEmpty());
        // The clear doesn't lose to the older notification coming round again
        assertFalse(b.merge(sent, NOW + 2000));
    }

    @Test
    public void theSameNotificationSentToEveryTvIsOne_andComesBackWhenSentAgainAfterAClear() {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        HouseholdEntry fromA = ha(a, HouseholdNotices.ALL_ADULTS, null, "Doorbell", "Someone is at the door", NOW);
        HouseholdEntry fromB = ha(b, HouseholdNotices.ALL_ADULTS, null, "Doorbell", "Someone is at the door", NOW + 5);
        assertEquals(fromA.id(), fromB.id());
        a.merge(fromB, NOW + 10);
        assertEquals(1, seenBy(a, ALEX, false, NOW + 10).size());

        a.delete(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, fromA.item, NOW + 20);
        assertTrue(seenBy(a, ALEX, false, NOW + 20).isEmpty());
        ha(a, HouseholdNotices.ALL_ADULTS, null, "Doorbell", "Someone is at the door", NOW + 60_000);
        assertEquals(1, seenBy(a, ALEX, false, NOW + 60_000).size());
    }

    @Test
    public void aTagNamesTheNotification_soALaterOneReplacesIt() {
        String first = HouseholdNotices.haItem(ALEX, "laundry", "Washer", "Running");
        String later = HouseholdNotices.haItem(ALEX, "laundry", "Washer", "Done");
        assertEquals(first, later);
        assertNotEquals(first, HouseholdNotices.haItem(SAM, "laundry", "Washer", "Done"));
        assertNotEquals(HouseholdNotices.haItem(ALEX, null, "Washer", "Running"),
                HouseholdNotices.haItem(ALEX, null, "Washer", "Done"));
        // A clear names it by its tag alone
        assertEquals(first, HouseholdNotices.haItem(ALEX, "laundry", null, null));
        assertFalse(first.contains("laundry"));
    }

    @Test
    public void aNotificationWithNothingToSayIsntOne_andLongTextIsCut() {
        assertNull(HouseholdNotices.haValue(null, "  ", NOW));
        HouseholdLog log = new HouseholdLog("tv-a");
        char[] lots = new char[5000];
        Arrays.fill(lots, 'x');
        ha(log, ALEX, null, "Long", new String(lots), NOW);
        assertEquals(HouseholdNotices.MAX_TEXT, seenBy(log, ALEX, false, NOW).get(0).text.length());
    }

    @Test
    public void notificationsGoAfterTheirTime_fromTheBellAndThenFromTheLog() {
        HouseholdLog log = new HouseholdLog("tv-a");
        HouseholdEntry kept = ha(log, ALEX, null, "Old", "An old one", NOW);
        HouseholdEntry gone = ha(log, ALEX, null, "Cleared", "A cleared one", NOW);
        log.delete(HouseholdNotices.KIND, ALEX, gone.item, NOW + 60_000);
        long later = NOW + HouseholdNotices.MAX_AGE_MS + 1;
        assertTrue(seenBy(log, ALEX, false, later).isEmpty());
        assertEquals(1, log.purge(later));
        assertNull(log.entry(HouseholdNotices.KIND, ALEX, kept.item));
        // The clear is newer than what it cleared, so it stays as long as that could come back
        assertNotNull(log.entry(HouseholdNotices.KIND, ALEX, gone.item));
        assertEquals(1, log.purge(NOW + 60_000 + HouseholdNotices.MAX_AGE_MS + 1));
    }

    @Test
    public void anotherTvsJoinRequestShowsToAdults_notOnTheTvItAsked_norToKids() {
        HouseholdLog asked = new HouseholdLog("tv-a");
        HouseholdEntry request = asked.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS,
                HouseholdNotices.joinItem("r1"), HouseholdNotices.joinValue("Kitchen", "tv-a", "Office", NOW,
                        NOW + HouseholdJoining.ANSWER_MS), NOW);
        HouseholdLog other = new HouseholdLog("tv-b");
        other.merge(request, NOW);

        List<HouseholdNotices.Notice> seen = HouseholdNotices.visible(other.all(), ALEX, false, "tv-b", NOW);
        assertEquals(1, seen.size());
        assertTrue(seen.get(0).isJoin());
        assertEquals("Kitchen", seen.get(0).joiner);
        assertEquals("Office", seen.get(0).askedName);
        assertTrue(HouseholdNotices.visible(other.all(), KID, true, "tv-b", NOW).isEmpty());
        // The TV it asked shows its own Bell item instead
        assertTrue(HouseholdNotices.visible(asked.all(), ALEX, false, "tv-a", NOW).isEmpty());
        // It ends when its time runs out, if the asked TV never says
        assertTrue(HouseholdNotices.visible(other.all(), ALEX, false, "tv-b",
                NOW + HouseholdJoining.ANSWER_MS).isEmpty());
    }

    @Test
    public void aJoinRequestIsDecidedOnce_byTheFirstAnswerTheAskedTvHears() {
        HouseholdLog asked = new HouseholdLog("tv-a");
        String item = HouseholdNotices.joinItem("r1");
        HouseholdEntry request = asked.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, item,
                HouseholdNotices.joinValue("Kitchen", "tv-a", "Office", NOW, NOW + 300_000), NOW);
        HouseholdLog b = new HouseholdLog("tv-b");
        b.merge(request, NOW);
        assertNull(HouseholdNotices.answer(asked.all(), item));

        HouseholdEntry allow = b.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item,
                HouseholdNotices.answerValue(true), NOW + 1000);
        // Answered: it leaves the Bell where it was answered
        assertTrue(HouseholdNotices.visible(b.all(), ALEX, false, "tv-b", NOW + 1000).isEmpty());
        asked.merge(allow, NOW + 1000);
        assertEquals(Boolean.TRUE, HouseholdNotices.answer(asked.all(), item));
        // Another request's answer isn't this one's
        assertNull(HouseholdNotices.answer(asked.all(), HouseholdNotices.joinItem("r2")));
    }

    @Test
    public void aJoinRequestMustBeForEveryAdult_andWrittenByTheTvItAsked() {
        HouseholdLog log = new HouseholdLog("tv-b");
        log.put(HouseholdNotices.KIND, ALEX, HouseholdNotices.joinItem("r1"),
                HouseholdNotices.joinValue("Kitchen", "tv-b", "Office", NOW, NOW + 300_000), NOW);
        log.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, HouseholdNotices.joinItem("r2"),
                HouseholdNotices.joinValue("Kitchen", "tv-a", "Office", NOW, NOW + 300_000), NOW);
        assertTrue(HouseholdNotices.visible(log.all(), ALEX, false, "tv-x", NOW).isEmpty());
    }

    @Test
    public void whoANotificationIsFor_byKeyAddressOrName() {
        List<HouseholdNotices.Person> people = Arrays.asList(
                new HouseholdNotices.Person("user:0:alex", ALEX, "Alex", "alex@example.com"),
                new HouseholdNotices.Person("user:10", KID, "Robin", null),
                new HouseholdNotices.Person("user:0:sam", SAM, "Sam", "sam@example.com"));
        assertEquals(KID, HouseholdNotices.target("user:10", people));
        assertEquals(ALEX, HouseholdNotices.target("Alex@Example.com", people));
        assertEquals(SAM, HouseholdNotices.target(" sam ", people));
        assertNull(HouseholdNotices.target("Jordan", people));
        assertNull(HouseholdNotices.target("", people));

        // Two profiles of one name: neither, rather than the wrong one
        List<HouseholdNotices.Person> twins = Arrays.asList(
                new HouseholdNotices.Person("user:0:a", ALEX, "Alex", null),
                new HouseholdNotices.Person("user:0:b", SAM, "Alex", null));
        assertNull(HouseholdNotices.target("Alex", twins));
    }

    @Test
    public void homeAssistantSaysWhoItsFor_andCanClearByTag_withTheButtonsAllowlistAsBefore() {
        String body = "title=Parcel&msg=Your%20parcel%20came&for=Alex&tag=parcel&actions="
                + "%5B%7B%22title%22%3A%22Unlock%22%2C%22service%22%3A%22lock.unlock%22%7D%2C"
                + "%7B%22title%22%3A%22Bad%22%2C%22service%22%3A%22rm%20-rf%22%7D%5D";
        HaNotificationServer.Notification n = HaNotificationServer.parse("application/x-www-form-urlencoded",
                body.getBytes(StandardCharsets.UTF_8));
        assertEquals("Alex", n.target);
        assertEquals("parcel", n.tag);
        assertFalse(n.clears());
        assertEquals(1, n.actions.size());

        HaNotificationServer.Notification clear = HaNotificationServer.parse("application/x-www-form-urlencoded",
                "msg=clear_notification&tag=parcel".getBytes(StandardCharsets.UTF_8));
        assertTrue(clear.clears());
        assertNull(clear.target);

        HaNotificationServer.Notification plain = HaNotificationServer.parse("application/x-www-form-urlencoded",
                "msg=clear_notification".getBytes(StandardCharsets.UTF_8));
        assertFalse(plain.clears());
    }

    // ---- Its buttons, on every TV ----

    private static JSONObject button(String title, String service, JSONObject data) throws JSONException {
        JSONObject b = new JSONObject().put("title", title).put("service", service);
        if (data != null) b.put("data", data);
        return b;
    }

    private static HouseholdEntry withButtons(HouseholdLog log, String person, String tag, long at)
            throws JSONException {
        List<JSONObject> buttons = Arrays.asList(
                button("Unlock door", "lock.unlock", new JSONObject().put("entity_id", "lock.front")),
                button("Ignore", "script.turn_on", null));
        return log.put(HouseholdNotices.KIND, person, HouseholdNotices.haItem(person, tag, "Doorbell", "At the door"),
                HouseholdNotices.haValue("Doorbell", "At the door", buttons, at), at);
    }

    /** A notification's value as another (or a tampered) TV could write it, with these buttons. */
    private static String valueWith(JSONArray buttons) throws JSONException {
        return new JSONObject().put("f", HouseholdNotices.FROM_HA).put("ti", "Doorbell").put("tx", "At the door")
                .put("at", NOW).put("u", NOW + HouseholdNotices.MAX_AGE_MS).put("ac", buttons).toString();
    }

    private static JSONObject carriedButton(String title, String service, String data) throws JSONException {
        return new JSONObject().put("ti", title).put("s", service).put("d", data);
    }

    private static int buttonsSeen(String value) {
        HouseholdLog log = new HouseholdLog("tv-b");
        log.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, "ha:x", value, NOW);
        List<HouseholdNotices.Notice> seen = seenBy(log, ALEX, false, NOW);
        return seen.isEmpty() ? -1 : seen.get(0).actions.size();
    }

    @Test
    public void theButtonsGoToEveryTv_withTheirTitlesAndWhatTheyCall() throws JSONException {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        b.merge(withButtons(a, HouseholdNotices.ALL_ADULTS, "door", NOW), NOW);
        List<HouseholdNotices.Notice> seen = seenBy(b, ALEX, false, NOW);
        assertEquals(1, seen.size());
        assertEquals(2, seen.get(0).actions.size());
        HouseholdNotices.Action unlock = seen.get(0).actions.get(0);
        assertEquals("Unlock door", unlock.title);
        assertEquals("lock.unlock", unlock.service);
        assertEquals("lock.front", unlock.dataObject().getString("entity_id"));
        assertEquals("Ignore", seen.get(0).actions.get(1).title);
        assertEquals(0, seen.get(0).actions.get(1).dataObject().length());
        // Kids still never see a notification for every adult, buttons or not
        assertTrue(seenBy(b, KID, true, NOW).isEmpty());
    }

    @Test
    public void buttonsThatCantAllTravelDontTravel_soTheirNumbersMatchThePopUp() throws JSONException {
        char[] lots = new char[HouseholdNotices.MAX_ACTION_DATA + 10];
        Arrays.fill(lots, 'x');
        JSONObject big = new JSONObject().put("entity_id", new String(lots));
        assertTrue(HouseholdNotices.carried(Arrays.asList(button("Ok", "light.toggle", null),
                button("Big", "light.toggle", big))).isEmpty());
        assertTrue(HouseholdNotices.carried(Arrays.asList(button("1", "a.b", null), button("2", "a.b", null),
                button("3", "a.b", null), button("4", "a.b", null))).isEmpty());
        assertTrue(HouseholdNotices.carried(null).isEmpty());
        assertEquals(1, HouseholdNotices.carried(Arrays.asList(button("Ok", "light.toggle", null))).size());
    }

    @Test
    public void aReceivedEntryCantWidenWhatCanBeCalled() throws JSONException {
        // Well formed: shown with its button
        assertEquals(1, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Unlock", "lock.unlock", "{}")))));
        // Not a service Home Assistant's own notification could name: the notification shows without buttons
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Bad", "rm -rf", "{}")))));
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Bad", "lock.unlock/../x", "{}")))));
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton(" ", "lock.unlock", "{}")))));
        // Data that isn't an object, or is too long
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Unlock", "lock.unlock", "[1]")))));
        char[] lots = new char[HouseholdNotices.MAX_ACTION_DATA + 10];
        Arrays.fill(lots, 'x');
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Unlock", "lock.unlock",
                new JSONObject().put("e", new String(lots)).toString())))));
        // More than Home Assistant may send, or one bad among good ones: none, so no button moves to another number
        JSONArray four = new JSONArray();
        for (int i = 0; i < 4; i++) four.put(carriedButton("B" + i, "light.toggle", "{}"));
        assertEquals(0, buttonsSeen(valueWith(four)));
        assertEquals(0, buttonsSeen(valueWith(new JSONArray().put(carriedButton("Ok", "light.toggle", "{}"))
                .put(carriedButton("Bad", "nope", "{}")))));
        // Not a list at all
        assertEquals(0, buttonsSeen(new JSONObject(valueWith(new JSONArray())).put("ac", "lock.unlock").toString()));
    }

    @Test
    public void homeAssistantsOwnButtonsAreCheckedTheSameWay() throws JSONException {
        assertTrue(HaNotificationServer.allowedAction(button("Unlock", "lock.unlock", null)));
        assertTrue(HaNotificationServer.allowedAction(button("Unlock", "lock.unlock", new JSONObject())));
        assertFalse(HaNotificationServer.allowedAction(button("Unlock", "lock", null)));
        assertFalse(HaNotificationServer.allowedAction(button("", "lock.unlock", null)));
        assertFalse(HaNotificationServer.allowedAction(new JSONObject().put("title", "x").put("service", "a.b")
                .put("data", "not an object")));
        assertFalse(HaNotificationServer.allowedAction(null));
    }

    @Test
    public void aButtonPressedOnAnotherTvRunsOnce_onTheTvThatReceivedIt_andGoesFromEveryBell() throws JSONException {
        HouseholdLog a = new HouseholdLog("tv-a"); // received it from Home Assistant
        HouseholdLog b = new HouseholdLog("tv-b"); // no Home Assistant connection of its own
        HouseholdEntry notice = withButtons(a, HouseholdNotices.ALL_ADULTS, "door", NOW);
        b.merge(notice, NOW);
        HouseholdNotices.Notice seen = seenBy(b, ALEX, false, NOW).get(0);
        assertEquals(-1, HouseholdNotices.pressed(b.all(), seen));

        HouseholdEntry press = b.put(HouseholdNotices.PRESS, seen.person, seen.item,
                HouseholdNotices.pressValue(0, seen.at), NOW + 1000);
        // Pressed: it leaves the Bell where it was pressed at once
        assertTrue(seenBy(b, ALEX, false, NOW + 1000).isEmpty());
        assertEquals(0, HouseholdNotices.pressed(b.all(), seen));
        // Only the TV that wrote it runs it
        assertTrue(HouseholdNotices.due(b.all(), "tv-b", NOW + 1000).isEmpty());

        a.merge(press, NOW + 2000);
        List<HouseholdNotices.Due> due = HouseholdNotices.due(a.all(), "tv-a", NOW + 2000);
        assertEquals(1, due.size());
        assertEquals("lock.unlock", due.get(0).action.service);
        assertEquals("lock.front", due.get(0).action.dataObject().getString("entity_id"));
        assertEquals(notice.item, due.get(0).notice.item);

        // It deletes the notification before running it: nothing is due again, and the delete clears every Bell
        HouseholdEntry cleared = a.delete(HouseholdNotices.KIND, due.get(0).notice.person, due.get(0).notice.item,
                NOW + 2000);
        assertTrue(HouseholdNotices.due(a.all(), "tv-a", NOW + 3000).isEmpty());
        b.merge(cleared, NOW + 3000);
        assertTrue(seenBy(a, ALEX, false, NOW + 3000).isEmpty());
        assertTrue(seenBy(b, ALEX, false, NOW + 3000).isEmpty());
        // A second press anywhere, coming round again, changes nothing
        a.merge(b.put(HouseholdNotices.PRESS, seen.person, seen.item, HouseholdNotices.pressValue(1, seen.at),
                NOW + 4000), NOW + 4000);
        assertTrue(HouseholdNotices.due(a.all(), "tv-a", NOW + 4000).isEmpty());
        // And the press leaves the log with the notification
        assertTrue(HouseholdNotices.expired(press, NOW + 1000 + HouseholdNotices.MAX_AGE_MS + 1));
    }

    @Test
    public void aPressNamesTheButtonByNumber_onlyInTheNotificationItWasPressedFor() throws JSONException {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        HouseholdEntry first = withButtons(a, ALEX, "door", NOW);
        b.merge(first, NOW);
        long firstAt = HouseholdLog.millisOf(first);
        // A button that isn't there runs nothing
        HouseholdEntry wrong = b.put(HouseholdNotices.PRESS, ALEX, first.item, HouseholdNotices.pressValue(5, firstAt),
                NOW + 100);
        a.merge(wrong, NOW + 100);
        assertTrue(HouseholdNotices.due(a.all(), "tv-a", NOW + 100).isEmpty());

        // The same tag sent again replaces it: a press for the older one is no press of the new one
        HouseholdEntry second = withButtons(a, ALEX, "door", NOW + 10_000);
        assertEquals(first.item, second.item);
        a.merge(b.put(HouseholdNotices.PRESS, ALEX, first.item, HouseholdNotices.pressValue(0, firstAt), NOW + 11_000),
                NOW + 11_000);
        assertTrue(HouseholdNotices.due(a.all(), "tv-a", NOW + 11_000).isEmpty());
        assertEquals(1, seenBy(a, ALEX, false, NOW + 11_000).size());
    }

    @Test
    public void aPressHeardLongAfterOnlyClearsTheNotification() throws JSONException {
        HouseholdLog a = new HouseholdLog("tv-a");
        HouseholdLog b = new HouseholdLog("tv-b");
        HouseholdEntry notice = withButtons(a, HouseholdNotices.ALL_ADULTS, "door", NOW);
        b.merge(notice, NOW);
        HouseholdEntry press = b.put(HouseholdNotices.PRESS, HouseholdNotices.ALL_ADULTS, notice.item,
                HouseholdNotices.pressValue(0, HouseholdLog.millisOf(notice)), NOW + 1000);
        long later = NOW + 1000 + HouseholdNotices.PRESS_MS + 1;
        a.merge(press, later);
        List<HouseholdNotices.Due> due = HouseholdNotices.due(a.all(), "tv-a", later);
        assertEquals(1, due.size());
        assertNull(due.get(0).action);
    }
}
