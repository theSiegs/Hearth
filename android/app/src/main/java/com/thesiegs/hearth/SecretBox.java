package com.thesiegs.hearth;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Small secrets kept encrypted at rest (docs/household-sync.md, "Secrets at rest"): AES-256-GCM under a
 * non-exportable Android Keystore key, one key per purpose (its alias). The sealed text is base64 of the nonce and the
 * ciphertext; the alias is authenticated with it, so a sealed value doesn't open as another purpose's. Where the TV
 * has a StrongBox it holds the key, otherwise the TEE does. A value that doesn't open (the key is gone, the text was
 * altered) gives null, never an exception: the caller treats it as not set.
 */
final class SecretBox {
    /** Where the keys for a purpose come from: the Keystore in the app, a plain key in tests. */
    interface Keys {
        SecretKey key(String alias) throws Exception;
    }

    private static final String KEYSTORE = "AndroidKeyStore";
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BITS = 128;

    private SecretBox() {
    }

    /** The Android Keystore, making a key for an alias the first time. */
    static Keys keystore() {
        return SecretBox::keystoreKey;
    }

    private static synchronized SecretKey keystoreKey(String alias) throws Exception {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        if (store.containsAlias(alias)) return ((KeyStore.SecretKeyEntry) store.getEntry(alias, null)).getSecretKey();
        try {
            return generate(alias, true);
        } catch (StrongBoxUnavailableException e) {
            return generate(alias, false);
        }
    }

    private static SecretKey generate(String alias, boolean strongBox) throws Exception {
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE);
        generator.init(new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setIsStrongBoxBacked(strongBox)
                .build());
        return generator.generateKey();
    }

    /** {@code plain} sealed under the key for {@code alias}; null if the Keystore refuses. */
    static String seal(Keys keys, String alias, byte[] plain) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, keys.key(alias));
            cipher.updateAAD(alias.getBytes(StandardCharsets.UTF_8));
            byte[] iv = cipher.getIV();
            byte[] sealed = cipher.doFinal(plain);
            byte[] out = Arrays.copyOf(iv, iv.length + sealed.length);
            System.arraycopy(sealed, 0, out, iv.length, sealed.length);
            return Base64.getEncoder().encodeToString(out);
        } catch (Exception e) {
            return null;
        }
    }

    /** What {@link #seal} sealed, or null when it doesn't open. */
    static byte[] open(Keys keys, String alias, String sealed) {
        if (sealed == null) return null;
        try {
            byte[] raw = Base64.getDecoder().decode(sealed);
            if (raw.length < NONCE_BYTES + TAG_BITS / 8) return null;
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, keys.key(alias), new GCMParameterSpec(TAG_BITS, raw, 0, NONCE_BYTES));
            cipher.updateAAD(alias.getBytes(StandardCharsets.UTF_8));
            return cipher.doFinal(raw, NONCE_BYTES, raw.length - NONCE_BYTES);
        } catch (Exception e) {
            return null;
        }
    }

    static String sealText(Keys keys, String alias, String text) {
        return seal(keys, alias, text.getBytes(StandardCharsets.UTF_8));
    }

    static String openText(Keys keys, String alias, String sealed) {
        byte[] plain = open(keys, alias, sealed);
        return plain == null ? null : new String(plain, StandardCharsets.UTF_8);
    }
}
