package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** What Hearth makes in Home Assistant for a TV's status. */
public class HaProvisionTest {
    @Test
    public void aTvsNameBecomesASafeSlug() {
        assertEquals("den", HaProvision.slug("Den"));
        assertEquals("living_room", HaProvision.slug("  Living Room!  "));
        assertEquals("tv", HaProvision.slug("???"));
        assertEquals("tv", HaProvision.slug(null));
        assertTrue(HaProvision.slug("x".repeat(80)).length() <= 30);
    }

    @Test
    public void everyTvGetsItsOwnUnguessableWebhookId() {
        String a = HaProvision.newWebhookId("living_room");
        String b = HaProvision.newWebhookId("living_room");
        assertTrue(a.matches("hearth-living-room-[0-9a-f]{12}"));
        assertNotEquals(a, b);
    }

    @Test
    public void theAutomationListensOnThatWebhookAndOnlyOnTheLocalNetwork() throws Exception {
        JSONObject automation = HaProvision.automation("Den", "den", "hearth-den-abc123abc123");
        JSONObject trigger = automation.getJSONArray("triggers").getJSONObject(0);
        assertEquals("webhook", trigger.getString("trigger"));
        assertEquals("hearth-den-abc123abc123", trigger.getString("webhook_id"));
        assertTrue(trigger.getBoolean("local_only"));
        assertEquals("POST", trigger.getJSONArray("allowed_methods").getString(0));
        assertEquals("Den TV - Status from Hearth", automation.getString("alias"));
        assertEquals("queued", automation.getString("mode"));
    }

    @Test
    public void theAutomationWritesOnlyToThisTvsHelpers() throws Exception {
        String text = HaProvision.automation("Den", "den", "hearth-den-abc123abc123").toString();
        for (HaProvision.Helper helper : HaProvision.HELPERS) {
            assertTrue(helper.entityId("den") + " is written", text.contains(helper.entityId("den")));
        }
        assertTrue(!text.contains("family_room"));
        assertEquals(7, HaProvision.HELPERS.length);
    }

    @Test
    public void anExistingAutomationKeepsItsWebhook() throws Exception {
        JSONObject made = HaProvision.automation("Den", "den", "hearth-den-keepme");
        assertEquals("hearth-den-keepme", HaProvision.webhookOf(made));
        // Older Home Assistant wrote "platform" instead of "trigger"
        JSONObject old = new JSONObject().put("triggers", new JSONArray().put(
                new JSONObject().put("platform", "webhook").put("webhook_id", "x-1")));
        assertEquals("x-1", HaProvision.webhookOf(old));
        assertNull(HaProvision.webhookOf(new JSONObject().put("triggers", new JSONArray())));
        assertNull(HaProvision.webhookOf(null));
    }

    @Test
    public void helpersAreMadeTheWayHomeAssistantsEditorMakesThem() throws Exception {
        JSONObject select = HaProvision.createMessage(HaProvision.HELPERS[0], "Den");
        assertEquals("input_select/create", select.getString("type"));
        assertEquals("Den TV State", select.getString("name"));
        assertEquals(4, select.getJSONArray("options").length());
        JSONObject text = HaProvision.createMessage(HaProvision.HELPERS[4], "Den");
        assertEquals("input_text/create", text.getString("type"));
        assertEquals(100, text.getInt("max"));
        assertEquals("input_boolean/create", HaProvision.createMessage(HaProvision.HELPERS[5], "Den").getString("type"));
        assertEquals("input_select.den_tv_state", HaProvision.HELPERS[0].entityId("den"));
    }
}
