package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import android.database.Cursor;

import org.junit.Test;

import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Turning the TV's Watch Next rows into the maps Continue Watching reads. */
public class WatchNextRowsTest {
    /** A Cursor over rows of column -> value; a column a row doesn't have is null in it. */
    private static Cursor cursor(List<Map<String, Object>> rows) {
        List<String> columns = new ArrayList<>(Arrays.asList("_id", "package_name", "title", "short_description",
                "long_description", "episode_title", "watch_next_type", "last_engagement_time_utc_millis",
                "last_playback_position_millis", "duration_millis", "intent_uri", "poster_art_uri", "thumbnail_uri",
                "internal_provider_id"));
        int[] position = {-1};
        return (Cursor) Proxy.newProxyInstance(Cursor.class.getClassLoader(), new Class<?>[]{Cursor.class},
                (proxy, method, args) -> {
                    switch (method.getName()) {
                        case "moveToNext":
                            position[0]++;
                            return position[0] < rows.size();
                        case "getColumnIndex":
                            return columns.indexOf((String) args[0]);
                        case "getColumnIndexOrThrow": {
                            int index = columns.indexOf((String) args[0]);
                            if (index < 0) throw new IllegalArgumentException("No column " + args[0]);
                            return index;
                        }
                        case "isNull":
                            return value(rows, position[0], columns, args) == null;
                        case "getString": {
                            Object v = value(rows, position[0], columns, args);
                            return v == null ? null : v.toString();
                        }
                        case "getLong": {
                            Object v = value(rows, position[0], columns, args);
                            return v == null ? 0L : ((Number) v).longValue();
                        }
                        case "getInt": {
                            Object v = value(rows, position[0], columns, args);
                            return v == null ? 0 : ((Number) v).intValue();
                        }
                        case "close":
                            return null;
                        default:
                            throw new UnsupportedOperationException(method.getName());
                    }
                });
    }

    private static Object value(List<Map<String, Object>> rows, int position, List<String> columns, Object[] args) {
        return rows.get(position).get(columns.get((Integer) args[0]));
    }

    private static Map<String, Object> row(long id, String title, long engaged) {
        Map<String, Object> row = new HashMap<>();
        row.put("_id", id);
        row.put("package_name", "com.example.video");
        row.put("title", title);
        row.put("watch_next_type", 0);
        row.put("last_engagement_time_utc_millis", engaged);
        row.put("last_playback_position_millis", 60_000L);
        row.put("duration_millis", 3_600_000L);
        return row;
    }

    @SafeVarargs
    private static List<Map<String, Object>> read(Map<String, Object>... rows) {
        List<Map<String, Object>> list = new ArrayList<>();
        WatchNextRows.addRows(cursor(Arrays.asList(rows)), list);
        return list;
    }

    @Test
    public void aRowBecomesTheMapFlutterReads() {
        Map<String, Object> source = row(7, "The Film", 1_700_000_000_000L);
        source.put("intent_uri", "intent://watch/1");
        source.put("poster_art_uri", "https://img.example/1.jpg");
        source.put("internal_provider_id", "ep-1");
        source.put("short_description", "A film");

        Map<String, Object> map = read(source).get(0);

        assertEquals(7L, map.get("id"));
        assertEquals("com.example.video", map.get("packageName"));
        assertEquals("The Film", map.get("title"));
        assertEquals("A film", map.get("description"));
        assertEquals(0, map.get("watchNextType"));
        assertEquals(1_700_000_000_000L, map.get("lastEngagementTime"));
        assertEquals(60_000L, map.get("playbackPosition"));
        assertEquals(3_600_000L, map.get("duration"));
        assertEquals("intent://watch/1", map.get("intentUri"));
        assertEquals("https://img.example/1.jpg", map.get("posterArtUri"));
        assertEquals("ep-1", map.get("internalId"));
    }

    @Test
    public void missingTextsAreEmptyNotNull() {
        Map<String, Object> source = row(1, null, 5_000_000_000_000L);
        Map<String, Object> map = read(source).get(0);
        assertEquals("", map.get("title"));
        assertEquals("", map.get("description"));
        assertEquals("", map.get("intentUri"));
        assertEquals("", map.get("posterArtUri"));
        assertEquals("", map.get("internalId"));
    }

    @Test
    public void anEngagementTimeInSecondsIsTurnedIntoMilliseconds() {
        assertEquals(1_700_000_000_000L, read(row(1, "a", 1_700_000_000L)).get(0).get("lastEngagementTime"));
        // Already milliseconds, none, or missing: left as is
        assertEquals(10_000_000_000L, read(row(1, "a", 10_000_000_000L)).get(0).get("lastEngagementTime"));
        assertEquals(0L, read(row(1, "a", 0L)).get(0).get("lastEngagementTime"));
        Map<String, Object> missing = row(1, "a", 0L);
        missing.remove("last_engagement_time_utc_millis");
        assertEquals(0L, read(missing).get(0).get("lastEngagementTime"));
    }

    @Test
    public void theThumbnailStandsInForAMissingPoster() {
        Map<String, Object> source = row(1, "a", 1L);
        source.put("poster_art_uri", "");
        source.put("thumbnail_uri", "content://thumb/1");
        assertEquals("content://thumb/1", read(source).get(0).get("posterArtUri"));
    }

    @Test
    public void anEpisodeWithoutATitleIsNamedByTheEpisode() {
        Map<String, Object> source = row(1, "", 1L);
        source.put("episode_title", "Pilot");
        Map<String, Object> map = read(source).get(0);
        assertEquals("Pilot", map.get("title"));
        // Not described by its own name again
        assertEquals("", map.get("description"));
    }

    @Test
    public void aDescriptionThatOnlyRepeatsTheTitleGivesWayToALongerOne() {
        Map<String, Object> source = row(1, "The Show", 1L);
        source.put("short_description", " the show ");
        source.put("long_description", "Season 2, a long way from home");
        source.put("episode_title", "Episode 4");
        assertEquals("Season 2, a long way from home", read(source).get(0).get("description"));

        source.put("long_description", "THE SHOW");
        assertEquals("Episode 4", read(source).get(0).get("description"));

        source.put("short_description", "");
        source.put("long_description", "");
        assertEquals("Episode 4", read(source).get(0).get("description"));
    }

    @Test
    public void newestFirstAfterSecondsAreConvertedAndTiesGoToTheNewerId() {
        // As the provider sorted them (by the raw column): the one stored in seconds sorts last there
        List<Map<String, Object>> list = read(
                row(1, "older", 1_600_000_000_000L),
                row(2, "same time, lower id", 1_650_000_000_000L),
                row(3, "same time, higher id", 1_650_000_000_000L),
                row(4, "newest, in seconds", 1_700_000_000L));

        assertEquals(Arrays.asList(4L, 3L, 2L, 1L), Arrays.asList(list.get(0).get("id"), list.get(1).get("id"),
                list.get(2).get("id"), list.get(3).get("id")));
    }

    @Test
    public void readsAtMostMaxRows() {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (int i = 0; i < WatchNextRows.MAX_ROWS + 20; i++) rows.add(row(i, "t" + i, 1_000_000_000_000L - i));
        List<Map<String, Object>> list = new ArrayList<>();
        WatchNextRows.addRows(cursor(rows), list);
        assertEquals(WatchNextRows.MAX_ROWS, list.size());
        assertEquals(0L, list.get(0).get("id"));
        assertEquals((long) WatchNextRows.MAX_ROWS - 1, list.get(list.size() - 1).get("id"));
    }
}
