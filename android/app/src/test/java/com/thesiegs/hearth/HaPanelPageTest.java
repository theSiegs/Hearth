package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** The Home Assistant panel's page loads in the background only for an adult's profile that shows it. */
public class HaPanelPageTest {
    @Test
    public void preloadsForAnAdultWithTheFullDashboardOn() {
        assertTrue(HaPanelPage.shouldPreload(true, true, true, false));
    }

    @Test
    public void neverPreloadsInAKidsProfile() {
        // The panel is for adults: a kids profile's settings saying otherwise don't count
        assertFalse(HaPanelPage.shouldPreload(true, true, true, true));
    }

    @Test
    public void notWhenThePanelIsOffShowsHearthsOwnOrHasNoAddress() {
        assertFalse(HaPanelPage.shouldPreload(false, true, true, false));
        assertFalse(HaPanelPage.shouldPreload(true, false, true, false));
        assertFalse(HaPanelPage.shouldPreload(true, true, false, false));
    }
}
