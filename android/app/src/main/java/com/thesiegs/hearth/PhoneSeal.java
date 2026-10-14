package com.thesiegs.hearth;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Opens what a phone page sealed (res/raw/phone_seal.js): ChaCha20-Poly1305 under a one-time key that only went to
 * the phone in the QR code's link fragment, which browsers never send over the network. The page's own path is the
 * additional data, so a body sealed for one page doesn't open on another.
 */
final class PhoneSeal {
    private static final SecureRandom RANDOM = new SecureRandom();

    private PhoneSeal() {
    }

    /** A fresh key for one page, base64url (for the link's #fragment). */
    static String newKey() {
        byte[] key = new byte[32];
        RANDOM.nextBytes(key);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(key);
    }

    /** Whether this Android can open sealed bodies (ChaCha20-Poly1305 is there from Android 9). */
    static boolean available() {
        try {
            cipher();
            return true;
        } catch (GeneralSecurityException e) {
            return false;
        }
    }

    /** The text the phone sealed: body = base64url(nonce || ciphertext || tag). Throws if it doesn't open. */
    static String open(String keyB64, String path, String body) throws GeneralSecurityException {
        byte[] key = Base64.getUrlDecoder().decode(keyB64);
        byte[] raw;
        try {
            raw = Base64.getUrlDecoder().decode(body.trim());
        } catch (IllegalArgumentException e) {
            throw new GeneralSecurityException("not base64url");
        }
        if (raw.length < 12 + 16) throw new GeneralSecurityException("too short");
        Cipher cipher = cipher();
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "ChaCha20"),
                new IvParameterSpec(Arrays.copyOfRange(raw, 0, 12)));
        cipher.updateAAD(path.getBytes(StandardCharsets.UTF_8));
        byte[] plain = cipher.doFinal(raw, 12, raw.length - 12);
        try {
            return new String(plain, StandardCharsets.UTF_8);
        } finally {
            Arrays.fill(plain, (byte) 0);
        }
    }

    private static Cipher cipher() throws GeneralSecurityException {
        try {
            return Cipher.getInstance("ChaCha20/Poly1305/NoPadding");
        } catch (GeneralSecurityException e) {
            // The JDK's name for it (unit tests)
            return Cipher.getInstance("ChaCha20-Poly1305");
        }
    }
}
