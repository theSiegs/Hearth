package com.example.hearthtest.supervisor;

import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.util.Arrays;

/**
 * am broadcast --user N -n com.example.hearthtest.supervisor/.Cmd -a com.example.hearthtest.SUPERVISE
 *   --ez supervised true|false        add/clear Family Link's supervision restrictions on this user
 *   --es suspend pkg1,pkg2            suspend these packages in this user (Google TV's unapproved / bedtime)
 *   --es unsuspend pkg1,pkg2          lift that
 */
public class Cmd extends BroadcastReceiver {
    private static final String TAG = "HearthTestSupervisor";
    private static final String[] RESTRICTIONS = {"no_config_credentials", "no_grant_admin", "no_add_managed_profile"};

    @Override
    public void onReceive(Context context, Intent intent) {
        DevicePolicyManager dpm = context.getSystemService(DevicePolicyManager.class);
        ComponentName admin = new ComponentName(context, Admin.class);
        try {
            if (intent.hasExtra("supervised")) {
                boolean on = intent.getBooleanExtra("supervised", false);
                for (String r : RESTRICTIONS) {
                    if (on) dpm.addUserRestriction(admin, r); else dpm.clearUserRestriction(admin, r);
                }
                Log.i(TAG, "supervised=" + on);
            }
            String suspend = intent.getStringExtra("suspend");
            if (suspend != null) {
                String[] failed = dpm.setPackagesSuspended(admin, suspend.split(","), true);
                Log.i(TAG, "suspended " + suspend + " failed=" + Arrays.toString(failed));
            }
            String unsuspend = intent.getStringExtra("unsuspend");
            if (unsuspend != null) {
                String[] failed = dpm.setPackagesSuspended(admin, unsuspend.split(","), false);
                Log.i(TAG, "unsuspended " + unsuspend + " failed=" + Arrays.toString(failed));
            }
            setResultCode(1);
        } catch (RuntimeException e) {
            Log.e(TAG, "failed", e);
            setResultCode(-1);
            setResultData(e.toString());
        }
    }
}
