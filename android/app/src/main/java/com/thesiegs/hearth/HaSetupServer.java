package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.OutputStream;

/**
 * Hands the Home Assistant address and access token to the TV from a phone, so nobody types a 180-character token
 * with a remote. While Settings shows its QR code, this serves a small form at a one-time secret link on the home
 * network; the phone opens it, pastes the token and sends it. Idea and flow from QuickBars for Home Assistant
 * (github.com/Trooped/QuickBars, GPL-3.0), with the secret link added so nothing else on the network can push a
 * token in the meantime. The page seals what it sends with a key that's only in the link's #fragment (PhoneSeal), as
 * the PIN page does (PinSetupServer), so the token can't be read on the network. Stops after one successful send,
 * when Settings closes it, or after ten minutes.
 */
final class HaSetupServer extends SecretLinkServer<HaSetupServer.Sent> {
    private static final String TAG = "HearthHaSetup";
    private static final int MAX_BODY_BYTES = 16 * 1024;

    /** The server running now: start sets it, stop clears it. Both guarded by HaSetupServer.class. */
    private static HaSetupServer sCurrent;
    private static boolean sLastReceived;

    private HaSetupServer(Context context) {
        super(context, TAG, MAX_BODY_BYTES);
    }

    /** Starts a fresh server (replacing any running one) and returns the link for the QR code, or null. */
    static synchronized String start(Context context) {
        stop();
        if (!PhoneSeal.available()) return null;
        String ip = LocalNet.ipv4Address();
        if (ip == null) return null;
        HaSetupServer server = new HaSetupServer(context);
        if (!server.bind()) return null;
        sLastReceived = false;
        server.serve();
        sCurrent = server;
        return server.link(ip);
    }

    static synchronized void stop() {
        if (sCurrent != null) {
            sCurrent.close();
            sCurrent = null;
        }
    }

    /** True once a phone has sent a token through the current (or just-finished) server. */
    static synchronized boolean received() {
        return sLastReceived;
    }

    @Override
    String page() {
        // Only the address is filled in: the token is a secret, and this page isn't sealed on its way out
        return formPage(HaConfig.prefs(mContext).getString(HaConfig.URL_KEY, ""));
    }

    @Override
    Sent read(String opened) throws JSONException {
        return parse(opened);
    }

    @Override
    void answer(Sent sent, OutputStream out) throws IOException {
        if (sent == null) {
            // It opened, but the address or token isn't usable: the page says so
            MiniHttp.respond(out, 422, "Missing");
            return;
        }
        SharedPreferences.Editor edit = HaConfig.prefs(mContext).edit().putString(HaConfig.URL_KEY, sent.url);
        edit.apply();
        HaConfig.setToken(mContext, sent.token);
        // The bridge lives on the main thread: a new token reaches what uses it at once
        new Handler(Looper.getMainLooper()).post(() -> HaBridgeService.sync(mContext));
        String state = "saved";
        finish();
        synchronized (HaSetupServer.class) {
            sLastReceived = true;
        }
        MiniHttp.respond(out, 200, state);
    }

    /** What the phone sent, once it passed the checks in {@link #parse}. */
    static final class Sent {
        final String url;
        final String token;

        Sent(String url, String token) {
            this.url = url;
            this.token = token;
        }
    }

    /**
     * Reads {"url", "token"}: the address and a token (anything else an older page sends is ignored). Null when either
     * is missing.
     */
    static Sent parse(String json) throws JSONException {
        JSONObject fields = new JSONObject(json);
        String url = HaConfig.normalizeUrl(fields.optString("url", ""));
        String token = fields.optString("token", "").replaceAll("\\s", "");
        if (url == null || token.isEmpty()) return null;
        return new Sent(url, token);
    }

    private String formPage(String url) {
        String form = "<form id='f'>"
                + "<label for='url'>" + text(R.string.ha_setup_address_label) + "</label>"
                + "<input id='url' type='url' value='" + escape(url) + "' placeholder='http://192.168.1.10:8123'>"
                + "<label for='token'>" + text(R.string.ha_setup_token_label) + "</label>"
                + "<textarea id='token' rows='5' placeholder='" + text(R.string.ha_setup_token_hint)
                + "' autofocus></textarea>"
                + "<p class='help'>" + text(R.string.ha_setup_token_help) + "</p>"
                + "<p id='err' class='err'></p>"
                + "<button type='submit'>" + text(R.string.ha_setup_send) + "</button></form>"
                + "<div id='done' hidden><p>" + text(R.string.ha_setup_sent_detail) + "</p><p id='more'></p></div>"
                + "<p class='help'>" + text(R.string.ha_setup_help) + "</p>";
        String script = "<script>" + raw(R.raw.phone_seal) + "</script><script>"
                + "var M={missing:'" + js(R.string.ha_setup_missing) + "',failed:'" + js(R.string.ha_setup_failed)
                + "',old:'" + js(R.string.pin_phone_old_browser) + "',sent:'" + js(R.string.ha_setup_sent_title)
                + "'};"
                + PAGE_SCRIPT + "</script>";
        return page(mContext.getString(R.string.ha_setup_title), form, script);
    }

    /**
     * Seals {"url", "token"} with the key in the link's #fragment and posts it to this page's path; the
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
            + "{url:v('url').trim(),token:v('token').replace(/\\s/g,'')}));}"
            + "catch(x){err.textContent=M.old;return;}"
            + "fetch(location.pathname,{method:'POST',headers:{'Content-Type':'text/plain'},body:body})"
            + ".then(function(r){if(r.status===422){err.textContent=M.missing;return null;}if(!r.ok)throw r;"
            + "return r.text();}).then(function(t){if(t===null)return;"
            + "document.getElementById('token').value='';f.hidden=true;document.getElementById('done').hidden=false;"
            + "document.querySelector('h2').textContent=M.sent;})"
            + ".catch(function(){err.textContent=M.failed;});});";

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
}
