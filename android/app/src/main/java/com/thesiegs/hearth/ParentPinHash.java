package com.thesiegs.hearth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Checks a PIN against the Parent PIN as the app keeps it (ParentPinHash in Dart): {@code v2$<iterations>$<salt>$<hash>}
 * (PBKDF2-HMAC-SHA256, hex), or the old unsalted form (64 hex digits). A TV can hold either: one set here, or one that
 * came from the household.
 */
final class ParentPinHash {
    private ParentPinHash() {
    }

    static boolean verify(String pin, String stored) {
        if (pin == null || stored == null || !Household.PARENT_PIN_HASH.matcher(stored).matches()) return false;
        try {
            if (stored.length() == 64) return same(Hex.of(MessageDigest.getInstance("SHA-256")
                    .digest(("ltv-parent-pin:" + pin).getBytes(StandardCharsets.UTF_8))), stored);
            String[] parts = stored.split("\\$");
            int cost = Integer.parseInt(parts[1]);
            if (cost < 1 || cost > 200_000) return false;
            byte[] derived = pbkdf2(pin.getBytes(StandardCharsets.UTF_8), unhex(parts[2]), cost, 32);
            return same(Hex.of(derived), parts[3]);
        } catch (Exception e) {
            return false;
        }
    }

    /** PBKDF2-HMAC-SHA256 (RFC 8018), as the Dart side computes it. */
    static byte[] pbkdf2(byte[] password, byte[] salt, int cost, int length) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(password.length == 0 ? new byte[1] : password, "HmacSHA256"));
        byte[] out = new byte[length];
        int done = 0;
        for (int block = 1; done < length; block++) {
            mac.update(salt);
            mac.update(new byte[]{(byte) (block >>> 24), (byte) (block >>> 16), (byte) (block >>> 8), (byte) block});
            byte[] u = mac.doFinal();
            byte[] t = u.clone();
            for (int i = 1; i < cost; i++) {
                u = mac.doFinal(u);
                for (int j = 0; j < t.length; j++) t[j] ^= u[j];
            }
            int n = Math.min(t.length, length - done);
            System.arraycopy(t, 0, out, done, n);
            done += n;
        }
        return out;
    }

    private static byte[] unhex(String hex) {
        byte[] out = new byte[hex.length() / 2];
        for (int i = 0; i < out.length; i++) out[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        return out;
    }

    private static boolean same(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.US_ASCII), b.getBytes(StandardCharsets.US_ASCII));
    }
}
