package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.security.KeyPairGenerator;
import java.security.SecureRandom;
import java.security.interfaces.RSAPublicKey;
import java.util.List;

/** Pairing a phone the way the TV's own remote service does (docs/tv-remote-api.md "Pairing"). */
public class RemotePoloTest {
    private static RSAPublicKey key() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        return (RSAPublicKey) generator.generateKeyPair().getPublic();
    }

    private static RemoteWire.Writer outer() {
        return new RemoteWire.Writer().varint(1, 2).varint(2, 200);
    }

    private static RemoteWire.Writer hex6() {
        return new RemoteWire.Writer().varint(1, 3).varint(2, 6);
    }

    // What the phone sends, as Glint's Polo builds it
    private static byte[] request(String service) {
        return outer().message(10, new RemoteWire.Writer().string(1, service).string(2, "Alex's phone")).toByteArray();
    }

    private static byte[] options() {
        return outer().message(20, new RemoteWire.Writer().message(1, hex6()).varint(3, 1)).toByteArray();
    }

    private static byte[] configuration() {
        return outer().message(30, new RemoteWire.Writer().message(1, hex6()).varint(2, 1)).toByteArray();
    }

    private static byte[] secret(byte[] value) {
        return outer().message(40, new RemoteWire.Writer().bytes(1, value)).toByteArray();
    }

    private static int status(byte[] reply) throws Exception {
        return (int) RemoteWire.first(RemoteWire.read(reply), 2).value;
    }

    private static boolean has(byte[] reply, int field) throws Exception {
        return RemoteWire.first(RemoteWire.read(reply), field) != null;
    }

    private static byte[] hex(String s) {
        byte[] b = new byte[s.length() / 2];
        for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        return b;
    }

    @Test
    public void aPhoneThatTypesTheCodeIsPaired() throws Exception {
        RSAPublicKey phone = key();
        RSAPublicKey tv = key();
        RemotePolo polo = new RemotePolo(phone, tv, "the TV", new SecureRandom());

        RemotePolo.Step step = polo.handle(request("hearth-tv"));
        assertEquals(200, status(step.reply));
        RemoteWire.Field ack = RemoteWire.first(RemoteWire.read(step.reply), 11);
        assertEquals("the TV", RemoteWire.first(ack.fields(), 1).string());
        assertEquals("Alex's phone", polo.clientName());

        step = polo.handle(options());
        assertTrue(has(step.reply, 20));
        assertNull(step.showCode);

        step = polo.handle(configuration());
        assertTrue(has(step.reply, 31));
        String code = step.showCode;
        assertNotNull(code);
        assertTrue(code.matches("[0-9A-F]{6}"));

        // The phone computes the secret from the code, as Glint's PairingSecret does, and checks the first byte
        byte[] computed = RemotePolo.secret(phone, tv, hex(code.substring(2)));
        assertEquals(Integer.parseInt(code.substring(0, 2), 16), computed[0] & 0xFF);
        step = polo.handle(secret(computed));
        assertTrue(step.paired);
        assertTrue(step.close);
        RemoteWire.Field secretAck = RemoteWire.first(RemoteWire.read(step.reply), 41);
        assertArrayEquals(computed, RemoteWire.first(secretAck.fields(), 1).bytes);
    }

    @Test
    public void aWrongCodeIsRefusedWith402() throws Exception {
        RSAPublicKey phone = key();
        RSAPublicKey tv = key();
        RemotePolo polo = new RemotePolo(phone, tv, "the TV", new SecureRandom());
        polo.handle(request("atvremote")); // the TV's own service name is accepted too
        polo.handle(options());
        String code = polo.handle(configuration()).showCode;
        String wrong = code.substring(0, 2) + (code.substring(2).equals("0000") ? "0001" : "0000");

        RemotePolo.Step step = polo.handle(secret(RemotePolo.secret(phone, tv, hex(wrong.substring(2)))));
        assertFalse(step.paired);
        assertTrue(step.close);
        assertEquals(402, status(step.reply));
        // Nothing more is taken on this connection
        assertFalse(polo.handle(secret(RemotePolo.secret(phone, tv, hex(code.substring(2))))).paired);
    }

    @Test
    public void anotherServiceOrAnOutOfOrderMessageIsRefused() throws Exception {
        RemotePolo polo = new RemotePolo(key(), key(), "the TV", new SecureRandom());
        RemotePolo.Step step = polo.handle(request("something-else"));
        assertTrue(step.close);
        assertEquals(400, status(step.reply));

        polo = new RemotePolo(key(), key(), "the TV", new SecureRandom());
        step = polo.handle(configuration());
        assertTrue(step.close);
        assertNull(step.showCode);

        polo = new RemotePolo(key(), key(), "the TV", new SecureRandom());
        polo.handle(request("hearth-tv"));
        // Options without six hex digits
        byte[] fourDigits = outer().message(20, new RemoteWire.Writer()
                .message(1, new RemoteWire.Writer().varint(1, 3).varint(2, 4)).varint(3, 1)).toByteArray();
        assertEquals(401, status(polo.handle(fourDigits).reply));
    }

    @Test
    public void framesSurviveBeingReadOneByteAtATime() throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] big = new byte[300];
        RemoteWire.writeFrame(out, "{\"t\":\"hello\"}".getBytes("UTF-8"));
        RemoteWire.writeFrame(out, big);
        byte[] wire = out.toByteArray();
        assertEquals((byte) 0xAC, wire[14]); // 300 as a varint: AC 02
        InputStream slow = new ByteArrayInputStream(wire) {
            @Override
            public synchronized int read(byte[] b, int off, int len) {
                return super.read(b, off, Math.min(len, 1));
            }
        };
        assertEquals("{\"t\":\"hello\"}", new String(RemoteWire.readFrame(slow), "UTF-8"));
        assertEquals(300, RemoteWire.readFrame(slow).length);
        assertNull(RemoteWire.readFrame(slow));
    }

    @Test(expected = java.io.IOException.class)
    public void anOversizedFrameIsRefused() throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(new byte[]{(byte) 0x80, (byte) 0x80, 0x40});
        RemoteWire.readFrame(new ByteArrayInputStream(out.toByteArray()));
    }

    @Test
    public void readsNestedFields() throws Exception {
        byte[] message = outer().message(11, new RemoteWire.Writer().string(1, "x")).toByteArray();
        List<RemoteWire.Field> fields = RemoteWire.read(message);
        assertEquals(3, fields.size());
        assertEquals("x", RemoteWire.first(RemoteWire.first(fields, 11).fields(), 1).string());
    }
}
