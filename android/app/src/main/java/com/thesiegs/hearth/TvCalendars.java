package com.thesiegs.hearth;

import android.Manifest;
import android.content.ContentUris;
import android.content.Context;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.provider.CalendarContract;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * The Google calendars synced to the TV, for the top bar's date and time: Android's own calendar store
 * (CalendarContract), which Google's calendar sync fills for every Google account on the TV. Read only, and only the
 * active profile's: in the owner's user every adult's account syncs into the one store, so only the calendars of
 * the account whose profile is on are used (see {@link #chooseAccount}); a kids profile's own user has a store of its
 * own, which Hearth's agent there reads and relays ({@link AgentService}, {@link AgentHub}). Needs READ_CALENDAR.
 *
 * <p>Only calendars that sync their events and that the account shows (Google Calendar's own on/off for each
 * calendar): the others have no events on the TV.
 */
final class TvCalendars {
    private static final String TAG = "HearthCalendars";
    static final String READ_CALENDAR = Manifest.permission.READ_CALENDAR;
    /** More events than this in the range are left out (the home shows a week). */
    static final int MAX_EVENTS = 500;

    /** The answers to getCalendarAccess. */
    static final String GRANTED = "granted";
    static final String DENIED = "denied";
    /** A kids profile whose agent hasn't reported yet. */
    static final String WAITING = "waiting";

    private TvCalendars() {
    }

    /** One calendar in the store. */
    static final class Cal {
        final long id;
        final String account;
        final String name;
        final int color;
        final boolean visible;
        final boolean synced;
        final boolean primary;

        Cal(long id, String account, String name, int color, boolean visible, boolean synced, boolean primary) {
            this.id = id;
            this.account = account;
            this.name = name;
            this.color = color;
            this.visible = visible;
            this.synced = synced;
            this.primary = primary;
        }

        Map<String, Object> toMap() {
            Map<String, Object> map = new HashMap<>();
            map.put("id", id);
            map.put("name", name);
            map.put("color", color);
            map.put("account", account);
            map.put("primary", primary);
            return map;
        }
    }

    static boolean canRead(Context context) {
        return context.checkSelfPermission(READ_CALENDAR) == PackageManager.PERMISSION_GRANTED;
    }

    /** Every calendar in this user's store, by _id; empty when it can't be read. */
    static List<Cal> readAll(Context context) {
        List<Cal> out = new ArrayList<>();
        if (!canRead(context)) return out;
        String[] projection = {
                CalendarContract.Calendars._ID,
                CalendarContract.Calendars.ACCOUNT_NAME,
                CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                CalendarContract.Calendars.CALENDAR_COLOR,
                CalendarContract.Calendars.VISIBLE,
                CalendarContract.Calendars.SYNC_EVENTS,
                CalendarContract.Calendars.IS_PRIMARY,
        };
        try (Cursor c = context.getContentResolver().query(CalendarContract.Calendars.CONTENT_URI, projection, null,
                null, CalendarContract.Calendars._ID + " ASC")) {
            if (c == null) return out;
            while (c.moveToNext()) {
                String account = c.getString(1);
                String name = c.getString(2);
                out.add(new Cal(c.getLong(0), account != null ? account : "",
                        name != null && !name.trim().isEmpty() ? name.trim() : (account != null ? account : ""),
                        c.getInt(3), c.getInt(4) == 1, c.getInt(5) == 1, !c.isNull(6) && c.getInt(6) == 1));
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't read the calendars: " + e);
        }
        return out;
    }

    /**
     * The account whose calendars a profile shows: the profile's own Google account ({@code email}, learned from
     * Google TV's profile chooser) when it's known, even if it has no calendars here; else the one account whose
     * address starts with the profile's first name, if just one does; else the TV's first account (the one whose
     * calendars came first to the store). Null when there are no calendars.
     */
    static String chooseAccount(List<Cal> all, String email, String profileName) {
        if (all.isEmpty()) return null;
        if (email != null && !email.isEmpty()) {
            for (Cal cal : all) {
                if (cal.account.equalsIgnoreCase(email)) return cal.account;
            }
            return email;
        }
        String first = firstName(profileName);
        if (first.length() >= 2) {
            Set<String> matches = new LinkedHashSet<>();
            for (Cal cal : all) {
                String local = cal.account.toLowerCase(Locale.ROOT);
                int at = local.indexOf('@');
                if (at > 0 && local.substring(0, at).startsWith(first)) matches.add(cal.account);
            }
            if (matches.size() == 1) return matches.iterator().next();
        }
        Cal earliest = all.get(0);
        for (Cal cal : all) {
            if (cal.id < earliest.id) earliest = cal;
        }
        return earliest.account;
    }

    /** "Alex Rivera" → "alex": a name's first word, letters and digits only, in lower case. */
    static String firstName(String name) {
        if (name == null) return "";
        StringBuilder out = new StringBuilder();
        String trimmed = name.trim();
        for (int i = 0; i < trimmed.length(); ) {
            int c = trimmed.codePointAt(i);
            i += Character.charCount(c);
            if (Character.isLetterOrDigit(c)) {
                out.appendCodePoint(Character.toLowerCase(c));
            } else if (Character.isWhitespace(c)) {
                break;
            }
        }
        return out.toString();
    }

    /** The calendars a profile shows: those of its account ({@code account}, null: every one) that sync and show. */
    static List<Cal> shown(List<Cal> all, String account) {
        List<Cal> out = new ArrayList<>();
        for (Cal cal : all) {
            if (!cal.synced || !cal.visible) continue;
            if (account != null && !cal.account.equalsIgnoreCase(account)) continue;
            out.add(cal);
        }
        return out;
    }

    /** The calendars of this user's store that the active profile shows, as maps for Flutter. */
    static List<Map<String, Object>> toMaps(List<Cal> calendars) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Cal cal : calendars) out.add(cal.toMap());
        return out;
    }

    /**
     * The events of these calendars between start and end (milliseconds), recurring ones expanded (the store's
     * Instances), cancelled ones and those the account declined left out. An all-day event's start and end are
     * midnights in UTC. Each: calendarId, calendarName, color, title, location, start, end, allDay.
     */
    static List<Map<String, Object>> events(Context context, List<Cal> calendars, long start, long end) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (calendars.isEmpty() || end <= start || !canRead(context)) return out;
        Map<Long, Cal> byId = new HashMap<>();
        StringBuilder ids = new StringBuilder();
        for (Cal cal : calendars) {
            byId.put(cal.id, cal);
            if (ids.length() > 0) ids.append(',');
            ids.append(cal.id);
        }
        Uri.Builder uri = CalendarContract.Instances.CONTENT_URI.buildUpon();
        ContentUris.appendId(uri, start);
        ContentUris.appendId(uri, end);
        String[] projection = {
                CalendarContract.Instances.CALENDAR_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.DISPLAY_COLOR,
        };
        String selection = CalendarContract.Instances.CALENDAR_ID + " IN (" + ids + ")"
                + " AND (" + CalendarContract.Instances.STATUS + " IS NULL OR "
                + CalendarContract.Instances.STATUS + " != " + CalendarContract.Events.STATUS_CANCELED + ")"
                + " AND (" + CalendarContract.Instances.SELF_ATTENDEE_STATUS + " IS NULL OR "
                + CalendarContract.Instances.SELF_ATTENDEE_STATUS + " != "
                + CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED + ")";
        try (Cursor c = context.getContentResolver().query(uri.build(), projection, selection, null,
                CalendarContract.Instances.BEGIN + " ASC")) {
            if (c == null) return out;
            while (c.moveToNext() && out.size() < MAX_EVENTS) {
                Cal cal = byId.get(c.getLong(0));
                if (cal == null) continue;
                Map<String, Object> event = new HashMap<>();
                event.put("calendarId", cal.id);
                event.put("calendarName", cal.name);
                event.put("color", c.isNull(6) ? cal.color : c.getInt(6));
                event.put("title", c.getString(1));
                event.put("location", c.getString(2));
                long begin = c.getLong(3);
                event.put("start", begin);
                event.put("end", c.isNull(4) ? begin : c.getLong(4));
                event.put("allDay", c.getInt(5) == 1);
                out.add(event);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't read the calendars' events: " + e);
        }
        return out;
    }

    // --- The active profile, for Flutter (MainActivity) ---

    /**
     * Whether the active profile's calendars can be read: GRANTED, DENIED (Hearth there may not read them), or WAITING
     * (a kids profile whose agent hasn't said yet).
     */
    static String access(Context context) {
        long serial = ProfileUsers.settledSerial(context);
        if (ProfileUsers.otherUser(context, serial) != null) {
            Boolean agent = AgentHub.calendarAccess(serial);
            return agent == null ? WAITING : agent ? GRANTED : DENIED;
        }
        return canRead(context) ? GRANTED : DENIED;
    }

    /** The calendars the active profile shows. */
    static List<Map<String, Object>> activeCalendars(Context context) {
        long serial = ProfileUsers.settledSerial(context);
        if (ProfileUsers.otherUser(context, serial) != null) return AgentHub.calendars(serial);
        return toMaps(ownerProfileCalendars(context));
    }

    /** The active profile's events between start and end (milliseconds). */
    static List<Map<String, Object>> activeEvents(Context context, long start, long end) {
        long serial = ProfileUsers.settledSerial(context);
        if (ProfileUsers.otherUser(context, serial) != null) return AgentHub.calendarEvents(serial, start, end);
        return events(context, ownerProfileCalendars(context), start, end);
    }

    /** In the owner's user: the calendars of the adult whose profile is on. */
    private static List<Cal> ownerProfileCalendars(Context context) {
        List<Cal> all = readAll(context);
        String key = LauncherAccessibilityService.getActiveProfileKey(context);
        String name = key != null ? ProfileUsers.displayName(context, key) : null;
        String email = key != null ? ProfileUsers.emailOf(context, key) : null;
        return shown(all, chooseAccount(all, email, name));
    }

    /** Overlaps [start, end): what a range asks for of events read for a longer one. */
    static boolean overlaps(long eventStart, long eventEnd, long start, long end) {
        if (eventEnd <= eventStart) return eventStart >= start && eventStart < end;
        return eventStart < end && eventEnd > start;
    }
}
