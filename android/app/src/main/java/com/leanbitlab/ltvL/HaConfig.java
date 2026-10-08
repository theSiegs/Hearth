package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Where Hearth keeps its Home Assistant settings (the address, the status webhook id and the panel's long-lived
 * token, in the device prefs), read the same way by the status reporter, the REST API and the panel.
 */
final class HaConfig {
    static final String URL_KEY = "ha_base_url";
    static final String WEBHOOK_KEY = "ha_webhook_id";
    static final String TOKEN_KEY = "ha_panel_token";

    private HaConfig() {}

    /** Adds http:// when the scheme is missing and drops trailing slashes; null when there's nothing usable. */
    static String normalizeUrl(String raw) {
        if (raw == null) return null;
        String url = raw.trim().replaceAll("/+$", "");
        if (url.isEmpty()) return null;
        if (!url.matches("(?i)^https?://.*")) url = "http://" + url;
        return url;
    }

    /** The Home Assistant address, normalized; null when none is set. */
    static String baseUrl(Context context) {
        return normalizeUrl(prefs(context).getString(URL_KEY, null));
    }

    /** The panel's long-lived access token, also used for the REST API; null when none is set. */
    static String token(Context context) {
        String token = prefs(context).getString(TOKEN_KEY, null);
        return token == null || token.isEmpty() ? null : token;
    }

    /** An address and a token are both set, so the panel and the REST API can sign in. */
    static boolean isConfigured(Context context) {
        return baseUrl(context) != null && token(context) != null;
    }

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }
}
