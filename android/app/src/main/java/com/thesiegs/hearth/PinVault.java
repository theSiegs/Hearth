package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;

import org.json.JSONObject;

import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * The streaming apps' profile PINs the parent saved in Settings, so Profile Pairing can type them (see
 * docs/design/streaming-pin-entry.md). One per (app, app profile): each streaming service keeps its own.
 *
 * Encrypted with AES-256-GCM under a non-exportable Android Keystore key; stored in a prefs file of its own that no
 * backup, layout, provider or agent message includes. A PIN is never returned to Flutter (only its status), never
 * logged, and decrypted only into a char[] the caller wipes.
 */
final class PinVault {
    private static final String TAG = "HearthPins";
    private static final String PREFS = "pin_vault";
    private static final String KEY_ALIAS = "hearth_pin_vault_v1";
    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String PAUSED_PREFIX = "paused|";

    static final String STATUS_NONE = "none";
    static final String STATUS_SAVED = "saved";
    /** The app didn't take it last time; still tried once per launch until changed (see PinEntryMachine). */
    static final String STATUS_REJECTED = "rejected";
    /** Rejected often enough that another try could lock the profile: not tried until changed. */

    private PinVault() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The entry's id: the app, and the app profile's name as the app shows it (case and spacing aside). */
    static String id(String pkg, String appProfile) {
        return pkg + "|" + appProfile.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
    }

    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        if (store.containsAlias(KEY_ALIAS)) return ((KeyStore.SecretKeyEntry) store.getEntry(KEY_ALIAS, null)).getSecretKey();
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE);
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return generator.generateKey();
    }

    /** Saves (or replaces) a PIN of digits only; wipes {@code pin}. A saved PIN starts as accepted. */
    static boolean save(Context context, String pkg, String appProfile, char[] pin) {
        byte[] plain = null;
        try {
            for (char c : pin) {
                if (c < '0' || c > '9') return false;
            }
            ByteBuffer bytes = StandardCharsets.UTF_8.encode(CharBuffer.wrap(pin));
            plain = Arrays.copyOf(bytes.array(), bytes.limit());
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            byte[] sealed = cipher.doFinal(plain);
            JSONObject entry = new JSONObject()
                    .put("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                    .put("ct", Base64.encodeToString(sealed, Base64.NO_WRAP))
                    .put("len", pin.length)
                    .put("savedAt", System.currentTimeMillis())
                    .put("status", STATUS_SAVED)
                    .put("rejections", 0);
            prefs(context).edit().putString(id(pkg, appProfile), entry.toString()).apply();
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Couldn't save a PIN for " + pkg + ": " + e.getClass().getSimpleName());
            return false;
        } finally {
            Arrays.fill(pin, '\0');
            if (plain != null) Arrays.fill(plain, (byte) 0);
        }
    }

    static void remove(Context context, String pkg, String appProfile) {
        prefs(context).edit().remove(id(pkg, appProfile)).apply();
    }

    /** Every PIN of an app (its pairings removed, the app uninstalled). */
    static void removeApp(Context context, String pkg) {
        SharedPreferences.Editor editor = prefs(context).edit();
        for (String k : prefs(context).getAll().keySet()) {
            if (k.startsWith(pkg + "|") || k.equals(PAUSED_PREFIX + pkg) || k.equals(BREAKS_PREFIX + pkg)) {
                editor.remove(k);
            }
        }
        editor.apply();
    }

    /** Every PIN (the parent PIN was removed: nobody can vouch for them any more). */
    static void removeAll(Context context) {
        prefs(context).edit().clear().apply();
    }

    private static JSONObject entry(Context context, String pkg, String appProfile) {
        String raw = prefs(context).getString(id(pkg, appProfile), null);
        if (raw == null) return null;
        try {
            return new JSONObject(raw);
        } catch (Exception e) {
            return null;
        }
    }

    /** For Settings: {status, length, savedAt, rejections}. Never the PIN. */
    static Map<String, Object> status(Context context, String pkg, String appProfile) {
        Map<String, Object> out = new HashMap<>();
        JSONObject e = entry(context, pkg, appProfile);
        out.put("status", e == null ? STATUS_NONE : e.optString("status", STATUS_SAVED));
        out.put("length", e == null ? 0 : e.optInt("len"));
        out.put("savedAt", e == null ? 0L : e.optLong("savedAt"));
        out.put("rejections", e == null ? 0 : e.optInt("rejections"));
        out.put("paused", isPaused(context, pkg));
        return out;
    }

    static boolean has(Context context, String pkg, String appProfile) {
        return entry(context, pkg, appProfile) != null;
    }

    static String statusOf(Context context, String pkg, String appProfile) {
        JSONObject e = entry(context, pkg, appProfile);
        return e == null ? STATUS_NONE : e.optString("status", STATUS_SAVED);
    }

    static int rejections(Context context, String pkg, String appProfile) {
        JSONObject e = entry(context, pkg, appProfile);
        return e == null ? 0 : e.optInt("rejections");
    }

    /** The PIN, for one entry only; the caller wipes it. Null when there's none or it can't be opened. */
    static char[] open(Context context, String pkg, String appProfile) {
        JSONObject e = entry(context, pkg, appProfile);
        if (e == null) return null;
        byte[] plain = null;
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(),
                    new GCMParameterSpec(128, Base64.decode(e.getString("iv"), Base64.NO_WRAP)));
            plain = cipher.doFinal(Base64.decode(e.getString("ct"), Base64.NO_WRAP));
            CharBuffer chars = StandardCharsets.UTF_8.decode(ByteBuffer.wrap(plain));
            char[] out = Arrays.copyOf(chars.array(), chars.limit());
            Arrays.fill(chars.array(), '\0');
            return out;
        } catch (Exception ex) {
            Log.w(TAG, "Couldn't open a PIN for " + pkg + ": " + ex.getClass().getSimpleName());
            return null;
        } finally {
            if (plain != null) Arrays.fill(plain, (byte) 0);
        }
    }

    private static void update(Context context, String pkg, String appProfile, String status, int rejections) {
        JSONObject e = entry(context, pkg, appProfile);
        if (e == null) return;
        try {
            e.put("status", status).put("rejections", rejections);
            prefs(context).edit().putString(id(pkg, appProfile), e.toString()).apply();
        } catch (Exception ignored) {
        }
    }

    static void markAccepted(Context context, String pkg, String appProfile) {
        update(context, pkg, appProfile, STATUS_SAVED, 0);
    }

    /** One more rejection: still tried on the next launch, and Settings says it wasn't accepted. */
    static void markRejected(Context context, String pkg, String appProfile) {
        update(context, pkg, appProfile, STATUS_REJECTED,
                rejections(context, pkg, appProfile) + 1);
    }

    /**
     * PIN entry paused for an app (its PIN screen changed, or entry broke too often) until a Hearth update, which may
     * bring a fixed recipe: the pause is kept with the Hearth version that set it.
     */
    static boolean isPaused(Context context, String pkg) {
        return prefs(context).getLong(PAUSED_PREFIX + pkg, -1) == hearthVersion(context);
    }

    private static long hearthVersion(Context context) {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0).getLongVersionCode();
        } catch (Exception e) {
            return 0;
        }
    }

    private static final String BREAKS_PREFIX = "breaks|";

    /** One more broken entry in a row for the app; returns how many. */
    static int addBreak(Context context, String pkg) {
        int count = prefs(context).getInt(BREAKS_PREFIX + pkg, 0) + 1;
        prefs(context).edit().putInt(BREAKS_PREFIX + pkg, count).apply();
        return count;
    }

    static void resetBreaks(Context context, String pkg) {
        prefs(context).edit().remove(BREAKS_PREFIX + pkg).apply();
    }

    static void setPaused(Context context, String pkg, boolean paused) {
        if (paused) {
            prefs(context).edit().putLong(PAUSED_PREFIX + pkg, hearthVersion(context)).apply();
        } else {
            prefs(context).edit().remove(PAUSED_PREFIX + pkg).apply();
        }
    }
}
