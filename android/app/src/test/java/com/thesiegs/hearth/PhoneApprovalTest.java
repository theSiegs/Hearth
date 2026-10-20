package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.json.JSONObject;

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

    @Test
    public void thePushKeepsItsButtonsAndDoesNothingWhenTapped() throws Exception {
        JSONObject data = PhoneApproval.pushData("Allow", "Deny", "ab12");
        assertEquals("true", data.getString("sticky"));
        assertEquals("noAction", data.getString("clickAction"));
        assertEquals("hearth-approval-ab12", data.getString("tag"));
        assertEquals("HEARTH_APPROVE_ALLOW_ab12", data.getJSONArray("actions").getJSONObject(0).getString("action"));
        assertEquals("HEARTH_APPROVE_DENY_ab12", data.getJSONArray("actions").getJSONObject(1).getString("action"));
    }

    @Test
    public void onlyAFirstPressOfAKeyThePinScreenTakesEndsTheRequest() {
        assertTrue(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_DPAD_CENTER, 0));
        assertTrue(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_5, 0));
        assertTrue(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_BACK, 0));
        assertFalse(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_DPAD_DOWN, 3));
        assertFalse(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_VOLUME_UP, 0));
        assertFalse(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 0));
        assertFalse(PhoneApproval.isPinScreenKey(android.view.KeyEvent.KEYCODE_POWER, 0));
    }
}
