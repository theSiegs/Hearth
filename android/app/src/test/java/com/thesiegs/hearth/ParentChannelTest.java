package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

/** The parent channel's two stores (contract 8): the log of started videos, and the parent's blocked lists. */
public class ParentChannelTest {
    private static StartedLog.Entry entry(long t, String id) {
        return new StartedLog.Entry(t, id, "Title", "Channel", "UCchannel1");
    }

    @Test
    public void aStartNeedsATimeAndAnIdThatLooksLikeOne() {
        assertTrue(StartedLog.valid(1_000, "abc123_-XYZ"));
        assertFalse(StartedLog.valid(0, "abc123"));
        assertFalse(StartedLog.valid(1_000, null));
        assertFalse(StartedLog.valid(1_000, "abc"));
        assertFalse(StartedLog.valid(1_000, "abc 123"));
        assertFalse(StartedLog.valid(1_000, "a/../../b"));
    }

    @Test
    public void textFromAnotherAppIsCleanedAndCut() {
        assertEquals("a b", StartedLog.clean("a\nb"));
        assertEquals("", StartedLog.clean(null));
        assertEquals(300, StartedLog.clean(new String(new char[1000]).replace('\0', 'x')).length());
    }

    @Test
    public void theSameStartSentTwiceIsOneEntry() {
        List<StartedLog.Entry> entries = new ArrayList<>();

        assertTrue(StartedLog.add(entries, entry(5_000, "video1")));
        assertFalse(StartedLog.add(entries, entry(5_000, "video1")));
        assertEquals(1, entries.size());
    }

    @Test
    public void aLateArrivalGoesInItsPlaceByTime() {
        List<StartedLog.Entry> entries = new ArrayList<>();
        StartedLog.add(entries, entry(1_000, "video1"));
        StartedLog.add(entries, entry(3_000, "video3"));
        StartedLog.add(entries, entry(2_000, "video2"));

        assertEquals("video1", entries.get(0).videoId);
        assertEquals("video2", entries.get(1).videoId);
        assertEquals("video3", entries.get(2).videoId);
    }

    @Test
    public void onlyTheNewestAreKept() {
        List<StartedLog.Entry> entries = new ArrayList<>();
        for (int i = 1; i <= StartedLog.MAX + 5; i++) StartedLog.add(entries, entry(i * 1_000L, "video" + i));

        assertEquals(StartedLog.MAX, entries.size());
        assertEquals("video6", entries.get(0).videoId);
    }

    @Test
    public void anEntrySurvivesBeingSaved() throws Exception {
        StartedLog.Entry back = StartedLog.Entry.of(entry(7_000, "video7").toJson());

        assertEquals(7_000, back.timeMs);
        assertEquals("video7", back.videoId);
        assertEquals("Channel", back.channel);
        assertEquals("UCchannel1", back.channelId);
        assertNull(StartedLog.Entry.of(new JSONObject()));
    }

    @Test
    public void blockedListsKeepOnlyWhatIsValid() throws Exception {
        ParentBlocks.Lists lists = ParentBlocks.parse(new JSONObject(
                "{\"videos\":[\"abc123\",\"bad id\",\"abc123\"],\"channels\":[\"UCchannel1\",\"\"],\"words\":[\" Foo \",\"\",\"BAR\"]}"));

        assertEquals(1, lists.videos.size());
        assertEquals(1, lists.channels.size());
        assertEquals("[foo, bar]", lists.words.toString());
    }

    @Test
    public void nothingBlockedIsEmpty() {
        assertTrue(ParentBlocks.parse(null).isEmpty());
        assertTrue(ParentBlocks.parse(new JSONObject()).isEmpty());
    }

    @Test
    public void hearthsListsAndHomeAssistantsAreOneListTogether() throws Exception {
        ParentBlocks.Lists own = ParentBlocks.parse(new JSONObject("{\"videos\":[\"video1\"],\"words\":[\"one\"]}"));
        ParentBlocks.Lists ha = ParentBlocks.parse(new JSONObject("{\"videos\":[\"video1\",\"video2\"],\"channels\":[\"UCchannel1\"]}"));
        ParentBlocks.Lists all = own.union(ha);

        assertEquals("[video1, video2]", all.videos.toString());
        assertEquals("[UCchannel1]", all.channels.toString());
        assertEquals("[one]", all.words.toString());
        assertEquals(all, ha.union(own).union(own));
    }
}
