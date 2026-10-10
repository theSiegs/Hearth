package com.thesiegs.hearth;

import android.app.Notification;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

public class LauncherNotificationListenerService extends NotificationListenerService {
    private static final String TAG = "HearthNotifications";
    private static final long POPUP_MS = 4_000;

    public interface NotificationListener {
        void onNotificationChanged();
    }

    private static final List<NotificationListener> listeners = new ArrayList<>();
    private static LauncherNotificationListenerService instance = null;

    private final Handler mHandler = new Handler(Looper.getMainLooper());

    public static void registerListener(NotificationListener listener) {
        synchronized (listeners) {
            listeners.add(listener);
        }
    }

    public static void unregisterListener(NotificationListener listener) {
        synchronized (listeners) {
            listeners.remove(listener);
        }
    }

    public static LauncherNotificationListenerService getInstance() {
        return instance;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        notifyListeners();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (instance == this) {
            instance = null;
        }
        notifyListeners();
    }

    @Override
    public void onListenerConnected() {
        super.onListenerConnected();
        // Just allowed from the setup flow: back to it
        SetupReturn.onConnected(this, SetupReturn.NOTIFICATION_ACCESS);
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        notifyListeners();
        showNotificationPopup(sbn);
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        notifyListeners();
    }

    private void notifyListeners() {
        synchronized (listeners) {
            for (NotificationListener listener : listeners) {
                listener.onNotificationChanged();
            }
        }
    }

    private boolean canShowPopup() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this);
        }
        return true;
    }

    private int dp(int value) {
        return Dp.px(this, value);
    }

    /** Pops up a new notification for a few seconds in the top corner, when that's turned on. */
    private void showNotificationPopup(StatusBarNotification sbn) {
        if (!shouldPopUp(sbn)) return;
        Bundle extras = sbn.getNotification().extras;
        CharSequence titleChar = extras.getCharSequence(Notification.EXTRA_TITLE);
        CharSequence textChar = extras.getCharSequence(Notification.EXTRA_TEXT);
        String title = titleChar != null ? titleChar.toString().trim() : "";
        String text = textChar != null ? textChar.toString().trim() : "";
        if (title.isEmpty() && text.isEmpty()) return;

        String packageName = sbn.getPackageName();
        PackageManager pm = getPackageManager();
        String appLabel = packageName;
        Drawable appIcon = null;
        try {
            ApplicationInfo appInfo = pm.getApplicationInfo(packageName, 0);
            appLabel = pm.getApplicationLabel(appInfo).toString().trim();
            appIcon = pm.getApplicationIcon(appInfo);
        } catch (Exception e) {
            Log.w(TAG, "No label or icon for " + packageName, e);
        }

        // Generic "app is running" notifications whose title and text are just the app's name
        if (title.equalsIgnoreCase(appLabel) && (text.isEmpty() || text.equalsIgnoreCase(appLabel))) return;
        if (title.equalsIgnoreCase(packageName) && (text.isEmpty() || text.equalsIgnoreCase(packageName))) return;

        String label = appLabel;
        Drawable icon = appIcon;
        mHandler.post(() -> {
            try {
                showFor(buildPopup(label, icon, title, text), POPUP_MS);
            } catch (Exception e) {
                Log.w(TAG, "Couldn't show the notification popup", e);
            }
        });
    }

    /** Popups are on, Hearth may draw over apps, and it's not ongoing, a service's, or media playback. */
    private boolean shouldPopUp(StatusBarNotification sbn) {
        if (sbn == null || sbn.isOngoing()) return false;
        if (!FlutterPrefs.getBoolean(this, "system_notifications_popup", false) || !canShowPopup()) return false;
        Notification notification = sbn.getNotification();
        if (notification == null) return false;
        if (Notification.CATEGORY_SERVICE.equals(notification.category)
                || Notification.CATEGORY_TRANSPORT.equals(notification.category)) {
            return false;
        }
        return notification.extras != null && !notification.extras.containsKey(Notification.EXTRA_MEDIA_SESSION);
    }

    /** The app's icon, then "App • Title" over the text, on a dark rounded card. */
    private View buildPopup(String appLabel, Drawable appIcon, String title, String text) {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.HORIZONTAL);
        container.setGravity(Gravity.CENTER_VERTICAL);
        int pad = dp(16);
        container.setPadding(pad, pad, pad, pad);

        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.parseColor("#E01E1E1E"));
        background.setCornerRadius(dp(12));
        background.setStroke(dp(1), Color.parseColor("#44FFFFFF"));
        container.setBackground(background);

        ImageView iconView = new ImageView(this);
        if (appIcon != null) {
            iconView.setImageDrawable(appIcon);
        }
        LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(dp(40), dp(40));
        iconParams.rightMargin = dp(12);
        iconView.setLayoutParams(iconParams);
        container.addView(iconView);

        LinearLayout textContainer = new LinearLayout(this);
        textContainer.setOrientation(LinearLayout.VERTICAL);
        textContainer.setLayoutParams(new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        TextView titleView = new TextView(this);
        titleView.setText(title.isEmpty() ? appLabel : getString(R.string.popup_app_and_title, appLabel, title));
        titleView.setTextColor(Color.WHITE);
        titleView.setTextSize(14);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        textContainer.addView(titleView);

        if (!text.isEmpty()) {
            TextView bodyView = new TextView(this);
            bodyView.setText(text);
            bodyView.setTextColor(Color.parseColor("#CCCCCC"));
            bodyView.setTextSize(13);
            LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            bodyParams.topMargin = dp(4);
            bodyView.setLayoutParams(bodyParams);
            textContainer.addView(bodyView);
        }

        container.addView(textContainer);
        return container;
    }

    /** Shows the popup in the top-right corner, over any app, and takes it down after {@code ms}. */
    private void showFor(View popup, long ms) {
        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE;
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.END;
        params.x = dp(24);
        params.y = dp(24);

        WindowManager windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        windowManager.addView(popup, params);
        mHandler.postDelayed(() -> {
            try {
                windowManager.removeView(popup);
            } catch (Exception e) {
                Log.w(TAG, "Couldn't take the notification popup down", e);
            }
        }, ms);
    }
}
