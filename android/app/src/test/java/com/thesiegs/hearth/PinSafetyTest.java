package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.junit.Test;

/** The list of app versions Hearth doesn't type PINs in, and the log of recent entries. */
public class PinSafetyTest {
    private static final String LIST = "{\"version\":1,\"disabled\":["
            + "{\"package\":\"com.example.tv\",\"from\":100,\"to\":199,\"note\":\"PIN screen changed\"},"
            + "{\"package\":\"com.example.other\"}]}";

    @Test
    public void listedVersionsAreTurnedOff() {
        assertEquals("PIN screen changed", PinSafety.disabledIn(LIST, "com.example.tv", 150));
        assertEquals("PIN screen changed", PinSafety.disabledIn(LIST, "com.example.tv", 199));
        assertNull(PinSafety.disabledIn(LIST, "com.example.tv", 99));
        assertNull(PinSafety.disabledIn(LIST, "com.example.tv", 200));
        // No range: every version
        assertNotNull(PinSafety.disabledIn(LIST, "com.example.other", 1));
        assertNull(PinSafety.disabledIn(LIST, "com.example.unlisted", 1));
        // No list, or one that doesn't parse: nothing turned off (the list can only turn typing off)
        assertNull(PinSafety.disabledIn(null, "com.example.tv", 150));
        assertNull(PinSafety.disabledIn("not json", "com.example.tv", 150));
    }

    @Test
    public void theLogKeepsTheLatestEntriesNewestFirst() throws Exception {
        String log = "[]";
        for (int i = 0; i < PinSafety.LOG_SIZE + 5; i++) {
            log = PinSafety.withEntry(log, "com.example.tv", 7, false, "ACCEPTED", i);
        }
        JSONArray entries = new JSONArray(log);
        assertEquals(PinSafety.LOG_SIZE, entries.length());
        assertEquals(PinSafety.LOG_SIZE + 4, entries.getJSONObject(0).getLong("at"));
        assertTrue(entries.getJSONObject(0).has("result"));
        // A damaged log starts again with the new entry
        assertEquals(1, new JSONArray(PinSafety.withEntry("garbage", "com.example.tv", 7, true, "REJECTED", 1)).length());
    }
}
