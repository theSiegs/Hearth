package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ProfileLockTest {
    private static final long MINUTE = 60_000L;

    @Test
    public void offNeverOpensTheChooser() {
        assertFalse(ProfileLock.due(ProfileLock.OFF, 1_000, 1_000 + 90 * MINUTE));
    }

    @Test
    public void everyTimeOpensItAfterAnySleep() {
        assertTrue(ProfileLock.due(0, 1_000, 1_000));
        assertTrue(ProfileLock.due(0, 1_000, 1_000 + 5_000));
    }

    @Test
    public void aSetTimeNeedsThatLongAsleep() {
        assertFalse(ProfileLock.due(15, 1_000, 1_000 + 14 * MINUTE));
        assertTrue(ProfileLock.due(15, 1_000, 1_000 + 15 * MINUTE));
    }

    @Test
    public void aWakeWithoutASleepWeSawIsIgnored() {
        // The screen-off was never seen (the service started while the TV was already asleep)
        assertFalse(ProfileLock.due(0, 0, 5 * MINUTE));
    }

    private static final String HOME = "com.google.android.apps.tv.launcherx.home.HomeActivity";
    private static final String KIDS_TIME_UP = "com.google.android.apps.tv.launcherx.kids.wellbeing.KidsTimeUpActivity";
    private static final String CHOOSER = "com.google.android.apps.tv.launcherx.profile.chooser.ProfileChooserActivity";

    /** reopenOnWake with everything as on a plain power-button wake, but the front window. */
    private static boolean plainWake(String front) {
        return ProfileLock.reopenOnWake(true, 0, true, front, false, false, false, false);
    }

    @Test
    public void aWakeOntoGoogleTvsHomeOrTheLastKidsTimeUpOpensTheChooserAgain() {
        assertTrue(plainWake(HOME));
        assertTrue(plainWake(KIDS_TIME_UP));
        // Hearth already bounced Google's home: still the last profile's home
        assertTrue(plainWake("com.thesiegs.hearth.MainActivity"));
    }

    @Test
    public void theChooserOrAScreenOverItIsLeftAlone() {
        assertFalse(plainWake(CHOOSER));
        assertFalse(plainWake("com.google.android.apps.tv.launcherx.profile.chooser.ProfileChooserTransparentActivity"));
        assertFalse(plainWake("com.google.android.apps.tv.launcherx.profile.lock.ProfileLockWrapperActivity"));
        assertFalse(plainWake("com.google.android.libraries.tv.reauth.ReauthActivity"));
        // Nothing seen in front: nothing to go by
        assertFalse(plainWake(null));
    }

    @Test
    public void aPersonWhoPickedOrPressedBackIsNotFought() {
        // A key since the wake: they picked, or pressed Back on the chooser
        assertFalse(ProfileLock.reopenOnWake(true, 0, true, HOME, true, false, false, false));
        // The profile changed since the wake
        assertFalse(ProfileLock.reopenOnWake(true, 0, true, HOME, false, true, false, false));
    }

    @Test
    public void onlyAWakeThatWantedTheChooserAndWithTheGuardsOff() {
        // The chooser didn't open for this sleep (slept too briefly, or it was off)
        assertFalse(ProfileLock.reopenOnWake(false, 0, true, HOME, false, false, false, false));
        assertFalse(ProfileLock.reopenOnWake(true, ProfileLock.OFF, true, HOME, false, false, false, false));
        // Asleep again by the time of the check
        assertFalse(ProfileLock.reopenOnWake(true, 0, false, HOME, false, false, false, false));
        // "Use Google TV's home" is on
        assertFalse(ProfileLock.reopenOnWake(true, 0, true, HOME, false, false, true, false));
        // Google's own setup, or a new profile it is starting
        assertFalse(ProfileLock.reopenOnWake(true, 0, true, HOME, false, false, false, true));
    }
}
