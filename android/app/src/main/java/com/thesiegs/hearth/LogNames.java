package com.thesiegs.hearth;

import android.content.Context;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Locale;

/**
 * People's names in Hearth's log: in a release build each is a short stand-in ("#3f2a", the same for the same name),
 * so a log pasted into a bug report doesn't name the family. A debug build, or
 * `adb shell settings put global hearth_log_names 1`, logs the names themselves.
 */
final class LogNames {
    static final String SETTING = "hearth_log_names";
    private static volatile boolean sShow = BuildConfig.DEBUG;

    private LogNames() {
    }

    /** Reads the setting again (the accessibility service does, as it starts and every so often). */
    static void refresh(Context context) {
        sShow = BuildConfig.DEBUG
                || Settings.Global.getInt(context.getContentResolver(), SETTING, 0) == 1;
    }

    static void setShowing(boolean show) {
        sShow = show;
    }

    /** A name, or its stand-in. */
    static String of(String name) {
        if (name == null || sShow) return name;
        return standIn(name);
    }

    /** Names, each as {@link #of}. */
    static String of(Collection<String> names) {
        if (names == null || sShow) return String.valueOf(names);
        List<String> out = new ArrayList<>();
        for (String name : names) out.add(of(name));
        return out.toString();
    }

    /** A profile key ("user:0:alex" names its account): its name part as {@link #of}. */
    static String key(String key) {
        if (key == null || sShow) return key;
        int second = key.indexOf(':', key.indexOf(':') + 1);
        return second < 0 ? key : key.substring(0, second + 1) + of(key.substring(second + 1));
    }

    static String standIn(String name) {
        return String.format(Locale.ROOT, "#%04x", name.trim().toLowerCase(Locale.ROOT).hashCode() & 0xffff);
    }
}
