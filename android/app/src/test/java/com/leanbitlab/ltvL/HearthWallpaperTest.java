package com.leanbitlab.ltvL;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

import org.junit.Test;

/** Which wallpaper the provider says Hearth shows, and when its version changes. */
public class HearthWallpaperTest {

    private static final String KID = "wallpapers/user_11/";

    private static String pick(boolean bing, boolean timed, int hour, String... files) {
        Set<String> existing = new HashSet<>(Arrays.asList(files));
        return HearthWallpaper.pick(bing, timed, hour, "wallpapers/user_11", existing::contains);
    }

    @Test
    public void picksLikeWallpaperService() {
        assertEquals("wallpaper_bing", pick(true, true, 12, "wallpaper_bing", KID + "wallpaper_day", KID + "wallpaper"));
        // Bing on but not downloaded yet: what would show without it
        assertEquals(KID + "wallpaper", pick(true, false, 12, KID + "wallpaper"));
        assertEquals(KID + "wallpaper_day", pick(false, true, 6, KID + "wallpaper_day", KID + "wallpaper_night"));
        assertEquals(KID + "wallpaper_night", pick(false, true, 18, KID + "wallpaper_day", KID + "wallpaper_night"));
        assertEquals(KID + "wallpaper_night", pick(false, true, 5, KID + "wallpaper_day", KID + "wallpaper_night"));
        // No night picture: the plain one
        assertEquals(KID + "wallpaper", pick(false, true, 22, KID + "wallpaper_day", KID + "wallpaper"));
        // Day/night off: their pictures don't count
        assertNull(pick(false, false, 12, KID + "wallpaper_day", "wallpaper_bing"));
    }

    @Test
    public void picturesAreTheProfilesOwn() {
        // Another profile's picture, or one from before pictures were per profile, isn't this profile's
        assertNull(pick(false, false, 12, "wallpapers/user_0/wallpaper", "wallpaper"));
        assertEquals("wallpapers/user_11", HearthWallpaper.profileFolder("user:11"));
        assertEquals("wallpapers/Alex_s_TV", HearthWallpaper.profileFolder("Alex's TV"));
    }

    @Test
    public void kinds() {
        assertEquals("gradient", HearthWallpaper.kindOf(null));
        assertEquals("bing", HearthWallpaper.kindOf("wallpaper_bing"));
        assertEquals("picture", HearthWallpaper.kindOf(KID + "wallpaper_night"));
    }

    @Test
    public void versionChangesWithWhatIsShown() {
        long picture = HearthWallpaper.version("picture", "wallpaper", 1000, 50, "a");
        assertTrue(picture > 0);
        assertEquals(picture, HearthWallpaper.version("picture", "wallpaper", 1000, 50, "a"));
        // A new pick into the same file
        assertNotEquals(picture, HearthWallpaper.version("picture", "wallpaper", 2000, 50, "a"));
        assertNotEquals(picture, HearthWallpaper.version("picture", "wallpaper", 1000, 51, "a"));
        // Day turning to night
        assertNotEquals(picture, HearthWallpaper.version("picture", "wallpaper_night", 1000, 50, "a"));
        // The gradient behind a picture doesn't change what's shown
        assertEquals(picture, HearthWallpaper.version("picture", "wallpaper", 1000, 50, "b"));
        // Another gradient does when it's what's shown
        assertNotEquals(HearthWallpaper.version("gradient", null, 0, 0, "a"),
                HearthWallpaper.version("gradient", null, 0, 0, "b"));
        assertNotEquals(HearthWallpaper.version("gradient", null, 0, 0, null),
                HearthWallpaper.version("gradient", null, 0, 0, "a"));
    }

    @Test
    public void brightnessOnlyForWhatFlutterMeasured() {
        assertEquals(0.7, HearthWallpaper.brightness("wallpaper_bing", "wallpaper_bing", 0.7, 0.1), 0);
        // Flutter hasn't measured the night picture yet
        assertNull(HearthWallpaper.brightness("wallpaper_night", "wallpaper_day", 0.7, 0.1));
        assertEquals(0.1, HearthWallpaper.brightness(null, "wallpaper", 0.7, 0.1), 0);
        assertNull(HearthWallpaper.brightness(null, null, null, null));
    }
}
