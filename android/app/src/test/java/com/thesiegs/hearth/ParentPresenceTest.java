package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;

/** A grown-up at the remote isn't asked for the parent PIN until the remote has gone untouched for five minutes. */
public class ParentPresenceTest {
    private static final long MIN = 60_000;

    @Before
    public void setUp() {
        ParentPresence.reset();
    }

    @Test
    public void presentWhileTheRemoteKeepsBeingUsed() {
        assertFalse(ParentPresence.isPresent(1_000));
        ParentPresence.confirmed(1_000);
        ParentPresence.onKey(1_000 + 4 * MIN);
        ParentPresence.onKey(1_000 + 8 * MIN);
        assertTrue(ParentPresence.isPresent(1_000 + 9 * MIN));
    }

    @Test
    public void aFiveMinuteGapEndsIt() {
        ParentPresence.confirmed(1_000);
        // Nobody touched the remote for five minutes: asked now, and after the next key too
        assertFalse(ParentPresence.isPresent(1_000 + 5 * MIN));
        ParentPresence.onKey(1_000 + 6 * MIN);
        assertFalse(ParentPresence.isPresent(1_000 + 6 * MIN));
        // The parent PIN brings it back
        ParentPresence.confirmed(1_000 + 7 * MIN);
        assertTrue(ParentPresence.isPresent(1_000 + 8 * MIN));
    }

    @Test
    public void aKidsProfileEndsIt() {
        ParentPresence.confirmed(1_000);
        ParentPresence.ended();
        assertFalse(ParentPresence.isPresent(2_000));
    }
}
