package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * The setup flow's wait for a switch in Android's settings. (Bringing Hearth back builds an Intent, which plain
 * JUnit's android.jar can't; the paths here are the ones that decide not to.)
 */
public class SetupReturnTest {
    private final FakeContext context = new FakeContext("com.thesiegs.hearth");

    private FakeContext.Prefs prefs() {
        return context.getSharedPreferences("hearth_setup", 0);
    }

    @Test
    public void waitingIsRememberedWithItsTimeAndForgottenWithNull() {
        long before = System.currentTimeMillis();
        SetupReturn.setWaitingFor(context, SetupReturn.PROFILE_PAIRING);
        assertEquals(SetupReturn.PROFILE_PAIRING, prefs().getString("waiting_for", null));
        long since = prefs().getLong("waiting_since", 0);
        assertTrue(since >= before && since <= System.currentTimeMillis());

        SetupReturn.setWaitingFor(context, null);
        assertFalse(prefs().contains("waiting_for"));
        assertFalse(prefs().contains("waiting_since"));
    }

    @Test
    public void anotherSwitchComingOnLeavesTheWaitAlone() {
        SetupReturn.setWaitingFor(context, SetupReturn.HOME_BUTTON_FIX);
        SetupReturn.onConnected(context, SetupReturn.NOTIFICATION_ACCESS);
        assertEquals(SetupReturn.HOME_BUTTON_FIX, prefs().getString("waiting_for", null));
        assertTrue(context.started.isEmpty());
    }

    @Test
    public void nothingHappensWhenTheFlowIsntWaiting() {
        SetupReturn.onConnected(context, SetupReturn.HOME_BUTTON_FIX);
        assertTrue(context.started.isEmpty());
        assertFalse(prefs().contains("waiting_for"));
    }

    @Test
    public void aStaleWaitIsDroppedWithoutBringingHearthBack() {
        SetupReturn.setWaitingFor(context, SetupReturn.HOME_BUTTON_FIX);
        prefs().edit().putLong("waiting_since",
                System.currentTimeMillis() - SetupReturn.FRESH_MS - 1_000).apply();

        SetupReturn.onConnected(context, SetupReturn.HOME_BUTTON_FIX);

        assertTrue(context.started.isEmpty());
        assertFalse(prefs().contains("waiting_for"));
    }
}
