package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.json.JSONObject;
import org.junit.Test;

/** What a kids profile's agent says plays there: checked before it goes into that profile's watch history. */
public class AgentPlayedTest {
    private static JSONObject message(String pkg, Object title) throws Exception {
        return new JSONObject().put("type", "played").put("package", pkg).put("title", title)
                .put("subtitle", "S1 E2").put("duration", 1_200_000).put("position", 300_000);
    }

    @Test
    public void aShowIsTakenAsSent() throws Exception {
        AgentHub.Played p = AgentHub.played(message("com.example.tv", "The Show"));
        assertEquals("com.example.tv", p.packageName);
        assertEquals("The Show", p.title);
        assertEquals("S1 E2", p.subtitle);
        assertEquals(1_200_000, p.durationMs);
        assertEquals(300_000, p.positionMs);
    }

    @Test
    public void noAppOrTitleIsNothing() throws Exception {
        assertNull(AgentHub.played(message("", "The Show")));
        assertNull(AgentHub.played(message("not a package", "The Show")));
        assertNull(AgentHub.played(message("com.example.tv/../x", "The Show")));
        assertNull(AgentHub.played(message("com.example.tv", "  ")));
        assertNull(AgentHub.played(message("com.example.tv", 42)));
        assertNull(AgentHub.played(new JSONObject().put("package", "com.example.tv")));
    }

    @Test
    public void controlCharactersAndLongTitlesAreTidied() throws Exception {
        AgentHub.Played p = AgentHub.played(message("com.example.tv", "The\nShow\u0000\u202e"));
        assertEquals("The Show", p.title);
        StringBuilder longTitle = new StringBuilder();
        for (int i = 0; i < 1000; i++) longTitle.append('a');
        assertEquals(AgentHub.MAX_PLAYED_TITLE, AgentHub.played(message("com.example.tv", longTitle.toString())).title.length());
    }

    @Test
    public void numbersThatArentAShowAreRefused() throws Exception {
        assertNull(AgentHub.played(message("com.example.tv", "The Show").put("duration", -1)));
        assertNull(AgentHub.played(message("com.example.tv", "The Show").put("position", -5)));
        assertNull(AgentHub.played(message("com.example.tv", "The Show").put("duration", AgentHub.MAX_PLAYED_MS + 1)));
        // Past the end: at the end
        assertEquals(1_200_000, AgentHub.played(message("com.example.tv", "The Show").put("position", 1_500_000)).positionMs);
        // No duration known: the position as sent
        assertEquals(1_500_000, AgentHub.played(message("com.example.tv", "The Show").put("duration", 0)
                .put("position", 1_500_000)).positionMs);
    }

    @Test
    public void noEpisodeIsFine() throws Exception {
        JSONObject m = message("com.example.tv", "A Film");
        m.remove("subtitle");
        assertNull(AgentHub.played(m).subtitle);
    }
}
