package com.thesiegs.hearth;

import android.app.Activity;
import android.app.ActivityOptions;
import android.app.Notification;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

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
                // Groups that have notifications of their own listed
                Set<String> groupsWithMembers = new HashSet<>();
                for (StatusBarNotification sbn : sbns) {
                    if (!isGroupSummary(sbn)) groupsWithMembers.add(sbn.getGroupKey());
                }
                for (StatusBarNotification sbn : sbns) {
                    // A group's summary (an app's, or the one Android makes when it bundles an app's notifications)
                    // isn't a notification of its own while its members are listed, as in Android's own shade:
                    // dismissing it would dismiss the whole group
                    if (isGroupSummary(sbn) && groupsWithMembers.contains(sbn.getGroupKey())) continue;
                    Map<String, Object> map = new HashMap<>();
                    map.put("key", sbn.getKey());
                    map.put("packageName", sbn.getPackageName());

                    Notification notification = sbn.getNotification();
                    Bundle extras = notification != null ? notification.extras : null;
                    String label = NotificationContent.appLabel(service, sbn.getPackageName(), extras);
                    String title = notification != null ? NotificationContent.title(extras) : "";
                    String text = notification != null ? NotificationContent.text(notification) : "";
                    map.put("appLabel", label);
                    map.put("title", title);
                    map.put("text", text);
                    map.put("postTime", sbn.getPostTime());
                    map.put("isClearable", sbn.isClearable());
                    // What a tap on the notification does (else the app opens), and its buttons (not ones that need
                    // typed text)
                    map.put("canOpen", notification != null && (NotificationContent.contentIntent(notification) != null
                            || NotificationContent.launchIntent(service, sbn.getPackageName()) != null));
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
                // Newest first, as in Android's own shade
                list.sort((a, b) -> Long.compare((Long) b.get("postTime"), (Long) a.get("postTime")));
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read the active notifications", e);
        }
        return list;
    }

    private static boolean isGroupSummary(StatusBarNotification sbn) {
        Notification notification = sbn.getNotification();
        return notification != null && (notification.flags & Notification.FLAG_GROUP_SUMMARY) != 0;
    }

    /**
     * Does what tapping the notification does (action -1) or presses one of its buttons, as the system shade would.
     * A tap goes where the app told Google TV it should, and opens the app as well when the notification has no tap
     * of its own or its tap may not bring anything up ({@link NotificationContent#opensScreen}). A tap on a
     * notification that cancels itself on a tap also removes it. Whether something was sent or opened.
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
                    intent = NotificationContent.contentIntent(notification);
                } else if (notification.actions != null && action < notification.actions.length) {
                    intent = notification.actions[action].actionIntent;
                } else {
                    intent = null;
                }
                Intent app = action < 0 && !NotificationContent.opensScreen(intent)
                        ? NotificationContent.launchIntent(context, sbn.getPackageName()) : null;
                if (intent == null && app == null) return false;
                Bundle options = null;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Hearth is in front: the app it opens may start its activity
                    options = ActivityOptions.makeBasic()
                            .setPendingIntentBackgroundActivityStartMode(
                                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                            .toBundle();
                }
                boolean sent = false;
                if (intent != null) {
                    try {
                        intent.send(context, 0, null, null, null, null, options);
                        sent = true;
                    } catch (PendingIntent.CanceledException e) {
                        Log.w(TAG, "A notification's intent was cancelled");
                    }
                }
                if (app != null) {
                    try {
                        context.startActivity(app);
                        sent = true;
                    } catch (RuntimeException e) {
                        Log.w(TAG, "Couldn't open a notification's app", e);
                    }
                }
                if (!sent) return false;
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
