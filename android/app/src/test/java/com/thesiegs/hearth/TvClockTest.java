package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import java.util.Calendar;

import org.junit.Test;

/** The TV's clock set by hand doesn't start a new day, end a wait or put bedtime off; the network's clock is believed. */
public class TvClockTest {
    private static final long MIN = 60_000L;
    private static final long HOUR = 60 * MIN;
    /** 3 PM on some day, local time. */
    private static final long AFTERNOON = at(15);
    private static final int BOOT = 7;

    private static long at(int hour) {
        Calendar day = Calendar.getInstance();
        day.set(2026, Calendar.MARCH, 10, hour, 0, 0);
        day.set(Calendar.MILLISECOND, 0);
        return day.getTimeInMillis();
    }

    private static long time(TvClock.State state, long wall) {
        return wall - state.skew;
    }

    @Test
    public void theClockRunningOnIsTheTime_andMidnightComes() {
        TvClock.State start = TvClock.step(null, AFTERNOON, 1_000, BOOT, false);
        assertEquals(0, start.skew);
        // Ten hours later, by the clock and by the time the TV ran: tomorrow
        TvClock.State later = TvClock.step(start, AFTERNOON + 10 * HOUR, 1_000 + 10 * HOUR, BOOT, false);
        assertEquals(0, later.skew);
        assertNotEquals(UsageToday.day(AFTERNOON), UsageToday.day(time(later, AFTERNOON + 10 * HOUR)));
    }

    @Test
    public void setADayAheadByHand_itIsStillToday() {
        TvClock.State start = TvClock.step(null, AFTERNOON, 1_000, BOOT, true);
        // Automatic time off, the date set to tomorrow, half a minute later
        long wall = AFTERNOON + 24 * HOUR + 30_000;
        TvClock.State jumped = TvClock.step(start, wall, 31_000, BOOT, false);
        assertEquals(24 * HOUR, jumped.skew);
        assertEquals(AFTERNOON + 30_000, time(jumped, wall));
        assertEquals(UsageToday.day(AFTERNOON), UsageToday.day(time(jumped, wall)));
        // It stays so as the TV runs on, and the real midnight still starts the next day
        TvClock.State evening = TvClock.step(jumped, wall + 5 * HOUR, 31_000 + 5 * HOUR, BOOT, false);
        assertEquals(UsageToday.day(AFTERNOON), UsageToday.day(time(evening, wall + 5 * HOUR)));
        TvClock.State night = TvClock.step(evening, wall + 10 * HOUR, 31_000 + 10 * HOUR, BOOT, false);
        assertEquals(UsageToday.day(AFTERNOON + 24 * HOUR), UsageToday.day(time(night, wall + 10 * HOUR)));
    }

    @Test
    public void setBackBeforeBedtime_bedtimeStillComesOnTime() {
        TvClock.State start = TvClock.step(null, at(19), 1_000, BOOT, false);
        // 7 PM, the clock set back to 3 PM; an hour on, bedtime (8 PM) has come
        long wall = at(15) + HOUR;
        TvClock.State later = TvClock.step(start, wall, 1_000 + HOUR, BOOT, false);
        assertEquals(-4 * HOUR, later.skew);
        assertEquals(at(20), time(later, wall));
    }

    @Test
    public void setBackToWhereItWas_nothingIsTakenOff() {
        TvClock.State start = TvClock.step(null, AFTERNOON, 1_000, BOOT, false);
        TvClock.State jumped = TvClock.step(start, AFTERNOON + 3 * HOUR + MIN, 1_000 + MIN, BOOT, false);
        assertEquals(3 * HOUR, jumped.skew);
        TvClock.State back = TvClock.step(jumped, AFTERNOON + 2 * MIN + 5_000, 1_000 + 2 * MIN, BOOT, false);
        assertEquals(0, back.skew);
    }

    @Test
    public void smallStepsByHandAddUp() {
        TvClock.State state = TvClock.step(null, AFTERNOON, 1_000, BOOT, false);
        long wall = AFTERNOON;
        long elapsed = 1_000;
        // 90 seconds ahead at a time, each under the tolerance
        for (int i = 0; i < 4; i++) {
            wall += 90_000 + 5_000;
            elapsed += 5_000;
            state = TvClock.step(state, wall, elapsed, BOOT, false);
        }
        assertEquals(AFTERNOON + 20_000, time(state, wall));
    }

    @Test
    public void theNetworkSettingTheClockIsBelieved() {
        // A stick that woke with the time it lost power at, then got the time from the network
        TvClock.State start = TvClock.step(null, AFTERNOON, 1_000, BOOT, true);
        TvClock.State synced = TvClock.step(start, AFTERNOON + 8 * HOUR, 20_000, BOOT, true);
        assertEquals(0, synced.skew);
        assertEquals(AFTERNOON + 8 * HOUR, synced.wall);
    }

    @Test
    public void automaticTimeBackOn_theSkewEndsWhenTheNetworkSetsTheClock() {
        TvClock.State start = TvClock.step(null, AFTERNOON, 1_000, BOOT, true);
        TvClock.State jumped = TvClock.step(start, AFTERNOON + 24 * HOUR, 1_000, BOOT, false);
        // Automatic time on again with no network: the clock is still a day ahead, and still not believed
        long wall = AFTERNOON + 24 * HOUR + 5 * MIN;
        TvClock.State offline = TvClock.step(jumped, wall, 1_000 + 5 * MIN, BOOT, true);
        assertEquals(24 * HOUR, offline.skew);
        // The network is back and sets it right
        TvClock.State synced = TvClock.step(offline, AFTERNOON + 6 * MIN, 1_000 + 6 * MIN, BOOT, true);
        assertEquals(0, synced.skew);
    }

    @Test
    public void aRestartMeasuresNothing_andKeepsTheSkewOnlyWhileAutomaticTimeIsOff() {
        TvClock.State start = TvClock.step(null, AFTERNOON, 5 * HOUR, BOOT, true);
        // Off overnight: the clock is 8 hours on, the time since boot starts again. Not a jump.
        TvClock.State morning = TvClock.step(start, AFTERNOON + 8 * HOUR, 30_000, BOOT + 1, false);
        assertEquals(0, morning.skew);
        // Even when the new boot has run longer than the old one had
        assertEquals(0, TvClock.step(start, AFTERNOON + 8 * HOUR, 6 * HOUR, BOOT + 1, false).skew);

        TvClock.State jumped = TvClock.step(start, AFTERNOON + 24 * HOUR, 5 * HOUR, BOOT, false);
        assertEquals(24 * HOUR, TvClock.step(jumped, AFTERNOON + 24 * HOUR + MIN, 30_000, BOOT + 1, false).skew);
        assertEquals(0, TvClock.step(jumped, AFTERNOON + 24 * HOUR + MIN, 30_000, BOOT + 1, true).skew);
    }

    @Test
    public void driftIsNeverASkew_andTheNetworksClockIsFollowed() {
        TvClock.State state = TvClock.step(null, AFTERNOON, 1_000, BOOT, true);
        // Read again within the minute: nothing to keep
        assertSame(state, TvClock.step(state, AFTERNOON + 10_000, 11_000, BOOT, true));
        long wall = AFTERNOON;
        long elapsed = 1_000;
        // A clock that gains a minute every hour, for a day
        for (int i = 0; i < 24; i++) {
            wall += HOUR + MIN;
            elapsed += HOUR;
            state = TvClock.step(state, wall, elapsed, BOOT, true);
            assertEquals(0, state.skew);
        }
        assertEquals(wall, state.wall);
    }

    @Test
    public void withoutABootCountTheClockIsTakenAsItIs() {
        // Plain JUnit's android.jar has no settings: no boot count, nothing measured
        FakeContext context = new FakeContext("com.thesiegs.hearth");
        long before = System.currentTimeMillis();
        long now = TvClock.now(context);
        assertTrue(now >= before && now <= System.currentTimeMillis());
        assertEquals(1_000, TvClock.toWall(context, 1_000), 50);
    }
}
