package com.thesiegs.hearth;

import android.content.Context;
import android.util.Base64;
import android.util.Log;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

import javax.net.ssl.SSLSocketFactory;

/**
 * A small client of Home Assistant's WebSocket API (/api/websocket) with the panel's token: one text frame per message,
 * the server's frames never masked, the client's always (RFC 6455). Commands go over a connection of their own
 * ({@link #connect}, {@link #mintToken}). Events (a phone's answer to an actionable notification,
 * mobile_app_notification_action, since Home Assistant's REST API has no events) are heard through the one session
 * HaBridgeService keeps while something waits ({@link HaEventSession}), which connects through {@link #dialer}.
 * Blocks: run it off the main thread.
 */
final class HaEvents implements HaEventSession.Link {
    private static final String TAG = "HearthHaEvents";
    private static final int MAX_FRAME_BYTES = 1024 * 1024;

    private final Socket mSocket;
    private final InputStream mIn;
    private final OutputStream mOut;
    private final String mToken;
    private final SecureRandom mRandom = new SecureRandom();

    private HaEvents(Socket socket, String token) throws IOException {
        mSocket = socket;
        mIn = socket.getInputStream();
        mOut = socket.getOutputStream();
        mToken = token;
    }

    /** Which address and token are set, without opening the token; null when either is missing. */
    static String settings(Context context) {
        String base = HaConfig.baseUrl(context);
        String token = HaConfig.tokenStamp(context);
        return base == null || token == null ? null : base + " " + token;
    }

    /** What the event session connects with: this TV's Home Assistant settings, read again for every connection. */
    static HaEventSession.Dialer dialer(Context context) {
        Context app = context.getApplicationContext();
        return new HaEventSession.Dialer() {
            @Override
            public String settings() {
                return HaEvents.settings(app);
            }

            @Override
            public HaEventSession.Link dial() throws Exception {
                return HaEvents.dial(app);
            }
        };
    }

    /**
     * An answer to an actionable notification: true for {@code prefix + "ALLOW_" + nonce}, false for its DENY, null
     * for anything else (another request's buttons, another notification).
     */
    static Boolean answer(JSONObject data, String prefix, String nonce) {
        String action = data != null ? data.optString("action") : "";
        if (action.equals(prefix + "ALLOW_" + nonce)) return Boolean.TRUE;
        if (action.equals(prefix + "DENY_" + nonce)) return Boolean.FALSE;
        return null;
    }

    /** Connected and signed in with the panel's token, or null (nothing set up, plain HTTP off the home network, refused). */
    private static HaEvents open(Context context) throws Exception {
        HaEvents events = dial(context);
        if (events == null) return null;
        try {
            JSONObject first = events.readJson();
            if (first == null || !"auth_required".equals(first.optString("type"))) {
                events.closeSocket();
                return null;
            }
            events.send(new JSONObject().put("type", "auth").put("access_token", events.mToken));
            JSONObject second = events.readJson();
            if (second == null || !"auth_ok".equals(second.optString("type"))) {
                Log.w(TAG, "Home Assistant refused the token");
                events.closeSocket();
                return null;
            }
            return events;
        } catch (Exception e) {
            events.closeSocket();
            throw e;
        }
    }

    /** Connected and upgraded to a WebSocket, not signed in; null when nothing is set up or the address is refused. */
    private static HaEvents dial(Context context) throws Exception {
        String base = HaConfig.baseUrl(context);
        String token = HaConfig.token(context);
        if (base == null || token == null) return null;
        URL url = new URL(base);
        if (!LocalNet.allows(url)) {
            Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
            return null;
        }
        boolean tls = "https".equalsIgnoreCase(url.getProtocol());
        int port = url.getPort() > 0 ? url.getPort() : tls ? 443 : 80;
        Socket socket = new Socket();
        HaEvents events = null;
        try {
            socket.connect(new InetSocketAddress(url.getHost(), port), 5_000);
            if (tls) {
                // The certificate has to be for the address asked for, or the token goes to whoever answers
                javax.net.ssl.SSLSocket secure = (javax.net.ssl.SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault())
                        .createSocket(socket, url.getHost(), port, true);
                javax.net.ssl.SSLParameters parameters = secure.getSSLParameters();
                parameters.setEndpointIdentificationAlgorithm("HTTPS");
                secure.setSSLParameters(parameters);
                secure.startHandshake();
                socket = secure;
            }
            socket.setSoTimeout(5_000);
            events = new HaEvents(socket, token);
            String path = (url.getPath() == null ? "" : url.getPath().replaceAll("/+$", "")) + "/api/websocket";
            events.handshake(url.getHost() + (url.getPort() > 0 ? ":" + url.getPort() : ""), path);
            return events;
        } catch (Exception e) {
            if (events != null) events.closeSocket();
            else socket.close();
            throw e;
        }
    }

    /**
     * A new long-lived access token for another TV, made with this TV's own (Home Assistant's WebSocket API is the
     * only place that makes one) and named {@code clientName}: it shows in the person's Home Assistant profile and
     * they can revoke it there. Null when it couldn't be made. Blocks: run it off the main thread.
     */
    static String mintToken(Context context, String clientName, int lifespanDays) {
        HaEvents events = null;
        try {
            events = open(context);
            if (events == null) return null;
            events.send(new JSONObject().put("id", 1).put("type", "auth/long_lived_access_token")
                    .put("client_name", clientName).put("lifespan", lifespanDays));
            JSONObject result = events.readJson();
            if (result == null || !result.optBoolean("success")) {
                Log.i(TAG, "Home Assistant wouldn't make a token");
                return null;
            }
            String token = result.optString("result", "");
            return token.isEmpty() ? null : token;
        } catch (Exception e) {
            Log.i(TAG, "A token wasn't made: " + e.getClass().getSimpleName());
            return null;
        } finally {
            if (events != null) events.closeSocket();
        }
    }

    /** A signed-in connection for commands (not events), or null; end it with {@link #disconnect}. Blocks. */
    static HaEvents connect(Context context) {
        try {
            return open(context);
        } catch (Exception e) {
            Log.i(TAG, "Couldn't connect to Home Assistant: " + e.getClass().getSimpleName());
            return null;
        }
    }

    private int mNextId = 1;

    /**
     * One command ({"type": ..., more fields}) and its answer: {"success": bool, "result": ..., "error": {"code": ...}};
     * null when the connection broke. Blocks.
     */
    JSONObject command(JSONObject message) {
        try {
            int id = ++mNextId;
            send(message.put("id", id));
            for (int i = 0; i < 20; i++) {
                JSONObject answer = readJson();
                if (answer == null) return null;
                if (answer.optInt("id") == id) return answer;
            }
        } catch (Exception e) {
            Log.i(TAG, "A command to Home Assistant failed: " + e.getClass().getSimpleName());
        }
        return null;
    }

    void disconnect() {
        closeSocket();
    }

    // --- The event session's link ---

    @Override
    public String token() {
        return mToken;
    }

    @Override
    public JSONObject read() throws Exception {
        return readJson();
    }

    @Override
    public void setReadTimeout(int ms) throws IOException {
        mSocket.setSoTimeout(ms);
    }

    @Override
    public void close() {
        closeSocket();
    }

    private void closeSocket() {
        try {
            mSocket.close();
        } catch (IOException ignored) {
        }
    }

    private void handshake(String host, String path) throws IOException {
        byte[] nonce = new byte[16];
        mRandom.nextBytes(nonce);
        String key = Base64.encodeToString(nonce, Base64.NO_WRAP);
        mOut.write(("GET " + path + " HTTP/1.1\r\nHost: " + host + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                + "Sec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        mOut.flush();
        String status = readLine();
        if (status == null || !status.contains(" 101")) throw new IOException("no upgrade: " + status);
        String line;
        while ((line = readLine()) != null && !line.isEmpty()) {
            // Headers: nothing needed from them
        }
    }

    private String readLine() throws IOException {
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        int c;
        while ((c = mIn.read()) >= 0) {
            if (c == '\n') break;
            if (c != '\r') line.write(c);
            if (line.size() > 8192) throw new IOException("header too long");
        }
        return c < 0 && line.size() == 0 ? null : line.toString("UTF-8");
    }

    @Override
    public void send(JSONObject message) throws IOException {
        sendFrame(0x1, message.toString().getBytes(StandardCharsets.UTF_8));
    }

    private synchronized void sendFrame(int opcode, byte[] payload) throws IOException {
        ByteArrayOutputStream frame = new ByteArrayOutputStream();
        frame.write(0x80 | opcode);
        int n = payload.length;
        if (n < 126) {
            frame.write(0x80 | n);
        } else if (n < 65536) {
            frame.write(0x80 | 126);
            frame.write(n >> 8);
            frame.write(n);
        } else {
            frame.write(0x80 | 127);
            for (int i = 7; i >= 0; i--) frame.write((int) ((long) n >> (8 * i)));
        }
        byte[] mask = new byte[4];
        mRandom.nextBytes(mask);
        frame.write(mask);
        for (int i = 0; i < n; i++) frame.write(payload[i] ^ mask[i % 4]);
        mOut.write(frame.toByteArray());
        mOut.flush();
    }

    /** The next text message, answering pings on the way; null when the server closed the connection. */
    private JSONObject readJson() throws Exception {
        ByteArrayOutputStream message = new ByteArrayOutputStream();
        while (true) {
            int b0 = mIn.read();
            if (b0 < 0) return null;
            int b1 = readByte();
            int opcode = b0 & 0x0f;
            long length = b1 & 0x7f;
            if (length == 126) {
                length = (readByte() << 8) | readByte();
            } else if (length == 127) {
                length = 0;
                for (int i = 0; i < 8; i++) length = (length << 8) | readByte();
            }
            if (length > MAX_FRAME_BYTES || message.size() + length > MAX_FRAME_BYTES) throw new IOException("too big");
            byte[] mask = (b1 & 0x80) != 0 ? readBytes(4) : null;
            byte[] payload = readBytes((int) length);
            if (mask != null) for (int i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
            if (opcode == 0x8) return null;
            if (opcode == 0x9) {
                sendFrame(0xA, payload);
                continue;
            }
            if (opcode == 0xA) continue;
            message.write(payload);
            if ((b0 & 0x80) != 0) return new JSONObject(message.toString("UTF-8"));
        }
    }

    private int readByte() throws IOException {
        int b = mIn.read();
        if (b < 0) throw new IOException("closed");
        return b;
    }

    private byte[] readBytes(int n) throws IOException {
        byte[] out = new byte[n];
        int read = 0;
        while (read < n) {
            int r = mIn.read(out, read, n - read);
            if (r < 0) throw new IOException("closed");
            read += r;
        }
        return out;
    }
}
