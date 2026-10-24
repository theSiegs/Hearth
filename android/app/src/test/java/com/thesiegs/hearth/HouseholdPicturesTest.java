package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.nio.file.Files;
import java.util.Collections;

import org.junit.Test;

/** Wallpaper pictures: kept once by hash, only JPEGs that match their name, and moved only to a TV that lacks them. */
public class HouseholdPicturesTest {
    private static final long T0 = 1_800_000_000_000L;

    private static byte[] jpeg(int seed) {
        byte[] bytes = new byte[2048];
        new java.util.Random(seed).nextBytes(bytes);
        bytes[0] = (byte) 0xFF;
        bytes[1] = (byte) 0xD8;
        bytes[2] = (byte) 0xFF;
        return bytes;
    }

    private static HouseholdPictures pictures() throws Exception {
        return new HouseholdPictures(Files.createTempDirectory("pictures").toFile());
    }

    @Test
    public void aPictureIsKeptByItsHashAndOnlyAPictureIs() throws Exception {
        HouseholdPictures pictures = pictures();
        byte[] picture = jpeg(1);
        String hash = pictures.write(picture, null);
        assertEquals(HouseholdPictures.hashOf(picture), hash);
        assertTrue(pictures.has(hash));
        assertArrayEquals(picture, pictures.read(hash));
        // not a JPEG, too big, or not what it's said to be
        assertNull(pictures.write(new byte[] {1, 2, 3, 4}, null));
        assertNull(pictures.write(new byte[HouseholdPictures.MAX_BYTES + 1], null));
        assertNull(pictures.write(jpeg(2), hash));
        // a name that isn't a hash points nowhere
        assertNull(pictures.file("../../shared_prefs/x"));
        assertFalse(pictures.has("../x"));
    }

    @Test
    public void picturesNoEntryNamesAreDeleted() throws Exception {
        HouseholdPictures pictures = pictures();
        String keep = pictures.write(jpeg(1), null);
        String drop = pictures.write(jpeg(2), null);
        pictures.keepOnly(Collections.singleton(keep));
        assertTrue(pictures.has(keep));
        assertFalse(pictures.has(drop));
        pictures.clear();
        assertFalse(pictures.has(keep));
    }

    /** Two TVs that have met; the first has a profile's wallpaper picture and its entry. */
    private static HouseholdTvs.Tv[] pairWithPicture(HouseholdPictures aPictures, byte[] picture) throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv b = new HouseholdTvs.Tv();
        b.store.join(a.store.invite("Office", T0), "Kitchen", T0);
        HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 1);
        String hash = aPictures.write(picture, null);
        a.store.log().put(HouseholdBridge.WALLPAPER, "a:alex", "day", HouseholdBridge.wallpaperValue(hash), T0 + 2);
        return new HouseholdTvs.Tv[] {a, b};
    }

    @Test
    public void aPictureMovesWithItsEntryOnceEitherWayRound() throws Exception {
        for (boolean ownerConnects : new boolean[] {true, false}) {
            HouseholdPictures aPictures = pictures();
            HouseholdPictures bPictures = pictures();
            byte[] picture = jpeg(7);
            HouseholdTvs.Tv[] tvs = pairWithPicture(aPictures, picture);
            String hash = HouseholdPictures.hashOf(picture);
            HouseholdSync.Result[] results = ownerConnects
                    ? HouseholdSyncExchangeTest.exchange(tvs[0].store, aPictures, tvs[1].store, bPictures, null, T0 + 100)
                    : HouseholdSyncExchangeTest.exchange(tvs[1].store, bPictures, tvs[0].store, aPictures, null, T0 + 100);
            assertTrue(bPictures.has(hash));
            assertArrayEquals(picture, bPictures.read(hash));
            assertEquals(1, results[ownerConnects ? 1 : 0].pictures);
            // the next exchange moves nothing: both have it
            HouseholdSync.Result[] again =
                    HouseholdSyncExchangeTest.exchange(tvs[0].store, aPictures, tvs[1].store, bPictures, null, T0 + 200);
            assertEquals(0, again[0].pictures + again[1].pictures);
        }
    }

    @Test
    public void aPictureNotHereYetComesWithALaterExchange() throws Exception {
        HouseholdPictures aPictures = pictures();
        HouseholdPictures bPictures = pictures();
        byte[] picture = jpeg(9);
        HouseholdTvs.Tv[] tvs = pairWithPicture(aPictures, picture);
        // the entry moves to b without its picture (a TV that keeps no pictures in between, say)
        HouseholdSyncExchangeTest.exchange(tvs[0].store, null, tvs[1].store, null, null, T0 + 100);
        assertFalse(bPictures.has(HouseholdPictures.hashOf(picture)));
        // b asks for it the next time it meets a TV that has it
        HouseholdSyncExchangeTest.exchange(tvs[1].store, bPictures, tvs[0].store, aPictures, null, T0 + 200);
        assertTrue(bPictures.has(HouseholdPictures.hashOf(picture)));
    }

    @Test
    public void aDeletedWallpaperNamesNoPicture() {
        HouseholdLog log = new HouseholdLog("tv-a");
        log.put(HouseholdBridge.WALLPAPER, "a:alex", "any", HouseholdBridge.wallpaperValue(HouseholdPictures.hashOf(jpeg(1))), T0);
        assertEquals(1, HouseholdBridge.pictures(log).size());
        log.delete(HouseholdBridge.WALLPAPER, "a:alex", "any", T0 + 1);
        assertTrue(HouseholdBridge.pictures(log).isEmpty());
        assertNull(HouseholdBridge.pictureOf("{\"hash\":\"../x\"}"));
        assertNull(HouseholdBridge.pictureOf("not json"));
    }

    @Test
    public void theFileIsInTheFolderGiven() throws Exception {
        File dir = Files.createTempDirectory("pictures").toFile();
        HouseholdPictures pictures = new HouseholdPictures(dir);
        String hash = pictures.write(jpeg(3), null);
        assertEquals(dir, pictures.file(hash).getParentFile());
    }
}
