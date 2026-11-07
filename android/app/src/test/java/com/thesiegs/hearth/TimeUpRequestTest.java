package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.Test;

/** com.thesiegs.hearth.action.TIME_UP: its extras, and what the card then names. */
public class TimeUpRequestTest {
    private static Map<String, Object> group(String id, String name) {
        Map<String, Object> map = new HashMap<>();
        map.put("id", id);
        map.put("name", name);
        return map;
    }

    private static final List<Map<String, Object>> OUT = Arrays.asList(group("youtube", "YouTube"), group("games", "Games"));

    @Test
    public void theExtrasAreAPackageNameAndAGroupIdOrNothing() {
        assertEquals("com.thesiegs.hearthtube", TimeUpRequest.cleanPackage(" com.thesiegs.hearthtube "));
        assertNull(TimeUpRequest.cleanPackage("hearthtube"));
        assertNull(TimeUpRequest.cleanPackage("com.example/../x"));
        assertNull(TimeUpRequest.cleanPackage(""));
        assertNull(TimeUpRequest.cleanPackage(null));
        assertEquals("youtube", TimeUpRequest.cleanGroup("youtube"));
        assertEquals("my_group_2", TimeUpRequest.cleanGroup("my_group_2"));
        assertNull(TimeUpRequest.cleanGroup("YouTube"));
        assertNull(TimeUpRequest.cleanGroup("a b"));
        assertNull(TimeUpRequest.cleanGroup(null));
    }

    @Test
    public void theCardNamesTheGroupOutOfTime() {
        // A known group out of time, named
        assertEquals("YouTube", TimeUpRequest.cardGroup("youtube", OUT, "YouTube"));
        assertEquals("Games", TimeUpRequest.cardGroup("games", OUT, null));
        // An unknown group (or one with time left) is ignored: the app's own hold decides
        assertEquals("YouTube", TimeUpRequest.cardGroup("video", OUT, "YouTube"));
        // Nothing holds the app: no card, the home only
        assertNull(TimeUpRequest.cardGroup(null, OUT, null));
        assertNull(TimeUpRequest.cardGroup("video", OUT, null));
        // A pause or a lock holds everything, whatever the group
        assertEquals("", TimeUpRequest.cardGroup("youtube", OUT, ""));
    }
}
