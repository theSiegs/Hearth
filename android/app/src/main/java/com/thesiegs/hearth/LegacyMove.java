package com.thesiegs.hearth;

import android.content.ContentResolver;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Moving a TV from Hearth's old app id (com.leanbitlab.ltvL) to the new one (com.thesiegs.hearth); see
 * docs/design/app-id-change.md.
 *
 * <p>The old id's bridge build offers its data through {@link LegacyExportProvider} (only to the new Hearth, signed
 * with the same key). The new Hearth copies it the first time it starts ({@link #runIfDue}, from
 * {@link HearthApplication} before anything has opened a setting or the database), or again when asked from
 * Settings ({@link #request}: the next start re-imports, replacing what's there).
 *
 * <p>What moves: Hearth's private data folders as they are, so every setting, section, per-profile layout, Profile
 * Pairing choice, wallpaper picture, Home Assistant setting and the self-adb key come over unchanged. What doesn't:
 * the agent bookkeeping for other profiles (rebuilt when the profiles' agents connect), what was sent to them, and
 * the streaming PINs, whose Keystore key can't leave the old app: they're kept as "enter again" entries.
 */
final class LegacyMove {
    private static final String TAG = "HearthMove";

    /** This class's own record; never exported, never replaced. */
    static final String STATE_PREFS = "hearth_move";
    static final String KEY_STATE = "state";
    static final String KEY_DETAIL = "detail";
    static final String KEY_AT = "at";
    static final String KEY_FILES = "files";
    static final String KEY_BYTES = "bytes";
    static final String KEY_PINS = "pins_to_reenter";
    static final String KEY_FROM_VERSION = "from_version";
    static final String KEY_NOTICE_SHOWN = "notice_shown";

    /** Nothing to do: no old Hearth on this TV when the new one first started. */
    static final String STATE_NONE = "none";
    /** The old Hearth's data was copied. */
    static final String STATE_IMPORTED = "imported";
    /** The old Hearth is installed but doesn't offer its data (not the bridge build yet, or refused). */
    static final String STATE_UNAVAILABLE = "unavailable";
    static final String STATE_FAILED = "failed";
    /** Asked for from Settings: the next start imports, replacing this Hearth's data. */
    static final String STATE_REQUESTED = "requested";
    /** Not the TV owner's user (a profile's agent): nothing to move there. */
    static final String STATE_NOT_OWNER = "not_owner";

    /** The data folders that move; everything else (caches, code caches, WebView) is rebuilt. */
    static final String[] ROOTS = {"shared_prefs", "app_flutter", "files", "databases"};

    /** Left behind: this move's own record, and per-install state about other profiles' agents. */
    private static final String[] EXCLUDED = {
            "shared_prefs/" + STATE_PREFS + ".xml",
            "shared_prefs/ltv_agents.xml",       // AgentHub: per-profile agent keys (new agents, new keys)
            "shared_prefs/ltv_agent.xml",        // AgentService: this user's agent state
            "shared_prefs/ltv_agent_wallpaper.xml",
            "shared_prefs/hearth_wallpaper.xml", // what was sent to the agents: send it all again
    };

    private static final String STAGING = "hearth_move_staging";

    private LegacyMove() {
    }

    // --- rules (plain Java, unit tested) ---

    /** The old id's package matching this build: "com.leanbitlab.ltvL", or its ".debug" for a debug build. */
    static String legacyPackage(String ownPackage) {
        return ownPackage.endsWith(".debug") ? BuildConfig.LEGACY_APP_ID + ".debug" : BuildConfig.LEGACY_APP_ID;
    }

    /** The package allowed to take the bridge's data: the new id, release or debug like the bridge itself. */
    static String newPackage(String bridgePackage) {
        return bridgePackage.endsWith(".debug") ? BuildConfig.HEARTH_APP_ID + ".debug" : BuildConfig.HEARTH_APP_ID;
    }

    static String authority(String exportingPackage) {
        return exportingPackage + ".legacyexport";
    }

    /** A path relative to the data folder that may move: inside one of {@link #ROOTS}, no "..", not excluded. */
    static boolean movable(String relative) {
        if (relative == null || relative.isEmpty() || relative.startsWith("/") || relative.contains("\\")) return false;
        for (String part : relative.split("/")) {
            if (part.isEmpty() || part.equals(".") || part.equals("..")) return false;
        }
        boolean inRoot = false;
        for (String root : ROOTS) {
            if (relative.startsWith(root + "/")) inRoot = true;
        }
        if (!inRoot) return false;
        for (String excluded : EXCLUDED) {
            if (relative.equals(excluded) || relative.startsWith(excluded + "/")) return false;
        }
        return true;
    }

    /** Every movable file under {@code dataDir}, as relative paths with "/" separators. */
    static List<String> movableFiles(File dataDir) {
        List<String> out = new ArrayList<>();
        for (String root : ROOTS) collect(new File(dataDir, root), root, out);
        return out;
    }

    private static void collect(File dir, String relative, List<String> out) {
        File[] children = dir.listFiles();
        if (children == null) return;
        for (File child : children) {
            String path = relative + "/" + child.getName();
            if (child.isDirectory()) {
                collect(child, path, out);
            } else if (child.isFile() && movable(path)) {
                out.add(path);
            }
        }
    }

    // --- the new Hearth's side ---

    static SharedPreferences state(Context context) {
        return context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE);
    }

    /** Asks for an import at the next start, replacing this Hearth's data with the old one's. */
    static void request(Context context) {
        state(context).edit().putString(KEY_STATE, STATE_REQUESTED).commit();
    }

    /**
     * Imports the old Hearth's data when it's due: on the first start of the new Hearth (nothing of its own yet), or
     * when {@link #request}ed. Runs before anything reads Hearth's settings or database. Never in the bridge build.
     */
    static void runIfDue(Context context) {
        if (BuildConfig.BRIDGE) return;
        SharedPreferences prefs = state(context);
        String current = prefs.getString(KEY_STATE, null);
        boolean requested = STATE_REQUESTED.equals(current);
        if (current != null && !requested) return;

        if (android.os.Process.myUid() / 100000 != 0) {
            record(prefs, STATE_NOT_OWNER, null);
            return;
        }
        File dataDir = context.getDataDir();
        boolean fresh = !new File(dataDir, "shared_prefs/FlutterSharedPreferences.xml").exists()
                && !new File(dataDir, "app_flutter/db.sqlite").exists();
        if (!fresh && !requested) {
            // Used before this record existed (or set up by hand): leave it alone; Settings can still import
            record(prefs, STATE_NONE, "already set up");
            return;
        }

        String legacy = legacyPackage(context.getPackageName());
        PackageInfo legacyInfo = packageInfo(context, legacy);
        if (legacyInfo == null) {
            record(prefs, STATE_NONE, null);
            return;
        }
        try {
            importFrom(context, legacy, legacyInfo, dataDir, prefs);
        } catch (SecurityException e) {
            Log.w(TAG, "the old Hearth refused to hand over its data", e);
            record(prefs, STATE_UNAVAILABLE, "refused");
        } catch (Exception e) {
            Log.w(TAG, "moving the old Hearth's data failed", e);
            record(prefs, STATE_FAILED, e.getClass().getSimpleName() + ": " + e.getMessage());
        } finally {
            deleteTree(new File(dataDir, STAGING));
        }
    }

    private static void importFrom(Context context, String legacy, PackageInfo legacyInfo, File dataDir,
            SharedPreferences prefs) throws Exception {
        ContentResolver resolver = context.getContentResolver();
        Uri base = Uri.parse("content://" + authority(legacy));
        List<String> paths = new ArrayList<>();
        try (Cursor cursor = resolver.query(base.buildUpon().appendPath("files").build(), null, null, null, null)) {
            if (cursor == null) {
                // An old Hearth from before the bridge build: no provider to ask
                record(prefs, STATE_UNAVAILABLE, "no export");
                return;
            }
            int column = cursor.getColumnIndexOrThrow("path");
            while (cursor.moveToNext()) {
                String path = cursor.getString(column);
                if (movable(path)) paths.add(path);
            }
        }

        // Copy everything into a staging folder first: a failure half way leaves this Hearth as it was
        File staging = new File(dataDir, STAGING);
        deleteTree(staging);
        long bytes = 0;
        for (String path : paths) {
            File target = new File(staging, path);
            File parent = target.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) throw new IOException("mkdirs " + parent);
            Uri file = base.buildUpon().appendPath("file").appendQueryParameter("path", path).build();
            try (InputStream in = resolver.openInputStream(file); OutputStream out = new FileOutputStream(target)) {
                if (in == null) throw new IOException("no stream for " + path);
                byte[] buffer = new byte[64 * 1024];
                int n;
                while ((n = in.read(buffer)) > 0) {
                    out.write(buffer, 0, n);
                    bytes += n;
                }
            }
        }

        // Replace this Hearth's own data (none on a first start) with the copy
        for (String root : ROOTS) clearMovable(new File(dataDir, root), root);
        for (String path : paths) {
            File from = new File(staging, path);
            File to = new File(dataDir, path);
            File parent = to.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) throw new IOException("mkdirs " + parent);
            if (!from.renameTo(to)) throw new IOException("couldn't move " + path + " into place");
        }

        int pins = PinVault.keepForReentry(context);
        // The services were the old Hearth's: the "Hearth moved" notice asks for them, not the Home Button Fix reminder
        LauncherAccessibilityService.forgetHomeButtonFix(context);
        prefs.edit()
                .putString(KEY_STATE, STATE_IMPORTED)
                .remove(KEY_DETAIL)
                .putLong(KEY_AT, System.currentTimeMillis())
                .putInt(KEY_FILES, paths.size())
                .putLong(KEY_BYTES, bytes)
                .putInt(KEY_PINS, pins)
                .putString(KEY_FROM_VERSION, legacyInfo.versionName)
                .putBoolean(KEY_NOTICE_SHOWN, false)
                .commit();
        Log.i(TAG, "moved " + paths.size() + " files (" + bytes + " bytes) from " + legacy + " "
                + legacyInfo.versionName + "; " + pins + " PINs to enter again");
    }

    /** Deletes the movable files under {@code dir} (this record and other excluded files stay). */
    private static void clearMovable(File dir, String relative) {
        File[] children = dir.listFiles();
        if (children == null) return;
        for (File child : children) {
            String path = relative + "/" + child.getName();
            if (child.isDirectory()) {
                clearMovable(child, path);
                String[] left = child.list();
                if (left != null && left.length == 0) child.delete();
            } else if (movable(path)) {
                child.delete();
            }
        }
    }

    private static void record(SharedPreferences prefs, String state, String detail) {
        SharedPreferences.Editor editor = prefs.edit().putString(KEY_STATE, state).putLong(KEY_AT, System.currentTimeMillis());
        if (detail != null) editor.putString(KEY_DETAIL, detail);
        else editor.remove(KEY_DETAIL);
        // Hearth says once why the old Hearth's data didn't come over
        editor.putBoolean(KEY_NOTICE_SHOWN, !STATE_UNAVAILABLE.equals(state) && !STATE_FAILED.equals(state));
        editor.commit();
    }

    static PackageInfo packageInfo(Context context, String pkg) {
        try {
            return context.getPackageManager().getPackageInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }

    /** Whether the old Hearth on this TV offers its data (it's the bridge build). */
    static boolean legacyOffersData(Context context) {
        String legacy = legacyPackage(context.getPackageName());
        return packageInfo(context, legacy) != null
                && context.getPackageManager().resolveContentProvider(authority(legacy), 0) != null;
    }

    /** For Settings and the "Hearth moved" notice; see FLauncherChannel.getMoveStatus. */
    static java.util.Map<String, Object> status(Context context) {
        SharedPreferences prefs = state(context);
        String own = context.getPackageName();
        String legacy = legacyPackage(own);
        String fresh = newPackage(own);
        java.util.Map<String, Object> out = new java.util.HashMap<>();
        out.put("bridge", BuildConfig.BRIDGE);
        out.put("state", prefs.getString(KEY_STATE, null));
        out.put("detail", prefs.getString(KEY_DETAIL, null));
        out.put("at", prefs.getLong(KEY_AT, 0));
        out.put("files", prefs.getInt(KEY_FILES, 0));
        out.put("bytes", prefs.getLong(KEY_BYTES, 0));
        out.put("pinsToReenter", prefs.getInt(KEY_PINS, 0));
        out.put("fromVersion", prefs.getString(KEY_FROM_VERSION, null));
        out.put("noticeShown", prefs.getBoolean(KEY_NOTICE_SHOWN, true));
        out.put("legacyPackage", legacy);
        PackageInfo legacyInfo = BuildConfig.BRIDGE ? null : packageInfo(context, legacy);
        out.put("legacyInstalled", legacyInfo != null);
        out.put("legacyVersion", legacyInfo != null ? legacyInfo.versionName : null);
        out.put("legacyOffersData", !BuildConfig.BRIDGE && legacyOffersData(context));
        out.put("newPackage", fresh);
        PackageInfo newInfo = BuildConfig.BRIDGE ? packageInfo(context, fresh) : null;
        out.put("newInstalled", newInfo != null);
        out.put("newVersion", newInfo != null ? newInfo.versionName : null);
        return out;
    }

    static void markNoticeShown(Context context) {
        state(context).edit().putBoolean(KEY_NOTICE_SHOWN, true).apply();
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteTree(child);
        }
        file.delete();
    }
}
