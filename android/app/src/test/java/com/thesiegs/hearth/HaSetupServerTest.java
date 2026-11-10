package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** What the Home Assistant phone page may send (the page seals it; see PhoneSealTest). */
public class HaSetupServerTest {
    @Test
    public void takesAddressAndTokenAndTidiesThem() throws Exception {
        HaSetupServer.Sent sent = HaSetupServer.parse(
                "{\"url\":\" 192.0.2.10:8123/ \",\"token\":\"abc.def\\n ghi\"}");
        assertNotNull(sent);
        assertEquals("http://192.0.2.10:8123", sent.url);
        assertEquals("abc.defghi", sent.token);
        // What an older page sends besides is ignored
        assertNotNull(HaSetupServer.parse("{\"url\":\"192.0.2.10:8123\",\"token\":\"abc\",\"webhook\":\"x\",\"create\":true}"));
    }

    @Test
    public void refusesWhatCouldNotWork() throws Exception {
        // No address
        assertNull(HaSetupServer.parse("{\"url\":\"\",\"token\":\"abc\"}"));
        assertNull(HaSetupServer.parse("{\"token\":\"abc\"}"));
        // No token (the webhook id alone was the retired TV status way)
        assertNull(HaSetupServer.parse("{\"url\":\"192.0.2.10:8123\",\"token\":\"  \"}"));
        assertNull(HaSetupServer.parse("{\"url\":\"192.0.2.10:8123\",\"token\":\"\",\"webhook\":\"hearth-1\"}"));
    }

    @Test(expected = org.json.JSONException.class)
    public void notJsonIsAnError() throws Exception {
        HaSetupServer.parse("url=192.0.2.10&token=abc");
    }
}
