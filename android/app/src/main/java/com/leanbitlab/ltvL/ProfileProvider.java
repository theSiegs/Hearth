package com.leanbitlab.ltvL;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;

/**
 * Shares the active Google TV profile with other apps, so HearthTube can follow it.
 * Read-only: content://com.leanbitlab.ltvL.profile/active returns one row with
 * the profile name (null when Hearth couldn't tell) and Hearth's accent color ("7C4DFF").
 * Neither is secret: the profile name is on screen in Hearth's top bar.
 */
public class ProfileProvider extends ContentProvider {
    private static final String[] COLUMNS = {"name", "accent_color"};

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
        MatrixCursor cursor = new MatrixCursor(COLUMNS, 1);
        // shared_preferences stores Flutter keys in this file with a "flutter." prefix.
        String accent = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.accent_color", null);
        cursor.addRow(new Object[]{LauncherAccessibilityService.getActiveProfileName(context), accent});
        cursor.setNotificationUri(context.getContentResolver(), activeUri(context));
        return cursor;
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
