package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

/** A saved PIN's vault id, read back as the profile, app and app profile it was saved for. */
public class PinVaultSlotTest {
    private static final String NETFLIX = ProfilePairing.NETFLIX;

    @Test
    public void aVaultIdIsReadBackAsItsSlot() {
        PinVault.Slot profile = PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex  R"), "user:0:alex");
        assertEquals(NETFLIX, profile.pkg);
        assertEquals("alex r", profile.appProfile);
        assertNull(PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex"), "user:11"));
        assertNull(PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex"), null));
        PinVault.Slot shared = PinVault.parseSlot(PinVault.id(null, ContentPin.PACKAGE, ContentPin.VAULT_PROFILE), null);
        assertEquals(ContentPin.VAULT_PROFILE.toLowerCase(), shared.appProfile);
        assertNull(PinVault.parseSlot("paused|" + NETFLIX, null));
        assertNull(PinVault.parseSlot("breaks|" + NETFLIX, null));
    }
}
