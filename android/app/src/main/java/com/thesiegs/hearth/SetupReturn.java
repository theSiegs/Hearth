package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

/**
 * Brings Hearth back after its setup flow sent the owner to Android's settings for one of its switches. The flow
 * says what it's waiting for before it opens the screen; when that switch's service connects (the owner turned it
 * on), the service starts Hearth again, so the owner lands on the flow's next step instead of pressing Back through
 * Android's screens. A wait older than {@link #FRESH_MS} is ignored: the owner went elsewhere.
 */
final class SetupReturn {
    private static final String TAG = "HearthSetup";

    /** MainActivity's extra when a service brought Hearth back for the setup flow: which switch came on. */
    static final String EXTRA_RESUME_SETUP = "hearth_resume_setup";

    static final String HOME_BUTTON_FIX = "home_button_fix";
    static final String PROFILE_PAIRING = "profile_pairing";
    static final String NOTIFICATION_ACCESS = "notification_access";

    private static final String PREFS = "hearth_setup";
    private static final String WAITING_FOR = "waiting_for";
    private static final String WAITING_SINCE = "waiting_since";
    static final long FRESH_MS = 15 * 60_000L;

    private SetupReturn() {
    }

    /** The flow is about to open Android's screen for [what]; null when it no longer waits. */
    static void setWaitingFor(Context context, String what) {
        SharedPreferences.Editor editor = prefs(context).edit();
        if (what == null) {
            editor.remove(WAITING_FOR).remove(WAITING_SINCE);
        } else {
            editor.putString(WAITING_FOR, what).putLong(WAITING_SINCE, System.currentTimeMillis());
        }
        editor.apply();
    }

    /** A service's switch is on: if the setup flow was waiting for it, Hearth comes back to the front. */
    static void onConnected(Context context, String what) {
        SharedPreferences prefs = prefs(context);
        if (!what.equals(prefs.getString(WAITING_FOR, null))) return;
        long since = prefs.getLong(WAITING_SINCE, 0);
        setWaitingFor(context, null);
        if (System.currentTimeMillis() - since > FRESH_MS) return;
        Log.i(TAG, what + " came on: back to the setup flow");
        Intent intent = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_RESUME_SETUP, what);
        try {
            context.startActivity(intent);
        } catch (Exception e) {
            // Android didn't let the service start it: the owner comes back with Back, and the flow checks then
            Log.w(TAG, "Couldn't bring Hearth back", e);
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
