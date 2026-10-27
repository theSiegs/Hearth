package com.thesiegs.hearth;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

/**
 * Hearth's link to Home Assistant, kept apart from the accessibility service: the notification server (port 7676) and
 * the status reports to the webhook. Android switches the accessibility service off after a sideloaded update, and
 * Home Assistant shouldn't go quiet with it. Runs only when something is set up (an address and a webhook, or
 * notifications turned on), and only in the TV owner's user.
 *
 * The pop-up itself is still drawn by the accessibility service, whose window needs no extra permission: while it is
 * off, the server answers "unavailable" instead of showing nothing. The accessibility service also feeds the reporter
 * what only it can see (the app in front, Google TV's screen time screens); without it those stay out of the status.
 */
public class HaBridgeService extends Service {
    private static final String TAG = "HearthHaBridge";
    private static final String CHANNEL = "ha_bridge";
    private static final int NOTIFICATION_ID = 2;

    /** The running reporter, for the accessibility service to feed; null when the bridge isn't running. */
    private static volatile HaStatusReporter sStatus;
    // What the accessibility service last said, replayed to a reporter that starts after it
    private static volatile String sForegroundPackage;
    private static volatile boolean sScreenTimeLock;

    private HaStatusReporter mStatus;
    private HaNotificationServer mServer;
    /** Where the reporter was started to post ({@link #reportTarget}), so a refresh that changes nothing doesn't post. */
    private String mReportingTo;
    private boolean mScreenReceiverOn;

    private final BroadcastReceiver mScreenReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (mStatus == null || intent.getAction() == null) return;
            if (Intent.ACTION_SCREEN_ON.equals(intent.getAction())) {
                mStatus.setScreenOn(true);
            } else if (Intent.ACTION_SCREEN_OFF.equals(intent.getAction())) {
                mStatus.setScreenOn(false);
            }
        }
    };

    /** Whether the bridge has anything to do: something is set up, in the TV owner's user. */
    static boolean needed(boolean statusConfigured, boolean notificationsEnabled, boolean agentUser) {
        return !agentUser && (statusConfigured || notificationsEnabled);
    }

    /**
     * Where the status goes and with what, as one value that changes whenever any of it does: the Hearth integration
     * ({@code integrationUrl}, set while paired, and {@code pairing}, which changes with every pairing) or else the
     * webhook; and the Home Assistant token ({@code token}, which changes when a new one is saved). Null when the status
     * goes nowhere.
     */
    static String reportTarget(String integrationUrl, String pairing, String webhookUrl, String token) {
        String to = integrationUrl != null ? "integration " + integrationUrl + " " + pairing
                : webhookUrl != null ? "webhook " + webhookUrl : null;
        return to == null ? null : to + " " + token;
    }

    /**
     * Starts, refreshes or stops the bridge to match what is set up. Safe to call as often as needed (after the
     * settings change, at boot, whenever Hearth or its accessibility service starts): a refresh that changes nothing
     * sends nothing.
     */
    static void sync(Context context) {
        Context app = context.getApplicationContext();
        Intent intent = new Intent(app, HaBridgeService.class);
        if (!needed(HaStatusReporter.isConfigured(app), LauncherAccessibilityService.isHaNotificationsEnabled(app),
                AgentService.isAgent(app))) {
            app.stopService(intent);
            return;
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(intent);
            } else {
                app.startService(intent);
            }
        } catch (RuntimeException e) {
            // Android refuses a foreground start from the background; the next time Hearth is opened tries again
            Log.w(TAG, "Couldn't start the Home Assistant link: " + e.getClass().getSimpleName());
        }
    }

    // --- What the accessibility service tells the reporter (main thread) ---

    static boolean isRunning() {
        return sStatus != null;
    }

    static void setForegroundPackage(String packageName) {
        sForegroundPackage = packageName;
        HaStatusReporter status = sStatus;
        if (status != null) status.setForegroundPackage(packageName);
    }

    static void setScreenOn(boolean on) {
        HaStatusReporter status = sStatus;
        if (status != null) status.setScreenOn(on);
    }

    static void setScreenTimeLock(boolean locked) {
        sScreenTimeLock = locked;
        HaStatusReporter status = sStatus;
        if (status != null) status.setScreenTimeLock(locked);
    }

    static void setScreenTime(ScreenTimeScreen screen) {
        HaStatusReporter status = sStatus;
        if (status != null) status.setScreenTime(screen);
    }

    static void onAppsChanged() {
        HaStatusReporter status = sStatus;
        if (status != null) status.onAppsChanged();
    }

    static void onProfileChanged() {
        HaStatusReporter status = sStatus;
        if (status != null) status.onProfileChanged();
    }

    // --- The service ---

    @Override
    public void onCreate() {
        super.onCreate();
        mStatus = new HaStatusReporter(this);
        sStatus = mStatus;
        if (sForegroundPackage != null) mStatus.setForegroundPackage(sForegroundPackage);
        if (sScreenTimeLock) mStatus.setScreenTimeLock(true);
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (power != null) mStatus.setScreenOn(power.isInteractive());
        IntentFilter screen = new IntentFilter(Intent.ACTION_SCREEN_ON);
        screen.addAction(Intent.ACTION_SCREEN_OFF);
        registerReceiver(mScreenReceiver, screen);
        mScreenReceiverOn = true;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startInForeground();
        refresh();
        return START_STICKY;
    }

    /** Makes the reporter and the server match what is set up now. */
    private void refresh() {
        if (!needed(HaStatusReporter.isConfigured(this), LauncherAccessibilityService.isHaNotificationsEnabled(this),
                AgentService.isAgent(this))) {
            stopSelf();
            return;
        }
        String target = reportTarget(HaIntegration.isPaired(this) ? HaIntegration.statusUrl(this) : null,
                HaIntegration.pairingStamp(this), HaStatusReporter.webhookUrl(this), HaConfig.tokenStamp(this));
        if (target == null) {
            mStatus.stop();
            mReportingTo = null;
        } else if (!target.equals(mReportingTo)) {
            // Starting posts the status at once: a TV just paired, or given a new address or token, shows up right away
            mStatus.start();
            mReportingTo = target;
        }
        boolean notifications = LauncherAccessibilityService.isHaNotificationsEnabled(this);
        if (notifications && mServer == null) {
            mServer = new HaNotificationServer(n -> Household.onHaNotification(this, n));
            mServer.start();
        } else if (!notifications && mServer != null) {
            mServer.stop();
            mServer = null;
        }
    }

    private void startInForeground() {
        NotificationManager notifications = getSystemService(NotificationManager.class);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(new NotificationChannel(CHANNEL,
                    getString(R.string.ha_bridge_channel_name), NotificationManager.IMPORTANCE_MIN));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hearth")
                .setContentText(getString(R.string.ha_bridge_notification_text))
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    @Override
    public void onDestroy() {
        if (mServer != null) mServer.stop();
        mServer = null;
        if (mScreenReceiverOn) {
            try {
                unregisterReceiver(mScreenReceiver);
            } catch (IllegalArgumentException ignored) {
                // Already gone
            }
        }
        sStatus = null;
        if (mStatus != null) mStatus.stop();
        mStatus = null;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
