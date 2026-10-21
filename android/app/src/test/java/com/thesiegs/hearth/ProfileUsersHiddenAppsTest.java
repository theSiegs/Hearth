package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Which apps a kids profile leaves out of its app list. */
public class ProfileUsersHiddenAppsTest {
    @Test
    public void thePlayStoreIsHiddenInAKidsProfileOnly() {
        assertTrue(ProfileUsers.hiddenInKids(true, "com.android.vending"));
        assertFalse(ProfileUsers.hiddenInKids(false, "com.android.vending"));
    }

    @Test
    public void otherAppsAreNotHidden() {
        assertFalse(ProfileUsers.hiddenInKids(true, "com.example.video"));
        assertFalse(ProfileUsers.hiddenInKids(true, "com.android.tv.settings"));
    }
}
