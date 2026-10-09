package com.leanbitlab.ltvL;

import android.app.Activity;
import android.content.Intent;
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
                    Intent intent = Intent.parseUri(pending, Intent.URI_INTENT_SCHEME)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    intent.setSelector(null);
                    startActivity(intent, MainActivity.shareIdentity());
                    ok = true;
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

    @Override
    protected void onDestroy() {
        mHandler.removeCallbacks(mCheck);
        super.onDestroy();
    }
}
