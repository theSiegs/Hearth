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
                "{\"url\":\" 192.0.2.10:8123/ \",\"token\":\"abc.def\\n ghi\",\"webhook\":\"\"}");
        assertNotNull(sent);
        assertEquals("http://192.0.2.10:8123", sent.url);
        assertEquals("abc.defghi", sent.token);
        assertFalse(sent.webhookOk);
    }

    @Test
    public void takesAWebhookIdAloneForTvStatus() throws Exception {
        HaSetupServer.Sent sent = HaSetupServer.parse(
                "{\"url\":\"https://ha.example.test\",\"token\":\"\",\"webhook\":\"hearth_status-1\"}");
        assertNotNull(sent);
        assertTrue(sent.webhookOk);
        assertEquals("", sent.token);
        assertEquals("hearth_status-1", sent.webhook);
    }

    @Test
    public void asksToCreateTvStatusOnlyWithATokenAndNoWebhookId() throws Exception {
        assertTrue(HaSetupServer.parse(
                "{\"url\":\"192.0.2.10:8123\",\"token\":\"abc\",\"webhook\":\"\",\"create\":true}").create);
        // Not asked for, or nothing to do it with, or an id already given
        assertFalse(HaSetupServer.parse(
                "{\"url\":\"192.0.2.10:8123\",\"token\":\"abc\",\"webhook\":\"\"}").create);
        assertFalse(HaSetupServer.parse(
                "{\"url\":\"192.0.2.10:8123\",\"token\":\"\",\"webhook\":\"hearth-1\",\"create\":true}").create);
        assertFalse(HaSetupServer.parse(
                "{\"url\":\"192.0.2.10:8123\",\"token\":\"abc\",\"webhook\":\"hearth-1\",\"create\":true}").create);
    }

    @Test
    public void refusesWhatCouldNotWork() throws Exception {
        // No address
        assertNull(HaSetupServer.parse("{\"url\":\"\",\"token\":\"abc\",\"webhook\":\"\"}"));
        assertNull(HaSetupServer.parse("{\"token\":\"abc\"}"));
        // Neither a token nor a webhook id
        assertNull(HaSetupServer.parse("{\"url\":\"192.0.2.10:8123\",\"token\":\"  \",\"webhook\":\"\"}"));
        // A webhook id that would change the URL Hearth posts to
        assertNull(HaSetupServer.parse(
                "{\"url\":\"192.0.2.10:8123\",\"token\":\"abc\",\"webhook\":\"a/../b\"}"));
    }

    @Test(expected = org.json.JSONException.class)
    public void notJsonIsAnError() throws Exception {
        HaSetupServer.parse("url=192.0.2.10&token=abc");
    }
}
