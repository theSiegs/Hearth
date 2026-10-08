package com.leanbitlab.ltvL;

import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Receives Home Assistant's "Notifications for Android TV / Fire TV" pushes (the PiPup-style protocol on port
 * 7676): a GET as the connection test, then a POST of multipart/form-data with msg, title, duration, position,
 * bkgcolor, transparency, fontsize, interrupt, and optional "filename" (icon) and "filename2" (image) files.
 * Hearth also takes two fields of its own, which Home Assistant can send with a rest_command:
 * "camera" (a camera entity shown live in the card, picture-in-picture style) and "actions" (a JSON list of
 * up to three buttons, each {"title", "service": "domain.service", "data": {...}}, run with the panel's token).
 * Only accepts connections from the local network.
 */
final class HaNotificationServer {
    static final int PORT = 7676;
    private static final String TAG = "HearthHaNotify";
    private static final int MAX_BODY_BYTES = 10 * 1024 * 1024;

    static final class Notification {
        String title;
        String message;
        int durationSeconds = 5;
        int position = 2; // top-right
        String backgroundColor;
        byte[] icon;
        byte[] image;
        /** A camera entity to show live in the card, or null. */
        String camera;
        /** Buttons, each {"title", "service", "data"}; empty for an ordinary notification. */
        final List<JSONObject> actions = new ArrayList<>();
    }

    interface Listener {
        void onNotification(Notification notification);
    }

    private final Listener mListener;
    private ServerSocket mServerSocket;
    private Thread mThread;

    HaNotificationServer(Listener listener) {
        mListener = listener;
    }

    synchronized void start() {
        if (mThread != null) return;
        mThread = new Thread(this::run, "HearthHaNotify");
        mThread.setDaemon(true);
        mThread.start();
    }

    synchronized void stop() {
        try {
            if (mServerSocket != null) mServerSocket.close();
        } catch (IOException ignored) {
        }
        mServerSocket = null;
        mThread = null;
    }

    private void run() {
        try (ServerSocket server = new ServerSocket(PORT)) {
            synchronized (this) {
                mServerSocket = server;
            }
            while (!server.isClosed()) {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(10_000);
                    handle(socket);
                } catch (IOException | RuntimeException e) {
                    // A malformed request from the network must not take the server (or Hearth) down
                    if (!server.isClosed()) Log.w(TAG, "Request failed", e);
                }
            }
        } catch (IOException e) {
            Log.w(TAG, "Notification server stopped", e);
        }
    }

    private void handle(Socket socket) throws IOException {
        OutputStream out = socket.getOutputStream();
        if (!LocalNet.isLocal(socket.getInetAddress())) {
            MiniHttp.respond(out, 403, "Forbidden");
            return;
        }
        InputStream in = socket.getInputStream();
        MiniHttp.Request request = MiniHttp.read(in);
        if (request == null) return;
        if (!"POST".equals(request.method)) {
            // Home Assistant's connection test
            MiniHttp.respond(out, 200, "Hearth");
            return;
        }

        int length = request.contentLength();
        if (length <= 0 || length > MAX_BODY_BYTES) {
            MiniHttp.respond(out, 400, "Bad Request");
            return;
        }
        byte[] body = MiniHttp.readBody(in, length);
        Notification notification = parse(request.headers.getOrDefault("content-type", ""), body);
        if (notification == null
                || (isBlank(notification.message) && isBlank(notification.title) && isBlank(notification.camera))) {
            MiniHttp.respond(out, 400, "Missing msg");
            return;
        }
        MiniHttp.respond(out, 200, "OK");
        mListener.onNotification(notification);
    }

    static Notification parse(String contentType, byte[] body) {
        Map<String, byte[]> fields = new HashMap<>();
        String lower = contentType.toLowerCase(Locale.ROOT);
        if (lower.startsWith("multipart/form-data")) {
            String boundary = null;
            for (String part : contentType.split(";")) {
                part = part.trim();
                if (part.toLowerCase(Locale.ROOT).startsWith("boundary=")) {
                    boundary = part.substring("boundary=".length()).replace("\"", "");
                }
            }
            if (boundary == null) return null;
            parseMultipart(body, boundary, fields);
        } else {
            // application/x-www-form-urlencoded, handy for curl tests
            for (Map.Entry<String, String> field : MiniHttp.parseForm(new String(body, StandardCharsets.UTF_8)).entrySet()) {
                fields.put(field.getKey(), field.getValue().getBytes(StandardCharsets.UTF_8));
            }
        }

        Notification n = new Notification();
        n.title = text(fields, "title");
        n.message = text(fields, "msg");
        n.durationSeconds = clamp(intValue(fields, "duration", 5), 1, 120);
        n.position = clamp(intValue(fields, "position", 2), 0, 4);
        n.backgroundColor = text(fields, "bkgcolor");
        n.icon = fields.get("filename");
        n.image = fields.get("filename2");
        n.camera = text(fields, "camera");
        if (n.camera != null && !n.camera.matches("camera\\.[a-z0-9_]+")) n.camera = null;
        String actions = text(fields, "actions");
        if (actions != null && !actions.isEmpty()) {
            try {
                JSONArray list = new JSONArray(actions);
                for (int i = 0; i < list.length() && n.actions.size() < 3; i++) {
                    JSONObject action = list.getJSONObject(i);
                    if (!isBlank(action.optString("title")) && action.optString("service").matches("[a-z_]+\\.[a-z0-9_]+")) {
                        n.actions.add(action);
                    }
                }
            } catch (JSONException e) {
                Log.w(TAG, "Ignoring the notification's actions: not a JSON list of buttons", e);
            }
        }
        return n;
    }

    private static void parseMultipart(byte[] body, String boundary, Map<String, byte[]> fields) {
        byte[] delimiter = ("--" + boundary).getBytes(StandardCharsets.ISO_8859_1);
        int pos = indexOf(body, delimiter, 0);
        while (pos >= 0) {
            int partStart = pos + delimiter.length;
            if (partStart + 1 < body.length && body[partStart] == '-' && body[partStart + 1] == '-') break;
            partStart += 2; // CRLF
            int headersEnd = indexOf(body, "\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1), partStart);
            if (headersEnd < 0) break;
            String partHeaders = new String(body, partStart, headersEnd - partStart, StandardCharsets.UTF_8);
            int next = indexOf(body, delimiter, headersEnd + 4);
            if (next < 0) break;
            int dataEnd = next - 2; // CRLF before the delimiter
            String name = null;
            for (String header : partHeaders.split("\r\n")) {
                if (header.toLowerCase(Locale.ROOT).startsWith("content-disposition")) {
                    int nameAt = header.indexOf("name=\"");
                    if (nameAt >= 0) {
                        int end = header.indexOf('"', nameAt + 6);
                        if (end >= 0) name = header.substring(nameAt + 6, end);
                    }
                }
            }
            if (name != null && dataEnd >= headersEnd + 4) {
                byte[] value = new byte[dataEnd - (headersEnd + 4)];
                System.arraycopy(body, headersEnd + 4, value, 0, value.length);
                fields.put(name, value);
            }
            pos = next;
        }
    }

    private static int indexOf(byte[] haystack, byte[] needle, int from) {
        outer:
        for (int i = Math.max(from, 0); i <= haystack.length - needle.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) continue outer;
            }
            return i;
        }
        return -1;
    }

    private static String text(Map<String, byte[]> fields, String key) {
        byte[] value = fields.get(key);
        return value == null ? null : new String(value, StandardCharsets.UTF_8).trim();
    }

    private static int intValue(Map<String, byte[]> fields, String key, int fallback) {
        try {
            String value = text(fields, key);
            return value == null || value.isEmpty() ? fallback : (int) Double.parseDouble(value);
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }
}
