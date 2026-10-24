package com.thesiegs.hearth;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.security.GeneralSecurityException;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * The wallpaper pictures the household's entries name (docs/household-sync.md, "Look and layout"): a wallpaper entry
 * carries a picture's SHA-256, and the picture itself is kept here once, as a file named by that hash, and moves only
 * to a TV that lacks it (HouseholdSync). Only a JPEG of at most {@link #MAX_BYTES} whose bytes match its name is ever
 * written, so a name from another TV can't point anywhere else.
 */
final class HouseholdPictures {
    /** A wallpaper picture as the screen shows it: a JPEG of at most 1920x1080 (the same limit as a copy's). */
    static final int MAX_BYTES = 3 * 1024 * 1024;
    private static final Pattern HASH = Pattern.compile("[0-9a-f]{64}");

    private final File dir;

    HouseholdPictures(File dir) {
        this.dir = dir;
    }

    /** A picture's name: its SHA-256 in hex. */
    static String hashOf(byte[] jpeg) {
        try {
            return HouseholdSeal.hex(ShareCrypto.sha256(jpeg), 32);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    static boolean validHash(String hash) {
        return hash != null && HASH.matcher(hash).matches();
    }

    /** Whether {@code bytes} could be a wallpaper picture: a JPEG, not too big. */
    static boolean isPicture(byte[] bytes) {
        return bytes != null && bytes.length >= 4 && bytes.length <= MAX_BYTES && (bytes[0] & 0xFF) == 0xFF
                && (bytes[1] & 0xFF) == 0xD8 && (bytes[2] & 0xFF) == 0xFF;
    }

    /** Where the picture named {@code hash} is (it may not be there); null for a name that isn't a hash. */
    File file(String hash) {
        return validHash(hash) ? new File(dir, hash + ".jpg") : null;
    }

    boolean has(String hash) {
        File file = file(hash);
        return file != null && file.isFile();
    }

    /** The picture's bytes, or null when it isn't here. */
    byte[] read(String hash) {
        File file = file(hash);
        if (file == null || !file.isFile() || file.length() > MAX_BYTES) return null;
        try {
            return Files.readAllBytes(file.toPath());
        } catch (IOException e) {
            return null;
        }
    }

    /**
     * Keeps a picture; returns its hash, or null when it isn't one or doesn't match {@code expected} (null: any).
     */
    String write(byte[] bytes, String expected) {
        if (!isPicture(bytes)) return null;
        String hash = hashOf(bytes);
        if (expected != null && !expected.equals(hash)) return null;
        if (has(hash)) return hash;
        if (!dir.isDirectory() && !dir.mkdirs()) return null;
        File temp = new File(dir, hash + ".tmp");
        try (FileOutputStream out = new FileOutputStream(temp)) {
            out.write(bytes);
            out.getFD().sync();
        } catch (IOException e) {
            temp.delete();
            return null;
        }
        return temp.renameTo(file(hash)) ? hash : null;
    }

    /** Deletes the pictures no entry names any more. */
    void keepOnly(Set<String> hashes) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File file : files) {
            String name = file.getName();
            String hash = name.endsWith(".jpg") ? name.substring(0, name.length() - 4) : null;
            if (hash == null || !hashes.contains(hash)) file.delete();
        }
    }

    /** Deletes every picture (the household was left). */
    void clear() {
        File[] files = dir.listFiles();
        if (files != null) for (File file : files) file.delete();
    }
}
