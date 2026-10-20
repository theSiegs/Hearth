package com.thesiegs.hearth;

import android.util.Log;

import java.io.IOException;
import java.net.ConnectException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * One copy of a profile between two TVs, as the screens drive it: the TV that has the profile listens
 * ({@link #startSending}), the TV that wants it connects ({@link #startReceiving}), both show the same six digits
 * (ShareSession), a parent says on each whether they match ({@link #confirm}), and the bundle moves one way and a
 * short report the other. Only one copy runs at a time and nothing is kept after it: no key, no peer.
 *
 * <p>Answers only addresses on the home network (LocalNet). A stray connection to the sending TV that doesn't get as
 * far as the digits is dropped and the TV goes on listening; one whose digits the parent says don't match is refused
 * and the TV listens again, up to {@link #MAX_MISMATCHES} times. The screens read {@link #status} now and then.
 */
final class ShareService {
    private static final String TAG = "HearthShare";

    static final String WAITING = "waiting";
    static final String CONNECTING = "connecting";
    static final String DIGITS = "digits";
    static final String WORKING = "working";
    /** The receiver has the bundle and waits for the screen to apply it and send a report. */
    static final String RECEIVED = "received";
    static final String DONE = "done";
    static final String FAILED = "failed";

    static final int[] PORTS = {8770, 8771, 8772, 8773, 8774};
    static final int MAX_BUNDLE_BYTES = 40 * 1024 * 1024;
    /** The secrets (PINs, Home Assistant) are small. */
    static final int MAX_SECRETS_BYTES = 256 * 1024;
    static final int MAX_REPORT_BYTES = 64 * 1024;
    static final int MAX_MISMATCHES = 3;
    private static final int MAX_STRAY = 8;

    /** How long each step may take: the key exchange, a parent looking at two screens, the transfer. */
    static final class Timeouts {
        long lifetimeMs = 10 * 60_000;
        int handshakeMs = 10_000;
        int confirmMs = 5 * 60_000;
        int transferMs = 60_000;
        int applyMs = 10 * 60_000;
    }

    private static ShareService sCurrent;

    private final boolean mSender;
    private final Timeouts mTimeouts;
    private final BlockingQueue<Boolean> mConfirm = new ArrayBlockingQueue<>(1);
    private final BlockingQueue<String> mReportOut = new ArrayBlockingQueue<>(1);
    private ServerSocket mServer;
    private volatile Socket mSocket;
    private volatile boolean mStopped;
    private String mState = WAITING;
    private String mDigits;
    private String mError;
    private String mBundle;
    /** The sender builds the secrets message when the transfer starts (not before both parents said yes). */
    private java.util.function.Supplier<String> mSecretsSource;
    /** What the receiver got; only Java reads it (ShareSecrets). */
    private String mSecrets;
    /** Something the sending screen should say about the secrets ("ha_failed"). */
    private String mNote;
    private String mReport;
    private int mMismatches;

    private ShareService(boolean sender, Timeouts timeouts) {
        mSender = sender;
        mTimeouts = timeouts;
    }

    // ---- What the screens call ----

    /** Starts listening to send {@code bundleJson}; returns {port} or null if no port is free. */
    static synchronized Map<String, Object> startSending(String bundleJson) {
        return startSending(bundleJson, null);
    }

    /** As above, with the secrets to send (made once both parents said the digits match) or null for none. */
    static synchronized Map<String, Object> startSending(String bundleJson, java.util.function.Supplier<String> secrets) {
        stop();
        ShareService service = openSender(bundleJson, secrets, new Timeouts());
        if (service == null) return null;
        sCurrent = service;
        Map<String, Object> started = new HashMap<>();
        started.put("port", service.port());
        return started;
    }

    /** Connects to the sending TV at {@code host}:{@code port} to receive its bundle. */
    static synchronized void startReceiving(String host, int port) {
        stop();
        sCurrent = openReceiver(host, port, new Timeouts());
    }

    /** Where it stands: {state, digits?, error?, report?}. "idle" when no copy has started. */
    static synchronized Map<String, Object> status() {
        ShareService service = sCurrent;
        if (service != null) return service.snapshot();
        Map<String, Object> status = new HashMap<>();
        status.put("state", "idle");
        return status;
    }

    /** The parent saw the same digits on both TVs ({@code same}) or didn't. */
    static synchronized void confirm(boolean same) {
        if (sCurrent != null) sCurrent.answer(same);
    }

    /** The bundle the receiver got, once; null if it hasn't one. */
    static synchronized String takeBundle() {
        return sCurrent == null ? null : sCurrent.takeReceived();
    }

    /** The secrets the receiver got (for ShareSecrets on this side only); null if there are none. */
    static synchronized String secrets() {
        return sCurrent == null ? null : sCurrent.receivedSecrets();
    }

    /** The receiver's screen has applied the bundle: sends its report back and finishes. */
    static synchronized void sendReport(String report) {
        if (sCurrent != null) sCurrent.reportBack(report);
    }

    static synchronized void stop() {
        ShareService service = sCurrent;
        sCurrent = null;
        if (service != null) service.close();
    }

    // ---- One copy ----

    /** A sending copy, already listening; null if no port is free. For {@link #startSending} and tests. */
    static ShareService openSender(String bundleJson, Timeouts timeouts) {
        return openSender(bundleJson, null, timeouts);
    }

    static ShareService openSender(String bundleJson, java.util.function.Supplier<String> secrets, Timeouts timeouts) {
        ShareService service = new ShareService(true, timeouts);
        service.mBundle = bundleJson;
        service.mSecretsSource = secrets;
        for (int port : PORTS) {
            try {
                service.mServer = new ServerSocket(port);
                break;
            } catch (IOException ignored) {
            }
        }
        if (service.mServer == null) return null;
        Thread thread = new Thread(service::runSender, "HearthShareSend");
        thread.setDaemon(true);
        thread.start();
        return service;
    }

    static ShareService openReceiver(String host, int port, Timeouts timeouts) {
        ShareService service = new ShareService(false, timeouts);
        service.mState = CONNECTING;
        Thread thread = new Thread(() -> service.runReceiver(host, port), "HearthShareReceive");
        thread.setDaemon(true);
        thread.start();
        return service;
    }

    int port() {
        return mServer.getLocalPort();
    }

    synchronized Map<String, Object> snapshot() {
        Map<String, Object> status = new HashMap<>();
        status.put("role", mSender ? "sender" : "receiver");
        status.put("state", mState);
        if (DIGITS.equals(mState)) status.put("digits", mDigits);
        if (mError != null) status.put("error", mError);
        if (mReport != null) status.put("report", mReport);
        if (mNote != null) status.put("note", mNote);
        status.put("mismatches", mMismatches);
        return status;
    }

    void answer(boolean same) {
        mConfirm.offer(same);
    }

    synchronized String takeReceived() {
        if (!RECEIVED.equals(mState) || mBundle == null) return null;
        String bundle = mBundle;
        mBundle = null;
        return bundle;
    }

    synchronized String receivedSecrets() {
        return RECEIVED.equals(mState) ? mSecrets : null;
    }

    void reportBack(String report) {
        mReportOut.offer(report == null ? "" : report);
    }

    void close() {
        mStopped = true;
        synchronized (this) {
            mSecrets = null;
        }
        try {
            if (mServer != null) mServer.close();
        } catch (IOException ignored) {
        }
        try {
            Socket socket = mSocket;
            if (socket != null) socket.close();
        } catch (IOException ignored) {
        }
        mConfirm.offer(false);
        mReportOut.offer("");
    }

    // ---- The two sides ----

    private void runSender() {
        long deadline = System.currentTimeMillis() + mTimeouts.lifetimeMs;
        int stray = 0;
        try {
            mServer.setSoTimeout(1000);
            while (!mStopped && System.currentTimeMillis() < deadline) {
                Socket socket;
                try {
                    socket = mServer.accept();
                } catch (SocketTimeoutException e) {
                    continue;
                }
                mSocket = socket;
                try (Socket s = socket) {
                    if (!LocalNet.isLocal(s.getInetAddress())) continue;
                    Outcome outcome = senderSession(s);
                    if (outcome == Outcome.FINISHED) return;
                    if (outcome == Outcome.STRAY && ++stray >= MAX_STRAY) {
                        fail("too_many");
                        return;
                    }
                    if (outcome == Outcome.REFUSED && mMismatches >= MAX_MISMATCHES) {
                        fail("mismatch");
                        return;
                    }
                } catch (IOException | GeneralSecurityException | RuntimeException e) {
                    Log.i(TAG, "A connection ended: " + e.getClass().getSimpleName());
                    if (!mStopped) stray++;
                }
                setState(WAITING, null);
            }
            if (!mStopped) fail("timeout");
        } catch (IOException e) {
            if (!mStopped) fail("network");
        } finally {
            try {
                mServer.close();
            } catch (IOException ignored) {
            }
        }
    }

    private enum Outcome { FINISHED, STRAY, REFUSED }

    /** One connection to the sending TV, as far as it goes. */
    private Outcome senderSession(Socket socket) throws IOException, GeneralSecurityException {
        socket.setSoTimeout(mTimeouts.handshakeMs);
        ShareSession session = ShareSession.sender(socket.getInputStream(), socket.getOutputStream());
        String digits;
        try {
            digits = session.handshake();
        } catch (ShareSession.ShareException | SocketTimeoutException e) {
            Log.i(TAG, "A connection didn't get as far as the digits");
            return Outcome.STRAY;
        }
        mConfirm.clear();
        setState(DIGITS, digits);
        Boolean same = awaitConfirm();
        if (mStopped) return Outcome.FINISHED;
        if (same == null || !same) {
            session.abort();
            finish(socket);
            synchronized (this) {
                mMismatches++;
            }
            return Outcome.REFUSED;
        }
        setState(WORKING, null);
        socket.setSoTimeout(mTimeouts.confirmMs);
        try {
            session.confirm();
        } catch (IOException e) {
            // The other TV's parent saw different digits (or the other TV went): listen again
            synchronized (this) {
                mMismatches++;
            }
            return Outcome.REFUSED;
        }
        socket.setSoTimeout(mTimeouts.transferMs);
        String bundle;
        synchronized (this) {
            bundle = mBundle;
        }
        session.send(bundle.getBytes(StandardCharsets.UTF_8));
        String secrets = mSecretsSource == null ? "{\"v\":1}" : mSecretsSource.get();
        if (secrets.contains("\"haFailed\":true")) {
            synchronized (this) {
                mNote = "ha_failed";
            }
        }
        session.send(secrets.getBytes(StandardCharsets.UTF_8));
        socket.setSoTimeout(mTimeouts.applyMs);
        byte[] report = session.receive(MAX_REPORT_BYTES);
        synchronized (this) {
            mReport = new String(report, StandardCharsets.UTF_8);
            mBundle = null;
        }
        setState(DONE, null);
        return Outcome.FINISHED;
    }

    private void runReceiver(String host, int port) {
        try (Socket socket = new Socket()) {
            mSocket = socket;
            InetAddress address = InetAddress.getByName(host);
            if (!LocalNet.isLocal(address)) {
                fail("not_local");
                return;
            }
            socket.connect(new InetSocketAddress(address, port), 5000);
            socket.setSoTimeout(mTimeouts.handshakeMs);
            ShareSession session = ShareSession.receiver(socket.getInputStream(), socket.getOutputStream());
            String digits = session.handshake();
            mConfirm.clear();
            setState(DIGITS, digits);
            Boolean same = awaitConfirm();
            if (mStopped) return;
            if (same == null || !same) {
                session.abort();
                finish(socket);
                fail("mismatch");
                return;
            }
            setState(WORKING, null);
            socket.setSoTimeout(mTimeouts.confirmMs);
            session.confirm();
            socket.setSoTimeout(mTimeouts.transferMs);
            byte[] bundle = session.receive(MAX_BUNDLE_BYTES);
            byte[] secrets = session.receive(MAX_SECRETS_BYTES);
            synchronized (this) {
                mBundle = new String(bundle, StandardCharsets.UTF_8);
                mSecrets = new String(secrets, StandardCharsets.UTF_8);
            }
            setState(RECEIVED, null);
            String report = mReportOut.poll(mTimeouts.applyMs, TimeUnit.MILLISECONDS);
            if (mStopped) return;
            if (report == null) {
                fail("timeout");
                return;
            }
            socket.setSoTimeout(mTimeouts.transferMs);
            session.send(report.getBytes(StandardCharsets.UTF_8));
            synchronized (this) {
                mSecrets = null;
            }
            setState(DONE, null);
        } catch (UnknownHostException e) {
            if (!mStopped) fail("network");
        } catch (ConnectException | java.net.NoRouteToHostException e) {
            if (!mStopped) fail("network");
        } catch (SocketTimeoutException e) {
            if (!mStopped) fail("timeout");
        } catch (ShareSession.ShareException e) {
            if (!mStopped) fail(e.getMessage() != null && e.getMessage().contains("stopped") ? "peer_stopped"
                    : e.getMessage() != null && e.getMessage().contains("More than") ? "too_big" : "protocol");
        } catch (IOException | GeneralSecurityException | RuntimeException e) {
            Log.i(TAG, "The copy ended: " + e.getClass().getSimpleName());
            if (!mStopped) fail("network");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Ends a connection after an abort without a reset: closing a socket that still has unread data makes TCP reset
     * it, and the other end then loses the abort. Says no more, waits briefly for the other end to finish, then closes.
     */
    private static void finish(Socket socket) {
        try {
            socket.shutdownOutput();
            socket.setSoTimeout(500);
            byte[] sink = new byte[512];
            while (socket.getInputStream().read(sink) >= 0) {
                // The other end's last frames: not needed
            }
        } catch (IOException ignored) {
        }
    }

    /** The parent's answer, or null when none came in time (or the copy was stopped). */
    private Boolean awaitConfirm() {
        try {
            return mConfirm.poll(mTimeouts.confirmMs, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    private synchronized void setState(String state, String digits) {
        mState = state;
        mDigits = digits;
        if (!FAILED.equals(state)) mError = null;
    }

    private synchronized void fail(String error) {
        if (mStopped) return;
        mState = FAILED;
        mDigits = null;
        mError = error;
        mBundle = null;
        mSecrets = null;
    }
}
