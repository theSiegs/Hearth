package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ParentPinHashTest {
    /** As the Dart side's ParentPinHash.hash("2468") keeps it, with salt 00..0f and a cost of 3. */
    private static final String SALTED =
            "v2$3$000102030405060708090a0b0c0d0e0f$9a3485228d1d796b879fd845db14495a013a59a0a41ac147f4151299fdaa0f1a";
    private static final String OLD = "845cdcc0a8a73c7509cdfed614ca4e5811f2d342db3d8c89dfcc9dbf14e0d857";

    @Test
    public void checksTheSaltedFormAsDartMakesIt() {
        assertTrue(ParentPinHash.verify("2468", SALTED));
        assertFalse(ParentPinHash.verify("2469", SALTED));
    }

    @Test
    public void checksTheOldForm() {
        assertTrue(ParentPinHash.verify("2468", OLD));
        assertFalse(ParentPinHash.verify("1357", OLD));
    }

    @Test
    public void refusesWhatIsntAStoredPin() {
        assertFalse(ParentPinHash.verify("2468", null));
        assertFalse(ParentPinHash.verify(null, SALTED));
        assertFalse(ParentPinHash.verify("2468", "2468"));
        assertFalse(ParentPinHash.verify("2468", "v2$0$000102030405060708090a0b0c0d0e0f$" + OLD));
    }
}
