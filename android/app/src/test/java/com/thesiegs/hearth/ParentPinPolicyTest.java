package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Wrong Parent PINs: five free, then 30 seconds doubling up to an hour. */
public class ParentPinPolicyTest {
    @Test
    public void waitsGrowWithEachWrongPin() {
        assertEquals(0, ParentPinPolicy.waitFor(4));
        assertEquals(30_000, ParentPinPolicy.waitFor(5));
        assertEquals(60_000, ParentPinPolicy.waitFor(6));
        assertEquals(120_000, ParentPinPolicy.waitFor(7));
        assertEquals(ParentPinPolicy.MAX_MS, ParentPinPolicy.waitFor(12));
        assertEquals(ParentPinPolicy.MAX_MS, ParentPinPolicy.waitFor(1_000));
    }

    @Test
    public void aWaitHomeAssistantSetHoldsHere_andAWrongPinDoesntCutItShort() {
        FakeContext context = new FakeContext("com.thesiegs.hearth");
        long now = System.currentTimeMillis();
        ParentPinPolicy.holdUntil(context, now + 600_000);
        assertTrue(ParentPinPolicy.lockedUntil(context, now) >= now + 590_000);
        // The pad counts the wrong PIN too: its own count (no wait yet) keeps Home Assistant's
        assertTrue(ParentPinPolicy.miss(context, now) >= now + 590_000);
        // A shorter one doesn't shorten it; never more than an hour
        ParentPinPolicy.holdUntil(context, now + 1_000);
        assertTrue(ParentPinPolicy.lockedUntil(context, now) >= now + 590_000);
        ParentPinPolicy.holdUntil(context, now + 10 * ParentPinPolicy.MAX_MS);
        assertTrue(ParentPinPolicy.lockedUntil(context, now) <= System.currentTimeMillis() + ParentPinPolicy.MAX_MS);
        ParentPinPolicy.clear(context);
        assertEquals(0, ParentPinPolicy.lockedUntil(context, now));
    }
}
