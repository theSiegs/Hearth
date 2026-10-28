package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.provider.Settings;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Collections;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The streaming apps whose PINs Hearth can type, one recipe ({@link PinRecipeSpec}, run by {@link DataPinRecipe})
 * each. An app without a recipe isn't typed for: its saved PINs wait, and Settings says entry isn't supported for it
 * yet. Each recipe comes from research on the app's real PIN screen (a wrong and then the right PIN typed by a parent
 * with research mode on, digits masked). Not here: Paramount+'s profiles (it keeps the profile without a PIN at
 * launch; its account-wide content PIN is ContentPin's, slot "content") and, until its PIN screen is recorded, Hulu.
 *
 * <p>Hearth's own recipes are the asset {@code pin-recipes.json}. A newer copy can come from Hearth's repository
 * ({@code pin-entry/recipes.json} on master, read at most every {@link #REFRESH_MS} while a PIN is saved, like
 * PinSafety's list), so a recipe broken by an app update can be fixed without a Hearth release. A fetched recipe is
 * used instead of Hearth's own only when it's for an app Hearth already has a recipe for, its {@code version} is
 * higher, its engine isn't newer than this Hearth's, it is for the app version installed (when it says), and the
 * whole file passed every check; anything else, and Hearth's own is used. The fetched file can only describe what
 * the built-in engine already does (see PinRecipeSpec). PinSafety's list and switch still turn typing off on top.
 *
 * <p>Thread-safe: what's read is immutable and swapped whole.
 */
final class PinRecipes {
    private static final String TAG = "HearthPins";
    private static final String PREFS = "pin_recipes";
    private static final String BODY_KEY = "fetched";
    private static final String AT_KEY = "fetched_at";
    private static final String URL_KEY = "fetched_url";
    static final String ASSET = "pin-recipes.json";
    static final String URL_DEFAULT = "https://raw.githubusercontent.com/theSiegs/Hearth/master/pin-entry/recipes.json";
    /**
     * For a TV test of recipes not yet on master: {@code adb shell settings put global hearth_pin_recipes_url <url>}.
     * Only a file in Hearth's own repository is taken ({@link #URL_PREFIX}); only adb can write this setting.
     */
    static final String URL_SETTING = "hearth_pin_recipes_url";
    static final String URL_PREFIX = "https://raw.githubusercontent.com/theSiegs/Hearth/";
    static final long REFRESH_MS = PinSafety.REFRESH_MS;
    private static final ExecutorService FETCH = Executors.newSingleThreadExecutor();

    private static final Object LOCK = new Object();
    /** Hearth's own recipes, read once. */
    private static volatile Map<String, PinRecipeSpec> sBuiltIn;
    /** The last fetched file as read: its text and its recipes, swapped whole. */
    private static volatile Fetched sFetched;

    private static final class Fetched {
        final String body;
        final Map<String, PinRecipeSpec> recipes;

        Fetched(String body, Map<String, PinRecipeSpec> recipes) {
            this.body = body;
            this.recipes = recipes;
        }
    }

    private PinRecipes() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // ---- Which recipe ----

    /** A fresh recipe for one profile PIN entry in the app, or null when Hearth can't type its PINs. */
    static PinRecipe forPackage(Context context, String packageName) {
        return recipe(context, PinRecipeSpec.SLOT_PROFILE, packageName);
    }

    static boolean supports(Context context, String packageName) {
        return packageName != null
                && builtIn(context).containsKey(PinRecipeSpec.key(PinRecipeSpec.SLOT_PROFILE, packageName));
    }

    /** A fresh recipe for Paramount+'s content PIN dialog (ContentPin). */
    static PinRecipe contentPin(Context context) {
        return recipe(context, PinRecipeSpec.SLOT_CONTENT, ContentPin.PACKAGE);
    }

    /** A fresh recipe for Google TV's own PIN screen (GooglePinRecipe). */
    static PinRecipe googleTv(Context context) {
        return recipe(context, PinRecipeSpec.SLOT_GOOGLE_TV, LauncherAccessibilityService.GOOGLE_TV_PACKAGE);
    }

    private static PinRecipe recipe(Context context, String slot, String pkg) {
        PinRecipeSpec spec = spec(context, slot, pkg);
        if (spec == null) return null;
        if (spec != builtIn(context).get(spec.key())) {
            Log.i(TAG, "Using the fetched PIN recipe for " + pkg + " (version " + spec.version + ")");
        }
        return new DataPinRecipe(spec);
    }

    /** The recipe that applies now for this app (see {@link #choose}), or null when Hearth has none. */
    static PinRecipeSpec spec(Context context, String slot, String pkg) {
        if (pkg == null) return null;
        String key = PinRecipeSpec.key(slot, pkg);
        PinRecipeSpec builtIn = builtIn(context).get(key);
        if (builtIn == null) return null;
        PinRecipeSpec fetched = fetched(context).get(key);
        return choose(builtIn, fetched, fetched != null ? PinSafety.versionCodeOf(context, pkg) : -1);
    }

    /**
     * The recipe to use: the fetched one when it's for an app Hearth has its own recipe for, newer than Hearth's, and
     * for this version of the app (-1: not known); else Hearth's own (null when Hearth has none: a file adds no app).
     */
    static PinRecipeSpec choose(PinRecipeSpec builtIn, PinRecipeSpec fetched, long appVersionCode) {
        if (builtIn == null) return null;
        if (fetched == null || !fetched.key().equals(builtIn.key())) return builtIn;
        if (fetched.engine > PinRecipeSpec.ENGINE || fetched.version <= builtIn.version) return builtIn;
        return fetched.coversAppVersion(appVersionCode) ? fetched : builtIn;
    }

    /** Hearth's own recipes; none (and an error in the log) if the asset is broken, which a unit test rules out. */
    static Map<String, PinRecipeSpec> builtIn(Context context) {
        Map<String, PinRecipeSpec> recipes = sBuiltIn;
        if (recipes != null) return recipes;
        synchronized (LOCK) {
            if (sBuiltIn != null) return sBuiltIn;
            try (InputStream in = context.getApplicationContext().getAssets().open(ASSET)) {
                recipes = PinRecipeSpec.parseFile(read(in));
            } catch (Exception e) {
                Log.e(TAG, "Hearth's own PIN recipes couldn't be read: " + e.getClass().getSimpleName() + " "
                        + e.getMessage());
                recipes = Collections.emptyMap();
            }
            sBuiltIn = recipes;
            return recipes;
        }
    }

    /** The recipes of the last fetched file that passed every check; none when there's none. */
    static Map<String, PinRecipeSpec> fetched(Context context) {
        String body = prefs(context).getString(BODY_KEY, null);
        if (body == null) return Collections.emptyMap();
        Fetched last = sFetched;
        if (last != null && body.equals(last.body)) return last.recipes;
        Map<String, PinRecipeSpec> recipes;
        try {
            recipes = PinRecipeSpec.parseFile(body);
        } catch (PinRecipeSpec.BadRecipes e) {
            // Checked before it was kept, so only a newer Hearth with stricter rules gets here: Hearth's own then
            recipes = Collections.emptyMap();
        }
        sFetched = new Fetched(body, recipes);
        return recipes;
    }

    // ---- Fetching ----

    /** Where recipes are read from: master, or (for a test) the adb setting if it's a file in Hearth's repository. */
    static String url(Context context) {
        String override = null;
        try {
            override = Settings.Global.getString(context.getContentResolver(), URL_SETTING);
        } catch (Exception e) {
            // Unreadable: master's
            Log.i(TAG, "The PIN recipes address setting couldn't be read: " + e.getClass().getSimpleName());
        }
        return validOverride(override) ? override : URL_DEFAULT;
    }

    static boolean validOverride(String url) {
        if (url == null || !url.startsWith(URL_PREFIX) || !url.endsWith(".json") || url.length() > 300) return false;
        String path = url.substring(URL_PREFIX.length());
        for (int i = 0; i < path.length(); i++) {
            char c = path.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '/'
                    || c == '-' || c == '_' || c == '.';
            if (!ok) return false;
        }
        return !path.contains("..");
    }

    /**
     * Reads the recipes again in the background if they're older than {@link #REFRESH_MS} (or come from another
     * address now). Nothing is sent but the request. Only a file that passes every check is kept; a missing file or
     * one that fails drops the last one, so Hearth's own recipes are used. A network error keeps what's there.
     */
    static void refreshIfDue(Context context) {
        Context app = context.getApplicationContext();
        SharedPreferences prefs = prefs(app);
        String url = url(app);
        long at = prefs.getLong(AT_KEY, 0);
        if (url.equals(prefs.getString(URL_KEY, URL_DEFAULT)) && System.currentTimeMillis() - at < REFRESH_MS) return;
        prefs.edit().putLong(AT_KEY, System.currentTimeMillis()).putString(URL_KEY, url).apply();
        FETCH.execute(() -> {
            HttpURLConnection connection = null;
            try {
                connection = (HttpURLConnection) new URL(url).openConnection();
                connection.setConnectTimeout(10_000);
                connection.setReadTimeout(10_000);
                connection.setInstanceFollowRedirects(false);
                connection.setRequestProperty("User-Agent", "Hearth");
                int code = connection.getResponseCode();
                if (code == HttpURLConnection.HTTP_NOT_FOUND) {
                    prefs.edit().remove(BODY_KEY).apply();
                    return;
                }
                if (code != HttpURLConnection.HTTP_OK) return;
                String body;
                try {
                    body = read(connection.getInputStream());
                    PinRecipeSpec.parseFile(body);
                } catch (PinRecipeSpec.BadRecipes e) {
                    prefs.edit().remove(BODY_KEY).apply();
                    Log.w(TAG, "The fetched PIN recipes were refused (" + e.getMessage() + "); Hearth's own are used");
                    return;
                }
                prefs.edit().putString(BODY_KEY, body).apply();
                Log.i(TAG, "Read the PIN recipes");
            } catch (Exception e) {
                Log.i(TAG, "Couldn't read the PIN recipes: " + e.getClass().getSimpleName());
            } finally {
                if (connection != null) connection.disconnect();
            }
        });
    }

    /** The stream as UTF-8, refused past {@link PinRecipeSpec#MAX_FILE} bytes. */
    static String read(InputStream in) throws Exception {
        try (InputStream stream = in; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int total = 0;
            int n;
            while ((n = stream.read(buffer)) > 0) {
                total += n;
                if (total > PinRecipeSpec.MAX_FILE) throw new PinRecipeSpec.BadRecipes("the file is too long");
                out.write(buffer, 0, n);
            }
            return out.toString("UTF-8");
        }
    }
}
