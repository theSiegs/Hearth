package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.regex.Matcher;

import org.junit.Test;

/** Reading Disney+'s and Netflix's profile tiles, what the agent may open, and which adults' apps start again on a profile switch. */
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
        assertEquals("Alex", disneyName("Access Alex's pin protected profile"));
        assertEquals(null, disneyName("Add profile"));
        assertEquals(null, disneyName("Access Alex's profiles"));
    }

    @Test
    public void disneysPinScreenAvatarIsNotATile() {
        // The picker's tile label is a plain view; the PIN screen shows the same words on an image
        assertEquals("Alex", ProfilePairingService.disneyTileName("android.view.View", "Access Alex's pin protected profile"));
        assertEquals(null, ProfilePairingService.disneyTileName("android.widget.ImageView", "Access Alex's pin protected profile"));
        assertEquals("Sam", ProfilePairingService.disneyTileName(null, "Access Sam's profile"));
    }

    @Test
    public void onlyAnotherAdultsAppsStartAgain() {
        // The other adult had it: it starts again at its picker
        assertTrue(AdultsApps.stops("user:0", "user:0:sam", 0));
        assertTrue(AdultsApps.stops("user:0:sam", "user:0", 0));
        // This profile had it, nobody did, or a kids profile (its own copy, in its own user)
        assertFalse(AdultsApps.stops("user:0:sam", "user:0:sam", 0));
        assertFalse(AdultsApps.stops(null, "user:0", 0));
        assertFalse(AdultsApps.stops("user:11", "user:0", 0));
    }

    private static String netflix(String text) {
        Matcher m = ProfilePairingService.NETFLIX_COUNT.matcher(text);
        if (!m.find()) return null;
        return ProfilePairingService.netflixName(text.substring(0, m.start())) + "|" + m.group(1) + "|" + m.group(2);
    }

    @Test
    public void netflixTilesGiveTheNameAndCount() {
        assertEquals("Sam|2|5", netflix("Sam, 2 of 5 profiles"));
        assertEquals("Alex Rivera|1|1", netflix("Alex Rivera. 1 of 1 profile"));
        assertEquals("|3|4", netflix("3 of 4 profiles"));
        assertEquals(null, netflix("Add profile"));
        // Long runs of digits and commas come back at once (no backtracking)
        StringBuilder junk = new StringBuilder();
        for (int i = 0; i < 20_000; i++) junk.append(",1 ");
        assertEquals(null, netflix(junk.toString()));
    }

    @Test
    public void agentOpensOnlyOtherApps() {
        assertTrue(AgentActivity.isOtherApp("com.example.hearth", "com.example.tv"));
        assertFalse(AgentActivity.isOtherApp("com.example.hearth", "com.example.hearth"));
        assertFalse(AgentActivity.isOtherApp("com.example.hearth", null));
        assertFalse(AgentActivity.isOtherApp("com.example.hearth", ""));
        int grants = android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                | android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                | android.content.Intent.FLAG_GRANT_PREFIX_URI_PERMISSION;
        int newTask = android.content.Intent.FLAG_ACTIVITY_NEW_TASK;
        assertEquals(newTask, AgentActivity.withoutGrants(grants | newTask));
    }

}
