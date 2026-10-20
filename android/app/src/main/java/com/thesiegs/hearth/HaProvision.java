package com.thesiegs.hearth;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Sets up "TV status" in Home Assistant for this TV, so a person doesn't have to: the helpers the status goes into,
 * an automation that listens on a webhook with a new random id, and this TV's own settings pointing at it. Uses the
 * Home Assistant token the TV already has, which has to belong to an administrator (Home Assistant refuses the rest
 * of it otherwise; the answer is "not_admin" and nothing is changed here).
 *
 * <p>Safe to run again: helpers that exist are left alone, and an automation that exists keeps its webhook id.
 * The TV's name picks the names (Den TV State, "Den TV - Status from Hearth"), so two TVs never share a webhook.
 */
final class HaProvision {
    private static final String TAG = "HearthHaProvision";
    private static final SecureRandom RANDOM = new SecureRandom();

    static final String DONE = "done";
    static final String NOT_ADMIN = "not_admin";
    static final String NOT_SET_UP = "not_set_up";
    static final String FAILED = "failed";

    private HaProvision() {
    }

    /** One helper this TV's status goes into. */
    static final class Helper {
        final String type;
        final String suffix;
        final String label;
        final String icon;

        Helper(String type, String suffix, String label, String icon) {
            this.type = type;
            this.suffix = suffix;
            this.label = label;
            this.icon = icon;
        }

        String entityId(String slug) {
            return type + "." + slug + "_tv_" + suffix;
        }

        String name(String tv) {
            return tv + " TV " + label;
        }
    }

    static final Helper[] HELPERS = {
            new Helper("input_select", "state", "State", "mdi:television-play"),
            new Helper("input_text", "app", "App", "mdi:application"),
            new Helper("input_text", "media_title", "Media Title", "mdi:movie-open"),
            new Helper("input_text", "media_artist", "Media Artist", "mdi:account-music"),
            new Helper("input_text", "profile", "Profile", "mdi:account-box"),
            new Helper("input_boolean", "kids_profile", "Kids Profile", "mdi:human-child"),
            new Helper("input_boolean", "screen_time_up", "Screen Time Up", "mdi:timer-sand-complete"),
    };

    /** Lower-case letters, digits and underscores from a TV's name; "tv" when nothing is left. */
    static String slug(String name) {
        String slug = name == null ? "" : name.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", "_").replaceAll("^_+|_+$", "");
        if (slug.length() > 30) slug = slug.substring(0, 30).replaceAll("_+$", "");
        return slug.isEmpty() ? "tv" : slug;
    }

    /** A webhook id that can't be guessed: hearth-<slug>-<12 hex>. */
    static String newWebhookId(String slug) {
        byte[] bytes = new byte[6];
        RANDOM.nextBytes(bytes);
        return "hearth-" + slug.replace('_', '-') + "-" + AgentAuth.hex(bytes);
    }

    static String automationId(String slug) {
        return "hearth_status_" + slug;
    }

    /** The automation, in the shape Home Assistant's own editor saves. */
    static JSONObject automation(String tv, String slug, String webhookId) throws Exception {
        JSONArray actions = new JSONArray()
                .put(setValue("input_select.select_option", entity(slug, "input_select", "state"), "option",
                        "{{ trigger.json.state if trigger.json.state in ['off', 'idle', 'paused', 'playing'] else 'idle' }}"))
                .put(setValue("input_text.set_value", entity(slug, "input_text", "app"), "value",
                        "{{ (trigger.json.app or '')[:255] }}"))
                .put(setValue("input_text.set_value", entity(slug, "input_text", "media_title"), "value",
                        "{{ (trigger.json.media_title or '')[:255] }}"))
                .put(setValue("input_text.set_value", entity(slug, "input_text", "media_artist"), "value",
                        "{{ (trigger.json.media_artist or '')[:255] }}"))
                .put(setValue("input_text.set_value", entity(slug, "input_text", "profile"), "value",
                        "{{ (trigger.json.profile or '')[:100] }}"))
                .put(flag("{{ trigger.json.kids_profile == true }}", entity(slug, "input_boolean", "kids_profile")))
                .put(flag("{{ trigger.json.screen_time_up == true }}", entity(slug, "input_boolean", "screen_time_up")));
        return new JSONObject()
                .put("alias", tv + " TV - Status from Hearth")
                .put("description", "Hearth on the " + tv + " TV posts its status (app, now playing, Google TV profile, kids"
                        + " screen time) to this webhook when it changes. Keeps the " + tv + " TV helpers current."
                        + " Made by Hearth; the webhook id is also in Hearth > Settings > Home Assistant > TV status.")
                .put("mode", "queued")
                .put("max", 10)
                .put("max_exceeded", "silent")
                .put("triggers", new JSONArray().put(new JSONObject().put("trigger", "webhook")
                        .put("webhook_id", webhookId)
                        .put("allowed_methods", new JSONArray().put("POST"))
                        .put("local_only", true)))
                .put("actions", actions);
    }

    private static String entity(String slug, String type, String suffix) {
        return type + "." + slug + "_tv_" + suffix;
    }

    private static JSONObject setValue(String action, String entity, String field, String template) throws Exception {
        return new JSONObject().put("action", action)
                .put("target", new JSONObject().put("entity_id", entity))
                .put("data", new JSONObject().put(field, template));
    }

    private static JSONObject flag(String condition, String entity) throws Exception {
        JSONObject target = new JSONObject().put("entity_id", entity);
        return new JSONObject()
                .put("if", new JSONArray().put(condition))
                .put("then", new JSONArray().put(new JSONObject().put("action", "input_boolean.turn_on").put("target", target)))
                .put("else", new JSONArray().put(new JSONObject().put("action", "input_boolean.turn_off").put("target", target)));
    }

    /** The webhook id an existing automation listens on, or null. */
    static String webhookOf(JSONObject automation) {
        JSONArray triggers = automation == null ? null : automation.optJSONArray("triggers");
        for (int i = 0; triggers != null && i < triggers.length(); i++) {
            JSONObject trigger = triggers.optJSONObject(i);
            if (trigger != null && "webhook".equals(trigger.optString("trigger", trigger.optString("platform")))) {
                String id = trigger.optString("webhook_id", "");
                if (!id.isEmpty()) return id;
            }
        }
        return null;
    }

    /** The helper's creation message for the WebSocket API ("input_text/create" and so on). */
    static JSONObject createMessage(Helper helper, String tv) throws Exception {
        JSONObject message = new JSONObject().put("type", helper.type + "/create")
                .put("name", helper.name(tv)).put("icon", helper.icon);
        switch (helper.type) {
            case "input_select":
                message.put("options", new JSONArray().put("off").put("idle").put("paused").put("playing"));
                break;
            case "input_text":
                message.put("min", 0).put("max", "profile".equals(helper.suffix) ? 100 : 255);
                break;
            default:
                break;
        }
        return message;
    }

    /**
     * Does it all for the TV called {@code tv}: {state, helpers (created), webhook (when done)}. Blocks (Home
     * Assistant): run it off the main thread.
     */
    static Map<String, Object> setUp(Context context, String tv) {
        Map<String, Object> out = new HashMap<>();
        if (!HaConfig.isConfigured(context)) {
            out.put("state", NOT_SET_UP);
            return out;
        }
        String name = ShareData.tidy(tv == null ? "" : tv);
        if (name.isEmpty()) name = "Hearth";
        String slug = slug(name);
        HaEvents ha = HaEvents.connect(context);
        if (ha == null) {
            out.put("state", FAILED);
            return out;
        }
        try {
            int created = 0;
            Set<String> have = new HashSet<>();
            for (String type : new String[]{"input_select", "input_text", "input_boolean"}) {
                JSONObject listed = ha.command(new JSONObject().put("type", type + "/list"));
                if (listed == null) {
                    out.put("state", FAILED);
                    return out;
                }
                if (isUnauthorized(listed)) {
                    out.put("state", NOT_ADMIN);
                    return out;
                }
                JSONArray items = listed.optJSONArray("result");
                for (int i = 0; items != null && i < items.length(); i++) {
                    JSONObject item = items.optJSONObject(i);
                    if (item != null) have.add(type + "." + item.optString("id"));
                }
            }
            for (Helper helper : HELPERS) {
                if (have.contains(helper.entityId(slug))) continue;
                JSONObject made = ha.command(createMessage(helper, name));
                if (made == null || !made.optBoolean("success")) {
                    out.put("state", isUnauthorized(made) ? NOT_ADMIN : FAILED);
                    return out;
                }
                created++;
            }
            out.put("helpers", created);

            String path = "/api/config/automation/config/" + automationId(slug);
            String webhook = null;
            HaApi.Response existing = HaApi.exchange(context, "GET", path, null);
            if (existing.code == 401 || existing.code == 403) {
                out.put("state", NOT_ADMIN);
                return out;
            }
            if (existing.ok()) webhook = webhookOf(new JSONObject(new String(existing.body, StandardCharsets.UTF_8)));
            if (webhook == null) {
                webhook = newWebhookId(slug);
                HaApi.Response saved = HaApi.exchange(context, "POST", path,
                        automation(name, slug, webhook).toString().getBytes(StandardCharsets.UTF_8));
                if (saved.code == 401 || saved.code == 403) {
                    out.put("state", NOT_ADMIN);
                    return out;
                }
                if (!saved.ok()) {
                    out.put("state", FAILED);
                    return out;
                }
            }
            String base = HaConfig.baseUrl(context);
            String id = webhook;
            // Reporting starts now; the reporter lives on the main thread
            new Handler(Looper.getMainLooper()).post(() -> LauncherAccessibilityService.setHaStatusConfig(context, base, id));
            out.put("state", DONE);
            out.put("webhook", webhook);
            out.put("automation", name + " TV - Status from Hearth");
            return out;
        } catch (Exception e) {
            Log.w(TAG, "Setting up TV status failed: " + e.getClass().getSimpleName());
            out.put("state", FAILED);
            return out;
        } finally {
            ha.disconnect();
        }
    }

    private static boolean isUnauthorized(JSONObject answer) {
        if (answer == null || answer.optBoolean("success")) return false;
        JSONObject error = answer.optJSONObject("error");
        return error != null && "unauthorized".equals(error.optString("code"));
    }
}
