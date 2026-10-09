package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

/** The Dart side's settings: Flutter's shared_preferences keeps every key in one file with a "flutter." prefix. */
final class FlutterPrefs {
    private static final String FILE = "FlutterSharedPreferences";
    private static final String PREFIX = "flutter.";

    private FlutterPrefs() {}

    static SharedPreferences get(Context context) {
        return context.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    /** The stored name of a Dart key: "accent_color" is kept as "flutter.accent_color". */
    static String key(String dartKey) {
        return PREFIX + dartKey;
    }

    static String getString(Context context, String dartKey, String fallback) {
        return get(context).getString(key(dartKey), fallback);
    }

    static boolean getBoolean(Context context, String dartKey, boolean fallback) {
        return get(context).getBoolean(key(dartKey), fallback);
    }
}
