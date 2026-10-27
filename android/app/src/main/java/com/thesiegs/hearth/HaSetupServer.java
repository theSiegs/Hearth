package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

/**
 * Hands the Home Assistant address and access token to the TV from a phone, so nobody types a 180-character token
 * with a remote. While Settings shows its QR code, this serves a small form at a one-time secret link on the home
 * network; the phone opens it, pastes the token and sends it. Idea and flow from QuickBars for Home Assistant
 * (github.com/Trooped/QuickBars, GPL-3.0), with the secret link added so nothing else on the network can push a
 * token in the meantime. The page seals what it sends with a key that's only in the link's #fragment (PhoneSeal), as
 * the PIN page does (PinSetupServer), so the token can't be read on the network. Stops after one successful send,
 * when Settings closes it, or after ten minutes. The same page takes the webhook id for TV status (HaStatusReporter),
 * so that needs no typing on the TV either.
 */
final class HaSetupServer {
    private static final String TAG = "HearthHaSetup";
    private static final int[] PORTS = {8765, 8766, 8767, 8768, 8769};
    private static final int MAX_BODY_BYTES = 16 * 1024;
    private static final long LIFETIME_MS = 10 * 60 * 1000;
    /** What a webhook id may hold: it goes into the URL Hearth posts the TV's status to. */
    private static final java.util.regex.Pattern WEBHOOK_ID = java.util.regex.Pattern.compile("[A-Za-z0-9_-]{1,128}");

    private static HaSetupServer sCurrent;
    private static boolean sLastReceived;

    private final Context mContext;
    private final String mSecret;
    private final String mKey;
    private ServerSocket mServerSocket;
    private volatile boolean mReceived;
    private long mStartedAt;

    private HaSetupServer(Context context) {
        mContext = context.getApplicationContext();
        byte[] bytes = new byte[16];
        new SecureRandom().nextBytes(bytes);
        mSecret = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
        mKey = PhoneSeal.newKey();
    }

    /** Starts a fresh server (replacing any running one) and returns the link for the QR code, or null. */
    static synchronized String start(Context context) {
        stop();
        if (!PhoneSeal.available()) return null;
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
        return "http://" + ip + ":" + server.mServerSocket.getLocalPort() + "/" + server.mSecret + "#" + server.mKey;
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
                if (!server.isClosed()) Log.w(TAG, "Request failed: " + e.getClass().getSimpleName());
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
        String path = "/" + mSecret;
        if (!path.equals(request.path)) {
            MiniHttp.respond(out, 404, "Not found");
            return;
        }
        if (!"POST".equals(request.method)) {
            // Only the address is filled in: the webhook id is a secret, and this page isn't sealed on its way out
            MiniHttp.respondHtml(out, formPage(HaConfig.prefs(mContext).getString(HaConfig.URL_KEY, "")));
            return;
        }

        int length = request.contentLength();
        if (length <= 0 || length > MAX_BODY_BYTES) {
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        String body = new String(MiniHttp.readBody(in, length), StandardCharsets.UTF_8);
        Sent sent;
        try {
            sent = parse(PhoneSeal.open(mKey, path, body));
        } catch (Exception e) {
            Log.i(TAG, "A sent page didn't open: " + e.getClass().getSimpleName());
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        if (sent == null) {
            // It opened, but the address, token or webhook id isn't usable: the page says so
            MiniHttp.respond(out, 422, "Missing");
            return;
        }
        SharedPreferences.Editor edit = HaConfig.prefs(mContext).edit().putString(HaConfig.URL_KEY, sent.url);
        edit.apply();
        if (!sent.token.isEmpty()) HaConfig.setToken(mContext, sent.token);
        // Starts reporting right away when Home Button Fix runs; the reporter lives on the main thread. A new address
        // or token alone posts the status at once too, where it already goes somewhere
        if (sent.webhookOk) {
            new Handler(Looper.getMainLooper())
                    .post(() -> LauncherAccessibilityService.setHaStatusConfig(mContext, sent.url, sent.webhook));
        } else {
            new Handler(Looper.getMainLooper()).post(() -> HaBridgeService.sync(mContext));
        }
        // An administrator's token lets Hearth make the TV status automation itself: nobody has to find a webhook id
        String state = sent.create ? HaProvision.setUp(mContext, ShareDiscovery.deviceName(mContext)).get("state").toString()
                : "saved";
        mReceived = true;
        synchronized (HaSetupServer.class) {
            sLastReceived = true;
        }
        MiniHttp.respond(out, 200, state);
    }

    /** What the phone sent, once it passed the checks in {@link #parse}. */
    static final class Sent {
        final String url;
        final String token;
        final String webhook;
        final boolean webhookOk;
        /** The phone asked Hearth to make the TV status automation (it needs a token, and no webhook id came). */
        final boolean create;

        Sent(String url, String token, String webhook, boolean webhookOk, boolean create) {
            this.url = url;
            this.token = token;
            this.webhook = webhook;
            this.webhookOk = webhookOk;
            this.create = create;
        }
    }

    /**
     * Reads {"url", "token", "webhook", "create"}: the address, and a token or a webhook id (TV status alone needs no
     * token); "create" asks Hearth to make the TV status automation with the token, unless a webhook id came too.
     * Null when there's no address, neither a token nor a webhook id, or a webhook id that isn't one.
     */
    static Sent parse(String json) throws JSONException {
        JSONObject fields = new JSONObject(json);
        String url = HaConfig.normalizeUrl(fields.optString("url", ""));
        String token = fields.optString("token", "").replaceAll("\\s", "");
        String webhook = fields.optString("webhook", "").trim();
        boolean webhookOk = WEBHOOK_ID.matcher(webhook).matches();
        if (url == null || (token.isEmpty() && !webhookOk) || (!webhook.isEmpty() && !webhookOk)) return null;
        boolean create = fields.optBoolean("create", false) && !token.isEmpty() && !webhookOk;
        return new Sent(url, token, webhook, webhookOk, create);
    }

    private String formPage(String url) {
        String form = "<form id='f'>"
                + "<label for='url'>" + text(R.string.ha_setup_address_label) + "</label>"
                + "<input id='url' type='url' value='" + escape(url) + "' placeholder='http://192.168.1.10:8123'>"
                + "<label for='token'>" + text(R.string.ha_setup_token_label) + "</label>"
                + "<textarea id='token' rows='5' placeholder='" + text(R.string.ha_setup_token_hint)
                + "' autofocus></textarea>"
                + "<p class='help'>" + text(R.string.ha_setup_token_help) + "</p>"
                + "<label class='row'><input id='create' type='checkbox' checked> "
                + text(R.string.ha_setup_create_label) + "</label>"
                + "<p class='help'>" + text(R.string.ha_setup_create_help) + "</p>"
                + "<details><summary>" + text(R.string.ha_setup_webhook_label) + "</summary>"
                + "<input id='webhook' autocapitalize='off'>"
                + "<p class='help'>" + text(R.string.ha_setup_webhook_help) + "</p></details>"
                + "<p id='err' class='err'></p>"
                + "<button type='submit'>" + text(R.string.ha_setup_send) + "</button></form>"
                + "<div id='done' hidden><p>" + text(R.string.ha_setup_sent_detail) + "</p><p id='more'></p></div>"
                + "<p class='help'>" + text(R.string.ha_setup_help) + "</p>";
        String script = "<script>" + raw(R.raw.phone_seal) + "</script><script>"
                + "var M={missing:'" + js(R.string.ha_setup_missing) + "',failed:'" + js(R.string.ha_setup_failed)
                + "',old:'" + js(R.string.pin_phone_old_browser) + "',sent:'" + js(R.string.ha_setup_sent_title)
                + "',done:'" + js(R.string.ha_setup_created) + "',admin:'" + js(R.string.ha_setup_not_admin)
                + "',nope:'" + js(R.string.ha_setup_create_failed) + "'};"
                + PAGE_SCRIPT + "</script>";
        return page(mContext.getString(R.string.ha_setup_title), form, script);
    }

    /**
     * Seals {"url", "token", "webhook"} with the key in the link's #fragment and posts it to this page's path; the
     * fragment never leaves the phone. The token is cleared once the TV has it, not before, so a refused send can be
     * fixed and sent again.
     */
    private static final String PAGE_SCRIPT = ""
            + "var f=document.getElementById('f'),err=document.getElementById('err');"
            + "function v(id){return document.getElementById(id).value;}"
            + "if(typeof BigInt==='undefined'||!window.crypto||!crypto.getRandomValues||!location.hash){"
            + "err.textContent=M.old;}"
            + "f.addEventListener('submit',function(e){e.preventDefault();err.textContent='';"
            + "var body;try{body=HearthSeal.sealText(location.hash.substring(1),location.pathname,JSON.stringify("
            + "{url:v('url').trim(),token:v('token').replace(/\\s/g,''),webhook:v('webhook').trim(),"
            + "create:document.getElementById('create').checked}));}"
            + "catch(x){err.textContent=M.old;return;}"
            + "fetch(location.pathname,{method:'POST',headers:{'Content-Type':'text/plain'},body:body})"
            + ".then(function(r){if(r.status===422){err.textContent=M.missing;return null;}if(!r.ok)throw r;"
            + "return r.text();}).then(function(t){if(t===null)return;"
            + "document.getElementById('token').value='';f.hidden=true;document.getElementById('done').hidden=false;"
            + "document.querySelector('h2').textContent=M.sent;"
            + "if(t==='done')document.getElementById('more').textContent=M.done;"
            + "else if(t==='not_admin')document.getElementById('more').textContent=M.admin;"
            + "else if(t==='failed'||t==='not_set_up')document.getElementById('more').textContent=M.nope;})"
            + ".catch(function(){err.textContent=M.failed;});});";

    private String raw(int id) {
        try (InputStream in = mContext.getResources().openRawResource(id)) {
            byte[] buffer = new byte[16 * 1024];
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            int n;
            while ((n = in.read(buffer)) > 0) bytes.write(buffer, 0, n);
            return bytes.toString("UTF-8");
        } catch (IOException e) {
            return "";
        }
    }

    /** A string resource for a single-quoted JavaScript string. */
    private String js(int id) {
        return mContext.getString(id).replace("\\", "\\\\").replace("'", "\\'").replace("<", "\\x3c")
                .replace("\n", " ");
    }

    /** A string resource, escaped for the page's HTML. */
    private String text(int id) {
        return escape(mContext.getString(id));
    }

    private static String page(String title, String body, String script) {
        return "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
                + "<meta name='referrer' content='no-referrer'><title>Hearth</title><style>"
                + "body{font-family:Roboto,Arial,sans-serif;background:#0f0f0f;color:#ddd;margin:0;padding:20px}"
                + ".c{background:#1a1a1a;border:1px solid #333;border-radius:16px;padding:24px;max-width:520px;margin:0 auto}"
                + "h2{color:#fff;margin-top:0}label{display:block;margin:16px 0 6px;color:#bbb}"
                + "input,textarea{width:100%;box-sizing:border-box;padding:12px;font-size:16px;border-radius:8px;"
                + "border:2px solid #444;background:#222;color:#eee}textarea{font-family:monospace;font-size:13px}"
                + "button{margin-top:20px;width:100%;padding:14px;font-size:16px;border:0;border-radius:8px;"
                + "background:#ff7a1a;color:#111;font-weight:600}.help{color:#888;font-size:14px}.err{color:#ff8a80}"
                + "label.row{display:flex;align-items:center;gap:10px;color:#ddd}label.row input{width:auto}"
                + "summary{color:#bbb;margin-top:16px}"
                + "</style></head><body><div class='c'><h2>" + escape(title) + "</h2>" + body + "</div>" + script
                + "</body></html>";
    }

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;").replace("\"", "&quot;");
    }
}
