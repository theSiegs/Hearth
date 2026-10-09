package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Calendar;
import java.util.Map;
import java.util.function.Predicate;

/**
 * Hearth's wallpaper as the provider shares it with HearthTube (docs/design/wallpaper-sync.md). Android picks the
 * picture file itself, the way WallpaperService._updateWallpaper does, so it's right even when Flutter isn't running;
 * what only Flutter knows (how bright it is, the gradient's colors, the Bing photo's title and credit) comes from the
 * last state WallpaperService sent ({@link #save}).
 */
final class HearthWallpaper {
    static final String KIND_PICTURE = "picture";
    static final String KIND_BING = "bing";
    static final String KIND_GRADIENT = "gradient";

    /** Bing's photo of the day: everyone's, in the documents folder itself. */
    static final String BING = "wallpaper_bing";
    // A profile's own pictures, in its profileFolder
    private static final String PLAIN = "wallpaper";
    private static final String DAY = "wallpaper_day";
    private static final String NIGHT = "wallpaper_night";
    /**
     * The TV owner's profile key (WallpaperService.ownerProfileKey): whose pictures show before Hearth has seen a
     * profile.
     */
    static final String OWNER_PROFILE = "user:0";
    /** SettingsService.layoutOwnerKey: the profile whose settings (and so whose pictures) are in place. */
    private static final String LAYOUT_OWNER = "device_layout_owner";

    private static final String PREFS = "hearth_wallpaper";
    private static final String FILE = "file";
    private static final String BRIGHTNESS = "brightness";
    private static final String GRADIENT_UUID = "gradient_uuid";
    private static final String GRADIENT = "gradient";
    private static final String GRADIENT_BRIGHTNESS = "gradient_brightness";
    private static final String BING_TITLE = "bing_title";
    private static final String BING_CREDIT = "bing_credit";

    private HearthWallpaper() {}

    /** What the provider shows of the wallpaper, in one read. */
    static final class State {
        /** The profile this is the wallpaper of (its key, "user:11"). */
        final String profile;
        final File file;
        final String kind;
        final long version;
        final Double brightness;
        final String gradient;
        final String title;
        final String credit;

        State(String profile, File file, String kind, long version, Double brightness, String gradient, String title,
                String credit) {
            this.profile = profile;
            this.file = file;
            this.kind = kind;
            this.version = version;
            this.brightness = brightness;
            this.gradient = gradient;
            this.title = title;
            this.credit = credit;
        }
    }

    /** WallpaperService's latest state (the setWallpaperState channel call): kept, and HearthTube told. */
    static void save(Context context, Map<String, Object> state) {
        if (state == null) return;
        SharedPreferences.Editor editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear();
        putString(editor, FILE, state.get(FILE));
        putString(editor, GRADIENT_UUID, state.get(GRADIENT_UUID));
        putString(editor, GRADIENT, state.get(GRADIENT));
        putString(editor, BING_TITLE, state.get(BING_TITLE));
        putString(editor, BING_CREDIT, state.get(BING_CREDIT));
        putNumber(editor, BRIGHTNESS, state.get(BRIGHTNESS));
        putNumber(editor, GRADIENT_BRIGHTNESS, state.get(GRADIENT_BRIGHTNESS));
        editor.apply();  // in memory at once, so the provider reads it right after the notification
        ProfileProvider.notifyChanged(context);
    }

    private static void putString(SharedPreferences.Editor editor, String key, Object value) {
        if (value instanceof String) editor.putString(key, (String) value);
    }

    private static void putNumber(SharedPreferences.Editor editor, String key, Object value) {
        // As text: SharedPreferences has no double
        if (value instanceof Number) editor.putString(key, String.valueOf(((Number) value).doubleValue()));
    }

    /** The wallpaper Hearth shows right now (as Hearth itself, in the owner's user). */
    static State current(Context context) {
        // path_provider's getApplicationDocumentsDirectory()
        File dir = new File(context.getApplicationInfo().dataDir, "app_flutter");
        String profile = FlutterPrefs.getString(context, LAYOUT_OWNER, null);
        if (profile == null) profile = OWNER_PROFILE;
        String name = pick(FlutterPrefs.getBoolean(context, "bing_wallpaper_enabled", false),
                FlutterPrefs.getBoolean(context, "time_based_wallpaper_enabled", false),
                Calendar.getInstance().get(Calendar.HOUR_OF_DAY), profileFolder(profile),
                n -> new File(dir, n).exists());
        File file = name != null ? new File(dir, name) : null;
        String kind = kindOf(name);
        String gradientUuid = FlutterPrefs.getString(context, "gradient_uuid", null);

        SharedPreferences sent = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        // The gradient as Flutter last described it, if that's still the chosen one
        boolean sameGradient = equal(gradientUuid, sent.getString(GRADIENT_UUID, null));
        String gradient = sameGradient ? sent.getString(GRADIENT, null) : null;
        Double brightness = brightness(name, sent.getString(FILE, null), number(sent.getString(BRIGHTNESS, null)),
                sameGradient ? number(sent.getString(GRADIENT_BRIGHTNESS, null)) : null);
        boolean bing = KIND_BING.equals(kind);

        return new State(profile, file, kind,
                version(kind, name, file != null ? file.lastModified() : 0, file != null ? file.length() : 0,
                        gradientUuid),
                brightness, gradient,
                bing ? sent.getString(BING_TITLE, null) : null,
                bing ? sent.getString(BING_CREDIT, null) : null);
    }

    /**
     * The picture file shown (relative to the documents folder), as WallpaperService._updateWallpaper picks it:
     * Bing's when that's on, the profile's day or night one (06:00 to 18:00 is day) when those are on, falling back
     * to its plain one; null for the gradient.
     */
    static String pick(boolean bingEnabled, boolean timeBasedEnabled, int hour, String folder,
            Predicate<String> exists) {
        if (bingEnabled && exists.test(BING)) return BING;
        if (timeBasedEnabled) {
            String timed = folder + "/" + (hour >= 6 && hour < 18 ? DAY : NIGHT);
            if (exists.test(timed)) return timed;
        }
        String plain = folder + "/" + PLAIN;
        return exists.test(plain) ? plain : null;
    }

    /** The documents subfolder with a profile's own pictures, as WallpaperService.profileFolder names it. */
    static String profileFolder(String profileKey) {
        return "wallpapers/" + profileKey.replaceAll("[^A-Za-z0-9_-]", "_");
    }

    static String kindOf(String fileName) {
        if (fileName == null) return KIND_GRADIENT;
        return BING.equals(fileName) ? KIND_BING : KIND_PICTURE;
    }

    /**
     * Changes whenever what's shown does: another file, the same file rewritten (a new pick, a new day's Bing photo),
     * or another gradient. Positive, never 0.
     */
    static long version(String kind, String fileName, long modified, long length, String gradientUuid) {
        String key = kind + "|" + fileName + "|" + modified + "|" + length + "|"
                + (KIND_GRADIENT.equals(kind) ? gradientUuid : "");
        long hash = 0xcbf29ce484222325L;  // FNV-1a, 64 bits
        for (byte b : key.getBytes(StandardCharsets.UTF_8)) {
            hash ^= b & 0xff;
            hash *= 0x100000001b3L;
        }
        hash &= Long.MAX_VALUE;
        return hash == 0 ? 1 : hash;
    }

    /**
     * How bright the shown wallpaper is, 0 to 1: Flutter's measure of the picture if it's of this same file, the
     * gradient's when there's no picture; null when Flutter hasn't measured what's shown yet.
     */
    static Double brightness(String shownFile, String measuredFile, Double pictureBrightness,
            Double gradientBrightness) {
        if (shownFile == null) return gradientBrightness;
        return shownFile.equals(measuredFile) ? pictureBrightness : null;
    }

    private static Double number(String value) {
        if (value == null) return null;
        try {
            return Double.parseDouble(value);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static boolean equal(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }
}
