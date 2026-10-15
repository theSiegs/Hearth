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
}
