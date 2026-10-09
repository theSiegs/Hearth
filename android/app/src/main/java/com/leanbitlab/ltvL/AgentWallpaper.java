package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.util.Base64;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;

/**
 * A profile's own wallpaper for HearthTube in that profile's user (docs/design/wallpaper-sync.md). Hearth (owner's
 * user) sends the wallpaper of the profile whose settings are in place to that profile's agent only, a picture as a
 * JPEG no bigger than the screen; the agent keeps it and its provider answers /active and /wallpaper with it, as
 * Hearth's own does.
 *
 * <p>Over the agent channel (one JSON line, see {@link AgentHub}): {"type":"wallpaper","profile":"user:11",
 * "kind":…,"version":n,"brightness":…,"gradient":…,"title":…,"credit":…,"image":"base64 JPEG"}, the provider's
 * wallpaper columns as Hearth has them; "image" only when the agent doesn't have this version's picture yet.
 */
final class AgentWallpaper {
    private static final String TAG = "HearthAgent";
    static final int WIDTH = 1920;
    static final int HEIGHT = 1080;
    /** The most a picture may take over the channel, encoded. */
    static final int MAX_IMAGE_BYTES = 3 * 1024 * 1024;
    private static final int MAX_IMAGE_CHARS = (MAX_IMAGE_BYTES + 2) / 3 * 4;

    // The agent's copy
    private static final String PREFS = "ltv_agent_wallpaper";
    private static final String STATE = "state";
    private static final String IMAGE_VERSION = "image_version";
    private static final String PICTURE = "hearth_wallpaper.jpg";

    private AgentWallpaper() {}

    // ---- Hearth, in the owner's user

    /**
     * The message for the agent of the profile with this serial: null unless the wallpaper in place is that
     * profile's own (only a profile's own wallpaper goes to its user). The picture goes along when the agent doesn't
     * have this version of it ({@code versionThere}).
     */
    static JSONObject message(Context context, long serial, long versionThere) throws JSONException {
        HearthWallpaper.State state = HearthWallpaper.current(context);
        String profile = ProfileUsers.key(serial);
        if (profile == null || !profile.equals(state.profile)) return null;
        JSONObject message = new JSONObject()
                .put("type", "wallpaper")
                .put("profile", profile)
                .put("kind", state.kind)
                .put("version", state.version)
                .put("brightness", state.brightness)
                .put("gradient", state.gradient)
                .put("title", state.title)
                .put("credit", state.credit);
        if (!HearthWallpaper.KIND_GRADIENT.equals(state.kind) && state.file != null && state.version != versionThere) {
            // When it can't be made smaller than the limit the agent shows the gradient (shownKind)
            byte[] jpeg = encode(state.file);
            if (jpeg != null) message.put("image", Base64.encodeToString(jpeg, Base64.NO_WRAP));
        }
        return message;
    }

    /** The picture as the screen shows it (center-cropped to 1920x1080 at most), as a JPEG; null when it can't be. */
    static byte[] encode(File file) {
        Bitmap sampled = null;
        Bitmap scaled = null;
        Bitmap cropped = null;
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getPath(), bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;
            int degrees = rotation(file);
            boolean sideways = degrees == 90 || degrees == 270;
            int w = sideways ? bounds.outHeight : bounds.outWidth;
            int h = sideways ? bounds.outWidth : bounds.outHeight;
            int[] cover = cover(w, h, WIDTH, HEIGHT);

            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = sampleSize(w, h, cover[0], cover[1]);
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            sampled = BitmapFactory.decodeFile(file.getPath(), options);
            if (sampled == null) return null;
            int sw = sideways ? sampled.getHeight() : sampled.getWidth();
            int sh = sideways ? sampled.getWidth() : sampled.getHeight();
            Matrix matrix = new Matrix();
            matrix.postRotate(degrees);
            matrix.postScale(cover[0] / (float) sw, cover[1] / (float) sh);
            scaled = Bitmap.createBitmap(sampled, 0, 0, sampled.getWidth(), sampled.getHeight(), matrix, true);
            int cw = Math.min(cover[4], scaled.getWidth());
            int ch = Math.min(cover[5], scaled.getHeight());
            cropped = Bitmap.createBitmap(scaled, (scaled.getWidth() - cw) / 2, (scaled.getHeight() - ch) / 2, cw, ch);
            for (int quality : new int[]{85, 70}) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                cropped.compress(Bitmap.CompressFormat.JPEG, quality, out);
                if (out.size() <= MAX_IMAGE_BYTES) return out.toByteArray();
            }
            Log.w(TAG, "The wallpaper is too big to send");
            return null;
        } catch (Exception | OutOfMemoryError e) {
            Log.w(TAG, "Couldn't make the wallpaper for the agent: " + e);
            return null;
        } finally {
            if (cropped != null) cropped.recycle();
            if (scaled != null && scaled != cropped) scaled.recycle();
            if (sampled != null && sampled != scaled) sampled.recycle();
        }
    }

    /** How far the picture's EXIF says to turn it (Flutter shows it turned). */
    private static int rotation(File file) {
        try {
            switch (new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL)) {
                case ExifInterface.ORIENTATION_ROTATE_90:
                    return 90;
                case ExifInterface.ORIENTATION_ROTATE_180:
                    return 180;
                case ExifInterface.ORIENTATION_ROTATE_270:
                    return 270;
                default:
                    return 0;
            }
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * A w x h picture covering a tw x th screen (BoxFit.cover), never enlarged: {scaled width, scaled height, crop x,
     * crop y, crop width, crop height}, the crop being the screen's part of the scaled picture, centered.
     */
    static int[] cover(int w, int h, int tw, int th) {
        double scale = Math.min(1, Math.max(tw / (double) w, th / (double) h));
        int sw = Math.max(1, (int) Math.round(w * scale));
        int sh = Math.max(1, (int) Math.round(h * scale));
        int cw = Math.min(tw, sw);
        int ch = Math.min(th, sh);
        return new int[]{sw, sh, (sw - cw) / 2, (sh - ch) / 2, cw, ch};
    }

    /** The largest power-of-two step that still decodes a w x h picture at least tw x th. */
    static int sampleSize(int w, int h, int tw, int th) {
        int sample = 1;
        while (w / (sample * 2) >= tw && h / (sample * 2) >= th) sample *= 2;
        return sample;
    }

    // ---- The agent, in the profile's user

    /** The picture version the agent has (0: none), which Hearth hears in its hello so it doesn't resend it. */
    static long versionHere(Context context) {
        return picture(context).exists() ? prefs(context).getLong(IMAGE_VERSION, 0) : 0;
    }

    /**
     * Keeps a wallpaper message from Hearth, if it's this profile's ({@code ownProfile}, "user:11"). True when it was.
     */
    static boolean store(Context context, JSONObject message, String ownProfile) {
        if (ownProfile == null || !ownProfile.equals(message.optString("profile"))) {
            Log.w(TAG, "Ignored another profile's wallpaper");
            return false;
        }
        String kind = message.optString("kind", HearthWallpaper.KIND_GRADIENT);
        long version = message.optLong("version");
        SharedPreferences prefs = prefs(context);
        long imageVersion = prefs.getLong(IMAGE_VERSION, 0);
        File picture = picture(context);
        if (HearthWallpaper.KIND_GRADIENT.equals(kind)) {
            // Nothing to keep of a picture no longer shown
            if (picture.exists() && !picture.delete()) Log.w(TAG, "Couldn't delete the old wallpaper");
            imageVersion = 0;
        } else if (message.has("image")) {
            byte[] jpeg = decode(message.optString("image"));
            if (jpeg != null && write(picture, jpeg)) imageVersion = version;
        }
        try {
            JSONObject state = new JSONObject();
            for (String name : new String[]{"kind", "version", "brightness", "gradient", "title", "credit"}) {
                if (!message.isNull(name)) state.put(name, message.opt(name));
            }
            prefs.edit().putString(STATE, state.toString()).putLong(IMAGE_VERSION, imageVersion).apply();
        } catch (JSONException e) {
            return false;
        }
        return true;
    }

    private static byte[] decode(String base64) {
        if (base64 == null || base64.isEmpty() || base64.length() > MAX_IMAGE_CHARS) return null;
        try {
            byte[] bytes = Base64.decode(base64, Base64.NO_WRAP);
            return isJpeg(bytes) ? bytes : null;
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** A JPEG starts with FF D8 FF. */
    static boolean isJpeg(byte[] bytes) {
        return bytes != null && bytes.length > 3 && (bytes[0] & 0xff) == 0xff && (bytes[1] & 0xff) == 0xd8
                && (bytes[2] & 0xff) == 0xff;
    }

    /** Written whole or not at all, so the provider never serves half a picture. */
    private static boolean write(File target, byte[] bytes) {
        File temp = new File(target.getPath() + ".tmp");
        try (FileOutputStream out = new FileOutputStream(temp)) {
            out.write(bytes);
            out.getFD().sync();
        } catch (Exception e) {
            Log.w(TAG, "Couldn't keep the wallpaper: " + e);
            temp.delete();
            return false;
        }
        return temp.renameTo(target);
    }

    /** The wallpaper Hearth last sent this agent; null before the first. */
    static Kept kept(Context context) {
        String saved = prefs(context).getString(STATE, null);
        if (saved == null) return null;
        try {
            JSONObject state = new JSONObject(saved);
            File picture = picture(context);
            long version = state.optLong("version");
            String kind = shownKind(state.optString("kind", HearthWallpaper.KIND_GRADIENT), version,
                    prefs(context).getLong(IMAGE_VERSION, 0), picture.exists());
            boolean asSent = kind.equals(state.optString("kind"));
            return new Kept(kind, version,
                    asSent && !state.isNull("brightness") ? state.optDouble("brightness") : null,
                    state.isNull("gradient") ? null : state.optString("gradient"),
                    asSent && !state.isNull("title") ? state.optString("title") : null,
                    asSent && !state.isNull("credit") ? state.optString("credit") : null,
                    HearthWallpaper.KIND_GRADIENT.equals(kind) ? null : picture);
        } catch (JSONException e) {
            return null;
        }
    }

    /**
     * What the agent shows of a wallpaper: its kind, unless that's a picture this agent doesn't have (not this
     * version's, or none at all, as when it was too big to send), when it's the gradient.
     */
    static String shownKind(String kind, long version, long imageVersion, boolean imageExists) {
        if (HearthWallpaper.KIND_GRADIENT.equals(kind)) return kind;
        return imageExists && imageVersion == version ? kind : HearthWallpaper.KIND_GRADIENT;
    }

    /** The wallpaper the agent's provider shows. */
    static final class Kept {
        final String kind;
        final long version;
        final Double brightness;
        final String gradient;
        final String title;
        final String credit;
        /** The picture, for kinds "picture" and "bing". */
        final File picture;

        Kept(String kind, long version, Double brightness, String gradient, String title, String credit,
                File picture) {
            this.kind = kind;
            this.version = version;
            this.brightness = brightness;
            this.gradient = gradient;
            this.title = title;
            this.credit = credit;
            this.picture = picture;
        }
    }

    private static File picture(Context context) {
        return new File(context.getFilesDir(), PICTURE);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
