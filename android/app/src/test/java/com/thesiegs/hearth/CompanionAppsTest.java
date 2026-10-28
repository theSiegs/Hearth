package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Reading the Dart side's settings, and the companion auto-update switch kept there. */
public class CompanionAppsTest {
    private final FakeContext context = new FakeContext("com.thesiegs.hearth");

    private FakeContext.Prefs flutterPrefs() {
        return context.getSharedPreferences("FlutterSharedPreferences", 0);
    }

    @Test
    public void dartKeysAreReadWithFlutterPrefix() {
        assertEquals("flutter.accent_color", FlutterPrefs.key("accent_color"));
        flutterPrefs().edit().putString("flutter.ha_panel_profile_dashboard", "lovelace/kids")
                .putBoolean("flutter.ha_panel_enabled", true)
                // Not a Dart key: shared_preferences only reads prefixed ones
                .putString("ha_panel_profile_dashboard", "wrong").apply();

        assertEquals("lovelace/kids", FlutterPrefs.getString(context, "ha_panel_profile_dashboard", ""));
        assertTrue(FlutterPrefs.getBoolean(context, "ha_panel_enabled", false));
        assertEquals("fallback", FlutterPrefs.getString(context, "missing", "fallback"));
        assertFalse(FlutterPrefs.getBoolean(context, "missing", false));
    }

    @Test
    public void theStoredSwitchDecidesAutoUpdate() {
        flutterPrefs().edit().putBoolean("flutter.companion_auto_update", true).apply();
        assertTrue(CompanionApps.autoUpdate(context));
        flutterPrefs().edit().putBoolean("flutter.companion_auto_update", false).apply();
        assertFalse(CompanionApps.autoUpdate(context));
    }

    @Test
    public void withoutASwitchAutoUpdateFollowsWhoInstalledHearthTube() {
        // No package manager to say Hearth installed it: off, and so Hearth doesn't take over its updates
        assertFalse(CompanionApps.autoUpdate(context));
        assertFalse(CompanionApps.updatesHearthTube(context));
        assertFalse(CompanionApps.installedByHearth(context, null));
    }

    @Test
    public void hearthTubeIsNotUpdatedByHearthWhenItCantUpdateWithoutAPrompt() {
        // The switch is on, but Hearth isn't HearthTube's installer of record here
        flutterPrefs().edit().putBoolean("flutter.companion_auto_update", true).apply();
        assertFalse(CompanionApps.updatesHearthTube(context));
    }
}
