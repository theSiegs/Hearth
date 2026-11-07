package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Profile keys: a user's own ("user:0"), and in an adults' user one per other Google account ("user:0:sam");
 * and whose Continue Watching entry is, in a user several profiles share.
 */
public class ProfileKeysTest {
    @Test
    public void anotherAccountGetsAKeyOfItsOwn() {
        assertEquals("user:0", ProfileUsers.accountKey(0, null));
        assertEquals("user:0:sam", ProfileUsers.accountKey(0, "Sam"));
        assertEquals("user:0:sam-lee", ProfileUsers.accountKey(0, "Sam Lee"));
        assertEquals("user:0:zoë", ProfileUsers.accountKey(0, "Zoë"));
        assertNull(ProfileUsers.accountKey(ProfileUsers.UNKNOWN, "Sam"));
        // A name with no letters or digits still gets a key, and a different one per name
        assertTrue(ProfileUsers.slug("☺").startsWith("a"));
        assertNotEquals(ProfileUsers.slug("☺"), ProfileUsers.slug("☺☺"));
    }

    @Test
    public void keysNameTheirUserAndAccount() {
        assertEquals(0, ProfileUsers.serialOfKey("user:0"));
        assertEquals(0, ProfileUsers.serialOfKey("user:0:sam"));
        assertEquals(11, ProfileUsers.serialOfKey("user:11"));
        // Names saved before keys, and anything else
        assertEquals(ProfileUsers.UNKNOWN, ProfileUsers.serialOfKey("Alex"));
        assertEquals(ProfileUsers.UNKNOWN, ProfileUsers.serialOfKey("user:x"));
        assertEquals(ProfileUsers.UNKNOWN, ProfileUsers.serialOfKey(null));
        assertEquals("sam", ProfileUsers.accountOfKey("user:0:sam"));
        assertNull(ProfileUsers.accountOfKey("user:0"));
        assertNull(ProfileUsers.accountOfKey("Alex"));
    }

    @Test
    public void aProfilesHouseholdRefIsItsNameNotItsSerial() {
        // The same kid is user 10 on one TV and user 12 on another: both say who she is the same way
        FakeContext one = new FakeContext("com.thesiegs.hearth");
        FakeContext other = new FakeContext("com.thesiegs.hearth");
        ProfileUsers.setName(one, 10, "Robin Lee");
        ProfileUsers.setName(other, 12, "Robin Lee");
        assertEquals("name:robin-lee", ProfileUsers.householdRef(one, "user:10"));
        assertEquals(ProfileUsers.householdRef(one, "user:10"), ProfileUsers.householdRef(other, "user:12"));
        // Another account in an adults' user carries its own
        assertEquals("name:sam", ProfileUsers.householdRef(one, "user:0:sam"));
        // A profile whose name this TV hasn't learned, and anything that isn't a key
        assertNull(ProfileUsers.householdRef(one, "user:11"));
        assertNull(ProfileUsers.householdRef(one, "Alex"));
        assertNull(ProfileUsers.householdRef(one, null));
    }

    @Test
    public void anAppChangesHandsOnlyWhenAnotherProfileOpensIt() {
        String history = AppWatchers.record(null, 100, "user:0");
        assertEquals("100 user:0", history);
        // The same profile again: nothing new
        assertEquals(history, AppWatchers.record(history, 200, "user:0"));
        history = AppWatchers.record(history, 300, "user:0:sam");
        assertEquals("100 user:0\n300 user:0:sam", history);
    }

    @Test
    public void theRecordKeepsTheLatestHandOvers() {
        String history = null;
        for (int i = 0; i < AppWatchers.MAX_RECORDS + 4; i++) {
            history = AppWatchers.record(history, i * 10L, i % 2 == 0 ? "user:0" : "user:0:sam");
        }
        String[] lines = history.split("\n");
        assertEquals(AppWatchers.MAX_RECORDS, lines.length);
        assertEquals((AppWatchers.MAX_RECORDS + 3) * 10L + " user:0:sam", lines[lines.length - 1]);
    }

    @Test
    public void anEntryIsWhoeverHadItsAppWhenItWasWatched() {
        String history = "100 user:0\n300 user:0:sam\n500 user:11\n700 user:0";
        // Before anyone Hearth saw: unknown (the user's first profile's)
        assertNull(AppWatchers.watcherAt(history, 50, 0));
        assertEquals("user:0", AppWatchers.watcherAt(history, 100, 0));
        assertEquals("user:0", AppWatchers.watcherAt(history, 250, 0));
        assertEquals("user:0:sam", AppWatchers.watcherAt(history, 300, 0));
        // A kid's turn with the app doesn't count for this user's list (the kid's list is the kid's own)
        assertEquals("user:0:sam", AppWatchers.watcherAt(history, 600, 0));
        assertEquals("user:0", AppWatchers.watcherAt(history, 900, 0));
        // No time or no record: unknown
        assertNull(AppWatchers.watcherAt(history, 0, 0));
        assertNull(AppWatchers.watcherAt(null, 900, 0));
    }

    @Test
    public void aClockThatJumpedBackStillFindsTheLatestHandOver() {
        // Out of order (the TV's clock was set back): the latest one at or before the time
        String history = "300 user:0:sam\n100 user:0";
        assertEquals("user:0:sam", AppWatchers.watcherAt(history, 400, 0));
        assertEquals("user:0", AppWatchers.watcherAt(history, 200, 0));
    }

    @Test
    public void theHomeSaysWhoIsLoggedIn() {
        assertEquals("Alex", GoogleTvAccount.accountIn("Logged in as Alex, click to choose an account"));
        assertEquals("Sam Lee", GoogleTvAccount.accountIn("Logged in as Sam Lee, click to choose an account"));
        assertNull(GoogleTvAccount.accountIn("Settings"));
        assertNull(GoogleTvAccount.accountIn(null));
    }

    @Test
    public void theChoosersCurrentAccountNeverNamesAKidsUser() {
        // A kid's user (serial 12) is on and the chooser, which runs in the owner's user, marks an adult's account
        // there current: the kid's user keeps its name, whatever Hearth knows of the adult
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(true, "Robin", true, "Sam", null, 12, 0));
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(true, "Robin", true, "Sam", null, 12,
                ProfileUsers.UNKNOWN));
        // Nor is a kid's user named from it when it has no name yet, or its name left the chooser: picks name it
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(true, null, false, "Sam", null, 12,
                ProfileUsers.UNKNOWN));
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(true, "Robin", false, "Sam", null, 12,
                ProfileUsers.UNKNOWN));
    }

    @Test
    public void theChoosersCurrentAccountNamesAnUnnamedUserUnlessItIsAnothers() {
        // The owner's user with no name yet: its current account names it
        assertNull(LauncherAccessibilityService.whyCurrentDoesNotName(false, null, false, "Alex", null, 0,
                ProfileUsers.UNKNOWN));
        assertNull(LauncherAccessibilityService.whyCurrentDoesNotName(false, null, false, "Alex", null, 0, 0));
        // Supervision unreadable: still not an account Hearth knows as another user's
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(null, "Robin", true, "Alex", null, 12, 0));
        assertNull(LauncherAccessibilityService.whyCurrentDoesNotName(null, "Robin", true, "Alex", null, 12,
                ProfileUsers.UNKNOWN));
        // A just-added profile Google TV marks current before it has started doesn't rename the one running
        assertNotNull(LauncherAccessibilityService.whyCurrentDoesNotName(false, "Alex", true, "Sam", "Sam", 0,
                ProfileUsers.UNKNOWN));
        // ...unless the running one's name is gone from the chooser (renamed)
        assertNull(LauncherAccessibilityService.whyCurrentDoesNotName(false, "Alex", false, "Sam", "Sam", 0,
                ProfileUsers.UNKNOWN));
    }
}
