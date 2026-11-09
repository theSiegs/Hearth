package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

/** Which focused labels count as chooser picks, and when Google TV's home says a pick isn't coming. */
public class ChooserPicksTest {
    private static final List<String> TILES = Arrays.asList("Alex", "Sam", "Robin");

    @Test
    public void onlyTheChoosersTilesArePicks() {
        assertTrue(LauncherAccessibilityService.isChooserTile(TILES, "Sam"));
        // Google TV's home tabs, focused while Hearth wrongly thought the chooser was up after a PIN
        assertFalse(LauncherAccessibilityService.isChooserTile(TILES, "Home"));
        assertFalse(LauncherAccessibilityService.isChooserTile(TILES, "Apps"));
        assertFalse(LauncherAccessibilityService.isChooserTile(TILES, null));
    }

    @Test
    public void beforeAnyReadEveryLabelMayBeAPick() {
        assertTrue(LauncherAccessibilityService.isChooserTile(Collections.emptyList(), "Sam"));
        assertTrue(LauncherAccessibilityService.isChooserTile(null, "Home"));
        assertFalse(LauncherAccessibilityService.isChooserTile(null, null));
    }

    @Test
    public void aPickThatIsntAProfileIsCancelledWhenTheHomeNamesSomeoneElse() {
        assertTrue(LauncherAccessibilityService.pickNotAProfile("Home", "Alex", TILES));
    }

    @Test
    public void aRealPickIsNeverCancelledByThisCheck() {
        // The home names the pick: the switch is confirmed
        assertFalse(LauncherAccessibilityService.pickNotAProfile("Sam", "Sam", TILES));
        // A tile the home doesn't name (yet): a slow switch, or a new profile Google TV is still setting up
        assertFalse(LauncherAccessibilityService.pickNotAProfile("Sam", "Alex", TILES));
        // The home didn't say, or there was no pick
        assertFalse(LauncherAccessibilityService.pickNotAProfile("Home", null, TILES));
        assertFalse(LauncherAccessibilityService.pickNotAProfile(null, "Alex", TILES));
        // No tiles read yet: nothing to tell a profile by
        assertFalse(LauncherAccessibilityService.pickNotAProfile("Home", "Alex", Collections.emptyList()));
        assertFalse(LauncherAccessibilityService.pickNotAProfile("Home", "Alex", null));
    }
}
