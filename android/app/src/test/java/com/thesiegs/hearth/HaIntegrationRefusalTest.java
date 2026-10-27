package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** A refused status post unpairs the TV only when the refusals last: a restart or reload refuses for a moment. */
public class HaIntegrationRefusalTest {
    @Test
    public void aMomentOfRefusalsKeepsThePairing() {
        assertFalse(HaIntegration.refusedLongEnough(1_000, 1_000));
        assertFalse(HaIntegration.refusedLongEnough(1_000, 1_000 + 5 * 60_000L));
    }

    @Test
    public void tenMinutesOfRefusalsUnpair() {
        assertTrue(HaIntegration.refusedLongEnough(1_000, 1_000 + HaIntegration.UNPAIR_AFTER_REFUSALS_MS));
    }
}
