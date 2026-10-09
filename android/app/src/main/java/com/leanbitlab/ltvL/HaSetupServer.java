package com.leanbitlab.ltvL;

import android.content.Context;
import android.util.Base64;
import android.util.Log;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
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
        String ip = LocalNet.ipv4Address();
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
            } catch (SocketTimeoutException ignored) {
            } catch (IOException | RuntimeException e) {
                // A malformed request from the network must not take the server (or Hearth) down
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
        if (!LocalNet.isLocal(socket.getInetAddress())) {
            MiniHttp.respond(out, 403, "Forbidden");
            return;
        }
        InputStream in = socket.getInputStream();
        MiniHttp.Request request = MiniHttp.read(in);
        if (request == null) return;
        if (!("/" + mSecret).equals(request.path)) {
            MiniHttp.respond(out, 404, "Not found");
            return;
        }
        if (!"POST".equals(request.method)) {
            MiniHttp.respondHtml(out, formPage(HaConfig.prefs(mContext).getString(HaConfig.URL_KEY, "")));
            return;
        }

        int length = request.contentLength();
        if (length <= 0 || length > MAX_BODY_BYTES) {
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        Map<String, String> fields = MiniHttp.parseForm(new String(MiniHttp.readBody(in, length), StandardCharsets.UTF_8));
        String url = HaConfig.normalizeUrl(fields.getOrDefault("url", ""));
        String token = fields.getOrDefault("token", "").replaceAll("\\s", "");
        if (token.isEmpty() || url == null) {
            MiniHttp.respondHtml(out, formPage(fields.getOrDefault("url", ""))
                    .replace("<!--error-->", "<p class='err'>" + text(R.string.ha_setup_missing) + "</p>"));
            return;
        }
        HaConfig.prefs(mContext).edit().putString(HaConfig.URL_KEY, url).putString(HaConfig.TOKEN_KEY, token).apply();
        mReceived = true;
        synchronized (HaSetupServer.class) {
            sLastReceived = true;
        }
        MiniHttp.respondHtml(out, page(mContext.getString(R.string.ha_setup_sent_title),
                "<p>" + text(R.string.ha_setup_sent_detail) + "</p>"));
    }

    private String formPage(String url) {
        return page(mContext.getString(R.string.ha_setup_title),
                "<!--error--><form method='POST'>"
                        + "<label for='url'>" + text(R.string.ha_setup_address_label) + "</label>"
                        + "<input id='url' name='url' type='url' value='" + escape(url) + "' placeholder='http://192.168.1.10:8123'>"
                        + "<label for='token'>" + text(R.string.ha_setup_token_label) + "</label>"
                        + "<textarea id='token' name='token' rows='5' placeholder='" + text(R.string.ha_setup_token_hint)
                        + "' autofocus></textarea>"
                        + "<button type='submit'>" + text(R.string.ha_setup_send) + "</button></form>"
                        + "<p class='help'>" + text(R.string.ha_setup_help) + "</p>");
    }

    /** A string resource, escaped for the page's HTML. */
    private String text(int id) {
        return escape(mContext.getString(id));
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

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;").replace("\"", "&quot;");
    }
}
