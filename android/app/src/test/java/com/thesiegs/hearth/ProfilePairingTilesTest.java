package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.regex.Matcher;

import org.junit.Test;

/** Reading Disney+'s profile tiles, and which grown-ups' apps start again on a profile switch. */
public class ProfilePairingTilesTest {
    private static String disneyName(String label) {
        Matcher m = ProfilePairingService.DISNEY_TILE.matcher(label);
        return m.matches() ? m.group(1) : null;
    }

    @Test
    public void disneyTilesWithMoreAfterTheNameStillCount() {
        assertEquals("Sam", disneyName("Access Sam's profile"));
        // A profile with a PIN says so after its name
        assertEquals("Alex", disneyName("Access Alex's profile. Profile PIN required"));
        assertEquals("Alex", disneyName("Access Alex’s profile, locked"));
        assertEquals(null, disneyName("Add profile"));
        assertEquals(null, disneyName("Access Alex's profiles"));
    }

    @Test
    public void onlyAnotherGrownUpsAppsStartAgain() {
        // The other grown-up had it: it starts again at its picker
        assertTrue(GrownUpsApps.stops("user:0", "user:0:sam", 0));
        assertTrue(GrownUpsApps.stops("user:0:sam", "user:0", 0));
        // This profile had it, nobody did, or a kids' profile (its own copy, in its own user)
        assertFalse(GrownUpsApps.stops("user:0:sam", "user:0:sam", 0));
        assertFalse(GrownUpsApps.stops(null, "user:0", 0));
        assertFalse(GrownUpsApps.stops("user:11", "user:0", 0));
    }
}
