package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
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

    @Test
    public void refusalsTwoMinutesApartAddUpToTen() {
        long start = 1_000_000;
        long since = 0, last = 0;
        boolean unpaired = false;
        for (long now = start; now <= start + HaIntegration.UNPAIR_AFTER_REFUSALS_MS && !unpaired; now += 2 * 60_000L) {
            since = HaIntegration.refusalsSince(since, last, now);
            last = now;
            unpaired = HaIntegration.refusedLongEnough(since, now);
        }
        assertTrue(unpaired);
    }

    @Test
    public void aRefusalLongAfterAnEarlierOneStartsAgain() {
        // One 401 while Home Assistant restarted, then the TV was off (or Home Assistant unreachable) for a day, then
        // another restart's 401: a moment of refusals, not ten minutes of them
        long first = 1_000_000;
        long day = 24 * 60 * 60_000L;
        long since = HaIntegration.refusalsSince(0, 0, first);
        long again = HaIntegration.refusalsSince(since, first, first + day);
        assertEquals(first + day, again);
        assertFalse(HaIntegration.refusedLongEnough(again, first + day));
        // a clock that went back starts again too
        assertEquals(first, HaIntegration.refusalsSince(first + day, first + day, first));
    }
}
