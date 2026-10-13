package com.thesiegs.hearth;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * How Hearth and a profile's agent prove to each other that they share the agent's key, without either sending it
 * (AgentHub, AgentService). Each side picks a nonce; the hub answers the agent's with a proof made from both, the
 * agent checks it and answers the hub's. Something else listening on Hearth's port (Hearth not running) learns
 * nothing it could use, and an agent that can't prove the key gets nothing. Whatever secret the hub hands an agent
 * afterwards is sealed with a key made from both nonces.
 */
final class AgentAuth {
    static final String HUB = "hub";
    static final String AGENT = "agent";
    private static final String SEAL = "seal";
    private static final SecureRandom RANDOM = new SecureRandom();

    private AgentAuth() {
    }

    static String nonce() {
        byte[] bytes = new byte[16];
        RANDOM.nextBytes(bytes);
        return hex(bytes);
    }

    /** The proof one side ("hub" or "agent") gives: its role and both nonces, signed with the agent's key. */
    static String proof(String key, String role, String agentNonce, String hubNonce) {
        return hex(hmac(key, role + "|" + agentNonce + "|" + hubNonce));
    }

    /** Whether a proof received is the one expected, compared in constant time. */
    static boolean verify(String expected, String received) {
        if (expected == null || received == null) return false;
        return MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8),
                received.getBytes(StandardCharsets.UTF_8));
    }

    /** Seals a secret for this connection only (AES-GCM, with a key made from the agent's key and both nonces). */
    static String seal(String key, String agentNonce, String hubNonce, String secret) throws GeneralSecurityException {
        byte[] iv = new byte[12];
        RANDOM.nextBytes(iv);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, sealKey(key, agentNonce, hubNonce), new GCMParameterSpec(128, iv));
        return hex(iv) + ":" + hex(cipher.doFinal(secret.getBytes(StandardCharsets.UTF_8)));
    }

    /** The secret {@link #seal} sealed; throws if it was sealed for another connection or changed on the way. */
    static String open(String key, String agentNonce, String hubNonce, String sealed) throws GeneralSecurityException {
        int colon = sealed.indexOf(':');
        if (colon < 0) throw new GeneralSecurityException("not sealed");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, sealKey(key, agentNonce, hubNonce),
                new GCMParameterSpec(128, unhex(sealed.substring(0, colon))));
        return new String(cipher.doFinal(unhex(sealed.substring(colon + 1))), StandardCharsets.UTF_8);
    }

    private static SecretKeySpec sealKey(String key, String agentNonce, String hubNonce) {
        return new SecretKeySpec(hmac(key, SEAL + "|" + agentNonce + "|" + hubNonce), "AES");
    }

    private static byte[] hmac(String key, String message) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            // HmacSHA256 is always there
            throw new IllegalStateException(e);
        }
    }

    static String hex(byte[] bytes) {
        StringBuilder out = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) out.append(Character.forDigit((b >> 4) & 0xf, 16)).append(Character.forDigit(b & 0xf, 16));
        return out.toString();
    }

    static byte[] unhex(String text) {
        if (text.length() % 2 != 0) throw new IllegalArgumentException("odd length");
        byte[] out = new byte[text.length() / 2];
        for (int i = 0; i < out.length; i++) {
            int high = Character.digit(text.charAt(2 * i), 16);
            int low = Character.digit(text.charAt(2 * i + 1), 16);
            if (high < 0 || low < 0) throw new IllegalArgumentException("not hex");
            out[i] = (byte) ((high << 4) | low);
        }
        return out;
    }
}
