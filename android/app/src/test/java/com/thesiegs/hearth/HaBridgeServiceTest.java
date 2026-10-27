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
        String webhook = "http://192.0.2.10:8123/api/webhook/abc";
        String integration = "http://192.0.2.10:8123/api/hearth/device/tv-1/status";
        String before = HaBridgeService.reportTarget(null, null, webhook, "t1");
        // Paired: the integration, even with a webhook still set (the reporter posted only to the webhook's before)
        String paired = HaBridgeService.reportTarget(integration, "sealed-1", webhook, "t1");
        assertNotEquals(before, paired);
        // Paired without a webhook: still somewhere to post (it used to stop the reporter)
        assertNotNull(HaBridgeService.reportTarget(integration, "sealed-1", null, null));
        // Paired again, a new address, a new token: each changes where and how, so each posts at once
        assertNotEquals(paired, HaBridgeService.reportTarget(integration, "sealed-2", webhook, "t1"));
        assertNotEquals(paired, HaBridgeService.reportTarget(integration.replace("192.0.2.10", "192.0.2.11"),
                "sealed-1", webhook, "t1"));
        assertNotEquals(paired, HaBridgeService.reportTarget(integration, "sealed-1", webhook, "t2"));
        // Nothing changed: no post
        assertEquals(paired, HaBridgeService.reportTarget(integration, "sealed-1", webhook, "t1"));
    }

    @Test
    public void withNeitherTheIntegrationNorAWebhookTheStatusGoesNowhere() {
        assertNull(HaBridgeService.reportTarget(null, null, null, "t1"));
    }

    @Test
    public void neverRunsInAnotherProfilesUser() {
        // There Hearth is that profile's agent; the TV owner's Hearth holds the link
        assertFalse(HaBridgeService.needed(true, true, true));
    }
}
