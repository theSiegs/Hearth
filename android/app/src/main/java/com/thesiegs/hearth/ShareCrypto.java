package com.thesiegs.hearth;

import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECFieldFp;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.KeyAgreement;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * The primitives of a TV-to-TV copy (ShareSession): an ephemeral ECDH on P-256 with public keys in the uncompressed
 * point form, HKDF-SHA256, the six-digit code both TVs show, and ChaCha20-Poly1305 frames under a per-direction key.
 * Plain JCA, no library; the same cipher PhoneSeal opens phone pages with.
 */
final class ShareCrypto {
    static final int POINT_BYTES = 65;
    static final int KEY_BYTES = 32;
    private static final String CURVE = "secp256r1";

    private ShareCrypto() {
    }

    /** A fresh P-256 key pair for one session. */
    static KeyPair newKeyPair() throws GeneralSecurityException {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec(CURVE));
        return generator.generateKeyPair();
    }

    /** The public key as 0x04 || X || Y, 32 bytes each. */
    static byte[] encodePoint(PublicKey key) {
        ECPoint w = ((ECPublicKey) key).getW();
        byte[] out = new byte[POINT_BYTES];
        out[0] = 4;
        System.arraycopy(fixed(w.getAffineX()), 0, out, 1, 32);
        System.arraycopy(fixed(w.getAffineY()), 0, out, 33, 32);
        return out;
    }

    /** A peer's public key from its point; refuses anything that isn't on the curve (an invalid-curve attack). */
    static PublicKey decodePoint(byte[] point, ECParameterSpec params) throws GeneralSecurityException {
        if (point == null || point.length != POINT_BYTES || point[0] != 4) {
            throw new GeneralSecurityException("not an uncompressed point");
        }
        BigInteger x = new BigInteger(1, Arrays.copyOfRange(point, 1, 33));
        BigInteger y = new BigInteger(1, Arrays.copyOfRange(point, 33, 65));
        BigInteger p = ((ECFieldFp) params.getCurve().getField()).getP();
        if (x.compareTo(p) >= 0 || y.compareTo(p) >= 0) throw new GeneralSecurityException("coordinate out of range");
        BigInteger left = y.multiply(y).mod(p);
        BigInteger right = x.pow(3).add(params.getCurve().getA().multiply(x)).add(params.getCurve().getB()).mod(p);
        if (!left.equals(right)) throw new GeneralSecurityException("point not on the curve");
        return KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(new ECPoint(x, y), params));
    }

    /** The curve's parameters, from a key pair made here. */
    static ECParameterSpec params(KeyPair pair) {
        return ((ECPublicKey) pair.getPublic()).getParams();
    }

    /** The ECDH shared secret Z (32 bytes). */
    static byte[] agree(KeyPair mine, PublicKey theirs) throws GeneralSecurityException {
        KeyAgreement agreement = KeyAgreement.getInstance("ECDH");
        agreement.init(mine.getPrivate());
        agreement.doPhase(theirs, true);
        return agreement.generateSecret();
    }

    static byte[] sha256(byte[]... parts) throws GeneralSecurityException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (byte[] part : parts) digest.update(part);
        return digest.digest();
    }

    /** HKDF-Extract (RFC 5869). */
    static byte[] hkdfExtract(byte[] salt, byte[] ikm) throws GeneralSecurityException {
        return hmac(salt, ikm);
    }

    /** HKDF-Expand (RFC 5869). */
    static byte[] hkdfExpand(byte[] prk, byte[] info, int length) throws GeneralSecurityException {
        if (length > 255 * 32) throw new IllegalArgumentException("too long");
        byte[] out = new byte[length];
        byte[] block = new byte[0];
        int filled = 0;
        for (int counter = 1; filled < length; counter++) {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(prk, "HmacSHA256"));
            mac.update(block);
            mac.update(info);
            mac.update((byte) counter);
            block = mac.doFinal();
            int n = Math.min(block.length, length - filled);
            System.arraycopy(block, 0, out, filled, n);
            filled += n;
        }
        return out;
    }

    private static byte[] hmac(byte[] key, byte[] data) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key.length == 0 ? new byte[32] : key, "HmacSHA256"));
        return mac.doFinal(data);
    }

    /** Six decimal digits, from 4 bytes of key material: what both parents compare. */
    static String sas(byte[] material) {
        long value = ByteBuffer.wrap(material, 0, 4).getInt() & 0xFFFFFFFFL;
        return String.format(java.util.Locale.ROOT, "%06d", value % 1_000_000L);
    }

    /** A frame's sealed body: ChaCha20-Poly1305 under {@code key}, the nonce from {@code counter}, {@code aad} authenticated. */
    static byte[] seal(byte[] key, long counter, byte[] aad, byte[] plain) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("ChaCha20-Poly1305");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "ChaCha20"), new IvParameterSpec(nonce(counter)));
        cipher.updateAAD(aad);
        return cipher.doFinal(plain);
    }

    static byte[] open(byte[] key, long counter, byte[] aad, byte[] sealed) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("ChaCha20-Poly1305");
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "ChaCha20"), new IvParameterSpec(nonce(counter)));
        cipher.updateAAD(aad);
        return cipher.doFinal(sealed);
    }

    /** 12 bytes: four zero bytes and the 64-bit frame counter. Each direction has its own key, so a nonce never repeats. */
    private static byte[] nonce(long counter) {
        return ByteBuffer.allocate(12).putInt(0).putLong(counter).array();
    }

    private static byte[] fixed(BigInteger value) {
        byte[] raw = value.toByteArray();
        byte[] out = new byte[32];
        int skip = raw.length > 32 ? raw.length - 32 : 0;
        System.arraycopy(raw, skip, out, 32 - (raw.length - skip), raw.length - skip);
        return out;
    }

    static byte[] bytes(String text) {
        return text.getBytes(StandardCharsets.UTF_8);
    }
}
