package com.thesiegs.hearth;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.util.Log;

import java.io.File;
import java.io.FileNotFoundException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Shares Hearth's state with HearthTube: one row at content://<pkg>.profile/active, the wallpaper at
 * .../wallpaper, and a signature-checked "verify_parent_pin" call. The column-by-column contract is
 * docs/provider-contract.md.
 */
public class ProfileProvider extends ContentProvider {
    private static final String TAG = "HearthProvider";
    private static final String[] COLUMNS = {
            "name", "accent_color", "time_format", "app_language", "has_parent_pin", "gradient_uuid", "wallpaper_stamp",
            "date_format", "kids_profile", "screen_time_up", "service_running", "profile_id", "contract_version",
            "profile_ready", "switch_generation", "updates_hearthtube", "wallpaper_kind", "wallpaper_version",
            "wallpaper_brightness", "wallpaper_gradient", "wallpaper_title", "wallpaper_credit",
            "youtube_minutes_left", "schedule_locked", "allowance_message", "allowance_checked_at", "allowance_source"};
    /** docs/provider-contract.md: bumped when a column's meaning changes or one is added or removed. */
    static final int CONTRACT_VERSION = 6;
    // SettingsService.defaultTimeFormat / defaultDateFormat
    private static final String DEFAULT_TIME_FORMAT = "h:mm a";
    private static final String DEFAULT_DATE_FORMAT = "EEE, MMM d";
    private static final int MAX_PIN_TRIES = 5;
    private static final long PIN_LOCKOUT_MS = 60_000;
    // SHA-256 of the certificate HearthTube must be signed with: Hearth's release key, which HearthTube's releases
    // use too. HearthTube's debug builds (and its releases before 32.63+4) are signed with a debug key and get no
    // PIN checks.
    private static final Set<String> TRUSTED_CERTS = new HashSet<>(Arrays.asList(
            "243bf074648ab3bfebb260d129e7c8203b407ca7677507ce93dbe72b02396d4c"));

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
        HearthWallpaper.State wallpaper = HearthWallpaper.current(context);
        Allowance.Values allowance = Allowance.forProfile(context,
                LauncherAccessibilityService.getActiveProfileKey(context), System.currentTimeMillis());
        String[] formats = dateTimeFormats(context);
        return new Object[]{
                LauncherAccessibilityService.getActiveProfileName(context),
                FlutterPrefs.getString(context, "accent_color", null),
                formats[1],
                FlutterPrefs.getString(context, "app_language", ""),
                FlutterPrefs.getString(context, "device_parent_pin_hash", null) != null ? 1 : 0,
                FlutterPrefs.getString(context, "gradient_uuid", null),
                wallpaper.file != null ? wallpaper.file.lastModified() : 0,
                formats[0],
                ProfileUsers.isKids(context) ? 1 : 0,
                LauncherAccessibilityService.isScreenTimeUp() ? 1 : 0,
                LauncherAccessibilityService.isRunning() ? 1 : 0,
                LauncherAccessibilityService.getActiveProfileKey(context),
                CONTRACT_VERSION,
                LauncherAccessibilityService.isProfileReady(context) ? 1 : 0,
                LauncherAccessibilityService.getProfileGeneration(context),
                CompanionApps.updatesHearthTube(context) ? 1 : 0,
                wallpaper.kind,
                wallpaper.version,
                wallpaper.brightness,
                wallpaper.gradient,
                wallpaper.title,
                wallpaper.credit,
                allowance.youtubeMinutesLeft,
                allowance.scheduleLocked ? 1 : 0,
                allowance.message,
                allowance.checkedAt,
                allowance.source};
    }

    static String[] columns() {
        return COLUMNS.clone();
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"wallpaper".equals(uri.getLastPathSegment()) || !"r".equals(mode)) {
            throw new FileNotFoundException(uri.toString());
        }

        // The picture may be a family photo: only HearthTube gets it
        if (!CompanionApps.HEARTHTUBE.equals(getCallingPackage()) || !isTrustedHearthTube(getContext())) {
            throw new FileNotFoundException("Not for " + getCallingPackage());
        }

        // An agent serves its own profile's picture, as Hearth sent it (AgentWallpaper)
        File wallpaper;
        if (AgentService.isAgent(getContext())) {
            AgentWallpaper.Kept kept = AgentWallpaper.kept(getContext());
            wallpaper = kept != null ? kept.picture : null;
        } else {
            wallpaper = HearthWallpaper.current(getContext()).file;
        }

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

        if ("report_playing".equals(method)) {
            // HearthTube played this long for the active profile (its YouTube allowance counts down from it)
            long ms = extras != null ? extras.getLong("ms", 0) : 0;
            if (ms <= 0 || ms > 10 * 60_000) return null;
            if (AgentService.isAgent(getContext())) {
                AgentService.relayPlaying(CompanionApps.HEARTHTUBE, ms);
            } else {
                Context context = getContext();
                String profile = LauncherAccessibilityService.getActiveProfileKey(context);
                UsageToday.addPlaying(context, profile, CompanionApps.HEARTHTUBE, ms, System.currentTimeMillis());
                notifyChanged(context);
            }
            Bundle result = new Bundle();
            result.putBoolean("ok", true);
            return result;
        }

        return null;
    }

    /** HearthTube is signed with one of the trusted certificates, so another app can't pose as it to guess PINs. */
    private static boolean isTrustedHearthTube(Context context) {
        try {
            Signature[] signatures;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                SigningInfo info = context.getPackageManager()
                        .getPackageInfo(CompanionApps.HEARTHTUBE, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo;
                if (info == null || info.hasMultipleSigners()) return false;
                signatures = info.getSigningCertificateHistory();
            } else {
                signatures = context.getPackageManager()
                        .getPackageInfo(CompanionApps.HEARTHTUBE, PackageManager.GET_SIGNATURES).signatures;
            }
            if (signatures == null) return false;
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            for (Signature signature : signatures) {
                if (TRUSTED_CERTS.contains(Hex.of(sha256.digest(signature.toByteArray())))) return true;
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't check HearthTube's signature", e);
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

        String hash = FlutterPrefs.getString(context, "device_parent_pin_hash", null);
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
            return Hex.of(MessageDigest.getInstance("SHA-256")
                    .digest(("ltv-parent-pin:" + pin).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            return null;
        }
    }

    /** {date, time} formats. */
    private static String[] dateTimeFormats(Context context) {
        return new String[]{FlutterPrefs.getString(context, "date_format", DEFAULT_DATE_FORMAT),
                FlutterPrefs.getString(context, "time_format", DEFAULT_TIME_FORMAT)};
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
