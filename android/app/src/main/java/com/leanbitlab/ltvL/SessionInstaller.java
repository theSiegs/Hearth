package com.leanbitlab.ltvL;

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
 * Installs an APK the way app stores do: through a PackageInstaller session marked as coming from a store.
 * Android 13+ treats an app installed from a downloaded file (an ACTION_VIEW install) as "restricted", and
 * Google TV has no on-screen way to lift that, so its accessibility services (Home Button Fix, Profile Pairing
 * Helper) couldn't be turned on without adb. Store-source session installs aren't restricted. The user still
 * confirms the install on screen.
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
        params.setSize(apk.length());
        try {
            int sessionId = installer.createSession(params);
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
            }
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Session install failed", e);
            return false;
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
            Log.w(TAG, "Install finished: status=" + status + " "
                    + intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE));
        }
    }
}
