package com.leanbitlab.ltvL;

/** Lower-case hex, the way Hearth writes digests: certificate checks, the parent PIN hash, poster cache names. */
final class Hex {
    private static final char[] DIGITS = "0123456789abcdef".toCharArray();

    private Hex() {}

    static String of(byte[] bytes) {
        char[] out = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            out[i * 2] = DIGITS[(bytes[i] >> 4) & 0xF];
            out[i * 2 + 1] = DIGITS[bytes[i] & 0xF];
        }
        return new String(out);
    }
}
