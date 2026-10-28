package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import com.thesiegs.hearth.PinFakes.Clock;
import com.thesiegs.hearth.PinFakes.Host;
import com.thesiegs.hearth.PinFakes.Keypad;
import com.thesiegs.hearth.PinFakes.Node;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Hearth's own recipes on made-up copies of each app's PIN screen, as recorded (structure only; made-up PINs): what
 * each recognises, which key it presses for a digit, how it confirms the digit and reads the app's answer. These are
 * what the Java recipes they replaced did; the data engine must keep doing it.
 */
public class PinRecipeScreensTest {
    private static final String PIN = "4071";

    /** Types one digit, letting the clock run until the recipe answers; what it answered. */
    private static Boolean type(DataPinRecipe recipe, Host host, PinNode root, char digit, Clock clock) {
        Boolean[] result = new Boolean[1];
        recipe.type(host, root, digit, ok -> result[0] = ok);
        for (int i = 0; i < 400 && result[0] == null; i++) clock.advance(50);
        assertNotNull("the recipe answered", result[0]);
        return result[0];
    }

    // ---- Disney+: clickable keys under pinCodeKeyboard, the field's length, an error text ----

    private static final String DISNEY = ProfilePairing.DISNEY;

    private static final class Disney {
        final Node root = new Node(DISNEY);
        final Node screen = new Node(DISNEY).id("enterPinRootView");
        final Node field = new Node(DISNEY).id("pinCodeEditText").text("");
        final Node error = new Node(DISNEY).id("pinCodeErrorTextView").hidden();
        final Node keyboard = new Node(DISNEY).id("pinCodeKeyboard");
        final Node[] keys = new Node[10];
        final Node[] labels = new Node[10];
        /** Whether a click puts a digit in (the field grows by one). */
        boolean takes = true;

        Disney() {
            root.add(screen.add(field, error, keyboard));
            for (int d : new int[] {1, 2, 3, 4, 5, 6, 7, 8, 9, 0}) {
                labels[d] = new Node(DISNEY).id("digitKey").text(String.valueOf(d));
                keys[d] = new Node(DISNEY).clickable().add(labels[d]);
                keys[d].onClick = () -> {
                    if (takes) field.text = field.text + "•";
                };
                keyboard.add(keys[d]);
            }
        }
    }

    private static DataPinRecipe disney(Clock clock) {
        return PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, DISNEY, clock);
    }

    @Test
    public void disneyRecognisesItsPinScreen() {
        Disney d = new Disney();
        DataPinRecipe recipe = disney(new Clock());
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize(d.root));
        // Not its PIN screen: keep waiting
        assertNull(recipe.recognize(new Node(DISNEY).add(new Node(DISNEY).text("Who's watching?"))));
        // Its PIN screen laid out otherwise: changed, nothing typed
        Disney noKey = new Disney();
        noKey.keyboard.remove(noKey.keys[5]);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(noKey.root));
        Disney noField = new Disney();
        noField.screen.remove(noField.field);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(noField.root));
        Disney unclickable = new Disney();
        unclickable.keys[3].clickable = false;
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(unclickable.root));
    }

    @Test
    public void disneyClicksEachDigitsKeyAndCountsTheField() {
        Disney d = new Disney();
        Clock clock = new Clock();
        DataPinRecipe recipe = disney(clock);
        Host host = new Host();
        host.root = d.root;
        for (int i = 0; i < 3; i++) {
            char digit = PIN.charAt(i);
            assertTrue(type(recipe, host, d.root, digit, clock));
            assertEquals(1, d.keys[digit - '0'].clicks);
            // The label itself isn't clicked: its clickable key is
            assertEquals(0, d.labels[digit - '0'].clicks);
        }
        assertEquals(3, recipe.typed());
        // The last digit: the app answers at once (field cleared, error shown)
        d.keys[1].onClick = () -> {
            d.field.text = "";
            d.error.visible = true;
            d.error.text = "Incorrect PIN. Please try again.";
        };
        assertTrue(type(recipe, host, d.root, '1', clock));
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome(d.root));
    }

    @Test
    public void disneyAcceptedWhenThePinScreenGoes() {
        Disney d = new Disney();
        Clock clock = new Clock();
        DataPinRecipe recipe = disney(clock);
        Host host = new Host();
        host.root = d.root;
        for (int i = 0; i < 4; i++) assertTrue(type(recipe, host, d.root, PIN.charAt(i), clock));
        assertNull("still deciding", recipe.outcome(d.root));
        Node home = new Node(DISNEY).add(new Node(DISNEY).text("Home"));
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, recipe.outcome(home));
    }

    @Test
    public void disneyDigitThatDoesntShowIsNotConfirmed() {
        Disney d = new Disney();
        d.takes = false;
        Clock clock = new Clock();
        DataPinRecipe recipe = disney(clock);
        Host host = new Host();
        host.root = d.root;
        assertFalse(type(recipe, host, d.root, '4', clock));
        assertEquals(0, recipe.typed());
    }

    @Test
    public void keysArePressedOnlyInTheRecipesOwnApp() {
        Disney d = new Disney();
        Clock clock = new Clock();
        DataPinRecipe recipe = disney(clock);
        Host host = new Host();
        d.root.pkg = "com.example.other";
        host.root = d.root;
        assertFalse(type(recipe, host, d.root, '4', clock));
        assertEquals(0, d.keys[4].clicks);
    }

    // ---- Google TV: ten clickable digit texts, each once; the click is the confirmation ----

    private static final String GOOGLE = LauncherAccessibilityService.GOOGLE_TV_PACKAGE;

    private static Node[] googleKeys;

    private static Node googlePinScreen() {
        Node root = new Node(GOOGLE);
        Node pad = new Node(GOOGLE);
        root.add(new Node(GOOGLE).text("Verify your identity"), new Node(GOOGLE).text("Alex"), pad);
        googleKeys = new Node[10];
        for (int d : new int[] {1, 2, 3, 4, 5, 6, 7, 8, 9, 0}) {
            googleKeys[d] = new Node(GOOGLE).text(String.valueOf(d)).clickable();
            pad.add(googleKeys[d]);
        }
        pad.add(new Node(GOOGLE).desc("Delete").clickable());
        return root;
    }

    @Test
    public void googleTvRecognisesItsKeypad() {
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_GOOGLE_TV, GOOGLE, new Clock());
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize(googlePinScreen()));
        // A digit twice on screen, or a digit that isn't a key: not the keypad it knows (never CHANGED: just wait)
        Node twice = googlePinScreen();
        twice.add(new Node(GOOGLE).text("1"));
        assertNull(recipe.recognize(twice));
        Node unclickable = googlePinScreen();
        googleKeys[6].clickable = false;
        assertNull(recipe.recognize(unclickable));
        // A hidden "1" doesn't count
        Node hidden = googlePinScreen();
        hidden.add(new Node(GOOGLE).text("1").hidden());
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize(hidden));
        // Another app's window
        Node other = googlePinScreen();
        other.pkg = "com.example.other";
        assertNull(recipe.recognize(other));
    }

    @Test
    public void googleTvTypesByClickAndReadsTheAnswer() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_GOOGLE_TV, GOOGLE, clock);
        Node root = googlePinScreen();
        Host host = new Host();
        host.root = root;
        for (int i = 0; i < 4; i++) {
            assertTrue(type(recipe, host, root, PIN.charAt(i), clock));
            assertEquals(1, googleKeys[PIN.charAt(i) - '0'].clicks);
        }
        assertEquals(4_000, recipe.outcomeTimeoutMs());
        clock.advance(2_499);
        assertNull(recipe.outcome(root));
        clock.advance(1);
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome(root));
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, recipe.outcome(new Node(GOOGLE).text("For you")));
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, recipe.outcome(new Node("com.example.other")));
    }

    @Test
    public void googleTvKeyThatWontTakeTheClickIsNotConfirmed() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_GOOGLE_TV, GOOGLE, clock);
        Node root = googlePinScreen();
        googleKeys[4].clickWorks = false;
        Host host = new Host();
        host.root = root;
        assertFalse(type(recipe, host, root, '4', clock));
    }

    // ---- Paramount+'s content PIN: keys inside tvPinKeyboard, dots in pinEdit, a set-text fallback ----

    private static final String PARAMOUNT = ContentPin.PACKAGE;

    private static final class Paramount {
        final Node root = new Node(PARAMOUNT);
        final Node dialog = new Node(PARAMOUNT);
        final Node field = new Node(PARAMOUNT).id("pinEdit").text("Enter 4 digit pin");
        final Node keyboard = new Node(PARAMOUNT).id("tvPinKeyboard");
        final Node[] keys = new Node[10];
        int typed;

        Paramount() {
            field.showingHint = true;
            root.add(dialog.add(new Node(PARAMOUNT).text("Parental Controls"),
                    new Node(PARAMOUNT).text("Enter your PIN to watch."), field, keyboard));
            Node row = new Node(PARAMOUNT);
            keyboard.add(row);
            for (int d : new int[] {1, 2, 3, 4, 5, 6, 7, 8, 9, 0}) {
                keys[d] = new Node(PARAMOUNT).clickable().add(new Node(PARAMOUNT).text(String.valueOf(d)));
                keys[d].onClick = this::digitIn;
                row.add(keys[d]);
            }
            row.add(new Node(PARAMOUNT).desc("Microphone button").clickable(), new Node(PARAMOUNT).text("Backspace"));
        }

        void digitIn() {
            typed++;
            field.showingHint = false;
            StringBuilder dots = new StringBuilder();
            for (int i = 0; i < typed; i++) dots.append('•');
            field.text = dots.toString();
        }
    }

    private static DataPinRecipe paramount(Clock clock) {
        return PinFakes.recipe(PinRecipeSpec.SLOT_CONTENT, PARAMOUNT, clock);
    }

    @Test
    public void paramountRecognisesTheContentPinDialog() {
        DataPinRecipe recipe = paramount(new Clock());
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize(new Paramount().root));
        Paramount noKeyboard = new Paramount();
        noKeyboard.dialog.remove(noKeyboard.keyboard);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(noKeyboard.root));
        Paramount noField = new Paramount();
        noField.dialog.remove(noField.field);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(noField.root));
        Paramount textOnly = new Paramount();
        textOnly.dialog.remove(textOnly.field);
        textOnly.dialog.remove(textOnly.keyboard);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(textOnly.root));
        Paramount missingKey = new Paramount();
        missingKey.keys[8].parent.remove(missingKey.keys[8]);
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(missingKey.root));
        assertNull(recipe.recognize(new Node(PARAMOUNT).add(new Node(PARAMOUNT).text("Paramount+"))));
    }

    @Test
    public void paramountClicksKeysCountsDotsAndIsAcceptedWhenTheDialogGoes() {
        Paramount p = new Paramount();
        Clock clock = new Clock();
        DataPinRecipe recipe = paramount(clock);
        Host host = new Host();
        host.root = p.root;
        for (int i = 0; i < 3; i++) assertTrue(type(recipe, host, p.root, PIN.charAt(i), clock));
        // The 4th sends the PIN: the dialog goes and the title starts
        p.keys[1].onClick = () -> p.root.remove(p.dialog);
        assertTrue(type(recipe, host, p.root, '1', clock));
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, recipe.outcome(p.root));
    }

    @Test
    public void paramountStillUpAfterTheLastDigitIsRejected() {
        Paramount p = new Paramount();
        Clock clock = new Clock();
        DataPinRecipe recipe = paramount(clock);
        Host host = new Host();
        host.root = p.root;
        for (int i = 0; i < 3; i++) assertTrue(type(recipe, host, p.root, PIN.charAt(i), clock));
        // The field clears on the last digit (the app checked it)
        p.keys[1].onClick = () -> {
            p.typed = 0;
            p.field.text = "";
        };
        assertTrue(type(recipe, host, p.root, '1', clock));
        clock.advance(ContentPin.REJECT_AFTER_MS - 200);
        assertNull(recipe.outcome(p.root));
        clock.advance(200);
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome(p.root));
    }

    @Test
    public void paramountSetsTheFieldWhenAKeyWontTakeTheClick() {
        Paramount p = new Paramount();
        Clock clock = new Clock();
        DataPinRecipe recipe = paramount(clock);
        Host host = new Host();
        host.root = p.root;
        assertTrue(type(recipe, host, p.root, '4', clock));
        p.keys[0].clickWorks = false;
        // The fallback sets the field to the digits so far, and it shows one more
        Boolean[] result = new Boolean[1];
        recipe.type(host, p.root, '0', ok -> result[0] = ok);
        assertEquals("40", p.field.setTo);
        p.digitIn();
        clock.advance(200);
        assertEquals(Boolean.TRUE, result[0]);
        assertEquals(2, recipe.typed());
        recipe.close();
    }

    // ---- Apple TV: one row of described keys; focus events; "N of 4 values entered" ----

    private static final String APPLE = ProfilePairing.APPLE_TV;

    private static Node appleKey(String label, boolean first) {
        return new Node(APPLE).clickable().desc(first ? "Enter 4-Digit Code, Use the 4-digit code for Alex's profile.,"
                + " Keyboard, " + label : label);
    }

    private static Node applePinScreen(boolean withDelete) {
        Node root = new Node(APPLE);
        Node row = new Node(APPLE);
        root.add(row);
        boolean first = true;
        for (String label : new String[] {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}) {
            row.add(appleKey(label, first));
            first = false;
        }
        if (withDelete) row.add(appleKey("Delete", false));
        root.add(new Node(APPLE).clickable().desc("Use Password Instead"));
        return root;
    }

    @Test
    public void appleTvRecognisesItsRowOfKeys() {
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, APPLE, new Clock());
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize(applePinScreen(true)));
        assertEquals(PinEntryMachine.Screen.CHANGED, recipe.recognize(applePinScreen(false)));
        assertNull(recipe.recognize(new Node(APPLE).add(new Node(APPLE).desc("Watch Now").clickable())));
    }

    @Test
    public void appleTvMovesAlongTheRowAndCountsTheAnnouncements() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, APPLE, clock);
        Keypad keypad = new Keypad(new String[][] {{"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "DEL"}}, "1");
        keypad.sayFocus = label -> recipe.onFocused(appleKey("DEL".equals(label) ? "Delete" : label, false));
        keypad.sayOk = label -> recipe.onSpeech(keypad.entered.size() + " of 4 values entered");
        Host host = new Host();
        host.keypad = keypad;
        Node root = applePinScreen(true);
        host.root = root;
        recipe.onFocused(appleKey("1", true));
        for (int i = 0; i < 4; i++) assertTrue(type(recipe, host, root, PIN.charAt(i), clock));
        assertEquals(Arrays.asList("4", "0", "7", "1"), keypad.entered);
        // Still up 3 s after the last digit: not taken; gone: taken
        assertNull(recipe.outcome(root));
        clock.advance(3_000);
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome(root));
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, recipe.outcome(new Node(APPLE).text("Loading")));
    }

    @Test
    public void appleTvDigitNotAnnouncedIsNotConfirmed() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, APPLE, clock);
        Keypad keypad = new Keypad(new String[][] {{"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "DEL"}}, "1");
        keypad.sayFocus = label -> recipe.onFocused(appleKey(label, false));
        Host host = new Host();
        host.keypad = keypad;
        recipe.onFocused(appleKey("1", true));
        assertFalse(type(recipe, host, applePinScreen(true), '1', clock));
        assertEquals(Arrays.asList("1"), keypad.entered);
    }

    // ---- Netflix: speech only; the focused key spoken; nothing per digit ----

    @Test
    public void netflixWalksTheGridByWhatItSays() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, clock);
        Keypad keypad = new Keypad(new String[][] {{"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"},
                {"0", "DEL", "DEL"}}, "1");
        keypad.sayFocus = label -> recipe.onSpeech("DEL".equals(label) ? "Delete" : label);
        Host host = new Host();
        host.keypad = keypad;
        recipe.onSpeech("On the PIN entry screen.");
        recipe.onSpeech("In the numeric keyboard. This is a keyboard with 4 rows and 3 columns. The last row contains"
                + " 0 and Delete keys. ");
        recipe.onSpeech("1");
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize((PinNode) null));
        for (int i = 0; i < 4; i++) assertTrue(type(recipe, host, null, PIN.charAt(i), clock));
        assertEquals(Arrays.asList("4", "0", "7", "1"), keypad.entered);
        assertNull(recipe.outcome((PinNode) null));
        recipe.onSpeech("Entered 4 of 4 digits.");
        recipe.onSpeech("Whoops, wrong PIN. Please try again.");
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome((PinNode) null));
    }

    @Test
    public void aMoveTheAppDoesntAnswerStopsBeforeAnyOk() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, clock);
        Keypad keypad = new Keypad(new String[][] {{"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"},
                {"0", "DEL", "DEL"}}, "1");
        Host host = new Host();
        host.keypad = keypad;
        recipe.onSpeech("1");
        assertFalse(type(recipe, host, null, '9', clock));
        assertFalse(host.presses.contains(PinNode.Host.CENTER));
        assertTrue(keypad.entered.isEmpty());
    }

    @Test
    public void aFocusedKeyOffTheDigitsStopsBeforeAnyOk() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, clock);
        Host host = new Host();
        recipe.onSpeech("Delete");
        assertFalse(type(recipe, host, null, '1', clock));
        assertTrue(host.presses.isEmpty());
        // And nothing at all without D-pad actions (Android before 13)
        DataPinRecipe old = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, clock);
        old.onSpeech("1");
        host.canMove = false;
        assertFalse(type(old, host, null, '1', clock));
        assertTrue(host.presses.isEmpty());
    }

    // ---- HBO Max: announcements; an echo per digit; the answer counts for the last ----

    @Test
    public void maxWalksTheGridAndTakesTheAnswerAsTheLastEcho() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.MAX, clock);
        Keypad keypad = new Keypad(new String[][] {{"1", "2", "3"}, {"4", "5", "6"}, {"7", "8", "9"},
                {"", "0", ""}}, "1");
        List<String> said = new ArrayList<>();
        keypad.sayFocus = label -> recipe.onSpeech(", Numeric Keyboard, " + label + ", Button,  Actions are on the"
                + " far right, .");
        keypad.sayOk = label -> {
            said.add(label);
            recipe.onSpeech(said.size() < 4 ? label + "," : "That PIN doesn’t look right.");
        };
        Host host = new Host();
        host.keypad = keypad;
        recipe.onSpeech("Enter Your Profile PIN, Alex’s profile, , Required, Text Input, Empty, Numeric Keyboard, 1,"
                + " Button,  Actions are on the far right, . Close keyboard and");
        assertEquals(PinEntryMachine.Screen.MATCH, recipe.recognize((PinNode) null));
        for (int i = 0; i < 4; i++) assertTrue(type(recipe, host, null, PIN.charAt(i), clock));
        assertEquals(Arrays.asList("4", "0", "7", "1"), keypad.entered);
        assertEquals(PinEntryMachine.Outcome.REJECTED, recipe.outcome((PinNode) null));
    }

    @Test
    public void maxDigitWithoutAnEchoIsNotConfirmed() {
        Clock clock = new Clock();
        DataPinRecipe recipe = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.MAX, clock);
        Host host = new Host();
        recipe.onSpeech("Enter Your Profile PIN, Numeric Keyboard, 1, Button");
        assertFalse(type(recipe, host, null, '1', clock));
        assertEquals(Arrays.asList(PinNode.Host.CENTER), host.presses);
    }

    @Test
    public void lockoutsAreSeenInNetflixAndMax() {
        DataPinRecipe netflix = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX, new Clock());
        netflix.onSpeech("Too many attempts. Try again later.");
        assertEquals(PinEntryMachine.Screen.LOCKED_OUT, netflix.recognize((PinNode) null));
        assertEquals(PinEntryMachine.Outcome.LOCKED_OUT, netflix.outcome((PinNode) null));
        DataPinRecipe max = PinFakes.recipe(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.MAX, new Clock());
        max.onSpeech("Too many tries");
        assertEquals(PinEntryMachine.Screen.LOCKED_OUT, max.recognize((PinNode) null));
        assertEquals(PinEntryMachine.Outcome.LOCKED_OUT, max.outcome((PinNode) null));
    }

    @Test
    public void closeStopsEveryCheck() {
        Clock clock = new Clock();
        Disney d = new Disney();
        d.takes = false;
        DataPinRecipe recipe = disney(clock);
        Host host = new Host();
        host.root = d.root;
        recipe.type(host, d.root, '4', ok -> {
        });
        assertFalse(clock.idle());
        recipe.close();
        assertTrue(clock.idle());
    }
}
