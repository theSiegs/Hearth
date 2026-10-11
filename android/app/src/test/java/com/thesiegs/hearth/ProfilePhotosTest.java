package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Random;

import org.junit.Test;

/** Profile photos from Google TV's chooser: which tile may be photographed, and placeholders never win. */
public class ProfilePhotosTest {
    // As Google TV's chooser describes its tiles: a PIN-protected profile says "Profile locked"
    private static final String LOCKED_CURRENT =
            "Alex Rivera, alex@example.com, Profile locked: select to continue with current account";
    private static final String LOCKED = "Robin Rivera, robin@example.com, Profile locked: select to log in";
    private static final String UNLOCKED_CURRENT = "Sam Rivera, sam@example.com, : select to continue with current account";
    private static final String UNLOCKED = "Jo Rivera, jo@example.com, : select to log in";

    @Test
    public void currentAccountTileOnlyWhileItsProfileRuns() {
        // Focused, the current account's tile shows its photo, PIN or not
        assertNull(ChooserPhotos.whyNot("Alex", LOCKED_CURRENT, "Alex", LOCKED_CURRENT, true));
        assertNull(ChooserPhotos.whyNot("Sam", UNLOCKED_CURRENT, "Sam", UNLOCKED_CURRENT, true));
        // Mid-switch it may still be drawn locked
        assertNotNull(ChooserPhotos.whyNot("Alex", LOCKED_CURRENT, "Alex", LOCKED_CURRENT, false));
    }

    @Test
    public void anyTileWithoutAPinLock() {
        assertNull(ChooserPhotos.whyNot("Jo", UNLOCKED, "Alex", LOCKED_CURRENT, true));
        // Whoever is on, and even mid-switch: an unlocked tile never shows a lock
        assertNull(ChooserPhotos.whyNot("Jo", UNLOCKED, "Sam", UNLOCKED_CURRENT, false));
        assertNull(ChooserPhotos.whyNot("Jo", UNLOCKED, null, null, true));
    }

    @Test
    public void neverALockedTileThatIsntTheRunningOne() {
        assertNotNull(ChooserPhotos.whyNot("Robin", LOCKED, "Alex", LOCKED_CURRENT, true));
        assertNotNull(ChooserPhotos.whyNot("Robin", LOCKED, "Sam", UNLOCKED_CURRENT, true));
    }

    @Test
    public void nothingWithoutAFocusedTile() {
        assertNotNull(ChooserPhotos.whyNot(null, null, "Alex", LOCKED_CURRENT, true));
        assertNotNull(ChooserPhotos.whyNot("", null, "Alex", LOCKED_CURRENT, true));
    }

    @Test
    public void lockedTilesAreToldByTheirDescription() {
        assertTrue(ChooserPhotos.isLockedTile(LOCKED));
        assertTrue(ChooserPhotos.isLockedTile("ALEX, PROFILE LOCKED: SELECT"));
        assertFalse(ChooserPhotos.isLockedTile(UNLOCKED));
        assertFalse(ChooserPhotos.isLockedTile(null));
    }

    @Test
    public void aPlaceholderNeverReplacesARealPhoto() {
        assertEquals(ProfileAvatars.KEEP, ProfileAvatars.decide(true, true, false, false));
        assertEquals(ProfileAvatars.KEEP, ProfileAvatars.decide(true, true, false, true));
    }

    @Test
    public void aPlaceholderIsKeptOnlyUntilThereIsAPhoto() {
        // No photo yet: better than nothing, and the profile stays due
        assertEquals(ProfileAvatars.WRITE, ProfileAvatars.decide(true, false, false, false));
        // A different placeholder replaces the old one; the same one changes nothing
        assertEquals(ProfileAvatars.WRITE, ProfileAvatars.decide(true, true, true, false));
        assertEquals(ProfileAvatars.KEEP, ProfileAvatars.decide(true, true, true, true));
        // The real photo replaces a placeholder
        assertEquals(ProfileAvatars.WRITE, ProfileAvatars.decide(false, true, true, false));
    }

    @Test
    public void realPhotosAreWrittenWhenNewOrChanged() {
        assertEquals(ProfileAvatars.WRITE, ProfileAvatars.decide(false, false, false, false));
        assertEquals(ProfileAvatars.WRITE, ProfileAvatars.decide(false, true, false, false));
        assertEquals(ProfileAvatars.TOUCH, ProfileAvatars.decide(false, true, false, true));
        // A provisional photo that is in fact the real one stops being provisional
        assertEquals(ProfileAvatars.TOUCH, ProfileAvatars.decide(false, true, true, true));
    }

    private static final int SIZE = 128;

    /** Google's placeholder: an initial (a thick "L", anti-aliased edges) on a plain circle, on the chooser's dark. */
    private static int[] placeholder(int background, int letter) {
        int[] px = new int[SIZE * SIZE];
        float c = (SIZE - 1) / 2f;
        for (int y = 0; y < SIZE; y++) {
            for (int x = 0; x < SIZE; x++) {
                float dx = x - c;
                float dy = y - c;
                int p = dx * dx + dy * dy > (SIZE / 2f) * (SIZE / 2f) ? 0xff101010 : background;
                boolean stem = x >= 44 && x < 58 && y >= 34 && y < 94;
                boolean foot = x >= 44 && x < 86 && y >= 80 && y < 94;
                if (stem || foot) p = letter;
                // Anti-aliased edge around the letter
                boolean edge = (x == 43 || x == 58) && y >= 34 && y < 94 || (y == 33 || y == 94) && x >= 44 && x < 86;
                if (edge) p = mix(background, letter);
                px[y * SIZE + x] = p;
            }
        }
        return px;
    }

    private static int mix(int a, int b) {
        int r = (((a >> 16) & 0xff) + ((b >> 16) & 0xff)) / 2;
        int g = (((a >> 8) & 0xff) + ((b >> 8) & 0xff)) / 2;
        int bl = ((a & 0xff) + (b & 0xff)) / 2;
        return 0xff000000 | (r << 16) | (g << 8) | bl;
    }

    @Test
    public void placeholderInitialsAreRecognised() {
        assertTrue(ProfileAvatars.looksLikePlaceholder(placeholder(0xff7b1fa2, 0xffffffff), SIZE));
        assertTrue(ProfileAvatars.looksLikePlaceholder(placeholder(0xff0b8043, 0xffffffff), SIZE));
        // Just the plain circle, before the initial is drawn
        assertTrue(ProfileAvatars.looksLikePlaceholder(placeholder(0xff5f6368, 0xff5f6368), SIZE));
    }

    @Test
    public void photosAreNotPlaceholders() {
        // A photo: smooth light and shade with fine detail all over
        Random random = new Random(7);
        int[] photo = new int[SIZE * SIZE];
        for (int y = 0; y < SIZE; y++) {
            for (int x = 0; x < SIZE; x++) {
                int r = Math.min(255, 40 + x + random.nextInt(40));
                int g = Math.min(255, 30 + y + random.nextInt(40));
                int b = Math.min(255, 60 + (x + y) / 3 + random.nextInt(40));
                photo[y * SIZE + x] = 0xff000000 | (r << 16) | (g << 8) | b;
            }
        }
        assertFalse(ProfileAvatars.looksLikePlaceholder(photo, SIZE));
    }

    @Test
    public void illustratedAvatarsAreNotPlaceholders() {
        // One of Google's flat avatars: a background, a face, hair and a shirt
        int[] avatar = new int[SIZE * SIZE];
        float c = (SIZE - 1) / 2f;
        for (int y = 0; y < SIZE; y++) {
            for (int x = 0; x < SIZE; x++) {
                float dx = x - c;
                float dy = y - 52;
                int p = 0xff8ab4f8;
                if (dx * dx + dy * dy < 26 * 26) p = 0xfff6c7a0;
                if (dx * dx + dy * dy < 30 * 30 && y < 40) p = 0xff5d4037;
                if (y > 84 && Math.abs(dx) < 40) p = 0xffe53935;
                avatar[y * SIZE + x] = p;
            }
        }
        assertFalse(ProfileAvatars.looksLikePlaceholder(avatar, SIZE));
    }
}
