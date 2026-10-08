package com.leanbitlab.ltvL;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
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
    private static final String TAG = "LTvHaNotify";
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
        final java.util.List<org.json.JSONObject> actions = new java.util.ArrayList<>();
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
        mThread = new Thread(this::run, "LTvHaNotify");
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
                } catch (IOException e) {
                    if (!server.isClosed()) Log.w(TAG, "Request failed", e);
                }
            }
        } catch (IOException e) {
            Log.w(TAG, "Notification server stopped", e);
        }
    }

    static boolean isLocal(InetAddress address) {
        return address.isLoopbackAddress() || address.isSiteLocalAddress() || address.isLinkLocalAddress()
                || isUniqueLocalIpv6(address);
    }

    private static boolean isUniqueLocalIpv6(InetAddress address) {
        byte[] bytes = address.getAddress();
        return bytes.length == 16 && (bytes[0] & 0xFE) == 0xFC;
    }

    private void handle(Socket socket) throws IOException {
        if (!isLocal(socket.getInetAddress())) {
            respond(socket.getOutputStream(), 403, "Forbidden");
            return;
        }
        InputStream in = socket.getInputStream();
        String requestLine = readLine(in);
        if (requestLine == null) return;
        Map<String, String> headers = new HashMap<>();
        String line;
        while ((line = readLine(in)) != null && !line.isEmpty()) {
            int colon = line.indexOf(':');
            if (colon > 0) headers.put(line.substring(0, colon).trim().toLowerCase(Locale.ROOT), line.substring(colon + 1).trim());
        }

        String method = requestLine.split(" ")[0];
        if (!"POST".equals(method)) {
            // Home Assistant's connection test
            respond(socket.getOutputStream(), 200, "LTvLauncher");
            return;
        }

        int length = 0;
        try {
            length = Integer.parseInt(headers.getOrDefault("content-length", "0"));
        } catch (NumberFormatException ignored) {
        }
        if (length <= 0 || length > MAX_BODY_BYTES) {
            respond(socket.getOutputStream(), 400, "Bad Request");
            return;
        }
        byte[] body = readExactly(in, length);
        Notification notification = parse(headers.getOrDefault("content-type", ""), body);
        if (notification == null
                || (isBlank(notification.message) && isBlank(notification.title) && isBlank(notification.camera))) {
            respond(socket.getOutputStream(), 400, "Missing msg");
            return;
        }
        respond(socket.getOutputStream(), 200, "OK");
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
            for (String pair : new String(body, StandardCharsets.UTF_8).split("&")) {
                int eq = pair.indexOf('=');
                if (eq <= 0) continue;
                try {
                    fields.put(URLDecoder.decode(pair.substring(0, eq), "UTF-8"),
                            URLDecoder.decode(pair.substring(eq + 1), "UTF-8").getBytes(StandardCharsets.UTF_8));
                } catch (Exception ignored) {
                }
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
                org.json.JSONArray list = new org.json.JSONArray(actions);
                for (int i = 0; i < list.length() && n.actions.size() < 3; i++) {
                    org.json.JSONObject action = list.getJSONObject(i);
                    if (!isBlank(action.optString("title")) && action.optString("service").matches("[a-z_]+\\.[a-z0-9_]+")) {
                        n.actions.add(action);
                    }
                }
            } catch (org.json.JSONException ignored) {
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
                        name = header.substring(nameAt + 6, end);
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

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') break;
            if (b != '\r') line.write(b);
            if (line.size() > 8192) throw new IOException("Header too long");
        }
        if (b == -1 && line.size() == 0) return null;
        return line.toString("UTF-8");
    }

    private static byte[] readExactly(InputStream in, int length) throws IOException {
        byte[] data = new byte[length];
        int read = 0;
        while (read < length) {
            int n = in.read(data, read, length - read);
            if (n < 0) throw new IOException("Body truncated");
            read += n;
        }
        return data;
    }

    private static void respond(OutputStream out, int status, String text) throws IOException {
        byte[] body = text.getBytes(StandardCharsets.UTF_8);
        String reason = status == 200 ? "OK" : status == 403 ? "Forbidden" : "Bad Request";
        out.write(("HTTP/1.1 " + status + " " + reason + "\r\nContent-Type: text/plain\r\nContent-Length: " + body.length
                + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        out.write(body);
        out.flush();
    }
}
