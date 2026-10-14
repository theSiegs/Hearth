package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.Test;

/** How Hearth tells a kids profile's screen time: from its apps, from Google TV's windows, from the screen's text. */
public class ScreenTimeStateTest {
    private static final String WELLBEING =
            "com.google.android.apps.tv.launcherx.kids.wellbeing.timeupdialog.ui.KidsTimeUpActivity";
    private static final String GOOGLE_TV_HOME = "com.google.android.apps.tv.launcherx.home.HomeActivity";

    @Test
    public void appsDecideScreenTimeOnlyWhenTheyAgree() {
        assertEquals(Boolean.TRUE, ProfileUsers.screenTimeFromBlocked(4, 4));
        assertEquals(Boolean.FALSE, ProfileUsers.screenTimeFromBlocked(4, 0));
        // An app a parent always allows stays open at bedtime: that says nothing, it never lifts the lock
        assertNull(ProfileUsers.screenTimeFromBlocked(4, 3));
        assertNull(ProfileUsers.screenTimeFromBlocked(4, 1));
        assertNull(ProfileUsers.screenTimeFromBlocked(0, 0));
    }

    @Test
    public void bedtimeScreenStaysInFrontUnderPopUps() {
        // Google TV's bedtime screen comes up
        boolean inFront = LauncherAccessibilityService.wellbeingInFront(false, true, false, WELLBEING);
        assertTrue(inFront);
        // The volume panel, the keyboard, Play services' "ask a parent": the screen is still there
        assertTrue(LauncherAccessibilityService.wellbeingInFront(inFront, false, false, "com.android.systemui"));
        assertTrue(LauncherAccessibilityService.wellbeingInFront(inFront, false, false, "android.app.Dialog"));
        // A plain dialog of Google TV's own over it
        assertTrue(LauncherAccessibilityService.wellbeingInFront(inFront, true, false, "android.app.Dialog"));
        // Gone once Google TV's home, Hearth or an app comes up
        assertFalse(LauncherAccessibilityService.wellbeingInFront(inFront, true, false, GOOGLE_TV_HOME));
        assertFalse(LauncherAccessibilityService.wellbeingInFront(inFront, false, true, "com.thesiegs.hearth.MainActivity"));
        // Pop-ups don't make it come up either
        assertFalse(LauncherAccessibilityService.wellbeingInFront(false, false, false, "com.android.systemui"));
    }

    @Test
    public void kidsHomeAlwaysGetsItsGrace() {
        // Google TV opens its bedtime / time up screen from its kids home, and blocks the apps only afterwards, so a
        // kids profile always leaves the home up for a moment, whatever the apps say
        long kids = LauncherAccessibilityService.homeGraceMs(true, false);
        assertTrue(kids >= 1_000);
        // Just after a profile lock too: the kids grace is the longer wait
        assertEquals(kids, LauncherAccessibilityService.homeGraceMs(true, true));
        // An adult's home is covered at once, or after the short wait for a cancelled PIN's chooser
        assertEquals(0, LauncherAccessibilityService.homeGraceMs(false, false));
        long afterLock = LauncherAccessibilityService.homeGraceMs(false, true);
        assertTrue(afterLock > 0 && afterLock < kids);
    }

    @Test
    public void aPickedKidsHomeIsAKidsHomeBeforeTheKidsUserStarts() {
        // Picked a kid from an adult's profile: the adult is still the settled profile
        assertTrue(LauncherAccessibilityService.kidsHome(true, false, false));
        // Picked an adult from a kid's profile
        assertFalse(LauncherAccessibilityService.kidsHome(false, true, false));
        // No fresh pick (Back from an app): the profile on now
        assertTrue(LauncherAccessibilityService.kidsHome(null, true, false));
        assertFalse(LauncherAccessibilityService.kidsHome(null, false, false));
        // A kids screen time screen holds it whatever was picked
        assertTrue(LauncherAccessibilityService.kidsHome(false, false, true));
    }

    @Test
    public void aClickedPickGetsLongerToShowOnGoogleTvsHome() {
        // The home names the pick: done at once
        assertTrue(LauncherAccessibilityService.homeAccountDone(true, true, true, 100));
        // It names the last account after a click: not taken at its word at 1.2 s, nor at 2.5 s
        assertFalse(LauncherAccessibilityService.homeAccountDone(false, true, true, 1_300));
        assertFalse(LauncherAccessibilityService.homeAccountDone(false, true, true, 2_600));
        assertTrue(LauncherAccessibilityService.homeAccountDone(false, true, true, 4_000));
        // Without a click (the last focused tile) it's taken at its word after 1.2 s, as before
        assertFalse(LauncherAccessibilityService.homeAccountDone(false, true, false, 1_000));
        assertTrue(LauncherAccessibilityService.homeAccountDone(false, true, false, 1_300));
        // Nothing read yet: up to 2.5 s
        assertFalse(LauncherAccessibilityService.homeAccountDone(false, false, true, 2_000));
        assertTrue(LauncherAccessibilityService.homeAccountDone(false, false, true, 2_500));
    }

    @Test
    public void hearthsOverlaysAndAgentScreenDontReplaceWhatsInFront() {
        assertTrue(LauncherAccessibilityService.isHearthOverlay("android.widget.FrameLayout"));
        assertTrue(LauncherAccessibilityService.isHearthOverlay(AgentActivity.class.getName()));
        assertFalse(LauncherAccessibilityService.isHearthOverlay(MainActivity.class.getName()));
    }

    @Test
    public void readsGoogleTvsBedtimeScreen() {
        ScreenTimeScreen screen = ScreenTimeScreen.parse(WELLBEING,
                Arrays.asList("Time for bed", "This device unlocks at 7:00 AM"));
        assertEquals(ScreenTimeScreen.Reason.BEDTIME, screen.reason);
        assertEquals(Integer.valueOf(0), screen.minutesLeft);
        assertEquals("7:00 AM", screen.unlocksAt);
        assertTrue(screen.isScreenTimeText());
    }

    @Test
    public void ignoresUnrelatedGoogleTvText() {
        ScreenTimeScreen screen = ScreenTimeScreen.parse(GOOGLE_TV_HOME, Arrays.asList("For you", "Movies", "Shows"));
        assertEquals(ScreenTimeScreen.Reason.UNKNOWN, screen.reason);
        assertNull(screen.minutesLeft);
        assertFalse(screen.isScreenTimeText());
    }

    @Test
    public void bedtimeKeepsTheLockWhenTheOwnerIsReported() {
        // Google TV's own screen set it: the kid's user stopped and the owner's is reported, still locked
        assertFalse(LauncherAccessibilityService.mayLiftLock(true, false, true, false));
        assertFalse(LauncherAccessibilityService.mayLiftLock(true, false, false, false));
        // A pick in the chooser always lifts it
        assertTrue(LauncherAccessibilityService.mayLiftLock(true, true, false, false));
        // Set from the apps alone (no screen seen): an adult profile or a flip lifts it, as before
        assertTrue(LauncherAccessibilityService.mayLiftLock(false, false, true, true));
        assertTrue(LauncherAccessibilityService.mayLiftLock(false, false, false, false));
        assertFalse(LauncherAccessibilityService.mayLiftLock(false, false, false, true));
    }
}
