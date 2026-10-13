package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

/** Tidying the Home Assistant address a parent typed. */
public class HaConfigTest {
    @Test
    public void trailingSlashesGoAndASchemeIsAdded() {
        assertEquals("http://ha.local:8123", HaConfig.normalizeUrl(" ha.local:8123/// "));
        assertEquals("https://192.0.2.10", HaConfig.normalizeUrl("https://192.0.2.10/"));
        assertEquals("http://ha.local/lovelace", HaConfig.normalizeUrl("http://ha.local/lovelace"));
        assertNull(HaConfig.normalizeUrl("///"));
        assertNull(HaConfig.normalizeUrl(null));
        StringBuilder slashes = new StringBuilder("ha.local");
        for (int i = 0; i < 50_000; i++) slashes.append("/");
        slashes.append("x");
        assertEquals("http://" + slashes, HaConfig.normalizeUrl(slashes.toString()));
    }
}
