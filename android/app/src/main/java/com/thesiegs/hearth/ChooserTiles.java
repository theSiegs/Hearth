package com.thesiegs.hearth;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Which of Google TV's profile chooser tiles Hearth's own profile picker may select for the person picked there
 * (OwnChooser). Hearth only ever focuses and clicks one profile tile in Google's chooser, so Google itself makes the
 * switch and its own PIN screen still decides. Everything here says no unless it's sure:
 * <ul>
 * <li>only on the chooser itself, never on a PIN, lock, account check or any other screen;</li>
 * <li>never when the window shows anything that looks like a PIN or password entry, whatever its class;</li>
 * <li>exactly one tile must match: by the Google account address when Hearth knows the person's and the tiles show
 * addresses, else by the name, else by the name's stand-in (its slug, as household refs use). Two matches: no.</li>
 * </ul>
 * When it says no, Google's chooser stays on screen for the person to use. Pure, for tests.
 */
final class ChooserTiles {
    private ChooserTiles() {
    }

    /** One profile tile as the chooser shows it. */
    static final class Tile {
        final String name;
        final String description;
        final boolean focused;

        Tile(String name, String description, boolean focused) {
            this.name = name;
            this.description = description;
            this.focused = focused;
        }

        String email() {
            return GoogleTvAccount.emailIn(description);
        }
    }

    /** What to do now. */
    enum Act { SELECT, WAIT, REFUSE }

    static final class Decision {
        final Act act;
        /** The tile to select (SELECT only). */
        final int index;
        /** Why not (WAIT, REFUSE), for the log: never a name or an address. */
        final String why;

        private Decision(Act act, int index, String why) {
            this.act = act;
            this.index = index;
            this.why = why;
        }

        static Decision select(int index) {
            return new Decision(Act.SELECT, index, null);
        }

        static Decision waitFor(String why) {
            return new Decision(Act.WAIT, -1, why);
        }

        static Decision refuse(String why) {
            return new Decision(Act.REFUSE, -1, why);
        }

        @Override
        public String toString() {
            return act + (index >= 0 ? " " + index : "") + (why != null ? " (" + why + ")" : "");
        }
    }

    /** Google TV's chooser, in either form (ProfileChooserActivity or ProfileChooserTransparentActivity). */
    static boolean isChooserClass(String className) {
        return className != null
                && className.startsWith(LauncherAccessibilityService.GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooser");
    }

    /**
     * Whether a window class is one of the screens that guard a profile: a PIN, the profile lock, an account check or
     * reauth, a kids profile's PIN. ProfileLock.isChooserLike also counts the chooser; this doesn't.
     */
    static boolean isGuardClass(String className) {
        if (className == null) return false;
        if (isChooserClass(className)) return false;
        String c = className.toLowerCase(Locale.ROOT);
        return c.contains("reauth") || c.contains("accountverification") || c.contains("pin")
                || c.contains(".profile.lock.") || c.contains("password") || c.contains("verify");
    }

    /**
     * Whether a window's texts look like a PIN or password screen: "Enter your PIN", "Verify your identity", a
     * password, or a text field at all (the chooser has none). The chooser's own "Profile locked" on a tile doesn't
     * count: that's a tile saying it will ask.
     */
    static boolean looksLikePinScreen(List<String> texts, boolean hasTextField) {
        if (hasTextField) return true;
        if (texts == null) return false;
        for (String text : texts) {
            if (text == null) continue;
            String t = text.toLowerCase(Locale.ROOT);
            if (t.matches("(?s).*\\bpin\\b.*") || t.contains("verify your identity") || t.contains("password")
                    || t.contains("passcode") || t.contains("enter your")) {
                return true;
            }
        }
        return false;
    }

    /**
     * Which tile to select for the person picked in Hearth's picker.
     *
     * @param frontClass  the class of the window in front, as Hearth's service last heard it (null: unknown)
     * @param texts       the window's visible texts (not the tiles' descriptions)
     * @param textField   the window has a text field
     * @param tiles       its profile tiles, in screen order (empty: not laid out yet)
     * @param name        the picked person's Google TV profile name (null: only the address is known)
     * @param email       the picked person's Google account address (null: not known)
     */
    static Decision decide(String frontClass, List<String> texts, boolean textField, List<Tile> tiles, String name,
            String email) {
        // Never on a PIN, lock or account check, whatever else the window says
        if (isGuardClass(frontClass)) return Decision.refuse("a PIN or lock screen is in front");
        if (looksLikePinScreen(texts, textField)) return Decision.refuse("the window looks like a PIN screen");
        if (!isChooserClass(frontClass)) return Decision.waitFor("the chooser isn't in front yet");
        if (tiles.isEmpty()) return Decision.waitFor("no profile tiles yet");
        if ((name == null || name.trim().isEmpty()) && (email == null || email.isEmpty())) {
            return Decision.refuse("nobody to look for");
        }

        // By address: the most certain, when Hearth has one and the tiles show them
        boolean tilesShowEmails = false;
        for (Tile tile : tiles) tilesShowEmails |= tile.email() != null;
        if (email != null && !email.isEmpty() && tilesShowEmails) {
            List<Integer> byEmail = new ArrayList<>();
            for (int i = 0; i < tiles.size(); i++) {
                if (email.equalsIgnoreCase(tiles.get(i).email())) byEmail.add(i);
            }
            if (byEmail.size() == 1) {
                Tile tile = tiles.get(byEmail.get(0));
                // A name that says someone else on the same address: something's off
                if (name != null && !name.trim().isEmpty() && tile.name != null
                        && !ProfileUsers.slug(name.trim()).equals(ProfileUsers.slug(tile.name.trim()))) {
                    return Decision.refuse("the tile with that address has another name");
                }
                return Decision.select(byEmail.get(0));
            }
            if (byEmail.size() > 1) return Decision.refuse("more than one tile has that address");
            // The address isn't on any tile: a name match could be someone else of the same name
            return Decision.refuse("no tile has that address");
        }
        if (name == null || name.trim().isEmpty()) return Decision.refuse("no name to look for, and no addresses shown");

        String wanted = name.trim();
        Decision byName = only(tiles, wanted, false);
        if (byName != null) return byName;
        // The stand-in: the name's slug, as the household ref has it ("Alex Rivera", "alex rivera")
        Decision bySlug = only(tiles, wanted, true);
        if (bySlug != null) return bySlug;
        return Decision.refuse("no tile has that name");
    }

    /** The one tile named {@code wanted} (exactly, or by slug); a refusal for two or more; null for none. */
    private static Decision only(List<Tile> tiles, String wanted, boolean bySlug) {
        String key = bySlug ? ProfileUsers.slug(wanted) : wanted;
        int found = -1;
        for (int i = 0; i < tiles.size(); i++) {
            String tileName = tiles.get(i).name;
            if (tileName == null || tileName.trim().isEmpty()) continue;
            String other = bySlug ? ProfileUsers.slug(tileName.trim()) : tileName.trim();
            if (!key.equals(other)) continue;
            if (found >= 0) return Decision.refuse("more than one tile has that name");
            found = i;
        }
        return found >= 0 ? Decision.select(found) : null;
    }

    /**
     * After Hearth asked for focus on the tile: whether the focused tile is that one, by its name and the address in
     * its description (none on both, or the same). Only then is it clicked.
     */
    static boolean focusLanded(Tile wanted, String focusedName, String focusedDescription) {
        if (wanted == null || wanted.name == null || focusedName == null) return false;
        if (!focusedName.trim().equals(wanted.name.trim())) return false;
        String a = wanted.email();
        String b = GoogleTvAccount.emailIn(focusedDescription);
        return a == null ? b == null : a.equalsIgnoreCase(b);
    }
}
