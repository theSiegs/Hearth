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

    @Test
    public void thePressThatPickedTheProfileDoesNotEndTheRequest() {
        long shown = 50_000;
        int ok = android.view.KeyEvent.KEYCODE_DPAD_CENTER;
        // The chooser's OK began before the PIN screen came up (its repeat or late delivery): never counts
        assertFalse(PhoneApproval.endsRequest(ok, 0, shown - 300, shown));
        // An OK, arrow or Back within the grace after it came up (a laggy remote's second press): doesn't count
        assertFalse(PhoneApproval.endsRequest(ok, 0, shown + 680, shown));
        assertFalse(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_DPAD_RIGHT, 0, shown + 1_500, shown));
        assertFalse(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_BACK, 0, shown + PhoneApproval.GRACE_MS - 1,
                shown));
        // After the grace, the remote on the PIN screen is someone using it
        assertTrue(PhoneApproval.endsRequest(ok, 0, shown + PhoneApproval.GRACE_MS, shown));
        assertTrue(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_DPAD_LEFT, 0, shown + 5_000, shown));
        // A digit is typing the PIN, at once
        assertTrue(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_7, 0, shown + 200, shown));
        assertTrue(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_NUMPAD_3, 0, shown + 200, shown));
        // ...but not one held from before, nor a repeat, nor a key the PIN screen doesn't take
        assertFalse(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_7, 0, shown - 1, shown));
        assertFalse(PhoneApproval.endsRequest(ok, 2, shown + 5_000, shown));
        assertFalse(PhoneApproval.endsRequest(android.view.KeyEvent.KEYCODE_VOLUME_UP, 0, shown + 5_000, shown));
    }

    @Test
    public void homeAssistantsPhonesAreAskedOnlyWhenNoneWasChosen() {
        String doc = "{\"user:0\":[\"mobile_app_alex_phone\",\"mobile_app_alex_tablet\",\"mobile_app_alex_phone\","
                + "\"notify\"],\"user:11\":[]}";
        assertEquals(Arrays.asList("mobile_app_alex_phone", "mobile_app_alex_tablet"),
                PhoneApproval.phonesIn(doc, "user:0"));
        assertTrue(PhoneApproval.phonesIn(doc, "user:11").isEmpty());
        assertTrue(PhoneApproval.phonesIn(doc, "user:12").isEmpty());
        assertTrue(PhoneApproval.phonesIn("not json", "user:0").isEmpty());
        assertTrue(PhoneApproval.phonesIn(null, "user:0").isEmpty());

        java.util.List<String> fromHa = PhoneApproval.phonesIn(doc, "user:0");
        // A phone chosen on any TV wins
        assertEquals(Arrays.asList("mobile_app_sam_phone"), PhoneApproval.choose("mobile_app_sam_phone", fromHa));
        assertEquals(fromHa, PhoneApproval.choose(null, fromHa));
        assertTrue(PhoneApproval.choose(null, new java.util.ArrayList<>()).isEmpty());
    }
}
