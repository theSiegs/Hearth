package com.thesiegs.hearth;

import java.util.List;
import java.util.Locale;

/**
 * Paramount+'s content PIN: an account-wide PIN (not a profile's) the app asks for when a title starts, in a dialog
 * over its player ("Parental Controls", "Enter your PIN to watch.", a 4-digit field id/pinEdit and a keypad
 * id/tvPinKeyboard whose digit keys carry their digit as text). The parent saves it once in Hearth (PinVault, under
 * {@link #VAULT_PROFILE}), and Profile Pairing types it behind its cover card, but only in a grown-up's profile that
 * is itself PIN-locked in Google TV: otherwise a kid could switch to an unlocked grown-up's profile and have Hearth
 * type the PIN for them. A kids' profile never gets it typed.
 *
 * Pure logic here (tested without a TV); {@link ParamountContentPinRecipe} reads the dialog and types, and
 * ProfilePairingService runs the entry.
 */
final class ContentPin {
    static final String PACKAGE = ProfilePairing.PARAMOUNT;
    /** The PinVault entry the content PIN is kept under (Paramount+ profile PINs aren't typed, so it's free). */
    static final String VAULT_PROFILE = "#content-pin";
    /** What Profile Pairing's "Change PIN" asks Hearth's Settings to open: Streaming app PINs. */
    static final String SETTINGS_TARGET = "content_pin";
    static final int LENGTH = 4;
    /** No wrong-PIN message was seen: the dialog still up this long after the last digit means it was rejected. */
    static final long REJECT_AFTER_MS = 2_500;

    private ContentPin() {
    }

    /** A window's text (TYPE_WINDOW_STATE_CHANGED) is the content PIN dialog's. English only, like the recordings. */
    static boolean isDialogText(List<CharSequence> text) {
        if (text == null || text.isEmpty()) return false;
        StringBuilder all = new StringBuilder();
        for (CharSequence t : text) {
            if (t != null) all.append(t).append('\n');
        }
        String lower = all.toString().toLowerCase(Locale.ROOT);
        return lower.contains("enter your pin to watch")
                || (lower.contains("parental controls") && lower.contains("digit pin"));
    }

    /**
     * What the dialog's nodes make of it: MATCH with the field and a keypad of all ten digit keys; CHANGED when it's
     * there (any of its parts, or its text) but not laid out that way; null when it isn't up.
     */
    static PinEntryMachine.Screen screen(boolean field, boolean keyboard, int digitKeys, boolean dialogText) {
        if (field && keyboard && digitKeys == 10) return PinEntryMachine.Screen.MATCH;
        if (field || keyboard || dialogText) return PinEntryMachine.Screen.CHANGED;
        return null;
    }

    /**
     * How many digits the field holds: it shows "•••#" (dots, the last digit briefly). Its hint ("Enter 4 digit
     * pin"), or any text with letters in it, counts as none.
     */
    static int typedCount(CharSequence text, boolean showingHint) {
        if (text == null || showingHint) return 0;
        int count = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (Character.isLetter(c)) return 0;
            if (!Character.isWhitespace(c)) count++;
        }
        return count;
    }

    /** After the last digit: gone means taken; still up after REJECT_AFTER_MS means rejected; else still deciding. */
    static PinEntryMachine.Outcome outcome(boolean dialogUp, long sinceLastDigitMs) {
        if (!dialogUp) return PinEntryMachine.Outcome.ACCEPTED;
        return sinceLastDigitMs >= REJECT_AFTER_MS ? PinEntryMachine.Outcome.REJECTED : null;
    }

    /**
     * Why Hearth mustn't type the content PIN now, or null when it may: only in a grown-up's profile (not a kids'
     * one, and in a grown-ups' user) whose Google TV profile is known to be PIN-locked (unknown counts as not), with
     * a saved PIN that wasn't rejected (never retried on its own: a new one is saved in Settings) and entry not paused.
     */
    static String whyNot(boolean kids, boolean grownUpsUser, Boolean profileLocked, String pinStatus,
            boolean paused) {
        if (kids) return "a kids' profile";
        if (!grownUpsUser) return "not a grown-up's profile";
        if (profileLocked == null) return "the profile's lock isn't known yet";
        if (!profileLocked) return "the profile has no Google TV PIN lock";
        if (pinStatus == null || PinVault.STATUS_NONE.equals(pinStatus)) return "no content PIN saved";
        if (PinVault.STATUS_REJECTED.equals(pinStatus)) return "the saved PIN was rejected; waiting for a new one";
        if (paused) return "PIN entry is paused for the app";
        return null;
    }

    /**
     * What a chooser tile says about its profile's PIN lock: locked when its description says "Profile locked", not
     * locked when it doesn't; null (keep what's known) for the current account's tile without the words, which may
     * leave the lock out. The lock is read again whenever the chooser shows the tile as any other, which it does
     * before anyone can switch to that profile.
     */
    static Boolean lockedFromTile(String description, boolean current) {
        if (description == null) return null;
        boolean locked = ChooserPhotos.isLockedTile(description);
        if (current && !locked) return null;
        return locked;
    }

    /**
     * One entry per appearance of the dialog: it's armed again only once another window (not the dialog, Hearth's
     * own or the system's) comes up, so the dialog's own repeated window events don't start another entry.
     */
    static final class Trigger {
        private boolean mArmed = true;

        /** A window came up; true when it's the dialog and an entry may start for it. */
        synchronized boolean onWindow(boolean dialog) {
            if (!dialog) {
                mArmed = true;
                return false;
            }
            if (!mArmed) return false;
            mArmed = false;
            return true;
        }
    }
}
