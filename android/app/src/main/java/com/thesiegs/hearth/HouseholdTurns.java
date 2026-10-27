package com.thesiegs.hearth;

import java.io.Closeable;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Set;

/**
 * Turns on the household thread between the exchanges this TV opens and those other TVs open with it
 * (docs/household-sync.md, "What's checked"). Every exchange runs on the household thread, both the TV's that opened it
 * and the other's: so two TVs that open one with each other at the same moment (they do, right after a join: each
 * hears the other and syncs soon) would each hold its thread on its own exchange, waiting for the other's thread, which
 * is just as busy, until both time out. Here an exchange another TV opens waits for the household thread as before,
 * except while this TV runs one of its own and the other TV comes first (the lower TV id): then this TV's gives way,
 * its connection closed, and the other's goes on at once. So of any two (or any ring of TVs waiting on each other) one
 * always goes on, and the other TV's exchange, a whole exchange both ways, carries what this TV's would have.
 * Nothing here knows about Android, so it can be tested alone.
 */
final class HouseholdTurns {
    /** An exchange another TV opened with this one, its key proved, waiting for the household thread. */
    interface Waiting {
        /** The TV that opened it. */
        String peer();

        /** Goes on with it, on the household thread. Handles its own failures. */
        void serve();
    }

    /** An exchange this TV opens, on the household thread, over the connection {@link #open} was given. */
    interface Exchange {
        void run() throws IOException, GeneralSecurityException;
    }

    enum Outcome {
        /** The exchange ran. */
        DONE,
        /** It gave way to one the other TV (or another) opened with this one at the same time, which went on instead. */
        GAVE_WAY,
    }

    private final ArrayDeque<Waiting> waiting = new ArrayDeque<>();
    /** The connection of the exchange this TV is running now, or null. */
    private Closeable outgoing;
    private boolean gaveWay;
    /** The TVs whose exchanges were served since {@link #forgetServed}. */
    private final Set<String> served = new HashSet<>();

    /**
     * Off the household thread: another TV ({@code from}) opened an exchange with this one ({@code self}), and proved
     * its key. It waits for the household thread; the caller has that thread {@link #serveWaiting}. True when this
     * TV's own exchange, running now, gave way to it.
     */
    synchronized boolean arrived(Waiting from, String self) {
        if (outgoing != null && self != null && from.peer().compareTo(self) < 0) {
            waiting.addFirst(from);
            if (!gaveWay) {
                gaveWay = true;
                try {
                    outgoing.close();
                } catch (IOException ignored) {
                }
            }
            return true;
        }
        waiting.addLast(from);
        return false;
    }

    /** On the household thread: serves the exchanges other TVs opened that are waiting, oldest first (or given way to). */
    void serveWaiting() {
        while (true) {
            Waiting next;
            synchronized (this) {
                next = waiting.pollFirst();
                if (next == null) return;
                served.add(next.peer());
            }
            next.serve();
        }
    }

    /**
     * On the household thread: runs an exchange this TV opens over {@code connection} (which giving way closes), once those
     * waiting have been served; and serves any that came meanwhile right after. Throws what the exchange threw, unless
     * it gave way.
     */
    Outcome open(Closeable connection, Exchange exchange) throws IOException, GeneralSecurityException {
        while (true) {
            serveWaiting();
            synchronized (this) {
                if (waiting.isEmpty()) {
                    outgoing = connection;
                    gaveWay = false;
                    break;
                }
            }
        }
        try {
            exchange.run();
            return Outcome.DONE;
        } catch (IOException | GeneralSecurityException | RuntimeException e) {
            synchronized (this) {
                if (gaveWay) return Outcome.GAVE_WAY;
            }
            throw e;
        } finally {
            synchronized (this) {
                outgoing = null;
            }
            serveWaiting();
        }
    }

    /** A round of exchanges begins: which TVs were served counts from now. */
    synchronized void forgetServed() {
        served.clear();
    }

    /** Whether an exchange {@code peer} opened was served since {@link #forgetServed}: one with it now adds nothing. */
    synchronized boolean served(String peer) {
        return served.contains(peer);
    }
}
