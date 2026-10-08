package com.leanbitlab.ltvL;

import android.app.Activity;
import android.app.Notification;
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
                    list.add(map);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read the active notifications", e);
        }
        return list;
    }
}
