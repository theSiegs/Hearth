package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Which profiles count, and how a name from another TV is tidied. */
public class ShareDataTest {
    @Test
    public void tidiesANameFromAnotherTv() {
        assertEquals("Alex Red", ShareData.tidy("  Alex\u0000\u001bRed\n"));
        String longName = new String(new char[500]).replace('\0', 'a');
        assertEquals(200, ShareData.tidy(longName).length());
    }

    @Test
    public void aSpareUserAndroidKeepsReadyIsNotAProfile() {
        // Hearth never learned a name for it
        assertFalse(ShareData.listable("user:10", null));
        assertFalse(ShareData.listable("user:10", ""));
        assertTrue(ShareData.listable("user:10", "Alex"));
        // Another account in a user, and a name saved before keys, count
        assertTrue(ShareData.listable("user:0:sam", null));
        assertTrue(ShareData.listable("Alex", null));
        assertFalse(ShareData.listable(null, null));
    }
}
