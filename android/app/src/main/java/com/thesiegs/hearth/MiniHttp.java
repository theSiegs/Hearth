package com.thesiegs.hearth;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * The bit of HTTP/1.1 that Hearth's own small servers need (HaNotificationServer, HaSetupServer): one request per
 * connection, a body only by Content-Length, and every response closes the connection.
 */
final class MiniHttp {
    private static final int MAX_LINE_BYTES = 8192;

    /** A request's method, path (without the query) and headers (names in lower case). */
    static final class Request {
        final String method;
        final String path;
        final Map<String, String> headers;

        private Request(String method, String path, Map<String, String> headers) {
            this.method = method;
            this.path = path;
            this.headers = headers;
        }

        /** The Content-Length header; 0 when it's missing or not a number. */
        int contentLength() {
            try {
                return Integer.parseInt(headers.getOrDefault("content-length", "0"));
            } catch (NumberFormatException e) {
                return 0;
            }
        }
    }

    private MiniHttp() {}

    /** Reads the request line and headers; null when the client closed the connection without sending any. */
    static Request read(InputStream in) throws IOException {
        String requestLine = readLine(in);
        if (requestLine == null) return null;
        Map<String, String> headers = new HashMap<>();
        String line;
        while ((line = readLine(in)) != null && !line.isEmpty()) {
            int colon = line.indexOf(':');
            if (colon > 0) {
                headers.put(line.substring(0, colon).trim().toLowerCase(Locale.ROOT), line.substring(colon + 1).trim());
            }
        }
        String[] parts = requestLine.split(" ");
        String method = parts.length > 0 ? parts[0] : "";
        String target = parts.length > 1 ? parts[1] : "";
        int query = target.indexOf('?');
        return new Request(method, query >= 0 ? target.substring(0, query) : target, headers);
    }

    /** Exactly {@code length} bytes of body; throws when the client sends fewer. */
    static byte[] readBody(InputStream in, int length) throws IOException {
        byte[] data = new byte[length];
        int read = 0;
        while (read < length) {
            int n = in.read(data, read, length - read);
            if (n < 0) throw new IOException("Body truncated");
            read += n;
        }
        return data;
    }

    /** Decodes an application/x-www-form-urlencoded body; a pair that doesn't decode is skipped. */
    static Map<String, String> parseForm(String body) {
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

    static void respond(OutputStream out, int status, String text) throws IOException {
        send(out, status, "text/plain", "", text.getBytes(StandardCharsets.UTF_8));
    }

    /** A page that's never cached: the setup form lives at a one-time secret link. */
    static void respondHtml(OutputStream out, String html) throws IOException {
        send(out, 200, "text/html; charset=utf-8", "Cache-Control: no-store\r\n", html.getBytes(StandardCharsets.UTF_8));
    }

    private static void send(OutputStream out, int status, String contentType, String extraHeaders, byte[] body)
            throws IOException {
        out.write(("HTTP/1.1 " + status + " " + reason(status) + "\r\nContent-Type: " + contentType + "\r\n"
                + extraHeaders + "Content-Length: " + body.length + "\r\nConnection: close\r\n\r\n")
                .getBytes(StandardCharsets.ISO_8859_1));
        out.write(body);
        out.flush();
    }

    private static String reason(int status) {
        switch (status) {
            case 200: return "OK";
            case 403: return "Forbidden";
            case 404: return "Not Found";
            default: return "Bad Request";
        }
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') break;
            if (b != '\r') line.write(b);
            if (line.size() > MAX_LINE_BYTES) throw new IOException("Header too long");
        }
        if (b == -1 && line.size() == 0) return null;
        return line.toString("UTF-8");
    }
}
