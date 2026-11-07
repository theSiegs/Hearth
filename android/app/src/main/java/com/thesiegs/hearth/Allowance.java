package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.text.format.DateFormat;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.Date;

/**
 * A profile's YouTube allowance for HearthTube to enforce. Hearth works it out on its own: a daily limit set for the
 * profile in Hearth's Settings, less what HearthTube has played for it today (HearthTube reports that itself).
 * Home Assistant is optional: when it's set up and has a say for the profile (HaAllowance: a pool shared with the
 * family's other devices, a schedule), the stricter of the two counts.
 *
 * Paired with the Hearth integration, a kids profile's other groups are held too: an app whose group's time is up
 * today doesn't open from Hearth, and comes back to Hearth's home when it opens another way ({@link #timeUpGroup}).
 */
final class Allowance {
    private static final String PREFS = "ltv_allowance_limits";
    static final String SOURCE_HEARTH = "hearth";
    static final String SOURCE_HOME_ASSISTANT = "home_assistant";

    private Allowance() {
    }

    /** The daily YouTube limit set in Hearth for this profile, in minutes; 0 for none. */
    static int dailyMinutes(Context context, String profileKey) {
        return profileKey == null ? 0 : prefs(context).getInt(profileKey, 0);
    }

    static void setDailyMinutes(Context context, String profileKey, int minutes) {
        if (profileKey == null) return;
        SharedPreferences.Editor editor = prefs(context).edit();
        if (minutes > 0) {
            editor.putInt(profileKey, minutes);
        } else {
            editor.remove(profileKey);
        }
        editor.apply();
    }

    /** The profile's allowance now: minutes left (null: no limit), locked, message, and whose say it is. */
    static final class Values {
        final Integer youtubeMinutesLeft;
        final boolean scheduleLocked;
        final String message;
        final Long checkedAt;
        final String source;

        Values(Integer youtubeMinutesLeft, boolean scheduleLocked, String message, Long checkedAt, String source) {
            this.youtubeMinutesLeft = youtubeMinutesLeft;
            this.scheduleLocked = scheduleLocked;
            this.message = message;
            this.checkedAt = checkedAt;
            this.source = source;
        }
    }

    /** No limit or lock: an adult's profile (only kids profiles have a YouTube allowance). */
    static final Values NONE = new Values(null, false, null, null, null);

    static Values forProfile(Context context, String profileKey, long now) {
        // An adult's profile has no allowance, whatever was stored for it (an older Hearth let an adult set one)
        if (profileKey == null || ProfileUsers.isAdults(context, ProfileUsers.serialOfKey(profileKey))) return NONE;
        int limit = dailyMinutes(context, profileKey);
        long playedMs = UsageToday.playingMs(context, profileKey, CompanionApps.HEARTHTUBE, now);
        HaAllowance.Values ha = HaAllowance.forProfile(context, profileKey, now);
        return combine(limit, playedMs, ha.youtubeMinutesLeft, ha.scheduleLocked, ha.message, ha.checkedAt);
    }

    /**
     * Hearth's own limit (minutes, 0: none) less what was played, and Home Assistant's say (minutes left, null: no
     * limit), the stricter counting. The source names whose minutes they are (Home Assistant's when only its lock
     * applies); Home Assistant's lock comes along whenever it gave one, and its message when its say applies.
     */
    static Values combine(int limitMinutes, long playedMs, Integer haMinutesLeft, boolean haLocked, String haMessage,
            Long haCheckedAt) {
        Integer own = limitMinutes > 0 ? (int) Math.max(0, limitMinutes - playedMs / 60_000) : null;
        Integer left = own;
        String source = own != null ? SOURCE_HEARTH : null;
        if (haMinutesLeft != null && (own == null || haMinutesLeft < own)) {
            left = haMinutesLeft;
            source = SOURCE_HOME_ASSISTANT;
        }
        // The source says whose minutes they are; with no minutes, whose lock it is
        if (source == null && haLocked) source = SOURCE_HOME_ASSISTANT;
        String message = haLocked || SOURCE_HOME_ASSISTANT.equals(source) ? haMessage : null;
        return new Values(left, haLocked, message, haCheckedAt, source);
    }

    /**
     * The group whose time is up today for this app in the active profile, as the Hearth integration last said
     * (null: it may open). Never in an adult's profile, never Hearth itself, and nothing without today's word from
     * Home Assistant.
     */
    static String timeUpGroup(Context context, String packageName) {
        String profileKey = LauncherAccessibilityService.getActiveProfileKey(context);
        if (packageName == null || profileKey == null || packageName.equals(context.getPackageName())
                || ProfileUsers.isAdults(context, ProfileUsers.serialOfKey(profileKey))) {
            return null;
        }
        return HaAllowance.forProfile(context, profileKey, System.currentTimeMillis()).timeUpGroup(packageName);
    }

    /** In {@link #heldApps}: everything is held (a family pause or a lock), not one group's time. */
    static final String HELD_ALL = "";

    /**
     * Which of these apps the active profile can't open now, for Hearth's home to show them out of time: package ->
     * the group whose time is up, or {@link #HELD_ALL} while a family pause or a lock holds every app. None in an
     * adult's profile, and never Hearth's own entries or the apps Home Assistant never holds.
     */
    static java.util.Map<String, String> heldApps(Context context, java.util.Collection<String> packages) {
        String profileKey = LauncherAccessibilityService.getActiveProfileKey(context);
        if (profileKey == null || ProfileUsers.isAdults(context, ProfileUsers.serialOfKey(profileKey))) {
            return new java.util.HashMap<>();
        }
        long now = System.currentTimeMillis();
        Values values = forProfile(context, profileKey, now);
        return heldApps(packages, HaAllowance.entryFor(context, profileKey, now), values.youtubeMinutesLeft,
                "YouTube", now);
    }

    /** {@link #heldApps(Context, java.util.Collection)} from the profile's entry and its YouTube minutes left. */
    static java.util.Map<String, String> heldApps(java.util.Collection<String> packages, JSONObject entry,
            Integer youtubeMinutesLeft, String youtubeName, long now) {
        java.util.Map<String, String> held = new java.util.HashMap<>();
        HaAllowance.Values ha = HaAllowance.valuesOf(entry, null);
        JSONObject lock = HaLocks.locksOf(entry).optJSONObject("lock");
        Long lockUntil = lock != null ? HaLocks.parseTime(lock.optString("until", null)) : null;
        boolean locked = lock != null && (lockUntil == null || lockUntil > now);
        for (String app : packages) {
            if (app == null) continue;
            boolean hearthTube = CompanionApps.HEARTHTUBE.equals(app);
            if (HaAllowance.NEVER_HELD.contains(app) && !hearthTube) continue;
            String group = hearthTube ? null : ha.timeUpGroup(app, now);
            if (HaAllowance.PAUSE_HOLD.equals(group) || hearthTube && ha.pausedUntil != null && now < ha.pausedUntil) {
                held.put(app, HELD_ALL);
            } else if (group != null) {
                held.put(app, group);
            } else if (locked) {
                held.put(app, HELD_ALL);
            } else if (hearthTube && youtubeMinutesLeft != null && youtubeMinutesLeft <= 0) {
                // HearthTube holds YouTube time itself; Hearth's own limit (or Home Assistant's) says it's out
                held.put(app, youtubeName);
            }
        }
        return held;
    }

    /** Whether the app is held for its group's time (main thread): if so, the kid is told why and it doesn't open. */
    static boolean holdForTime(Context context, String packageName) {
        return holdForTime(context, packageName, false);
    }

    /**
     * As {@link #holdForTime(Context, String)}; [inHearth]: Hearth's home is in front (the app was picked there), so
     * Hearth's own time's up card can tell the kid, with a way to ask for more time.
     */
    static boolean holdForTime(Context context, String packageName, boolean inHearth) {
        String group = timeUpGroup(context, packageName);
        if (group == null) return false;
        showTimeUp(context, group, inHearth);
        return true;
    }

    private static final long TELL_AGAIN_AFTER_MS = 5_000;
    private static String sToldGroup;
    private static long sToldAt;

    /**
     * Tells the kid the group's time is up (main thread), after the app was sent back to the home: Hearth's card when
     * Hearth's home is the one that comes back, else a toast.
     */
    static void showTimeUp(Context context, String group) {
        showTimeUp(context, group, !LauncherAccessibilityService.isGoogleTvHome(context));
    }

    /**
     * Tells the kid the group's time is up, or that a family pause holds the apps (main thread); the same once every
     * few seconds at most. With Hearth's home in front ([inHearth]) Hearth's own card says it (why, until when, and
     * asking for more time); otherwise, or when Flutter isn't there to show it, a toast.
     */
    static void showTimeUp(Context context, String group, boolean inHearth) {
        long now = SystemClock.elapsedRealtime();
        if (group.equals(sToldGroup) && now - sToldAt < TELL_AGAIN_AFTER_MS) return;
        sToldGroup = group;
        sToldAt = now;
        boolean paused = HaAllowance.PAUSE_HOLD.equals(group);
        if (inHearth && MainActivity.notifyTimeUp(paused ? null : group)) return;
        Toast.makeText(context, paused ? pauseMessage(context)
                : context.getString(R.string.time_up_for_group, group), Toast.LENGTH_LONG).show();
    }

    /** "Paused: Dinner, until 7:00 PM", as the active profile's pause says it. */
    private static String pauseMessage(Context context) {
        long now = System.currentTimeMillis();
        JSONObject pause = HaLocks.locksOf(HaAllowance.entryFor(context,
                LauncherAccessibilityService.getActiveProfileKey(context), now)).optJSONObject("pause");
        String reason = pause != null ? pause.optString("reason", "").trim() : "";
        Long until = pause != null ? HaLocks.parseTime(pause.optString("until", null)) : null;
        if (reason.isEmpty()) reason = context.getString(R.string.paused_no_reason);
        if (until == null || until == Long.MAX_VALUE) return context.getString(R.string.paused_reason, reason);
        String time = DateFormat.getTimeFormat(context).format(new Date(until));
        return context.getString(R.string.paused_reason_until, reason, time);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
