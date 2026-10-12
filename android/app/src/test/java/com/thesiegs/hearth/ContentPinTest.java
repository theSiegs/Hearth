package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.junit.Test;

/**
 * Paramount+'s content PIN: recognising its dialog, who may have it typed, and reading the app's answer. From the
 * recording of the real dialog (digits masked; made-up PINs and names here).
 */
public class ContentPinTest {

    private static List<CharSequence> text(String... parts) {
        return new ArrayList<>(Arrays.asList(parts));
    }

    // ---- The dialog, from its window event's text ----

    @Test
    public void recognisesTheDialogFromItsWindowText() {
        assertTrue(ContentPin.isDialogText(text("Parental Controls", "Enter your PIN to watch.",
                "Forgot PIN? Visit https://www.paramountplus.com/setPIN", "Enter 4 digit pin", "1", "2", "3",
                "Microphone button", "0", "Backspace")));
        // Either line is enough
        assertTrue(ContentPin.isDialogText(text("ENTER YOUR PIN TO WATCH.")));
        assertTrue(ContentPin.isDialogText(text("Parental Controls", "Enter 4 digit pin")));
    }

    @Test
    public void otherWindowsAreNotTheDialog() {
        assertFalse(ContentPin.isDialogText(null));
        assertFalse(ContentPin.isDialogText(text()));
        assertFalse(ContentPin.isDialogText(text("Paramount+")));
        assertFalse(ContentPin.isDialogText(text("Who's watching?", "Alex", "Kids")));
        // The app's own settings page about parental controls isn't the PIN prompt
        assertFalse(ContentPin.isDialogText(text("Parental Controls", "Turn on parental controls")));
        assertFalse(ContentPin.isDialogText(text((String) null)));
    }

    // ---- The dialog, from its nodes (ids pinEdit and tvPinKeyboard) ----

    @Test
    public void typedOnlyOnTheDialogItKnows() {
        assertEquals(PinEntryMachine.Screen.MATCH, ContentPin.screen(true, true, 10, true));
        assertEquals(PinEntryMachine.Screen.MATCH, ContentPin.screen(true, true, 10, false));
        // A key missing, the keypad or the field gone: changed, nothing typed
        assertEquals(PinEntryMachine.Screen.CHANGED, ContentPin.screen(true, true, 9, true));
        assertEquals(PinEntryMachine.Screen.CHANGED, ContentPin.screen(true, false, 0, true));
        assertEquals(PinEntryMachine.Screen.CHANGED, ContentPin.screen(false, true, 10, true));
        assertEquals(PinEntryMachine.Screen.CHANGED, ContentPin.screen(false, false, 0, true));
        // Not up at all
        assertNull(ContentPin.screen(false, false, 0, false));
    }

    @Test
    public void countsTheDigitsInTheField() {
        assertEquals(0, ContentPin.typedCount(null, false));
        assertEquals(0, ContentPin.typedCount("", false));
        assertEquals(1, ContentPin.typedCount("5", false));
        assertEquals(4, ContentPin.typedCount("•••5", false));
        assertEquals(3, ContentPin.typedCount("•••", false));
        // The hint isn't a digit typed, whether or not the node says it's the hint
        assertEquals(0, ContentPin.typedCount("Enter 4 digit pin", true));
        assertEquals(0, ContentPin.typedCount("Enter 4 digit pin", false));
    }

    // ---- The answer ----

    @Test
    public void goneIsAcceptedStillUpIsRejected() {
        assertEquals(PinEntryMachine.Outcome.ACCEPTED, ContentPin.outcome(false, 100));
        assertNull(ContentPin.outcome(true, 0));
        assertNull(ContentPin.outcome(true, ContentPin.REJECT_AFTER_MS - 1));
        assertEquals(PinEntryMachine.Outcome.REJECTED, ContentPin.outcome(true, ContentPin.REJECT_AFTER_MS));
    }

    /** A rejected PIN ends the entry and isn't typed again until a new one is saved. */
    @Test
    public void rejectionStopsAndIsNotRetried() {
        List<String> events = new ArrayList<>();
        PinEntryMachine[] machine = new PinEntryMachine[1];
        machine[0] = new PinEntryMachine(new PinEntryMachine.Driver() {
            @Override
            public void typeDigit(int index) {
                events.add("type " + index);
            }

            @Override
            public void finished(PinEntryMachine.Result result, int digitsTyped) {
                events.add(result + " after " + digitsTyped);
            }
        }, ContentPin.LENGTH);
        machine[0].onScreen(PinEntryMachine.Screen.MATCH);
        for (int i = 0; i < ContentPin.LENGTH; i++) machine[0].onDigit(true);
        machine[0].onOutcome(ContentPin.outcome(true, ContentPin.REJECT_AFTER_MS));
        assertEquals(Arrays.asList("type 0", "type 1", "type 2", "type 3", "REJECTED after 4"), events);
        // Nothing more on that dialog
        machine[0].onScreen(PinEntryMachine.Screen.MATCH);
        assertEquals(5, events.size());
        // And the saved PIN, now marked rejected, isn't typed again
        assertNotNull(ContentPin.whyNot(false, true, true, PinVault.STATUS_REJECTED, false));
    }

    // ---- Who may have it typed ----

    @Test
    public void typedOnlyInAGrownUpsLockedProfile() {
        assertNull(ContentPin.whyNot(false, true, true, PinVault.STATUS_SAVED, false));
    }

    @Test
    public void notInAGrownUpsUnlockedOrUnknownProfile() {
        assertNotNull(ContentPin.whyNot(false, true, false, PinVault.STATUS_SAVED, false));
        assertNotNull(ContentPin.whyNot(false, true, null, PinVault.STATUS_SAVED, false));
    }

    @Test
    public void neverInAKidsProfile() {
        assertNotNull(ContentPin.whyNot(true, false, true, PinVault.STATUS_SAVED, false));
        assertNotNull(ContentPin.whyNot(true, true, true, PinVault.STATUS_SAVED, false));
        // Supervision unreadable: not known to be a grown-up's
        assertNotNull(ContentPin.whyNot(false, false, true, PinVault.STATUS_SAVED, false));
    }

    @Test
    public void notWithoutASavedPinOrWhilePaused() {
        assertNotNull(ContentPin.whyNot(false, true, true, PinVault.STATUS_NONE, false));
        assertNotNull(ContentPin.whyNot(false, true, true, null, false));
        assertNotNull(ContentPin.whyNot(false, true, true, PinVault.STATUS_SAVED, true));
    }

    // ---- The lock, from Google TV's chooser tiles ----

    @Test
    public void readsTheLockFromChooserTiles() {
        assertEquals(Boolean.TRUE, ContentPin.lockedFromTile(
                "Alex, alex@example.com, Profile locked: select to log in", false));
        assertEquals(Boolean.FALSE, ContentPin.lockedFromTile("Sam, sam@example.com, : select to log in", false));
        assertEquals(Boolean.TRUE, ContentPin.lockedFromTile(
                "Alex, alex@example.com, Profile locked: select to continue with current account", true));
        // The current account's tile without the words may leave the lock out: what's known stays
        assertNull(ContentPin.lockedFromTile("Alex, alex@example.com, : select to continue with current account",
                true));
        assertNull(ContentPin.lockedFromTile(null, false));
    }

    // ---- Once per dialog ----

    @Test
    public void oneEntryPerDialog() {
        ContentPin.Trigger trigger = new ContentPin.Trigger();
        assertTrue(trigger.onWindow(true));
        // The same dialog's further window events
        assertFalse(trigger.onWindow(true));
        assertFalse(trigger.onWindow(true));
        // Another window (the player), then the dialog again for the next title
        assertFalse(trigger.onWindow(false));
        assertTrue(trigger.onWindow(true));
    }
}
