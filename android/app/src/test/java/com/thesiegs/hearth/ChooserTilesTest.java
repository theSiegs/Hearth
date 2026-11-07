package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** Which of Google's chooser tiles Hearth's own picker may select (ChooserTiles), and when it must not. */
public class ChooserTilesTest {
    private static final String CHOOSER =
            "com.google.android.apps.tv.launcherx.profile.chooser.ProfileChooserActivity";
    private static final String TRANSPARENT_CHOOSER =
            "com.google.android.apps.tv.launcherx.profile.chooser.ProfileChooserTransparentActivity";
    private static final String REAUTH = "com.google.android.libraries.tv.reauth.ReauthActivity";
    private static final String LOCK = "com.google.android.apps.tv.launcherx.profile.lock.ProfileLockWrapperActivity";
    private static final String VERIFY = "com.google.android.apps.tv.launcherx.profile.core.AccountVerificationActivity";
    private static final String KIDS_PIN = "com.google.android.apps.tv.launcherx.kids.CreatePinActivity";
    private static final String HOME = "com.google.android.apps.tv.launcherx.home.HomeActivity";

    private static ChooserTiles.Tile tile(String name, String email, boolean current, boolean locked) {
        String desc = name + ", " + (email != null ? email + ", " : "") + (locked ? "Profile locked" : "")
                + ": select to " + (current ? "continue with current account" : "log in");
        return new ChooserTiles.Tile(name, desc, current);
    }

    private static List<ChooserTiles.Tile> household() {
        return new ArrayList<>(Arrays.asList(
                tile("Alex Rivera", "alex@example.com", true, true),
                tile("Sam", "sam@example.com", false, false),
                tile("Jo", "jo.kid@example.com", false, false)));
    }

    private static List<String> texts(List<ChooserTiles.Tile> tiles) {
        List<String> out = new ArrayList<>(Collections.singletonList("Who's watching?"));
        for (ChooserTiles.Tile t : tiles) out.add(t.name);
        out.add("Add account");
        return out;
    }

    private static ChooserTiles.Decision decide(String front, List<ChooserTiles.Tile> tiles, String name, String email) {
        return ChooserTiles.decide(front, texts(tiles), false, tiles, name, email);
    }

    // --- Finding the tile ---

    @Test
    public void findsTheTileByAddress() {
        ChooserTiles.Decision d = decide(CHOOSER, household(), "Sam", "sam@example.com");
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(1, d.index);
    }

    @Test
    public void theAddressMatchIgnoresCase() {
        ChooserTiles.Decision d = decide(CHOOSER, household(), "Sam", "SAM@Example.com");
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(1, d.index);
    }

    @Test
    public void findsAnUnnamedAccountByAddressAlone() {
        // An account the chooser hasn't named for Hearth yet: the picker only knows its address
        ChooserTiles.Decision d = decide(CHOOSER, household(), null, "jo.kid@example.com");
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(2, d.index);
    }

    @Test
    public void findsTheTileByNameWhenNoAddressIsKnown() {
        ChooserTiles.Decision d = decide(CHOOSER, household(), "Alex Rivera", null);
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(0, d.index);
    }

    @Test
    public void findsTheTileByNameWhenTheTilesShowNoAddresses() {
        List<ChooserTiles.Tile> tiles = Arrays.asList(tile("Alex Rivera", null, true, false), tile("Sam", null, false, false));
        ChooserTiles.Decision d = decide(CHOOSER, tiles, "Sam", "sam@example.com");
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(1, d.index);
    }

    @Test
    public void findsTheTileByTheNamesStandIn() {
        // The stand-in is the name's slug, as household refs have it: case and spacing don't matter
        List<ChooserTiles.Tile> tiles = Arrays.asList(tile("Alex  Rivera", null, true, false), tile("Sam", null, false, false));
        ChooserTiles.Decision d = decide(CHOOSER, tiles, "alex rivera", null);
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertEquals(0, d.index);
    }

    @Test
    public void worksOnTheSeeThroughChooserToo() {
        assertEquals(ChooserTiles.Act.SELECT, decide(TRANSPARENT_CHOOSER, household(), "Sam", null).act);
    }

    // --- Refusing when it isn't sure ---

    @Test
    public void refusesTwoTilesWithTheSameName() {
        List<ChooserTiles.Tile> tiles = Arrays.asList(tile("Sam", null, false, false), tile("Sam", null, false, false));
        ChooserTiles.Decision d = decide(CHOOSER, tiles, "Sam", null);
        assertEquals(ChooserTiles.Act.REFUSE, d.act);
    }

    @Test
    public void refusesTwoTilesWithTheSameStandIn() {
        List<ChooserTiles.Tile> tiles = Arrays.asList(tile("Sam Lee", null, false, false), tile("sam-lee", null, false, false));
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, tiles, "SAM LEE", null).act);
    }

    @Test
    public void refusesTwoTilesWithTheSameAddress() {
        List<ChooserTiles.Tile> tiles = Arrays.asList(tile("Sam", "sam@example.com", false, false),
                tile("Sam", "sam@example.com", false, false));
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, tiles, "Sam", "sam@example.com").act);
    }

    @Test
    public void refusesWhenTheAddressIsOnNoTileRatherThanGuessByName() {
        // Someone else of the same name could be on the TV: no guessing
        ChooserTiles.Decision d = decide(CHOOSER, household(), "Sam", "another.sam@example.com");
        assertEquals(ChooserTiles.Act.REFUSE, d.act);
    }

    @Test
    public void refusesWhenTheAddressesTileHasAnotherName() {
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, household(), "Alex Rivera", "sam@example.com").act);
    }

    @Test
    public void refusesANameOnNoTile() {
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, household(), "Robin", null).act);
    }

    @Test
    public void refusesNobody() {
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, household(), null, null).act);
        assertEquals(ChooserTiles.Act.REFUSE, decide(CHOOSER, household(), "  ", null).act);
    }

    @Test
    public void waitsWhileTheChooserHasNoTilesYet() {
        assertEquals(ChooserTiles.Act.WAIT, decide(CHOOSER, new ArrayList<>(), "Sam", null).act);
    }

    @Test
    public void waitsWhileAnotherScreenThanTheChooserIsInFront() {
        assertEquals(ChooserTiles.Act.WAIT, decide(HOME, household(), "Sam", null).act);
        assertEquals(ChooserTiles.Act.WAIT, decide(null, household(), "Sam", null).act);
    }

    // --- Never on a PIN screen ---

    @Test
    public void neverActsOnAPinLockOrAccountScreen() {
        for (String guard : new String[]{REAUTH, LOCK, VERIFY, KIDS_PIN}) {
            ChooserTiles.Decision d = decide(guard, household(), "Sam", "sam@example.com");
            assertEquals(guard, ChooserTiles.Act.REFUSE, d.act);
        }
    }

    @Test
    public void neverActsWhenTheWindowAsksForAPin() {
        List<ChooserTiles.Tile> tiles = household();
        for (String prompt : new String[]{"Enter your PIN", "Verify your identity", "Enter your Google PIN",
                "Password", "Enter the parent PIN to leave"}) {
            List<String> texts = texts(tiles);
            texts.add(prompt);
            ChooserTiles.Decision d = ChooserTiles.decide(CHOOSER, texts, false, tiles, "Sam", "sam@example.com");
            assertEquals(prompt, ChooserTiles.Act.REFUSE, d.act);
        }
    }

    @Test
    public void neverActsWhenTheWindowHasATextField() {
        List<ChooserTiles.Tile> tiles = household();
        ChooserTiles.Decision d = ChooserTiles.decide(CHOOSER, texts(tiles), true, tiles, "Sam", "sam@example.com");
        assertEquals(ChooserTiles.Act.REFUSE, d.act);
    }

    @Test
    public void aLockedTileIsStillSelectableGooglesPinThenDecides() {
        // "Profile locked" on a tile only says Google will ask for the PIN after the pick
        ChooserTiles.Decision d = decide(CHOOSER, household(), "Alex Rivera", "alex@example.com");
        assertEquals(ChooserTiles.Act.SELECT, d.act);
        assertFalse(ChooserTiles.looksLikePinScreen(texts(household()), false));
    }

    @Test
    public void guardClasses() {
        assertTrue(ChooserTiles.isGuardClass(REAUTH));
        assertTrue(ChooserTiles.isGuardClass(LOCK));
        assertTrue(ChooserTiles.isGuardClass(VERIFY));
        assertTrue(ChooserTiles.isGuardClass(KIDS_PIN));
        assertFalse(ChooserTiles.isGuardClass(CHOOSER));
        assertFalse(ChooserTiles.isGuardClass(TRANSPARENT_CHOOSER));
        assertFalse(ChooserTiles.isGuardClass(HOME));
        assertFalse(ChooserTiles.isGuardClass(null));
    }

    // --- Focus check before the click ---

    @Test
    public void clicksOnlyWhenFocusLandedOnThatTile() {
        ChooserTiles.Tile sam = household().get(1);
        assertTrue(ChooserTiles.focusLanded(sam, "Sam", sam.description));
        assertFalse(ChooserTiles.focusLanded(sam, "Alex Rivera", household().get(0).description));
        // Same name, another account
        assertFalse(ChooserTiles.focusLanded(sam, "Sam", "Sam, other@example.com, : select to log in"));
        assertFalse(ChooserTiles.focusLanded(sam, null, null));
        assertFalse(ChooserTiles.focusLanded(null, "Sam", sam.description));
        // Google may word the focused tile's description differently: the name and address are what count
        assertTrue(ChooserTiles.focusLanded(sam, "Sam", "Sam, sam@example.com, selected"));
        // A tile without an address only matches one without
        ChooserTiles.Tile bare = new ChooserTiles.Tile("Sam", null, false);
        assertTrue(ChooserTiles.focusLanded(bare, "Sam", "Sam: select to log in"));
        assertFalse(ChooserTiles.focusLanded(bare, "Sam", "Sam, sam@example.com"));
    }
}
