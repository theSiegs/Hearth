package com.thesiegs.hearth;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.media.tv.TvContract;
import android.net.Uri;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

/**
 * Remote button remapping, run from the accessibility service (the only place that sees remote keys
 * before apps and the system do). Stored as JSON: {"keyCode": {"short": action, "long": action, "homeOnly": bool}},
 * where "homeOnly" leaves the button alone (its normal job) unless Hearth is in front,
 * where an action is {"type": ..., "target": ..., "label": ...}. Type "ha" runs a Home Assistant entity (target is
 * its entity ID) through the panel's token.
 */
final class ButtonMapper {
    private static final String TAG = "HearthButtons";
    private static final String MAPPINGS_KEY = "button_mappings";
    /** The profile button's own mapping was added once (removing it on the Remote buttons page is then kept). */
    private static final String PROFILE_BUTTON_SEEDED_KEY = "profile_button_seeded";
    static final String PRESS_SHORT = "short";
    static final String PRESS_LONG = "long";

    // Parsed once, not on every key event; setJson, the only writer, drops it. Guarded by ButtonMapper.class.
    private static JSONObject sMappings;

    private ButtonMapper() {}

    /** False for keys whose remapping would leave the TV hard to navigate. */
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

    /** The stored mappings. Shared between callers, so only read it. */
    private static synchronized JSONObject load(Context context) {
        if (sMappings != null) return sMappings;
        String raw = context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE)
                .getString(MAPPINGS_KEY, "{}");
        try {
            sMappings = new JSONObject(raw);
        } catch (JSONException e) {
            sMappings = new JSONObject();
        }
        seedProfileButton(context, sMappings);
        return sMappings;
    }

    /**
     * Google TV's profile button only opens its chooser, by way of its own home (it has no hold to lock). Hearth
     * maps it once, as a button anyone can change or restore on the Remote buttons page: a press opens the chooser
     * straight away, a hold locks the profile (see "lock").
     */
    private static void seedProfileButton(Context context, JSONObject mappings) {
        SharedPreferences prefs = context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS,
                Context.MODE_PRIVATE);
        if (prefs.getBoolean(PROFILE_BUTTON_SEEDED_KEY, false)) return;
        SharedPreferences.Editor edit = prefs.edit().putBoolean(PROFILE_BUTTON_SEEDED_KEY, true);
        String key = String.valueOf(KeyEvent.KEYCODE_PROFILE_SWITCH);
        if (!mappings.has(key)) {
            try {
                mappings.put(key, profileButtonDefault());
                edit.putString(MAPPINGS_KEY, mappings.toString());
            } catch (JSONException e) {
                // Never for these values
            }
        }
        edit.apply();
    }

    static JSONObject profileButtonDefault() throws JSONException {
        return new JSONObject()
                .put(PRESS_SHORT, new JSONObject().put("type", "profiles").put("label", "Switch profile"))
                .put(PRESS_LONG, new JSONObject().put("type", "lock").put("label", "Lock my profile"))
                .put("name", KeyEvent.keyCodeToString(KeyEvent.KEYCODE_PROFILE_SWITCH));
    }

    static String getJson(Context context) {
        return load(context).toString();
    }

    static synchronized void setJson(Context context, String json) throws JSONException {
        JSONObject cleaned = cleaned(json);
        context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE)
                .edit().putString(MAPPINGS_KEY, cleaned.toString()).apply();
        sMappings = null;
    }

    /** The mappings Dart sent, validated, without any key that isn't allowed. Throws on JSON that isn't mappings. */
    static JSONObject cleaned(String json) throws JSONException {
        JSONObject parsed = new JSONObject(json);
        Iterator<String> keys = parsed.keys();
        JSONObject cleaned = new JSONObject();
        while (keys.hasNext()) {
            String key = keys.next();
            if (isRemappable(Integer.parseInt(key))) {
                cleaned.put(key, parsed.getJSONObject(key));
            }
        }
        return cleaned;
    }

    /** The button is remapped only on Hearth's own screens; elsewhere (in an app) it does its normal job. */
    static boolean homeOnly(Context context, int keyCode) {
        JSONObject entry = load(context).optJSONObject(String.valueOf(keyCode));
        return entry != null && entry.optBoolean("homeOnly", false);
    }

    /** {"short": action?, "long": action?} for this key, or null when it isn't remapped. */
    static Map<String, JSONObject> forKey(Context context, int keyCode) {
        return actions(load(context).optJSONObject(String.valueOf(keyCode)));
    }

    /** A stored entry's press actions, or null when it has none. */
    static Map<String, JSONObject> actions(JSONObject entry) {
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
                // Its group's time is up today for this kid (the Hearth integration)
                if (Allowance.holdForTime(service, target)) return;
                // Another profile on: its own copy, in its user
                if (ProfileApps.launch(service, target) != null) return;
                PackageManager pm = service.getPackageManager();
                intent = pm.getLeanbackLaunchIntentForPackage(target);
                if (intent == null) intent = pm.getLaunchIntentForPackage(target);
                break;
            }
            case "input":
                intent = new Intent(Intent.ACTION_VIEW, TvContract.buildChannelUriForPassthroughInput(target));
                break;
            case "profiles":
                intent = LauncherAccessibilityService.profileChooserIntent();
                break;
            case "home":
                intent = new Intent(service, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                break;
            case "settings":
                intent = new Intent(Settings.ACTION_SETTINGS);
                break;
            case "search":
                // In HearthTube, its own search (YouTube's videos; it hands everything else to Google): its voice
                // search link, or its search screen with the keyboard
                if (CompanionApps.HEARTHTUBE.equals(LauncherAccessibilityService.appInFront())) {
                    intent = new Intent(Intent.ACTION_VIEW, Uri.parse("text".equals(target)
                            ? "youtube://search?q=" : "youtube://search?launch=voice"))
                            .setPackage(CompanionApps.HEARTHTUBE);
                    if (intent.resolveActivity(service.getPackageManager()) != null) break;
                }
                // Hearth's search, listening right away (target "voice") or with the keyboard ("text")
                intent = new Intent(service, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        .putExtra(MainActivity.EXTRA_OPEN_SEARCH, "text".equals(target) ? "text" : "voice");
                break;
            case "sleep":
                service.sleepNow();
                return;
            case "lock":
                // Nothing to lock (a kids profile, or one without a Google TV PIN): the chooser, to leave it
                if (ProfileLock.lockNow(service)) return;
                intent = LauncherAccessibilityService.profileChooserIntent();
                break;
            case "assistant": {
                // Google's assistant (Gemini on Google TV): what the mic button does when Hearth doesn't take it
                PackageManager pm = service.getPackageManager();
                for (String assistAction : new String[]{Intent.ACTION_ASSIST, "android.intent.action.VOICE_ASSIST",
                        Intent.ACTION_VOICE_COMMAND}) {
                    Intent candidate = new Intent(assistAction);
                    if (candidate.resolveActivity(pm) != null) {
                        intent = candidate;
                        break;
                    }
                }
                break;
            }
            case "ha": {
                // A Home Assistant entity: toggled, or turned on for scenes and scripts
                String[] parts = haCall(target);
                if (parts == null) return;
                HaApi.EXECUTOR.execute(() -> {
                    try {
                        HaApi.callService(service, parts[0], parts[1], new JSONObject().put("entity_id", target));
                    } catch (JSONException e) {
                        Log.w(TAG, "Couldn't call Home Assistant for " + target, e);
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
        } catch (Exception e) {
            Log.w(TAG, "Couldn't start the mapped action " + type, e);
        }
    }

    /** {domain, service} a button calls for this Home Assistant entity, or null when it can't act on it. */
    static String[] haCall(String entityId) {
        String haService = HaApi.serviceFor(entityId.contains(".") ? entityId.substring(0, entityId.indexOf('.')) : "");
        if (haService == null) return null;
        return haService.split("\\.", 2);
    }

    static String keyName(int keyCode) {
        return KeyEvent.keyCodeToString(keyCode);
    }
}
