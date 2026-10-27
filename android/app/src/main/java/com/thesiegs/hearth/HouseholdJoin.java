package com.thesiegs.hearth;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;

/**
 * A TV asking a TV of a household to let it join (docs/household-sync.md, "Joining"), over any pair of streams. The new
 * TV connects to the household TV's sync port and says {@link #MAGIC}, its name and whether it wants the Home Assistant
 * settings. Then the two run ShareSession's key exchange (each commits to its key before seeing the other's), and both
 * show the same six digits: the new TV on its screen, the household TV in the request it puts in the Bell, for the
 * adult to compare. On Allow the household TV sends an invitation (HouseholdStore.Invitation) over the sealed session,
 * and the Home Assistant connection only when the adult also chose to give it; the new TV joins with it, and the first
 * sync then lists it. Deny, or no answer, ends it with nothing sent. Nothing secret moves before Allow, and no PIN is
 * ever sent.
 */
final class HouseholdJoin {
    static final byte[] MAGIC = {'H', 'H', 'J', '1'};
    static final int MAX_PAYLOAD = 64 * 1024;
    private static final int MAX_NAME = 60;
    /** The longest hello taken: {"name": a name of {@link #MAX_NAME}, escaped, "ha": a flag} fits several times over. */
    static final int MAX_HELLO_BYTES = 1024;

    /** The household TV's side: who decides, and what it gives. */
    interface Host {
        /**
         * Asks an adult whether the TV called {@code name}, showing {@code code}, may join; {@code wantsHa}: it has no
         * Home Assistant connection and asks for one (the host asks about that separately). Blocks.
         */
        boolean approve(String name, String code, boolean wantsHa) throws InterruptedException;

        /**
         * What the new TV gets once allowed ({"invitation": …, "ha": {url, token}}, the connection only when it asked
         * and the adult chose to give it); null when there's nothing.
         */
        String payload(String name, boolean wantsHa);
    }

    private HouseholdJoin() {
    }

    /**
     * Serves one request whose {@link #MAGIC} was already read. True when the new TV was allowed and got its
     * invitation.
     */
    static boolean serve(InputStream in, OutputStream out, Host host)
            throws IOException, GeneralSecurityException, InterruptedException {
        String name;
        boolean wantsHa;
        // Anyone on the network can send this, before any key exchange: a TV's hello is a name and a flag, so a longer
        // one isn't parsed (Android's JSON parser recurses, and deep nesting would overflow the thread's stack)
        DataInputStream data = new DataInputStream(in);
        int length = data.readUnsignedShort();
        if (length > MAX_HELLO_BYTES) throw new ShareSession.ShareException("Not a join request");
        byte[] utf = new byte[2 + length];
        utf[0] = (byte) (length >>> 8);
        utf[1] = (byte) length;
        data.readFully(utf, 2, length);
        try {
            JSONObject hello = new JSONObject(new DataInputStream(new java.io.ByteArrayInputStream(utf)).readUTF());
            name = tidy(hello.optString("name", ""));
            wantsHa = hello.optBoolean("ha");
        } catch (JSONException e) {
            throw new ShareSession.ShareException("Not a join request");
        }
        ShareSession session = ShareSession.sender(in, out);
        String code = session.handshake();
        if (!host.approve(name, code, wantsHa)) {
            refuse(session, in);
            return false;
        }
        // The new TV is still there before anything is made for it (a Home Assistant token, an invitation)
        session.confirm();
        String payload = host.payload(name, wantsHa);
        if (payload == null) {
            refuse(session, in);
            return false;
        }
        session.send(payload.getBytes(StandardCharsets.UTF_8));
        return true;
    }

    /**
     * Says no, then reads until the new TV hangs up, so the no reaches it before the connection closes (its own
     * confirmation, sent while it waited, would otherwise turn the close into a reset).
     */
    private static void refuse(ShareSession session, InputStream in) {
        session.abort();
        try {
            byte[] rest = new byte[256];
            for (int total = 0; total < MAX_PAYLOAD; ) {
                int n = in.read(rest);
                if (n < 0) return;
                total += n;
            }
        } catch (IOException ignored) {
        }
    }

    /** The new TV's side: {@link #start} gives the code to show, {@link #await} the household TV's answer. */
    static final class Request {
        private final InputStream in;
        private final OutputStream out;
        private ShareSession session;

        Request(InputStream in, OutputStream out) {
            this.in = in;
            this.out = out;
        }

        /** Says who this TV is and runs the key exchange; returns the six digits to show. */
        String start(String name, boolean wantsHa) throws IOException, GeneralSecurityException {
            DataOutputStream data = new DataOutputStream(out);
            data.write(MAGIC);
            try {
                data.writeUTF(new JSONObject().put("name", tidy(name)).put("ha", wantsHa).toString());
            } catch (JSONException e) {
                throw new IllegalStateException(e);
            }
            data.flush();
            session = ShareSession.receiver(in, out);
            return session.handshake();
        }

        /**
         * Waits for the parent's answer: the payload on Allow. Throws ShareSession.ShareException, {@code stopped}, on
         * Deny or no answer; any other IOException when the connection dropped, timed out or broke the protocol.
         */
        String await() throws IOException, GeneralSecurityException {
            session.confirm();
            return new String(session.receive(MAX_PAYLOAD), StandardCharsets.UTF_8);
        }
    }

    private static String tidy(String name) {
        String trimmed = ShareData.tidy(name == null ? "" : name);
        return trimmed.length() > MAX_NAME ? trimmed.substring(0, MAX_NAME) : trimmed;
    }
}
