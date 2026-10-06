package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.tv.TvContract;
import android.provider.Settings;
import android.view.KeyEvent;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

/**
 * Remote button remapping, run from the accessibility service (the only place that sees remote keys
 * before apps and the system do). Stored as JSON: {"keyCode": {"short": action, "long": action}},
 * where an action is {"type": ..., "target": ..., "label": ...}. Type "ha" runs a Home Assistant entity (target is
 * its entity ID) through the panel's token.
 */
final class ButtonMapper {
    static final String MAPPINGS_KEY = "button_mappings";
    static final String PRESS_SHORT = "short";
    static final String PRESS_LONG = "long";

    private ButtonMapper() {}

    /** Keys that would leave the TV hard to navigate if remapped. */
    static boolean isRemappable(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_BACK:
            case KeyEvent.KEYCODE_HOME:
            case KeyEvent.KEYCODE_POWER:
            case KeyEvent.KEYCODE_SLEEP:
            case KeyEvent.KEYCODE_WAKEUP:
            case KeyEvent.KEYCODE_UNKNOWN:
                return false;
            default:
                return true;
        }
    }

    static JSONObject load(Context context) {
        String raw = context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE)
                .getString(MAPPINGS_KEY, "{}");
        try {
            return new JSONObject(raw);
        } catch (JSONException e) {
            return new JSONObject();
        }
    }

    static String getJson(Context context) {
        return load(context).toString();
    }

    static void setJson(Context context, String json) throws JSONException {
        // Validate, and drop any key that isn't allowed
        JSONObject parsed = new JSONObject(json);
        Iterator<String> keys = parsed.keys();
        JSONObject cleaned = new JSONObject();
        while (keys.hasNext()) {
            String key = keys.next();
            if (isRemappable(Integer.parseInt(key))) {
                cleaned.put(key, parsed.getJSONObject(key));
            }
        }
        context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE)
                .edit().putString(MAPPINGS_KEY, cleaned.toString()).apply();
    }

    /** {"short": action?, "long": action?} for this key, or null when it isn't remapped. */
    static Map<String, JSONObject> forKey(Context context, int keyCode) {
        JSONObject entry = load(context).optJSONObject(String.valueOf(keyCode));
        if (entry == null) return null;
        Map<String, JSONObject> result = new HashMap<>();
        if (entry.optJSONObject(PRESS_SHORT) != null) result.put(PRESS_SHORT, entry.optJSONObject(PRESS_SHORT));
        if (entry.optJSONObject(PRESS_LONG) != null) result.put(PRESS_LONG, entry.optJSONObject(PRESS_LONG));
        return result.isEmpty() ? null : result;
    }

    static void run(LauncherAccessibilityService service, JSONObject action) {
        String type = action.optString("type");
        String target = action.optString("target");
        Intent intent = null;
        switch (type) {
            case "app": {
                PackageManager pm = service.getPackageManager();
                intent = pm.getLeanbackLaunchIntentForPackage(target);
                if (intent == null) intent = pm.getLaunchIntentForPackage(target);
                break;
            }
            case "input":
                intent = new Intent(Intent.ACTION_VIEW, TvContract.buildChannelUriForPassthroughInput(target));
                break;
            case "profiles":
                intent = new Intent("com.google.android.gms.account.ProfilePickerDelegation")
                        .setClassName(LauncherAccessibilityService.GOOGLE_TV_PACKAGE,
                                LauncherAccessibilityService.GOOGLE_TV_PACKAGE + ".profile.chooser.ProfileChooserActivity");
                break;
            case "home":
                intent = new Intent(service, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                break;
            case "settings":
                intent = new Intent(Settings.ACTION_SETTINGS);
                break;
            case "sleep":
                service.sleepNow();
                return;
            case "ha": {
                // A Home Assistant entity: toggled, or turned on for scenes and scripts
                String haService = HaApi.serviceFor(target.contains(".") ? target.substring(0, target.indexOf('.')) : "");
                if (haService == null) return;
                String[] parts = haService.split("\\.", 2);
                HaApi.EXECUTOR.execute(() -> {
                    try {
                        HaApi.callService(service, parts[0], parts[1], new JSONObject().put("entity_id", target));
                    } catch (JSONException ignored) {
                    }
                });
                return;
            }
            default:
                return;
        }
        if (intent == null) return;
        try {
            service.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception ignored) {
        }
    }

    static String keyName(int keyCode) {
        return KeyEvent.keyCodeToString(keyCode);
    }
}
