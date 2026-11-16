package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.json.JSONObject;
import org.junit.Test;

/** Phone approval through the Hearth integration: what the TV makes of its answers. */
public class HaSwitchApprovalTest {
    private static final String ID = "0123456789abcdef0123456789abcdef";

    @Test
    public void aTakenRequestHasItsIdAndStatus() throws Exception {
        JSONObject body = new JSONObject().put("ok", true)
                .put("request", new JSONObject().put("id", ID).put("status", "pending"));
        HaIntegration.SwitchAnswer answer = HaIntegration.switchAnswer(200, body);
        assertEquals(ID, answer.id);
        assertEquals(HaIntegration.SWITCH_PENDING, answer.status);
        assertNull(answer.error);
        body.getJSONObject("request").put("status", "allowed");
        assertEquals(HaIntegration.SWITCH_ALLOWED, HaIntegration.switchAnswer(200, body).status);
    }

    @Test
    public void aMalformedIdIsNotTaken() throws Exception {
        JSONObject body = new JSONObject().put("request", new JSONObject().put("id", "../x").put("status", "allowed"));
        HaIntegration.SwitchAnswer answer = HaIntegration.switchAnswer(200, body);
        assertNull(answer.id);
        assertNull(answer.status);
        assertEquals("failed", answer.error);
    }

    @Test
    public void refusalsSayWhy() throws Exception {
        assertEquals("not_adult",
                HaIntegration.switchAnswer(403, new JSONObject().put("error", "not_adult")).error);
        assertEquals("no_phone", HaIntegration.switchAnswer(404, new JSONObject().put("error", "no_phone")).error);
        assertEquals("gone", HaIntegration.switchAnswer(404, new JSONObject().put("error", "gone")).error);
        // An integration from before it answers Home Assistant's own 404, without a JSON error: fall back
        assertEquals("unsupported", HaIntegration.switchAnswer(404, null).error);
        assertEquals("unreachable", HaIntegration.switchAnswer(0, null).error);
        assertEquals("not_paired", HaIntegration.switchAnswer(401, new JSONObject().put("error", "not_paired")).error);
        assertEquals("failed", HaIntegration.switchAnswer(500, null).error);
    }
}
