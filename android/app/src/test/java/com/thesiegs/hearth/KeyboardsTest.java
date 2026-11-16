package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

/** Which keyboard the TV types with, and when Hearth puts the on-screen one back. */
public class KeyboardsTest {
    private static final String BRIDGE = "com.google.android.tv.remote.service/.ImeBridgeService";
    private static final String GBOARD = "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME";
    private static final String VOICE = "com.google.android.tts/"
            + "com.google.android.apps.speech.tts.googletts.settings.asr.voiceime.VoiceInputMethodService";
    private static final String LEANBACK = "com.google.android.leanback.ime/.LeanbackImeService";
    private static final String OTHER = "com.example.keys/.KeysIme";

    @Test
    public void googleTvsRemoteBridgeIsAPhoneKeyboard() {
        assertEquals(Keyboards.KIND_PHONE, Keyboards.kind(BRIDGE));
        assertEquals(Keyboards.KIND_PHONE, Keyboards.kind(
                "com.google.android.tv.remote.service/com.google.android.tv.remote.service.ImeBridgeService"));
    }

    @Test
    public void gboardAndUnknownKeyboardsAreOnScreen() {
        assertEquals(Keyboards.KIND_ON_SCREEN, Keyboards.kind(GBOARD));
        assertEquals(Keyboards.KIND_ON_SCREEN, Keyboards.kind(LEANBACK));
        assertEquals(Keyboards.KIND_ON_SCREEN, Keyboards.kind(OTHER));
    }

    @Test
    public void googlesVoiceInputIsVoiceOnly() {
        assertEquals(Keyboards.KIND_VOICE, Keyboards.kind(VOICE));
    }

    @Test
    public void noKeyboardSetIsNone() {
        assertEquals(Keyboards.KIND_NONE, Keyboards.kind(null));
        assertEquals(Keyboards.KIND_NONE, Keyboards.kind(""));
    }

    @Test
    public void gboardIsPutBackFirstThenAndroidTvsOwnThenAnyOnScreenOne() {
        assertEquals(GBOARD, Keyboards.pickOnScreen(Arrays.asList(BRIDGE, LEANBACK, GBOARD)));
        assertEquals(LEANBACK, Keyboards.pickOnScreen(Arrays.asList(BRIDGE, OTHER, LEANBACK)));
        assertEquals(OTHER, Keyboards.pickOnScreen(Arrays.asList(BRIDGE, VOICE, OTHER)));
    }

    @Test
    public void noOnScreenKeyboardToPutBack() {
        assertNull(Keyboards.pickOnScreen(Arrays.asList(BRIDGE, VOICE)));
        assertNull(Keyboards.pickOnScreen(Collections.emptyList()));
        assertNull(Keyboards.pickOnScreen(null));
    }

    @Test
    public void aStuckPhoneKeyboardIsSwitchedOnlyWithNoPhoneThereAndThePermission() {
        assertTrue(Keyboards.shouldSwitch(Keyboards.KIND_PHONE, false, true, GBOARD));
        assertTrue(Keyboards.shouldSwitch(Keyboards.KIND_NONE, false, true, GBOARD));
        assertTrue(Keyboards.shouldSwitch(Keyboards.KIND_VOICE, false, true, GBOARD));
        // A phone remote is there: its keyboard stays (Hearth still shows its own on screen)
        assertFalse(Keyboards.shouldSwitch(Keyboards.KIND_PHONE, true, true, GBOARD));
        // Not allowed, nothing to switch to, or already on screen
        assertFalse(Keyboards.shouldSwitch(Keyboards.KIND_PHONE, false, false, GBOARD));
        assertFalse(Keyboards.shouldSwitch(Keyboards.KIND_PHONE, false, true, null));
        assertFalse(Keyboards.shouldSwitch(Keyboards.KIND_ON_SCREEN, false, true, GBOARD));
    }

    @Test
    public void noPhoneRemoteWhileTheRemoteApiIsntRunning() {
        assertFalse(RemoteApiService.phoneRemoteOpen(Keyboards.PHONE_SESSION_MIN_MS));
    }
}
