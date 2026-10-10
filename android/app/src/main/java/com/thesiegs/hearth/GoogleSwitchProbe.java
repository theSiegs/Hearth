package com.thesiegs.hearth;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Debug;
import android.util.Log;
import android.view.accessibility.AccessibilityNodeInfo;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * What Google TV says about a profile switch, read for the log only (it doesn't change what Hearth does yet).
 * Grown-up profiles share Android user 0: Google TV switches the active Google account inside it, which no user
 * start shows. Google TV records each switch it makes ("homeroot.profileSwitch" in its own dump, readable with the
 * DUMP permission, granted over adb), and its home names the active account on the profile picture ("Logged in as
 * Alex, click to choose an account"). Together: whether a switch happened and to whom.
 */
final class GoogleSwitchProbe {
    static final String TAG = "HearthSwitch";

    /** A switch Google TV recorded: "10-09 20:04:03.271 homeroot.profileSwitch". */
    private static final Pattern SWITCH = Pattern.compile("(\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d\\.\\d{3}) homeroot\\.profileSwitch");
    /** The home's profile picture, as Google TV labels it for screen readers (English). */
    private static final Pattern LOGGED_IN = Pattern.compile("Logged in as (.+?), click to choose an account");

    private GoogleSwitchProbe() {
    }

    static boolean canReadSwitches(Context context) {
        return context.checkSelfPermission(android.Manifest.permission.DUMP) == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * When Google TV last switched profile ("MM-dd HH:mm:ss.SSS", the TV's clock), from its own dump; null without
     * the DUMP permission or before any switch it still remembers. Slow (a few hundred ms): off the main thread.
     */
    static String latestSwitch(Context context) {
        if (!canReadSwitches(context)) return null;
        File dump = new File(context.getCacheDir(), "google_tv_dump.txt");
        try {
            try (FileOutputStream out = new FileOutputStream(dump)) {
                if (!Debug.dumpService("activity", out.getFD(),
                        new String[]{"service", LauncherAccessibilityService.GOOGLE_TV_PACKAGE})) {
                    return null;
                }
            }
            // Its log isn't strictly in order: the latest is the largest time (same year)
            String latest = null;
            try (BufferedReader in = new BufferedReader(new FileReader(dump))) {
                for (String line; (line = in.readLine()) != null; ) {
                    Matcher m = SWITCH.matcher(line);
                    if (m.find() && (latest == null || m.group(1).compareTo(latest) > 0)) latest = m.group(1);
                }
            }
            return latest;
        } catch (Exception e) {
            Log.w(TAG, "Couldn't read Google TV's dump", e);
            return null;
        } finally {
            //noinspection ResultOfMethodCallIgnored
            dump.delete();
        }
    }

    /** The account Google TV's home names on its profile picture, or null when it isn't showing. */
    static String homeAccount(AccessibilityNodeInfo root) {
        if (root == null) return null;
        Deque<AccessibilityNodeInfo> nodes = new ArrayDeque<>();
        nodes.add(root);
        int visited = 0;
        while (!nodes.isEmpty() && visited++ < 600) {
            AccessibilityNodeInfo node = nodes.poll();
            CharSequence description = node.getContentDescription();
            if (description != null) {
                Matcher m = LOGGED_IN.matcher(description);
                if (m.find()) return m.group(1).trim();
            }
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo child = node.getChild(i);
                if (child != null) nodes.add(child);
            }
        }
        return null;
    }
}
