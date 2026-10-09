package com.leanbitlab.ltvL;

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
        assertFalse(LauncherAccessibilityService.wellbeingInFront(inFront, false, true, "com.leanbitlab.ltvL.MainActivity"));
        // Pop-ups don't make it come up either
        assertFalse(LauncherAccessibilityService.wellbeingInFront(false, false, false, "com.android.systemui"));
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
        // Set from the apps alone (no screen seen): a grown-up profile or a flip lifts it, as before
        assertTrue(LauncherAccessibilityService.mayLiftLock(false, false, true, true));
        assertTrue(LauncherAccessibilityService.mayLiftLock(false, false, false, false));
        assertFalse(LauncherAccessibilityService.mayLiftLock(false, false, false, true));
    }
}
