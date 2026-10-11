package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
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

    // The second grown-up's account synced first here, to show the first account goes by the store's order
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
