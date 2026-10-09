package com.thesiegs.hearth;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Process;

/**
 * Restarts Hearth's main process (after asking for the old Hearth's data: the import runs at process start, before
 * anything has read a setting). Runs in a process of its own (":restart"): it ends the main one, opens Hearth again
 * and goes away.
 */
public class RestartActivity extends Activity {
    static final String PROCESS_SUFFIX = ":restart";
    private static final String EXTRA_PID = "pid";

    /** Ends this (main) process and starts Hearth again in a fresh one. */
    static void restart(Activity from) {
        from.startActivity(new Intent(from, RestartActivity.class)
                .putExtra(EXTRA_PID, Process.myPid())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        from.finishAffinity();
        Runtime.getRuntime().exit(0);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int pid = getIntent().getIntExtra(EXTRA_PID, -1);
        if (pid > 0 && pid != Process.myPid()) Process.killProcess(pid);
        startActivity(new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
        finish();
        Runtime.getRuntime().exit(0);
    }

    /** Whether this process is the restarter (nothing else should run there). */
    static boolean isRestartProcess(Context context) {
        String name = android.os.Build.VERSION.SDK_INT >= 28 ? android.app.Application.getProcessName() : null;
        return name != null && name.endsWith(PROCESS_SUFFIX);
    }
}
