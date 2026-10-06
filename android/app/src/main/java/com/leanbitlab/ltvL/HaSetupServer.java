package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Hands the Home Assistant address and access token to the TV from a phone, so nobody types a 180-character token
 * with a remote. While Settings shows its QR code, this serves a small form at a one-time secret link on the home
 * network; the phone opens it, pastes the token and sends it. Idea and flow from QuickBars for Home Assistant
 * (github.com/Trooped/QuickBars, GPL-3.0), with the secret link added so nothing else on the network can push a
 * token in the meantime. Stops after one successful send, when Settings closes it, or after ten minutes.
 */
final class HaSetupServer {
    private static final String TAG = "HearthHaSetup";
    private static final int[] PORTS = {8765, 8766, 8767, 8768, 8769};
    private static final int MAX_BODY_BYTES = 16 * 1024;
    private static final long LIFETIME_MS = 10 * 60 * 1000;

    private static HaSetupServer sCurrent;
    private static boolean sLastReceived;

    private final Context mContext;
    private final String mSecret;
    private ServerSocket mServerSocket;
    private volatile boolean mReceived;
    private long mStartedAt;

    private HaSetupServer(Context context) {
        mContext = context.getApplicationContext();
        byte[] bytes = new byte[16];
        new SecureRandom().nextBytes(bytes);
        mSecret = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
    }

    /** Starts a fresh server (replacing any running one) and returns the link for the QR code, or null. */
    static synchronized String start(Context context) {
        stop();
        String ip = localIpv4();
        if (ip == null) return null;
        HaSetupServer server = new HaSetupServer(context);
        for (int port : PORTS) {
            try {
                server.mServerSocket = new ServerSocket(port);
                break;
            } catch (IOException ignored) {
            }
        }
        if (server.mServerSocket == null) return null;
        server.mStartedAt = System.currentTimeMillis();
        sLastReceived = false;
        Thread thread = new Thread(server::run, "HearthHaSetup");
        thread.setDaemon(true);
        thread.start();
        sCurrent = server;
        return "http://" + ip + ":" + server.mServerSocket.getLocalPort() + "/" + server.mSecret;
    }

    static synchronized void stop() {
        if (sCurrent != null) {
            try {
                sCurrent.mServerSocket.close();
            } catch (IOException ignored) {
            }
            sCurrent = null;
        }
    }

    /** True once a phone has sent a token through the current (or just-finished) server. */
    static synchronized boolean received() {
        return sLastReceived;
    }

    private void run() {
        ServerSocket server = mServerSocket;
        try {
            server.setSoTimeout(30_000);
        } catch (IOException ignored) {
        }
        while (!server.isClosed() && !mReceived && System.currentTimeMillis() - mStartedAt < LIFETIME_MS) {
            try (Socket socket = server.accept()) {
                socket.setSoTimeout(10_000);
                handle(socket);
            } catch (java.net.SocketTimeoutException ignored) {
            } catch (IOException e) {
                if (!server.isClosed()) Log.w(TAG, "Request failed", e);
            }
        }
        try {
            server.close();
        } catch (IOException ignored) {
        }
    }

    private void handle(Socket socket) throws IOException {
        OutputStream out = socket.getOutputStream();
        if (!HaNotificationServer.isLocal(socket.getInetAddress())) {
            respond(out, 403, "Forbidden");
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
        String[] parts = requestLine.split(" ");
        if (parts.length < 2 || !("/" + mSecret).equals(parts[1].split("\\?")[0])) {
            respond(out, 404, "Not found");
            return;
        }
        if (!"POST".equals(parts[0])) {
            respondHtml(out, formPage(prefs().getString(HaStatusReporter.URL_KEY, "")));
            return;
        }

        int length = 0;
        try {
            length = Integer.parseInt(headers.getOrDefault("content-length", "0"));
        } catch (NumberFormatException ignored) {
        }
        if (length <= 0 || length > MAX_BODY_BYTES) {
            respond(out, 400, "Bad request");
            return;
        }
        Map<String, String> fields = parseForm(new String(readExactly(in, length), StandardCharsets.UTF_8));
        String url = normalizeUrl(fields.getOrDefault("url", ""));
        String token = fields.getOrDefault("token", "").replaceAll("\\s", "");
        if (token.isEmpty() || url == null) {
            respondHtml(out, formPage(fields.getOrDefault("url", ""))
                    .replace("<!--error-->", "<p class='err'>Enter the Home Assistant address and the token.</p>"));
            return;
        }
        prefs().edit().putString(HaStatusReporter.URL_KEY, url).putString(HaPanelActivity.TOKEN_KEY, token).apply();
        mReceived = true;
        synchronized (HaSetupServer.class) {
            sLastReceived = true;
        }
        respondHtml(out, page("Sent to the TV", "<p>Hearth has the address and token. You can close this page.</p>"));
    }

    /** Adds http:// when the scheme is missing and drops a trailing slash; null when there's nothing usable. */
    static String normalizeUrl(String raw) {
        String url = raw.trim().replaceAll("/+$", "");
        if (url.isEmpty()) return null;
        if (!url.matches("(?i)^https?://.*")) url = "http://" + url;
        return url;
    }

    private SharedPreferences prefs() {
        return mContext.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, Context.MODE_PRIVATE);
    }

    private static String formPage(String url) {
        return page("Connect Hearth to Home Assistant",
                "<!--error--><form method='POST'>"
                        + "<label for='url'>Home Assistant address</label>"
                        + "<input id='url' name='url' type='url' value='" + escape(url) + "' placeholder='http://192.168.1.10:8123'>"
                        + "<label for='token'>Long-lived access token</label>"
                        + "<textarea id='token' name='token' rows='5' placeholder='Paste the token here' autofocus></textarea>"
                        + "<button type='submit'>Send to TV</button></form>"
                        + "<p class='help'>Create the token in Home Assistant while signed in as the user for this TV: "
                        + "profile, Security tab, Long-lived access tokens. It goes straight to the TV over your home "
                        + "network.</p>");
    }

    private static String page(String title, String body) {
        return "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
                + "<title>Hearth</title><style>"
                + "body{font-family:Roboto,Arial,sans-serif;background:#0f0f0f;color:#ddd;margin:0;padding:20px}"
                + ".c{background:#1a1a1a;border:1px solid #333;border-radius:16px;padding:24px;max-width:520px;margin:0 auto}"
                + "h2{color:#fff;margin-top:0}label{display:block;margin:16px 0 6px;color:#bbb}"
                + "input,textarea{width:100%;box-sizing:border-box;padding:12px;font-size:16px;border-radius:8px;"
                + "border:2px solid #444;background:#222;color:#eee}textarea{font-family:monospace;font-size:13px}"
                + "button{margin-top:20px;width:100%;padding:14px;font-size:16px;border:0;border-radius:8px;"
                + "background:#ff7a1a;color:#111;font-weight:600}.help{color:#888;font-size:14px}.err{color:#ff8a80}"
                + "</style></head><body><div class='c'><h2>" + escape(title) + "</h2>" + body + "</div></body></html>";
    }

    private static Map<String, String> parseForm(String body) {
        Map<String, String> fields = new HashMap<>();
        for (String pair : body.split("&")) {
            int eq = pair.indexOf('=');
            if (eq <= 0) continue;
            try {
                fields.put(URLDecoder.decode(pair.substring(0, eq), "UTF-8"), URLDecoder.decode(pair.substring(eq + 1), "UTF-8"));
            } catch (Exception ignored) {
            }
        }
        return fields;
    }

    private static String localIpv4() {
        try {
            for (NetworkInterface nif : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!nif.isUp() || nif.isLoopback()) continue;
                for (InetAddress address : Collections.list(nif.getInetAddresses())) {
                    if (address instanceof Inet4Address && address.isSiteLocalAddress()) return address.getHostAddress();
                }
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;").replace("\"", "&quot;");
    }

    private static void respondHtml(OutputStream out, String html) throws IOException {
        byte[] body = html.getBytes(StandardCharsets.UTF_8);
        out.write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n"
                + "Content-Length: " + body.length + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.ISO_8859_1));
        out.write(body);
        out.flush();
    }

    private static void respond(OutputStream out, int code, String text) throws IOException {
        byte[] body = text.getBytes(StandardCharsets.UTF_8);
        out.write(("HTTP/1.1 " + code + " " + text + "\r\nContent-Type: text/plain\r\nContent-Length: " + body.length
                + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.ISO_8859_1));
        out.write(body);
        out.flush();
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') break;
            if (b != '\r') buffer.write(b);
            if (buffer.size() > 8192) return null;
        }
        if (b == -1 && buffer.size() == 0) return null;
        return buffer.toString("UTF-8");
    }

    private static byte[] readExactly(InputStream in, int length) throws IOException {
        byte[] data = new byte[length];
        int read = 0;
        while (read < length) {
            int n = in.read(data, read, length - read);
            if (n < 0) break;
            read += n;
        }
        return data;
    }
}
