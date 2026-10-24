package com.thesiegs.hearth;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;

import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.X509EncodedKeySpec;

/**
 * This TV's own key in its household (docs/household-sync.md, "Terms"): an EC P-256 signing key pair whose private half
 * never leaves the Android Keystore. A TV proves who it is by signing each exchange; its TV id is a hash of the public
 * key, so an id can't be claimed with another key. The pair is made when the TV starts or joins a household and deleted
 * when it leaves; a TV that joins again gets a new pair, and so a new id.
 */
final class HouseholdIdentity {
    /** A TV key: its public half (X.509 encoded) and signing with the private half. */
    interface Signer {
        byte[] publicKey();

        byte[] sign(byte[] data) throws GeneralSecurityException;
    }

    /** Where the TV key is kept: the Keystore in the app, memory in tests. */
    interface Keys {
        /** The TV key, or null when there is none (or it can't be used any more). */
        Signer load();

        /** A new TV key, replacing any; null when the Keystore refuses. */
        Signer create();

        void delete();
    }

    private static final String KEYSTORE = "AndroidKeyStore";
    static final String ALIAS = "hearth_household_tv_v2";
    private static final String ALGORITHM = "SHA256withECDSA";

    private HouseholdIdentity() {
    }

    /** The TV id of a public key: "tv-" and 16 hex digits of its SHA-256. */
    static String tvIdOf(byte[] publicKey) {
        try {
            byte[] hash = ShareCrypto.sha256(publicKey);
            StringBuilder out = new StringBuilder("tv-");
            for (int i = 0; i < 8; i++) out.append(String.format("%02x", hash[i]));
            return out.toString();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Whether {@code signature} is {@code publicKey}'s over {@code data}; false for anything malformed. */
    static boolean verify(byte[] publicKey, byte[] data, byte[] signature) {
        try {
            PublicKey key = KeyFactory.getInstance("EC").generatePublic(new X509EncodedKeySpec(publicKey));
            Signature verifier = Signature.getInstance(ALGORITHM);
            verifier.initVerify(key);
            verifier.update(data);
            return verifier.verify(signature);
        } catch (Exception e) {
            return false;
        }
    }

    /** Signs with {@code key} the way {@link #verify} checks. */
    static byte[] sign(PrivateKey key, byte[] data) throws GeneralSecurityException {
        Signature signer = Signature.getInstance(ALGORITHM);
        signer.initSign(key);
        signer.update(data);
        return signer.sign();
    }

    /** The Android Keystore. */
    static Keys keystore() {
        return new Keys() {
            @Override
            public Signer load() {
                try {
                    KeyStore store = KeyStore.getInstance(KEYSTORE);
                    store.load(null);
                    if (!store.containsAlias(ALIAS)) return null;
                    KeyStore.PrivateKeyEntry entry = (KeyStore.PrivateKeyEntry) store.getEntry(ALIAS, null);
                    return signer(entry.getPrivateKey(), entry.getCertificate().getPublicKey().getEncoded());
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            public Signer create() {
                delete();
                try {
                    return generate(true);
                } catch (StrongBoxUnavailableException e) {
                    try {
                        return generate(false);
                    } catch (Exception again) {
                        return null;
                    }
                } catch (Exception e) {
                    return null;
                }
            }

            @Override
            public void delete() {
                try {
                    KeyStore store = KeyStore.getInstance(KEYSTORE);
                    store.load(null);
                    if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS);
                } catch (Exception ignored) {
                }
            }
        };
    }

    private static synchronized Signer generate(boolean strongBox) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE);
        generator.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setIsStrongBoxBacked(strongBox)
                .build());
        java.security.KeyPair pair = generator.generateKeyPair();
        return signer(pair.getPrivate(), pair.getPublic().getEncoded());
    }

    static Signer signer(PrivateKey key, byte[] publicKey) {
        return new Signer() {
            @Override
            public byte[] publicKey() {
                return publicKey.clone();
            }

            @Override
            public byte[] sign(byte[] data) throws GeneralSecurityException {
                return HouseholdIdentity.sign(key, data);
            }
        };
    }
}
