package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** The fixed shell commands the setup flow shows the parent before Hearth runs them over its own adb. */
public class SetupFixesTest {
    private static final String PKG = "com.thesiegs.hearth";
    private static final String SERVICE = PKG + "/" + PKG + ".LauncherAccessibilityService";
    private static final String SHORT = PKG + "/.LauncherAccessibilityService";
    private final FakeContext context = new FakeContext(PKG);

    @Test
    public void liftingTheRestrictedBlockIsOneAppOpsCommandForHearthItself() {
        assertEquals(Collections.singletonList("appops set " + PKG + " ACCESS_RESTRICTED_SETTINGS allow"),
                SetupFixes.commands(context, SetupFixes.RESTRICTED_SETTINGS));
    }

    @Test
    public void watchNextGrantsTheListingsPermissionToHearth() {
        assertEquals(Collections.singletonList("pm grant " + PKG + " android.permission.READ_TV_LISTINGS"),
                SetupFixes.commands(context, SetupFixes.WATCH_NEXT));
    }

    @Test
    public void anUnknownFixHasNoCommands() {
        assertNull(SetupFixes.commands(context, null));
        assertNull(SetupFixes.commands(context, "rm -rf /"));
        assertNull(SetupFixes.commands(context, "RESTRICTED_SETTINGS"));
    }

    @Test
    public void runRefusesAnUnknownFixBeforeItRunsAnything() {
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class, () -> SetupFixes.run(context,
                Arrays.asList(SetupFixes.RESTRICTED_SETTINGS, "reboot")));
        assertEquals("Not a setup fix: reboot", e.getMessage());
    }

    @Test
    public void theServiceIsTurnedOnNextToTheOnesAlreadyOn() {
        assertEquals(Arrays.asList(
                        "settings put secure enabled_accessibility_services 'com.other/.Reader:" + SERVICE + "'",
                        "settings put secure accessibility_enabled 1"),
                SetupFixes.accessibilityCommands("com.other/.Reader", SERVICE, SHORT));
    }

    @Test
    public void anEmptyListGetsJustTheService() {
        List<String> expected = Arrays.asList("settings put secure enabled_accessibility_services '" + SERVICE + "'",
                "settings put secure accessibility_enabled 1");
        assertEquals(expected, SetupFixes.accessibilityCommands(null, SERVICE, SHORT));
        assertEquals(expected, SetupFixes.accessibilityCommands("", SERVICE, SHORT));
    }

    @Test
    public void aServiceAlreadyOnByEitherNameIsntAddedTwice() {
        assertEquals("settings put secure enabled_accessibility_services '" + SERVICE + ":com.other/.Reader'",
                SetupFixes.accessibilityCommands(SERVICE + ":com.other/.Reader", SERVICE, SHORT).get(0));
        assertEquals("settings put secure enabled_accessibility_services '" + SHORT + "'",
                SetupFixes.accessibilityCommands(SHORT, SERVICE, SHORT).get(0));
    }

    @Test
    public void aListWithAnythingButComponentNamesIsntPutInACommand() {
        assertNull(SetupFixes.accessibilityCommands("com.other/.Reader'; reboot; '", SERVICE, SHORT));
        assertNull(SetupFixes.accessibilityCommands("com.other/.Reader $(id)", SERVICE, SHORT));
        assertNull(SetupFixes.accessibilityCommands("a/b\nreboot", SERVICE, SHORT));
    }

    @Test
    public void innerClassComponentNamesAreAllowed() {
        String inner = "com.other/com.other.Outer$Service";
        assertEquals("settings put secure enabled_accessibility_services '" + inner + ":" + SERVICE + "'",
                SetupFixes.accessibilityCommands(inner, SERVICE, SHORT).get(0));
    }
}
