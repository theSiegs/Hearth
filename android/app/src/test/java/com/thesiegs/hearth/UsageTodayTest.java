package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Calendar;

import org.junit.Test;

/** Today's usage for Home Assistant, and the screen time unlock as a moment. */
public class UsageTodayTest {
    private static long at(int year, int month, int day, int hour, int minute) {
        Calendar c = Calendar.getInstance();
        c.clear();
        c.set(year, month - 1, day, hour, minute, 0);
        return c.getTimeInMillis();
    }

    @Test
    public void anIntervalOverMidnightCountsOnlyItsNewDayPart() {
        long tenPast = at(2026, 10, 11, 0, 10);
        // 30 minutes ending ten past midnight: ten of them are today's
        assertEquals(10 * 60_000L, UsageToday.sinceMidnight(30 * 60_000L, tenPast));
        long evening = at(2026, 10, 10, 20, 0);
        assertEquals(30 * 60_000L, UsageToday.sinceMidnight(30 * 60_000L, evening));
        assertEquals("2026-10-10", UsageToday.day(evening));
        assertEquals("2026-10-11", UsageToday.day(tenPast));
    }

    @Test
    public void hearthsOwnLimitWorksWithoutHomeAssistant() {
        // 60 minutes a day, 25 played: 35 left, Hearth's say
        Allowance.Values v = Allowance.combine(60, 25 * 60_000L, null, false, null, null);
        assertEquals(Integer.valueOf(35), v.youtubeMinutesLeft);
        assertEquals(Allowance.SOURCE_HEARTH, v.source);
        assertNull(v.checkedAt);
        // Played past it: none left, never negative
        assertEquals(Integer.valueOf(0), Allowance.combine(60, 90 * 60_000L, null, false, null, null).youtubeMinutesLeft);
        // No limit anywhere
        Allowance.Values none = Allowance.combine(0, 25 * 60_000L, null, false, null, null);
        assertNull(none.youtubeMinutesLeft);
        assertNull(none.source);
    }

    @Test
    public void withHomeAssistantTheStricterLimitCounts() {
        // Home Assistant's shared pool has less left than Hearth's own limit: its say, with its message
        Allowance.Values pool = Allowance.combine(60, 10 * 60_000L, 20, false, "Shared with your phone", 5L);
        assertEquals(Integer.valueOf(20), pool.youtubeMinutesLeft);
        assertEquals(Allowance.SOURCE_HOME_ASSISTANT, pool.source);
        assertEquals("Shared with your phone", pool.message);
        // Hearth's own has less left
        Allowance.Values own = Allowance.combine(60, 50 * 60_000L, 20, false, "Shared with your phone", 5L);
        assertEquals(Integer.valueOf(10), own.youtubeMinutesLeft);
        assertEquals(Allowance.SOURCE_HEARTH, own.source);
        assertNull(own.message);
        // Only Home Assistant has a limit, or a schedule lock
        assertEquals(Integer.valueOf(20), Allowance.combine(0, 0, 20, false, null, 5L).youtubeMinutesLeft);
        Allowance.Values locked = Allowance.combine(0, 0, null, true, "Bedtime", 5L);
        assertTrue(locked.scheduleLocked);
        assertNull(locked.youtubeMinutesLeft);
        assertEquals("Bedtime", locked.message);
    }

    @Test
    public void theUnlockTimeIsTheNextSuchMoment() {
        long bedtime = at(2026, 10, 10, 21, 5);
        String iso = ScreenTimeScreen.unlocksAtIso("7:00 AM", bedtime);
        assertTrue(iso, iso.startsWith("2026-10-11T07:00:00"));
        // Later the same day
        assertTrue(ScreenTimeScreen.unlocksAtIso("9:30 p.m.", bedtime).startsWith("2026-10-10T21:30:00"));
        assertTrue(ScreenTimeScreen.unlocksAtIso("12 PM", bedtime).startsWith("2026-10-11T12:00:00"));
        assertTrue(ScreenTimeScreen.unlocksAtIso("06:15", bedtime).startsWith("2026-10-11T06:15:00"));
        // With the TV's UTC offset
        assertTrue(iso, iso.matches(".*[+-]\\d\\d:\\d\\d$"));
        assertNull(ScreenTimeScreen.unlocksAtIso("tomorrow", bedtime));
        assertNull(ScreenTimeScreen.unlocksAtIso("13 PM", bedtime));
        assertNull(ScreenTimeScreen.unlocksAtIso(null, bedtime));
    }
}
