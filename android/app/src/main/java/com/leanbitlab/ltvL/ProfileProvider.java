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
 * accent color ("7C4DFF"), time format ("h:mm a") and date format ("EEE, MMM d") as intl/ICU patterns (Hearth's
 * defaults when the user never changed them), app language ("" = the system's), whether a parent PIN is set,
 * the gradient's id and a stamp that changes when the wallpaper picture does (0 = no picture, use the gradient),
 * kids_profile (1 in a Google TV kids profile: one Family Link supervises, whatever apps a parent approved),
 * screen_time_up (1 while Google TV's bedtime / time's up lock is on: its screens, or the kid's approved apps blocked
 * in the kid's own profile user; cleared when they're unblocked or the profile changes; kept across Hearth restarts), service_running (1 while Hearth's accessibility service runs: without it Hearth sees no switches and no
 * screen time, so kids_profile / screen_time_up can't be trusted) and profile_id (the Google TV profile's lasting
 * key, "user:11", set before the name is known and unchanged by renames: what to save per-profile things under);
 * observers are notified when any of these change.
 * None of it is secret: it's all on screen in Hearth. The wallpaper picture itself is at .../wallpaper.
 *
 * One call, for HearthTube only (by package and signing certificate): "verify_parent_pin" checks a PIN without ever
 * handing out the PIN or its hash (5 wrong tries lock it for a minute).
 *
 * The full contract, column by column, is docs/provider-contract.md; contract_version says which one this is.
 */
public class ProfileProvider extends ContentProvider {
    private static final String[] COLUMNS = {
            "name", "accent_color", "time_format", "app_language", "has_parent_pin", "gradient_uuid", "wallpaper_stamp",
            "date_format", "kids_profile", "screen_time_up", "service_running", "profile_id", "contract_version",
            "profile_ready", "switch_generation", "updates_hearthtube"};
    /** docs/provider-contract.md: bumped when a column's meaning changes or one is added or removed. */
    static final int CONTRACT_VERSION = 4;
    // SettingsService.defaultTimeFormat / defaultDateFormat
    private static final String DEFAULT_TIME_FORMAT = "h:mm a";
    private static final String DEFAULT_DATE_FORMAT = "EEE, MMM d";
    private static final int MAX_PIN_TRIES = 5;
    private static final long PIN_LOCKOUT_MS = 60_000;

    // One lockout for every way in (HearthTube here, or a kid's HearthTube through that profile's agent)
    private static int sWrongPins;
    private static long sPinLockedUntil;

    /** content://<package>.profile/active (debug builds have a ".debug" package suffix). */
    static Uri activeUri(Context context) {
        return Uri.parse("content://" + context.getPackageName() + ".profile/active");
    }

    /** Tells apps observing {@link #activeUri} that the profile changed. */
    static void notifyChanged(Context context) {
        context.getContentResolver().notifyChange(activeUri(context), null);
        // And to the agents, whose provider mirrors this one in the other profiles' users
        AgentHub.pushHearthState(context);
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        Context context = getContext();
        MatrixCursor cursor = new MatrixCursor(COLUMNS, 1);
        // In another profile's user Hearth is that profile's agent: it answers with Hearth's own row, as Hearth last
        // sent it (a kid's HearthTube there can't reach Hearth's provider in the owner's user)
        cursor.addRow(AgentService.isAgent(context) ? AgentService.mirroredRow(context) : row(context));
        cursor.setNotificationUri(context.getContentResolver(), activeUri(context));
        return cursor;
    }

    /** The /active row's values, in {@link #COLUMNS} order (as Hearth itself, in the owner's user). */
    static Object[] row(Context context) {
        SharedPreferences prefs = flutterPrefs(context);
        File wallpaper = currentWallpaper(context);
        String[] formats = dateTimeFormats(prefs);
        return new Object[]{
                LauncherAccessibilityService.getActiveProfileName(context),
                prefs.getString("flutter.accent_color", null),
                formats[1],
                prefs.getString("flutter.app_language", ""),
                prefs.getString("flutter.device_parent_pin_hash", null) != null ? 1 : 0,
                prefs.getString("flutter.gradient_uuid", null),
                wallpaper != null ? wallpaper.lastModified() : 0,
                formats[0],
                ProfileUsers.isKids(context) ? 1 : 0,
                LauncherAccessibilityService.isScreenTimeUp() ? 1 : 0,
                LauncherAccessibilityService.isRunning() ? 1 : 0,
                LauncherAccessibilityService.getActiveProfileKey(context),
                CONTRACT_VERSION,
                LauncherAccessibilityService.isProfileReady(context) ? 1 : 0,
                LauncherAccessibilityService.getProfileGeneration(context),
                CompanionApps.updatesHearthTube(context) ? 1 : 0};
    }

    static String[] columns() {
        return COLUMNS.clone();
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
        if (!CompanionApps.HEARTHTUBE.equals(getCallingPackage()) || !isTrustedHearthTube(getContext())) {
            return null;
        }

        if ("verify_parent_pin".equals(method)) {
            // An agent asks Hearth (the PIN lives only there); null when Hearth doesn't answer
            return AgentService.isAgent(getContext()) ? AgentService.verifyPinWithHearth(arg)
                    : verifyParentPin(getContext(), arg);
        }

        return null;
    }

    // SHA-256 of the certificates HearthTube may be signed with: the debug key HearthTube's releases are signed
    // with, and Hearth's release key.
    private static final java.util.Set<String> TRUSTED_CERTS = new java.util.HashSet<>(java.util.Arrays.asList(
            "6748528ff4d17fd57c30b6c5d522c467920d9951ea5d208597f91b66df9a2bfe",
            "0438047b1a5eefe8693cad8f2b57189a418337bbcbd3c7dbdb79d20884beaf6e"));

    /** HearthTube is signed with one of the trusted certificates, so another app can't pose as it to guess PINs. */
    private static boolean isTrustedHearthTube(Context context) {
        try {
            android.content.pm.Signature[] signatures;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                android.content.pm.SigningInfo info = context.getPackageManager()
                        .getPackageInfo(CompanionApps.HEARTHTUBE, android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES).signingInfo;
                if (info == null || info.hasMultipleSigners()) return false;
                signatures = info.getSigningCertificateHistory();
            } else {
                signatures = context.getPackageManager()
                        .getPackageInfo(CompanionApps.HEARTHTUBE, android.content.pm.PackageManager.GET_SIGNATURES).signatures;
            }
            if (signatures == null) return false;
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            for (android.content.pm.Signature signature : signatures) {
                StringBuilder hex = new StringBuilder();
                for (byte b : sha256.digest(signature.toByteArray())) hex.append(String.format("%02x", b));
                if (TRUSTED_CERTS.contains(hex.toString())) return true;
            }
        } catch (Exception ignored) {
        }
        return false;
    }

    /** Checks a PIN against Hearth's parent PIN (in the owner's user), with the shared lockout. */
    static synchronized Bundle verifyParentPin(Context context, String pin) {
        Bundle result = new Bundle();
        long now = SystemClock.elapsedRealtime();

        if (now < sPinLockedUntil) {
            result.putBoolean("ok", false);
            result.putInt("wait_seconds", (int) ((sPinLockedUntil - now + 999) / 1000));
            return result;
        }

        String hash = flutterPrefs(context).getString("flutter.device_parent_pin_hash", null);
        boolean ok = hash != null && pin != null && hash.equals(hashPin(pin));

        if (ok) {
            sWrongPins = 0;
        } else if (++sWrongPins >= MAX_PIN_TRIES) {
            sWrongPins = 0;
            sPinLockedUntil = now + PIN_LOCKOUT_MS;
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

    /** {date, time} formats; the old saved defaults count as never chosen (as in SettingsService). */
    private static String[] dateTimeFormats(SharedPreferences prefs) {
        String date = prefs.getString("flutter.date_format", DEFAULT_DATE_FORMAT);
        String time = prefs.getString("flutter.time_format", DEFAULT_TIME_FORMAT);
        if ("EEEE d".equals(date) && "H:mm".equals(time)) return new String[]{DEFAULT_DATE_FORMAT, DEFAULT_TIME_FORMAT};
        return new String[]{date, time};
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
