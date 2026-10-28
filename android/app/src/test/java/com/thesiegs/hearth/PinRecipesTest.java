package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Hearth's own recipes (the asset pin-recipes.json, run by DataPinRecipe): their reading of what each app says, and
 * the D-pad route to every key on each keypad, from the recordings of the real PIN screens (digits shown as they'd be
 * spoken; these are made-up PIN screens, not anyone's PIN).
 */
public class PinRecipesTest {

    private static DataPinRecipe netflix() {
        return PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, new PinFakes.Clock());
    }

    private static DataPinRecipe max() {
        return PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.MAX, new PinFakes.Clock());
    }

    // ---- Routes: from every key to every key, on the keypad as it is on screen ----

    /** A keypad as laid out on screen: labels by row, null for an empty place, "DEL" for a wide Delete key. */
    private static void assertRoutes(String name, String pkg, String[][] screen) {
        PinRecipeSpec recipe = PinFakes.spec(PinRecipeSpec.SLOT_PROFILE, pkg);
        for (char from = '0'; from <= '9'; from++) {
            for (char to = '0'; to <= '9'; to++) {
                if (from == to) continue;
                int[] at = recipe.position(from);
                int moves = 0;
                while (!(at[0] == recipe.position(to)[0] && at[1] == recipe.position(to)[1])) {
                    int move = DataPinRecipe.nextMove(at, recipe.position(to), recipe.lastRow());
                    at = new int[] {at[0] + (move == PinNode.Host.DOWN ? 1 : move == PinNode.Host.UP ? -1 : 0),
                            at[1] + (move == PinNode.Host.RIGHT ? 1 : move == PinNode.Host.LEFT ? -1 : 0)};
                    String key = at[0] >= 0 && at[0] < screen.length && at[1] >= 0 && at[1] < screen[at[0]].length
                            ? screen[at[0]][at[1]] : null;
                    assertTrue(name + " " + from + "→" + to + " lands on a digit key, not " + key,
                            key != null && key.length() == 1 && Character.isDigit(key.charAt(0)));
                    assertTrue(name + " " + from + "→" + to + " takes too many moves", ++moves <= 9);
                }
                assertEquals(String.valueOf(to), screen[at[0]][at[1]]);
            }
        }
    }

    @Test
    public void netflixRoutesStayOnDigitKeys() {
        assertRoutes("Netflix", ProfilePairing.NETFLIX, new String[][] {
                {"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"}, {"0", "DEL", "DEL"}});
    }

    @Test
    public void maxRoutesStayOnDigitKeys() {
        assertRoutes("HBO Max", ProfilePairing.MAX, new String[][] {
                {"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"}, {null, "0", null}});
    }

    @Test
    public void appleTvRoutesStayOnDigitKeys() {
        assertRoutes("Apple TV", ProfilePairing.APPLE_TV, new String[][] {
                {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "DEL"}});
    }

    // ---- What the apps say ----

    @Test
    public void netflixPinScreenAndAnswers() {
        DataPinRecipe netflix = netflix();
        assertNull(netflix.recognize((PinNode) null));
        netflix.onSpeech("On the PIN entry screen.");
        assertNull("waits for the keyboard's description", netflix.recognize((PinNode) null));
        netflix.onSpeech("In the numeric keyboard. This is a keyboard with 4 rows and 3 columns. The last row contains"
                + " 0 and Delete keys. ");
        assertEquals(PinEntryMachine.Screen.MATCH, netflix.recognize((PinNode) null));
        assertNull(netflix.outcome((PinNode) null));
        netflix.onSpeech("Checking PIN");
        assertNull(netflix.outcome((PinNode) null));
        netflix.onSpeech("Whoops, wrong PIN. Please try again.");
        assertEquals(PinEntryMachine.Outcome.REJECTED, netflix.outcome((PinNode) null));

        DataPinRecipe right = netflix();
        right.onSpeech("On the browse screen. Use the up arrow to get to the navigation menu and profiles, and down to"
                + " browse movies, shows and games.");
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, right.outcome((PinNode) null));
    }

    @Test
    public void netflixKeyboardLaidOutDifferentlyIsAChangedScreen() {
        DataPinRecipe netflix = netflix();
        netflix.onSpeech("On the PIN entry screen.");
        netflix.onSpeech("In the numeric keyboard. This is a keyboard with 2 rows and 6 columns.");
        assertEquals(PinEntryMachine.Screen.CHANGED, netflix.recognize((PinNode) null));
    }

    @Test
    public void maxPinScreenAndAnswers() {
        DataPinRecipe max = max();
        max.onSpeech("Alex’s profile selected");
        assertNull(max.recognize((PinNode) null));
        max.onSpeech("Enter Your Profile PIN, Alex’s profile, , Required, Text Input, Empty, Forgot PIN? Reset it at"
                + " h, b, o, m, a, x, Dot, c, o, m, Forward slash, e, d, i, t, p, r, o, f, i, l, e, s,, Numeric"
                + " Keyboard, 1, Button,  Actions are on the far right, . Close keyboard and");
        assertEquals(PinEntryMachine.Screen.MATCH, max.recognize((PinNode) null));
        max.onSpeech("That PIN doesn’t look right.");
        assertEquals(PinEntryMachine.Outcome.REJECTED, max.outcome((PinNode) null));

        DataPinRecipe right = max();
        right.onSpeech("H B O Max Home, . Featured, Some Show, Season 1, Episode 1, Button");
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, right.outcome((PinNode) null));
    }

    @Test
    public void appleTvKeyLabels() {
        assertEquals("1", DataPinRecipe.afterLastComma("Enter 4-Digit Code, Use the 4-digit code for Alex's profile.,"
                + " Keyboard, 1"));
        assertEquals("7", DataPinRecipe.afterLastComma("7"));
        assertEquals("Delete", DataPinRecipe.afterLastComma("Delete"));
    }

    @Test
    public void aProfilePinIsTypedOnlyForItsOwnerWhenTheirProfileIsLocked() {
        // An adult's profile needs its own Google TV PIN lock (unknown counts as not)
        assertNull(ProfilePairingService.whyNotProfilePin(false, true, true, 0, false));
        assertNotNull(ProfilePairingService.whyNotProfilePin(false, false, true, 0, false));
        assertNotNull(ProfilePairingService.whyNotProfilePin(false, null, true, 0, false));
        // A kid's PIN is the parent's, saved for that kid
        assertNull(ProfilePairingService.whyNotProfilePin(true, null, true, 0, false));
        // Nothing saved by this profile, paused, or rejected twice: not typed
        assertNotNull(ProfilePairingService.whyNotProfilePin(false, true, false, 0, false));
        assertNotNull(ProfilePairingService.whyNotProfilePin(false, true, true, 0, true));
        assertNull(ProfilePairingService.whyNotProfilePin(false, true, true, 1, false));
        assertNotNull(ProfilePairingService.whyNotProfilePin(false, true, true, 2, false));
    }

    @Test
    public void eachProfilesPinsAreItsOwn() {
        String alex = PinVault.id("user:0:alex", "com.example.tv", "Alex  M");
        assertEquals("of|user:0:alex|com.example.tv|alex m", alex);
        assertNotEquals(alex, PinVault.id("user:0:sam", "com.example.tv", "Alex M"));
        // The whole TV's (the content PIN) keeps its old form
        assertEquals("com.example.tv|#content-pin", PinVault.id(PinVault.SHARED, "com.example.tv", "#content-pin"));
    }
}
