package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import java.io.Closeable;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.Test;

/**
 * Two TVs that open an exchange with each other at the same moment, as they do right after one joins: each household
 * thread runs every exchange, its own and the other's, so without turns each waits on the other until both time out.
 */
public class HouseholdTurnsTest {
    private static final long T0 = 1_800_000_000_000L;

    // ---- The turns alone ----

    /** An exchange another TV opened, which notes when it is served. */
    private static final class Opened implements HouseholdTurns.Waiting {
        final String peer;
        final List<String> log;

        Opened(String peer, List<String> log) {
            this.peer = peer;
            this.log = log;
        }

        @Override
        public String peer() {
            return peer;
        }

        @Override
        public void serve() {
            log.add("served " + peer);
        }
    }

    private static final class Connection implements Closeable {
        boolean closed;

        @Override
        public void close() {
            closed = true;
        }
    }

    @Test
    public void anExchangeOpenedWhileTheThreadIsFreeWaitsForIt() {
        HouseholdTurns turns = new HouseholdTurns();
        List<String> log = new ArrayList<>();
        assertFalse(turns.arrived(new Opened("tv-a", log), "tv-b"));
        assertTrue(log.isEmpty());
        turns.serveWaiting();
        assertEquals(List.of("served tv-a"), log);
        assertTrue(turns.served("tv-a"));
        turns.forgetServed();
        assertFalse(turns.served("tv-a"));
    }

    @Test
    public void whileThisTvRunsItsOwnTheLowerIdGoesOnAndTheHigherWaits() throws Exception {
        HouseholdTurns turns = new HouseholdTurns();
        List<String> log = new ArrayList<>();
        Connection mine = new Connection();
        boolean[] gave = new boolean[2];
        HouseholdTurns.Outcome outcome = turns.open(mine, () -> {
            // A higher id than this TV's waits for this TV's exchange to end
            gave[0] = turns.arrived(new Opened("tv-c", log), "tv-b");
            assertFalse(mine.closed);
            // A lower one: this TV's gives way, its connection closed (the exchange then fails)
            gave[1] = turns.arrived(new Opened("tv-a", log), "tv-b");
            assertTrue(mine.closed);
            throw new java.net.SocketException("Socket closed");
        });
        assertEquals(HouseholdTurns.Outcome.GAVE_WAY, outcome);
        assertFalse(gave[0]);
        assertTrue(gave[1]);
        // The one given way to first, then the one that waited
        assertEquals(List.of("served tv-a", "served tv-c"), log);
    }

    @Test
    public void exchangesThatWereWaitingGoBeforeThisTvsOwn() throws Exception {
        HouseholdTurns turns = new HouseholdTurns();
        List<String> log = new ArrayList<>();
        turns.arrived(new Opened("tv-c", log), "tv-b");
        assertEquals(HouseholdTurns.Outcome.DONE, turns.open(new Connection(), () -> log.add("mine")));
        assertEquals(List.of("served tv-c", "mine"), log);
    }

    @Test
    public void aFailureThatIsntGivingWayIsTheCallers() {
        HouseholdTurns turns = new HouseholdTurns();
        try {
            turns.open(new Connection(), () -> {
                throw new SocketTimeoutException("Read timed out");
            });
            throw new AssertionError("expected the failure");
        } catch (SocketTimeoutException expected) {
            // the caller logs it
        } catch (Exception e) {
            throw new AssertionError(e);
        }
    }

    // ---- Two TVs over real sockets ----

    /** A TV as Household runs it: a household thread for every exchange, and a network thread reading openings. */
    private static final class MiniTv implements Closeable {
        final HouseholdStore store;
        final boolean turns;
        final int timeoutMs;
        final HouseholdTurns turn = new HouseholdTurns();
        final ExecutorService household = Executors.newSingleThreadExecutor();
        final ExecutorService net = Executors.newCachedThreadPool();
        final ServerSocket server;

        MiniTv(HouseholdStore store, boolean turns, int timeoutMs) throws IOException {
            this.store = store;
            this.turns = turns;
            this.timeoutMs = timeoutMs;
            server = new ServerSocket(0, 8, InetAddress.getLoopbackAddress());
            net.execute(this::listen);
        }

        private void listen() {
            while (!server.isClosed()) {
                try {
                    Socket socket = server.accept();
                    net.execute(() -> route(socket));
                } catch (IOException e) {
                    return;
                }
            }
        }

        /** Household.route: the opening off the household thread, the rest on it. */
        private void route(Socket socket) {
            try {
                socket.setSoTimeout(timeoutMs);
                HouseholdSync.Accepted opened = HouseholdSync.accept(socket.getInputStream(), socket.getOutputStream(),
                        store.tvId(), store.householdId());
                HouseholdTurns.Waiting waiting = new HouseholdTurns.Waiting() {
                    @Override
                    public String peer() {
                        return opened.peer();
                    }

                    @Override
                    public void serve() {
                        try (Socket s = socket) {
                            HouseholdSync.run(opened, store, null, "TV", T0 + 100);
                        } catch (Exception e) {
                            // the other TV gave way, or timed out
                        }
                    }
                };
                if (turns) {
                    turn.arrived(waiting, store.tvId());
                    household.execute(turn::serveWaiting);
                } else {
                    household.execute(waiting::serve);
                }
            } catch (Exception e) {
                try {
                    socket.close();
                } catch (IOException ignored) {
                }
            }
        }

        /** Household.exchangeWith, on the household thread, once both TVs' threads are in theirs. */
        Future<Object> syncWith(MiniTv other, CountDownLatch bothBusy) {
            return household.submit(() -> {
                bothBusy.countDown();
                bothBusy.await(5, TimeUnit.SECONDS);
                try (Socket socket = new Socket()) {
                    HouseholdTurns.Exchange exchange = () -> {
                        socket.connect(new InetSocketAddress(InetAddress.getLoopbackAddress(),
                                other.server.getLocalPort()), 2000);
                        socket.setSoTimeout(timeoutMs);
                        HouseholdSync.run(socket.getInputStream(), socket.getOutputStream(), true, store, "TV",
                                T0 + 100);
                    };
                    if (turns) return turn.open(socket, exchange);
                    exchange.run();
                    return HouseholdTurns.Outcome.DONE;
                } catch (Exception e) {
                    return e;
                }
            });
        }

        /** What's left on the household thread (the exchanges that waited) is done. */
        void settle() throws Exception {
            household.submit(() -> { }).get(10, TimeUnit.SECONDS);
        }

        @Override
        public void close() throws IOException {
            server.close();
            household.shutdownNow();
            net.shutdownNow();
        }
    }

    /** Two TVs of one household that have met, each with a look the other hasn't got. */
    private static HouseholdTvs.Tv[] household() throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv b = new HouseholdTvs.Tv();
        assertTrue(b.store.join(a.store.invite("Office", T0), "Kitchen", T0));
        HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 50);
        a.store.log().put("look", "Alex", "theme", "dark", T0 + 60);
        b.store.log().put("look", "Sam", "theme", "light", T0 + 61);
        return new HouseholdTvs.Tv[] {a, b};
    }

    @Test
    public void withoutTurnsTwoTvsSyncingWithEachOtherAtOnceBothTimeOut() throws Exception {
        HouseholdTvs.Tv[] tvs = household();
        try (MiniTv a = new MiniTv(tvs[0].store, false, 1000); MiniTv b = new MiniTv(tvs[1].store, false, 1000)) {
            CountDownLatch bothBusy = new CountDownLatch(2);
            Future<Object> aToB = a.syncWith(b, bothBusy);
            Future<Object> bToA = b.syncWith(a, bothBusy);
            // Each thread waits for the other's answer, which waits behind that thread's own exchange
            assertTrue(String.valueOf(aToB.get(10, TimeUnit.SECONDS)),
                    aToB.get(10, TimeUnit.SECONDS) instanceof SocketTimeoutException);
            assertTrue(String.valueOf(bToA.get(10, TimeUnit.SECONDS)),
                    bToA.get(10, TimeUnit.SECONDS) instanceof SocketTimeoutException);
        }
    }

    @Test
    public void withTurnsOneGoesOnAtOnceAndBothTvsHaveEverything() throws Exception {
        HouseholdTvs.Tv[] tvs = household();
        try (MiniTv a = new MiniTv(tvs[0].store, true, 5000); MiniTv b = new MiniTv(tvs[1].store, true, 5000)) {
            CountDownLatch bothBusy = new CountDownLatch(2);
            long started = System.nanoTime();
            Future<Object> aToB = a.syncWith(b, bothBusy);
            Future<Object> bToA = b.syncWith(a, bothBusy);
            Object fromA = aToB.get(10, TimeUnit.SECONDS);
            Object fromB = bToA.get(10, TimeUnit.SECONDS);
            a.settle();
            b.settle();
            long tookMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started);
            assertTrue(String.valueOf(fromA), fromA instanceof HouseholdTurns.Outcome);
            assertTrue(String.valueOf(fromB), fromB instanceof HouseholdTurns.Outcome);
            // Not both gave way: one of them went on
            assertFalse(fromA == HouseholdTurns.Outcome.GAVE_WAY && fromB == HouseholdTurns.Outcome.GAVE_WAY);
            // Well within one read timeout: nothing waited on a thread that was waiting too
            assertTrue("took " + tookMs + " ms", tookMs < 4000);
            for (HouseholdStore store : new HouseholdStore[] {tvs[0].store, tvs[1].store}) {
                assertEquals("dark", store.log().get("look", "Alex", "theme").value);
                assertEquals("light", store.log().get("look", "Sam", "theme").value);
            }
            assertNotEquals(tvs[0].store.tvId(), tvs[1].store.tvId());
        }
    }
}
