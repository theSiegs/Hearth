package com.thesiegs.hearth;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * What a Google TV kids screen time screen or warning says: why the TV is (about to be) locked and how long is
 * left. Google TV has no API for this, so it's read from the text of the screen. The wording isn't documented
 * and varies by language, so everything is best effort: unknown text gives {@link Reason#UNKNOWN} and no minutes.
 */
final class ScreenTimeScreen {
    enum Reason {
        BEDTIME("bedtime"),
        DAILY_LIMIT("daily_limit"),
        UNKNOWN("unknown");

        final String id;

        Reason(String id) {
            this.id = id;
        }
    }

    private static final Pattern HOURS = Pattern.compile("(\\d+)\\s*(?:hours?|hrs?|h)\\b");
    private static final Pattern MINUTES = Pattern.compile("(\\d+)\\s*(?:minutes?|mins?|m)\\b");
    private static final Pattern TIME_UP = Pattern.compile("time'?s up|time is up|out of time|no time left|time limit reached");
    // "Time for bed", "Bedtime", "Bed time" (not "embedded")
    private static final Pattern BED = Pattern.compile("\\bbed|downtime");
    // Google TV's bedtime screen: "This device unlocks at 6:00 AM"
    private static final Pattern UNLOCKS_AT = Pattern.compile(
            "unlocks? at (\\d{1,2}(?::\\d{2})?\\s*(?:[ap]\\.?m\\.?)?)", Pattern.CASE_INSENSITIVE);

    final Reason reason;
    /** Minutes left as the screen states them; 0 when time is up; null when it states none. */
    final Integer minutesLeft;
    /** When the TV unlocks again as the screen states it (e.g. "6:00 AM"); null when it states none. */
    final String unlocksAt;
    /** The screen's own text, for seeing what Google TV actually says. */
    final String text;
    /** Google TV's own time up screen (kids.wellbeing.timeupdialog, KidsTimeUpActivity), not a warning or bedtime's. */
    final boolean timeUpDialog;

    private ScreenTimeScreen(Reason reason, Integer minutesLeft, String unlocksAt, String text, boolean timeUpDialog) {
        this.reason = reason;
        this.minutesLeft = minutesLeft;
        this.unlocksAt = unlocksAt;
        this.text = text;
        this.timeUpDialog = timeUpDialog;
    }

    /**
     * Google TV's own Kids daily limit holds the profile now: its time up screen is (or was last) up while the lock
     * is on, and it isn't bedtime. Hearth can't lift it; only raising or turning off the limit in Google TV can.
     */
    static boolean isGoogleLimit(boolean locked, ScreenTimeScreen screen) {
        return locked && screen != null && screen.timeUpDialog && screen.reason != Reason.BEDTIME;
    }

    private static final String PREFS = "screen_time_screen";
    private static final String GOOGLE_LIMIT_SEEN_KEY = "google_limit_seen_at";

    /**
     * Notes that Google TV's own Kids daily limit was just seen (its time up screen, not bedtime's), so Set up Hearth
     * can point to turning it off when Home Assistant runs screen time.
     */
    static void noteGoogleLimit(android.content.Context context, ScreenTimeScreen screen, long now) {
        if (!isGoogleLimit(true, screen)) return;
        context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).edit()
                .putLong(GOOGLE_LIMIT_SEEN_KEY, now).apply();
    }

    /** When Google TV's own Kids daily limit was last seen (epoch ms), or 0: never. */
    static long googleLimitSeenAt(android.content.Context context) {
        return context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
                .getLong(GOOGLE_LIMIT_SEEN_KEY, 0);
    }

    /**
     * @param className the Google TV window class; kept because it can name the reason when the text doesn't
     * @param texts the screen's text (the accessibility event's, or the window's own text views)
     */
    static ScreenTimeScreen parse(String className, List<CharSequence> texts) {
        StringBuilder joined = new StringBuilder();
        if (texts != null) {
            for (CharSequence part : texts) {
                if (part == null || part.length() == 0) continue;
                if (joined.length() > 0) joined.append(" | ");
                joined.append(part.toString().trim());
            }
        }
        String text = joined.toString();
        String lower = (text + " " + (className == null ? "" : className)).toLowerCase(Locale.ROOT);

        Reason reason = Reason.UNKNOWN;
        if (BED.matcher(lower).find()) {
            reason = Reason.BEDTIME;
        } else if (lower.contains("daily limit") || lower.contains("dailylimit") || lower.contains("screen time")
                || lower.contains("screentime") || lower.contains("time limit")) {
            reason = Reason.DAILY_LIMIT;
        }

        Integer minutes = null;
        // A time up screen (kids.wellbeing.timeupdialog.*) means none left, whatever its wording
        if (TIME_UP.matcher(lower).find() || lower.contains(".timeup")) {
            minutes = 0;
        } else {
            Matcher hours = HOURS.matcher(lower);
            Matcher mins = MINUTES.matcher(lower);
            boolean hasHours = hours.find();
            boolean hasMinutes = mins.find();
            if (hasHours || hasMinutes) {
                minutes = (hasHours ? Integer.parseInt(hours.group(1)) * 60 : 0)
                        + (hasMinutes ? Integer.parseInt(mins.group(1)) : 0);
            }
        }
        Matcher unlocks = UNLOCKS_AT.matcher(text);
        String unlocksAt = unlocks.find() ? unlocks.group(1).trim() : null;
        String cls = className == null ? "" : className.toLowerCase(Locale.ROOT);
        boolean timeUpDialog = cls.contains(".timeupdialog.") || cls.endsWith("kidstimeupactivity");
        return new ScreenTimeScreen(reason, minutes, unlocksAt, text, timeUpDialog);
    }

    /**
     * Whether the text is about screen time at all. Google TV's home shows plenty of unrelated text, so a
     * window that isn't a known screen time class only counts when it talks about time limits.
     */
    boolean isScreenTimeText() {
        return reason != Reason.UNKNOWN || minutesLeft != null && minutesLeft == 0;
    }

    private static final Pattern CLOCK = Pattern.compile(
            "(\\d{1,2})(?::(\\d{2}))?\\s*(?:([ap])\\.?m\\.?)?", Pattern.CASE_INSENSITIVE);

    /**
     * Google TV's unlock time ("7:00 AM", as the screen said it at seenAt) as the next such moment, in ISO 8601 with
     * the TV's UTC offset ("2026-10-11T07:00:00-04:00"); null when it can't be read.
     */
    static String unlocksAtIso(String unlocksAt, long seenAt) {
        if (unlocksAt == null || seenAt <= 0) return null;
        Matcher m = CLOCK.matcher(unlocksAt.trim());
        if (!m.matches()) return null;
        int hour = Integer.parseInt(m.group(1));
        int minute = m.group(2) != null ? Integer.parseInt(m.group(2)) : 0;
        String half = m.group(3);
        if (half != null) {
            if (hour < 1 || hour > 12) return null;
            hour = hour % 12 + ("p".equalsIgnoreCase(half) ? 12 : 0);
        }
        if (hour > 23 || minute > 59) return null;
        Calendar at = Calendar.getInstance();
        at.setTimeInMillis(seenAt);
        at.set(Calendar.HOUR_OF_DAY, hour);
        at.set(Calendar.MINUTE, minute);
        at.set(Calendar.SECOND, 0);
        at.set(Calendar.MILLISECOND, 0);
        if (at.getTimeInMillis() <= seenAt) at.add(Calendar.DAY_OF_MONTH, 1);
        long time = at.getTimeInMillis();
        int offset = TimeZone.getDefault().getOffset(time) / 60_000;
        String sign = offset < 0 ? "-" : "+";
        offset = Math.abs(offset);
        return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT).format(at.getTime())
                + String.format(Locale.ROOT, "%s%02d:%02d", sign, offset / 60, offset % 60);
    }
}
