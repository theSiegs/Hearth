package com.thesiegs.hearth;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.util.Log;
import android.view.inputmethod.InputMethodInfo;
import android.view.inputmethod.InputMethodManager;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Which keyboard the TV types with, for Hearth's text fields: on-screen and voice first, a phone only when one is there.
 *
 * <p>Google TV's remote service makes its own input method ({@code ImeBridgeService}) the TV's keyboard while a phone
 * with the Google TV app is connected, so typing goes to the phone. When the phone drops off without disconnecting the
 * setting can stay on the bridge, and every text field then waits for a phone that isn't there. Android doesn't let an
 * app pick an input method for its own window, so Hearth can't simply ask for Gboard. What it does:
 * <ul>
 *   <li>Always: reads the TV's keyboard ({@link #status}). When it isn't an on-screen one, Flutter shows Hearth's own
 *   on-screen keyboard with the mic instead of waiting for the phone.</li>
 *   <li>With WRITE_SECURE_SETTINGS (granted once over adb, Settings &gt; System &gt; Set up Hearth TV &gt; On-screen keyboard first): puts the TV's
 *   keyboard back on the on-screen one ({@link #useOnScreen}) when a Hearth field asks for the keyboard and no phone is
 *   known to be there. Google's remote service makes its bridge the keyboard again when a phone connects.</li>
 * </ul>
 *
 * <p>Whether a phone is really there: Android gives an app no way to see the remote service's connections (its sockets,
 * its bound client and its state are all private to it). Hearth knows only its own remote API: a paired phone (Glint)
 * with a session open now, which also holds Remote v2 for keys and text. A phone typing through the Google TV app alone
 * is not detectable; its typing still arrives when Hearth's field is handed to the system keyboard.
 */
final class Keyboards {
    private static final String TAG = "HearthKeyboards";

    static final String KIND_ON_SCREEN = "onscreen";
    static final String KIND_PHONE = "phone";
    static final String KIND_VOICE = "voice";
    static final String KIND_NONE = "none";

    /** Google TV's remote service: its input method sends typing to the connected phone. */
    static final String REMOTE_SERVICE = "com.google.android.tv.remote.service";
    static final String GBOARD = "com.google.android.inputmethod.latin";
    /** Android TV's older on-screen keyboard. */
    static final String LEANBACK_IME = "com.google.android.leanback.ime";

    /** A phone remote counts as there once its session has been open this long (a quick check-in is not a remote). */
    static final long PHONE_SESSION_MIN_MS = 5_000;

    private static final String PREFS = "hearth_keyboards";
    private static final String SWITCHED_FROM = "switched_from";
    private static final String SWITCHED_TO = "switched_to";
    private static final String SWITCHED_AT = "switched_at";

    private Keyboards() {
    }

    /** What kind of keyboard an input method id ("package/class") is. Unknown ones count as on-screen. */
    static String kind(String id) {
        if (id == null || id.trim().isEmpty()) return KIND_NONE;
        String pkg = id.contains("/") ? id.substring(0, id.indexOf('/')) : id;
        String cls = id.contains("/") ? id.substring(id.indexOf('/') + 1) : "";
        if (REMOTE_SERVICE.equals(pkg) || cls.contains("ImeBridge")) return KIND_PHONE;
        if (cls.contains("VoiceInputMethod")) return KIND_VOICE;
        return KIND_ON_SCREEN;
    }

    /**
     * The on-screen keyboard to put back among the TV's enabled input methods: Gboard first, then Android TV's own,
     * then any other on-screen one. Null when there is none.
     */
    static String pickOnScreen(List<String> enabled) {
        if (enabled == null) return null;
        String fallback = null;
        for (String preferred : new String[]{GBOARD, LEANBACK_IME}) {
            for (String id : enabled) {
                if (id != null && id.startsWith(preferred + "/") && KIND_ON_SCREEN.equals(kind(id))) return id;
            }
        }
        for (String id : enabled) {
            if (KIND_ON_SCREEN.equals(kind(id))) {
                fallback = id;
                break;
            }
        }
        return fallback;
    }

    /** The TV's keyboard now (the current user's default input method), or null. */
    static String current(Context context) {
        try {
            return Settings.Secure.getString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't read the keyboard: " + e.getClass().getSimpleName());
            return null;
        }
    }

    /** The ids of the input methods turned on in the TV's settings. */
    static List<String> enabled(Context context) {
        List<String> ids = new ArrayList<>();
        try {
            InputMethodManager imm = context.getSystemService(InputMethodManager.class);
            if (imm == null) return ids;
            for (InputMethodInfo info : imm.getEnabledInputMethodList()) ids.add(info.getId());
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't list the keyboards: " + e.getClass().getSimpleName());
        }
        return ids;
    }

    /** Whether Hearth may change the TV's keyboard (WRITE_SECURE_SETTINGS, granted over adb). */
    static boolean canSwitch(Context context) {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
                == PackageManager.PERMISSION_GRANTED;
    }

    /** Whether a phone remote is there now, as far as Hearth can tell (see the class comment). */
    static boolean phoneThere() {
        return RemoteApiService.phoneRemoteOpen(PHONE_SESSION_MIN_MS);
    }

    /**
     * For Flutter's keyboard choice: {@code current} (the input method id or null), {@code kind} (on-screen, phone,
     * voice or none), {@code phone} (a phone remote is there now), {@code canSwitch} and {@code onScreen} (the
     * on-screen keyboard Hearth would put back, or null).
     */
    static Map<String, Object> status(Context context) {
        String current = current(context);
        Map<String, Object> status = new HashMap<>();
        status.put("current", current);
        status.put("kind", kind(current));
        status.put("phone", phoneThere());
        status.put("canSwitch", canSwitch(context));
        status.put("onScreen", pickOnScreen(enabled(context)));
        return status;
    }

    /** Whether Hearth should put the on-screen keyboard back: the TV's isn't one, no phone is there, and it may. */
    static boolean shouldSwitch(String currentKind, boolean phone, boolean canSwitch, String onScreen) {
        return canSwitch && onScreen != null && !phone && !KIND_ON_SCREEN.equals(currentKind);
    }

    /**
     * Makes the TV's keyboard the on-screen one again when a Hearth field asks for it and the TV's is a phone bridge
     * (or none) with no phone there. Returns whether it switched. Notes what it replaced, for the log.
     */
    static boolean useOnScreen(Context context) {
        String current = current(context);
        String onScreen = pickOnScreen(enabled(context));
        if (!shouldSwitch(kind(current), phoneThere(), canSwitch(context), onScreen)) return false;
        try {
            if (!Settings.Secure.putString(context.getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD,
                    onScreen)) {
                return false;
            }
        } catch (SecurityException e) {
            Log.w(TAG, "Not allowed to change the keyboard");
            return false;
        }
        Log.i(TAG, "Keyboard was " + current + " with no phone there: back to " + onScreen);
        prefs(context).edit()
                .putString(SWITCHED_FROM, current)
                .putString(SWITCHED_TO, onScreen)
                .putLong(SWITCHED_AT, System.currentTimeMillis())
                .apply();
        return true;
    }

    /** Android's keyboard chooser (it changes the TV's keyboard for every app). False when it couldn't be shown. */
    static boolean showPicker(Context context) {
        try {
            InputMethodManager imm = context.getSystemService(InputMethodManager.class);
            if (imm == null) return false;
            imm.showInputMethodPicker();
            return true;
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't show the keyboard chooser: " + e.getClass().getSimpleName());
            return false;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
