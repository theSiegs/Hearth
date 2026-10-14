package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.After;
import org.junit.Test;

/** People's names in the log: stand-ins unless asked for. */
public class LogNamesTest {
    @After
    public void showAgain() {
        LogNames.setShowing(false);
    }

    @Test
    public void namesAreStandInsUnlessShown() {
        LogNames.setShowing(false);
        String alex = LogNames.of("Alex");
        assertTrue(alex.matches("#[0-9a-f]{4}"));
        // The Flutter side (log_names.dart) makes the same stand-in
        assertEquals("#ba1e", LogNames.standIn("alex"));
        // The same name (case and spacing aside) is the same stand-in, so a log can still be followed
        assertEquals(alex, LogNames.of(" alex "));
        assertFalse(LogNames.of(Arrays.asList("Alex", "Sam")).contains("Sam"));
        assertEquals("user:0:" + LogNames.standIn("alex"), LogNames.key("user:0:alex"));
        // Keys without a name stay as they are
        assertEquals("user:0", LogNames.key("user:0"));
        assertEquals("user:10", LogNames.key("user:10"));
        LogNames.setShowing(true);
        assertEquals("Alex", LogNames.of("Alex"));
        assertEquals("user:0:alex", LogNames.key("user:0:alex"));
    }
}
