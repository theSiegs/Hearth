package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.io.FileOutputStream;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public class LegacyMoveTest {
    @Rule
    public TemporaryFolder temp = new TemporaryFolder();

    @Test
    public void theOldIdMatchesTheBuildType() {
        assertEquals("com.leanbitlab.ltvL", LegacyMove.legacyPackage("com.thesiegs.hearth"));
        assertEquals("com.leanbitlab.ltvL.debug", LegacyMove.legacyPackage("com.thesiegs.hearth.debug"));
        assertEquals("com.thesiegs.hearth", LegacyMove.newPackage("com.leanbitlab.ltvL"));
        assertEquals("com.thesiegs.hearth.debug", LegacyMove.newPackage("com.leanbitlab.ltvL.debug"));
        assertEquals("com.leanbitlab.ltvL.legacyexport", LegacyMove.authority("com.leanbitlab.ltvL"));
    }

    @Test
    public void settingsLayoutsWallpapersAndPinsMove() {
        assertTrue(LegacyMove.movable("shared_prefs/FlutterSharedPreferences.xml"));
        assertTrue(LegacyMove.movable("shared_prefs/ltv_device.xml"));       // Home Assistant, button mappings
        assertTrue(LegacyMove.movable("shared_prefs/profile_pairing.xml"));
        assertTrue(LegacyMove.movable("shared_prefs/pin_vault.xml"));        // turned into "enter again" entries
        assertTrue(LegacyMove.movable("app_flutter/db.sqlite"));
        assertTrue(LegacyMove.movable("app_flutter/profile_layouts/user_10.json"));
        assertTrue(LegacyMove.movable("files/selfadb/adbkey"));
        assertTrue(LegacyMove.movable("databases/anything.db"));
    }

    @Test
    public void agentStateAndTheMoveRecordStay() {
        assertFalse(LegacyMove.movable("shared_prefs/hearth_move.xml"));
        assertFalse(LegacyMove.movable("shared_prefs/ltv_agents.xml"));
        assertFalse(LegacyMove.movable("shared_prefs/ltv_agent.xml"));
        assertFalse(LegacyMove.movable("shared_prefs/ltv_agent_wallpaper.xml"));
        assertFalse(LegacyMove.movable("shared_prefs/hearth_wallpaper.xml"));
    }

    @Test
    public void nothingOutsideTheDataFoldersOrEscapingThem() {
        assertFalse(LegacyMove.movable(null));
        assertFalse(LegacyMove.movable(""));
        assertFalse(LegacyMove.movable("cache/posters/1.jpg"));
        assertFalse(LegacyMove.movable("code_cache/x"));
        assertFalse(LegacyMove.movable("app_webview/Cookies"));
        assertFalse(LegacyMove.movable("shared_prefs"));
        assertFalse(LegacyMove.movable("/data/data/com.leanbitlab.ltvL/shared_prefs/x.xml"));
        assertFalse(LegacyMove.movable("files/../cache/x"));
        assertFalse(LegacyMove.movable("files/./x"));
        assertFalse(LegacyMove.movable("files//x"));
        assertFalse(LegacyMove.movable("files\\x"));
        assertFalse(LegacyMove.movable("shared_prefsx/a.xml"));
    }

    @Test
    public void listsEveryMovableFile() throws Exception {
        File data = temp.newFolder("data");
        touch(data, "shared_prefs/FlutterSharedPreferences.xml");
        touch(data, "shared_prefs/ltv_agents.xml");
        touch(data, "app_flutter/db.sqlite");
        touch(data, "app_flutter/wallpapers/profile_1/a.jpg");
        touch(data, "files/profile_avatars_v3/Alex.png");
        touch(data, "cache/posters/p.jpg");
        List<String> files = LegacyMove.movableFiles(data);
        Collections.sort(files);
        assertEquals(Arrays.asList(
                "app_flutter/db.sqlite",
                "app_flutter/wallpapers/profile_1/a.jpg",
                "files/profile_avatars_v3/Alex.png",
                "shared_prefs/FlutterSharedPreferences.xml"), files);
    }

    private static void touch(File root, String path) throws Exception {
        File file = new File(root, path);
        file.getParentFile().mkdirs();
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(1);
        }
    }
}
