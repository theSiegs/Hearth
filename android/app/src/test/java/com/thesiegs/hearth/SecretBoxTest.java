package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.Map;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

import org.junit.Test;

/** Small secrets sealed at rest: they open for their purpose and key, and for nothing else. */
public class SecretBoxTest {
    /** Plain in-memory keys standing in for the Keystore. */
    private static SecretBox.Keys memoryKeys() {
        Map<String, SecretKey> keys = new HashMap<>();
        return alias -> {
            SecretKey key = keys.get(alias);
            if (key == null) {
                KeyGenerator generator = KeyGenerator.getInstance("AES");
                generator.init(256);
                key = generator.generateKey();
                keys.put(alias, key);
            }
            return key;
        };
    }

    @Test
    public void aSealedTextOpensAgain() {
        SecretBox.Keys keys = memoryKeys();
        String sealed = SecretBox.sealText(keys, "token", "abc.def.ghi");
        assertEquals("abc.def.ghi", SecretBox.openText(keys, "token", sealed));
        assertFalse(sealed.contains("abc"));
    }

    @Test
    public void sealingTheSameTextTwiceGivesDifferentText() {
        SecretBox.Keys keys = memoryKeys();
        assertNotEquals(SecretBox.sealText(keys, "token", "x"), SecretBox.sealText(keys, "token", "x"));
    }

    @Test
    public void aSealedTextDoesNotOpenAsAnotherPurposeOrUnderAnotherKey() {
        SecretBox.Keys keys = memoryKeys();
        String sealed = SecretBox.sealText(keys, "token", "secret");
        assertNull(SecretBox.openText(keys, "household", sealed));
        assertNull(SecretBox.openText(memoryKeys(), "token", sealed));
    }

    @Test
    public void anAlteredOrShortOrMissingTextGivesNull() {
        SecretBox.Keys keys = memoryKeys();
        String sealed = SecretBox.sealText(keys, "token", "secret");
        char last = sealed.charAt(sealed.length() - 5);
        String altered = sealed.substring(0, sealed.length() - 5) + (last == 'A' ? 'B' : 'A') + sealed.substring(sealed.length() - 4);
        assertNull(SecretBox.openText(keys, "token", altered));
        assertNull(SecretBox.openText(keys, "token", "AAAA"));
        assertNull(SecretBox.openText(keys, "token", "not base64 !!"));
        assertNull(SecretBox.openText(keys, "token", ""));
        assertNull(SecretBox.openText(keys, "token", null));
    }

    @Test
    public void aRefusingKeystoreSealsNothing() {
        SecretBox.Keys broken = alias -> {
            throw new java.security.KeyStoreException("gone");
        };
        assertNull(SecretBox.sealText(broken, "token", "secret"));
        assertTrue(SecretBox.sealText(memoryKeys(), "token", "") != null);
    }

    @Test
    public void binarySecretsRoundTrip() {
        SecretBox.Keys keys = memoryKeys();
        byte[] key = new byte[32];
        for (int i = 0; i < key.length; i++) key[i] = (byte) (i * 7);
        String sealed = SecretBox.seal(keys, "household", key);
        assertEquals(java.util.Arrays.toString(key), java.util.Arrays.toString(SecretBox.open(keys, "household", sealed)));
    }
}
