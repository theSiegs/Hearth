package com.thesiegs.hearth;

import java.io.IOException;
import java.math.BigInteger;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.security.interfaces.RSAPublicKey;
import java.util.List;
import java.util.Locale;

/**
 * The TV's side of pairing a phone (docs/tv-remote-api.md "Pairing"): the polo exchange of the TV's own Android TV
 * Remote service, so a phone app reuses its pairing code. One instance per pairing connection.
 *
 * The phone sends pairing_request (10), options (20), configuration (30), secret (40); the TV answers
 * pairing_request_ack (11), its options (20), configuration_ack (31) — and shows the code then — and secret_ack (41).
 * The code is the secret's first byte as two hex digits, then a random 4-digit nonce; the secret is
 * SHA-256(client modulus ‖ client exponent ‖ server modulus ‖ server exponent ‖ nonce bytes).
 */
final class RemotePolo {
    static final int PROTOCOL_VERSION = 2;
    static final int STATUS_OK = 200;
    static final int STATUS_ERROR = 400;
    static final int STATUS_BAD_CONFIGURATION = 401;
    static final int STATUS_BAD_SECRET = 402;
    private static final int ENCODING_HEXADECIMAL = 3;
    private static final int CODE_LENGTH = 6;
    private static final int ROLE_INPUT = 1;
    /** The service names a phone may ask for. */
    static final String SERVICE = "hearth-tv";
    private static final String SERVICE_ANDROID_TV = "atvremote";

    /** What the connection should do after a message. */
    static final class Step {
        /** What to send back (null: nothing). */
        final byte[] reply;
        /** The code to show now (after configuration), else null. */
        final String showCode;
        /** The phone is paired. */
        final boolean paired;
        /** Close the connection after sending the reply. */
        final boolean close;

        Step(byte[] reply, String showCode, boolean paired, boolean close) {
            this.reply = reply;
            this.showCode = showCode;
            this.paired = paired;
            this.close = close;
        }
    }

    private enum Stage { REQUEST, OPTIONS, CONFIGURATION, SECRET, DONE }

    private final RSAPublicKey client;
    private final RSAPublicKey server;
    private final String serverName;
    private final SecureRandom random;
    private Stage stage = Stage.REQUEST;
    private String clientName;
    private byte[] expected;
    private String code;

    RemotePolo(RSAPublicKey client, RSAPublicKey server, String serverName, SecureRandom random) {
        this.client = client;
        this.server = server;
        this.serverName = serverName;
        this.random = random;
    }

    /** The name the phone gave in its pairing request. */
    String clientName() {
        return clientName;
    }

    String code() {
        return code;
    }

    Step handle(byte[] message) {
        List<RemoteWire.Field> fields;
        try {
            fields = RemoteWire.read(message);
        } catch (IOException e) {
            return refuse(STATUS_ERROR);
        }
        RemoteWire.Field status = RemoteWire.first(fields, 2);
        if (status != null && status.value != STATUS_OK) return new Step(null, null, false, true);
        try {
            switch (stage) {
                case REQUEST: {
                    RemoteWire.Field request = RemoteWire.first(fields, 10);
                    if (request == null) return refuse(STATUS_ERROR);
                    List<RemoteWire.Field> inner = request.fields();
                    RemoteWire.Field service = RemoteWire.first(inner, 1);
                    String name = service == null ? "" : service.string();
                    if (!SERVICE.equals(name) && !SERVICE_ANDROID_TV.equals(name)) return refuse(STATUS_ERROR);
                    RemoteWire.Field who = RemoteWire.first(inner, 2);
                    clientName = who == null || who.string().trim().isEmpty() ? "phone" : clean(who.string());
                    stage = Stage.OPTIONS;
                    return send(outer().message(11, new RemoteWire.Writer().string(1, serverName)));
                }
                case OPTIONS: {
                    RemoteWire.Field options = RemoteWire.first(fields, 20);
                    if (options == null || !offersHex6(options.fields())) return refuse(STATUS_BAD_CONFIGURATION);
                    stage = Stage.CONFIGURATION;
                    return send(outer().message(20, new RemoteWire.Writer()
                            .message(1, encoding())
                            .varint(3, ROLE_INPUT)));
                }
                case CONFIGURATION: {
                    RemoteWire.Field configuration = RemoteWire.first(fields, 30);
                    if (configuration == null || !offersHex6(configuration.fields())) {
                        return refuse(STATUS_BAD_CONFIGURATION);
                    }
                    makeCode();
                    stage = Stage.SECRET;
                    return new Step(outer().message(31, new RemoteWire.Writer()).toByteArray(), code, false, false);
                }
                case SECRET: {
                    RemoteWire.Field secret = RemoteWire.first(fields, 40);
                    RemoteWire.Field value = secret == null ? null : RemoteWire.first(secret.fields(), 1);
                    if (value == null || !MessageDigest.isEqual(expected, value.bytes)) return refuse(STATUS_BAD_SECRET);
                    stage = Stage.DONE;
                    return new Step(
                            outer().message(41, new RemoteWire.Writer().bytes(1, expected)).toByteArray(), null, true, true);
                }
                default:
                    return refuse(STATUS_ERROR);
            }
        } catch (IOException e) {
            return refuse(STATUS_ERROR);
        }
    }

    /** The secret for a nonce: both sides compute it from the two public keys. */
    static byte[] secret(RSAPublicKey client, RSAPublicKey server, byte[] nonce) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            for (BigInteger n : new BigInteger[]{
                    client.getModulus(), client.getPublicExponent(), server.getModulus(), server.getPublicExponent()}) {
                digest.update(unsigned(n));
            }
            digest.update(nonce);
            return digest.digest();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    static byte[] unsigned(BigInteger n) {
        byte[] b = n.toByteArray();
        if (b.length > 1 && b[0] == 0) {
            byte[] trimmed = new byte[b.length - 1];
            System.arraycopy(b, 1, trimmed, 0, trimmed.length);
            return trimmed;
        }
        return b;
    }

    private void makeCode() {
        byte[] nonce = new byte[2];
        random.nextBytes(nonce);
        expected = secret(client, server, nonce);
        code = String.format(Locale.ROOT, "%02X%02X%02X", expected[0] & 0xFF, nonce[0] & 0xFF, nonce[1] & 0xFF);
    }

    /** A message's input or output encodings offer six hex digits. */
    private static boolean offersHex6(List<RemoteWire.Field> fields) throws IOException {
        for (RemoteWire.Field f : fields) {
            if (f.number > 2 || f.bytes == null) continue;
            List<RemoteWire.Field> encoding = f.fields();
            RemoteWire.Field type = RemoteWire.first(encoding, 1);
            RemoteWire.Field length = RemoteWire.first(encoding, 2);
            if (type != null && type.value == ENCODING_HEXADECIMAL && length != null && length.value == CODE_LENGTH) {
                return true;
            }
        }
        return false;
    }

    private static RemoteWire.Writer encoding() {
        return new RemoteWire.Writer().varint(1, ENCODING_HEXADECIMAL).varint(2, CODE_LENGTH);
    }

    private static RemoteWire.Writer outer() {
        return new RemoteWire.Writer().varint(1, PROTOCOL_VERSION).varint(2, STATUS_OK);
    }

    private static Step send(RemoteWire.Writer message) {
        return new Step(message.toByteArray(), null, false, false);
    }

    private Step refuse(int status) {
        stage = Stage.DONE;
        byte[] reply = new RemoteWire.Writer().varint(1, PROTOCOL_VERSION).varint(2, status).toByteArray();
        return new Step(reply, null, false, true);
    }

    private static String clean(String name) {
        String s = name.replaceAll("[\\p{Cntrl}]", "").trim();
        return s.length() > 40 ? s.substring(0, 40) : s;
    }
}
