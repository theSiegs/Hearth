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
    /** The waiting request's id in the household's Bells (HouseholdNotices.joinItem). */
    private static String sRequestId;
    private static Boolean sScreenAnswer;
    /**
     * After Allow, while the adult is asked whether the new TV also gets this TV's Home Assistant connection: the
     * question shows ({@link #haQuestion}) until answered, or {@link #HA_ANSWER_MS} without an answer, which is no.
     */
    private static boolean sHaAsking;
    private static Boolean sHaAnswer;
    /** What was decided for the request being served: hand over the Home Assistant connection. */
    private static boolean sGiveHa;
    /** How long the Home Assistant question waits for an answer before the new TV joins without it. */
    static final long HA_ANSWER_MS = 60_000;
    private static final java.security.SecureRandom RANDOM = new java.security.SecureRandom();

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
            s.setSoTimeout((int) (ANSWER_MS + HA_ANSWER_MS) + 30_000);
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
                sRequestId = null;
                sScreenAnswer = null;
                sHaAsking = false;
                sHaAnswer = null;
                sGiveHa = false;
            }
        }
    }

    private static HouseholdJoin.Host host(Context context) {
        return new HouseholdJoin.Host() {
            @Override
            public boolean approve(String name, String code, boolean wantsHa) throws InterruptedException {
                String joiner = name.isEmpty() ? context.getString(R.string.household_join_unnamed) : name;
                // Allowing it asks next about this TV's Home Assistant connection, when it asked for one and there is one
                boolean offersHa = wantsHa && HaConfig.baseUrl(context) != null;
                byte[] random = new byte[12];
                RANDOM.nextBytes(random);
                String requestId = Hex.of(random);
                synchronized (HouseholdJoining.class) {
                    sRequestName = joiner;
                    sRequestCode = spaced(code);
                    sRequestId = requestId;
                    sScreenAnswer = null;
                    sHaAsking = false;
                    sHaAnswer = null;
                    sGiveHa = false;
                }
                Log.i(TAG, "A TV asks to join the household");
                HearthBellItems.joinRequestChanged(context, joiner);
                // The household's other TVs list it too, and can answer it (Household.answerJoin)
                Household.joinRequestStarted(context, requestId, joiner, System.currentTimeMillis() + ANSWER_MS,
                        spaced(code), offersHa);
                long deadline = SystemClock.elapsedRealtime() + ANSWER_MS;
                boolean allowed = false;
                try {
                    while (SystemClock.elapsedRealtime() < deadline) {
                        synchronized (HouseholdJoining.class) {
                            if (sScreenAnswer != null) {
                                allowed = sScreenAnswer;
                                break;
                            }
                        }
                        Thread.sleep(500);
                    }
                } finally {
                    synchronized (HouseholdJoining.class) {
                        sRequestName = null;
                        sRequestCode = null;
                        sRequestId = null;
                    }
                    HearthBellItems.joinRequestChanged(context, null);
                    Household.joinRequestEnded(context, requestId);
                }
                if (!allowed) return false;
                // Within what a TV of an older build waits for the answer (five minutes and a half)
                long left = deadline + 25_000 - SystemClock.elapsedRealtime();
                if (offersHa && left > 0) askAboutHa(context, joiner, Math.min(HA_ANSWER_MS, left));
                return true;
            }

            @Override
            public String payload(String name, boolean wantsHa) {
                String invitation = Household.invitationToJoin(context);
                if (invitation == null) return null;
                boolean giveHa;
                synchronized (HouseholdJoining.class) {
                    giveHa = sGiveHa;
                }
                try {
                    JSONObject out = new JSONObject().put("invitation", invitation);
                    String base = HaConfig.baseUrl(context);
                    // The token is made as now, with this TV's own: it's for the Home Assistant user this TV's panel
                    // signs in as, and shows in that user's profile, where it can be revoked
                    if (wantsHa && giveHa && base != null) {
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

    /**
     * Allow was chosen: asks, on its own and with no as the default, whether the new TV also gets this TV's Home
     * Assistant connection, for up to {@code waitMs}. An Allow from another TV of the household says already.
     */
    private static void askAboutHa(Context context, String joiner, long waitMs) throws InterruptedException {
        synchronized (HouseholdJoining.class) {
            if (sHaAnswer != null) {
                sGiveHa = sHaAnswer;
                return;
            }
            sHaAsking = true;
            sRequestName = joiner;
        }
        HearthBellItems.haQuestionChanged(context, joiner);
        long until = SystemClock.elapsedRealtime() + waitMs;
        boolean give = false;
        try {
            while (SystemClock.elapsedRealtime() < until) {
                synchronized (HouseholdJoining.class) {
                    if (sHaAnswer != null) break;
                }
                Thread.sleep(500);
            }
        } finally {
            synchronized (HouseholdJoining.class) {
                give = Boolean.TRUE.equals(sHaAnswer);
                sGiveHa = give;
                sHaAsking = false;
                sRequestName = null;
            }
            HearthBellItems.haQuestionChanged(context, null);
        }
        Log.i(TAG, give ? "The new TV gets this TV's Home Assistant connection"
                : "The new TV joins without Home Assistant");
    }

    /** The name of the TV allowed to join while this TV asks about its Home Assistant connection; null when not. */
    static synchronized String haQuestion() {
        return sHaAsking ? sRequestName : null;
    }

    /** Answered in this TV's Bell: the new TV gets the Home Assistant connection, or not. False when not asked. */
    static synchronized boolean answerHa(boolean give) {
        if (!sHaAsking || sHaAnswer != null) return false;
        sHaAnswer = give;
        return true;
    }

    // Another TV's join request, allowed here: the Home Assistant question that follows, until answered (no by default)
    private static String sOtherItem;
    private static String sOtherJoiner;
    private static String sOtherAsked;

    /**
     * Allow was chosen here for another TV's request that offers its Home Assistant connection: the Bell asks about it
     * next, and the Allow goes out with the answer, or without the connection after {@link #HA_ANSWER_MS}.
     */
    static void askHaForOther(Context context, String item, String joiner, String askedName) {
        synchronized (HouseholdJoining.class) {
            sOtherItem = item;
            sOtherJoiner = joiner;
            sOtherAsked = askedName;
        }
        HearthBellItems.haQuestionChanged(context, joiner);
        Context app = context.getApplicationContext();
        WORKER.execute(() -> {
            try {
                Thread.sleep(HA_ANSWER_MS);
            } catch (InterruptedException e) {
                return;
            }
            answerHaForOther(app, item, false);
        });
    }

    /** {item, joiner, asked TV's name} of another TV's request whose Home Assistant question shows here; or null. */
    static synchronized String[] otherHaQuestion() {
        return sOtherItem == null ? null : new String[] {sOtherItem, sOtherJoiner, sOtherAsked};
    }

    /** The Home Assistant question for another TV's request answered (or timed out): the Allow goes out with it. */
    static boolean answerHaForOther(Context context, String item, boolean give) {
        synchronized (HouseholdJoining.class) {
            if (item == null || !item.equals(sOtherItem)) return false;
            sOtherItem = null;
            sOtherJoiner = null;
            sOtherAsked = null;
        }
        HearthBellItems.haQuestionChanged(context, null);
        return Household.answerJoin(context, item, true, give);
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

    /** The six digits of the request waiting for an answer ("123 456"), which the new TV shows too; null when none. */
    static synchronized String requestCode() {
        return sRequestCode;
    }

    /** Someone answered in this TV's Bell. False when no request is waiting, or it was answered already. */
    static synchronized boolean answer(boolean allow) {
        if (sRequestCode == null || sScreenAnswer != null) return false;
        sScreenAnswer = allow;
        return true;
    }

    /**
     * The household's entries changed: someone may have answered the waiting request in another TV's Bell. The first
     * answer, here or there, decides; a later one changes nothing.
     */
    static void answeredInHousehold(List<HouseholdEntry> entries) {
        String id;
        synchronized (HouseholdJoining.class) {
            id = sRequestCode == null ? null : sRequestId;
        }
        if (id == null) return;
        String item = HouseholdNotices.joinItem(id);
        Boolean allow = HouseholdNotices.answer(entries, item);
        if (allow == null) return;
        boolean answered;
        synchronized (HouseholdJoining.class) {
            // Still the same request: one that ended meanwhile, and the next, aren't answered by it
            answered = id.equals(sRequestId) && answer(allow);
            // The TV that allowed it asked about the Home Assistant connection itself (an older TV's Allow: not given)
            if (answered && allow) sHaAnswer = HouseholdNotices.answerGivesHa(entries, item);
        }
        if (answered) Log.i(TAG, "A join request was answered on another TV of the household");
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
                // The answer, then the question about Home Assistant's connection that may follow it
                socket.setSoTimeout((int) (ANSWER_MS + HA_ANSWER_MS) + 30_000);
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
