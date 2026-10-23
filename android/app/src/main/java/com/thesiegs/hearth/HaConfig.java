package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Where Hearth keeps its Home Assistant settings (the address, the status webhook id and the panel's long-lived
 * token, in the device prefs), read the same way by the status reporter, the REST API and the panel.
 */
final class HaConfig {
    static final String URL_KEY = "ha_base_url";
    static final String WEBHOOK_KEY = "ha_webhook_id";
    /** The token before it was kept encrypted: read once, moved to {@link #TOKEN_SEALED_KEY}, and removed. */
    private static final String TOKEN_KEY = "ha_panel_token";
    private static final String TOKEN_SEALED_KEY = "ha_panel_token_sealed";
    private static final String TOKEN_ALIAS = "hearth_ha_token_v1";

    private HaConfig() {}

    /** Adds http:// when the scheme is missing and drops trailing slashes; null when there's nothing usable. */
    static String normalizeUrl(String raw) {
        if (raw == null) return null;
        String url = raw.trim();
        int end = url.length();
        while (end > 0 && url.charAt(end - 1) == '/') end--;
        url = url.substring(0, end);
        if (url.isEmpty()) return null;
        if (!url.matches("(?i)^https?://.*")) url = "http://" + url;
        return url;
    }

    /** The Home Assistant address, normalized; null when none is set. */
    static String baseUrl(Context context) {
        return normalizeUrl(prefs(context).getString(URL_KEY, null));
    }

    /**
     * The panel's long-lived access token, also used for the REST API; null when none is set. It is kept sealed under a
     * Keystore key; one saved before that is sealed on first read. A sealed token that no longer opens (the key is
     * gone) reads as none, and the parent sets it again.
     */
    static String token(Context context) {
        SharedPreferences prefs = prefs(context);
        String sealed = prefs.getString(TOKEN_SEALED_KEY, null);
        if (sealed != null) {
            String token = SecretBox.openText(SecretBox.keystore(), TOKEN_ALIAS, sealed);
            return token == null || token.isEmpty() ? null : token;
        }
        String legacy = prefs.getString(TOKEN_KEY, null);
        if (legacy == null || legacy.isEmpty()) return null;
        setToken(context, legacy);
        return legacy;
    }

    /** Saves the token sealed (null or empty clears it); false when the Keystore wouldn't seal it, and nothing changes. */
    static boolean setToken(Context context, String token) {
        SharedPreferences.Editor editor = prefs(context).edit();
        if (token == null || token.isEmpty()) {
            editor.remove(TOKEN_SEALED_KEY).remove(TOKEN_KEY).apply();
            return true;
        }
        String sealed = SecretBox.sealText(SecretBox.keystore(), TOKEN_ALIAS, token);
        if (sealed == null) return false;
        editor.putString(TOKEN_SEALED_KEY, sealed).remove(TOKEN_KEY).apply();
        return true;
    }

    /** An address and a token are both set, so the panel and the REST API can sign in. */
    static boolean isConfigured(Context context) {
        return baseUrl(context) != null && token(context) != null;
    }

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }
}
