package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Lower-case hex for digests: certificate checks, the parent PIN hash and poster cache names depend on it. */
public class HexTest {
    @Test
    public void everyByteIsTwoLowerCaseDigits() {
        assertEquals("", Hex.of(new byte[0]));
        assertEquals("00", Hex.of(new byte[]{0}));
        assertEquals("0f10", Hex.of(new byte[]{0x0f, 0x10}));
        // Negative bytes are not sign-extended into extra digits
        assertEquals("ff80", Hex.of(new byte[]{(byte) 0xff, (byte) 0x80}));
        assertEquals("deadbeef", Hex.of(new byte[]{(byte) 0xde, (byte) 0xad, (byte) 0xbe, (byte) 0xef}));
    }

    @Test
    public void matchesTheWellKnownSha1OfAbc() throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-1").digest("abc".getBytes(StandardCharsets.UTF_8));
        assertEquals("a9993e364706816aba3e25717850c26c9cd0d89d", Hex.of(digest));
    }
}
