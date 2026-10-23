package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Process;
import android.util.Log;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * "Keep Google's ad sandbox off": Android's Privacy Sandbox (ad topics, on-device ad auctions, ad measurement) and the
 * on-device personalization and federated learning that come with it, turned off on this TV and kept off. They are
 * system modules Google switches on and off from its servers and updates through Play, so a module update or a
 * server change could turn them back on; Hearth looks again when the TV wakes and turns off what it finds on.
 *
 * <p>The packages are a fixed list (the names the modules have on Google TV and on other Android builds); nothing
 * else is ever turned off. It runs over Hearth's own adb ({@link SelfAdb}) for this TV's own user only, after a
 * parent turned it on (and saw the commands). The automatic look uses adb only when the TV already trusts Hearth's
 * key, so it never raises "Allow debugging?". Turning the switch off turns back on exactly what Hearth turned off.
 */
final class AdSandbox {
    private static final String TAG = "HearthSandbox";
    private static final String PREFS = "hearth_ad_sandbox";
    private static final String KEEP_OFF = "keep_off";
    /** The packages Hearth itself turned off, which are the ones "back on" enables again. */
    private static final String TURNED_OFF = "turned_off";
    private static final int QUIET_TIMEOUT_MS = 5_000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    /** The Privacy Sandbox modules: com.android.* names on Google TV 14 (onn), com.google.android.* elsewhere. */
    static final List<String> PACKAGES = Collections.unmodifiableList(Arrays.asList(
            "com.android.adservices.api",
            "com.google.android.adservices.api",
            "com.google.android.ext.adservices.api",
            "com.android.ondevicepersonalization.services",
            "com.google.android.ondevicepersonalization.services",
            "com.android.federatedcompute.services",
            "com.google.android.federatedcompute"));

    private AdSandbox() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isKeptOff(Context context) {
        return prefs(context).getBoolean(KEEP_OFF, false);
    }

    /** This TV's own user (the one Hearth runs in), for the commands' {@code --user}. */
    private static int userId() {
        return Process.myUid() / 100_000;
    }

    /** Which of {@link #PACKAGES} this TV has, on or off. */
    static List<String> installed(Context context) {
        List<String> out = new ArrayList<>();
        PackageManager pm = context.getPackageManager();
        for (String pkg : PACKAGES) {
            try {
                pm.getApplicationInfo(pkg, PackageManager.MATCH_DISABLED_COMPONENTS);
                out.add(pkg);
            } catch (PackageManager.NameNotFoundException ignored) {
                // Not on this TV
            }
        }
        return out;
    }

    /** Whether an installed package is on: not turned off by a user or by Hearth. */
    static boolean isOn(Context context, String pkg) {
        PackageManager pm = context.getPackageManager();
        try {
            int state = pm.getApplicationEnabledSetting(pkg);
            if (state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    || state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER) {
                return false;
            }
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return true;
            ApplicationInfo info = pm.getApplicationInfo(pkg, PackageManager.MATCH_DISABLED_COMPONENTS);
            return info.enabled;
        } catch (IllegalArgumentException | PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /** The installed packages still on. */
    static List<String> stillOn(Context context) {
        List<String> out = new ArrayList<>();
        for (String pkg : installed(context)) {
            if (isOn(context, pkg)) out.add(pkg);
        }
        return out;
    }

    static List<String> offCommands(List<String> packages, int user) {
        List<String> out = new ArrayList<>();
        for (String pkg : packages) out.add("pm disable-user --user " + user + " " + pkg);
        return out;
    }

    static List<String> onCommands(List<String> packages, int user) {
        List<String> out = new ArrayList<>();
        for (String pkg : packages) out.add("pm enable --user " + user + " " + pkg);
        return out;
    }

    /** The commands the switch would run now, for the parent to see first: turning off, or back on. */
    static List<String> commands(Context context, boolean keepOff) {
        if (keepOff) return offCommands(stillOn(context), userId());
        List<String> back = new ArrayList<>(prefs(context).getStringSet(TURNED_OFF, Collections.emptySet()));
        back.retainAll(installed(context));
        Collections.sort(back);
        return onCommands(back, userId());
    }

    /**
     * The parent turned the switch on or off: runs the commands over self-adb (the first time, the TV may ask "Allow
     * debugging?") and remembers the choice. Returns what the shell said. Call off the main thread.
     */
    static List<String> setKeptOff(Context context, boolean keepOff) throws Exception {
        List<String> targets = keepOff ? stillOn(context) : null;
        List<String> commands = commands(context, keepOff);
        List<String> log = new ArrayList<>();
        if (!commands.isEmpty()) {
            try (SelfAdb shell = SelfAdb.open(context)) {
                for (String command : commands) {
                    String output = shell.run(command);
                    Log.i(TAG, "Ran " + command + (output == null || output.isEmpty() ? "" : ": " + output.trim()));
                    if (output != null && !output.trim().isEmpty()) log.add(output.trim());
                }
            }
        }
        SharedPreferences.Editor edit = prefs(context).edit().putBoolean(KEEP_OFF, keepOff);
        if (keepOff) {
            Set<String> off = new HashSet<>(prefs(context).getStringSet(TURNED_OFF, Collections.emptySet()));
            off.addAll(targets);
            edit.putStringSet(TURNED_OFF, off);
        } else {
            edit.remove(TURNED_OFF);
        }
        edit.apply();
        return log;
    }

    /**
     * With the switch on, turns off again anything of the list that's back on (a module update, Google's servers),
     * in the background and only when the TV already trusts Hearth's key. Called when the TV wakes and when Hearth's
     * service starts.
     */
    static void check(Context context) {
        Context app = context.getApplicationContext();
        EXECUTOR.execute(() -> {
            if (!isKeptOff(app)) return;
            List<String> on = stillOn(app);
            if (on.isEmpty()) return;
            if (!SelfAdb.isTrusted(app)) {
                Log.i(TAG, on + " came back on; not turning them off: Hearth's adb isn't set up");
                return;
            }
            try (SelfAdb shell = SelfAdb.open(app, QUIET_TIMEOUT_MS)) {
                for (String command : offCommands(on, userId())) shell.run(command);
                Set<String> off = new HashSet<>(prefs(app).getStringSet(TURNED_OFF, Collections.emptySet()));
                off.addAll(on);
                prefs(app).edit().putStringSet(TURNED_OFF, off).apply();
                Log.i(TAG, "Turned " + on + " off again");
            } catch (Exception e) {
                Log.i(TAG, "Couldn't turn " + on + " off again: " + e);
            }
        });
    }
}
