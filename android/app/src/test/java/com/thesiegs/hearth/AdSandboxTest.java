package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;

import org.junit.Test;

/** "Keep Google's ad sandbox off": the fixed list, and the commands Hearth's adb runs for it. */
public class AdSandboxTest {
    @Test
    public void theListIsOnlyPackageNames() {
        // These go into shell commands: nothing but a package name may be in one
        for (String pkg : AdSandbox.PACKAGES) {
            assertTrue(pkg, pkg.matches("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+"));
        }
    }

    @Test
    public void theListIsTheSandboxModulesOnly() {
        for (String pkg : AdSandbox.PACKAGES) {
            assertTrue(pkg, pkg.contains("adservices") || pkg.contains("ondevicepersonalization")
                    || pkg.contains("federatedcompute"));
        }
    }

    @Test
    public void offDisablesForThisUserOnly() {
        assertEquals(Arrays.asList("pm disable-user --user 0 com.android.adservices.api"),
                AdSandbox.offCommands(Arrays.asList("com.android.adservices.api"), 0));
    }

    @Test
    public void readsWhichOfTheListAreOn() {
        assertEquals(Arrays.asList("com.android.adservices.api", "com.android.federatedcompute.services"),
                AdSandbox.enabledIn("package:com.android.adservices.api\r\npackage:com.netflix.ninja\n"
                        + "package:com.android.federatedcompute.services\n"));
        assertTrue(AdSandbox.enabledIn("").isEmpty());
    }

    @Test
    public void backOnEnablesWhatWasTurnedOff() {
        assertEquals(Arrays.asList("pm enable --user 0 com.android.federatedcompute.services"),
                AdSandbox.onCommands(Arrays.asList("com.android.federatedcompute.services"), 0));
    }
}
