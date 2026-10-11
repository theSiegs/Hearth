package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.Calendar;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.junit.Test;

/** The data use's periods, whose data a uid is, and the app list Flutter gets. */
public class DataUsageTest {
    private static Calendar at(int year, int month, int day, int hour) {
        Calendar c = Calendar.getInstance(Locale.US);
        c.clear();
        c.set(year, month - 1, day, hour, 30, 15);
        return c;
    }

    private static long midnight(int year, int month, int day) {
        Calendar c = Calendar.getInstance(Locale.US);
        c.clear();
        c.set(year, month - 1, day, 0, 0, 0);
        return c.getTimeInMillis();
    }

    @Test
    public void periodsStartAtMidnightOfTheDayWeekOrMonth() {
        // Saturday, October 10, 2026; US weeks start on Sunday the 4th
        assertEquals(midnight(2026, 10, 10), DataUsage.periodStart("daily", at(2026, 10, 10, 20)));
        assertEquals(midnight(2026, 10, 4), DataUsage.periodStart("weekly", at(2026, 10, 10, 20)));
        assertEquals(midnight(2026, 10, 1), DataUsage.periodStart("monthly", at(2026, 10, 10, 20)));
        // The week's first day is its own week's start; weeks starting on Monday go back to Monday the 5th
        assertEquals(midnight(2026, 10, 4), DataUsage.periodStart("weekly", at(2026, 10, 4, 9)));
        Calendar germany = Calendar.getInstance(Locale.GERMANY);
        germany.setTimeInMillis(at(2026, 10, 10, 20).getTimeInMillis());
        assertEquals(midnight(2026, 10, 5), DataUsage.periodStart("weekly", germany));
        // Anything else is today
        assertEquals(midnight(2026, 10, 10), DataUsage.periodStart(null, at(2026, 10, 10, 20)));
        assertEquals("weekly", DataUsage.periodOfMethod("getWeeklyDataUsage"));
        assertEquals("monthly", DataUsage.periodOfMethod("getMonthlyDataUsage"));
        assertEquals("daily", DataUsage.periodOfMethod("getDailyDataUsage"));
    }

    @Test
    public void uidsAreAppsAndroidOrOther() {
        assertEquals(DataUsage.KIND_APP, DataUsage.kindOf(10113));
        // The same app in a kids profile (Android user 11)
        assertEquals(DataUsage.KIND_APP, DataUsage.kindOf(1110113));
        assertEquals(DataUsage.KIND_SYSTEM, DataUsage.kindOf(1000));
        assertEquals(DataUsage.KIND_SYSTEM, DataUsage.kindOf(0));
        assertEquals(DataUsage.KIND_SYSTEM, DataUsage.kindOf(1101000));
        assertEquals(DataUsage.KIND_OTHER, DataUsage.kindOf(DataUsage.UID_REMOVED));
        assertEquals(DataUsage.KIND_OTHER, DataUsage.kindOf(DataUsage.UID_TETHERING));
    }

    @Test
    public void aSharedUidIsNamedForItsFirstPackage() {
        assertNull(DataUsage.packageOf(null));
        assertNull(DataUsage.packageOf(new String[0]));
        assertEquals("com.example.tv", DataUsage.packageOf(new String[] {"com.example.tv"}));
        assertEquals("com.example.a", DataUsage.packageOf(new String[] {"com.example.b", "com.example.a"}));
    }

    @Test
    public void entriesComeLargestFirstWithAndroidAndOtherAsOneEach() {
        Map<String, Long> sums = new HashMap<>();
        DataUsage.add(sums, "com.example.tv", 5_000);
        DataUsage.add(sums, DataUsage.KIND_SYSTEM, 300);
        DataUsage.add(sums, DataUsage.KIND_SYSTEM, 200);
        DataUsage.add(sums, "com.example.music", 9_000);
        DataUsage.add(sums, DataUsage.KIND_OTHER, 0);
        Map<String, String> labels = new HashMap<>();
        labels.put("com.example.tv", "Example TV");

        List<Map<String, Object>> entries = DataUsage.entries(sums, labels);

        assertEquals(3, entries.size());
        assertEquals("com.example.music", entries.get(0).get("packageName"));
        assertEquals(9_000L, entries.get(0).get("bytes"));
        assertEquals("Example TV", entries.get(1).get("label"));
        assertEquals(DataUsage.KIND_APP, entries.get(1).get("kind"));
        assertNull(entries.get(2).get("packageName"));
        assertEquals(DataUsage.KIND_SYSTEM, entries.get(2).get("kind"));
        assertEquals(500L, entries.get(2).get("bytes"));
    }
}
