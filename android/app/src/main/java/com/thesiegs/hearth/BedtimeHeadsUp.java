package com.thesiegs.hearth;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.HashSet;
import java.util.Set;

/**
 * A quiet heads-up before a kid's bedtime or school time (the Hearth integration's "next_lock"): "Bedtime in 15 min",
 * then "in 5 min", over whatever is on, with no sound. Paired TVs only, kids profiles only, and only while the screen
 * is on. It's worked out again with each state document, profile change and screen on, and waits for the next mark
 * on the main thread. Each mark shows once for a profile and lock time.
 */
final class BedtimeHeadsUp {
    private static final String TAG = "HearthHeadsUp";
    private static final Handler sHandler = new Handler(Looper.getMainLooper());
    /** The next check, waiting on sHandler (main thread only). */
    private static Runnable sPending;
    /** "profile|at|mark" of the heads-ups shown (main thread only). */
    private static final Set<String> sTold = new HashSet<>();

    private BedtimeHeadsUp() {
    }

    /** Shows the heads-up that's due now, if any, and waits for the next one (main thread). */
    static void schedule(Context context) {
        Context app = context.getApplicationContext() != null ? context.getApplicationContext() : context;
        if (sPending != null) sHandler.removeCallbacks(sPending);
        sPending = null;
        if (!HaIntegration.isPaired(app)) return;
        String profile = LauncherAccessibilityService.getActiveProfileKey(app);
        if (profile == null || !ProfileUsers.isKids(app)) return;
        long now = System.currentTimeMillis();
        JSONObject entry = HaAllowance.entryFor(app, profile, now);
        Long at = HaLocks.nextLockAt(entry, now);
        if (at == null) return;
        int mark = HaLocks.headsUpMark(at, now);
        if (mark > 0 && isInteractive(app) && sTold.add(profile + "|" + at + "|" + mark)) {
            int minutes = HaLocks.minutesUntil(at, now);
            boolean school = "school_time".equals(HaLocks.nextLockKind(entry));
            String text = app.getString(school ? R.string.heads_up_school_time : R.string.heads_up_bedtime, minutes);
            Log.i(TAG, (school ? "School time" : "Bedtime") + " in " + minutes + " min");
            Toast.makeText(app, text, Toast.LENGTH_LONG).show();
        }
        long next = HaLocks.nextHeadsUpAt(at, now);
        if (next > 0) {
            sPending = () -> schedule(app);
            // A moment past the mark, so it's inside its stretch
            sHandler.postDelayed(sPending, next - now + 1_000);
        }
    }

    private static boolean isInteractive(Context context) {
        PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        return power == null || power.isInteractive();
    }
}
