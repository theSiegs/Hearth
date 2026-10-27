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
    public void aJoinRequestCarriesItsCodeAndWhetherAnAllowGivesHomeAssistant() {
        HouseholdLog asked = new HouseholdLog("tv-a");
        String item = HouseholdNotices.joinItem("r1");
        asked.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, item,
                HouseholdNotices.joinValue("Kitchen", "tv-a", "Office", NOW, NOW + 300_000, "123 456", true), NOW);
        HouseholdNotices.Notice n = HouseholdNotices.visible(asked.all(), ALEX, false, "tv-x", NOW).get(0);
        assertEquals("123 456", n.code);
        assertTrue(n.offersHa);
        // from a TV of an older build: no code, and its Allow asks nothing more
        HouseholdLog older = new HouseholdLog("tv-c");
        older.put(HouseholdNotices.KIND, HouseholdNotices.ALL_ADULTS, HouseholdNotices.joinItem("r2"),
                HouseholdNotices.joinValue("Kitchen", "tv-c", "Study", NOW, NOW + 300_000), NOW);
        HouseholdNotices.Notice o = HouseholdNotices.visible(older.all(), ALEX, false, "tv-x", NOW).get(0);
        assertEquals("", o.code);
        assertFalse(o.offersHa);

        // An Allow says whether the connection goes with it; an older TV's Allow, and a Don't allow, don't give it
        HouseholdLog b = new HouseholdLog("tv-b");
        b.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item, HouseholdNotices.answerValue(true, true), NOW);
        assertEquals(Boolean.TRUE, HouseholdNotices.answer(b.all(), item));
        assertTrue(HouseholdNotices.answerGivesHa(b.all(), item));
        b.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item, HouseholdNotices.answerValue(true, false),
                NOW + 1);
        assertFalse(HouseholdNotices.answerGivesHa(b.all(), item));
        b.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item, HouseholdNotices.answerValue(true), NOW + 2);
        assertEquals(Boolean.TRUE, HouseholdNotices.answer(b.all(), item));
        assertFalse(HouseholdNotices.answerGivesHa(b.all(), item));
        b.put(HouseholdNotices.ANSWER, HouseholdNotices.ALL_ADULTS, item, HouseholdNotices.answerValue(false, true),
                NOW + 3);
        assertEquals(Boolean.FALSE, HouseholdNotices.answer(b.all(), item));
        assertFalse(HouseholdNotices.answerGivesHa(b.all(), item));
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
}
