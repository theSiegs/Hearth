package com.thesiegs.hearth;

import android.content.Context;
import android.content.pm.PackageManager;
import android.util.Base64;
import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Streaming app PINs typed on a phone instead of with the remote. While Settings shows its QR code (after the parent
 * PIN and the consent screen on the TV), this serves a page at a one-time secret link on the home network listing the
 * PIN rows of the Google TV profile that was on then. The page seals what's typed with a key that's only in the link's
 * #fragment (PhoneSeal), so nothing on the network can read the PINs, and the TV saves them for that profile exactly as
 * Settings would (PinVault, pairing a name match for good). Stops after one save, when Settings closes it, or after
 * ten minutes, like the Home Assistant page (HaSetupServer).
 */
final class PinSetupServer {
    private static final String TAG = "HearthPinSetup";
    private static final int[] PORTS = {8765, 8766, 8767, 8768, 8769};
    private static final int MAX_BODY_BYTES = 8 * 1024;
    private static final long LIFETIME_MS = 10 * 60 * 1000;

    private static PinSetupServer sCurrent;
    private static int sLastSaved = -1;

    /** One PIN row: an app and the app profile Hearth picks there for this Google TV profile. */
    static final class Row {
        final String pkg;
        final String label;
        final String appProfile;
        /** Picked by name so far: saving a PIN pairs it for good, as Settings does. */
        final boolean nameMatch;
        final int length;
        final boolean saved;
        /** The app's account-wide content PIN (Paramount+), not a profile's. */
        final boolean content;

        /** The profile's own Google TV PIN (PhoneApproval), not an app's. */
        boolean googleTv() {
            return GooglePinRecipe.VAULT_NAME.equals(appProfile);
        }

        Row(String pkg, String label, String appProfile, boolean nameMatch, int length, boolean saved, boolean content) {
            this.pkg = pkg;
            this.label = label;
            this.appProfile = appProfile;
            this.nameMatch = nameMatch;
            this.length = length;
            this.saved = saved;
            this.content = content;
        }
    }

    private final Context mContext;
    private final String mOwner;
    private final String mOwnerName;
    private final List<Row> mRows;
    /** Apps Hearth can type in that it hasn't seen this profile's app profiles in yet. */
    private final List<String> mNotSeen;
    private final String mSecret;
    private final String mKey;
    private ServerSocket mServerSocket;
    private volatile boolean mDone;
    private long mStartedAt;

    private PinSetupServer(Context context, String owner) {
        mContext = context.getApplicationContext();
        mOwner = owner;
        mOwnerName = ProfileUsers.displayName(mContext, owner);
        mRows = new ArrayList<>();
        mNotSeen = new ArrayList<>();
        readRows();
        byte[] bytes = new byte[16];
        new SecureRandom().nextBytes(bytes);
        mSecret = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
        mKey = PhoneSeal.newKey();
    }

    private void readRows() {
        PackageManager pm = mContext.getPackageManager();
        boolean grownUp = !ProfilePairing.isKids(mContext, mOwner) && mOwner.startsWith("user:0");
        // An adult's own Google TV PIN, for approving switches from their phone
        if (grownUp) {
            mRows.add(new Row(LauncherAccessibilityService.GOOGLE_TV_PACKAGE, "Google TV", GooglePinRecipe.VAULT_NAME,
                    false, 4, PhoneApproval.hasPin(mContext, mOwner), false));
        }
        for (String pkg : ProfilePairing.APPS) {
            String label;
            try {
                label = pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString();
            } catch (PackageManager.NameNotFoundException e) {
                continue;
            }
            if (grownUp && ContentPin.PACKAGE.equals(pkg)) {
                mRows.add(new Row(pkg, label, ContentPin.VAULT_PROFILE, false, ContentPin.LENGTH,
                        !PinVault.STATUS_NONE.equals(PinVault.statusOf(mContext, PinVault.SHARED, pkg,
                                ContentPin.VAULT_PROFILE)), true));
            }
            PinRecipe recipe = PinRecipes.forPackage(pkg);
            if (recipe == null || !ProfilePairing.isAppEnabled(mContext, pkg)) continue;
            String mode = ProfilePairing.getMode(mContext, pkg, mOwner);
            String appProfile = ProfilePairing.MODE_PROFILE.equals(mode)
                    ? ProfilePairing.getChosenProfile(mContext, pkg, mOwner)
                    : ProfilePairing.MODE_AUTO.equals(mode)
                    ? ProfilePairing.bestMatch(mOwnerName, ProfilePairing.getSeenNames(mContext, pkg)) : null;
            if (appProfile == null) {
                if (!ProfilePairing.MODE_PICKER.equals(mode)) mNotSeen.add(label);
                continue;
            }
            mRows.add(new Row(pkg, label, appProfile, ProfilePairing.MODE_AUTO.equals(mode), recipe.pinLength(),
                    PinVault.has(mContext, mOwner, pkg, appProfile), false));
        }
    }

    /** Starts a fresh page for this Google TV profile and returns its link (secret path, #key), or null. */
    static synchronized String start(Context context, String owner) {
        stop();
        if (owner == null || !PhoneSeal.available()) return null;
        String ip = LocalNet.ipv4Address();
        if (ip == null) return null;
        PinSetupServer server = new PinSetupServer(context, owner);
        for (int port : PORTS) {
            try {
                server.mServerSocket = new ServerSocket(port);
                break;
            } catch (IOException ignored) {
            }
        }
        if (server.mServerSocket == null) return null;
        server.mStartedAt = System.currentTimeMillis();
        sLastSaved = -1;
        Thread thread = new Thread(server::run, "HearthPinSetup");
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

    /** How many PINs the phone saved through the current (or just-finished) page; -1 before it has. */
    static synchronized int saved() {
        return sLastSaved;
    }

    private void run() {
        ServerSocket server = mServerSocket;
        try {
            server.setSoTimeout(30_000);
        } catch (IOException ignored) {
        }
        while (!server.isClosed() && !mDone && System.currentTimeMillis() - mStartedAt < LIFETIME_MS) {
            try (Socket socket = server.accept()) {
                socket.setSoTimeout(10_000);
                handle(socket);
            } catch (SocketTimeoutException ignored) {
            } catch (IOException | RuntimeException e) {
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
            MiniHttp.respondHtml(out, page());
            return;
        }
        int length = request.contentLength();
        if (length <= 0 || length > MAX_BODY_BYTES) {
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        String body = new String(MiniHttp.readBody(in, length), StandardCharsets.UTF_8);
        int saved;
        try {
            saved = save(PhoneSeal.open(mKey, path, body));
        } catch (Exception e) {
            Log.i(TAG, "A sent page didn't open: " + e.getClass().getSimpleName());
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        mDone = true;
        synchronized (PinSetupServer.class) {
            sLastSaved = saved;
        }
        MiniHttp.respond(out, 200, String.valueOf(saved));
    }

    /**
     * Saves what the phone sent, {"pins": {"<row index>": "<digits>"}}, for this page's profile: only rows the page
     * listed, only digits of the row's length. Returns how many were saved.
     */
    private int save(String json) throws Exception {
        JSONObject pins = new JSONObject(json).getJSONObject("pins");
        int saved = 0;
        for (int i = 0; i < mRows.size(); i++) {
            Row row = mRows.get(i);
            String pin = pins.optString(String.valueOf(i), "");
            if (pin.isEmpty()) continue;
            char[] digits = pin.toCharArray();
            try {
                if (!validPin(digits, row.length)) continue;
                if (row.content) {
                    if (!PinVault.save(mContext, PinVault.SHARED, row.pkg, ContentPin.VAULT_PROFILE, digits)) continue;
                } else {
                    // A name match gets paired for good, as Settings does, so the PIN always goes with that profile
                    if (row.nameMatch) {
                        ProfilePairing.setChoice(mContext, row.pkg, mOwner, ProfilePairing.MODE_PROFILE, row.appProfile);
                    }
                    if (!PinVault.save(mContext, mOwner, row.pkg, row.appProfile, digits)) continue;
                }
                if (!row.googleTv()) {
                    PinVault.setPaused(mContext, row.pkg, false);
                    PinVault.resetBreaks(mContext, row.pkg);
                }
                saved++;
            } finally {
                Arrays.fill(digits, '\0');
            }
        }
        Log.i(TAG, saved + " PIN(s) saved from a phone for " + LogNames.key(mOwner));
        return saved;
    }

    static boolean validPin(char[] digits, int length) {
        if (digits.length != length) return false;
        for (char c : digits) {
            if (c < '0' || c > '9') return false;
        }
        return true;
    }

    // ---- The page ----

    private String text(int id, Object... args) {
        return escape(mContext.getString(id, args));
    }

    private String page() {
        StringBuilder body = new StringBuilder();
        body.append("<p class='help'>").append(text(R.string.pin_phone_intro)).append("</p>");
        if (mRows.isEmpty()) body.append("<p>").append(text(R.string.pin_phone_none)).append("</p>");
        body.append("<form id='f'>");
        for (int i = 0; i < mRows.size(); i++) {
            Row row = mRows.get(i);
            String title = row.googleTv() ? text(R.string.pin_phone_google)
                    : row.content ? text(R.string.pin_phone_content, row.label)
                    : text(R.string.pin_phone_row, row.label, row.appProfile);
            body.append("<fieldset data-i='").append(i).append("' data-len='").append(row.length).append("'>")
                    .append("<legend>").append(title).append("</legend>")
                    .append("<p class='help'>").append(row.saved ? text(R.string.pin_phone_saved) : text(R.string.pin_phone_unsaved))
                    .append("</p><input class='a' type='password' inputmode='numeric' autocomplete='off' maxlength='")
                    .append(row.length).append("' placeholder='").append(text(R.string.pin_phone_pin)).append("'>")
                    .append("<input class='b' type='password' inputmode='numeric' autocomplete='off' maxlength='")
                    .append(row.length).append("' placeholder='").append(text(R.string.pin_phone_again)).append("'>")
                    .append("</fieldset>");
        }
        for (String label : mNotSeen) {
            body.append("<p class='help'>").append(text(R.string.pin_phone_open_once, label)).append("</p>");
        }
        if (!mRows.isEmpty()) {
            body.append("<p id='err' class='err'></p><button type='submit'>").append(text(R.string.pin_phone_send))
                    .append("</button>");
        }
        body.append("</form><div id='done' hidden><p>").append(text(R.string.pin_phone_sent)).append("</p></div>");
        String script = "<script>" + raw(R.raw.phone_seal) + "</script><script>"
                + "var M={mismatch:'" + js(R.string.pin_phone_mismatch) + "',length:'" + js(R.string.pin_phone_length)
                + "',failed:'" + js(R.string.pin_phone_failed) + "',old:'" + js(R.string.pin_phone_old_browser) + "'};"
                + PAGE_SCRIPT + "</script>";
        return "<!DOCTYPE html><html><head><meta charset='utf-8'>"
                + "<meta name='viewport' content='width=device-width, initial-scale=1'><meta name='referrer' content='no-referrer'>"
                + "<title>Hearth</title><style>"
                + "body{font-family:Roboto,Arial,sans-serif;background:#0f0f0f;color:#ddd;margin:0;padding:20px}"
                + ".c{background:#1a1a1a;border:1px solid #333;border-radius:16px;padding:24px;max-width:520px;margin:0 auto}"
                + "h2{color:#fff;margin-top:0}fieldset{border:1px solid #333;border-radius:12px;margin:14px 0;padding:10px 14px}"
                + "legend{color:#fff;padding:0 6px}input{width:100%;box-sizing:border-box;padding:12px;font-size:18px;"
                + "letter-spacing:4px;border-radius:8px;border:2px solid #444;background:#222;color:#eee;margin:6px 0}"
                + "button{margin-top:16px;width:100%;padding:14px;font-size:16px;border:0;border-radius:8px;"
                + "background:#ff7a1a;color:#111;font-weight:600}.help{color:#888;font-size:14px}.err{color:#ff8a80}"
                + "</style></head><body><div class='c'><h2>" + text(R.string.pin_phone_title, mOwnerName) + "</h2>"
                + body + "</div>" + script + "</body></html>";
    }

    /**
     * Checks each row (both entries, digits only, the row's length), seals {"pins": {index: digits}} with the key in
     * the link's #fragment and posts it to this page's path. The fragment never leaves the phone.
     */
    private static final String PAGE_SCRIPT = ""
            + "var f=document.getElementById('f'),err=document.getElementById('err');"
            + "if(typeof BigInt==='undefined'||!window.crypto||!crypto.getRandomValues||!location.hash){"
            + "if(err)err.textContent=M.old;}"
            + "f&&f.addEventListener('submit',function(e){e.preventDefault();err.textContent='';var pins={},bad=null;"
            + "f.querySelectorAll('fieldset').forEach(function(s){var a=s.querySelector('.a').value.trim(),"
            + "b=s.querySelector('.b').value.trim(),n=+s.dataset.len;if(!a&&!b)return;"
            + "if(a!==b){bad=bad||M.mismatch;return;}if(!new RegExp('^[0-9]{'+n+'}$').test(a)){"
            + "bad=bad||M.length.replace('%d',n);return;}pins[s.dataset.i]=a;});"
            + "if(bad){err.textContent=bad;return;}if(!Object.keys(pins).length)return;"
            + "var body;try{body=HearthSeal.sealText(location.hash.substring(1),location.pathname,"
            + "JSON.stringify({pins:pins}));}catch(x){err.textContent=M.old;return;}"
            + "f.querySelectorAll('input').forEach(function(i){i.value='';});"
            + "fetch(location.pathname,{method:'POST',headers:{'Content-Type':'text/plain'},body:body})"
            + ".then(function(r){if(!r.ok)throw r;f.hidden=true;document.getElementById('done').hidden=false;})"
            + ".catch(function(){err.textContent=M.failed;});});";

    private String raw(int id) {
        try (InputStream in = mContext.getResources().openRawResource(id)) {
            byte[] buffer = new byte[16 * 1024];
            java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
            int n;
            while ((n = in.read(buffer)) > 0) bytes.write(buffer, 0, n);
            return bytes.toString("UTF-8");
        } catch (IOException e) {
            return "";
        }
    }

    /** A string resource for a single-quoted JavaScript string; %1$d becomes %d for the script to fill. */
    private String js(int id) {
        return mContext.getString(id).replace("%1$d", "%d").replace("\\", "\\\\").replace("'", "\\'")
                .replace("<", "\\x3c").replace("\n", " ");
    }

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;")
                .replace("\"", "&quot;");
    }
}
