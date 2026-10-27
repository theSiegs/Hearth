package com.thesiegs.hearth;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.ResolveInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * The agent's only screen, invisible: Hearth (in the owner's user) starts it in a profile's user to hand the agent
 * its key and, when asked, open something there; a visible window is what lets the agent start another app's
 * screen. Enabled only in profile users where Hearth acts as an agent (see AgentService.hideFromHome).
 */
public class AgentActivity extends Activity {
    private static final long WAIT_FOR_OPEN_MS = 1_500;
    private static final long POLL_MS = 100;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private long mStartedAt;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        AgentService.rememberKey(this, getIntent().getSourceBounds());
        AgentService.start(this);
        // Hearth asks to open something only over a connected agent: not connected, this start was only to get the
        // agent going, and the screen goes at once rather than sit over Hearth (taking the remote's first presses)
        if (!AgentService.isConnected() && !AgentService.hasPendingOpen()) {
            finish();
            return;
        }
        mStartedAt = System.currentTimeMillis();
        mHandler.post(mCheck);
    }

    /** Hearth sends what to open just before starting this screen; it may arrive a moment after. */
    private final Runnable mCheck = new Runnable() {
        @Override
        public void run() {
            String pending = AgentService.takePendingOpen();
            if (pending != null) {
                boolean ok;
                try {
                    Intent intent = checked(Intent.parseUri(pending, Intent.URI_INTENT_SCHEME));
                    if (intent != null) {
                        startActivity(intent, MainActivity.shareIdentity());
                        ok = true;
                    } else {
                        Log.i("HearthAgent", "Won't open " + pending);
                        ok = false;
                    }
                } catch (Exception e) {
                    Log.i("HearthAgent", "Couldn't open " + pending + ": " + e);
                    ok = false;
                }
                AgentService.reportOpened(ok);
                finish();
            } else if (System.currentTimeMillis() - mStartedAt < WAIT_FOR_OPEN_MS) {
                mHandler.postDelayed(this, POLL_MS);
            } else {
                finish();
            }
        }
    };

    /**
     * The intent to start, aimed at the one exported screen of another app it resolves to, without the flags that
     * would hand out access to Hearth's own files; null when it isn't another app's (Hearth only ever opens other
     * apps here, and what comes over the agent's socket must not reach Hearth's private screens).
     */
    private Intent checked(Intent intent) {
        intent.setSelector(null);
        intent.setFlags(withoutGrants(intent.getFlags()) | Intent.FLAG_ACTIVITY_NEW_TASK);
        String target = intent.getComponent() != null ? intent.getComponent().getPackageName() : intent.getPackage();
        if (!isOtherApp(getPackageName(), target)) return null;
        ResolveInfo resolved = getPackageManager().resolveActivity(intent, 0);
        ActivityInfo activity = resolved != null ? resolved.activityInfo : null;
        if (activity == null || !activity.exported || !target.equals(activity.packageName)) return null;
        intent.setComponent(new ComponentName(activity.packageName, activity.name));
        return intent;
    }

    /** Whether a target package names an app other than Hearth. */
    static boolean isOtherApp(String own, String target) {
        return target != null && !target.isEmpty() && !target.equals(own);
    }

    /**
     * Whether a Continue Watching card's deep link may open the screen it resolved to ({@code resolved}, its package;
     * {@code exported}): another app's, exported, and for a card from the household's other TVs
     * ({@code household}: the apps of its cards with that link; empty: not one) in that card's own app.
     */
    static boolean mayOpenProgram(String own, String resolved, boolean exported, java.util.Set<String> household) {
        if (!isOtherApp(own, resolved) || !exported) return false;
        return household.isEmpty() || household.contains(resolved);
    }

    /** Flags without the ones that grant access to content URIs. */
    static int withoutGrants(int flags) {
        return flags & ~(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
    }

    @Override
    protected void onDestroy() {
        mHandler.removeCallbacks(mCheck);
        super.onDestroy();
    }
}
