package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

/** Other computers' "Allow debugging?" is answered Cancel; Hearth's own, or one a parent allows, is left alone. */
public class AdbPromptGuardTest {
    private static final String OWN = "69:3E:9A:F8:4D:3D:FC:C7:1E:64:0E:00:5B:DC:5E:2E";
    private static final String OTHER = "01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF";
    private static final String SYSTEM_UI = "com.android.systemui";

    private static String prompt(String fingerprint) {
        return "Allow USB debugging?\nThe computer's RSA key fingerprint is:\n" + fingerprint
                + "\nAlways allow from this computer\nCancel\nAllow";
    }

    @Test
    public void readsAKeyAsAndroidShowsIt() {
        // MD5 of the decoded key: "AAAA" is three zero bytes
        assertEquals(OWN, AdbPromptGuard.fingerprintOf("AAAA hearth@tv\n"));
        assertNull(AdbPromptGuard.fingerprintOf("@@@@ user@host"));
        assertNull(AdbPromptGuard.fingerprintOf(null));
    }

    @Test
    public void anotherComputerIsAnsweredCancel() {
        assertEquals(AdbPromptGuard.Verdict.DISMISS, AdbPromptGuard.judge(SYSTEM_UI, prompt(OTHER), OWN, false, false));
        // Wireless debugging's prompt, with Hearth connecting at the same moment: the key still decides
        assertEquals(AdbPromptGuard.Verdict.DISMISS, AdbPromptGuard.judge(SYSTEM_UI,
                "Allow wireless debugging on this network?\n" + OTHER, OWN, true, false));
    }

    @Test
    public void hearthsOwnKeyOrAParentsWordIsLeftAlone() {
        assertEquals(AdbPromptGuard.Verdict.LEAVE, AdbPromptGuard.judge(SYSTEM_UI, prompt(OWN), OWN, false, false));
        assertEquals(AdbPromptGuard.Verdict.LEAVE, AdbPromptGuard.judge(SYSTEM_UI, prompt(OTHER), OWN, false, true));
        // No fingerprint on screen: Hearth's own while it connects, else Cancel
        assertEquals(AdbPromptGuard.Verdict.LEAVE,
                AdbPromptGuard.judge(SYSTEM_UI, "Allow USB debugging?", OWN, true, false));
        assertEquals(AdbPromptGuard.Verdict.DISMISS,
                AdbPromptGuard.judge(SYSTEM_UI, "Allow USB debugging?", null, false, false));
    }

    @Test
    public void otherWindowsAreNotThePrompt() {
        assertEquals(AdbPromptGuard.Verdict.NOT_A_PROMPT, AdbPromptGuard.judge(SYSTEM_UI, "Volume", OWN, false, false));
        // An app showing the same words is never answered
        assertEquals(AdbPromptGuard.Verdict.NOT_A_PROMPT,
                AdbPromptGuard.judge("com.example.tutorial", prompt(OTHER), OWN, false, false));
        // Settings' developer options name debugging but show no key
        assertEquals(AdbPromptGuard.Verdict.NOT_A_PROMPT,
                AdbPromptGuard.judge("com.android.tv.settings", "USB debugging\nOn", OWN, false, false));
    }
}
