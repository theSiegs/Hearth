package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** Whose calendars on the TV a profile shows, and the chooser's account addresses they're picked by. */
public class TvCalendarsTest {
    private static TvCalendars.Cal cal(long id, String account, boolean shown) {
        return new TvCalendars.Cal(id, account, "Calendar " + id, 0xFF3366CC, shown, shown, false);
    }

    // The second adult's account synced first here, to show the first account goes by the store's order
    private final List<TvCalendars.Cal> all = Arrays.asList(
            cal(3, "alex@example.com", true),
            cal(4, "alex@example.com", false),
            cal(1, "sam.rivera@example.com", false),
            cal(2, "sam.rivera@example.com", true),
            cal(5, "family@example.com", true));

    @Test
    public void aKnownAccountShowsItsOwnCalendarsOnly() {
        String account = TvCalendars.chooseAccount(all, "ALEX@example.com", "Sam");
        assertEquals("alex@example.com", account);
        List<TvCalendars.Cal> shown = TvCalendars.shown(all, account);
        assertEquals(1, shown.size());
        assertEquals(3, shown.get(0).id);
    }

    @Test
    public void aKnownAccountWithoutCalendarsShowsNone() {
        String account = TvCalendars.chooseAccount(all, "jo@example.com", "Jo");
        assertTrue(TvCalendars.shown(all, account).isEmpty());
    }

    @Test
    public void anUnknownAccountGoesByTheProfilesFirstName() {
        assertEquals("sam.rivera@example.com", TvCalendars.chooseAccount(all, null, "Sam Rivera"));
        assertEquals("alex@example.com", TvCalendars.chooseAccount(all, null, "Alex"));
    }

    @Test
    public void otherwiseTheTvsFirstAccount() {
        // No name, a name no address starts with, or one that fits two accounts
        assertEquals("sam.rivera@example.com", TvCalendars.chooseAccount(all, null, null));
        assertEquals("sam.rivera@example.com", TvCalendars.chooseAccount(all, null, "Profile 0"));
        List<TvCalendars.Cal> twoAlexes = new ArrayList<>(all);
        twoAlexes.add(cal(9, "alex.r@example.com", true));
        assertEquals("sam.rivera@example.com", TvCalendars.chooseAccount(twoAlexes, null, "Alex"));
        assertNull(TvCalendars.chooseAccount(Collections.emptyList(), null, "Alex"));
    }

    @Test
    public void onlyCalendarsThatSyncAndShow() {
        List<TvCalendars.Cal> shown = TvCalendars.shown(all, null);
        assertEquals(3, shown.size());
        for (TvCalendars.Cal cal : shown) assertTrue(cal.visible && cal.synced);
    }

    @Test
    public void aCalendarsKeyIsTheSameOnEveryTvWithItsAccount() {
        String key = TvCalendars.keyOf("alex@example.com", "com.google", "family01@group.calendar.google.com",
                "Family");
        assertTrue(key.matches("cal:[0-9a-f]{32}"));
        // Another TV: another row in its store, the address's case, a renamed calendar
        assertEquals(key, TvCalendars.keyOf(" Alex@Example.com", "com.google", "FAMILY01@group.calendar.google.com",
                "Kitchen"));
        // Another account with the same calendar, another account type, another calendar
        assertNotEquals(key, TvCalendars.keyOf("sam@example.com", "com.google", "family01@group.calendar.google.com",
                "Family"));
        assertNotEquals(key, TvCalendars.keyOf("alex@example.com", "LOCAL", "family01@group.calendar.google.com",
                "Family"));
        assertNotEquals(key, TvCalendars.keyOf("alex@example.com", "com.google", "alex@example.com", "Family"));
        // Without an owner account, by its name
        assertEquals(TvCalendars.keyOf("alex@example.com", "LOCAL", null, "Chores"),
                TvCalendars.keyOf("alex@example.com", "LOCAL", "", " Chores "));
        assertNotEquals(TvCalendars.keyOf("alex@example.com", "LOCAL", null, "Chores"),
                TvCalendars.keyOf("alex@example.com", "LOCAL", null, "Birthdays"));
        // It names no account in the clear
        assertFalse(key.contains("alex"));
    }

    @Test
    public void flutterGetsTheKeyWithTheId() {
        TvCalendars.Cal cal = new TvCalendars.Cal(12, "alex@example.com", "Family", 0, true, true, false, "cal:ab");
        assertEquals(12L, cal.toMap().get("id"));
        assertEquals("cal:ab", cal.toMap().get("key"));
    }

    @Test
    public void firstNames() {
        assertEquals("alex", TvCalendars.firstName(" Alex Rivera"));
        assertEquals("zoë", TvCalendars.firstName("Zoë"));
        assertEquals("", TvCalendars.firstName(null));
    }

    @Test
    public void eventsInARange() {
        assertTrue(TvCalendars.overlaps(100, 200, 150, 300));
        assertFalse(TvCalendars.overlaps(100, 150, 150, 300));
        assertFalse(TvCalendars.overlaps(300, 400, 150, 300));
        // No length: in it when it's at a time in it
        assertTrue(TvCalendars.overlaps(150, 150, 150, 300));
        assertFalse(TvCalendars.overlaps(300, 300, 150, 300));
    }

    @Test
    public void theChooserTileNamesTheAccount() {
        assertEquals("alex@example.com", GoogleTvAccount.emailIn(
                "Alex Rivera, alex@example.com, : select to continue with current account"));
        assertEquals("sam.rivera+tv@example.co.uk", GoogleTvAccount.emailIn(
                "Sam Rivera, sam.rivera+tv@example.co.uk, : select to log in"));
        assertNull(GoogleTvAccount.emailIn("Add account"));
        assertNull(GoogleTvAccount.emailIn(null));
    }
}
