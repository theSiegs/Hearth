package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.Test;

/** Asking a profile's owner on their phone before Hearth enters their Google TV PIN. */
public class PhoneApprovalTest {
    @Test
    public void onlyACompanionAppsNotifyServiceIsUsed() {
        assertTrue(PhoneApproval.isNotifyService("mobile_app_alex_phone"));
        assertFalse(PhoneApproval.isNotifyService("notify"));
        assertFalse(PhoneApproval.isNotifyService("persistent_notification"));
        assertFalse(PhoneApproval.isNotifyService("mobile_app_../x"));
        assertFalse(PhoneApproval.isNotifyService(null));
    }

    @Test
    public void thePinScreenIsMatchedByTheAccountItShows() {
        assertTrue(PhoneApproval.containsEmail(Arrays.asList("Verify your identity", "Alex Rivera", " Alex@Example.com "),
                "alex@example.com"));
        assertFalse(PhoneApproval.containsEmail(Arrays.asList("Verify your identity", "Sam"), "alex@example.com"));
        // Not a part of a longer text
        assertFalse(PhoneApproval.containsEmail(Arrays.asList("not alex@example.com"), "alex@example.com"));
    }
}
