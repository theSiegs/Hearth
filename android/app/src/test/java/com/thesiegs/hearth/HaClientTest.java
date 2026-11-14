package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import org.json.JSONObject;
import org.junit.Test;

/** Contract 3: the TV says which app it is in its pair and status bodies, and names no companions. */
public class HaClientTest {
    @Test
    public void theTvNamesItsOwnPackageVersionAndContract() throws Exception {
        JSONObject client = HaIntegration.clientJson("com.thesiegs.hearth", "2026.11.20");
        assertEquals("com.thesiegs.hearth", client.getString("id"));
        assertEquals("2026.11.20", client.getString("version"));
        assertEquals(3, client.getInt("contract"));
        assertFalse(client.has("companions"));
    }

    @Test
    public void anUnknownVersionIsLeftOut() throws Exception {
        JSONObject client = HaIntegration.clientJson("com.thesiegs.hearth", null);
        assertFalse(client.has("version"));
        assertEquals(HaIntegration.CONTRACT, client.getInt("contract"));
    }
}
