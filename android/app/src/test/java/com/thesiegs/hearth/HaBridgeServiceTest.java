package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class HaBridgeServiceTest {
    @Test
    public void runsWhenAnythingIsSetUp() {
        assertTrue(HaBridgeService.needed(true, false, false));
        assertTrue(HaBridgeService.needed(false, true, false));
        assertTrue(HaBridgeService.needed(true, true, false));
    }

    @Test
    public void staysOffWhenNothingIsSetUp() {
        assertFalse(HaBridgeService.needed(false, false, false));
    }

    @Test
    public void neverRunsInAnotherProfilesUser() {
        // There Hearth is that profile's agent; the TV owner's Hearth holds the link
        assertFalse(HaBridgeService.needed(true, true, true));
    }
}
