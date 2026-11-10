package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;

/**
 * The one count of wrong Parent PINs on this TV, for every way a PIN is entered: Hearth's own PIN pad, HearthTube
 * here, and a kid's HearthTube through that profile's agent. After {@link #FREE_TRIES} wrong in a row each further
 * one waits, 30 seconds and doubling up to an hour; a right PIN clears it. Kept in the device prefs on wall-clock time,
 * so restarting Hearth, or the TV, gives no fresh tries; a clock set back never stretches a wait past an hour.
 */
final class ParentPinPolicy {
    static final int FREE_TRIES = 5;
    static final long BASE_MS = 30_000;
    static final long MAX_MS = 60 * 60_000;
    private static final String PREF_WRONG = "parent_pin_wrong_tries";
    private static final String PREF_LOCKED_UNTIL = "parent_pin_locked_until";

    private ParentPinPolicy() {
    }

    /** How long the [misses]-th wrong PIN in a row locks the pad (0: not yet). */
    static long waitFor(int misses) {
        if (misses < FREE_TRIES) return 0;
        int doublings = Math.min(misses - FREE_TRIES, 20);
        return Math.min(MAX_MS, BASE_MS << doublings);
    }

    /** When the pad opens again (0 or past: open now); never more than {@link #MAX_MS} from {@code now}. */
    static synchronized long lockedUntil(Context context, long now) {
        return Math.min(prefs(context).getLong(PREF_LOCKED_UNTIL, 0), now + MAX_MS);
    }

    /** A wrong PIN: counts it; returns when the pad opens again (0: it doesn't wait). A new wait is told to HA. */
    static synchronized long miss(Context context, long now) {
        SharedPreferences prefs = prefs(context);
        int misses = prefs.getInt(PREF_WRONG, 0) + 1;
        long wait = waitFor(misses);
        long until = wait > 0 ? now + wait : 0;
        prefs.edit().putInt(PREF_WRONG, misses).putLong(PREF_LOCKED_UNTIL, until).commit();
        if (wait > 0) HaParentPins.noteLockout(context);
        return until;
    }

    /** A right PIN: the count starts over. */
    static synchronized void clear(Context context) {
        prefs(context).edit().remove(PREF_WRONG).remove(PREF_LOCKED_UNTIL).commit();
    }

    /**
     * Checks a PIN (blocking: Home Assistant's are asked there) unless the pad waits: {"ok": bool} and, while it
     * waits, "wait_seconds".
     */
    static Bundle verify(Context context, String pin) {
        Bundle result = new Bundle();
        long now = System.currentTimeMillis();
        long until = lockedUntil(context, now);
        if (now < until) {
            result.putBoolean("ok", false);
            result.putInt("wait_seconds", (int) ((until - now + 999) / 1000));
            return result;
        }
        // The adults' from Home Assistant while there are any, else the TV's own (either form ParentPinHash keeps)
        boolean ok = HaParentPins.verify(context, pin);
        if (ok) {
            clear(context);
        } else {
            long next = miss(context, System.currentTimeMillis());
            if (next > 0) result.putInt("wait_seconds", (int) ((next - System.currentTimeMillis() + 999) / 1000));
        }
        result.putBoolean("ok", ok);
        return result;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }
}
