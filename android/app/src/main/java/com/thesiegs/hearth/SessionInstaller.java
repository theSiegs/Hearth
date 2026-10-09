package com.thesiegs.hearth;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Installs an APK through a PackageInstaller session marked store-sourced, so Android 13+ doesn't mark it
 * "restricted" (which blocks Hearth's accessibility services). First installs still ask; updates to apps Hearth
 * installed don't, where allowed.
 */
final class SessionInstaller {
    private static final String TAG = "HearthInstaller";

    private SessionInstaller() {}

    static boolean install(Context context, File apk) {
        PackageInstaller installer = context.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            params.setPackageSource(PackageInstaller.PACKAGE_SOURCE_STORE);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
        }
        params.setSize(apk.length());
        int sessionId = -1;
        boolean committed = false;
        try {
            sessionId = installer.createSession(params);
            try (PackageInstaller.Session session = installer.openSession(sessionId)) {
                try (InputStream in = new FileInputStream(apk);
                     OutputStream out = session.openWrite("base.apk", 0, apk.length())) {
                    byte[] buffer = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
                    session.fsync(out);
                }
                int flags = PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0);
                PendingIntent result = PendingIntent.getBroadcast(context, sessionId,
                        new Intent(context, ResultReceiver.class), flags);
                session.commit(result.getIntentSender());
                committed = true;
            }
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Session install failed", e);
            // A session left open keeps its partly written APK until Android cleans up days later
            if (sessionId != -1 && !committed) abandon(installer, sessionId);
            return false;
        }
    }

    private static void abandon(PackageInstaller installer, int sessionId) {
        try {
            installer.abandonSession(sessionId);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't abandon install session " + sessionId, e);
        }
    }

    /** Shows the system's confirmation screen when Android asks for it, and logs the outcome. */
    public static class ResultReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                if (confirm != null) {
                    context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                }
                return;
            }
            String message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
            if (status == PackageInstaller.STATUS_SUCCESS) {
                Log.i(TAG, "Installed: " + message);
            } else {
                Log.w(TAG, "Install failed: status=" + status + " " + message);
            }
        }
    }
}
