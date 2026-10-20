package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

/** What a copy from another TV may do to a profile's pairing choices. */
public class ShareDataTest {
    private static Map<String, Object> pairing(String pkg, String mode, Object appProfile) {
        Map<String, Object> map = new HashMap<>();
        map.put("pkg", pkg);
        map.put("mode", mode);
        if (appProfile != null) map.put("appProfile", appProfile);
        return map;
    }

    @Test
    public void takesAnAppProfileOrAlwaysAskForAStreamingAppItPairs() {
        Map<String, String> byName = ShareData.clean(pairing(ProfilePairing.NETFLIX, "profile", "Alex"));
        assertNotNull(byName);
        assertEquals(ProfilePairing.MODE_PROFILE, byName.get("mode"));
        assertEquals("Alex", byName.get("appProfile"));

        Map<String, String> ask = ShareData.clean(pairing(ProfilePairing.DISNEY, "picker", "ignored"));
        assertNotNull(ask);
        assertEquals(ProfilePairing.MODE_PICKER, ask.get("mode"));
        assertEquals("", ask.get("appProfile"));
    }

    @Test
    public void refusesWhatIsNotAPairing() {
        assertNull(ShareData.clean(null));
        // An app Hearth doesn't pair
        assertNull(ShareData.clean(pairing("com.example.video", "profile", "Alex")));
        // The automatic mode isn't a choice, and an unknown mode isn't one either
        assertNull(ShareData.clean(pairing(ProfilePairing.NETFLIX, "auto", null)));
        assertNull(ShareData.clean(pairing(ProfilePairing.NETFLIX, "whatever", "Alex")));
        // A name that isn't text, or is nothing
        assertNull(ShareData.clean(pairing(ProfilePairing.NETFLIX, "profile", 5)));
        assertNull(ShareData.clean(pairing(ProfilePairing.NETFLIX, "profile", "  \n ")));
        assertNull(ShareData.clean(pairing(ProfilePairing.NETFLIX, "profile", null)));
        assertNull(ShareData.clean(pairing(null, "profile", "Alex")));
    }

    @Test
    public void tidiesANameFromAnotherTv() {
        assertEquals("Alex Red", ShareData.tidy("  Alex\u0000\u001bRed\n"));
        String longName = new String(new char[500]).replace('\0', 'a');
        assertEquals(200, ShareData.tidy(longName).length());
    }

    @Test
    public void onlyAProfileWithNoChoiceOfItsOwnTakesAnother() {
        assertTrue(ShareData.shouldApply(ProfilePairing.MODE_AUTO));
        assertFalse(ShareData.shouldApply(ProfilePairing.MODE_PROFILE));
        assertFalse(ShareData.shouldApply(ProfilePairing.MODE_PICKER));
    }
}
