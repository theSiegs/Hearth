package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * A profile's YouTube allowance for HearthTube to enforce. Hearth works it out on its own: a daily limit set for the
 * profile in Hearth's Settings, less what HearthTube has played for it today (HearthTube reports that itself).
 * Home Assistant is optional: when it's set up and has a say for the profile (HaAllowance: a pool shared with the
 * family's other devices, a schedule), the stricter of the two counts.
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

    static Values forProfile(Context context, String profileKey, long now) {
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

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
