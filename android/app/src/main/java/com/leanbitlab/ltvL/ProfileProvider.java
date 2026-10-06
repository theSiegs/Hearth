package com.leanbitlab.ltvL;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;

import java.io.File;
import java.io.FileNotFoundException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Calendar;

/**
 * Shares Hearth's state with HearthTube, so it can follow the profile and match Hearth's look.
 *
 * content://com.leanbitlab.ltvL.profile/active returns one row: the profile name (null when Hearth couldn't tell),
 * accent color ("7C4DFF"), time format ("HH:mm"), app language ("" = the system's), whether a parent PIN is set,
 * the gradient's id and a stamp that changes when the wallpaper picture does (0 = no picture, use the gradient).
 * None of it is secret: it's all on screen in Hearth. The wallpaper picture itself is at .../wallpaper.
 *
 * One call, for HearthTube only: "verify_parent_pin" checks a PIN without ever handing out the PIN or its hash
 * (5 wrong tries lock it for a minute).
 */
public class ProfileProvider extends ContentProvider {
    private static final String[] COLUMNS = {
            "name", "accent_color", "time_format", "app_language", "has_parent_pin", "gradient_uuid", "wallpaper_stamp"};
    private static final String HEARTHTUBE = "com.thesiegs.hearthtube";
    private static final int MAX_PIN_TRIES = 5;
    private static final long PIN_LOCKOUT_MS = 60_000;

    private int mWrongPins;
    private long mPinLockedUntil;

    /** content://<package>.profile/active (debug builds have a ".debug" package suffix). */
    static Uri activeUri(Context context) {
        return Uri.parse("content://" + context.getPackageName() + ".profile/active");
    }

    /** Tells apps observing {@link #activeUri} that the profile changed. */
    static void notifyChanged(Context context) {
        context.getContentResolver().notifyChange(activeUri(context), null);
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        Context context = getContext();
        SharedPreferences prefs = flutterPrefs(context);
        File wallpaper = currentWallpaper(context);
        MatrixCursor cursor = new MatrixCursor(COLUMNS, 1);
        cursor.addRow(new Object[]{
                LauncherAccessibilityService.getActiveProfileName(context),
                prefs.getString("flutter.accent_color", null),
                prefs.getString("flutter.time_format", null),
                prefs.getString("flutter.app_language", ""),
                prefs.getString("flutter.device_parent_pin_hash", null) != null ? 1 : 0,
                prefs.getString("flutter.gradient_uuid", null),
                wallpaper != null ? wallpaper.lastModified() : 0});
        cursor.setNotificationUri(context.getContentResolver(), activeUri(context));
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"wallpaper".equals(uri.getLastPathSegment()) || !"r".equals(mode)) {
            throw new FileNotFoundException(uri.toString());
        }

        File wallpaper = currentWallpaper(getContext());

        if (wallpaper == null) {
            throw new FileNotFoundException("No wallpaper picture");
        }

        return ParcelFileDescriptor.open(wallpaper, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (!HEARTHTUBE.equals(getCallingPackage())) {
            return null;
        }

        if ("verify_parent_pin".equals(method)) {
            return verifyParentPin(arg);
        }

        return null;
    }

    private synchronized Bundle verifyParentPin(String pin) {
        Bundle result = new Bundle();
        long now = SystemClock.elapsedRealtime();

        if (now < mPinLockedUntil) {
            result.putBoolean("ok", false);
            result.putInt("wait_seconds", (int) ((mPinLockedUntil - now + 999) / 1000));
            return result;
        }

        String hash = flutterPrefs(getContext()).getString("flutter.device_parent_pin_hash", null);
        boolean ok = hash != null && pin != null && hash.equals(hashPin(pin));

        if (ok) {
            mWrongPins = 0;
        } else if (++mWrongPins >= MAX_PIN_TRIES) {
            mWrongPins = 0;
            mPinLockedUntil = now + PIN_LOCKOUT_MS;
        }

        result.putBoolean("ok", ok);
        return result;
    }

    /** Same hash as SettingsService._hashPin in Dart. */
    private static String hashPin(String pin) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("ltv-parent-pin:" + pin).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : digest) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (Exception e) {
            return null;
        }
    }

    /** The picture Hearth shows right now, picked like WallpaperService._updateWallpaper. Null = the gradient. */
    private static File currentWallpaper(Context context) {
        SharedPreferences prefs = flutterPrefs(context);
        // path_provider's getApplicationDocumentsDirectory()
        File dir = new File(context.getApplicationInfo().dataDir, "app_flutter");
        File bing = new File(dir, "wallpaper_bing");
        File plain = new File(dir, "wallpaper");

        if (prefs.getBoolean("flutter.bing_wallpaper_enabled", false) && bing.exists()) {
            return bing;
        }

        if (prefs.getBoolean("flutter.time_based_wallpaper_enabled", false)) {
            int hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
            File timed = new File(dir, hour >= 6 && hour < 18 ? "wallpaper_day" : "wallpaper_night");
            if (timed.exists()) {
                return timed;
            }
        }

        return plain.exists() ? plain : null;
    }

    // shared_preferences stores Flutter keys in this file with a "flutter." prefix.
    private static SharedPreferences flutterPrefs(Context context) {
        return context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
    }

    @Override
    public String getType(Uri uri) {
        return "vnd.android.cursor.item/vnd." + getContext().getPackageName() + ".profile";
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Read-only");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only");
    }
}
