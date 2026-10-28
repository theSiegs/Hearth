package com.thesiegs.hearth;

import android.content.Context;
import android.util.Base64;
import android.util.Log;

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
 * A page at a one-time secret link on the home network, for a phone to send something to the TV (HaSetupServer,
 * PinSetupServer). A GET of the link serves the page; a POST brings what the page sealed with the key that's only in
 * the link's #fragment (PhoneSeal). Serves until a send is done ({@link #finish}), it's closed, or ten minutes pass.
 *
 * @param <T> what a send holds once opened
 */
abstract class SecretLinkServer<T> {
    private static final int[] PORTS = {8765, 8766, 8767, 8768, 8769};
    private static final long LIFETIME_MS = 10 * 60 * 1000;

    final Context mContext;
    private final String mTag;
    private final int mMaxBodyBytes;
    private final String mSecret;
    private final String mKey;
    private ServerSocket mServerSocket;
    private volatile boolean mDone;
    private long mStartedAt;

    /** The tag names the log and the thread; a POST's body may be up to maxBodyBytes. */
    SecretLinkServer(Context context, String tag, int maxBodyBytes) {
        mContext = context.getApplicationContext();
        mTag = tag;
        mMaxBodyBytes = maxBodyBytes;
        byte[] bytes = new byte[16];
        new SecureRandom().nextBytes(bytes);
        mSecret = Base64.encodeToString(bytes, Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
        mKey = PhoneSeal.newKey();
    }

    /** The page a GET of the link gets. */
    abstract String page();

    /** What a send holds, from the opened (unsealed) body; throwing answers 400. */
    abstract T read(String opened) throws Exception;

    /** Answers a send that opened; call {@link #finish} when it's the one the page was for. */
    abstract void answer(T sent, OutputStream out) throws IOException;

    /** Takes the first free port of the five; false when none is. */
    final boolean bind() {
        for (int port : PORTS) {
            try {
                mServerSocket = new ServerSocket(port);
                return true;
            } catch (IOException ignored) {
            }
        }
        return false;
    }

    /** Starts serving on the bound port. */
    final void serve() {
        mStartedAt = System.currentTimeMillis();
        Thread thread = new Thread(this::run, mTag);
        thread.setDaemon(true);
        thread.start();
    }

    /** The link for the QR code: this TV's address, the port, the secret path and the #key. */
    final String link(String ip) {
        return "http://" + ip + ":" + mServerSocket.getLocalPort() + "/" + mSecret + "#" + mKey;
    }

    final void close() {
        try {
            mServerSocket.close();
        } catch (IOException ignored) {
        }
    }

    /** Stops serving after this request. */
    final void finish() {
        mDone = true;
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
                // A malformed request from the network must not take the server (or Hearth) down
                if (!server.isClosed()) Log.w(mTag, "Request failed: " + e.getClass().getSimpleName());
            }
        }
        try {
            server.close();
        } catch (IOException ignored) {
        }
    }

    private void handle(Socket socket) throws IOException {
        MiniHttp.Request request = MiniHttp.readLocal(socket);
        if (request == null) return;
        OutputStream out = socket.getOutputStream();
        String path = "/" + mSecret;
        if (!path.equals(request.path)) {
            MiniHttp.respond(out, 404, "Not found");
            return;
        }
        if (!"POST".equals(request.method)) {
            MiniHttp.respondHtml(out, page());
            return;
        }
        InputStream in = socket.getInputStream();
        byte[] body = MiniHttp.readBody(in, request, mMaxBodyBytes);
        if (body == null) {
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        T sent;
        try {
            sent = read(PhoneSeal.open(mKey, path, new String(body, StandardCharsets.UTF_8)));
        } catch (Exception e) {
            Log.i(mTag, "A sent page didn't open: " + e.getClass().getSimpleName());
            MiniHttp.respond(out, 400, "Bad request");
            return;
        }
        answer(sent, out);
    }

    /** A raw resource (the page's scripts) as text; empty when it can't be read. */
    final String raw(int id) {
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

    /** Text escaped for the page's HTML. */
    static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("'", "&#39;").replace("\"", "&quot;");
    }
}
