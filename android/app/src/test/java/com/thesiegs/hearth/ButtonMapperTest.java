package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.view.KeyEvent;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Test;

import java.util.Map;

/** Remote button remapping: which keys may be remapped, what is stored, and what a press runs. */
public class ButtonMapperTest {
    @Test
    public void navigationAndPowerKeysCantBeRemapped() {
        int[] fixed = {KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME, KeyEvent.KEYCODE_POWER,
                KeyEvent.KEYCODE_SLEEP, KeyEvent.KEYCODE_WAKEUP, KeyEvent.KEYCODE_UNKNOWN};
        for (int key : fixed) assertFalse("key " + key, ButtonMapper.isRemappable(key));
    }

    @Test
    public void appAndMediaKeysCanBeRemapped() {
        int[] free = {KeyEvent.KEYCODE_PROFILE_SWITCH, KeyEvent.KEYCODE_TV_INPUT, KeyEvent.KEYCODE_BOOKMARK,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_SEARCH, KeyEvent.KEYCODE_SETTINGS,
                KeyEvent.KEYCODE_PROG_RED};
        for (int key : free) assertTrue("key " + key, ButtonMapper.isRemappable(key));
    }

    @Test
    public void cleanedDropsKeysThatMayNotBeRemapped() throws Exception {
        JSONObject press = new JSONObject().put("short", new JSONObject().put("type", "home"));
        String json = new JSONObject()
                .put(String.valueOf(KeyEvent.KEYCODE_BOOKMARK), press)
                .put(String.valueOf(KeyEvent.KEYCODE_HOME), press)
                .put(String.valueOf(KeyEvent.KEYCODE_BACK), press)
                .toString();

        JSONObject cleaned = ButtonMapper.cleaned(json);

        assertEquals(1, cleaned.length());
        assertEquals("home", cleaned.getJSONObject(String.valueOf(KeyEvent.KEYCODE_BOOKMARK))
                .getJSONObject("short").getString("type"));
    }

    @Test
    public void cleanedRefusesWhatIsntAMapping() {
        assertThrows(JSONException.class, () -> ButtonMapper.cleaned("not json"));
        // A key's value must be an object
        assertThrows(JSONException.class, () -> ButtonMapper.cleaned("{\"174\": \"home\"}"));
        // Keys are key codes
        assertThrows(NumberFormatException.class, () -> ButtonMapper.cleaned("{\"home\": {}}"));
    }

    @Test
    public void actionsHasOnlyThePressesThatAreSet() throws Exception {
        JSONObject shortOnly = new JSONObject().put("short", new JSONObject().put("type", "settings"))
                .put("homeOnly", true);
        Map<String, JSONObject> actions = ButtonMapper.actions(shortOnly);
        assertEquals(1, actions.size());
        assertEquals("settings", actions.get(ButtonMapper.PRESS_SHORT).getString("type"));

        JSONObject both = new JSONObject().put("short", new JSONObject().put("type", "home"))
                .put("long", new JSONObject().put("type", "sleep"));
        assertEquals("sleep", ButtonMapper.actions(both).get(ButtonMapper.PRESS_LONG).getString("type"));
    }

    @Test
    public void anEntryWithoutPressesIsntRemapped() throws Exception {
        assertNull(ButtonMapper.actions(null));
        assertNull(ButtonMapper.actions(new JSONObject()));
        // Only the name left (both presses restored), or a press that isn't an action
        assertNull(ButtonMapper.actions(new JSONObject().put("name", "KEYCODE_BOOKMARK").put("short", "home")));
    }

    @Test
    public void theProfileButtonOpensTheChooserAndAHoldLocks() throws Exception {
        JSONObject seeded = ButtonMapper.profileButtonDefault();
        assertEquals("profiles", seeded.getJSONObject(ButtonMapper.PRESS_SHORT).getString("type"));
        assertEquals("lock", seeded.getJSONObject(ButtonMapper.PRESS_LONG).getString("type"));
        assertEquals(2, ButtonMapper.actions(seeded).size());
    }

    @Test
    public void aHomeAssistantButtonCallsTheServiceForItsDomain() {
        assertArrayEquals(new String[]{"homeassistant", "toggle"}, ButtonMapper.haCall("light.porch"));
        assertArrayEquals(new String[]{"scene", "turn_on"}, ButtonMapper.haCall("scene.movie_night"));
        assertArrayEquals(new String[]{"input_button", "press"}, ButtonMapper.haCall("input_button.doorbell"));
    }

    @Test
    public void aHomeAssistantButtonDoesNothingForOtherEntities() {
        assertNull(ButtonMapper.haCall("sensor.temperature"));
        assertNull(ButtonMapper.haCall("light"));
        assertNull(ButtonMapper.haCall(""));
    }
}
