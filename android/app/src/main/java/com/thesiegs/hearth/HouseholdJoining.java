package com.thesiegs.hearth;

import android.content.Context;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Joining a household from the new TV's own screen (docs/household-sync.md, "Joining"), over HouseholdJoin. On a TV of
 * the household it serves one request at a time: the request goes in that TV's notification Bell, on adults'
 * profiles only (HearthBellItems), naming the TV that asks, with Allow and Don't allow. On the new TV it connects to a
 * TV of the household heard on the network, says which TV to answer on, and joins with what comes back.
 */
final class HouseholdJoining {
    private static final String TAG = "HearthHousehold";
    /** How long someone has to answer: time to go to the other TV, turn it on and open its Bell. */
    static final long ANSWER_MS = 5 * 60_000;
    /** A request refused or unanswered holds off the next for this long, so a TV can't be flooded with requests. */
    private static final long COOLDOWN_MS = 30_000;
    private static final int CONNECT_MS = 5_000;
    private static final int TOKEN_DAYS = 3650;
    private static final ExecutorService WORKER = Executors.newCachedThreadPool(r -> {
        Thread thread = new Thread(r, "household-join");
        thread.setDaemon(true);
        return thread;
    });

    // The household TV: the request being answered
    private static boolean sServing;
    private static long sServedUntil;
    private static String sRequestName;
    private static String sRequestCode;
    private static Boolean sScreenAnswer;

    // The new TV: its own request
    static final String NONE = "none";
    static final String CONNECTING = "connecting";
    static final String WAITING = "waiting";
    static final String JOINED = "joined";
    static final String DENIED = "denied";
    static final String FAILED = "failed";
    private static String sJoinState = NONE;
    private static String sJoinCode;
    /** The household's TV this one asked, to answer on. */
    private static String sJoinVia;
    private static Socket sJoinSocket;
    /** Which request is the current one: a worker of an earlier one (cancelled, then started again) stops. */
    private static int sJoinGeneration;

    private HouseholdJoining() {
    }

    // ---- On a TV of the household ----

    /** Serves a join request that has said HouseholdJoin.MAGIC (already read from {@code in}). Closes the socket. */
    static void serve(Context context, Socket socket, InputStream in) {
        try (Socket s = socket) {
            synchronized (HouseholdJoining.class) {
                if (sServing || SystemClock.elapsedRealtime() < sServedUntil) {
                    Log.i(TAG, "A join request came while another was being answered, or too soon after one");
                    return;
                }
                sServing = true;
            }
            s.setSoTimeout((int) ANSWER_MS + 30_000);
            boolean allowed = HouseholdJoin.serve(in, s.getOutputStream(), host(context));
            Log.i(TAG, allowed ? "A TV was allowed to join the household" : "A TV asked to join and wasn't allowed");
            synchronized (HouseholdJoining.class) {
                if (!allowed) sServedUntil = SystemClock.elapsedRealtime() + COOLDOWN_MS;
            }
        } catch (IOException | java.security.GeneralSecurityException e) {
            Log.i(TAG, "A join request ended: " + e.getClass().getSimpleName());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } finally {
            synchronized (HouseholdJoining.class) {
                sServing = false;
                sRequestName = null;
                sRequestCode = null;
                sScreenAnswer = null;
            }
        }
    }

    private static HouseholdJoin.Host host(Context context) {
        return new HouseholdJoin.Host() {
            @Override
            public boolean approve(String name, String code) throws InterruptedException {
                String joiner = name.isEmpty() ? context.getString(R.string.household_join_unnamed) : name;
                synchronized (HouseholdJoining.class) {
                    sRequestName = joiner;
                    sRequestCode = spaced(code);
                    sScreenAnswer = null;
                }
                Log.i(TAG, "A TV asks to join the household");
                HearthBellItems.joinRequestChanged(context, joiner);
                long deadline = SystemClock.elapsedRealtime() + ANSWER_MS;
                try {
                    while (SystemClock.elapsedRealtime() < deadline) {
                        synchronized (HouseholdJoining.class) {
                            if (sScreenAnswer != null) return sScreenAnswer;
                        }
                        Thread.sleep(500);
                    }
                    return false;
                } finally {
                    synchronized (HouseholdJoining.class) {
                        sRequestName = null;
                        sRequestCode = null;
                    }
                    HearthBellItems.joinRequestChanged(context, null);
                }
            }

            @Override
            public String payload(String name, boolean wantsHa) {
                String invitation = Household.invitationToJoin(context);
                if (invitation == null) return null;
                try {
                    JSONObject out = new JSONObject().put("invitation", invitation);
                    String base = HaConfig.baseUrl(context);
                    if (wantsHa && base != null) {
                        String token = HaEvents.mintToken(context, tokenName(name, new Date()), TOKEN_DAYS);
                        if (token != null) out.put("ha", new JSONObject().put("url", base).put("token", token));
                    }
                    return out.toString();
                } catch (Exception e) {
                    return null;
                }
            }
        };
    }

    /** The new TV's token's name in Home Assistant: unique (Home Assistant refuses a name twice). */
    static String tokenName(String joiner, Date now) {
        String stamp = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).format(now);
        String tv = ShareData.tidy(joiner == null ? "" : joiner);
        return "Hearth household: " + (tv.isEmpty() ? "a new TV" : tv) + " " + stamp;
    }

    /** "123456" as "123 456", easier to compare at a glance. */
    static String spaced(String code) {
        return code.length() == 6 ? code.substring(0, 3) + " " + code.substring(3) : code;
    }

    /** The name of the TV whose request waits for an answer, for the Bell; null when none. */
    static synchronized String requestName() {
        return sRequestCode == null ? null : sRequestName;
    }

    /** Someone answered in this TV's Bell. False when no request is waiting. */
    static synchronized boolean answer(boolean allow) {
        if (sRequestCode == null || sScreenAnswer != null) return false;
        sScreenAnswer = allow;
        return true;
    }

    // ---- On the new TV ----

    /**
     * Asks to join the household heard on the network that the Household page offers (the one with the most TVs heard),
     * through the first of its TVs that answers. False when one is already under way or none is heard.
     */
    static boolean start(Context context, String ownHousehold) {
        List<HouseholdNet.Heard> candidates = candidates(HouseholdNet.heard(), ownHousehold);
        int generation;
        synchronized (HouseholdJoining.class) {
            if (CONNECTING.equals(sJoinState) || WAITING.equals(sJoinState)) return false;
            if (candidates.isEmpty()) return false;
            sJoinState = CONNECTING;
            sJoinCode = null;
            sJoinVia = null;
            generation = ++sJoinGeneration;
        }
        Context app = context.getApplicationContext();
        WORKER.execute(() -> run(app, candidates, generation));
        return true;
    }

    /** The TVs to ask: those of the household with the most TVs heard, the same one HouseholdMembers.nearby lists first. */
    static List<HouseholdNet.Heard> candidates(List<HouseholdNet.Heard> heard, String ownHousehold) {
        Map<String, List<HouseholdNet.Heard>> byHousehold = new LinkedHashMap<>();
        for (HouseholdNet.Heard h : heard) {
            if (h.householdId == null || h.householdId.equals(ownHousehold)) continue;
            byHousehold.computeIfAbsent(h.householdId, k -> new ArrayList<>()).add(h);
        }
        List<List<HouseholdNet.Heard>> households = new ArrayList<>(byHousehold.values());
        households.sort((a, b) -> b.size() - a.size());
        List<HouseholdNet.Heard> out = new ArrayList<>();
        if (households.isEmpty()) return out;
        for (HouseholdNet.Heard h : households.get(0)) {
            if (h.host != null && h.port > 0) out.add(h);
        }
        return out;
    }

    private static boolean current(int generation) {
        return generation == sJoinGeneration && (CONNECTING.equals(sJoinState) || WAITING.equals(sJoinState));
    }

    private static void run(Context context, List<HouseholdNet.Heard> candidates, int generation) {
        String outcome = FAILED;
        for (HouseholdNet.Heard tv : candidates) {
            Socket socket = new Socket();
            synchronized (HouseholdJoining.class) {
                if (!current(generation)) return; // cancelled
                sJoinSocket = socket;
            }
            boolean asked = false;
            try {
                socket.connect(new InetSocketAddress(tv.host, tv.port), CONNECT_MS);
                socket.setSoTimeout((int) ANSWER_MS + 30_000);
                HouseholdJoin.Request request = new HouseholdJoin.Request(socket.getInputStream(), socket.getOutputStream());
                String code = request.start(ShareDiscovery.deviceName(context), !HaConfig.isConfigured(context));
                synchronized (HouseholdJoining.class) {
                    if (!current(generation)) return;
                    sJoinState = WAITING;
                    sJoinCode = spaced(code);
                    sJoinVia = tv.name;
                }
                asked = true;
                String payload = request.await();
                outcome = Household.joinFromInvitation(context, payload) ? JOINED : FAILED;
            } catch (ShareSession.ShareException e) {
                outcome = e.stopped ? DENIED : FAILED;
                if (!e.stopped) Log.i(TAG, "Asking to join didn't work: " + e.getMessage());
            } catch (IOException | java.security.GeneralSecurityException e) {
                Log.i(TAG, "Asking to join didn't work: " + e.getClass().getSimpleName());
                outcome = FAILED;
            } finally {
                close(socket);
            }
            // A TV that is off, busy with another request or not taking any: the next one may answer
            if (asked) break;
        }
        synchronized (HouseholdJoining.class) {
            if (current(generation)) sJoinState = outcome;
            if (generation == sJoinGeneration) sJoinSocket = null;
        }
        Log.i(TAG, "Asked to join a household: " + outcome);
    }

    /** Stops a request under way (the person backed out). */
    static void cancel() {
        Socket socket;
        synchronized (HouseholdJoining.class) {
            socket = sJoinSocket;
            sJoinSocket = null;
            sJoinState = NONE;
            sJoinCode = null;
            sJoinVia = null;
        }
        if (socket != null) close(socket);
    }

    /** Where this TV's own request stands, for its screen: {state, code, via (the TV to answer on, when known)}. */
    static synchronized Map<String, Object> status() {
        Map<String, Object> out = new HashMap<>();
        out.put("state", sJoinState);
        out.put("code", sJoinCode);
        out.put("via", sJoinVia);
        return out;
    }

    private static void close(Socket socket) {
        try {
            socket.close();
        } catch (IOException ignored) {
        }
    }
}
