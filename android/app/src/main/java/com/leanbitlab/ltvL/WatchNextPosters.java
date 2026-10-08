package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;

/**
 * Loads Watch Next poster art for the Continue Watching cards, downscaled so full-size artwork never crosses the
 * Flutter channel.
 *
 * Local artwork (content://, android.resource://, file://) is read directly. Remote artwork is fetched once and kept
 * in a disk cache for 30 days. Remote fetches reveal the TV's IP address, and which titles are on the row, to the
 * artwork host. That is usually the streaming service that published the entry, which already knows. To limit
 * what leaks: no cookies, no referrer, a generic user agent, https only (plain http only for hosts on the local
 * network), and each poster is fetched at most once a month.
 * TODO: fetch remote artwork anonymously, e.g. through a self-hosted image proxy on the home network.
 */
final class WatchNextPosters {
    private static final String TAG = "HearthPosters";
    private static final int MAX_WIDTH = 640;
    private static final int MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024;
    private static final long CACHE_MAX_AGE_MS = 30L * 24 * 60 * 60 * 1000;
    private static final int TIMEOUT_MS = 8000;

    private WatchNextPosters() {}

    static byte[] load(Context context, String uri) {
        if (uri == null || uri.isEmpty()) return null;
        try {
            if (uri.startsWith("https://") || uri.startsWith("http://")) return loadRemote(context, uri);
            byte[] raw = loadLocal(context, uri);
            return raw == null ? null : downscale(raw);
        } catch (Exception e) {
            Log.w(TAG, "Poster unavailable: " + e.getMessage());
            return null;
        }
    }

    /** Drops cached posters that haven't been shown for a month. */
    static void pruneCache(Context context) {
        long cutoff = System.currentTimeMillis() - CACHE_MAX_AGE_MS;
        File[] files = cacheDir(context).listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.lastModified() < cutoff) f.delete();
        }
    }

    private static byte[] loadRemote(Context context, String uri) throws IOException {
        File cached = new File(cacheDir(context), sha1(uri) + ".jpg");
        if (cached.length() > 0) {
            try (InputStream in = new FileInputStream(cached)) {
                byte[] bytes = readAll(in, MAX_DOWNLOAD_BYTES);
                cached.setLastModified(System.currentTimeMillis());
                return bytes;
            } catch (IOException e) {
                cached.delete();
            }
        }

        byte[] raw = download(uri);
        if (raw == null) return null;
        byte[] small = downscale(raw);
        try (FileOutputStream out = new FileOutputStream(cached)) {
            out.write(small);
        } catch (IOException e) {
            cached.delete();
        }
        return small;
    }

    private static byte[] download(String uri) throws IOException {
        String current = uri;
        for (int redirects = 0; redirects < 5; redirects++) {
            URL url = new URL(current);
            if (!allowed(url)) {
                Log.w(TAG, "Skipping poster over plain http from a non-local host");
                return null;
            }
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            try {
                conn.setConnectTimeout(TIMEOUT_MS);
                conn.setReadTimeout(TIMEOUT_MS);
                // Redirects are followed by hand so each hop gets the https check.
                conn.setInstanceFollowRedirects(false);
                conn.setUseCaches(false);
                conn.setRequestProperty("User-Agent", "Mozilla/5.0");
                conn.setRequestProperty("Accept", "image/*");
                int code = conn.getResponseCode();
                if (code >= 300 && code < 400) {
                    String location = conn.getHeaderField("Location");
                    if (location == null || location.isEmpty()) return null;
                    current = new URL(url, location).toString();
                    continue;
                }
                if (code < 200 || code >= 300) return null;
                try (InputStream in = conn.getInputStream()) {
                    return readAll(in, MAX_DOWNLOAD_BYTES);
                }
            } finally {
                conn.disconnect();
            }
        }
        return null;
    }

    private static boolean allowed(URL url) {
        try {
            return LocalNet.allows(url);
        } catch (IOException e) {
            return false;
        }
    }

    private static byte[] loadLocal(Context context, String uri) throws IOException {
        if (uri.startsWith("file://") || uri.startsWith("/")) {
            String path = uri.startsWith("/") ? uri : Uri.parse(uri).getPath();
            File file = path == null ? null : new File(path);
            if (file == null || !file.canRead()) return null;
            try (InputStream in = new FileInputStream(file)) {
                return readAll(in, MAX_DOWNLOAD_BYTES);
            }
        }
        Uri parsed = Uri.parse(uri);
        try (InputStream in = context.getContentResolver().openInputStream(parsed)) {
            if (in != null) return readAll(in, MAX_DOWNLOAD_BYTES);
        } catch (Exception e) {
            if (!uri.startsWith("android.resource://")) throw e;
        }
        return loadResource(context, parsed);
    }

    /** android.resource://package/type/name or android.resource://package/id, read from the publishing app. */
    private static byte[] loadResource(Context context, Uri uri) throws IOException {
        String authority = uri.getAuthority();
        if (authority == null || authority.isEmpty()) return null;
        try {
            Resources res = context.getPackageManager().getResourcesForApplication(authority);
            List<String> segments = uri.getPathSegments();
            int resId = 0;
            if (segments.size() == 1) {
                resId = Integer.parseInt(segments.get(0));
            } else if (segments.size() >= 2) {
                resId = res.getIdentifier(segments.get(1), segments.get(0), authority);
            }
            if (resId == 0) return null;
            try (InputStream in = res.openRawResource(resId)) {
                return readAll(in, MAX_DOWNLOAD_BYTES);
            }
        } catch (Exception e) {
            return null;
        }
    }

    private static byte[] readAll(InputStream in, int limit) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) != -1) {
            out.write(buffer, 0, read);
            if (out.size() > limit) throw new IOException("Poster larger than " + limit + " bytes");
        }
        return out.toByteArray();
    }

    /** Scales to at most MAX_WIDTH px wide as JPEG; returns the input when it can't be decoded or is small. */
    private static byte[] downscale(byte[] raw) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(raw, 0, raw.length, bounds);
            if (bounds.outWidth <= 0 || bounds.outWidth <= MAX_WIDTH) return raw;
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = 1;
            while (bounds.outWidth / (opts.inSampleSize * 2) >= MAX_WIDTH) opts.inSampleSize *= 2;
            Bitmap bmp = BitmapFactory.decodeByteArray(raw, 0, raw.length, opts);
            if (bmp == null) return raw;
            if (bmp.getWidth() > MAX_WIDTH) {
                Bitmap scaled = Bitmap.createScaledBitmap(bmp, MAX_WIDTH,
                        Math.round(bmp.getHeight() * (MAX_WIDTH / (float) bmp.getWidth())), true);
                bmp.recycle();
                bmp = scaled;
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out);
            bmp.recycle();
            return out.toByteArray();
        } catch (Throwable t) {
            return raw;
        }
    }

    private static File cacheDir(Context context) {
        File dir = new File(context.getCacheDir(), "posters");
        if (!dir.exists()) dir.mkdirs();
        return dir;
    }

    private static String sha1(String s) {
        try {
            return Hex.of(MessageDigest.getInstance("SHA-1").digest(s.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            return Integer.toHexString(s.hashCode());
        }
    }
}
