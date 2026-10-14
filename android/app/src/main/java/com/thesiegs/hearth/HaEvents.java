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
import java.util.function.Consumer;

import javax.net.ssl.SSLSocketFactory;

/**
 * Listens to one kind of Home Assistant event for a while, over its WebSocket API (/api/websocket) with the panel's
 * token: Hearth hears a phone's answer to an actionable notification (mobile_app_notification_action) this way, since
 * Home Assistant's REST API has no events. A small client of its own: one text frame per message, the server's frames
 * never masked, the client's always (RFC 6455). Blocks: run it off the main thread.
 */
final class HaEvents {
    private static final String TAG = "HearthHaEvents";
    private static final int MAX_FRAME_BYTES = 1024 * 1024;

    private final Socket mSocket;
    private final InputStream mIn;
    private final OutputStream mOut;
    private final SecureRandom mRandom = new SecureRandom();
    private volatile boolean mClosed;

    private HaEvents(Socket socket) throws IOException {
        mSocket = socket;
        mIn = socket.getInputStream();
        mOut = socket.getOutputStream();
    }

    /**
     * Connects, signs in and subscribes to {@code eventType}; then hands each event's data to {@code onEvent} (on
     * this thread) until {@link #close}, the time is up or the connection ends. False when it couldn't subscribe.
     */
    static boolean listen(Context context, String eventType, long forMs, Consumer<JSONObject> onEvent,
            Consumer<HaEvents> onOpen) {
        String base = HaConfig.baseUrl(context);
        String token = HaConfig.token(context);
        if (base == null || token == null) return false;
        HaEvents events = null;
        try {
            URL url = new URL(base);
            if (!LocalNet.allows(url)) {
                Log.w(TAG, "Refusing plain HTTP to a non-local address; use https");
                return false;
            }
            boolean tls = "https".equalsIgnoreCase(url.getProtocol());
            int port = url.getPort() > 0 ? url.getPort() : tls ? 443 : 80;
            Socket socket = tls ? SSLSocketFactory.getDefault().createSocket() : new Socket();
            socket.connect(new InetSocketAddress(url.getHost(), port), 5_000);
            socket.setSoTimeout(5_000);
            events = new HaEvents(socket);
            String path = (url.getPath() == null ? "" : url.getPath().replaceAll("/+$", "")) + "/api/websocket";
            events.handshake(url.getHost() + (url.getPort() > 0 ? ":" + url.getPort() : ""), path);
            if (!"auth_required".equals(events.readJson().optString("type"))) return false;
            events.send(new JSONObject().put("type", "auth").put("access_token", token));
            if (!"auth_ok".equals(events.readJson().optString("type"))) {
                Log.w(TAG, "Home Assistant refused the token");
                return false;
            }
            events.send(new JSONObject().put("id", 1).put("type", "subscribe_events").put("event_type", eventType));
            JSONObject result = events.readJson();
            if (!result.optBoolean("success")) return false;
            if (onOpen != null) onOpen.accept(events);
            long until = System.currentTimeMillis() + forMs;
            socket.setSoTimeout(1_000);
            while (!events.mClosed && System.currentTimeMillis() < until) {
                JSONObject message;
                try {
                    message = events.readJson();
                } catch (java.net.SocketTimeoutException e) {
                    continue;
                }
                if (message == null) break;
                if ("event".equals(message.optString("type"))) {
                    JSONObject event = message.optJSONObject("event");
                    if (event != null) onEvent.accept(event.optJSONObject("data"));
                }
            }
            return true;
        } catch (Exception e) {
            Log.i(TAG, "Home Assistant events ended: " + e.getClass().getSimpleName());
            return events != null && events.mClosed;
        } finally {
            if (events != null) events.closeSocket();
        }
    }

    /** Stops listening (from any thread). */
    void close() {
        mClosed = true;
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

    private void send(JSONObject message) throws IOException {
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
