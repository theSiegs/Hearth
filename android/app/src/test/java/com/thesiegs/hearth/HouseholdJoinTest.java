package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.DataInputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import org.json.JSONObject;
import org.junit.Test;

/** A new TV asking a household TV to join: the code both show, what a parent's answer does, and the first sync after. */
public class HouseholdJoinTest {
    private static final long T0 = 1_800_000_000_000L;

    /** What the household TV saw: the name and code it asked a parent about. */
    private static final class Asked {
        final AtomicReference<String> name = new AtomicReference<>();
        final AtomicReference<String> code = new AtomicReference<>();
        final java.util.concurrent.atomic.AtomicBoolean wantsHa = new java.util.concurrent.atomic.AtomicBoolean();
    }

    private static HouseholdJoin.Host host(HouseholdTvs.Tv tv, boolean allow, Asked asked) {
        return new HouseholdJoin.Host() {
            @Override
            public boolean approve(String name, String code, boolean wantsHa) {
                asked.name.set(name);
                asked.code.set(code);
                asked.wantsHa.set(wantsHa);
                return allow;
            }

            @Override
            public String payload(String name, boolean wantsHa) {
                try {
                    JSONObject out = new JSONObject().put("invitation", tv.store.invite("Office", T0).toJson());
                    if (wantsHa) out.put("ha", new JSONObject().put("url", "http://192.0.2.10:8123").put("token", "t"));
                    return out.toString();
                } catch (Exception e) {
                    return null;
                }
            }
        };
    }

    /** Runs one request; returns {the code the new TV showed, the payload it got}, or throws what the new TV got. */
    private static String[] ask(HouseholdJoin.Host host, String name) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try (ServerSocket server = new ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
            server.setSoTimeout(5000);
            Future<Boolean> serving = pool.submit(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(5000);
                    DataInputStream in = new DataInputStream(socket.getInputStream());
                    byte[] magic = new byte[4];
                    in.readFully(magic);
                    assertTrue(Arrays.equals(HouseholdJoin.MAGIC, magic));
                    return HouseholdJoin.serve(in, socket.getOutputStream(), host);
                }
            });
            Future<String[]> asking = pool.submit(() -> {
                try (Socket socket = new Socket(java.net.InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                    socket.setSoTimeout(5000);
                    HouseholdJoin.Request request = new HouseholdJoin.Request(socket.getInputStream(), socket.getOutputStream());
                    String code = request.start(name, true);
                    return new String[] {code, request.await()};
                }
            });
            try {
                return asking.get(10, TimeUnit.SECONDS);
            } finally {
                try {
                    serving.get(10, TimeUnit.SECONDS);
                } catch (Exception ignored) {
                }
            }
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    public void anAllowedTvGetsAnInvitationAndTheFirstSyncListsIt() throws Exception {
        HouseholdTvs.Tv household = new HouseholdTvs.Tv();
        household.store.create("Office", T0);
        Asked asked = new Asked();
        String[] got = ask(host(household, true, asked), "Kitchen");
        // the parent was asked about the code the new TV shows
        assertEquals("Kitchen", asked.name.get());
        assertEquals(got[0], asked.code.get());
        assertTrue(got[0].matches("[0-9]{6}"));
        // it said it has no Home Assistant connection: the household TV asks about giving it one, separately
        assertTrue(asked.wantsHa.get());
        JSONObject payload = new JSONObject(got[1]);
        assertEquals("http://192.0.2.10:8123", payload.getJSONObject("ha").getString("url"));
        HouseholdTvs.Tv joining = new HouseholdTvs.Tv();
        assertTrue(joining.store.join(HouseholdStore.Invitation.fromJson(payload.getString("invitation")), "Kitchen", T0));
        assertEquals(household.store.householdId(), joining.store.householdId());
        // the household TV hasn't listed it yet; the first exchange does
        assertEquals(HouseholdMembers.Standing.UNKNOWN,
                HouseholdMembers.standing(household.store.log(), joining.store.tvId()));
        HouseholdSyncExchangeTest.exchange(joining.store, household.store, null, T0 + 100);
        assertEquals(HouseholdMembers.Standing.MEMBER,
                HouseholdMembers.standing(household.store.log(), joining.store.tvId()));
    }

    @Test
    public void aDeniedTvGetsNothing() throws Exception {
        HouseholdTvs.Tv household = new HouseholdTvs.Tv();
        household.store.create("Office", T0);
        try {
            ask(host(household, false, new Asked()), "Kitchen");
            fail("expected a refusal");
        } catch (java.util.concurrent.ExecutionException expected) {
            assertTrue(expected.getCause() instanceof ShareSession.ShareException);
            // told apart from a broken connection: the household TV said no
            assertTrue(((ShareSession.ShareException) expected.getCause()).stopped);
        }
    }

    @Test
    public void aLongOrOddNameIsTidiedBeforeAParentSeesIt() throws Exception {
        HouseholdTvs.Tv household = new HouseholdTvs.Tv();
        household.store.create("Office", T0);
        Asked asked = new Asked();
        StringBuilder longName = new StringBuilder();
        for (int i = 0; i < 100; i++) longName.append('x');
        ask(host(household, true, asked), longName.toString());
        assertEquals(60, asked.name.get().length());
    }

    @Test
    public void aHelloNoTvWouldSendIsRefusedBeforeItIsParsed() throws Exception {
        // Anyone on the network can send a hello. Android's JSON parser recurses, so 60,000 nested brackets (well
        // within a hello's 64 KB) overflow the thread's stack there and take Hearth down; this JVM's parser copes, so
        // the test checks the bound that keeps them from being parsed at all, with JSON that is otherwise fine.
        StringBuilder pad = new StringBuilder();
        for (int i = 0; i < 2_000; i++) pad.append('x');
        String[] hellos = {"{\"name\":\"Kitchen\",\"x\":\"" + pad + "\"}", "{\"name\":\"Kitchen\",\"x\":" + "[".repeat(60_000)};
        for (String text : hellos) {
            HouseholdTvs.Tv household = new HouseholdTvs.Tv();
            household.store.create("Office", T0);
            Asked asked = new Asked();
            ExecutorService pool = Executors.newFixedThreadPool(2);
            try (ServerSocket server = new ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())) {
                server.setSoTimeout(5000);
                Future<Boolean> serving = pool.submit(() -> {
                    try (Socket socket = server.accept()) {
                        socket.setSoTimeout(5000);
                        DataInputStream in = new DataInputStream(socket.getInputStream());
                        in.readFully(new byte[4]);
                        return HouseholdJoin.serve(in, socket.getOutputStream(), host(household, true, asked));
                    }
                });
                // The asking side, as a TV would be but for its hello: the key exchange follows
                pool.submit(() -> {
                    try (Socket socket = new Socket(java.net.InetAddress.getLoopbackAddress(), server.getLocalPort())) {
                        socket.setSoTimeout(5000);
                        java.io.DataOutputStream out = new java.io.DataOutputStream(socket.getOutputStream());
                        out.write(HouseholdJoin.MAGIC);
                        out.writeUTF(text);
                        out.flush();
                        ShareSession.receiver(socket.getInputStream(), socket.getOutputStream()).handshake();
                    }
                    return null;
                });
                try {
                    serving.get(10, TimeUnit.SECONDS);
                    fail("expected a refusal");
                } catch (java.util.concurrent.ExecutionException expected) {
                    assertTrue(expected.getCause() instanceof ShareSession.ShareException);
                }
                // not a join request: no parent was asked
                assertNull(asked.name.get());
            } finally {
                pool.shutdownNow();
            }
        }
    }

    @Test
    public void theCandidatesAreTheTvsOfTheLargestOtherHouseholdThatCanBeReached() {
        List<HouseholdNet.Heard> heard = Arrays.asList(
                new HouseholdNet.Heard("tv-b", "h1", "Kitchen", "192.0.2.11", 4000),
                new HouseholdNet.Heard("tv-c", "h1", null, null, 0),
                new HouseholdNet.Heard("tv-d", "h1", "Attic", "192.0.2.12", 4000),
                new HouseholdNet.Heard("tv-e", "h2", "Office", "192.0.2.13", 4000),
                new HouseholdNet.Heard("tv-f", "mine", "Study", "192.0.2.14", 4000),
                new HouseholdNet.Heard("tv-g", "mine", "Study 2", "192.0.2.15", 4000),
                new HouseholdNet.Heard("tv-h", "mine", "Study 3", "192.0.2.16", 4000));
        List<HouseholdNet.Heard> candidates = HouseholdJoining.candidates(heard, "mine");
        assertEquals(2, candidates.size());
        assertEquals("tv-b", candidates.get(0).tvId);
        assertEquals("tv-d", candidates.get(1).tvId);
        assertTrue(HouseholdJoining.candidates(heard.subList(4, 7), "mine").isEmpty());
        assertEquals("123 456", HouseholdJoining.spaced("123456"));
        assertNotNull(HouseholdJoining.tokenName("Kitchen", new java.util.Date()));
        assertFalse(HouseholdJoining.tokenName("", new java.util.Date()).contains("null"));
        assertNull(HouseholdStore.Invitation.fromJson("{}"));
    }
}
