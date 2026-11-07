package com.thesiegs.hearth;

import android.accounts.Account;
import android.accounts.AccountManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.UserHandle;
import android.os.UserManager;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The Google accounts on the TV, per Android user, without reading Google TV's profile chooser (experiment,
 * feature/own-chooser).
 *
 * <p>Where it comes from:
 * <ul>
 * <li>{@link AccountManager}: asked once, for the log. Google TV makes its Google accounts visible only to its own
 * launcher and screensaver, so Hearth sees none (and GET_ACCOUNTS wouldn't change that on Android 8 and later).</li>
 * <li>{@code dumpsys account} over Hearth's own adb (SelfAdb), when the TV trusts Hearth's key: every user's Google
 * accounts, by address. It gives no display names: a Google TV profile's name comes from Google's profile sync,
 * which only Google TV's own screens show. So names (and the household refs made from them) still come from the
 * chooser, once per profile; this adds each profile's address, which profiles exist, and which are a kid's (their
 * own user, which Family Link supervises).</li>
 * </ul>
 * Addresses are kept on the TV only and never logged.
 */
final class AccountList {
    private static final String TAG = "HearthAccounts";
    private static final String PREFS = "hearth_account_list";
    private static final String USERS_KEY = "users";
    private static final String AT_KEY = "at";
    private static final String SOURCE_KEY = "source";
    /** Read again at most this often. */
    static final long REFRESH_MS = 10 * 60_000L;
    private static final int QUIET_TIMEOUT_MS = 5_000;
    /** Android gives each user this many uids: user N's are N * this and up. */
    private static final int PER_USER_RANGE = 100_000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private static final Pattern USER = Pattern.compile("^User UserInfo\\{(\\d+):");
    private static final Pattern ACCOUNT = Pattern.compile("^\\s+Account \\{name=([^,]+), type=com\\.google\\}");

    private AccountList() {
    }

    /**
     * Each Android user's Google account addresses, from {@code dumpsys account}: the "Account {name=…,
     * type=com.google}" lines under each "User UserInfo{id:…}". The history and visibility lines below them name
     * no accounts that way. Users without a Google account are left out.
     */
    static Map<Integer, List<String>> parse(String dump) {
        Map<Integer, List<String>> out = new LinkedHashMap<>();
        if (dump == null) return out;
        Integer user = null;
        for (String line : dump.split("\r?\n")) {
            Matcher u = USER.matcher(line);
            if (u.find()) {
                try {
                    user = Integer.parseInt(u.group(1));
                } catch (NumberFormatException e) {
                    user = null;
                }
                continue;
            }
            if (user == null) continue;
            Matcher a = ACCOUNT.matcher(line);
            if (!a.find()) continue;
            String email = a.group(1).trim();
            if (GoogleTvAccount.emailIn(email) == null) continue;
            List<String> list = out.get(user);
            if (list == null) {
                list = new ArrayList<>();
                out.put(user, list);
            }
            if (!list.contains(email)) list.add(email);
        }
        return out;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** Each profile user's serial and its Google account addresses, as last read; empty when never read. */
    static Map<Long, List<String>> bySerial(Context context) {
        Map<Long, List<String>> out = new LinkedHashMap<>();
        String saved = prefs(context).getString(USERS_KEY, null);
        if (saved == null) return out;
        try {
            JSONObject users = new JSONObject(saved);
            for (Iterator<String> keys = users.keys(); keys.hasNext(); ) {
                String key = keys.next();
                JSONArray emails = users.getJSONArray(key);
                List<String> list = new ArrayList<>();
                for (int i = 0; i < emails.length(); i++) list.add(emails.getString(i));
                out.put(Long.parseLong(key), list);
            }
        } catch (Exception e) {
            Log.w(TAG, "The saved account list isn't readable");
        }
        return out;
    }

    /** Whether the account list has been read at all (else nothing can be said about which accounts exist). */
    static boolean known(Context context) {
        return prefs(context).contains(USERS_KEY);
    }

    /** Where the last list came from ("adb", "accounts" or none), for Settings and the report. */
    static String source(Context context) {
        return prefs(context).getString(SOURCE_KEY, null);
    }

    /** Reads the list again in the background, if it's older than {@link #REFRESH_MS}. */
    static void refreshIfDue(Context context) {
        Context app = context.getApplicationContext();
        long at = prefs(app).getLong(AT_KEY, 0);
        if (Math.abs(System.currentTimeMillis() - at) < REFRESH_MS) return;
        prefs(app).edit().putLong(AT_KEY, System.currentTimeMillis()).apply();
        EXECUTOR.execute(() -> refresh(app));
    }

    /** Reads the list now (background thread). */
    static void refresh(Context context) {
        // What Android lets Hearth see on its own: for the log (Google TV hides its accounts from other apps)
        int visible = -1;
        try {
            Account[] accounts = AccountManager.get(context).getAccountsByType("com.google");
            visible = accounts.length;
        } catch (RuntimeException e) {
            Log.i(TAG, "AccountManager refused: " + e.getClass().getSimpleName());
        }
        Log.i(TAG, "AccountManager shows Hearth " + visible + " Google account(s)");

        if (!SelfAdb.isTrusted(context)) {
            Log.i(TAG, "Not reading the account list: Hearth's adb isn't set up (the chooser names profiles instead)");
            return;
        }
        Map<Integer, List<String>> users;
        try (SelfAdb shell = SelfAdb.open(context, QUIET_TIMEOUT_MS)) {
            users = parse(shell.run("dumpsys account"));
        } catch (Exception e) {
            Log.i(TAG, "Couldn't read the account list: " + e.getClass().getSimpleName());
            return;
        }
        UserManager um = (UserManager) context.getSystemService(Context.USER_SERVICE);
        JSONObject out = new JSONObject();
        int total = 0;
        try {
            for (Map.Entry<Integer, List<String>> user : users.entrySet()) {
                long serial = um != null ? um.getSerialNumberForUser(
                        UserHandle.getUserHandleForUid(user.getKey() * PER_USER_RANGE)) : -1;
                if (serial < 0) continue;
                out.put(String.valueOf(serial), new JSONArray(user.getValue()));
                total += user.getValue().size();
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't keep the account list: " + e.getClass().getSimpleName());
            return;
        }
        prefs(context).edit().putString(USERS_KEY, out.toString()).putString(SOURCE_KEY, "adb").apply();
        Log.i(TAG, "Account list read over Hearth's adb: " + total + " Google account(s) in " + out.length()
                + " user(s)");
        learnEmails(context);
    }

    /**
     * A profile user (not the owner's) with one account is one profile, a kid's: its address belongs to the name the
     * chooser taught Hearth for that serial. And when Hearth hasn't named the serial yet, but the chooser once showed
     * a tile with that address, the tile's name names it: the same name the chooser would give it, so its household
     * ref is unchanged. Not the profile on now (its own switch names it, as before). The owner's user holds several
     * adults' accounts, which only Google TV's home or chooser tell apart.
     */
    static void learnEmails(Context context) {
        long owner = ProfileUsers.ownerSerial(context);
        long active = ProfileUsers.settledSerial(context);
        for (Map.Entry<Long, List<String>> user : bySerial(context).entrySet()) {
            long serial = user.getKey();
            if (user.getValue().size() != 1 || serial == owner) continue;
            String email = user.getValue().get(0);
            String name = ProfileUsers.getName(context, serial);
            if (name == null && serial != active) {
                String shown = ProfileUsers.nameForEmail(context, email);
                long elsewhere = ProfileUsers.serialOf(context, shown);
                if (shown != null && elsewhere == ProfileUsers.UNKNOWN) {
                    Log.i(TAG, "Serial " + serial + " named from the account list and the chooser's address");
                    ProfileUsers.setName(context, serial, shown);
                    ProfilePairing.adoptNameChoices(context, ProfileUsers.key(serial), shown);
                    name = shown;
                }
            }
            if (name != null && ProfileUsers.emailOf(context, ProfileUsers.key(serial)) == null) {
                ProfileUsers.setEmail(context, name, email);
            }
        }
    }

    /** Whether this address is still one of the TV's Google accounts (true when the list was never read). */
    static boolean stillThere(Context context, String email) {
        if (email == null || !known(context)) return true;
        for (List<String> emails : bySerial(context).values()) {
            for (String e : emails) {
                if (e.equalsIgnoreCase(email)) return true;
            }
        }
        return false;
    }
}
