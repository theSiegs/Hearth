package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.junit.After;
import org.junit.Test;

/** A copy between two TVs as the screens drive it, on the loopback address with short timeouts. */
public class ShareServiceTest {
    private final List<ShareService> started = new ArrayList<>();

    @After
    public void tearDown() {
        for (ShareService service : started) service.close();
    }

    private static ShareService.Timeouts quick() {
        ShareService.Timeouts timeouts = new ShareService.Timeouts();
        timeouts.lifetimeMs = 20_000;
        timeouts.handshakeMs = 1500;
        timeouts.confirmMs = 4000;
        timeouts.transferMs = 4000;
        timeouts.applyMs = 4000;
        return timeouts;
    }

    private ShareService sender(String bundle) {
        ShareService service = ShareService.openSender(bundle, quick());
        assertNotNull("a port to listen on", service);
        started.add(service);
        return service;
    }

    private ShareService receiver(ShareService sender) {
        ShareService service = ShareService.openReceiver("127.0.0.1", sender.port(), quick());
        started.add(service);
        return service;
    }

    private static String state(ShareService service) {
        return (String) service.snapshot().get("state");
    }

    private static void waitFor(ShareService service, String state) throws InterruptedException {
        long end = System.currentTimeMillis() + 8000;
        while (System.currentTimeMillis() < end) {
            if (state.equals(state(service))) return;
            Thread.sleep(20);
        }
        fail("expected " + state + " but it is " + service.snapshot());
    }

    private static void bothShowDigits(ShareService a, ShareService b) throws InterruptedException {
        waitFor(a, ShareService.DIGITS);
        waitFor(b, ShareService.DIGITS);
        assertEquals(a.snapshot().get("digits"), b.snapshot().get("digits"));
        assertTrue(((String) a.snapshot().get("digits")).matches("[0-9]{6}"));
    }

    @Test
    public void aCopyGoesThroughAndTheReportComesBack() throws Exception {
        String bundle = "{\"format\":\"hearth-share\",\"pad\":\"" + "x".repeat(200_000) + "\"}";
        ShareService sending = sender(bundle);
        ShareService receiving = receiver(sending);
        bothShowDigits(sending, receiving);

        sending.answer(true);
        receiving.answer(true);
        waitFor(receiving, ShareService.RECEIVED);
        assertEquals(bundle, receiving.takeReceived());
        assertNull("only once", receiving.takeReceived());

        receiving.reportBack("{\"applied\":2}");
        waitFor(sending, ShareService.DONE);
        waitFor(receiving, ShareService.DONE);
        assertEquals("{\"applied\":2}", sending.snapshot().get("report"));
    }

    @Test
    public void theSecretsAreMadeOnlyAfterBothSayYesAndGoToTheReceiverAlone() throws Exception {
        java.util.concurrent.atomic.AtomicInteger made = new java.util.concurrent.atomic.AtomicInteger();
        ShareService sending = ShareService.openSender("bundle", () -> {
            made.incrementAndGet();
            return "{\"v\":1,\"haFailed\":true}";
        }, quick());
        started.add(sending);
        ShareService receiving = receiver(sending);
        bothShowDigits(sending, receiving);
        assertEquals("not before they said yes", 0, made.get());
        assertNull(receiving.receivedSecrets());

        sending.answer(true);
        receiving.answer(true);
        waitFor(receiving, ShareService.RECEIVED);
        assertEquals("{\"v\":1,\"haFailed\":true}", receiving.receivedSecrets());
        assertEquals(1, made.get());
        assertEquals("ha_failed", sending.snapshot().get("note"));

        receiving.reportBack("{}");
        waitFor(receiving, ShareService.DONE);
        assertNull("not kept afterwards", receiving.receivedSecrets());
    }

    @Test
    public void aSenderThatIsToldNoMakesNoSecrets() throws Exception {
        java.util.concurrent.atomic.AtomicInteger made = new java.util.concurrent.atomic.AtomicInteger();
        ShareService sending = ShareService.openSender("bundle", () -> {
            made.incrementAndGet();
            return "{}";
        }, quick());
        started.add(sending);
        ShareService receiving = receiver(sending);
        bothShowDigits(sending, receiving);
        sending.answer(false);
        receiving.answer(true);
        waitFor(receiving, ShareService.FAILED);
        assertEquals(0, made.get());
    }

    @Test
    public void theReceivingParentSayingNoStopsItAndTheSenderListensAgain() throws Exception {
        ShareService sending = sender("bundle-1");
        ShareService first = receiver(sending);
        bothShowDigits(sending, first);
        first.answer(false);
        sending.answer(true);
        waitFor(first, ShareService.FAILED);
        assertEquals("mismatch", first.snapshot().get("error"));
        waitFor(sending, ShareService.WAITING);
        assertEquals(1, sending.snapshot().get("mismatches"));

        // The right TV connects next
        ShareService second = receiver(sending);
        bothShowDigits(sending, second);
        sending.answer(true);
        second.answer(true);
        waitFor(second, ShareService.RECEIVED);
        assertEquals("bundle-1", second.takeReceived());
    }

    @Test
    public void theSendingParentSayingNoSendsNothing() throws Exception {
        ShareService sending = sender("secret-layout");
        ShareService receiving = receiver(sending);
        bothShowDigits(sending, receiving);
        sending.answer(false);
        receiving.answer(true);
        waitFor(receiving, ShareService.FAILED);
        assertEquals("peer_stopped", receiving.snapshot().get("error"));
        assertNull(receiving.takeReceived());
        waitFor(sending, ShareService.WAITING);
    }

    @Test
    public void aStrayConnectionIsDroppedAndTheRealOneStillWorks() throws Exception {
        ShareService sending = sender("bundle-2");
        // Something connects and says nothing, then something that sends junk
        Socket silent = new Socket(InetAddress.getLoopbackAddress(), sending.port());
        Socket junk = new Socket(InetAddress.getLoopbackAddress(), sending.port());
        junk.getOutputStream().write(new byte[]{9, 9, 0, 0, 0, 3, 1, 2, 3});
        junk.getOutputStream().flush();
        try {
            Thread.sleep(100);
            assertEquals(ShareService.WAITING, state(sending));
            ShareService receiving = receiver(sending);
            bothShowDigits(sending, receiving);
            sending.answer(true);
            receiving.answer(true);
            waitFor(receiving, ShareService.RECEIVED);
            assertEquals("bundle-2", receiving.takeReceived());
        } finally {
            silent.close();
            junk.close();
        }
    }

    @Test
    public void afterThreeRefusedAttemptsTheSenderGivesUp() throws Exception {
        ShareService sending = sender("bundle-3");
        for (int i = 0; i < ShareService.MAX_MISMATCHES; i++) {
            ShareService receiving = receiver(sending);
            waitFor(sending, ShareService.DIGITS);
            sending.answer(false);
            waitFor(receiving, ShareService.FAILED);
            if (i < ShareService.MAX_MISMATCHES - 1) waitFor(sending, ShareService.WAITING);
        }
        waitFor(sending, ShareService.FAILED);
        assertEquals("mismatch", sending.snapshot().get("error"));
    }

    @Test
    public void aTvThatIsNotOnTheHomeNetworkIsNotCalled() throws Exception {
        ShareService receiving = ShareService.openReceiver("8.8.8.8", 8770, quick());
        started.add(receiving);
        waitFor(receiving, ShareService.FAILED);
        assertEquals("not_local", receiving.snapshot().get("error"));
    }

    @Test
    public void nobodyListeningIsANetworkError() throws Exception {
        int free;
        try (ServerSocket probe = new ServerSocket(0)) {
            free = probe.getLocalPort();
        }
        ShareService receiving = ShareService.openReceiver("127.0.0.1", free, quick());
        started.add(receiving);
        waitFor(receiving, ShareService.FAILED);
        assertEquals("network", receiving.snapshot().get("error"));
    }

    @Test
    public void noAnswerFromTheParentIsARefusal() throws Exception {
        ShareService.Timeouts timeouts = quick();
        timeouts.confirmMs = 400;
        ShareService sending = ShareService.openSender("bundle-4", timeouts);
        started.add(sending);
        ShareService receiving = ShareService.openReceiver("127.0.0.1", sending.port(), timeouts);
        started.add(receiving);
        waitFor(receiving, ShareService.FAILED);
        assertEquals("mismatch", receiving.snapshot().get("error"));
        waitFor(sending, ShareService.WAITING);
    }

    @Test
    public void stoppingFreesThePortAndEndsTheCopy() throws Exception {
        ShareService sending = sender("bundle-5");
        int port = sending.port();
        sending.close();
        Thread.sleep(300);
        try (ServerSocket again = new ServerSocket(port)) {
            assertEquals(port, again.getLocalPort());
        } catch (IOException e) {
            fail("the port is still taken: " + e);
        }
    }

    @Test
    public void theStaticCallsFollowTheCurrentCopy() throws Exception {
        Map<String, Object> idle = ShareService.status();
        assertEquals("idle", idle.get("state"));
        Map<String, Object> started = ShareService.startSending("bundle-6");
        assertNotNull(started);
        try {
            assertEquals(ShareService.WAITING, ShareService.status().get("state"));
            assertEquals("sender", ShareService.status().get("role"));
            assertNull(ShareService.takeBundle());
        } finally {
            ShareService.stop();
        }
        assertEquals("idle", ShareService.status().get("state"));
    }
}
