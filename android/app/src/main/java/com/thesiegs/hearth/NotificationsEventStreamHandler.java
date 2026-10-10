package com.thesiegs.hearth;

import android.app.Activity;
import android.app.ActivityOptions;
import android.app.Notification;
import android.app.PendingIntent;
import android.content.Context;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;

/** The notifications event channel: the active notifications now, then again whenever they change. */
final class NotificationsEventStreamHandler implements EventChannel.StreamHandler {
    private static final String TAG = "HearthNotifications";

    private final Activity mActivity;
    private LauncherNotificationListenerService.NotificationListener mListener;

    NotificationsEventStreamHandler(Activity activity) {
        mActivity = activity;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        mListener = () -> mActivity.runOnUiThread(() -> {
            try {
                events.success(activeNotifications());
            } catch (Exception e) {
                Log.w(TAG, "Couldn't send the notifications", e);
            }
        });
        LauncherNotificationListenerService.registerListener(mListener);
        mListener.onNotificationChanged();
    }

    @Override
    public void onCancel(Object arguments) {
        if (mListener != null) {
            LauncherNotificationListenerService.unregisterListener(mListener);
            mListener = null;
        }
    }

    /** The active notifications as the channel sends them; empty while Hearth's listener isn't connected. */
    static List<Map<String, Object>> activeNotifications() {
        List<Map<String, Object>> list = new ArrayList<>();
        LauncherNotificationListenerService service = LauncherNotificationListenerService.getInstance();
        if (service == null) {
            return list;
        }
        try {
            StatusBarNotification[] sbns = service.getActiveNotifications();
            if (sbns != null) {
                for (StatusBarNotification sbn : sbns) {
                    Map<String, Object> map = new HashMap<>();
                    map.put("key", sbn.getKey());
                    map.put("packageName", sbn.getPackageName());

                    Notification notification = sbn.getNotification();
                    String title = "";
                    String text = "";
                    if (notification != null && notification.extras != null) {
                        CharSequence titleChar = notification.extras.getCharSequence(Notification.EXTRA_TITLE);
                        CharSequence textChar = notification.extras.getCharSequence(Notification.EXTRA_TEXT);
                        if (titleChar != null) title = titleChar.toString();
                        if (textChar != null) text = textChar.toString();
                    }
                    map.put("title", title);
                    map.put("text", text);
                    map.put("isClearable", sbn.isClearable());
                    // What a tap on the notification does, and its buttons (not ones that need typed text)
                    map.put("canOpen", notification != null && notification.contentIntent != null);
                    List<Map<String, Object>> actions = new ArrayList<>();
                    if (notification != null && notification.actions != null) {
                        for (int i = 0; i < notification.actions.length; i++) {
                            Notification.Action action = notification.actions[i];
                            if (action == null || action.actionIntent == null || action.title == null) continue;
                            if (action.getRemoteInputs() != null && action.getRemoteInputs().length > 0) continue;
                            Map<String, Object> item = new HashMap<>();
                            item.put("index", i);
                            item.put("title", action.title.toString());
                            actions.add(item);
                        }
                    }
                    map.put("actions", actions);
                    list.add(map);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read the active notifications", e);
        }
        return list;
    }

    /**
     * Does what tapping the notification does (action -1) or presses one of its buttons, as the system shade would.
     * A tap on a notification that cancels itself on a tap also removes it. Whether it was sent.
     */
    static boolean open(Context context, String key, int action) {
        LauncherNotificationListenerService service = LauncherNotificationListenerService.getInstance();
        if (service == null || key == null) return false;
        try {
            StatusBarNotification[] sbns = service.getActiveNotifications();
            if (sbns == null) return false;
            for (StatusBarNotification sbn : sbns) {
                if (!key.equals(sbn.getKey())) continue;
                Notification notification = sbn.getNotification();
                if (notification == null) return false;
                PendingIntent intent;
                if (action < 0) {
                    intent = notification.contentIntent;
                } else if (notification.actions != null && action < notification.actions.length) {
                    intent = notification.actions[action].actionIntent;
                } else {
                    intent = null;
                }
                if (intent == null) return false;
                Bundle options = null;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Hearth is in front: the app it opens may start its activity
                    options = ActivityOptions.makeBasic()
                            .setPendingIntentBackgroundActivityStartMode(
                                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                            .toBundle();
                }
                intent.send(context, 0, null, null, null, null, options);
                if (action < 0 && (notification.flags & Notification.FLAG_AUTO_CANCEL) != 0 && sbn.isClearable()) {
                    service.cancelNotification(key);
                }
                return true;
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't open a notification", e);
        }
        return false;
    }
}
