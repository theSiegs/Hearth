package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.Test;

/** Hearth's own watch history: whose a Watch Next entry is, and what was played that shows on its own. */
public class WatchHistoryTest {
    private static final long HOUR = 60 * 60_000L;
    private static final long NOW = 1_800_000_000_000L;

    private static WatchHistory.Entry played(String profile, String pkg, String title, String subtitle, long duration,
            long position, long lastAt) {
        return new WatchHistory.Entry(1, WatchHistory.PLAYED, profile, pkg,
                WatchHistory.playedItem(title, subtitle), title, subtitle, duration, position, lastAt, null, 0);
    }

    @Test
    public void titlesMatchWhateverTheirPunctuationAndCase() {
        assertEquals("normalpeople", WatchHistory.norm("Normal People"));
        assertEquals("s1e9episode9", WatchHistory.norm("S1:E9 Episode 9"));
        assertTrue(WatchHistory.sameTitle("Normal People", "S1:E9 Episode 9", "normal people"));
        // Some apps put the episode where the title goes
        assertTrue(WatchHistory.sameTitle("Normal People", "Episode 9", "Episode 9"));
        assertFalse(WatchHistory.sameTitle("Normal People", null, "Normal Heart"));
        assertFalse(WatchHistory.sameTitle("Normal People", null, ""));
        // The app's list names show and episode together; what played names them apart
        assertTrue(WatchHistory.sameTitle("The Long Road", "Normal People", "Normal People - The Long Road"));
        assertTrue(WatchHistory.sameTitle("Normal People", null, "Normal People: Episode 9"));
        assertFalse(WatchHistory.sameTitle("The Long Road", "Other Show", "Normal People - The Long Road"));
        assertFalse(WatchHistory.sameTitle("Up", null, "Updates"));
    }

    @Test
    public void theProfileThatPlayedItOwnsTheEntry() {
        List<WatchHistory.Entry> history = Arrays.asList(
                played("user:0", "com.disney.disneyplus", "Normal People", "S1:E9", 0, 0, NOW - 3 * HOUR),
                played("user:0:sam", "com.disney.disneyplus", "Bluey", "S2:E1", 0, 0, NOW - HOUR));
        assertEquals("user:0", WatchHistory.playedOwner(history, "com.disney.disneyplus", "Normal People", NOW - 3 * HOUR));
        assertEquals("user:0:sam", WatchHistory.playedOwner(history, "com.disney.disneyplus", "Bluey", NOW - HOUR));
        // Another app, or a title nobody played here: not known from this
        assertNull(WatchHistory.playedOwner(history, "com.hulu.livingroomplus", "Bluey", NOW - HOUR));
        assertNull(WatchHistory.playedOwner(history, "com.disney.disneyplus", "Andor", NOW));
        // Played long before the entry's time: someone else may have watched it since
        assertNull(WatchHistory.playedOwner(history, "com.disney.disneyplus", "Normal People", NOW + 2 * 24 * HOUR));
    }

    @Test
    public void bothWatchedIt_theOneClosestInTimeOwnsIt() {
        List<WatchHistory.Entry> history = Arrays.asList(
                played("user:0", "com.netflix.ninja", "Dark", "S1:E1", 0, 0, NOW - 5 * HOUR),
                played("user:0:sam", "com.netflix.ninja", "Dark", "S1:E4", 0, 0, NOW - HOUR));
        assertEquals("user:0:sam", WatchHistory.playedOwner(history, "com.netflix.ninja", "Dark", NOW - HOUR));
        assertEquals("user:0", WatchHistory.playedOwner(history, "com.netflix.ninja", "Dark", NOW - 5 * HOUR));
    }

    @Test
    public void anotherProfilePickingTheAppUpAfterThePlayOwnsTheEntry() {
        String tube = "com.thesiegs.hearthtube";
        // The owner watched a video this afternoon; Sam opened the app tonight and watched it again, too briefly for
        // Hearth to count, and the app moved its one entry for the video to then
        List<WatchHistory.Entry> history = Arrays.asList(
                played("user:0", tube, "Cats Being Cats", "Alex's channel", 0, 0, NOW - 5 * HOUR));
        String watchers = "1000 user:0\n" + (NOW - 10 * 60_000) + " user:0:sam";
        assertEquals("user:0:sam", WatchHistory.ownerOf(history, watchers, tube, "Cats Being Cats", NOW, 0));
        // Nobody else opened the app since the play: still the owner's
        String ownerOnly = "1000 user:0";
        assertEquals("user:0", WatchHistory.ownerOf(history, ownerOnly, tube, "Cats Being Cats", NOW, 0));
        // Sam had the app before the owner's play: the play says whose it is
        String samBefore = "1000 user:0:sam\n" + (NOW - 6 * HOUR) + " user:0";
        assertEquals("user:0", WatchHistory.ownerOf(history, samBefore, tube, "Cats Being Cats", NOW - 5 * HOUR, 0));
        // Sam came and went, and the owner opened the app again before the entry's time: the owner's
        String backAgain = "1000 user:0\n" + (NOW - 2 * HOUR) + " user:0:sam\n" + (NOW - HOUR) + " user:0";
        assertEquals("user:0", WatchHistory.ownerOf(history, backAgain, tube, "Cats Being Cats", NOW, 0));
        // Nothing played: whoever had the app; nothing known at all: null
        assertEquals("user:0:sam", WatchHistory.ownerOf(history, watchers, tube, "Another Video", NOW, 0));
        assertNull(WatchHistory.ownerOf(history, null, tube, "Another Video", NOW, 0));
        // A kids profile's record (another user) doesn't take it
        String kid = "1000 user:0\n" + (NOW - 10 * 60_000) + " user:10";
        assertEquals("user:0", WatchHistory.ownerOf(history, kid, tube, "Cats Being Cats", NOW, 0));
    }

    @Test
    public void changedHandsLooksBetweenTheTwoTimes() {
        String history = "100 user:0\n300 user:0:sam\n500 user:10";
        assertTrue(AppWatchers.changedHands(history, 200, 300, 0));
        assertFalse(AppWatchers.changedHands(history, 300, 400, 0));
        // Another user's profile
        assertFalse(AppWatchers.changedHands(history, 400, 600, 0));
        assertFalse(AppWatchers.changedHands(history, 400, 200, 0));
        assertFalse(AppWatchers.changedHands(null, 0, 600, 0));
    }

    @Test
    public void onlyAShowOrFilmPartWayThroughShowsOnItsOwn() {
        long minute = 60_000;
        assertTrue(WatchHistory.showsOnItsOwn(played("user:0", "p", "Film", null, 100 * minute, 30 * minute, NOW), NOW));
        // A trailer or a clip
        assertFalse(WatchHistory.showsOnItsOwn(played("user:0", "p", "Trailer", null, 2 * minute, minute, NOW), NOW));
        // Barely started, finished, or live (no length)
        assertFalse(WatchHistory.showsOnItsOwn(played("user:0", "p", "Film", null, 100 * minute, 20_000, NOW), NOW));
        assertFalse(WatchHistory.showsOnItsOwn(played("user:0", "p", "Film", null, 100 * minute, 98 * minute, NOW), NOW));
        assertFalse(WatchHistory.showsOnItsOwn(played("user:0", "p", "News", null, 0, 30 * minute, NOW), NOW));
        // Too long ago
        assertFalse(WatchHistory.showsOnItsOwn(
                played("user:0", "p", "Film", null, 100 * minute, 30 * minute, NOW - WatchHistory.MAX_AGE_MS - 1), NOW));
    }

    @Test
    public void anEntryIsKeptByTheAppsOwnIdElseItsTitle() {
        Map<String, Object> row = new HashMap<>();
        row.put("title", "Dark");
        row.put("internalId", "80100172");
        assertEquals("id:80100172", WatchHistory.keptItem(row));
        row.put("internalId", "");
        assertEquals("title:dark", WatchHistory.keptItem(row));
    }

    @Test
    public void openedSinceLooksForThatProfileAfterTheTime() {
        String history = "100 user:0\n300 user:0:sam\n500 user:0";
        assertTrue(AppWatchers.openedSince(history, "user:0", 400));
        assertFalse(AppWatchers.openedSince(history, "user:0:sam", 400));
        assertFalse(AppWatchers.openedSince(null, "user:0", 0));
    }
}
