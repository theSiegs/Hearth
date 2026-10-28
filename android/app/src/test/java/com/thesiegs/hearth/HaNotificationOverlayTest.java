package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import android.view.Gravity;

import org.junit.Test;

/** Where a Home Assistant notification card sits, from the position number Home Assistant sends. */
public class HaNotificationOverlayTest {
    @Test
    public void positionsMapToCornersAndCenter() {
        assertEquals(Gravity.BOTTOM | Gravity.END, HaNotificationOverlay.gravity(0));
        assertEquals(Gravity.BOTTOM | Gravity.START, HaNotificationOverlay.gravity(1));
        assertEquals(Gravity.TOP | Gravity.END, HaNotificationOverlay.gravity(2));
        assertEquals(Gravity.TOP | Gravity.START, HaNotificationOverlay.gravity(3));
        assertEquals(Gravity.CENTER, HaNotificationOverlay.gravity(4));
    }

    @Test
    public void anUnknownPositionIsTopRight() {
        assertEquals(Gravity.TOP | Gravity.END, HaNotificationOverlay.gravity(-1));
        assertEquals(Gravity.TOP | Gravity.END, HaNotificationOverlay.gravity(5));
    }
}
