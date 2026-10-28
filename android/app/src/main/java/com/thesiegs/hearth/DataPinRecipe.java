package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;

/**
 * A {@link PinRecipe} run from a {@link PinRecipeSpec}: one engine for every app, so a recipe can be fixed by data
 * (pin-entry/recipes.json) instead of a Hearth release. What it can do is all here and nothing more: click a digit
 * key (or, as a fallback, set the named PIN field to the digits so far), move the D-pad focus one key at a time and
 * press OK on a key confirmed to be the digit. It never logs a digit, a key label or what the app says.
 *
 * <p>Two ways of typing, as the apps need:
 * <ul>
 * <li><b>click</b>: the keypad's keys are nodes (Disney+, Paramount+, Google TV): each digit's key is clicked and the
 * digit confirmed by the click, or by the PIN field's count going up by one;</li>
 * <li><b>dpad</b>: the keypad can't be pressed through its nodes (Netflix, HBO Max, Apple TV): the focus moves with
 * D-pad actions, the focused key's label is read from what the app says or reports, and OK is pressed only once the
 * focused key is the digit. A move the app doesn't answer with a key label, or a label off the layout, stops the
 * entry before any OK.</li>
 * </ul>
 */
final class DataPinRecipe implements PinRecipe {
    static final long MOVE_WAIT_MS = 1_500;
    static final int MAX_MOVES = 10;
    private static final long MOVE_POLL_MS = 50;
    /** How far a tree walk for the keys goes up for a clickable key at most. */
    private static final int PARENT_LIMIT = 64;

    final PinRecipeSpec spec;
    private final PinNode.Ticker mTicker;

    // What the app said (speech rules) or reported (focus events)
    private final Set<String> mFlags = new HashSet<>();
    private PinEntryMachine.Outcome mHeard;
    private Integer mLastCount;
    private long mEchoAt = Long.MIN_VALUE;
    private String mFocused;
    private long mFocusedAt;

    /** Digits confirmed so far, and when the last one was. */
    private int mTyped;
    private long mLastDigitAt;
    /** The digits typed so far, kept only for a set-text fallback; wiped on close. */
    private final char[] mDigits;

    DataPinRecipe(PinRecipeSpec spec) {
        this(spec, new PinNode.MainTicker());
    }

    DataPinRecipe(PinRecipeSpec spec, PinNode.Ticker ticker) {
        this.spec = spec;
        mTicker = ticker;
        mDigits = new char[spec.pinLength];
    }

    @Override
    public String packageName() {
        return spec.pkg;
    }

    @Override
    public int pinLength() {
        return spec.pinLength;
    }

    @Override
    public long stepTimeoutMs() {
        return spec.stepTimeoutMs;
    }

    @Override
    public long outcomeTimeoutMs() {
        return spec.outcomeTimeoutMs;
    }

    int typed() {
        return mTyped;
    }

    // ---- What the app says and reports ----

    @Override
    public void onSpeech(String text) {
        String said = PinTemplate.normalize(text);
        if (said == null) return;
        for (PinRecipeSpec.SpeechRule rule : spec.speech) {
            String capture = null;
            boolean all = true;
            for (PinTemplate phrase : rule.when) {
                String got = phrase.match(said);
                if (got == null) {
                    all = false;
                    break;
                }
                if (capture == null && phrase.hasPlaceholder()) capture = got;
            }
            if (!all) continue;
            if (capture == null) capture = said;
            for (PinRecipeSpec.Effect effect : rule.effects) apply(effect, capture);
            if (rule.stop) return;
        }
    }

    private void apply(PinRecipeSpec.Effect effect, String capture) {
        switch (effect.kind) {
            case SET:
                mFlags.add(effect.flag);
                break;
            case FOCUS:
                keyFocused(capture.trim());
                break;
            case OUTCOME:
                mHeard = effect.outcome;
                break;
            case ECHO:
                mEchoAt = mTicker.now();
                break;
            case COUNT:
                try {
                    mLastCount = Integer.parseInt(capture.trim());
                } catch (NumberFormatException e) {
                    // Only {d}/{n} phrases count (checked when read), so this can't happen
                }
                break;
        }
    }

    @Override
    public void onEvent(AccessibilityEvent event) {
        if (spec.focusFromEvents == null) return;
        if (event.getEventType() != AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED
                && event.getEventType() != AccessibilityEvent.TYPE_VIEW_FOCUSED) {
            return;
        }
        AccessibilityNodeInfo source = event.getSource();
        if (source != null) onFocused(PinNode.Android.wrap(source));
    }

    /** The app reported focus on this node (a focus event). */
    void onFocused(PinNode node) {
        if (spec.focusFromEvents == null || node == null) return;
        String label = label(spec.focusFromEvents, node);
        if (label != null && !label.isEmpty()) keyFocused(label);
    }

    private void keyFocused(String label) {
        mFocused = label;
        mFocusedAt = mTicker.now();
    }

    // ---- The window ----

    /** "…, Keyboard, 1" or "1": the label after the last comma. */
    static String afterLastComma(CharSequence description) {
        if (description == null) return null;
        String d = description.toString();
        int comma = d.lastIndexOf(',');
        return (comma >= 0 ? d.substring(comma + 1) : d).trim();
    }

    private static String label(PinRecipeSpec.Label how, PinNode node) {
        switch (how) {
            case TEXT:
                return node.text() == null ? null : node.text().toString();
            case DESCRIPTION:
                return node.description() == null ? null : node.description().toString();
            default:
                return afterLastComma(node.description());
        }
    }

    private static boolean isDigit(String label) {
        return label != null && label.length() == 1 && label.charAt(0) >= '0' && label.charAt(0) <= '9';
    }

    /** The keypad found in a window: a key per digit (and per extra label), and whether it's whole. */
    static final class KeySet {
        final PinNode[] digits = new PinNode[10];
        final PinNode[] extra;
        boolean spoiled;

        KeySet(int extras) {
            extra = new PinNode[extras];
        }

        int found() {
            if (spoiled) return 0;
            int n = 0;
            for (PinNode key : digits) {
                if (key != null) n++;
            }
            for (PinNode key : extra) {
                if (key != null) n++;
            }
            return n;
        }

        boolean whole() {
            return !spoiled && found() == digits.length + extra.length;
        }
    }

    /** One look at the window: named nodes and the keypad, each found once. */
    private final class View {
        final PinNode root;
        private final Map<String, PinNode> mNodes = new HashMap<>();
        private KeySet mKeys;

        View(PinNode root) {
            this.root = root;
        }

        PinNode node(String name) {
            if (mNodes.containsKey(name)) return mNodes.get(name);
            List<PinNode> found = root.findById(spec.pkg + ":id/" + spec.nodes.get(name));
            PinNode node = found == null || found.isEmpty() ? null : found.get(0);
            mNodes.put(name, node);
            return node;
        }

        boolean inApp() {
            CharSequence pkg = root.packageName();
            return pkg != null && spec.pkg.contentEquals(pkg);
        }

        KeySet keys() {
            if (mKeys == null) mKeys = findKeys(this);
            return mKeys;
        }
    }

    private KeySet findKeys(View view) {
        PinRecipeSpec.Keys k = spec.keys;
        KeySet keys = new KeySet(k.extra.size());
        if (k.byId != null) {
            List<PinNode> nodes = view.root.findById(spec.pkg + ":id/" + k.byId);
            if (nodes != null) {
                for (PinNode node : nodes) {
                    consider(node, null, keys);
                    if (keys.spoiled) return keys;
                }
            }
        } else {
            PinNode scope = k.in != null ? view.node(k.in) : view.root;
            if (scope != null) walk(scope, k.in != null ? scope : null, keys, 0);
        }
        return keys;
    }

    private void walk(PinNode node, PinNode scope, KeySet keys, int depth) {
        if (node == null || depth > spec.keys.walkDepth || keys.spoiled) return;
        boolean key = scope == null || !node.sameAs(scope) ? consider(node, scope, keys) : false;
        if (key && spec.keys.stopAtKey) return;
        for (int i = 0; i < node.childCount(); i++) {
            walk(node.child(i), scope, keys, depth + 1);
            if (keys.spoiled) return;
        }
    }

    /** Takes the node as a key if it's labelled as one; true when its label is a digit (taken or not). */
    private boolean consider(PinNode node, PinNode scope, KeySet keys) {
        PinRecipeSpec.Keys k = spec.keys;
        if (k.onlyVisible && !node.isVisible()) return false;
        if (k.onlyClickable && !node.isClickable()) return false;
        String label = label(k.label, node);
        if (label == null) return false;
        PinNode[] slots;
        int slot;
        if (isDigit(label)) {
            slots = keys.digits;
            slot = label.charAt(0) - '0';
        } else {
            slot = k.extra.indexOf(label);
            if (slot < 0) return false;
            slots = keys.extra;
        }
        boolean digit = slots == keys.digits;
        if (digit && k.mustBeClickable && !node.isClickable()) {
            keys.spoiled = true;
            return true;
        }
        if (slots[slot] != null) {
            if (k.duplicates == PinRecipeSpec.Duplicates.FIRST) return digit;
            if (k.duplicates == PinRecipeSpec.Duplicates.FAIL) {
                keys.spoiled = true;
                return digit;
            }
        }
        PinNode press = node;
        if (k.pressAncestor) {
            PinNode up = node;
            for (int steps = 0; up != null && !up.isClickable() && steps < Math.min(k.maxUp, PARENT_LIMIT)
                    && !(scope != null && up.sameAs(scope)); steps++) {
                up = up.parent();
            }
            if (up != null && up.isClickable()) {
                press = up;
            } else if (!k.otherwiseSelf) {
                keys.spoiled = true;
                return digit;
            }
        }
        slots[slot] = press;
        return digit;
    }

    private boolean holds(PinRecipeSpec.Cond c, View view, int countBefore) {
        switch (c.kind) {
            case NODE:
                return view.node(c.name) != null;
            case NO_NODE:
                return view.node(c.name) == null;
            case NODE_SHOWS_TEXT: {
                PinNode node = view.node(c.name);
                return node != null && node.isVisible() && node.text() != null && node.text().length() > 0;
            }
            case TEXT: {
                List<PinNode> found = view.root.findByText(c.name);
                return found != null && !found.isEmpty();
            }
            case KEYS_ALL:
                return view.keys().whole();
            case KEYS_SOME: {
                KeySet keys = view.keys();
                return keys.found() > 0 && !keys.whole();
            }
            case KEYS_NOT_ALL:
                return !view.keys().whole();
            case IN_APP:
                return view.inApp();
            case NOT_IN_APP:
                return !view.inApp();
            case FLAG:
                return mFlags.contains(c.name);
            case NO_FLAG:
                return !mFlags.contains(c.name);
            case HEARD:
                return mHeard != null;
            case SINCE_LAST_DIGIT:
                return mTyped > 0 && mTicker.now() - mLastDigitAt >= c.ms;
            case COUNT_DROPPED:
                return countBefore >= 0 && count(view) < countBefore;
            default:
                return false;
        }
    }

    private boolean allHold(List<PinRecipeSpec.Cond> conds, View view, int countBefore) {
        for (PinRecipeSpec.Cond c : conds) {
            if (!holds(c, view, countBefore)) return false;
        }
        return true;
    }

    private PinRecipeSpec.Is first(List<PinRecipeSpec.Rule> rules, View view) {
        for (PinRecipeSpec.Rule rule : rules) {
            if (allHold(rule.when, view, -1)) return rule.is;
        }
        return null;
    }

    /** How many digits the PIN field shows. */
    private int count(View view) {
        PinNode field = view.node(spec.countNode);
        if (field == null) return 0;
        if (spec.countAs == PinRecipeSpec.CountAs.DOTS) return ContentPin.typedCount(field.text(), field.isShowingHint());
        return field.text() == null ? 0 : field.text().length();
    }

    @Override
    public PinEntryMachine.Screen recognize(AccessibilityNodeInfo root) {
        return recognize(PinNode.Android.wrap(root));
    }

    PinEntryMachine.Screen recognize(PinNode root) {
        View view = root != null ? new View(root) : null;
        if (view == null && needsWindow(spec.screen)) return null;
        PinRecipeSpec.Is is = first(spec.screen, view);
        if (is == null) return null;
        switch (is) {
            case MATCH:
                return PinEntryMachine.Screen.MATCH;
            case CHANGED:
                return PinEntryMachine.Screen.CHANGED;
            default:
                return PinEntryMachine.Screen.LOCKED_OUT;
        }
    }

    @Override
    public PinEntryMachine.Outcome outcome(AccessibilityNodeInfo root) {
        return outcome(PinNode.Android.wrap(root));
    }

    /** Asked once every digit is in (Profile Pairing asks no sooner). */
    PinEntryMachine.Outcome outcome(PinNode root) {
        View view = root != null ? new View(root) : null;
        if (view == null && needsWindow(spec.outcome)) return null;
        PinRecipeSpec.Is is = first(spec.outcome, view);
        if (is == null) return null;
        switch (is) {
            case ACCEPTED:
                return PinEntryMachine.Outcome.ACCEPTED;
            case REJECTED:
                return PinEntryMachine.Outcome.REJECTED;
            case LOCKED_OUT:
                return PinEntryMachine.Outcome.LOCKED_OUT;
            default:
                return mHeard;
        }
    }

    /** Whether any of these rules looks at the window (speech-only recipes are asked without one in tests). */
    private static boolean needsWindow(List<PinRecipeSpec.Rule> rules) {
        for (PinRecipeSpec.Rule rule : rules) {
            for (PinRecipeSpec.Cond c : rule.when) {
                switch (c.kind) {
                    case FLAG:
                    case NO_FLAG:
                    case HEARD:
                    case SINCE_LAST_DIGIT:
                        break;
                    default:
                        return true;
                }
            }
        }
        return false;
    }

    // ---- Typing ----

    @Override
    public void type(AccessibilityService service, AccessibilityNodeInfo root, char digit,
            Consumer<Boolean> confirmed) {
        type(new PinNode.ServiceHost(service), PinNode.Android.wrap(root), digit, confirmed);
    }

    void type(PinNode.Host host, PinNode root, char digit, Consumer<Boolean> confirmed) {
        if (digit < '0' || digit > '9' || mTyped >= spec.pinLength) {
            confirmed.accept(false);
            return;
        }
        if (spec.typing == PinRecipeSpec.Typing.DPAD) {
            if (!host.canMoveFocus()) {
                confirmed.accept(false);
                return;
            }
            step(host, digit, 0, confirmed);
            return;
        }
        View view = root != null ? new View(root) : null;
        // Keys are only ever pressed in the recipe's own app, on a whole keypad
        KeySet keys = view != null && view.inApp() ? view.keys() : null;
        if (keys == null || !keys.whole()) {
            confirmed.accept(false);
            return;
        }
        boolean last = mTyped + 1 == spec.pinLength;
        int before = spec.confirm == PinRecipeSpec.Confirm.COUNT ? count(view) : -1;
        mDigits[mTyped] = digit;
        boolean sent = keys.digits[digit - '0'].click();
        if (!sent && spec.setTextField != null) {
            PinNode field = view.node(spec.setTextField);
            char[] digits = Arrays.copyOf(mDigits, mTyped + 1);
            try {
                sent = field != null && field.setText(digits);
            } finally {
                Arrays.fill(digits, '\0');
            }
        }
        if (!sent) {
            confirmed.accept(false);
            return;
        }
        if (spec.confirm == PinRecipeSpec.Confirm.CLICK) {
            digitIn(confirmed);
            return;
        }
        long until = mTicker.now() + spec.waitMs;
        Runnable check = new Runnable() {
            @Override
            public void run() {
                PinNode now = host.root();
                View after = now != null ? new View(now) : null;
                // One more digit; or, after the last one, the app already answered in one of the recipe's ways
                boolean in = after != null && after.inApp()
                        && (count(after) == before + 1 || (last && anyHolds(spec.orOnLastDigit, after, before)));
                if (in) {
                    digitIn(confirmed);
                } else if (mTicker.now() >= until) {
                    confirmed.accept(false);
                } else {
                    mTicker.later(this, spec.pollMs);
                }
            }
        };
        mTicker.later(check, spec.pollMs);
    }

    private boolean anyHolds(List<List<PinRecipeSpec.Cond>> ways, View view, int countBefore) {
        for (List<PinRecipeSpec.Cond> way : ways) {
            if (allHold(way, view, countBefore)) return true;
        }
        return false;
    }

    private void digitIn(Consumer<Boolean> confirmed) {
        mTyped++;
        mLastDigitAt = mTicker.now();
        confirmed.accept(true);
    }

    private void step(PinNode.Host host, char digit, int moves, Consumer<Boolean> confirmed) {
        String focused = mFocused;
        if (!isDigit(focused)) {
            confirmed.accept(false);
            return;
        }
        if (focused.charAt(0) == digit) {
            host.press(PinNode.Host.CENTER);
            awaitPress(confirmed);
            return;
        }
        if (moves >= MAX_MOVES) {
            confirmed.accept(false);
            return;
        }
        int move = nextMove(spec.position(focused.charAt(0)), spec.position(digit), spec.lastRow());
        long movedAt = mTicker.now();
        mFocused = null;
        host.press(move);
        Runnable wait = new Runnable() {
            @Override
            public void run() {
                if (mFocused != null && mFocusedAt >= movedAt) {
                    step(host, digit, moves + 1, confirmed);
                } else if (mTicker.now() - movedAt >= MOVE_WAIT_MS) {
                    confirmed.accept(false);
                } else {
                    mTicker.later(this, MOVE_POLL_MS);
                }
            }
        };
        mTicker.later(wait, MOVE_POLL_MS);
    }

    /** After OK on a key: the digit is in once the app shows it the recipe's way. */
    private void awaitPress(Consumer<Boolean> confirmed) {
        if (spec.confirm == PinRecipeSpec.Confirm.SETTLE) {
            // The app says nothing per digit (Netflix): its answer after the last one is what counts
            mTicker.later(() -> digitIn(confirmed), spec.settleMs);
            return;
        }
        int expected = mTyped + 1;
        boolean last = expected == spec.pinLength;
        long since = mTicker.now();
        Runnable check = new Runnable() {
            @Override
            public void run() {
                boolean in;
                if (spec.confirm == PinRecipeSpec.Confirm.SPOKEN_COUNT) {
                    in = mLastCount != null && mLastCount == expected;
                } else {
                    // An echo of the digit; the last digit sends the PIN at once, so the app's answer counts too
                    in = mEchoAt >= since || (last && !spec.orOnLastDigit.isEmpty()
                            && anyHolds(spec.orOnLastDigit, null, -1));
                }
                if (in) {
                    digitIn(confirmed);
                } else if (mTicker.now() - since >= spec.waitMs) {
                    confirmed.accept(false);
                } else {
                    mTicker.later(this, spec.pollMs);
                }
            }
        };
        mTicker.later(check, spec.pollMs);
    }

    /**
     * One move from the key at {@code from} toward {@code to} ({row, column}; never equal): rows first, except into
     * the last row (0's row, with gaps or wide keys beside it), where the column is lined up first.
     */
    static int nextMove(int[] from, int[] to, int lastRow) {
        boolean intoLastRow = to[0] > from[0] && to[0] == lastRow;
        if ((intoLastRow || from[0] == to[0]) && from[1] != to[1]) {
            return to[1] > from[1] ? PinNode.Host.RIGHT : PinNode.Host.LEFT;
        }
        return to[0] > from[0] ? PinNode.Host.DOWN : PinNode.Host.UP;
    }

    @Override
    public void close() {
        Arrays.fill(mDigits, '\0');
        mTicker.cancel();
    }
}
