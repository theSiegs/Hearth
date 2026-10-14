package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import org.junit.Test;

/** Opening what a phone page sealed (the page's side is tested in test/js/phone_seal_test.js). */
public class PhoneSealTest {
    private static String seal(byte[] key, byte[] nonce, String path, String text) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("ChaCha20-Poly1305");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "ChaCha20"), new IvParameterSpec(nonce));
        cipher.updateAAD(path.getBytes(StandardCharsets.UTF_8));
        byte[] sealed = cipher.doFinal(text.getBytes(StandardCharsets.UTF_8));
        byte[] body = new byte[12 + sealed.length];
        System.arraycopy(nonce, 0, body, 0, 12);
        System.arraycopy(sealed, 0, body, 12, sealed.length);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(body);
    }

    @Test
    public void opensOnlyWithItsKeyAndPath() throws GeneralSecurityException {
        assertTrue(PhoneSeal.available());
        String keyB64 = PhoneSeal.newKey();
        byte[] key = Base64.getUrlDecoder().decode(keyB64);
        String body = seal(key, new byte[12], "/abc", "{\"pins\":{\"0\":\"1234\"}}");
        assertEquals("{\"pins\":{\"0\":\"1234\"}}", PhoneSeal.open(keyB64, "/abc", body));
        for (String[] bad : new String[][]{{PhoneSeal.newKey(), "/abc"}, {keyB64, "/other"}}) {
            try {
                PhoneSeal.open(bad[0], bad[1], body);
                fail("opened with " + bad[1]);
            } catch (GeneralSecurityException expected) {
                // Another key, or sealed for another page
            }
        }
        try {
            PhoneSeal.open(keyB64, "/abc", "not!base64");
            fail("opened garbage");
        } catch (GeneralSecurityException expected) {
            // Not a sealed body
        }
    }

    @Test
    public void onlyDigitsOfTheRightLength() {
        assertTrue(PinSetupServer.validPin("1234".toCharArray(), 4));
        assertFalse(PinSetupServer.validPin("123".toCharArray(), 4));
        assertFalse(PinSetupServer.validPin("12a4".toCharArray(), 4));
    }
}
