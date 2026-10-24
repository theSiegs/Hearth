package com.thesiegs.hearth;

import android.app.Notification;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Parcelable;

/**
 * What a notification says and where a tap on it goes, read the way Android's own shade reads it: the app's name (or
 * the name a system notification asks to be shown as) rather than its package, a title and text from whichever style
 * the app used (big text, inbox, messaging), and on a TV the tap target an app gives Google TV (TvExtender).
 */
final class NotificationContent {
    /** Notification.EXTRA_SUBSTITUTE_APP_NAME: the name a system notification is shown under (hidden in the SDK). */
    static final String EXTRA_SUBSTITUTE_APP_NAME = "android.substName";
    /** Notification.TvExtender's extras, where a TV app keeps its own tap and dismiss intents. */
    private static final String TV_EXTENSIONS = "android.tv.EXTENSIONS";
    private static final String TV_CONTENT_INTENT = "content_intent";
    private static final String TV_DELETE_INTENT = "delete_intent";
    private static final int MAX_LINES = 3;

    private NotificationContent() {
    }

    /** The first of these with something besides spaces in it, trimmed; "" when none has. */
    static String firstText(CharSequence... candidates) {
        for (CharSequence candidate : candidates) {
            if (candidate == null) continue;
            String text = candidate.toString().trim();
            if (!text.isEmpty()) return text;
        }
        return "";
    }

    /** The app's name as the TV shows it: the substitute name a system notification asks for, else its label. */
    static String appLabel(Context context, String packageName, Bundle extras) {
        String substitute = extras != null ? firstText(safeText(extras, EXTRA_SUBSTITUTE_APP_NAME)) : "";
        if (!substitute.isEmpty()) return substitute;
        try {
            PackageManager pm = context.getPackageManager();
            ApplicationInfo info = pm.getApplicationInfo(packageName, 0);
            String label = firstText(pm.getApplicationLabel(info));
            if (!label.isEmpty()) return label;
        } catch (PackageManager.NameNotFoundException | RuntimeException ignored) {
        }
        return packageName;
    }

    /** The title: the plain one, else the expanded one, else a conversation's. */
    static String title(Bundle extras) {
        if (extras == null) return "";
        return firstText(safeText(extras, Notification.EXTRA_TITLE), safeText(extras, Notification.EXTRA_TITLE_BIG),
                safeText(extras, Notification.EXTRA_CONVERSATION_TITLE));
    }

    /**
     * The text: big text, else the plain text, else a messaging style's last message ("Sam: text"), else an inbox
     * style's first lines, else the sub text or ticker.
     */
    static String text(Notification notification) {
        Bundle extras = notification.extras;
        if (extras == null) return firstText(notification.tickerText);
        return firstText(safeText(extras, Notification.EXTRA_BIG_TEXT), safeText(extras, Notification.EXTRA_TEXT),
                lastMessage(extras), lines(extras), safeText(extras, Notification.EXTRA_SUB_TEXT),
                notification.tickerText);
    }

    /** Where a tap goes: the intent the app gave Google TV, else the notification's own. */
    static PendingIntent contentIntent(Notification notification) {
        PendingIntent tv = tvIntent(notification, TV_CONTENT_INTENT);
        return tv != null ? tv : notification.contentIntent;
    }

    /** What dismissing it tells the app: the intent the app gave Google TV, else the notification's own. */
    static PendingIntent deleteIntent(Notification notification) {
        PendingIntent tv = tvIntent(notification, TV_DELETE_INTENT);
        return tv != null ? tv : notification.deleteIntent;
    }

    /**
     * Whether sending this intent can be trusted to bring something up. A broadcast or service intent has the app
     * start its screen itself, which Android blocks for one sent by an app other than the system shade, so it may
     * do nothing; then the app is opened as well. (Unknown before Android 12: trusted.)
     */
    static boolean opensScreen(PendingIntent intent) {
        if (intent == null) return false;
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || intent.isActivity();
    }

    /** The app's TV launch intent, else its phone one; null when it has neither. */
    static Intent launchIntent(Context context, String packageName) {
        PackageManager pm = context.getPackageManager();
        Intent intent = pm.getLeanbackLaunchIntentForPackage(packageName);
        if (intent == null) intent = pm.getLaunchIntentForPackage(packageName);
        if (intent != null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    private static PendingIntent tvIntent(Notification notification, String key) {
        Bundle extras = notification.extras;
        if (extras == null) return null;
        try {
            Bundle tv = extras.getBundle(TV_EXTENSIONS);
            if (tv == null) return null;
            Parcelable intent = tv.getParcelable(key);
            return intent instanceof PendingIntent ? (PendingIntent) intent : null;
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** One text extra; an app can put anything under a key, so a wrong type reads as none. */
    private static CharSequence safeText(Bundle extras, String key) {
        try {
            return extras.getCharSequence(key);
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static String lastMessage(Bundle extras) {
        try {
            Parcelable[] messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES);
            if (messages == null || messages.length == 0 || !(messages[messages.length - 1] instanceof Bundle)) {
                return "";
            }
            Bundle last = (Bundle) messages[messages.length - 1];
            String text = firstText(last.getCharSequence("text"));
            String sender = firstText(last.getCharSequence("sender"));
            return text.isEmpty() || sender.isEmpty() ? text : sender + ": " + text;
        } catch (RuntimeException e) {
            return "";
        }
    }

    private static String lines(Bundle extras) {
        try {
            CharSequence[] lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES);
            if (lines == null) return "";
            StringBuilder out = new StringBuilder();
            int taken = 0;
            for (CharSequence line : lines) {
                String text = firstText(line);
                if (text.isEmpty()) continue;
                if (out.length() > 0) out.append('\n');
                out.append(text);
                if (++taken == MAX_LINES) break;
            }
            return out.toString();
        } catch (RuntimeException e) {
            return "";
        }
    }
}
