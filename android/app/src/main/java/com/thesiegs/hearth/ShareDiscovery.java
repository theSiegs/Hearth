package com.thesiegs.hearth;

import android.content.Context;
import android.os.Build;
import android.provider.Settings;

/**
 * The TV's name as other TVs and Home Assistant see it: household sync announces it, joining shows it, and Home
 * Assistant names the TV by it. (The copy of profiles between TVs announced it too; household sync replaced that.)
 */
final class ShareDiscovery {
    private ShareDiscovery() {
    }

    /** What the TV is called to its owner (Settings > Device name), else its model. */
    static String deviceName(Context context) {
        String name = null;
        try {
            name = Settings.Global.getString(context.getContentResolver(), "device_name");
        } catch (RuntimeException ignored) {
        }
        return name == null || name.trim().isEmpty() ? Build.MODEL : name.trim();
    }
}
