package com.thesiegs.hearth;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * A phrase a PIN recipe listens for in what an app says: plain lower-case text with at most three placeholders, matched
 * by hand (no regular expressions, so a recipe read from the network can't make one that runs away):
 * <ul>
 * <li>{@code {d}}: one digit 0-9;</li>
 * <li>{@code {n}}: one to three digits 0-9;</li>
 * <li>{@code {field}}: one to {@link #FIELD_MAX} characters other than a comma (a part of a comma-separated
 * announcement).</li>
 * </ul>
 * Placeholders must be separated by text, and at most one may be {@code {field}}. The first placeholder's value is
 * what the phrase captures; a phrase without one captures the whole text. Matching is on the app's words lower-cased
 * and trimmed, and like a regular expression's search: the leftmost place, each placeholder as long as it can be.
 */
final class PinTemplate {
    enum Mode { EQUALS, CONTAINS, STARTS_WITH }

    static final int MAX_LENGTH = 200;
    static final int FIELD_MAX = 200;
    /** Longer words are cut here before a phrase with placeholders is looked for (no app says this much at once). */
    static final int TEXT_MAX = 4000;

    private static final int LITERAL = 0, DIGIT = 1, NUMBER = 2, FIELD = 3;

    final Mode mode;
    final String source;
    private final int[] mKinds;
    private final String[] mLiterals;
    private final boolean mPlain;
    private final String mLongestLiteral;

    private PinTemplate(Mode mode, String source, int[] kinds, String[] literals) {
        this.mode = mode;
        this.source = source;
        mKinds = kinds;
        mLiterals = literals;
        boolean plain = true;
        String longest = "";
        for (int i = 0; i < kinds.length; i++) {
            if (kinds[i] != LITERAL) plain = false;
            else if (literals[i].length() > longest.length()) longest = literals[i];
        }
        mPlain = plain;
        mLongestLiteral = longest;
    }

    /** Reads a phrase; a bad one throws (IllegalArgumentException) with what's wrong, never the phrase itself. */
    static PinTemplate parse(Mode mode, String source) {
        if (source == null || source.isEmpty() || source.length() > MAX_LENGTH) {
            throw new IllegalArgumentException("a phrase must be 1-" + MAX_LENGTH + " characters");
        }
        if (!source.equals(source.toLowerCase(Locale.ROOT))) {
            throw new IllegalArgumentException("a phrase must be lower case (the app's words are lower-cased)");
        }
        List<Integer> kinds = new ArrayList<>();
        List<String> literals = new ArrayList<>();
        StringBuilder text = new StringBuilder();
        int placeholders = 0, fields = 0;
        for (int i = 0; i < source.length(); ) {
            char c = source.charAt(i);
            if (c == '}') throw new IllegalArgumentException("a '}' without its '{'");
            if (c != '{') {
                text.append(c);
                i++;
                continue;
            }
            int end = source.indexOf('}', i);
            if (end < 0) throw new IllegalArgumentException("a '{' without its '}'");
            String name = source.substring(i + 1, end);
            int kind = "d".equals(name) ? DIGIT : "n".equals(name) ? NUMBER : "field".equals(name) ? FIELD : -1;
            if (kind < 0) throw new IllegalArgumentException("unknown placeholder (only {d}, {n} and {field})");
            if (text.length() > 0) {
                kinds.add(LITERAL);
                literals.add(text.toString());
                text.setLength(0);
            } else if (!kinds.isEmpty()) {
                throw new IllegalArgumentException("placeholders must be separated by text");
            }
            kinds.add(kind);
            literals.add(null);
            placeholders++;
            if (kind == FIELD) fields++;
            i = end + 1;
        }
        if (text.length() > 0) {
            kinds.add(LITERAL);
            literals.add(text.toString());
        }
        if (placeholders > 3) throw new IllegalArgumentException("at most three placeholders");
        if (fields > 1) throw new IllegalArgumentException("at most one {field}");
        int[] k = new int[kinds.size()];
        for (int i = 0; i < k.length; i++) k[i] = kinds.get(i);
        return new PinTemplate(mode, source, k, literals.toArray(new String[0]));
    }

    boolean hasPlaceholder() {
        return !mPlain;
    }

    /** The first placeholder is {d} or {n}, so what it captures is a number. */
    boolean capturesNumber() {
        for (int kind : mKinds) {
            if (kind != LITERAL) return kind == DIGIT || kind == NUMBER;
        }
        return false;
    }

    /** The app's words as phrases see them: lower-cased and trimmed. */
    static String normalize(String text) {
        return text == null ? null : text.toLowerCase(Locale.ROOT).trim();
    }

    /** What the phrase captures in these (normalized) words, or null when it isn't there. */
    String match(String text) {
        if (text == null) return null;
        if (mPlain) {
            switch (mode) {
                case EQUALS:
                    return text.equals(source) ? text : null;
                case STARTS_WITH:
                    return text.startsWith(source) ? text : null;
                default:
                    return text.contains(source) ? text : null;
            }
        }
        if (text.length() > TEXT_MAX) text = text.substring(0, TEXT_MAX);
        if (!mLongestLiteral.isEmpty() && !text.contains(mLongestLiteral)) return null;
        String[] capture = new String[1];
        int lastStart = mode == Mode.CONTAINS ? text.length() : 0;
        for (int start = 0; start <= lastStart; start++) {
            capture[0] = null;
            if (matchAt(text, 0, start, capture)) return capture[0];
        }
        return null;
    }

    private boolean matchAt(String text, int token, int pos, String[] capture) {
        if (token == mKinds.length) return mode != Mode.EQUALS || pos == text.length();
        int kind = mKinds[token];
        if (kind == LITERAL) {
            return text.startsWith(mLiterals[token], pos) && matchAt(text, token + 1, pos + mLiterals[token].length(),
                    capture);
        }
        int max = kind == DIGIT ? 1 : kind == NUMBER ? 3 : FIELD_MAX;
        int run = 0;
        while (run < max && pos + run < text.length()) {
            char c = text.charAt(pos + run);
            boolean fits = kind == FIELD ? c != ',' : c >= '0' && c <= '9';
            if (!fits) break;
            run++;
        }
        for (int length = run; length >= 1; length--) {
            String before = capture[0];
            if (before == null) capture[0] = text.substring(pos, pos + length);
            if (matchAt(text, token + 1, pos + length, capture)) return true;
            capture[0] = before;
        }
        return false;
    }
}
