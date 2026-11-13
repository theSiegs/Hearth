package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import org.json.JSONObject;
import org.junit.Test;

/** The integration's long-poll: what the TV asks for, and how it reads the answer. */
public class HaWaitTest {
    private static final String BASE = "https://ha.example:8123";

    @Test
    public void asksForItsOwnDocumentWithTheVersionItHolds() {
        assertEquals(BASE + "/api/hearth/device/tv_1234abcd/wait?timeout=50&version=0f3a9c2e11d4b5a6",
                HaIntegration.waitUrl(BASE, "tv_1234abcd", "0f3a9c2e11d4b5a6", 50));
    }

    @Test
    public void withoutAVersionItAsksForAnyChange() {
        assertEquals(BASE + "/api/hearth/device/tv_1234abcd/wait?timeout=50",
                HaIntegration.waitUrl(BASE, "tv_1234abcd", null, 50));
        // Anything that isn't the document's hex hash is never put in the address
        assertEquals(BASE + "/api/hearth/device/tv_1234abcd/wait?timeout=50",
                HaIntegration.waitUrl(BASE, "tv_1234abcd", "a&b=c", 50));
    }

    @Test
    public void readsTheAnswer() throws Exception {
        assertEquals(HaIntegration.WaitResult.CHANGED,
                HaIntegration.waitResult(200, new JSONObject().put("changed", true)));
        assertEquals(HaIntegration.WaitResult.NOT_CHANGED,
                HaIntegration.waitResult(200, new JSONObject().put("changed", false)));
        // An older integration has no long-poll: the TV keeps its two-minute post
        assertEquals(HaIntegration.WaitResult.UNSUPPORTED, HaIntegration.waitResult(404, null));
        assertEquals(HaIntegration.WaitResult.FAILED, HaIntegration.waitResult(503, null));
        assertEquals(HaIntegration.WaitResult.FAILED, HaIntegration.waitResult(0, null));
    }
}
