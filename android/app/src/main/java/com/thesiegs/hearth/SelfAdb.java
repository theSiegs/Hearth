package com.thesiegs.hearth;

import android.content.Context;
import android.util.Log;

import java.io.File;

import dadb.AdbKeyPair;
import dadb.AdbShellResponse;
import dadb.Dadb;

/**
 * Hearth's own loopback adb connection: it lets Hearth run a few commands as the {@code shell} user on its OWN TV,
 * by being an adb client to the TV's own {@code adbd} on {@code 127.0.0.1:5555}. {@link ProfileAppAccess} uses this
 * to add/remove its own apps in kids' profiles, and {@link SetupFixes} to turn on Hearth's own switches. Nothing here
 * is a general back door: it runs only the specific commands those two build.
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
public final class SelfAdb implements ProfileAppAccess.ShellRunner, AutoCloseable {

    private static final String TAG = "HearthSelfAdb";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 5555;
    private static final String PREFS = "hearth_self_adb";
    /** A command has run over Hearth's key: the TV trusts it (the parent chose Allow on "Allow debugging?"). */
    private static final String TRUSTED = "trusted";

    private final Dadb dadb;
    private final Context context;
    private boolean ran;

    private SelfAdb(Dadb dadb, Context context) {
        this.dadb = dadb;
        this.context = context;
    }

    /**
     * Opens the loopback adb connection, creating Hearth's debugging key on first use (which triggers the one-time
     * on-screen "Allow debugging?" prompt the parent approves). Call from a background thread.
     */
    public static SelfAdb open(Context context) throws Exception {
        return open(context, 0);
    }

    /**
     * {@link #open(Context)}, giving up on any one read after {@code timeoutMs} (0: never). A key the TV doesn't trust
     * leaves the connection waiting on "Allow debugging?"; a read that times out ends that wait with a
     * {@link java.net.SocketTimeoutException}.
     */
    public static SelfAdb open(Context context, int timeoutMs) throws Exception {
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
        return new SelfAdb(Dadb.create(HOST, PORT, keyPair, timeoutMs, timeoutMs), context.getApplicationContext());
    }

    /**
     * Whether a command has run over Hearth's key before, so the TV trusts it and connecting won't ask "Allow
     * debugging?". It can be out of date: the parent chose Allow without Always allow and the TV restarted since, or
     * took the approval back in Developer options.
     */
    static boolean isTrusted(Context context) {
        return prefs(context).getBoolean(TRUSTED, false);
    }

    /** The TV didn't answer as one that trusts Hearth's key: no longer counted as trusted until a command runs again. */
    static void forgetTrusted(Context context) {
        prefs(context).edit().remove(TRUSTED).apply();
    }

    private static android.content.SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /**
     * Owner-Hearth's adb key material ({private, public} PEM), or null if it hasn't connected yet. Shared with the
     * profile agents over the loopback channel so that, if owner-Hearth is ever uninstalled, an agent can still use
     * this already-authorized key to clean up its profile (see AgentService). Loopback-only, so it never leaves the
     * device.
     */
    static String[] keyMaterial(Context context) {
        try {
            java.io.File dir = new java.io.File(context.getFilesDir(), "selfadb");
            java.io.File priv = new java.io.File(dir, "adbkey");
            java.io.File pub = new java.io.File(dir, "adbkey.pub");
            if (!priv.exists() || !pub.exists()) return null;
            return new String[]{readFile(priv), readFile(pub)};
        } catch (Exception e) {
            return null;
        }
    }

    private static String readFile(java.io.File f) throws Exception {
        try (java.io.FileInputStream in = new java.io.FileInputStream(f);
             java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return out.toString("UTF-8");
        }
    }

    @Override
    public String run(String command) throws Exception {
        AdbShellResponse response = dadb.shell(command);
        if (!ran) {
            ran = true;
            prefs(context).edit().putBoolean(TRUSTED, true).apply();
        }
        // Combined output; ProfileAppAccess only parses the helper's fixed "blockUninstall=" line and ignores the rest.
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
