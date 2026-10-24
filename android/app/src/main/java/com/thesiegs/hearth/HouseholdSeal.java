package com.thesiegs.hearth;

import java.security.GeneralSecurityException;
import java.security.SecureRandom;

/**
 * Who a person is to the household (docs/household-sync.md, "Who a profile is"): a keyed hash of their Google account
 * address under the household's person salt, the same on every TV of the household. Also what a version 1 household key
 * becomes when its TVs convert: the household's id, the person salt (so person ids don't change), and the key that lets
 * two converting TVs admit each other.
 */
final class HouseholdSeal {
    static final int SALT_BYTES = 32;
    /** A version 1 household key. */
    static final int V1_KEY_BYTES = 32;
    private static final byte[] V1_PERSON_LABEL = ShareCrypto.bytes("hearth-household-person-v1");
    private static final byte[] V1_ID_LABEL = ShareCrypto.bytes("hearth-household-id-v1");
    private static final byte[] V1_ADMIT_LABEL = ShareCrypto.bytes("hearth-household-admit-v2");
    private static final byte[] ID_LABEL = ShareCrypto.bytes("hearth-household-id-v2");
    private static final SecureRandom RANDOM = new SecureRandom();

    private final byte[] personSalt;

    HouseholdSeal(byte[] personSalt) {
        if (personSalt == null || personSalt.length != SALT_BYTES) throw new IllegalArgumentException("person salt");
        this.personSalt = personSalt.clone();
    }

    /**
     * Who a Google account is to the household: a keyed hash of the address, "a:" and 24 hex digits. The same on every
     * TV in the household, and the address can't be read from it. Null when there is no address.
     */
    String personId(String email) {
        if (email == null || email.trim().isEmpty()) return null;
        try {
            byte[] mac = ShareCrypto.hkdfExtract(personSalt, ShareCrypto.bytes(email.trim().toLowerCase(java.util.Locale.ROOT)));
            return "a:" + hex(mac, 12);
        } catch (GeneralSecurityException e) {
            return null;
        }
    }

    /** A new household's person salt. */
    static byte[] newSalt() {
        byte[] salt = new byte[SALT_BYTES];
        RANDOM.nextBytes(salt);
        return salt;
    }

    /** A new household's id, from the TV that starts it: 16 hex digits that name it and prove nothing. */
    static String newId(String firstTvId) {
        try {
            return hex(ShareCrypto.sha256(ID_LABEL, ShareCrypto.bytes(firstTvId)), 8);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    // ---- Version 1 ----

    /** A version 1 household's id, as its TVs announced it. */
    static String v1Id(byte[] key) throws GeneralSecurityException {
        return hex(ShareCrypto.hkdfExpand(v1Prk(key), V1_ID_LABEL, 8), 8);
    }

    /** A version 1 household's person salt: its old person key, so person ids stay the same. */
    static byte[] v1PersonSalt(byte[] key) throws GeneralSecurityException {
        return ShareCrypto.hkdfExpand(v1Prk(key), V1_PERSON_LABEL, SALT_BYTES);
    }

    /** What two TVs of a version 1 household prove to each other while they convert. */
    static byte[] v1AdmitKey(byte[] key) throws GeneralSecurityException {
        return ShareCrypto.hkdfExpand(v1Prk(key), V1_ADMIT_LABEL, ShareCrypto.KEY_BYTES);
    }

    private static byte[] v1Prk(byte[] key) throws GeneralSecurityException {
        if (key == null || key.length != V1_KEY_BYTES) throw new IllegalArgumentException("household key");
        return ShareCrypto.hkdfExtract(new byte[0], key);
    }

    static String hex(byte[] bytes, int count) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < count; i++) out.append(String.format("%02x", bytes[i]));
        return out.toString();
    }
}
