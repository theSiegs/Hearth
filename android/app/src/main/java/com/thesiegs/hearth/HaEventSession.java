package com.thesiegs.hearth;

import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.Executor;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * One WebSocket to Home Assistant, signed in and subscribed to one event type, shared by everything that waits for an
 * event (a phone's answer to an approval request): {@link #await} registers a waiter with a timeout, and the session
 * connects for it. It is open only while something waits: the last waiter to end closes it. While a waiter that has
 * already been told the session is open ({@link Listener#onOpen}) waits, a dropped connection (Home Assistant
 * restarting, the network going) is made again with exponential backoff (1 s doubling up to a minute), so an answer
 * that arrives after the reconnect still reaches it. A waiter that has never been opened ends when a connection attempt
 * fails, as a single request's connection did before the session. A waiter's time starts when it is opened.
 *
 * <p>The socket, the timers and the callback thread are passed in ({@link Link}, {@link Dialer}, {@link Scheduler}),
 * so tests drive it without a network. Callbacks for one waiter come in order (open, events, end) on the callback
 * executor, never with the session's lock held, so a callback may close its waiter.
 */
final class HaEventSession {
    private static final String TAG = "HearthHaEvents";
    static final long FIRST_RETRY_MS = 1_000;
    static final long MAX_RETRY_MS = 60_000;
    /** A ping this often while open, so a connection that died without a word is noticed. */
    static final long PING_MS = 30_000;
    /** Connecting, signing in and subscribing: as long as each step may take. */
    static final int SETUP_TIMEOUT_MS = 5_000;
    /** Open: no message (not even a ping's answer) for this long means the connection is gone. */
    static final int IDLE_TIMEOUT_MS = 75_000;

    /** A WebSocket to Home Assistant's /api/websocket, upgraded but not signed in. */
    interface Link {
        /** The token to sign in with. */
        String token();

        void send(JSONObject message) throws IOException;

        /** The next message; null when the server closed the connection. Throws on a read timeout or a broken one. */
        JSONObject read() throws Exception;

        void setReadTimeout(int ms) throws IOException;

        /** Closes it (from any thread); a read waiting on it ends. */
        void close();
    }

    interface Dialer {
        /** Which address and token are set now, cheap to read; null when Home Assistant isn't set up. */
        String settings();

        /** A new link, or null when there is nothing to connect to (not set up, or refused before connecting). */
        Link dial() throws Exception;
    }

    interface Scheduler {
        /** Runs {@code task} after {@code delayMs} (0: soon, off the caller's thread); returns what cancels it. */
        Runnable schedule(Runnable task, long delayMs);
    }

    /** What a waiter hears. */
    interface Listener {
        /** Subscribed: what will be answered can be sent now. Once per waiter, not again after a reconnect. */
        void onOpen(Waiter waiter);

        /** An event's data (may be null). */
        void onEvent(JSONObject data);

        /**
         * It ended: closed, timed out, or no connection could be made for it. {@code listened} is false when it was
         * never opened (it couldn't subscribe).
         */
        void onEnd(boolean listened);
    }

    /** One wait for events, from {@link #await}. */
    final class Waiter {
        private final Listener mListener;
        private final long mTimeoutMs;
        // Guarded by the session
        private boolean mOpened;
        private boolean mEnded;
        private Runnable mCancelTimeout;

        private Waiter(Listener listener, long timeoutMs) {
            mListener = listener;
            mTimeoutMs = timeoutMs;
        }

        /** Stops waiting (from any thread); {@link Listener#onEnd} follows. */
        void close() {
            end(this);
        }
    }

    private final String mEventType;
    private final Dialer mDialer;
    private final Scheduler mScheduler;
    private final Executor mCallbacks;
    private final Executor mConnections;

    // Guarded by this
    private final List<Waiter> mWaiters = new ArrayList<>();
    /** Bumped whenever the current connection (or attempt) is given up, so a late one changes nothing. */
    private int mGeneration;
    private boolean mConnecting;
    private boolean mSubscribed;
    private Link mLink;
    private String mLinkSettings;
    private int mNextId;
    private long mRetryMs = FIRST_RETRY_MS;
    private Runnable mCancelRetry;
    private Runnable mCancelPing;

    /**
     * @param callbacks where listeners are called, in order
     * @param connections where each connection runs (it blocks reading for as long as it is open)
     */
    HaEventSession(String eventType, Dialer dialer, Scheduler scheduler, Executor callbacks, Executor connections) {
        mEventType = eventType;
        mDialer = dialer;
        mScheduler = scheduler;
        mCallbacks = callbacks;
        mConnections = connections;
    }

    /** The session the app uses: daemon threads that go away while nothing waits. */
    static HaEventSession standard(String eventType, Dialer dialer) {
        ScheduledThreadPoolExecutor timers = new ScheduledThreadPoolExecutor(1, r -> daemon(r, "HearthHaTimers"));
        timers.setKeepAliveTime(10, TimeUnit.SECONDS);
        timers.allowCoreThreadTimeOut(true);
        timers.setRemoveOnCancelPolicy(true);
        ThreadPoolExecutor callbacks = new ThreadPoolExecutor(1, 1, 10, TimeUnit.SECONDS, new LinkedBlockingQueue<>(),
                r -> daemon(r, "HearthHaCallbacks"));
        callbacks.allowCoreThreadTimeOut(true);
        Scheduler scheduler = (task, delayMs) -> {
            ScheduledFuture<?> future = timers.schedule(task, delayMs, TimeUnit.MILLISECONDS);
            return () -> future.cancel(false);
        };
        return new HaEventSession(eventType, dialer, scheduler, callbacks, r -> daemon(r, "HearthHaEvents").start());
    }

    private static Thread daemon(Runnable r, String name) {
        Thread thread = new Thread(r, name);
        thread.setDaemon(true);
        return thread;
    }

    /**
     * Waits up to {@code timeoutMs} (counted from {@link Listener#onOpen}) for events, connecting if nothing else
     * waits. Doesn't block.
     */
    Waiter await(long timeoutMs, Listener listener) {
        Waiter waiter = new Waiter(listener, timeoutMs);
        boolean openNow = false;
        synchronized (this) {
            mWaiters.add(waiter);
            if (mSubscribed) {
                openNow = true;
                markOpened(waiter);
            } else if (!mConnecting) {
                // Idle, or between retries: a new request shouldn't wait out the backoff
                cancelRetry();
                connect();
            }
        }
        if (openNow) mCallbacks.execute(() -> listener.onOpen(waiter));
        return waiter;
    }

    /**
     * The Home Assistant address or token may have changed (HaBridgeService.sync): a connection made with other
     * settings is made again with the new ones. Nothing happens while nothing waits.
     */
    void settingsChanged() {
        Link old;
        synchronized (this) {
            if (mWaiters.isEmpty()) return;
            // The same settings (sync runs often): the connection, or the next retry, stays as it is
            if (Objects.equals(mDialer.settings(), mLinkSettings)) return;
            Log.i(TAG, "Home Assistant settings changed: connecting again");
            old = dropLink();
            cancelRetry();
            mRetryMs = FIRST_RETRY_MS;
            connect();
        }
        closeLater(old);
    }

    /** Whether a connection is open or being made (for tests). */
    synchronized boolean isActive() {
        return mConnecting || mSubscribed;
    }

    /** How many waiters wait (for tests). */
    synchronized int waiting() {
        return mWaiters.size();
    }

    // --- Inside; the methods named *Locked and the ones they call hold the lock ---

    private void connect() {
        int generation = ++mGeneration;
        mConnecting = true;
        mLinkSettings = mDialer.settings();
        mConnections.execute(() -> run(generation));
    }

    /** One connection, from dialing to its end. */
    private void run(int generation) {
        Link link = null;
        try {
            link = mDialer.dial();
            if (link == null) {
                Log.i(TAG, "Home Assistant isn't set up for events");
                return;
            }
            synchronized (this) {
                if (generation != mGeneration) return;
                mLink = link;
                mNextId = 0;
            }
            link.setReadTimeout(SETUP_TIMEOUT_MS);
            JSONObject first = link.read();
            if (first == null || !"auth_required".equals(first.optString("type"))) {
                Log.i(TAG, "Not Home Assistant's WebSocket");
                return;
            }
            link.send(new JSONObject().put("type", "auth").put("access_token", link.token()));
            JSONObject auth = link.read();
            if (auth == null || !"auth_ok".equals(auth.optString("type"))) {
                Log.w(TAG, "Home Assistant refused the token");
                return;
            }
            int id = nextId();
            link.send(new JSONObject().put("id", id).put("type", "subscribe_events").put("event_type", mEventType));
            JSONObject result = link.read();
            if (result == null || result.optInt("id") != id || !result.optBoolean("success")) {
                Log.i(TAG, "Home Assistant didn't take the subscription");
                return;
            }
            link.setReadTimeout(IDLE_TIMEOUT_MS);
            if (!subscribed(generation)) return;
            while (true) {
                JSONObject message = link.read();
                if (message == null) break;
                if ("event".equals(message.optString("type"))) {
                    JSONObject event = message.optJSONObject("event");
                    if (event != null) deliver(event.optJSONObject("data"));
                }
            }
            Log.i(TAG, "Home Assistant closed the events connection");
        } catch (Exception e) {
            Log.i(TAG, "Home Assistant events connection ended: " + e.getClass().getSimpleName());
        } finally {
            if (link != null) link.close();
            ended(generation);
        }
    }

    private synchronized int nextId() {
        return ++mNextId;
    }

    /** Subscribed: opens the waiters that weren't yet, and starts the pings. False when this connection is stale. */
    private boolean subscribed(int generation) {
        List<Waiter> opened = new ArrayList<>();
        synchronized (this) {
            if (generation != mGeneration) return false;
            mConnecting = false;
            mSubscribed = true;
            mRetryMs = FIRST_RETRY_MS;
            for (Waiter waiter : mWaiters) {
                if (!waiter.mOpened) {
                    markOpened(waiter);
                    opened.add(waiter);
                }
            }
            schedulePing(generation);
        }
        for (Waiter waiter : opened) mCallbacks.execute(() -> waiter.mListener.onOpen(waiter));
        return true;
    }

    private void markOpened(Waiter waiter) {
        waiter.mOpened = true;
        waiter.mCancelTimeout = mScheduler.schedule(() -> end(waiter), waiter.mTimeoutMs);
    }

    private void schedulePing(int generation) {
        mCancelPing = mScheduler.schedule(() -> ping(generation), PING_MS);
    }

    private void ping(int generation) {
        Link link;
        int id;
        synchronized (this) {
            if (generation != mGeneration || !mSubscribed || mLink == null) return;
            link = mLink;
            id = ++mNextId;
            schedulePing(generation);
        }
        try {
            link.send(new JSONObject().put("id", id).put("type", "ping"));
        } catch (Exception e) {
            // The read ends with it and the connection is made again
            link.close();
        }
    }

    private void deliver(JSONObject data) {
        List<Waiter> opened = new ArrayList<>();
        synchronized (this) {
            for (Waiter waiter : mWaiters) if (waiter.mOpened) opened.add(waiter);
        }
        for (Waiter waiter : opened) {
            mCallbacks.execute(() -> {
                synchronized (HaEventSession.this) {
                    if (waiter.mEnded) return;
                }
                waiter.mListener.onEvent(data);
            });
        }
    }

    /** A connection (or attempt) ended: waiters never opened end; opened ones wait for a retry. */
    private void ended(int generation) {
        List<Waiter> unopened = new ArrayList<>();
        synchronized (this) {
            if (generation != mGeneration) return;
            mLink = null;
            mConnecting = false;
            mSubscribed = false;
            cancelPing();
            for (Waiter waiter : mWaiters) if (!waiter.mOpened) unopened.add(waiter);
        }
        for (Waiter waiter : unopened) end(waiter);
        synchronized (this) {
            if (generation != mGeneration || mWaiters.isEmpty() || mConnecting || mCancelRetry != null) return;
            long delay = mRetryMs;
            mRetryMs = Math.min(mRetryMs * 2, MAX_RETRY_MS);
            Log.i(TAG, "Connecting to Home Assistant again in " + delay + " ms");
            mCancelRetry = mScheduler.schedule(this::retry, delay);
        }
    }

    private synchronized void retry() {
        mCancelRetry = null;
        if (mWaiters.isEmpty() || mConnecting || mSubscribed) return;
        connect();
    }

    private void end(Waiter waiter) {
        boolean listened;
        Link old = null;
        synchronized (this) {
            if (waiter.mEnded) return;
            waiter.mEnded = true;
            mWaiters.remove(waiter);
            listened = waiter.mOpened;
            if (waiter.mCancelTimeout != null) waiter.mCancelTimeout.run();
            if (mWaiters.isEmpty()) {
                // Nothing waits: no connection kept
                old = dropLink();
                cancelRetry();
                mRetryMs = FIRST_RETRY_MS;
            }
        }
        closeLater(old);
        mCallbacks.execute(() -> waiter.mListener.onEnd(listened));
    }

    /** Gives up the current connection or attempt; returns the link to close (outside the lock). */
    private Link dropLink() {
        mGeneration++;
        Link old = mLink;
        mLink = null;
        mConnecting = false;
        mSubscribed = false;
        cancelPing();
        return old;
    }

    private void cancelRetry() {
        if (mCancelRetry != null) mCancelRetry.run();
        mCancelRetry = null;
    }

    private void cancelPing() {
        if (mCancelPing != null) mCancelPing.run();
        mCancelPing = null;
    }

    /** Closing a TLS socket writes to it: never on the caller's (maybe main) thread. */
    private void closeLater(Link link) {
        if (link != null) mScheduler.schedule(link::close, 0);
    }
}
