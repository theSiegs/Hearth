package com.leanbitlab.ltvL;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Starts the launcher after boot when the "Start on boot" setting is on. Meant for devices whose
 * stock launcher always wins HOME resolution (Google TV, Fire TV). Android 10+ only allows this
 * background activity start while the app holds an exemption, e.g. the Home Button Fix
 * accessibility service is enabled or the overlay permission is granted; otherwise it is dropped.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        // In another Google TV profile's user, this is that profile starting: its agent goes with it
        if (AgentService.isAgent(context)) {
            AgentService.start(context);
            return;
        }
        if (!FlutterPrefs.getBoolean(context, "start_on_boot", false)) return;
        context.startActivity(new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
}
