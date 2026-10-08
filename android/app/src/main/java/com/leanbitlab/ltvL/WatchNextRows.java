package com.leanbitlab.ltvL;

import android.content.Context;
import android.database.Cursor;
import android.media.tv.TvContract;
import android.os.Build;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Reads Android TV's Watch Next list of the calling user (Hearth's own, or an agent's in a profile user). */
final class WatchNextRows {
    private static final String TAG = "HearthWatchNext";

    private WatchNextRows() {
    }

    static String cursorStringOrEmpty(Cursor cursor, String column) {
        String val = cursor.getString(cursor.getColumnIndexOrThrow(column));
        return val != null ? val : "";
    }

    /** This user's Watch Next programs, most recently engaged first (at most 20), as maps for Flutter. */
    static List<Map<String, Object>> read(Context context) {
        List<Map<String, Object>> list = new ArrayList<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return list;
        }

        String[] projection = {
            TvContract.WatchNextPrograms._ID,
            TvContract.WatchNextPrograms.COLUMN_PACKAGE_NAME,
            TvContract.WatchNextPrograms.COLUMN_TITLE,
            TvContract.WatchNextPrograms.COLUMN_SHORT_DESCRIPTION,
            TvContract.WatchNextPrograms.COLUMN_LONG_DESCRIPTION,
            TvContract.WatchNextPrograms.COLUMN_EPISODE_TITLE,
            TvContract.WatchNextPrograms.COLUMN_WATCH_NEXT_TYPE,
            TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS,
            TvContract.WatchNextPrograms.COLUMN_LAST_PLAYBACK_POSITION_MILLIS,
            TvContract.WatchNextPrograms.COLUMN_DURATION_MILLIS,
            TvContract.WatchNextPrograms.COLUMN_INTENT_URI,
            TvContract.WatchNextPrograms.COLUMN_POSTER_ART_URI,
            TvContract.WatchNextPrograms.COLUMN_THUMBNAIL_URI
        };

        try (Cursor cursor = context.getContentResolver().query(
                TvContract.WatchNextPrograms.CONTENT_URI,
                projection,
                null,
                null,
                TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS + " DESC")) {

            if (cursor == null) {
                return list;
            }

            final int maxFetch = 100;
            int row = 0;
            while (row < maxFetch && cursor.moveToNext()) {
                row++;

                long time = 0;
                int timeCol = cursor.getColumnIndex(TvContract.WatchNextPrograms.COLUMN_LAST_ENGAGEMENT_TIME_UTC_MILLIS);
                if (timeCol != -1 && !cursor.isNull(timeCol)) {
                    time = cursor.getLong(timeCol);
                    if (time > 0 && time < 10000000000L) {
                        time *= 1000L;
                    }
                }

                String poster = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_POSTER_ART_URI);
                if (poster.isEmpty()) {
                    poster = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_THUMBNAIL_URI);
                }

                String title = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_TITLE);
                String episodeTitle = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_EPISODE_TITLE);
                if (title.isEmpty() && !episodeTitle.isEmpty()) {
                    title = episodeTitle;
                }

                String shortDesc = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_SHORT_DESCRIPTION);
                String longDesc = cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_LONG_DESCRIPTION);

                String description = shortDesc;
                if (description.isEmpty() || description.trim().equalsIgnoreCase(title.trim())) {
                    if (!longDesc.isEmpty() && !longDesc.trim().equalsIgnoreCase(title.trim())) {
                        description = longDesc;
                    } else if (!episodeTitle.isEmpty() && !episodeTitle.trim().equalsIgnoreCase(title.trim())) {
                        description = episodeTitle;
                    }
                }

                Map<String, Object> map = new HashMap<>();
                map.put("id", cursor.getLong(cursor.getColumnIndexOrThrow(TvContract.WatchNextPrograms._ID)));
                map.put("packageName", cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_PACKAGE_NAME));
                map.put("title", title);
                map.put("description", description);
                map.put("watchNextType", cursor.getInt(cursor.getColumnIndexOrThrow(TvContract.WatchNextPrograms.COLUMN_WATCH_NEXT_TYPE)));
                map.put("lastEngagementTime", time);
                map.put("playbackPosition", cursor.getLong(cursor.getColumnIndexOrThrow(TvContract.WatchNextPrograms.COLUMN_LAST_PLAYBACK_POSITION_MILLIS)));
                map.put("duration", cursor.getLong(cursor.getColumnIndexOrThrow(TvContract.WatchNextPrograms.COLUMN_DURATION_MILLIS)));
                map.put("intentUri", cursorStringOrEmpty(cursor, TvContract.WatchNextPrograms.COLUMN_INTENT_URI));
                map.put("posterArtUri", poster);
                list.add(map);
            }

            // Explicitly sort descending by last engagement time (most recently watched first),
            // and fallback to ID descending if timestamps are identical.
            list.sort((a, b) -> {
                long timeA = (Long) a.get("lastEngagementTime");
                long timeB = (Long) b.get("lastEngagementTime");
                if (timeA != timeB) {
                    return Long.compare(timeB, timeA);
                }
                long idA = (Long) a.get("id");
                long idB = (Long) b.get("id");
                return Long.compare(idB, idA);
            });

            if (list.size() > 20) {
                list = new ArrayList<>(list.subList(0, 20));
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read Watch Next", e);
        }

        return list;
    }
}
