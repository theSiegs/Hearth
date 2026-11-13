package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
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
    public void pairingStartsTheStatusAgain_soItGoesOutAtOnce() {
        String integration = "http://192.0.2.10:8123/api/hearth/device/tv-1/status";
        String paired = HaBridgeService.reportTarget(integration, "sealed-1", "t1");
        assertNotNull(paired);
        // Without a token: still somewhere to post
        assertNotNull(HaBridgeService.reportTarget(integration, "sealed-1", null));
        // Paired again, a new address, a new token: each changes where and how, so each posts at once
        assertNotEquals(paired, HaBridgeService.reportTarget(integration, "sealed-2", "t1"));
        assertNotEquals(paired, HaBridgeService.reportTarget(integration.replace("192.0.2.10", "192.0.2.11"),
                "sealed-1", "t1"));
        assertNotEquals(paired, HaBridgeService.reportTarget(integration, "sealed-1", "t2"));
        // Nothing changed: no post
        assertEquals(paired, HaBridgeService.reportTarget(integration, "sealed-1", "t1"));
    }

    @Test
    public void unpairedTheStatusGoesNowhere() {
        assertNull(HaBridgeService.reportTarget(null, null, "t1"));
    }

    @Test
    public void neverRunsInAnotherProfilesUser() {
        // There Hearth is that profile's agent; the TV owner's Hearth holds the link
        assertFalse(HaBridgeService.needed(true, true, true));
    }
}
