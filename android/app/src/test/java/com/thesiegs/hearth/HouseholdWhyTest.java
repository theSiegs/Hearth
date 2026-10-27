package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.net.SocketTimeoutException;
import java.util.concurrent.ExecutionException;

import org.junit.Test;

/** What the household's log lines say went wrong: the exception's class, and its message. */
public class HouseholdWhyTest {
    @Test
    public void aLineNamesTheClassAndTheMessage() {
        assertEquals("SyncException: The other TV is not in this household",
                Household.why(new HouseholdSync.SyncException("The other TV is not in this household")));
        assertEquals("SocketTimeoutException: Read timed out", Household.why(new SocketTimeoutException("Read timed out")));
    }

    @Test
    public void withoutAMessageItIsTheClass() {
        assertEquals("SocketTimeoutException", Household.why(new SocketTimeoutException()));
        assertEquals("EOFException", Household.why(new java.io.EOFException(" ")));
    }

    @Test
    public void aTaskThatFailedNamesWhatEndedIt() {
        assertEquals("SyncException: Bad frame size",
                Household.why(new ExecutionException(new HouseholdSync.SyncException("Bad frame size"))));
    }

    @Test
    public void aLongMessageIsCutAndKeptOnOneLine() {
        String why = Household.why(new java.io.IOException("first\nsecond " + "x".repeat(500)));
        assertTrue(why.startsWith("IOException: first second x"));
        assertTrue(why.length() < 200);
    }
}
