/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.thesiegs.hearth;

import android.app.usage.NetworkStats;
import android.app.usage.NetworkStatsManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.util.Log;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The data this TV sent and received (NetworkStatsManager, with usage access): in all, and app by app. Wi-Fi and
 * mobile only: Android's public API keeps no Ethernet count (NetworkStatsManager takes only TYPE_WIFI and TYPE_MOBILE
 * and throws for TYPE_ETHERNET), so on a wired TV the numbers stay near zero.
 */
final class DataUsage {
    private static final String TAG = "HearthDataUsage";

    /** The networks counted. */
    static final int[] NETWORKS = {ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE};

    /** An app's own data. */
    static final String KIND_APP = "app";
    /** Android itself (the uids below the first app uid, root and system services). */
    static final String KIND_SYSTEM = "system";
    /** Anything else: removed apps, tethering, apps Hearth can't see (another profile's). */
    static final String KIND_OTHER = "other";

    /** NetworkStats.Bucket.UID_REMOVED and UID_TETHERING, and Process.FIRST_APPLICATION_UID. */
    static final int UID_REMOVED = -4;
    static final int UID_TETHERING = -5;
    static final int FIRST_APPLICATION_UID = 10000;
    /** An Android user's uids are its number times this plus the app's id (UserHandle.PER_USER_RANGE). */
    static final int PER_USER_RANGE = 100000;

    private DataUsage() {
    }

    /** Midnight at the start of today ("daily"), this week (the locale's first day, "weekly") or this month. */
    static long periodStart(String period, Calendar calendar) {
        switch (period == null ? "" : period) {
            // Back to the week's first day (setting DAY_OF_WEEK can land on another week, by how the date was set)
            case "weekly" -> calendar.add(Calendar.DAY_OF_MONTH,
                    -((calendar.get(Calendar.DAY_OF_WEEK) - calendar.getFirstDayOfWeek() + 7) % 7));
            case "monthly" -> calendar.set(Calendar.DAY_OF_MONTH, 1);
            default -> {
            }
        }
        calendar.set(Calendar.HOUR_OF_DAY, 0);
        calendar.set(Calendar.MINUTE, 0);
        calendar.set(Calendar.SECOND, 0);
        calendar.set(Calendar.MILLISECOND, 0);
        return calendar.getTimeInMillis();
    }

    /** The period a data usage method asks for ("getWeeklyDataUsage" is "weekly"). */
    static String periodOfMethod(String method) {
        return switch (method) {
            case "getWeeklyDataUsage" -> "weekly";
            case "getMonthlyDataUsage" -> "monthly";
            default -> "daily";
        };
    }

    /** What a uid's data is: an app's, Android's own, or other (see the KIND_ constants). */
    static String kindOf(int uid) {
        if (uid == UID_REMOVED || uid == UID_TETHERING || uid < 0) return KIND_OTHER;
        return uid % PER_USER_RANGE < FIRST_APPLICATION_UID ? KIND_SYSTEM : KIND_APP;
    }

    /** The package that names a uid's data: the only one, or of a shared uid the first by name; null for none. */
    static String packageOf(String[] packages) {
        if (packages == null || packages.length == 0) return null;
        String[] sorted = packages.clone();
        Arrays.sort(sorted);
        return sorted[0];
    }

    /** Adds bytes to key's sum. */
    static void add(Map<String, Long> sums, String key, long bytes) {
        if (bytes <= 0) return;
        Long sum = sums.get(key);
        sums.put(key, (sum == null ? 0 : sum) + bytes);
    }

    /**
     * The data sums as Flutter takes them, largest first: "packageName" and "label" (both null for Android's own and
     * other), "kind" and "bytes". Android's own and other are one entry each.
     */
    static List<Map<String, Object>> entries(Map<String, Long> sums, Map<String, String> labels) {
        List<Map<String, Object>> list = new ArrayList<>();
        for (Map.Entry<String, Long> sum : sums.entrySet()) {
            String key = sum.getKey();
            Map<String, Object> entry = new HashMap<>();
            boolean special = KIND_SYSTEM.equals(key) || KIND_OTHER.equals(key);
            entry.put("packageName", special ? null : key);
            entry.put("label", special ? null : labels.get(key));
            entry.put("kind", special ? key : KIND_APP);
            entry.put("bytes", sum.getValue());
            list.add(entry);
        }
        list.sort((a, b) -> Long.compare((Long) b.get("bytes"), (Long) a.get("bytes")));
        return list;
    }

    /** Bytes sent and received over Wi-Fi and mobile from start to end, all of the TV. */
    static long deviceTotal(Context context, long start, long end) {
        NetworkStatsManager manager = (NetworkStatsManager) context.getSystemService(Context.NETWORK_STATS_SERVICE);
        if (manager == null) return 0;
        long total = 0;
        for (int type : NETWORKS) {
            try {
                NetworkStats.Bucket bucket = manager.querySummaryForDevice(type, null, start, end);
                if (bucket != null) total += bucket.getRxBytes() + bucket.getTxBytes();
            } catch (Exception e) {
                Log.w(TAG, "No data usage for network type " + type, e);
            }
        }
        return total;
    }

    /**
     * The data from start to end app by app ({@link #entries}) with "total" (all of the TV, which also counts what no
     * app is named for) and "apps".
     */
    static Map<String, Object> byApp(Context context, long start, long end) {
        Map<String, Object> answer = new HashMap<>();
        answer.put("total", deviceTotal(context, start, end));
        NetworkStatsManager manager = (NetworkStatsManager) context.getSystemService(Context.NETWORK_STATS_SERVICE);
        PackageManager pm = context.getPackageManager();
        Map<Integer, Long> byUid = new HashMap<>();
        if (manager != null) {
            for (int type : NETWORKS) {
                try (NetworkStats stats = manager.querySummary(type, null, start, end)) {
                    NetworkStats.Bucket bucket = new NetworkStats.Bucket();
                    while (stats.hasNextBucket()) {
                        stats.getNextBucket(bucket);
                        long bytes = bucket.getRxBytes() + bucket.getTxBytes();
                        if (bytes <= 0) continue;
                        Long sum = byUid.get(bucket.getUid());
                        byUid.put(bucket.getUid(), (sum == null ? 0 : sum) + bytes);
                    }
                } catch (Exception e) {
                    Log.w(TAG, "No app data usage for network type " + type, e);
                }
            }
        }
        Map<String, Long> sums = new HashMap<>();
        Map<String, String> labels = new HashMap<>();
        for (Map.Entry<Integer, Long> uid : byUid.entrySet()) {
            String kind = kindOf(uid.getKey());
            String packageName = KIND_APP.equals(kind) ? packageOf(pm.getPackagesForUid(uid.getKey())) : null;
            if (KIND_APP.equals(kind) && packageName == null) kind = KIND_OTHER;
            add(sums, packageName != null ? packageName : kind, uid.getValue());
            if (packageName != null && !labels.containsKey(packageName)) labels.put(packageName, labelOf(pm, packageName));
        }
        answer.put("apps", entries(sums, labels));
        return answer;
    }

    /** The app's name, or its package name when it has none Hearth can read. */
    private static String labelOf(PackageManager pm, String packageName) {
        try {
            ApplicationInfo info = pm.getApplicationInfo(packageName, 0);
            CharSequence label = info.loadLabel(pm);
            return label == null || label.length() == 0 ? packageName : label.toString();
        } catch (Exception e) {
            return packageName;
        }
    }
}
