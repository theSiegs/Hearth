package com.thesiegs.hearth;

/**
 * Whether a grown-up is at the remote: their profile came on (or they entered the parent PIN), and the remote hasn't
 * gone untouched for {@link #GAP_MS} since. While so, a grown-up's profile isn't asked for the parent PIN; after such
 * a gap someone else may have the remote, so it's asked again. Keys anywhere count (Hearth's accessibility service
 * sees them in every app). Kids' profiles always ask.
 */
final class ParentPresence {
    static final long GAP_MS = 5 * 60_000;

    private static long sLastKeyAt;
    private static boolean sPresent;

    private ParentPresence() {
    }

    /** A remote key (elapsed realtime). A gap of GAP_MS or more since the last one ends the grown-up's presence. */
    static synchronized void onKey(long now) {
        if (sLastKeyAt != 0 && now - sLastKeyAt >= GAP_MS) sPresent = false;
        sLastKeyAt = now;
    }

    /** A grown-up's profile came on, or the parent PIN was entered. */
    static synchronized void confirmed(long now) {
        sPresent = true;
        sLastKeyAt = now;
    }

    /** A kids' profile came on. */
    static synchronized void ended() {
        sPresent = false;
    }

    static synchronized boolean isPresent(long now) {
        return sPresent && now - sLastKeyAt < GAP_MS;
    }

    /** For tests. */
    static synchronized void reset() {
        sPresent = false;
        sLastKeyAt = 0;
    }
}
