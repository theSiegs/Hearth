package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

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
}
