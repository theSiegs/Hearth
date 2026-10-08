package com.leanbitlab.ltvL;

import android.content.Context;
import android.util.Log;

import java.io.File;

import dadb.AdbKeyPair;
import dadb.AdbShellResponse;
import dadb.Dadb;

/**
 * Hearth's own loopback adb connection: it lets Hearth run a few commands as the {@code shell} user on its OWN TV,
 * by being an adb client to the TV's own {@code adbd} on {@code 127.0.0.1:5555}. {@link KidsAppAccess} uses this to
 * add/remove its own apps in kids profiles. Nothing here is a general back door — it runs only the specific,
 * parent-initiated commands in {@link KidsAppAccess}.
 *
 * <h3>The one-time consent</h3>
 * The first time Hearth connects with its key, the TV shows the system "Allow debugging?" prompt. The PARENT
 * approves it once (choosing "Always allow"). That approval is the gate: until it is given, none of the commands can
 * run. Hearth stores its key in its private files dir and reuses it, so the prompt appears only once.
 *
 * <h3>Status</h3>
 * This is the transport piece the app-integration session owns. The dadb calls below follow dadb's documented API;
 * the exact Kotlin/Java interop (static vs. {@code Companion}, {@code AdbKeyPair} factory names) must be confirmed
 * against the pinned dadb version when the app is first built, and the connection should target the persistent
 * wireless-debugging endpoint rather than cleartext 5555 if that is what survives a reboot (see
 * docs/kids-profile-installs.md). Kept isolated so finalizing it touches only this file.
 */
public final class SelfAdb implements KidsAppAccess.ShellRunner, AutoCloseable {

    private static final String TAG = "HearthSelfAdb";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 5555;

    private final Dadb dadb;

    private SelfAdb(Dadb dadb) {
        this.dadb = dadb;
    }

    /**
     * Opens the loopback adb connection, creating Hearth's debugging key on first use (which triggers the one-time
     * on-screen "Allow debugging?" prompt the parent approves). Call from a background thread.
     */
    public static SelfAdb open(Context context) throws Exception {
        File dir = new File(context.getFilesDir(), "selfadb");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("couldn't create key dir " + dir);
        }
        File privateKey = new File(dir, "adbkey");
        File publicKey = new File(dir, "adbkey.pub");
        // Generate Hearth's key once and reuse it, so the parent's "Always allow" sticks across runs.
        // NOTE: AdbKeyPair.generate/read and Dadb.create are Kotlin companion functions. If the pinned dadb build
        // does not mark them @JvmStatic, Java needs AdbKeyPair.Companion.generate(...)/read(...) and
        // Dadb.Companion.create(...). The first Gradle build will say which; adjust here only.
        if (!privateKey.exists() || !publicKey.exists()) {
            AdbKeyPair.generate(privateKey, publicKey);
        }
        AdbKeyPair keyPair = AdbKeyPair.read(privateKey, publicKey);
        Log.i(TAG, "connecting to " + HOST + ":" + PORT + " (first time raises the Allow-debugging prompt)");
        return new SelfAdb(Dadb.create(HOST, PORT, keyPair));
    }

    @Override
    public String run(String command) throws Exception {
        AdbShellResponse response = dadb.shell(command);
        // Combined output; KidsAppAccess only parses the helper's fixed "blockUninstall=" line and ignores the rest.
        return response.getAllOutput();
    }

    @Override
    public void close() {
        try {
            dadb.close();
        } catch (Exception e) {
            Log.w(TAG, "close failed: " + e);
        }
    }
}
