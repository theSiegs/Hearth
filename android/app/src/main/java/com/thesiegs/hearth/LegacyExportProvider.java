package com.thesiegs.hearth;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import java.io.File;
import java.io.FileNotFoundException;

/**
 * The bridge build's hand-over (old app id com.leanbitlab.ltvL): lets the new Hearth (com.thesiegs.hearth) copy this
 * Hearth's data the first time it starts. Enabled only in the bridge build (manifest placeholder legacyExportEnabled).
 *
 * <ul>
 *   <li>{@code content://<this package>.legacyexport/files}: one row per file that moves ({@code path}, {@code size}),
 *       paths relative to the data folder (see {@link LegacyMove#movable}).</li>
 *   <li>{@code content://<this package>.legacyexport/file?path=<path>}: that file, read-only.</li>
 * </ul>
 *
 * Only the new Hearth may ask: the caller must be {@code com.thesiegs.hearth} (or its debug build, from a debug
 * bridge) and signed with this app's own certificate. Anyone else gets a SecurityException.
 */
public class LegacyExportProvider extends ContentProvider {

    @Override
    public boolean onCreate() {
        return true;
    }

    private void checkCaller() {
        String caller = getCallingPackage();
        String allowed = LegacyMove.newPackage(getContext().getPackageName());
        if (caller == null || !caller.equals(allowed)
                || getContext().getPackageManager().checkSignatures(caller, getContext().getPackageName())
                        != PackageManager.SIGNATURE_MATCH) {
            throw new SecurityException("Hearth's data is only handed to the new Hearth");
        }
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        checkCaller();
        if (!"/files".equals(uri.getPath())) return null;
        File dataDir = getContext().getDataDir();
        MatrixCursor cursor = new MatrixCursor(new String[]{"path", "size"});
        for (String path : LegacyMove.movableFiles(dataDir)) {
            cursor.addRow(new Object[]{path, new File(dataDir, path).length()});
        }
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        checkCaller();
        String path = uri.getQueryParameter("path");
        if (!"/file".equals(uri.getPath()) || !"r".equals(mode) || !LegacyMove.movable(path)) {
            throw new FileNotFoundException("not handed over");
        }
        File file = new File(getContext().getDataDir(), path);
        if (!file.isFile()) throw new FileNotFoundException(path);
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException();
    }
}
