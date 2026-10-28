package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONObject;
import org.junit.After;
import org.junit.Test;

import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** The one Home Assistant events session, against a fake Home Assistant (no network). */
public class HaEventSessionTest {
    private static final String EVENT = "mobile_app_notification_action";
    private static final JSONObject CLOSED = new JSONObject();

    /** A WebSocket to a fake Home Assistant: answers the sign-in and the subscription like the real one. */
    static final class FakeLink implements HaEventSession.Link {
        final BlockingQueue<JSONObject> incoming = new LinkedBlockingQueue<>();
        final List<JSONObject> sent = new CopyOnWriteArrayList<>();
        volatile boolean refuseToken;
        volatile boolean closed;

        FakeLink() {
            incoming.add(json("{\"type\":\"auth_required\"}"));
        }

        @Override
        public String token() {
            return "token-1";
        }

        @Override
        public void send(JSONObject message) throws IOException {
            if (closed) throw new IOException("closed");
            sent.add(message);
            String type = message.optString("type");
            if ("auth".equals(type)) {
                incoming.add(json(refuseToken ? "{\"type\":\"auth_invalid\"}" : "{\"type\":\"auth_ok\"}"));
            } else if ("subscribe_events".equals(type)) {
                incoming.add(json("{\"id\":" + message.optInt("id") + ",\"type\":\"result\",\"success\":true}"));
            }
        }

        @Override
        public JSONObject read() throws Exception {
            JSONObject next = incoming.poll(10, TimeUnit.SECONDS);
            if (next == null) throw new SocketTimeoutException();
            if (next == CLOSED || closed) return null;
            return next;
        }

        @Override
        public void setReadTimeout(int ms) {
        }

        @Override
        public void close() {
            closed = true;
            incoming.add(CLOSED);
        }

        /** Home Assistant sends an event. */
        void event(String action) {
            incoming.add(json("{\"type\":\"event\",\"event\":{\"event_type\":\"" + EVENT
                    + "\",\"data\":{\"action\":\"" + action + "\"}}}"));
        }

        /** Home Assistant goes away (a restart). */
        void drop() {
            incoming.add(CLOSED);
        }

        boolean sentType(String type) {
            for (JSONObject message : sent) if (type.equals(message.optString("type"))) return true;
            return false;
        }
    }

    /** Hands out the links queued for it; an exception queued is thrown (Home Assistant unreachable). */
    static final class FakeDialer implements HaEventSession.Dialer {
        final BlockingQueue<Object> next = new LinkedBlockingQueue<>();
        final List<FakeLink> dialed = new CopyOnWriteArrayList<>();
        volatile String settings = "http://192.0.2.10:8123 sealed-1";
        volatile int dials;

        FakeLink queueLink() {
            FakeLink link = new FakeLink();
            next.add(link);
            return link;
        }

        void queueFailure() {
            next.add(new IOException("connection refused"));
        }

        @Override
        public String settings() {
            return settings;
        }

        @Override
        public HaEventSession.Link dial() throws Exception {
            dials++;
            Object o = next.poll();
            if (o == null) return null;
            if (o instanceof Exception) throw (Exception) o;
            dialed.add((FakeLink) o);
            return (FakeLink) o;
        }
    }

    /** Timers that run only when the test says so. */
    static final class FakeScheduler implements HaEventSession.Scheduler {
        static final class Task {
            final Runnable run;
            final long delayMs;
            volatile boolean cancelled;
            volatile boolean done;

            Task(Runnable run, long delayMs) {
                this.run = run;
                this.delayMs = delayMs;
            }
        }

        final List<Task> tasks = Collections.synchronizedList(new ArrayList<>());

        @Override
        public Runnable schedule(Runnable task, long delayMs) {
            if (delayMs == 0) {
                // "Soon": closing a link; nothing to wait for
                task.run();
                return () -> { };
            }
            Task t = new Task(task, delayMs);
            tasks.add(t);
            return () -> t.cancelled = true;
        }

        /** The live timers with this delay. */
        List<Task> pending(long delayMs) {
            List<Task> out = new ArrayList<>();
            synchronized (tasks) {
                for (Task t : tasks) if (!t.cancelled && !t.done && t.delayMs == delayMs) out.add(t);
            }
            return out;
        }

        List<Long> pendingDelays() {
            List<Long> out = new ArrayList<>();
            synchronized (tasks) {
                for (Task t : tasks) if (!t.cancelled && !t.done) out.add(t.delayMs);
            }
            return out;
        }

        /** Runs the one live timer with this delay. */
        void fire(long delayMs) {
            List<Task> due = pending(delayMs);
            assertEquals("timers of " + delayMs + " ms: " + pendingDelays(), 1, due.size());
            Task t = due.get(0);
            t.done = true;
            t.run.run();
        }
    }

    /** Records what a waiter heard. */
    static final class Recorder implements HaEventSession.Listener {
        final List<String> heard = new CopyOnWriteArrayList<>();
        final List<String> actions = new CopyOnWriteArrayList<>();
        volatile int opens;
        volatile Boolean ended;

        @Override
        public void onOpen(HaEventSession.Waiter waiter) {
            opens++;
            heard.add("open");
        }

        @Override
        public void onEvent(JSONObject data) {
            actions.add(data == null ? null : data.optString("action"));
            heard.add("event");
        }

        @Override
        public void onEnd(boolean listened) {
            ended = listened;
            heard.add("end");
        }
    }

    private final FakeDialer dialer = new FakeDialer();
    private final FakeScheduler scheduler = new FakeScheduler();
    private final List<Thread> threads = new CopyOnWriteArrayList<>();
    // Callbacks run where they're raised, so the test sees them in order
    private final HaEventSession session = new HaEventSession(EVENT, dialer, scheduler, Runnable::run, r -> {
        Thread thread = new Thread(r, "test-ha-events");
        thread.setDaemon(true);
        threads.add(thread);
        thread.start();
    });

    @After
    public void tearDown() throws Exception {
        for (FakeLink link : dialer.dialed) link.close();
        for (Thread thread : threads) thread.join(5_000);
    }

    private static JSONObject json(String text) {
        try {
            return new JSONObject(text);
        } catch (Exception e) {
            throw new AssertionError(e);
        }
    }

    private static void eventually(String what, BooleanSupplier condition) throws InterruptedException {
        long until = System.currentTimeMillis() + 5_000;
        while (!condition.getAsBoolean()) {
            if (System.currentTimeMillis() > until) fail("never: " + what);
            Thread.sleep(5);
        }
    }

    private HaEventSession.Waiter openWaiter(Recorder recorder, long timeoutMs) throws InterruptedException {
        HaEventSession.Waiter waiter = session.await(timeoutMs, recorder);
        eventually("opened", () -> recorder.opens == 1);
        return waiter;
    }

    @Test
    public void signsInWithTheToken_subscribesOnce_thenOpensTheWaiter() throws Exception {
        FakeLink link = dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 120_000);
        JSONObject auth = link.sent.get(0);
        assertEquals("auth", auth.getString("type"));
        assertEquals("token-1", auth.getString("access_token"));
        JSONObject subscribe = link.sent.get(1);
        assertEquals("subscribe_events", subscribe.getString("type"));
        assertEquals(EVENT, subscribe.getString("event_type"));
        assertTrue(session.isActive());
        // The answer's time starts at the open, as a request's did
        assertEquals(1, scheduler.pending(120_000).size());

        // A second waiter shares the connection: no new dial, no second subscription
        Recorder second = new Recorder();
        session.await(120_000, second);
        assertEquals(1, second.opens);
        assertEquals(1, dialer.dials);
        long subscriptions = link.sent.stream().filter(m -> "subscribe_events".equals(m.optString("type"))).count();
        assertEquals(1, subscriptions);
    }

    @Test
    public void aRefusedTokenEndsTheWaiter_withoutListening_andNothingRetries() throws Exception {
        FakeLink link = dialer.queueLink();
        link.refuseToken = true;
        Recorder recorder = new Recorder();
        session.await(120_000, recorder);
        eventually("ended", () -> recorder.ended != null);
        assertFalse(recorder.ended);
        assertEquals(0, recorder.opens);
        assertFalse(link.sentType("subscribe_events"));
        eventually("closed", () -> link.closed);
        assertFalse(session.isActive());
        assertEquals(0, session.waiting());
        assertTrue(scheduler.pendingDelays().isEmpty());
    }

    @Test
    public void unreachableAtFirst_endsTheRequestAsBefore() throws Exception {
        dialer.queueFailure();
        Recorder recorder = new Recorder();
        session.await(120_000, recorder);
        eventually("ended", () -> recorder.ended != null);
        assertFalse(recorder.ended);
        assertTrue(scheduler.pendingDelays().isEmpty());
    }

    @Test
    public void notSetUp_nothingIsHeard() throws Exception {
        // The dialer has nothing to connect to (no address or token)
        Recorder recorder = new Recorder();
        session.await(120_000, recorder);
        eventually("ended", () -> recorder.ended != null);
        assertFalse(recorder.ended);
        assertFalse(session.isActive());
    }

    @Test
    public void eachEventReachesTheOpenWaiters_andAClosedOneHearsNoMore() throws Exception {
        FakeLink link = dialer.queueLink();
        Recorder alex = new Recorder();
        HaEventSession.Waiter alexWaiter = openWaiter(alex, 120_000);
        Recorder sam = new Recorder();
        session.await(120_000, sam);
        assertEquals(1, sam.opens);

        link.event("HEARTH_APPROVE_ALLOW_aa11");
        eventually("both heard it", () -> alex.actions.size() == 1 && sam.actions.size() == 1);
        assertEquals("HEARTH_APPROVE_ALLOW_aa11", alex.actions.get(0));

        alexWaiter.close();
        assertEquals(Boolean.TRUE, alex.ended);
        link.event("HEARTH_PARENT_DENY_bb22");
        eventually("sam heard it", () -> sam.actions.size() == 2);
        assertEquals(1, alex.actions.size());
        assertEquals("[open, event, end]", alex.heard.toString());
        // Sam still waits on the same connection
        assertTrue(session.isActive());
        assertFalse(link.closed);
    }

    @Test
    public void theRightRequestTakesTheAnswer() {
        JSONObject allow = json("{\"action\":\"HEARTH_APPROVE_ALLOW_aa11\"}");
        assertEquals(Boolean.TRUE, HaEvents.answer(allow, "HEARTH_APPROVE_", "aa11"));
        assertEquals(Boolean.FALSE, HaEvents.answer(json("{\"action\":\"HEARTH_APPROVE_DENY_aa11\"}"),
                "HEARTH_APPROVE_", "aa11"));
        // Another request's buttons, the other kind of request, other notifications: not an answer
        assertNull(HaEvents.answer(allow, "HEARTH_APPROVE_", "bb22"));
        assertNull(HaEvents.answer(allow, "HEARTH_PARENT_", "aa11"));
        assertNull(HaEvents.answer(json("{\"action\":\"OPEN_GARAGE\"}"), "HEARTH_APPROVE_", "aa11"));
        assertNull(HaEvents.answer(null, "HEARTH_APPROVE_", "aa11"));
    }

    @Test
    public void aDroppedConnectionIsMadeAgainWithBackoff_andTheAnswerStillArrives() throws Exception {
        FakeLink first = dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 120_000);

        // Home Assistant restarts: the first retry after 1 s fails, the next after 2 s
        first.drop();
        eventually("retry planned", () -> scheduler.pending(1_000).size() == 1);
        assertFalse(session.isActive());
        dialer.queueFailure();
        scheduler.fire(1_000);
        eventually("second retry planned", () -> scheduler.pending(2_000).size() == 1);
        FakeLink second = dialer.queueLink();
        scheduler.fire(2_000);
        eventually("subscribed again", () -> second.sentType("subscribe_events") && session.isActive());

        second.event("HEARTH_APPROVE_ALLOW_aa11");
        eventually("heard", () -> recorder.actions.size() == 1);
        // The request was sent once; the waiter isn't opened again
        assertEquals(1, recorder.opens);
        assertNull(recorder.ended);
        // Its time keeps running from the first open: still one timer
        assertEquals(1, scheduler.pending(120_000).size());

        // Backoff starts over after a good connection
        second.drop();
        eventually("retry planned", () -> scheduler.pending(1_000).size() == 1);
    }

    @Test
    public void theBackoffDoublesUpToAMinute() throws Exception {
        dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 600_000);
        dialer.dialed.get(0).drop();
        long[] expected = {1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000, 60_000};
        for (long delay : expected) {
            eventually("retry after " + delay, () -> scheduler.pending(delay).size() == 1);
            dialer.queueFailure();
            scheduler.fire(delay);
        }
        eventually("still retrying", () -> scheduler.pending(60_000).size() == 1);
        assertNull(recorder.ended);
    }

    @Test
    public void theTimeoutEndsTheWait_andClosesTheConnection() throws Exception {
        FakeLink link = dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 120_000);
        scheduler.fire(120_000);
        assertEquals(Boolean.TRUE, recorder.ended);
        eventually("closed", () -> link.closed);
        assertFalse(session.isActive());
        // No retry and no ping left behind
        eventually("no timers", () -> scheduler.pendingDelays().isEmpty());
    }

    @Test
    public void aTimeoutDuringAnOutageStillEndsOnTime() throws Exception {
        FakeLink link = dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 120_000);
        link.drop();
        eventually("retry planned", () -> scheduler.pending(1_000).size() == 1);
        scheduler.fire(120_000);
        assertEquals(Boolean.TRUE, recorder.ended);
        // The retry was called off with it
        assertTrue(scheduler.pendingDelays().isEmpty());
    }

    @Test
    public void whenNothingWaits_theConnectionCloses_andTheNextRequestConnectsAgain() throws Exception {
        FakeLink first = dialer.queueLink();
        Recorder recorder = new Recorder();
        HaEventSession.Waiter waiter = openWaiter(recorder, 120_000);
        waiter.close();
        assertEquals(Boolean.TRUE, recorder.ended);
        eventually("closed", () -> first.closed);
        assertFalse(session.isActive());
        assertEquals(0, session.waiting());
        Thread.sleep(50);
        // The end of the closed connection plans nothing
        assertTrue(scheduler.pendingDelays().isEmpty());

        FakeLink second = dialer.queueLink();
        Recorder next = new Recorder();
        openWaiter(next, 120_000);
        assertEquals(2, dialer.dials);
        assertTrue(second.sentType("subscribe_events"));
    }

    @Test
    public void aWaiterClosedBeforeItOpens_endsWithoutListening() throws Exception {
        Recorder recorder = new Recorder();
        // The Parent PIN dialog closed while the session was still connecting
        HaEventSession.Waiter waiter = session.await(120_000, recorder);
        waiter.close();
        assertEquals(Boolean.FALSE, recorder.ended);
        assertEquals(0, recorder.opens);
        assertFalse(session.isActive());
    }

    @Test
    public void pingsKeepTheConnectionHonest() throws Exception {
        FakeLink link = dialer.queueLink();
        openWaiter(new Recorder(), 120_000);
        scheduler.fire(HaEventSession.PING_MS);
        assertTrue(link.sentType("ping"));
        // The next one is planned
        assertEquals(1, scheduler.pending(HaEventSession.PING_MS).size());
        // A ping that can't be sent closes the link, and it is made again
        link.closed = true;
        scheduler.fire(HaEventSession.PING_MS);
        eventually("retry planned", () -> scheduler.pending(1_000).size() == 1);
    }

    @Test
    public void newSettingsConnectAgain_theSameOnesChangeNothing() throws Exception {
        FakeLink first = dialer.queueLink();
        Recorder recorder = new Recorder();
        openWaiter(recorder, 120_000);

        session.settingsChanged();
        assertFalse(first.closed);
        assertEquals(1, dialer.dials);

        FakeLink second = dialer.queueLink();
        dialer.settings = "http://192.0.2.11:8123 sealed-2";
        session.settingsChanged();
        eventually("old one closed", () -> first.closed);
        eventually("subscribed with the new settings", () -> second.sentType("subscribe_events") && session.isActive());
        assertEquals(1, recorder.opens);
        second.event("HEARTH_APPROVE_ALLOW_aa11");
        eventually("heard", () -> recorder.actions.size() == 1);
        // The old connection's end plans no retry
        assertTrue(scheduler.pending(1_000).isEmpty());
    }

    @Test
    public void settingsChangedWhileNothingWaits_startsNothing() {
        dialer.settings = "http://192.0.2.11:8123 sealed-2";
        session.settingsChanged();
        assertEquals(0, dialer.dials);
        assertFalse(session.isActive());
    }
}
