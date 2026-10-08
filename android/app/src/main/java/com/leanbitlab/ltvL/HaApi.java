package com.leanbitlab.ltvL;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Home Assistant's REST API, signed in with the Home Assistant panel's long-lived token. Used for remote-button
 * actions, notification buttons and camera pictures. Plain HTTP is only used for addresses on the home network,
 * so the token never crosses the internet unencrypted. Every call blocks: run them off the main thread.
 */
final class HaApi {
    private static final String TAG = "HearthHaApi";
    static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private HaApi() {}

    /** Calls a service, e.g. ("light", "toggle", {"entity_id": "light.kitchen"}). True on success. */
    static boolean callService(Context context, String domain, String service, JSONObject data) {
        byte[] body = (data == null ? new JSONObject() : data).toString().getBytes(StandardCharsets.UTF_8);
        return request(context, "POST", "/api/services/" + domain + "/" + service, body) != null;
    }

    /** A still picture from a camera entity, or null. */
    static byte[] cameraImage(Context context, String entityId) {
        return request(context, "GET", "/api/camera_proxy/" + entityId, null);
    }

    /** [{entity_id, name, domain}] for entities a remote button can act on, sorted by name. */
    static JSONArray actionableEntities(Context context) {
        JSONArray result = new JSONArray();
        byte[] raw = request(context, "GET", "/api/states", null);
        if (raw == null) return result;
        try {
            JSONArray states = new JSONArray(new String(raw, StandardCharsets.UTF_8));
            java.util.List<JSONObject> list = new java.util.ArrayList<>();
            for (int i = 0; i < states.length(); i++) {
                JSONObject state = states.getJSONObject(i);
                String id = state.getString("entity_id");
                String domain = id.substring(0, id.indexOf('.'));
                if (serviceFor(domain) == null) continue;
                String name = state.optJSONObject("attributes") != null
                        ? state.getJSONObject("attributes").optString("friendly_name", id) : id;
                list.add(new JSONObject().put("entity_id", id).put("name", name).put("domain", domain));
            }
            list.sort((a, b) -> a.optString("name").compareToIgnoreCase(b.optString("name")));
            for (JSONObject o : list) result.put(o);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read entities", e);
        }
        return result;
    }

    /** The service a button runs for an entity of this domain: a toggle, or a turn_on for scenes and scripts. */
    static String serviceFor(String domain) {
        switch (domain) {
            case "scene":
            case "script":
                return domain + ".turn_on";
            case "button":
            case "input_button":
                return domain + ".press";
            case "light":
            case "switch":
            case "fan":
            case "input_boolean":
            case "cover":
            case "media_player":
            case "automation":
                return "homeassistant.toggle";
            default:
                return null;
        }
    }

    private static byte[] request(Context context, String method, String path, byte[] body) {
        String base = HaConfig.baseUrl(context);
        String token = HaConfig.token(context);
        if (base == null || token == null) return null;
        HttpURLConnection connection = null;
        try {
            URL url = new URL(base + path);
            if (!LocalNet.allows(url)) {
                Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
                return null;
            }
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(10000);
            connection.setRequestMethod(method);
            connection.setRequestProperty("Authorization", "Bearer " + token);
            if (body != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                try (OutputStream out = connection.getOutputStream()) {
                    out.write(body);
                }
            }
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) {
                Log.w(TAG, method + " " + path + " -> " + code);
                return null;
            }
            try (InputStream in = connection.getInputStream()) {
                ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                byte[] chunk = new byte[16 * 1024];
                int n;
                while ((n = in.read(chunk)) > 0) buffer.write(chunk, 0, n);
                return buffer.toByteArray();
            }
        } catch (IOException e) {
            Log.w(TAG, method + " " + path + " failed: " + e.getMessage());
            return null;
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
