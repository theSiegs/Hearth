package com.thesiegs.hearth;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * The wire pieces of the remote API (docs/tv-remote-api.md): varint-length framing (both ports), and the few protobuf
 * shapes the pairing messages need (polo, as the TV's own Android TV Remote service speaks it). Written by hand: no
 * protobuf runtime.
 */
final class RemoteWire {
    /** The largest frame either side accepts (the art reply is the biggest message). */
    static final int MAX_FRAME = 512 * 1024;

    private RemoteWire() {}

    // --- Framing: a varint length, then the message

    static void writeFrame(OutputStream out, byte[] message) throws IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream(message.length + 5);
        rawVarint(buf, message.length);
        buf.write(message);
        out.write(buf.toByteArray());
        out.flush();
    }

    /** The next frame, or null at a clean end of the stream before a frame starts. */
    static byte[] readFrame(InputStream in) throws IOException {
        long length = 0;
        int shift = 0;
        while (true) {
            int b = in.read();
            if (b < 0) {
                if (shift == 0) return null;
                throw new EOFException("cut off in a frame length");
            }
            length |= (long) (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
            if (shift > 28) throw new IOException("frame length too long");
        }
        if (length > MAX_FRAME) throw new IOException("frame too big: " + length);
        byte[] message = new byte[(int) length];
        int read = 0;
        while (read < message.length) {
            int n = in.read(message, read, message.length - read);
            if (n < 0) throw new EOFException("cut off in a frame");
            read += n;
        }
        return message;
    }

    // --- Protobuf

    static final class Writer {
        private final ByteArrayOutputStream out = new ByteArrayOutputStream();

        Writer varint(int field, long value) {
            rawVarint(out, (field << 3));
            rawVarint(out, value);
            return this;
        }

        Writer bytes(int field, byte[] value) {
            rawVarint(out, (field << 3) | 2);
            rawVarint(out, value.length);
            out.write(value, 0, value.length);
            return this;
        }

        Writer string(int field, String value) {
            return bytes(field, value.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        Writer message(int field, Writer inner) {
            return bytes(field, inner.toByteArray());
        }

        byte[] toByteArray() {
            return out.toByteArray();
        }
    }

    /** One field: a varint's value, or a length-delimited field's bytes. */
    static final class Field {
        final int number;
        final long value;
        final byte[] bytes;

        Field(int number, long value, byte[] bytes) {
            this.number = number;
            this.value = value;
            this.bytes = bytes;
        }

        String string() {
            return bytes == null ? "" : new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
        }

        List<Field> fields() throws IOException {
            return read(bytes == null ? new byte[0] : bytes);
        }
    }

    /** Every field of a message, in order; fixed-width fields are skipped. */
    static List<Field> read(byte[] data) throws IOException {
        List<Field> fields = new ArrayList<>();
        int[] pos = {0};
        while (pos[0] < data.length) {
            long key = varintAt(data, pos);
            int number = (int) (key >>> 3);
            int wire = (int) (key & 7);
            switch (wire) {
                case 0:
                    fields.add(new Field(number, varintAt(data, pos), null));
                    break;
                case 2: {
                    long length = varintAt(data, pos);
                    if (length < 0 || pos[0] + length > data.length) throw new IOException("bad field length");
                    byte[] b = new byte[(int) length];
                    System.arraycopy(data, pos[0], b, 0, b.length);
                    pos[0] += b.length;
                    fields.add(new Field(number, 0, b));
                    break;
                }
                case 1:
                    pos[0] += 8;
                    break;
                case 5:
                    pos[0] += 4;
                    break;
                default:
                    throw new IOException("unsupported wire type " + wire);
            }
            if (pos[0] > data.length) throw new IOException("cut off field");
        }
        return fields;
    }

    static Field first(List<Field> fields, int number) {
        for (Field f : fields) if (f.number == number) return f;
        return null;
    }

    private static long varintAt(byte[] data, int[] pos) throws IOException {
        long value = 0;
        int shift = 0;
        while (true) {
            if (pos[0] >= data.length) throw new IOException("cut off varint");
            int b = data[pos[0]++] & 0xFF;
            value |= (long) (b & 0x7F) << shift;
            if ((b & 0x80) == 0) return value;
            shift += 7;
            if (shift > 63) throw new IOException("varint too long");
        }
    }

    private static void rawVarint(ByteArrayOutputStream out, long value) {
        long v = value;
        while ((v & ~0x7FL) != 0) {
            out.write((int) ((v & 0x7F) | 0x80));
            v >>>= 7;
        }
        out.write((int) v);
    }
}
