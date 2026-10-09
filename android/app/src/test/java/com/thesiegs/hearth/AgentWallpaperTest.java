package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** How a profile's wallpaper is sized for its agent, and what the agent shows of it. */
public class AgentWallpaperTest {

    @Test
    public void coversTheScreenWithoutEnlarging() {
        // A 4K photo: halved, nothing cut
        assertArrayEquals(new int[]{1920, 1080, 0, 0, 1920, 1080}, AgentWallpaper.cover(3840, 2160, 1920, 1080));
        // A wide panorama: as tall as the screen, its middle kept
        assertArrayEquals(new int[]{4320, 1080, 1200, 0, 1920, 1080}, AgentWallpaper.cover(8000, 2000, 1920, 1080));
        // A portrait photo: as wide as the screen, its middle kept
        assertArrayEquals(new int[]{1920, 2560, 0, 740, 1920, 1080}, AgentWallpaper.cover(3000, 4000, 1920, 1080));
        // Smaller than the screen: left as it is (HearthTube scales it up)
        assertArrayEquals(new int[]{1280, 720, 0, 0, 1280, 720}, AgentWallpaper.cover(1280, 720, 1920, 1080));
        // Already the screen's size (Bing's photo)
        assertArrayEquals(new int[]{1920, 1080, 0, 0, 1920, 1080}, AgentWallpaper.cover(1920, 1080, 1920, 1080));
    }

    @Test
    public void decodesNoMoreThanNeeded() {
        assertEquals(2, AgentWallpaper.sampleSize(3840, 2160, 1920, 1080));
        assertEquals(4, AgentWallpaper.sampleSize(8000, 4500, 1920, 1080));
        assertEquals(1, AgentWallpaper.sampleSize(3000, 2000, 1920, 1080));
        assertEquals(1, AgentWallpaper.sampleSize(1280, 720, 1280, 720));
    }

    @Test
    public void showsOnlyAPictureItHas() {
        assertEquals("picture", AgentWallpaper.shownKind("picture", 7, 7, true));
        assertEquals("bing", AgentWallpaper.shownKind("bing", 7, 7, true));
        // An older picture, or none (too big to send): the gradient
        assertEquals("gradient", AgentWallpaper.shownKind("picture", 8, 7, true));
        assertEquals("gradient", AgentWallpaper.shownKind("bing", 7, 7, false));
        assertEquals("gradient", AgentWallpaper.shownKind("gradient", 7, 0, false));
    }

    @Test
    public void takesOnlyJpegs() {
        assertTrue(AgentWallpaper.isJpeg(new byte[]{(byte) 0xff, (byte) 0xd8, (byte) 0xff, (byte) 0xe0}));
        assertFalse(AgentWallpaper.isJpeg(new byte[]{(byte) 0x89, 'P', 'N', 'G'}));
        assertFalse(AgentWallpaper.isJpeg(new byte[0]));
        assertFalse(AgentWallpaper.isJpeg(null));
    }
}
