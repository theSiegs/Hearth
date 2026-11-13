package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

/** One Home Assistant pairing for the household: who gets a ticket, and reading one's own. */
public class HouseholdHaTest {
    private static final String URL = "http://192.0.2.10:8123";
    private static final String TICKET = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde";

    @Test
    public void aTvSaysItsState() {
        assertEquals(HouseholdHa.PAIRED, HouseholdHa.stateOf(true, true));
        assertEquals(HouseholdHa.LEFT, HouseholdHa.stateOf(false, true));
        assertNull(HouseholdHa.stateOf(false, false));
        // A refused ticket keeps the others from making another for a while
        assertEquals(HouseholdHa.REFUSED, HouseholdHa.stateOf(false, false, true));
        assertEquals(HouseholdHa.LEFT, HouseholdHa.stateOf(false, true, true));
    }

    @Test
    public void onlyTvsOnTheNetworkThatArentPairedOrLeftGetATicket() {
        HouseholdLog study = new HouseholdLog("study");
        HouseholdLog loft = new HouseholdLog("loft");
        long now = 10_000_000L;
        List<HouseholdEntry> entries = new ArrayList<>();
        entries.add(study.put(HouseholdHa.STATE, "", "study", HouseholdHa.PAIRED, now));
        entries.add(loft.put(HouseholdHa.STATE, "", "loft", HouseholdHa.LEFT, now));
        List<String> online = List.of("study", "loft", "attic", "porch", "self");
        // The porch had a ticket a minute ago
        entries.add(study.put(HouseholdHa.TICKET, "", "porch", HouseholdHa.ticketValue(URL, TICKET), now - 60_000));
        assertEquals(List.of("attic"), HouseholdHa.needTickets(entries, "self", online, now));
        // Once that one may have run out, the porch gets another
        assertEquals(List.of("attic", "porch"),
                HouseholdHa.needTickets(entries, "self", online, now + HouseholdHa.TICKET_MS));
    }

    @Test
    public void aTvReadsTheTicketLeftForIt() {
        HouseholdLog study = new HouseholdLog("study");
        long now = 10_000_000L;
        List<HouseholdEntry> entries = List.of(
                study.put(HouseholdHa.TICKET, "", "attic", HouseholdHa.ticketValue(URL, TICKET), now),
                study.put(HouseholdHa.TICKET, "", "porch", HouseholdHa.ticketValue(URL, "not a ticket!"), now));
        assertArrayEquals(new String[]{URL, TICKET}, HouseholdHa.ticketFor(entries, "attic", now + 1_000));
        assertNull(HouseholdHa.ticketFor(entries, "attic", now + HouseholdHa.TICKET_MS));
        assertNull(HouseholdHa.ticketFor(entries, "porch", now));
        assertNull(HouseholdHa.ticketFor(entries, "loft", now));
    }
}
