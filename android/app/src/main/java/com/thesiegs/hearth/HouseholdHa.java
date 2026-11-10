package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * One Home Assistant pairing for the whole household (docs/household-sync.md, "Home Assistant once"): each TV says in
 * an {@link #STATE} entry whether it's paired with the Hearth integration, and a paired TV gets a single-use ticket from
 * Home Assistant for each TV of the household on the network that isn't (and wasn't unpaired on purpose), and leaves it
 * in a {@link #TICKET} entry for that TV, which pairs with it at once. Pure: the rules, so they can be tested alone.
 */
final class HouseholdHa {
    /** A TV's pairing with Home Assistant: item its TV id, value {@link #PAIRED} or {@link #LEFT}; none: not paired. */
    static final String STATE = "ha_state";
    /** A ticket for a TV: item that TV's id, value {"url", "ticket"}. Gone once it's used. */
    static final String TICKET = "ha_ticket";
    static final String PAIRED = "paired";
    /** Unpaired here, or deleted in Home Assistant: it isn't paired again by the household. */
    static final String LEFT = "left";
    /** A ticket lives five minutes in Home Assistant; another isn't asked for a TV while one may still work. */
    static final long TICKET_MS = 5 * 60_000;

    private HouseholdHa() {
    }

    /** What this TV's state entry should say: {@link #PAIRED}, {@link #LEFT}, or null (no entry). */
    static String stateOf(boolean paired, boolean left) {
        return paired ? PAIRED : left ? LEFT : null;
    }

    /**
     * The TVs on the network now that a paired TV should get a ticket for: not this one, not paired, not left on
     * purpose, and with no ticket left for them in the last {@link #TICKET_MS}.
     */
    static List<String> needTickets(Collection<HouseholdEntry> entries, String selfTv, Collection<String> online,
            long nowMs) {
        Map<String, String> states = new HashMap<>();
        Set<String> ticketed = new HashSet<>();
        for (HouseholdEntry e : entries) {
            if (STATE.equals(e.kind) && !e.deleted) states.put(e.item, e.value);
            if (TICKET.equals(e.kind) && !e.deleted && nowMs - HouseholdLog.millisOf(e) < TICKET_MS) ticketed.add(e.item);
        }
        List<String> out = new ArrayList<>();
        for (String tv : online) {
            if (tv == null || tv.equals(selfTv) || ticketed.contains(tv) || states.containsKey(tv)) continue;
            out.add(tv);
        }
        return out;
    }

    /** The ticket's value for a TV. */
    static String ticketValue(String url, String ticket) {
        try {
            return new JSONObject().put("url", url).put("ticket", ticket).toString();
        } catch (JSONException e) {
            return null;
        }
    }

    /** This TV's ticket, {url, ticket}, when one was left for it and may still work; null otherwise. */
    static String[] ticketFor(Collection<HouseholdEntry> entries, String selfTv, long nowMs) {
        for (HouseholdEntry e : entries) {
            if (!TICKET.equals(e.kind) || e.deleted || !selfTv.equals(e.item)) continue;
            if (nowMs - HouseholdLog.millisOf(e) >= TICKET_MS) return null;
            try {
                JSONObject value = new JSONObject(e.value);
                String url = HaConfig.normalizeUrl(value.optString("url", ""));
                String ticket = value.optString("ticket", "");
                if (url == null || !HaIntegration.ticketShaped(ticket)) return null;
                return new String[]{url, ticket};
            } catch (JSONException ex) {
                return null;
            }
        }
        return null;
    }
}
