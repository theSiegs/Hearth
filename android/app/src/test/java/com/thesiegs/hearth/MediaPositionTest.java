package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;

import android.media.session.PlaybackState;

import org.junit.Test;

/** The media position a TV's status gives the integration: from any app's session (HearthTube's too), sent no more often. */
public class MediaPositionTest {
    private static final String APP = "com.example.player";
    private static final long WALL = 1_700_000_000_000L;
    private static final long ELAPSED = 500_000L;

    @Test
    public void theSessionsLastUpdateIsWhenThePositionWasTrue() {
        // Updated 3 s ago at 60 s in: 60 s as of 3 s ago, not moved on (the integration does that)
        HaStatusReporter.MediaPosition p = HaStatusReporter.MediaPosition.of(null, APP, PlaybackState.STATE_PLAYING,
                60_000, 1f, ELAPSED - 3_000, ELAPSED, WALL);
        assertEquals(60_000, p.positionMs);
        assertEquals(WALL - 3_000, p.at);
        // A session that doesn't say when: as of now
        p = HaStatusReporter.MediaPosition.of(null, APP, PlaybackState.STATE_PAUSED, 60_000, 0f, 0, ELAPSED, WALL);
        assertEquals(60_000, p.positionMs);
        assertEquals(WALL, p.at);
    }

    @Test
    public void anUnknownPositionIsNone() {
        assertNull(HaStatusReporter.MediaPosition.of(null, APP, PlaybackState.STATE_PLAYING,
                PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f, ELAPSED, ELAPSED, WALL));
    }

    @Test
    public void aSessionThatOnlyRefreshesItsPositionKeepsTheLastOne() {
        HaStatusReporter.MediaPosition first = HaStatusReporter.MediaPosition.of(null, APP,
                PlaybackState.STATE_PLAYING, 60_000, 1f, ELAPSED, ELAPSED, WALL);
        // 30 s later the session says 30 s further on: the same play, so the status doesn't change
        assertSame(first, HaStatusReporter.MediaPosition.of(first, APP, PlaybackState.STATE_PLAYING,
                90_000, 1f, ELAPSED + 30_000, ELAPSED + 30_000, WALL + 30_000));
        // Paused, with no update time: built again each status, still the same one
        HaStatusReporter.MediaPosition paused = HaStatusReporter.MediaPosition.of(null, APP,
                PlaybackState.STATE_PAUSED, 60_000, 0f, 0, ELAPSED, WALL);
        assertSame(paused, HaStatusReporter.MediaPosition.of(paused, APP, PlaybackState.STATE_PAUSED,
                60_000, 0f, 0, ELAPSED + 120_000, WALL + 120_000));
        // At double speed it moves twice as fast
        HaStatusReporter.MediaPosition fast = HaStatusReporter.MediaPosition.of(null, APP,
                PlaybackState.STATE_PLAYING, 60_000, 2f, ELAPSED, ELAPSED, WALL);
        assertSame(fast, HaStatusReporter.MediaPosition.of(fast, APP, PlaybackState.STATE_PLAYING,
                80_000, 2f, ELAPSED + 10_000, ELAPSED + 10_000, WALL + 10_000));
    }

    @Test
    public void aSeekPauseOrOtherAppIsANewPosition() {
        HaStatusReporter.MediaPosition first = HaStatusReporter.MediaPosition.of(null, APP,
                PlaybackState.STATE_PLAYING, 60_000, 1f, ELAPSED, ELAPSED, WALL);
        HaStatusReporter.MediaPosition seek = HaStatusReporter.MediaPosition.of(first, APP,
                PlaybackState.STATE_PLAYING, 600_000, 1f, ELAPSED + 5_000, ELAPSED + 5_000, WALL + 5_000);
        assertNotSame(first, seek);
        assertEquals(600_000, seek.positionMs);
        assertEquals(WALL + 5_000, seek.at);
        assertNotSame(first, HaStatusReporter.MediaPosition.of(first, APP, PlaybackState.STATE_PAUSED,
                65_000, 0f, ELAPSED + 5_000, ELAPSED + 5_000, WALL + 5_000));
        assertNotSame(first, HaStatusReporter.MediaPosition.of(first, "com.example.other",
                PlaybackState.STATE_PLAYING, 65_000, 1f, ELAPSED + 5_000, ELAPSED + 5_000, WALL + 5_000));
    }
}
