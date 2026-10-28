package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** What a remote button runs on a Home Assistant entity, and which entities the button picker offers. */
public class HaApiTest {
    @Test
    public void scenesAndScriptsTurnOnButtonsPressTheRestToggle() {
        assertEquals("scene.turn_on", HaApi.serviceFor("scene"));
        assertEquals("script.turn_on", HaApi.serviceFor("script"));
        assertEquals("button.press", HaApi.serviceFor("button"));
        assertEquals("input_button.press", HaApi.serviceFor("input_button"));
        for (String domain : new String[]{"light", "switch", "fan", "input_boolean", "cover", "media_player",
                "automation"}) {
            assertEquals(domain, "homeassistant.toggle", HaApi.serviceFor(domain));
        }
    }

    @Test
    public void domainsAButtonCantActOnHaveNoService() {
        assertNull(HaApi.serviceFor("sensor"));
        assertNull(HaApi.serviceFor("person"));
        assertNull(HaApi.serviceFor("camera"));
        assertNull(HaApi.serviceFor(""));
        assertNull(HaApi.serviceFor("Light"));
    }

    @Test
    public void onlyTwoHundredsAreOk() {
        assertFalse(new HaApi.Response(0, null).ok());
        assertFalse(new HaApi.Response(199, null).ok());
        assertTrue(new HaApi.Response(200, new byte[0]).ok());
        assertTrue(new HaApi.Response(204, null).ok());
        assertFalse(new HaApi.Response(300, null).ok());
        assertFalse(new HaApi.Response(401, null).ok());
    }

    @Test
    public void actionableKeepsButtonEntitiesSortedByFriendlyName() throws Exception {
        JSONArray states = new JSONArray()
                .put(state("sensor.temperature", "Temperature"))
                .put(state("light.porch", "porch light"))
                .put(state("scene.movie_night", "Movie night"))
                .put(new JSONObject().put("entity_id", "switch.fan_plug").put("state", "off"))
                .put(state("person.alex", "Alex"))
                .put(state("script.bedtime", "Bedtime"));

        JSONArray result = HaApi.actionable(states.toString());

        assertEquals(4, result.length());
        // Case-insensitive by name; an entity without attributes is named by its id
        assertEquals("Bedtime", result.getJSONObject(0).getString("name"));
        assertEquals("Movie night", result.getJSONObject(1).getString("name"));
        assertEquals("porch light", result.getJSONObject(2).getString("name"));
        assertEquals("switch.fan_plug", result.getJSONObject(3).getString("name"));
        JSONObject scene = result.getJSONObject(1);
        assertEquals("scene.movie_night", scene.getString("entity_id"));
        assertEquals("scene", scene.getString("domain"));
    }

    @Test
    public void attributesWithoutAFriendlyNameFallBackToTheId() throws Exception {
        JSONArray states = new JSONArray().put(new JSONObject().put("entity_id", "fan.office")
                .put("attributes", new JSONObject().put("percentage", 50)));
        assertEquals("fan.office", HaApi.actionable(states.toString()).getJSONObject(0).getString("name"));
    }

    @Test
    public void anAnswerThatIsntAListGivesNothing() {
        assertEquals(0, HaApi.actionable("{\"message\": \"401: Unauthorized\"}").length());
        assertEquals(0, HaApi.actionable("not json").length());
        assertEquals(0, HaApi.actionable("[]").length());
    }

    private static JSONObject state(String id, String name) throws Exception {
        return new JSONObject().put("entity_id", id).put("state", "on")
                .put("attributes", new JSONObject().put("friendly_name", name));
    }
}
