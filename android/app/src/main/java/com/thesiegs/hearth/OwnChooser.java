package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.util.Log;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Hearth's own profile picker over Google TV's profile chooser (experiment, feature/own-chooser; never merged).
 *
 * <p>Wherever Hearth opens Google's chooser (the TV going to sleep, the profile button, Settings &gt; Profiles), it
 * still opens Google's chooser first, and then puts {@link OwnChooserActivity} over it: faces, names, kid or adult.
 * Picking someone there closes Hearth's picker and has the accessibility service focus and click that person's tile
 * in Google's chooser ({@link ChooserTiles} decides which, or that it won't), so Google itself makes the switch and
 * its own PIN screen decides. Hearth never types a PIN, never presses OK on a PIN, lock or account screen, and never
 * starts or stops an Android user.
 *
 * <p>Because Google's chooser is always underneath, Back, Home, a crash of Hearth's picker or anything that bypasses
 * it leaves Google's chooser on screen, not a profile. Only a chooser Hearth itself just opened gets the picker: one
 * another app opened (an app asking which account to use) stays Google's.
 */
final class OwnChooser {
    private static final String TAG = "HearthOwnChooser";
    private static final String PREFS = "hearth_own_chooser";
    private static final String ON_KEY = "on";
    /** On in this experimental build. */
    static final boolean DEFAULT_ON = true;
    /** Hearth's request for the picker holds this long, for Google's chooser to come up. */
    static final long WANTED_MS = 8_000;

    /** When Hearth last opened Google's chooser wanting its picker over it (elapsed realtime; 0: not wanted). */
    private static long sWantedAt;

    private OwnChooser() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isOn(Context context) {
        return prefs(context).getBoolean(ON_KEY, DEFAULT_ON);
    }

    static void setOn(Context context, boolean on) {
        prefs(context).edit().putBoolean(ON_KEY, on).apply();
        Log.i(TAG, "Hearth's profile picker " + (on ? "on" : "off"));
    }

    /**
     * Opens Google TV's profile chooser, wanting Hearth's picker over it when that's on and the accessibility service
     * (which clicks the tile) runs. Whether Google's chooser opened.
     */
    static boolean open(Context context) {
        boolean wanted = isOn(context) && LauncherAccessibilityService.isRunning();
        try {
            if (wanted) sWantedAt = SystemClock.elapsedRealtime();
            context.startActivity(LauncherAccessibilityService.profileChooserIntent()
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        } catch (Exception e) {
            sWantedAt = 0;
            Log.w(TAG, "Couldn't open the profile chooser: " + e.getClass().getSimpleName());
            return false;
        }
    }

    /** Google's chooser just came up: whether Hearth opened it for its picker (asked once per opening). */
    static boolean takeWanted() {
        boolean wanted = wantedNow(sWantedAt, SystemClock.elapsedRealtime());
        sWantedAt = 0;
        return wanted;
    }

    static boolean wantedNow(long wantedAt, long now) {
        return wantedAt != 0 && now - wantedAt >= 0 && now - wantedAt < WANTED_MS;
    }

    /** One person in Hearth's picker. */
    static final class Entry {
        final String key;
        /** Google TV's profile name (null: only the address is known; the chooser hasn't named it yet). */
        final String name;
        final String email;
        final boolean kids;
        /** Google TV's chooser last showed the profile PIN-locked. */
        final boolean locked;

        Entry(String key, String name, String email, boolean kids, boolean locked) {
            this.key = key;
            this.name = name;
            this.email = email;
            this.kids = kids;
            this.locked = locked;
        }

        /** What the picker shows: the name, else the address's part before the "@" (a stand-in until it's named). */
        String label() {
            if (name != null && !name.isEmpty()) return name;
            return standIn(email);
        }
    }

    static String standIn(String email) {
        if (email == null) return "?";
        int at = email.indexOf('@');
        return at > 0 ? email.substring(0, at) : email;
    }

    /**
     * The people to show: every profile Hearth has a name for (from Google's chooser), with its address from the
     * account list or the chooser, and every account on the TV the chooser hasn't named yet (by address). Profiles
     * whose account is gone from the TV are left out. Adults first, then kids; by name within each.
     */
    static List<Entry> entries(Context context) {
        List<Entry> adults = new ArrayList<>();
        List<Entry> kids = new ArrayList<>();
        Set<String> named = new HashSet<>();
        // Users with a named profile whose address isn't known: an unnamed address there may be that profile
        Set<Long> unsure = new HashSet<>();
        for (ProfileUsers.Known profile : ProfileUsers.known(context)) {
            String email = ProfileUsers.emailOf(context, profile.key);
            if (!AccountList.stillThere(context, email)) continue;
            if (email != null) named.add(email.toLowerCase(Locale.ROOT));
            else unsure.add(profile.serial);
            boolean kid = Boolean.TRUE.equals(ProfileUsers.isSupervised(context, profile.serial));
            boolean locked = Boolean.TRUE.equals(ProfileUsers.isLocked(context, profile.name));
            (kid ? kids : adults).add(new Entry(profile.key, profile.name, email, kid, locked));
        }
        // Accounts the chooser hasn't named yet: shown by address, and found in the chooser by it
        for (Map.Entry<Long, List<String>> user : AccountList.bySerial(context).entrySet()) {
            boolean kid = Boolean.TRUE.equals(ProfileUsers.isSupervised(context, user.getKey()));
            if (unsure.contains(user.getKey())) continue;
            for (String email : user.getValue()) {
                if (named.contains(email.toLowerCase(Locale.ROOT))) continue;
                // The chooser may have shown this address on a tile with a name: that name, else the address's stand-in
                String shown = ProfileUsers.nameForEmail(context, email);
                boolean locked = shown != null && Boolean.TRUE.equals(ProfileUsers.isLocked(context, shown));
                (kid ? kids : adults).add(new Entry(kid ? ProfileUsers.key(user.getKey()) : null, shown, email, kid,
                        locked));
            }
        }
        Collections.sort(adults, (a, b) -> a.label().compareToIgnoreCase(b.label()));
        Collections.sort(kids, (a, b) -> a.label().compareToIgnoreCase(b.label()));
        List<Entry> out = new ArrayList<>(adults);
        out.addAll(kids);
        return out;
    }
}
