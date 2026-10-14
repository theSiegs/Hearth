package com.thesiegs.hearth;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Shader;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.nio.file.Files;

/**
 * Google TV profile photos, cropped from a screenshot of its profile chooser (Google keeps them out of other
 * apps' reach). One small round PNG per profile name, checked again once a day (at the next chooser visit) so a
 * changed Google photo comes through once Google TV has it.
 *
 * Until the photo has loaded, the chooser shows Google's placeholder (the name's initial on a plain circle). A crop
 * that looks like one never replaces a real photo; with no photo yet it's kept for now, marked provisional, and the
 * profile stays due so the real photo is taken at the next chance.
 */
final class ProfileAvatars {
    private static final String TAG = "HearthAvatars";
    private static final long REFRESH_MS = 24L * 60 * 60_000;
    static final int FAILED = 0;
    static final int UNCHANGED = 1;
    static final int SAVED = 2;
    /** Looked like Google's placeholder: the real photo (or the same placeholder) kept. */
    static final int PLACEHOLDER = 3;
    /** Looked like Google's placeholder, saved (provisional) as there's no photo yet. */
    static final int PLACEHOLDER_SAVED = 4;
    private static final int SIZE = 128;

    private static boolean sLegacyDropped;

    private ProfileAvatars() {
    }

    private static File file(Context context, String name) {
        dropLegacyPhotos(context);
        String safe;
        try {
            safe = URLEncoder.encode(name, "UTF-8");
        } catch (UnsupportedEncodingException e) {
            safe = Integer.toHexString(name.hashCode());
        }
        return new File(new File(context.getFilesDir(), "profile_avatars_v3"), safe + ".png");
    }

    /**
     * Earlier photos could include Google TV's PIN lock badge (v1: any tile; v2: the current account's tile while
     * another tile was selected). Runs once per process.
     */
    private static synchronized void dropLegacyPhotos(Context context) {
        if (sLegacyDropped) return;
        sLegacyDropped = true;
        for (String dir : new String[]{"profile_avatars", "profile_avatars_v2"}) dropDir(new File(context.getFilesDir(), dir));
    }

    private static void dropDir(File old) {
        if (!old.isDirectory()) return;
        File[] files = old.listFiles();
        if (files != null) {
            for (File f : files) {
                //noinspection ResultOfMethodCallIgnored
                f.delete();
            }
        }
        //noinspection ResultOfMethodCallIgnored
        old.delete();
    }

    /** Marks a saved photo that looked like Google's placeholder. */
    private static File provisionalMark(File photo) {
        return new File(photo.getPath() + ".provisional");
    }

    /** No photo yet for this profile, only a placeholder, or it's due a refresh. */
    static boolean isDue(Context context, String name) {
        File f = file(context, name);
        return !f.exists() || provisionalMark(f).exists()
                || System.currentTimeMillis() - f.lastModified() > REFRESH_MS;
    }

    /** The profile's photo as PNG bytes, or null. */
    static byte[] read(Context context, String name) {
        if (name == null) return null;
        File f = file(context, name);
        if (!f.exists()) return null;
        try {
            return Files.readAllBytes(f.toPath());
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read the photo of " + LogNames.of(name), e);
            return null;
        }
    }

    /** When the profile's photo last changed (0: none), so Flutter knows when to reload it. */
    static long modified(Context context, String name) {
        return name == null ? 0 : file(context, name).lastModified();
    }

    /**
     * Crops a round photo out of the screenshot: SAVED when it's new or changed, UNCHANGED (just marked checked),
     * PLACEHOLDER / PLACEHOLDER_SAVED when it looked like Google's placeholder (see the class comment), or FAILED
     * when that part of the screenshot is blank (screen off, not drawn yet).
     */
    static int save(Context context, String name, Bitmap screen, Rect bounds) {
        Rect r = new Rect(bounds);
        if (!r.intersect(0, 0, screen.getWidth(), screen.getHeight()) || r.width() < 16 || r.height() < 16) return FAILED;
        int side = Math.min(r.width(), r.height());
        Bitmap square = Bitmap.createBitmap(screen, r.centerX() - side / 2, r.centerY() - side / 2, side, side);
        if (isBlank(square)) return FAILED;

        Bitmap out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        BitmapShader shader = new BitmapShader(square, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
        Matrix scale = new Matrix();
        scale.setScale((float) SIZE / side, (float) SIZE / side);
        shader.setLocalMatrix(scale);
        paint.setShader(shader);
        new Canvas(out).drawCircle(SIZE / 2f, SIZE / 2f, SIZE / 2f, paint);

        int[] pixels = new int[SIZE * SIZE];
        out.getPixels(pixels, 0, SIZE, 0, 0, SIZE, SIZE);
        boolean placeholder = looksLikePlaceholder(pixels, SIZE);
        File f = file(context, name);
        File mark = provisionalMark(f);
        int action = decide(placeholder, f.exists(), mark.exists(), looksSame(f, out));
        if (action == KEEP) return PLACEHOLDER;
        if (action == TOUCH) {
            f.setLastModified(System.currentTimeMillis());
            //noinspection ResultOfMethodCallIgnored
            mark.delete();
            return UNCHANGED;
        }
        File dir = f.getParentFile();
        if (dir != null && !dir.exists() && !dir.mkdirs()) return FAILED;
        File tmp = new File(f.getPath() + ".tmp");
        try (FileOutputStream stream = new FileOutputStream(tmp)) {
            out.compress(Bitmap.CompressFormat.PNG, 100, stream);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't save the photo of " + LogNames.of(name), e);
            return FAILED;
        }
        try {
            if (placeholder) {
                //noinspection ResultOfMethodCallIgnored
                mark.createNewFile();
            } else {
                //noinspection ResultOfMethodCallIgnored
                mark.delete();
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't mark the photo of " + LogNames.of(name), e);
        }
        if (!tmp.renameTo(f)) return FAILED;
        return placeholder ? PLACEHOLDER_SAVED : SAVED;
    }

    static final int KEEP = 0;
    static final int TOUCH = 1;
    static final int WRITE = 2;

    /**
     * What a new crop does to the saved photo: KEEP it (a placeholder never replaces a real photo, and the same
     * placeholder again changes nothing), TOUCH it (the same real photo: marked checked, and no longer provisional
     * if it was a placeholder that turned out to be the real thing) or WRITE the crop.
     *
     * @param placeholder the crop looks like Google's placeholder
     * @param exists      a photo is saved
     * @param provisional the saved photo looked like a placeholder
     * @param same        the saved photo looks the same as the crop
     */
    static int decide(boolean placeholder, boolean exists, boolean provisional, boolean same) {
        if (placeholder) return exists && (!provisional || same) ? KEEP : WRITE;
        return exists && same ? TOUCH : WRITE;
    }

    /**
     * The crop looks like Google's placeholder, an initial on a plain circle: nearly all of the middle of the circle
     * is one of two colors. A photo, or one of Google's illustrated avatars, has more.
     *
     * @param pixels ARGB, size x size, row by row
     */
    static boolean looksLikePlaceholder(int[] pixels, int size) {
        final int maxBuckets = 8;
        int[] seeds = new int[maxBuckets];
        int[] counts = new int[maxBuckets];
        int buckets = 0;
        int total = 0;
        float center = (size - 1) / 2f;
        float radius = size * 0.42f;
        for (int y = 0; y < size; y += 2) {
            for (int x = 0; x < size; x += 2) {
                float dx = x - center;
                float dy = y - center;
                if (dx * dx + dy * dy > radius * radius) continue;
                int p = pixels[y * size + x];
                total++;
                int i = 0;
                while (i < buckets && distance(seeds[i], p) > 60) i++;
                if (i < buckets) {
                    counts[i]++;
                } else if (buckets < maxBuckets) {
                    seeds[buckets] = p;
                    counts[buckets++] = 1;
                }
            }
        }
        if (total == 0) return false;
        int first = 0;
        int second = 0;
        for (int i = 0; i < buckets; i++) {
            if (counts[i] > first) {
                second = first;
                first = counts[i];
            } else if (counts[i] > second) {
                second = counts[i];
            }
        }
        return (first + second) * 100 >= total * 93;
    }

    private static int distance(int a, int b) {
        return Math.abs(((a >> 16) & 0xff) - ((b >> 16) & 0xff)) + Math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff))
                + Math.abs((a & 0xff) - (b & 0xff));
    }

    /**
     * The saved photo matches the new crop, give or take scaling noise and the chooser's focus glow: compared
     * on a coarse grid of the middle of the circle.
     */
    private static boolean looksSame(File saved, Bitmap fresh) {
        if (!saved.exists()) return false;
        Bitmap old = BitmapFactory.decodeFile(saved.getPath());
        if (old == null || old.getWidth() != fresh.getWidth() || old.getHeight() != fresh.getHeight()) return false;
        int differing = 0;
        int samples = 0;
        for (int y = SIZE / 4; y < SIZE * 3 / 4; y += 4) {
            for (int x = SIZE / 4; x < SIZE * 3 / 4; x += 4) {
                int a = old.getPixel(x, y);
                int b = fresh.getPixel(x, y);
                int delta = Math.abs(((a >> 16) & 0xff) - ((b >> 16) & 0xff)) + Math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff))
                        + Math.abs((a & 0xff) - (b & 0xff));
                if (delta > 60) differing++;
                samples++;
            }
        }
        old.recycle();
        return differing * 10 < samples;
    }

    /** Nearly one color throughout: nothing worth keeping. */
    private static boolean isBlank(Bitmap bitmap) {
        int first = bitmap.getPixel(0, 0);
        int step = Math.max(1, bitmap.getWidth() / 12);
        for (int y = step / 2; y < bitmap.getHeight(); y += step) {
            for (int x = step / 2; x < bitmap.getWidth(); x += step) {
                int p = bitmap.getPixel(x, y);
                if (Math.abs(((p >> 16) & 0xff) - ((first >> 16) & 0xff)) > 24
                        || Math.abs(((p >> 8) & 0xff) - ((first >> 8) & 0xff)) > 24
                        || Math.abs((p & 0xff) - (first & 0xff)) > 24) {
                    return false;
                }
            }
        }
        return true;
    }
}
