package com.thesiegs.hearth;

import android.content.Context;
import android.view.accessibility.AccessibilityNodeInfo;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Keeps other computers off the TV's debugging. Hearth keeps adbd listening on the network (SelfAdb), so anyone on the
 * home Wi-Fi can ask to connect, and a kid could press Allow on the TV's "Allow debugging?" prompt, then leave a kids
 * profile, turn Hearth's services off or script PIN guesses. Hearth's accessibility service answers that prompt Cancel
 * for any key but Hearth's own, unless a parent opened the door with the Parent PIN in the last two minutes
 * (Settings > Family > Allow a computer to connect). Hearth's own key is told by its fingerprint on the prompt, or, when the prompt
 * shows none, by Hearth connecting right then.
 */
final class AdbPromptGuard {
    /** How long a parent's "allow a computer" lasts. */
    static final long ALLOW_MS = 2 * 60_000;
    private static final String PREFS = "hearth_adb_guard";
    private static final String ALLOW_UNTIL = "allow_until";
    /** An RSA key fingerprint as Android shows it: 16 bytes in hex, colon separated. */
    private static final Pattern FINGERPRINT = Pattern.compile("(?:[0-9A-Fa-f]{2}:){15}[0-9A-Fa-f]{2}");

    enum Verdict { NOT_A_PROMPT, LEAVE, DISMISS }

    private static volatile long sOwnConnectAt;

    private AdbPromptGuard() {
    }

    /** Hearth is connecting to its own adbd now (SelfAdb.open): a prompt with no fingerprint shown is its own. */
    static void connecting() {
        sOwnConnectAt = System.currentTimeMillis();
    }

    /** Whether Hearth started connecting to its own adbd in the last {@link #ALLOW_MS}. */
    static boolean ownConnecting(long now) {
        long at = sOwnConnectAt;
        return at > 0 && now >= at && now - at < ALLOW_MS;
    }

    /** A parent entered the Parent PIN to let a computer connect: the prompt is left alone for {@link #ALLOW_MS}. */
    static void allow(Context context) {
        prefs(context).edit().putLong(ALLOW_UNTIL, System.currentTimeMillis() + ALLOW_MS).apply();
    }

    /** When a parent's allowing ends (0 or past: it doesn't). */
    static long allowedUntil(Context context) {
        long until = prefs(context).getLong(ALLOW_UNTIL, 0);
        // A clock set back never stretches it
        return Math.min(until, System.currentTimeMillis() + ALLOW_MS);
    }

    /**
     * What to do about a window: {@link Verdict#NOT_A_PROMPT} unless it's the debugging prompt (its words name
     * debugging and it shows a key fingerprint, or comes from System UI and names debugging); then LEAVE for Hearth's
     * own key or while a parent allows it, else DISMISS.
     */
    static Verdict judge(String packageName, String text, String ownFingerprint, boolean ownConnecting,
            boolean parentAllows) {
        if (text == null) return Verdict.NOT_A_PROMPT;
        String lower = text.toLowerCase(Locale.ROOT);
        if (!lower.contains("debugging")) return Verdict.NOT_A_PROMPT;
        // Only the system's own windows: an app that shows the words is never answered
        if (packageName == null || !(packageName.startsWith("com.android.") || packageName.startsWith("com.google.android.tv"))) {
            return Verdict.NOT_A_PROMPT;
        }
        Matcher shown = FINGERPRINT.matcher(text);
        boolean hasFingerprint = shown.find();
        boolean systemUi = "com.android.systemui".equals(packageName);
        if (!hasFingerprint && !(systemUi && lower.contains("allow"))) return Verdict.NOT_A_PROMPT;
        if (parentAllows) return Verdict.LEAVE;
        if (hasFingerprint) {
            return ownFingerprint != null && ownFingerprint.equalsIgnoreCase(shown.group()) ? Verdict.LEAVE
                    : Verdict.DISMISS;
        }
        return ownConnecting ? Verdict.LEAVE : Verdict.DISMISS;
    }

    /**
     * The fingerprint Android shows for a public key in adb's form ("base64 user@host"): MD5 of the decoded key,
     * upper-case hex pairs joined by colons; null when it isn't one.
     */
    static String fingerprintOf(String publicKey) {
        if (publicKey == null) return null;
        String[] parts = publicKey.trim().split("\\s+");
        if (parts.length == 0 || parts[0].isEmpty()) return null;
        try {
            byte[] key = java.util.Base64.getDecoder().decode(parts[0]);
            byte[] digest = MessageDigest.getInstance("MD5").digest(key);
            StringBuilder out = new StringBuilder();
            for (int i = 0; i < digest.length; i++) {
                if (i > 0) out.append(':');
                out.append(String.format(Locale.ROOT, "%02X", digest[i] & 0xff));
            }
            return out.toString();
        } catch (Exception e) {
            return null;
        }
    }

    /** Hearth's own key's fingerprint (SelfAdb's key), or null before it has one. */
    static String ownFingerprint(Context context) {
        File pub = new File(new File(context.getFilesDir(), "selfadb"), "adbkey.pub");
        if (!pub.exists()) return null;
        try {
            return fingerprintOf(new String(Files.readAllBytes(pub.toPath()), StandardCharsets.UTF_8));
        } catch (Exception e) {
            return null;
        }
    }

    /** All the words in a window, for {@link #judge}. */
    static String textOf(AccessibilityNodeInfo root) {
        StringBuilder out = new StringBuilder();
        collect(root, out, 0);
        return out.toString();
    }

    private static void collect(AccessibilityNodeInfo node, StringBuilder out, int depth) {
        if (node == null || depth > 30 || out.length() > 4000) return;
        if (node.getText() != null) out.append(node.getText()).append('\n');
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), out, depth + 1);
    }

    /** The prompt's Cancel (or "Don't allow") button, to answer it; null when none is found. */
    static AccessibilityNodeInfo cancelButton(AccessibilityNodeInfo root) {
        if (root == null) return null;
        List<AccessibilityNodeInfo> found = new ArrayList<>(root.findAccessibilityNodeInfosByViewId("android:id/button2"));
        for (String word : new String[]{"Cancel", "Deny", "Don't allow"}) {
            if (!found.isEmpty()) break;
            found.addAll(root.findAccessibilityNodeInfosByText(word));
        }
        for (AccessibilityNodeInfo node : found) {
            if (node.isClickable()) return node;
        }
        return null;
    }

    private static android.content.SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
