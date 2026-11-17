package com.thesiegs.hearth;

import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;

/**
 * The time a kid's day, minutes, locks and PIN waits are judged by: the TV's clock, less whatever it was moved by hand.
 * Turning "Automatic date &amp; time" off and setting the date forward would otherwise start a new day (yesterday's
 * minutes forgotten, the count back at zero) or end a bedtime or a PIN wait early; set back, it would put bedtime off.
 *
 * Each reading is compared with the last: how far the clock moved against how long the TV really ran
 * (elapsedRealtime, which counts sleep and no one can set). A difference of more than {@link #TOLERANCE_MS} while
 * automatic time is off is a change by hand: it's kept as the skew and taken off every reading, so Hearth's time runs
 * on as if nobody touched the clock. With automatic time on the network set the clock (a stick that woke with a stale
 * clock and then got the time): that is believed, and ends any skew. Midnight comes as ever. Across a restart nothing
 * can be measured (elapsedRealtime starts again): a skew is kept while automatic time is still off, and dropped once
 * it's on.
 */
final class TvClock {
    private static final String TAG = "HearthClock";
    private static final String PREFS = "ltv_clock";
    /** The clock may differ this much from the time the TV ran: drift, and the network's small corrections. */
    static final long TOLERANCE_MS = 2 * 60_000L;
    /** How often a clock that's the network's is taken as the new point to measure from. */
    static final long FOLLOW_EVERY_MS = 60_000L;

    private static State sState;

    private TvClock() {
    }

    /** A reading to measure the next from: the clock, the time since boot, which boot, and the skew found so far. */
    static final class State {
        final long wall;
        final long elapsed;
        final int boot;
        /** How far the clock was moved by hand (ms; forward is positive); Hearth's time is the clock less this. */
        final long skew;

        State(long wall, long elapsed, int boot, long skew) {
            this.wall = wall;
            this.elapsed = elapsed;
            this.boot = boot;
            this.skew = skew;
        }
    }

    /**
     * The state after a reading ([last] itself when nothing changed): see the class comment. [autoTime]: whether
     * automatic date and time is on at this reading.
     */
    static State step(State last, long wall, long elapsed, int boot, boolean autoTime) {
        if (last == null) return new State(wall, elapsed, boot, 0);
        if (last.boot != boot || elapsed < last.elapsed) {
            // Restarted: how far the clock moved meanwhile can't be measured
            return new State(wall, elapsed, boot, autoTime ? 0 : last.skew);
        }
        long jump = (wall - last.wall) - (elapsed - last.elapsed);
        if (Math.abs(jump) <= TOLERANCE_MS) {
            // The network's clock is followed as it's corrected; a clock set by hand is measured from where it was,
            // so small steps add up to a jump
            boolean follow = autoTime && elapsed - last.elapsed >= FOLLOW_EVERY_MS;
            return follow ? new State(wall, elapsed, boot, last.skew) : last;
        }
        if (autoTime) return new State(wall, elapsed, boot, 0);
        long skew = last.skew + jump;
        // Set back to where it was: nothing to take off any more
        return new State(wall, elapsed, boot, Math.abs(skew) <= TOLERANCE_MS ? 0 : skew);
    }

    /** Hearth's time now (epoch ms): the TV's clock less what it was moved by hand. */
    static synchronized long now(Context context) {
        long wall = System.currentTimeMillis();
        int boot;
        boolean autoTime;
        try {
            ContentResolver resolver = context.getContentResolver();
            boot = Settings.Global.getInt(resolver, Settings.Global.BOOT_COUNT, 0);
            autoTime = Settings.Global.getInt(resolver, Settings.Global.AUTO_TIME, 1) != 0;
        } catch (RuntimeException e) {
            return wall;
        }
        // Without a boot count a restart can't be told from a jump: the clock as it is
        if (boot <= 0) return wall;
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        State last = sState != null ? sState : load(prefs);
        State next = step(last, wall, SystemClock.elapsedRealtime(), boot, autoTime);
        if (next != last) {
            if (last != null && next.skew != last.skew) {
                Log.w(TAG, next.skew == 0 ? "The TV's clock is believed again"
                        : "The TV's clock was set by hand: " + next.skew / 60_000 + " min taken off for Hearth's time");
            }
            prefs.edit().putLong("wall", next.wall).putLong("elapsed", next.elapsed).putInt("boot", next.boot)
                    .putLong("skew", next.skew).apply();
        }
        sState = next;
        return wall - next.skew;
    }

    /** A time of Hearth's ({@link #now}) as the TV's clock shows it, for what compares it with that clock (Flutter). */
    static long toWall(Context context, long time) {
        long wall = System.currentTimeMillis();
        return time + (wall - now(context));
    }

    private static State load(SharedPreferences prefs) {
        if (!prefs.contains("boot")) return null;
        return new State(prefs.getLong("wall", 0), prefs.getLong("elapsed", 0), prefs.getInt("boot", 0),
                prefs.getLong("skew", 0));
    }
}
