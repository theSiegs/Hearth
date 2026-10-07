package com.leanbitlab.ltvL;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Shader;

import java.io.File;
import java.io.FileOutputStream;
import java.net.URLEncoder;
import java.nio.file.Files;

/**
 * Google TV profile photos, cropped from a screenshot of its profile chooser (Google keeps them out of other
 * apps' reach). One small round PNG per profile name, checked again once a day (at the next chooser visit) so a
 * changed Google photo comes through once Google TV has it.
 */
final class ProfileAvatars {
    private static final long REFRESH_MS = 24L * 60 * 60_000;
    static final int FAILED = 0;
    static final int UNCHANGED = 1;
    static final int SAVED = 2;
    private static final int SIZE = 128;

    private ProfileAvatars() {
    }

    private static File file(Context context, String name) {
        String safe;
        try {
            safe = URLEncoder.encode(name, "UTF-8");
        } catch (java.io.UnsupportedEncodingException e) {
            safe = Integer.toHexString(name.hashCode());
        }
        return new File(new File(context.getFilesDir(), "profile_avatars"), safe + ".png");
    }

    /** No photo yet for this profile, or it's due a refresh. */
    static boolean isDue(Context context, String name) {
        File f = file(context, name);
        return !f.exists() || System.currentTimeMillis() - f.lastModified() > REFRESH_MS;
    }

    /** The profile's photo as PNG bytes, or null. */
    static byte[] read(Context context, String name) {
        if (name == null) return null;
        File f = file(context, name);
        if (!f.exists()) return null;
        try {
            return Files.readAllBytes(f.toPath());
        } catch (Exception e) {
            return null;
        }
    }

    /** When the profile's photo last changed (0: none), so Flutter knows when to reload it. */
    static long modified(Context context, String name) {
        return name == null ? 0 : file(context, name).lastModified();
    }

    /**
     * Crops a round photo out of the screenshot: SAVED when it's new or changed, UNCHANGED (just marked checked),
     * or FAILED when that part of the screenshot is blank (screen off, not drawn yet).
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

        File f = file(context, name);
        if (looksSame(f, out)) {
            f.setLastModified(System.currentTimeMillis());
            return UNCHANGED;
        }
        File dir = f.getParentFile();
        if (dir != null && !dir.exists() && !dir.mkdirs()) return FAILED;
        File tmp = new File(f.getPath() + ".tmp");
        try (FileOutputStream stream = new FileOutputStream(tmp)) {
            out.compress(Bitmap.CompressFormat.PNG, 100, stream);
        } catch (Exception e) {
            return FAILED;
        }
        return tmp.renameTo(f) ? SAVED : FAILED;
    }

    /**
     * The saved photo matches the new crop, give or take scaling noise and the chooser's focus glow: compared
     * on a coarse grid of the middle of the circle.
     */
    private static boolean looksSame(File saved, Bitmap fresh) {
        if (!saved.exists()) return false;
        Bitmap old = android.graphics.BitmapFactory.decodeFile(saved.getPath());
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
