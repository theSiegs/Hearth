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
 * "Keep ad tracking off": Android's Privacy Sandbox (ad topics, on-device ad auctions, ad measurement) and the
 * on-device personalization and federated learning that come with it, turned off on this TV and kept off, for its
 * own user (every adult profile) and each kids profile's user. On unless a parent turned it off. They are system
 * modules Google switches on and off from its servers and updates through Play, so a module update or a server change
 * could turn them back on; Hearth looks again when the TV wakes and turns off what it finds on.
 *
 * <p>The packages are a fixed list (the names the modules have on Google TV and on other Android builds); nothing
 * else is ever turned off. It runs over Hearth's own adb ({@link SelfAdb}). The automatic look uses adb only when the
 * TV already trusts Hearth's key, so it never raises "Allow debugging?". Turning the switch off turns the list back on
 * in each user: what Hearth turned off, and any of it found off (turned off by hand, say).
 */
final class AdSandbox {
    private static final String TAG = "HearthSandbox";
    private static final String PREFS = "hearth_ad_sandbox";
    private static final String KEEP_OFF = "keep_off";
    /** What Hearth itself turned off, "user package" (a bare package: this TV's own user), which "back on" enables. */
    private static final String TURNED_OFF = "turned_off";
    /** When the kids profiles' users were last looked at over adb (wall clock). */
    private static final String KIDS_CHECKED_AT = "kids_checked_at";
    /** How often waking looks at the kids profiles' users, which takes adb even when nothing's on. */
    private static final long KIDS_CHECK_EVERY_MS = 6 * 60 * 60_000L;
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
        return prefs(context).getBoolean(KEEP_OFF, true);
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

    /** This TV's own user, then each kids profile's. */
    private static List<Integer> users(Context context) {
        List<Integer> out = new ArrayList<>();
        out.add(userId());
        for (KidsProfiles.Kid kid : KidsProfiles.list(context)) {
            if (!out.contains(kid.userId)) out.add(kid.userId);
        }
        return out;
    }

    /** Of {@link #PACKAGES}, those {@code pm list packages} printed (one "package:name" a line). */
    static List<String> listedIn(String listing) {
        Set<String> listed = new HashSet<>();
        if (listing != null) {
            for (String line : listing.split("\r?\n")) {
                String l = line.trim();
                if (l.startsWith("package:")) listed.add(l.substring("package:".length()));
            }
        }
        List<String> out = new ArrayList<>();
        for (String pkg : PACKAGES) {
            if (listed.contains(pkg)) out.add(pkg);
        }
        return out;
    }

    /** Turns off what's on, in each user; returns the "user package" entries turned off. */
    private static Set<String> turnOff(SelfAdb shell, List<Integer> users) throws Exception {
        Set<String> off = new HashSet<>();
        for (int user : users) {
            List<String> on = listedIn(shell.run("pm list packages -e --user " + user));
            for (String command : offCommands(on, user)) {
                String output = shell.run(command);
                Log.i(TAG, "Ran " + command + (output == null || output.isEmpty() ? "" : ": " + output.trim()));
            }
            for (String pkg : on) off.add(user + " " + pkg);
        }
        return off;
    }

    private static void rememberTurnedOff(Context context, Set<String> turnedOff) {
        Set<String> off = new HashSet<>(prefs(context).getStringSet(TURNED_OFF, Collections.emptySet()));
        off.addAll(turnedOff);
        prefs(context).edit().putStringSet(TURNED_OFF, off).putLong(KIDS_CHECKED_AT, System.currentTimeMillis()).apply();
    }

    /**
     * A parent turned the switch on or off: runs the commands over self-adb (the first time, the TV may ask "Allow
     * debugging?") and remembers the choice. Returns what the shell said. Call off the main thread.
     */
    static List<String> setKeptOff(Context context, boolean keepOff) throws Exception {
        List<String> log = new ArrayList<>();
        if (keepOff) {
            if (!installed(context).isEmpty()) {
                try (SelfAdb shell = SelfAdb.open(context)) {
                    rememberTurnedOff(context, turnOff(shell, users(context)));
                }
            }
            prefs(context).edit().putBoolean(KEEP_OFF, true).apply();
            return log;
        }
        // What Hearth turned off, in whichever user, and any of the list found off in the users Hearth looks after
        Set<String> back = new HashSet<>(prefs(context).getStringSet(TURNED_OFF, Collections.emptySet()));
        boolean any = !back.isEmpty() || !installed(context).isEmpty();
        if (any) {
            try (SelfAdb shell = SelfAdb.open(context)) {
                for (int user : users(context)) {
                    for (String pkg : listedIn(shell.run("pm list packages -d --user " + user))) back.add(user + " " + pkg);
                }
                for (String entry : back) {
                    int space = entry.indexOf(' ');
                    int user = space < 0 ? userId() : Integer.parseInt(entry.substring(0, space));
                    String pkg = space < 0 ? entry : entry.substring(space + 1);
                    if (!PACKAGES.contains(pkg)) continue;
                    for (String command : onCommands(Collections.singletonList(pkg), user)) {
                        String output = shell.run(command);
                        Log.i(TAG, "Ran " + command + (output == null || output.isEmpty() ? "" : ": " + output.trim()));
                        if (output != null && !output.trim().isEmpty()) log.add(output.trim());
                    }
                }
            }
        }
        prefs(context).edit().putBoolean(KEEP_OFF, false).remove(TURNED_OFF).apply();
        return log;
    }

    /**
     * With the switch on, turns off anything of the list that's on (a module update, Google's servers, a new kids
     * profile), in the background and only when the TV already trusts Hearth's key. This TV's own user is read without
     * adb; the kids profiles' users take adb, so they're looked at every few hours. Called when the TV wakes and when
     * Hearth's service starts.
     */
    static void check(Context context) {
        Context app = context.getApplicationContext();
        EXECUTOR.execute(() -> {
            if (!isKeptOff(app) || installed(app).isEmpty()) return;
            List<String> on = stillOn(app);
            long kidsAt = prefs(app).getLong(KIDS_CHECKED_AT, 0);
            boolean kidsDue = Math.abs(System.currentTimeMillis() - kidsAt) >= KIDS_CHECK_EVERY_MS;
            if (on.isEmpty() && !kidsDue) return;
            if (!SelfAdb.isTrusted(app)) {
                Log.i(TAG, "Not checking ad tracking " + on + ": Hearth's adb isn't set up");
                return;
            }
            List<Integer> users = kidsDue ? users(app) : Collections.singletonList(userId());
            try (SelfAdb shell = SelfAdb.open(app, QUIET_TIMEOUT_MS)) {
                Set<String> off = turnOff(shell, users);
                if (kidsDue || !off.isEmpty()) rememberTurnedOff(app, off);
                if (!off.isEmpty()) Log.i(TAG, "Turned " + off + " off");
            } catch (Exception e) {
                Log.i(TAG, "Couldn't turn ad tracking off for " + users + ": " + e);
            }
        });
    }
}
