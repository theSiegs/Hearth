package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/** The request reading Hearth's small servers share (HaNotificationServer, SecretLinkServer), on byte arrays. */
public class MiniHttpTest {
    private static InputStream bytes(String s) {
        return new ByteArrayInputStream(s.getBytes(StandardCharsets.UTF_8));
    }

    /** Hands out at most one byte per read, as a slow phone or network does. */
    private static InputStream trickle(String s) {
        return new ByteArrayInputStream(s.getBytes(StandardCharsets.UTF_8)) {
            @Override
            public synchronized int read(byte[] b, int off, int len) {
                return super.read(b, off, Math.min(len, 1));
            }
        };
    }

    @Test
    public void readsTheMethodPathWithoutQueryAndHeadersInLowerCase() throws IOException {
        MiniHttp.Request request = MiniHttp.read(bytes(
                "POST /abc?x=1 HTTP/1.1\r\nHost: 192.0.2.10\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n\r\nhey"));
        assertEquals("POST", request.method);
        assertEquals("/abc", request.path);
        assertEquals("text/plain", request.headers.get("content-type"));
        assertEquals(3, request.contentLength());
    }

    @Test
    public void aConnectionThatSendsNothingIsNoRequest() throws IOException {
        assertNull(MiniHttp.read(bytes("")));
    }

    @Test
    public void readsTheBodyByItsContentLength() throws IOException {
        InputStream in = bytes("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello and more");
        MiniHttp.Request request = MiniHttp.read(in);
        assertArrayEquals("hello".getBytes(StandardCharsets.UTF_8), MiniHttp.readBody(in, request, 16));
    }

    @Test
    public void aMissingZeroOrBrokenContentLengthGetsNoBody() throws IOException {
        for (String header : new String[] {"", "Content-Length: 0\r\n", "Content-Length: -4\r\n", "Content-Length: lots\r\n"}) {
            InputStream in = bytes("POST / HTTP/1.1\r\n" + header + "\r\nhello");
            assertNull(header, MiniHttp.readBody(in, MiniHttp.read(in), 16));
        }
    }

    @Test
    public void anOversizeBodyIsRefusedWithoutReadingIt() throws IOException {
        InputStream in = bytes("POST / HTTP/1.1\r\nContent-Length: 17\r\n\r\n12345678901234567");
        MiniHttp.Request request = MiniHttp.read(in);
        assertNull(MiniHttp.readBody(in, request, 16));
        assertEquals('1', in.read());
        // The cap itself is allowed
        InputStream atCap = bytes("POST / HTTP/1.1\r\nContent-Length: 16\r\n\r\n1234567890123456");
        assertEquals(16, MiniHttp.readBody(atCap, MiniHttp.read(atCap), 16).length);
    }

    @Test(expected = IOException.class)
    public void aBodyShorterThanItSaidIsAnError() throws IOException {
        InputStream in = bytes("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort");
        MiniHttp.readBody(in, MiniHttp.read(in), 16);
    }

    @Test
    public void aBodyArrivingAByteAtATimeIsReadWhole() throws IOException {
        InputStream in = trickle("POST /p HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world");
        MiniHttp.Request request = MiniHttp.read(in);
        assertEquals("/p", request.path);
        assertEquals("hello world", new String(MiniHttp.readBody(in, request, 16), StandardCharsets.UTF_8));
    }

    @Test
    public void headersEndingWithTheConnectionStillMakeARequest() throws IOException {
        MiniHttp.Request request = MiniHttp.read(bytes("GET /x HTTP/1.1\r\nHost: tv"));
        assertEquals("GET", request.method);
        assertEquals("tv", request.headers.get("host"));
        assertEquals(0, request.contentLength());
    }

    @Test(expected = IOException.class)
    public void aHeaderLineOver8KbIsAnError() throws IOException {
        StringBuilder line = new StringBuilder("GET /");
        for (int i = 0; i < 9000; i++) line.append('a');
        MiniHttp.read(bytes(line + " HTTP/1.1\r\n\r\n"));
    }

    @Test
    public void decodesAFormAndSkipsWhatDoesNotDecode() {
        Map<String, String> form = MiniHttp.parseForm("msg=Hi+there%21&title=&=x&bad=%zz&noequals");
        assertEquals("Hi there!", form.get("msg"));
        assertEquals("", form.get("title"));
        assertEquals(2, form.size());
    }

    @Test
    public void answersCloseTheConnectionWithTheLengthOfTheText() throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        MiniHttp.respond(out, 400, "Bad request");
        String sent = out.toString("UTF-8");
        assertTrue(sent, sent.startsWith("HTTP/1.1 400 Bad Request\r\n"));
        assertTrue(sent, sent.contains("Content-Length: 11\r\nConnection: close\r\n\r\nBad request"));
    }
}
