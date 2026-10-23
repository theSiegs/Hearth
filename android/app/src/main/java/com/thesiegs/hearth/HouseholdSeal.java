package com.thesiegs.hearth;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;

/**
 * Seals and opens household entries (docs/household-sync.md): ChaCha20-Poly1305 under a key derived from the household
 * key, so a TV outside the household can't read or forge one, and Home Assistant, which only stores the sealed bytes,
 * can't either. A sealed entry is a random 64-bit nonce counter and the ciphertext; the household's id is authenticated
 * with it, so an entry sealed for another household doesn't open. Each purpose has its own derived key.
 */
final class HouseholdSeal {
    static final int HOUSEHOLD_KEY_BYTES = 32;
    private static final int TAG_BYTES = 16;
    private static final byte[] ENTRY_LABEL = ShareCrypto.bytes("hearth-household-entry-v1");
    private static final byte[] PERSON_LABEL = ShareCrypto.bytes("hearth-household-person-v1");
    private static final byte[] ID_LABEL = ShareCrypto.bytes("hearth-household-id-v1");
    private static final SecureRandom RANDOM = new SecureRandom();

    private final byte[] entryKey;
    private final byte[] aad;
    private final byte[] personKey;

    HouseholdSeal(byte[] householdKey) throws GeneralSecurityException {
        if (householdKey == null || householdKey.length != HOUSEHOLD_KEY_BYTES) {
            throw new IllegalArgumentException("household key");
        }
        byte[] prk = ShareCrypto.hkdfExtract(new byte[0], householdKey);
        entryKey = ShareCrypto.hkdfExpand(prk, ENTRY_LABEL, ShareCrypto.KEY_BYTES);
        aad = ShareCrypto.hkdfExpand(prk, ID_LABEL, 8);
        personKey = ShareCrypto.hkdfExpand(prk, PERSON_LABEL, ShareCrypto.KEY_BYTES);
    }

    /**
     * Who a Google account is to the household: a keyed hash of the address, "a:" and 24 hex digits. The same on every
     * TV in the household, and the address can't be read from it or guessed against it without the key. Null when
     * there is no address.
     */
    String personId(String email) {
        if (email == null || email.trim().isEmpty()) return null;
        try {
            byte[] mac = ShareCrypto.hkdfExtract(personKey, ShareCrypto.bytes(email.trim().toLowerCase(java.util.Locale.ROOT)));
            StringBuilder out = new StringBuilder("a:");
            for (int i = 0; i < 12; i++) out.append(String.format("%02x", mac[i]));
            return out.toString();
        } catch (GeneralSecurityException e) {
            return null;
        }
    }

    /** A new household key. */
    static byte[] newKey() {
        byte[] key = new byte[HOUSEHOLD_KEY_BYTES];
        RANDOM.nextBytes(key);
        return key;
    }

    /** The household's id: the same for every TV with the key, and says nothing about the key. */
    String id() {
        StringBuilder out = new StringBuilder();
        for (byte b : aad) out.append(String.format("%02x", b));
        return out.toString();
    }

    byte[] seal(HouseholdEntry entry) throws GeneralSecurityException {
        long counter = RANDOM.nextLong();
        byte[] sealed = ShareCrypto.seal(entryKey, counter, aad, ShareCrypto.bytes(entry.toJson()));
        return ByteBuffer.allocate(8 + sealed.length).putLong(counter).put(sealed).array();
    }

    /** The entry in {@code blob}, or null if it doesn't open (another household, altered, truncated) or isn't an entry. */
    HouseholdEntry open(byte[] blob) {
        if (blob == null || blob.length < 8 + TAG_BYTES) return null;
        try {
            long counter = ByteBuffer.wrap(blob, 0, 8).getLong();
            byte[] plain = ShareCrypto.open(entryKey, counter, aad, Arrays.copyOfRange(blob, 8, blob.length));
            return HouseholdEntry.fromJson(new String(plain, StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            return null;
        }
    }
}
